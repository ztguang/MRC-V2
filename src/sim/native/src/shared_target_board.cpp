#include "shared_target_board.hpp"

#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

namespace sp_sim {
namespace {

constexpr double kMinDistance = 0.15;  // meters; avoid 1/d blow-up

double score_of(
  double confidence, double distance_m, double age_sec,
  double alpha, double beta, double gamma, double lambda)
{
  const double c = std::clamp(confidence, 0.0, 1.0);
  const double d = std::max(distance_m, kMinDistance);
  const double freshness = std::exp(-lambda * std::max(0.0, age_sec));
  return alpha * c + beta / d + gamma * freshness;
}

void aim_from_godot_delta(double dx, double dy, double dz, double &yaw, double &pitch)
{
  // Godot look: camera forward is -Z. World yaw around +Y, pitch about local X.
  yaw = std::atan2(-dx, -dz);
  const double horizontal = std::sqrt(dx * dx + dz * dz);
  // Planner pitch is positive downward (see engine scope notes); match that sign.
  pitch = std::atan2(-dy, std::max(horizontal, 1e-6));
}

}  // namespace

SharedTargetBoard &SharedTargetBoard::instance()
{
  static SharedTargetBoard board;
  return board;
}

void SharedTargetBoard::publish(const SharedObservation &obs)
{
  if (obs.robot_id < 0 || obs.robot_id >= SP_MAX_ROBOTS) return;
  std::lock_guard lock(mutex_);
  slots_[static_cast<std::size_t>(obs.robot_id)] = obs;
}

SharedObservation SharedTargetBoard::get(int robot_id) const
{
  if (robot_id < 0 || robot_id >= SP_MAX_ROBOTS) return {};
  std::lock_guard lock(mutex_);
  return slots_[static_cast<std::size_t>(robot_id)];
}

FusionOutput SharedTargetBoard::fuse(
  int robot_id, int team, float self_x, float self_y, float self_z,
  int64_t now_usec, bool has_local, float local_tx, float local_ty, float local_tz,
  float local_confidence) const
{
  FusionOutput out;
  struct Candidate {
    float tx, ty, tz;
    double confidence;
    double distance;
    double age_sec;
    bool is_self;
  };
  std::vector<Candidate> candidates;
  candidates.reserve(SP_MAX_ROBOTS);

  if (has_local) {
    const double dx = local_tx - self_x;
    const double dy = local_ty - self_y;
    const double dz = local_tz - self_z;
    candidates.push_back(Candidate{
      local_tx, local_ty, local_tz,
      std::clamp(static_cast<double>(local_confidence), 0.05, 1.0),
      std::sqrt(dx * dx + dy * dy + dz * dz),
      0.0,
      true});
  }

  {
    std::lock_guard lock(mutex_);
    for (const auto &slot : slots_) {
      if (!slot.valid) continue;
      if (slot.team != team) continue;
      if (slot.robot_id == robot_id) continue;
      const int64_t age = now_usec - slot.timestamp_usec;
      if (age < 0 || age > kMaxAgeUsec) continue;
      // Distance of THIS observer to neighbor-reported target (paper beta/d).
      const double dx = slot.target_x - self_x;
      const double dy = slot.target_y - self_y;
      const double dz = slot.target_z - self_z;
      const double distance = std::sqrt(dx * dx + dy * dy + dz * dz);
      candidates.push_back(Candidate{
        slot.target_x, slot.target_y, slot.target_z,
        std::clamp(static_cast<double>(slot.confidence), 0.05, 1.0),
        distance,
        age / 1e6,
        false});
    }
  }

  if (candidates.empty()) return out;

  std::vector<double> scores;
  scores.reserve(candidates.size());
  double max_score = -1e300;
  for (const auto &c : candidates) {
    const double s = score_of(
      c.confidence, c.distance, c.age_sec, out.alpha, out.beta, out.gamma, out.lambda);
    scores.push_back(s);
    max_score = std::max(max_score, s);
  }

  double sum_exp = 0.0;
  for (double &s : scores) {
    s = std::exp(s - max_score);
    sum_exp += s;
  }
  if (sum_exp <= 0.0) return out;

  double fx = 0.0, fy = 0.0, fz = 0.0, fc = 0.0;
  int neighbors = 0;
  for (std::size_t i = 0; i < candidates.size(); ++i) {
    const double w = scores[i] / sum_exp;
    fx += w * candidates[i].tx;
    fy += w * candidates[i].ty;
    fz += w * candidates[i].tz;
    fc += w * candidates[i].confidence;
    if (!candidates[i].is_self) ++neighbors;
  }

  out.valid = true;
  out.used_neighbors = neighbors > 0;
  out.source_count = static_cast<int32_t>(candidates.size());
  out.neighbor_count = neighbors;
  out.fused_x = static_cast<float>(fx);
  out.fused_y = static_cast<float>(fy);
  out.fused_z = static_cast<float>(fz);
  out.fused_confidence = static_cast<float>(std::clamp(fc, 0.0, 1.0));
  aim_from_godot_delta(fx - self_x, fy - self_y, fz - self_z, out.aim_yaw_rad, out.aim_pitch_rad);
  return out;
}

void apply_fusion_to_result(
  SpEngineResult *result, const FusionOutput &fusion, bool enable_assist)
{
  if (result == nullptr) return;
  // Revision protocol owns fusion in Godot. Do not inject aim from this board.
  if (const char *flag = std::getenv("SIM_EXP_PROTOCOL")) {
    if (flag[0] == '1') {
      result->fusion_valid = 0;
      result->fusion_used_neighbors = 0;
      result->fusion_source_count = 0;
      result->fusion_neighbor_count = 0;
      result->fusion_confidence = 0.f;
      return;
    }
  }
  result->fusion_valid = fusion.valid ? 1 : 0;
  result->fusion_used_neighbors = fusion.used_neighbors ? 1 : 0;
  result->fusion_source_count = fusion.source_count;
  result->fusion_neighbor_count = fusion.neighbor_count;
  result->fusion_confidence = fusion.fused_confidence;
  if (!fusion.valid) return;

  result->fused_x = fusion.fused_x;
  result->fused_y = fusion.fused_y;
  result->fused_z = fusion.fused_z;

  // Cross-robot multimodal fusion assist (paper highlight).
  // A) local cold + neighbors: inject fused aim as control (fusion_assist).
  // B) local hot + neighbors: refine pose/aim and tag fusion_fused.
  if (enable_assist && fusion.used_neighbors) {
    result->target_x = fusion.fused_x;
    result->target_y = fusion.fused_y;
    result->target_z = fusion.fused_z;
    if (result->control == 0) {
      result->valid = 1;
      result->control = 1;
      result->yaw = fusion.aim_yaw_rad;
      result->pitch = fusion.aim_pitch_rad;
      result->yaw_velocity_rad_s = 0.0;
      result->pitch_velocity_rad_s = 0.0;
      result->yaw_acceleration_rad_s2 = 0.0;
      result->pitch_acceleration_rad_s2 = 0.0;
      std::snprintf(
        result->tracker_state, sizeof(result->tracker_state), "fusion_assist/%dnb",
        fusion.neighbor_count);
    } else {
      const double yaw_f = fusion.aim_yaw_rad;
      const double pitch_f = fusion.aim_pitch_rad;
      double dyaw = yaw_f - result->yaw;
      while (dyaw > 3.141592653589793) dyaw -= 6.283185307179586;
      while (dyaw < -3.141592653589793) dyaw += 6.283185307179586;
      result->yaw = result->yaw + 0.35 * dyaw;
      result->pitch = result->pitch + 0.35 * (pitch_f - result->pitch);
      std::snprintf(
        result->tracker_state, sizeof(result->tracker_state), "fusion_fused/%dnb",
        fusion.neighbor_count);
    }
  }
}

}  // namespace sp_sim

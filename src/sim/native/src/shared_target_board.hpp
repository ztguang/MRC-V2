#pragma once

#include "engine_api.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <mutex>

// Cross-robot shared observations + paper-style dynamic weighted fusion
// (confidence / distance / timeliness). State is isolated per robot engine;
// this board is the only intentional cross-robot channel inside the worker.
namespace sp_sim {

struct SharedObservation {
  bool valid = false;
  int32_t robot_id = -1;
  int32_t team = SP_TEAM_RED;
  // Godot world frame: +X right, +Y up, -Z forward convention for poses.
  float self_x = 0.0f;
  float self_y = 0.0f;
  float self_z = 0.0f;
  float target_x = 0.0f;
  float target_y = 0.0f;
  float target_z = 0.0f;
  float confidence = 0.0f;  // [0,1]
  int64_t timestamp_usec = 0;
};

struct FusionOutput {
  bool valid = false;
  bool used_neighbors = false;
  int32_t source_count = 0;
  int32_t neighbor_count = 0;
  float fused_x = 0.0f;
  float fused_y = 0.0f;
  float fused_z = 0.0f;
  float fused_confidence = 0.0f;
  double aim_yaw_rad = 0.0;
  double aim_pitch_rad = 0.0;
  double alpha = 0.5;
  double beta = 0.3;
  double gamma = 0.2;
  double lambda = 0.1;
};

class SharedTargetBoard {
public:
  static SharedTargetBoard &instance();

  void publish(const SharedObservation &obs);
  SharedObservation get(int robot_id) const;

  FusionOutput fuse(
    int robot_id, int team, float self_x, float self_y, float self_z,
    int64_t now_usec, bool has_local, float local_tx, float local_ty, float local_tz,
    float local_confidence) const;

  static constexpr int64_t kMaxAgeUsec = 2500000;  // 2.5s for throttled multi-robot vision

private:
  SharedTargetBoard() = default;
  mutable std::mutex mutex_;
  std::array<SharedObservation, SP_MAX_ROBOTS> slots_{};
};

void apply_fusion_to_result(
  SpEngineResult *result, const FusionOutput &fusion, bool enable_assist);

}  // namespace sp_sim

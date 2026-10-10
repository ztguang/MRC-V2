#include "adaptive_lock_tuner.hpp"

#include <algorithm>
#include <cmath>

namespace sp_sim {
namespace {

constexpr double MIN_EXPOSURE = 0.25;
constexpr double MAX_EXPOSURE = 3.0;
constexpr double MIN_BOOST = 0.2;
constexpr double MAX_BOOST = 20.0;
constexpr uint64_t WARMUP_FRAMES = 12;
constexpr uint64_t ADJUST_INTERVAL = 6;

}  // namespace

void AdaptiveLockTuner::reset(
  bool enabled, double requested_exposure, double requested_capture_hz)
{
  enabled_ = enabled;
  frame_count_ = 0;
  const double base = std::max(0.01, requested_exposure);
  // Start near a neutral simulated sensor exposure. Brightness feedback takes
  // over after warmup, so even an accidentally tiny YAML exposure can acquire.
  exposure_boost_ = enabled_ ? std::clamp(1.0 / base, MIN_BOOST, MAX_BOOST) : 1.0;
  last_adjustment_ = 1.0;
  telemetry_ = {};
  telemetry_.effective_exposure = effective_exposure(base);
  telemetry_.suggested_capture_hz = std::max(1.0, requested_capture_hz);
  telemetry_.state = enabled_ ? "warming" : "disabled";
}

double AdaptiveLockTuner::effective_exposure(double requested_exposure) const
{
  const double base = std::max(0.01, requested_exposure);
  if (!enabled_) return base;
  return std::clamp(base * exposure_boost_, MIN_EXPOSURE, MAX_EXPOSURE);
}

double AdaptiveLockTuner::tracker_sample(std::string_view tracker_state)
{
  if (tracker_state == "tracking") return 1.0;
  if (tracker_state == "detecting") return 0.55;
  if (tracker_state == "temp_lost") return 0.2;
  if (tracker_state == "switching") return 0.35;
  return 0.0;
}

double AdaptiveLockTuner::update_ema(
  double current, double sample, double alpha, bool first)
{
  return first ? sample : current + alpha * (sample - current);
}

void AdaptiveLockTuner::observe(
  int armor_count, std::string_view tracker_state, double process_ms,
  double capture_gap_ms, double luma_median, double luma_p90,
  double saturated_fraction, double requested_exposure,
  double requested_capture_hz)
{
  ++frame_count_;
  const bool first = frame_count_ == 1;
  constexpr double RATE_ALPHA = 0.10;
  const double detected = armor_count > 0 ? 1.0 : 0.0;
  const double tracked = tracker_state == "tracking" ? 1.0 : 0.0;
  const double state_quality = tracker_sample(tracker_state);
  const double quality_sample = 0.75 * state_quality + 0.25 * detected;

  telemetry_.detection_rate = update_ema(
    telemetry_.detection_rate, detected, RATE_ALPHA, first);
  telemetry_.tracking_rate = update_ema(
    telemetry_.tracking_rate, tracked, RATE_ALPHA, first);
  telemetry_.lock_quality = update_ema(
    telemetry_.lock_quality, quality_sample, RATE_ALPHA, first);
  telemetry_.average_process_ms = update_ema(
    telemetry_.average_process_ms, std::max(0.1, process_ms), 0.08, first);

  const double requested_hz = std::max(1.0, requested_capture_hz);
  double observed_cost_ms = telemetry_.average_process_ms;
  if (capture_gap_ms > 0.0) observed_cost_ms = std::max(observed_cost_ms, capture_gap_ms);
  // Keep headroom for OpenCV GUI and pipe transfer, which are outside total_ms.
  const double throughput_hz = 850.0 / std::max(1.0, observed_cost_ms);
  telemetry_.suggested_capture_hz = std::clamp(
    std::min(requested_hz, throughput_hz), 8.0, requested_hz);

  last_adjustment_ = 1.0;
  if (enabled_ && frame_count_ >= WARMUP_FRAMES && frame_count_ % ADJUST_INTERVAL == 0) {
    if (luma_p90 < 80.0 || luma_median < 28.0) {
      last_adjustment_ = 1.16;
    } else if (luma_p90 < 108.0 || luma_median < 42.0) {
      last_adjustment_ = 1.08;
    } else if (luma_p90 > 242.0 || saturated_fraction > 0.18) {
      last_adjustment_ = 0.88;
    } else if (luma_p90 > 218.0 || saturated_fraction > 0.08) {
      last_adjustment_ = 0.94;
    }

    // Misses only influence exposure while the image is still plausibly dark.
    // A target outside the FOV must not drive exposure to its upper bound.
    if (
      telemetry_.detection_rate < 0.45 && telemetry_.lock_quality < 0.35 &&
      luma_p90 < 150.0) {
      last_adjustment_ = std::max(last_adjustment_, 1.10);
    }

    exposure_boost_ = std::clamp(
      exposure_boost_ * last_adjustment_, MIN_BOOST, MAX_BOOST);
  }

  telemetry_.effective_exposure = effective_exposure(requested_exposure);
  if (!enabled_) {
    telemetry_.state = "disabled";
  } else if (frame_count_ < WARMUP_FRAMES) {
    telemetry_.state = "warming";
  } else if (telemetry_.suggested_capture_hz < requested_hz * 0.85) {
    telemetry_.state = "cpu_limited";
  } else if (last_adjustment_ > 1.001) {
    telemetry_.state = "brightening";
  } else if (last_adjustment_ < 0.999) {
    telemetry_.state = "dimming";
  } else if (telemetry_.lock_quality >= 0.82) {
    telemetry_.state = "locked";
  } else if (telemetry_.detection_rate < 0.4) {
    telemetry_.state = "searching";
  } else {
    telemetry_.state = "stabilizing";
  }
}

}  // namespace sp_sim

#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace sp_sim {

struct AdaptiveLockTelemetry {
  double effective_exposure = 1.0;
  double lock_quality = 0.0;
  double detection_rate = 0.0;
  double tracking_rate = 0.0;
  double average_process_ms = 0.0;
  double suggested_capture_hz = 30.0;
  std::string state = "warming";
};

// Session-only controller. It never persists values and leaves the requested
// camera exposure untouched, applying only a bounded preprocessing multiplier.
class AdaptiveLockTuner {
public:
  void reset(bool enabled, double requested_exposure, double requested_capture_hz);

  double effective_exposure(double requested_exposure) const;
  void observe(
    int armor_count, std::string_view tracker_state, double process_ms,
    double capture_gap_ms, double luma_median, double luma_p90,
    double saturated_fraction, double requested_exposure,
    double requested_capture_hz);

  const AdaptiveLockTelemetry &telemetry() const { return telemetry_; }

private:
  static double tracker_sample(std::string_view tracker_state);
  static double update_ema(double current, double sample, double alpha, bool first);

  bool enabled_ = true;
  uint64_t frame_count_ = 0;
  double exposure_boost_ = 1.0;
  double last_adjustment_ = 1.0;
  AdaptiveLockTelemetry telemetry_;
};

}  // namespace sp_sim

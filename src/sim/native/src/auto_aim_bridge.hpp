#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <array>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>
#include <sys/types.h>

#include "engine_api.hpp"

namespace sp_sim {

// One bridge serves every robot in the scene: frames are tagged with a
// robot_id, multiplexed over a single worker process (one isolated engine per
// robot inside it), and results are polled back per robot.
class AutoAimBridge : public godot::RefCounted {
  GDCLASS(AutoAimBridge, godot::RefCounted)

public:
  AutoAimBridge();
  ~AutoAimBridge() override;

  godot::Dictionary initialize(const godot::String &config_path);
  godot::Dictionary initialize_with_runtime(
    const godot::String &config_path, const godot::String &runtime_config_path,
    int gui_robot_id = -1);
  godot::Dictionary get_engine_calibration(
    const godot::Transform3D &camera_in_gimbal, int image_width, int image_height,
    double vertical_fov_degrees) const;
  bool submit_frame(
    int robot_id, int team, const godot::Ref<godot::Image> &image,
    const godot::Quaternion &gimbal_rotation, const godot::Transform3D &camera_in_gimbal,
    double fov_degrees, double exposure_multiplier, double gamma,
    const godot::Vector3 &truth_target_world, bool truth_valid, int64_t timestamp_usec,
    double bullet_speed, const godot::Vector3 &self_world_position = godot::Vector3());
  godot::Dictionary poll_result(int robot_id) const;
  godot::Dictionary get_runtime_stats() const;
  void reset();

protected:
  static void _bind_methods();

private:
  struct Frame {
    std::vector<uint8_t> pixels;
    int robot_id = 0;
    int team = SP_TEAM_RED;
    int width = 0;
    int height = 0;
    int channels = 0;
    godot::Quaternion rotation;
    godot::Transform3D camera_in_gimbal;
    double fov_degrees = 50.0;
    double exposure_multiplier = 1.0;
    double gamma = 1.0;
    godot::Vector3 truth_target_world;
    bool truth_valid = false;
    int64_t timestamp_usec = 0;
    double bullet_speed = 23.0;
    godot::Vector3 self_world;
  };

  struct Result {
    bool ready = false;
    bool valid = false;
    bool control = false;
    bool shoot = false;
    double yaw = 0.0;
    double pitch = 0.0;
    double yaw_velocity_rad_s = 0.0;
    double yaw_acceleration_rad_s2 = 0.0;
    double pitch_velocity_rad_s = 0.0;
    double pitch_acceleration_rad_s2 = 0.0;
    double detect_ms = 0.0;
    double track_ms = 0.0;
    double aim_ms = 0.0;
    double total_ms = 0.0;
    double effective_exposure = 1.0;
    double lock_quality = 0.0;
    double suggested_capture_hz = 30.0;
    int armor_count = 0;
    int64_t capture_timestamp_usec = 0;
    int64_t result_timestamp_usec = 0;
    std::string tracker_state = "uninitialized";
    std::string tuner_state = "uninitialized";
    godot::Vector3 target_position;
    godot::Vector3 aim_point;
    bool fusion_valid = false;
    bool fusion_used_neighbors = false;
    int fusion_source_count = 0;
    int fusion_neighbor_count = 0;
    double fusion_confidence = 0.0;
    godot::Vector3 fused_position;
  };

  void start_worker();
  void stop_worker();
  void worker_loop();
  void process_frame(const Frame &frame);
  bool any_pending_locked() const;
  godot::Dictionary initialize_internal(
    const godot::String &config_path, const godot::String &runtime_config_path,
    int gui_robot_id);

  std::string config_path_;
  std::string runtime_config_path_;
  int gui_robot_id_ = -1;
  SpSimulationConfig simulation_config_{};
  bool launch_process(std::string &message);
  void stop_process();
  pid_t worker_pid_ = -1;
  int worker_input_ = -1;
  int worker_output_ = -1;

  mutable std::mutex mutex_;
  std::condition_variable frame_ready_;
  std::array<std::optional<Frame>, SP_MAX_ROBOTS> pending_frames_;
  std::array<Result, SP_MAX_ROBOTS> results_;
  int dispatch_cursor_ = 0;
  std::thread worker_;
  bool stopping_ = false;
  bool initialized_ = false;
  // Maps Godot's ticks-since-start onto the shared CLOCK_MONOTONIC timeline so
  // capture timestamps survive the process boundary (fixed offset, set once).
  int64_t godot_clock_offset_usec_ = 0;
  uint64_t submitted_ = 0;
  uint64_t processed_ = 0;
  uint64_t dropped_ = 0;
};

}  // namespace sp_sim

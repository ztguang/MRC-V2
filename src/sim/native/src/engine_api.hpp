#pragma once

#include <cstddef>
#include <cstdint>

struct SpEngineResult {
  int valid;
  int control;
  int shoot;
  double yaw;
  double pitch;
  double yaw_velocity_rad_s;
  double yaw_acceleration_rad_s2;
  double pitch_velocity_rad_s;
  double pitch_acceleration_rad_s2;
  double detect_ms;
  double track_ms;
  double aim_ms;
  double total_ms;
  double effective_exposure;
  double lock_quality;
  double suggested_capture_hz;
  int armor_count;
  int64_t capture_timestamp_usec;
  int64_t result_timestamp_usec;
  float target_x;
  float target_y;
  float target_z;
  float aim_x;
  float aim_y;
  float aim_z;
  char tracker_state[96];
  char tuner_state[64];
  // Cross-robot dynamic weighted fusion telemetry (Godot world frame).
  int fusion_valid;
  int fusion_used_neighbors;
  int fusion_source_count;
  int fusion_neighbor_count;
  float fusion_confidence;
  float fused_x;
  float fused_y;
  float fused_z;
};

struct SpSimulationConfig {
  int32_t image_width;
  int32_t image_height;
  double camera_fps;
  double fov_degrees;
  double exposure_ms;
  double gain;
  double gamma;
  double exposure_multiplier;
  double tonemap_exposure;
  double ambient_light_energy;
  double sun_energy;
  double threshold;
  double min_confidence;
  double bullet_speed;
  double target_spin_rad_s;
  double fire_thresh;
  double max_yaw_acc;
  double q_yaw_angle;
  double q_yaw_velocity;
  double r_yaw;
  double max_pitch_acc;
  double q_pitch_angle;
  double q_pitch_velocity;
  double r_pitch;
  double auto_aim_yaw_velocity_feedforward;
  double auto_aim_yaw_acceleration_feedforward;
  double auto_aim_pitch_velocity_feedforward;
  double auto_aim_pitch_acceleration_feedforward;
  double yaw_offset_degrees;
  double pitch_offset_degrees;
  int32_t use_traditional;
  int32_t auto_fire;
  int32_t adaptive_tuning;
};

struct SpCameraState {
  double fx;
  double fy;
  double cx;
  double cy;
  double distort_coeffs[5];
  float camera_qx;
  float camera_qy;
  float camera_qz;
  float camera_qw;
  float camera_tx;
  float camera_ty;
  float camera_tz;
  double exposure_multiplier;
  double gamma;
};

// Protocol version 2: per-robot multiplexing over a single worker process.
constexpr uint32_t SP_FRAME_MAGIC = 0x53505632;  // "SPV2"
constexpr int32_t SP_TEAM_RED = 0;
constexpr int32_t SP_TEAM_BLUE = 1;
constexpr int32_t SP_MAX_ROBOTS = 16;

struct SpFrameHeader {
  uint32_t magic;
  int32_t robot_id;
  int32_t team;
  int32_t width;
  int32_t height;
  int32_t channels;
  float qx;
  float qy;
  float qz;
  float qw;
  int64_t timestamp_usec;
  double bullet_speed;
  uint64_t pixel_bytes;
  SpCameraState camera;
  int32_t truth_valid;
  float truth_x;
  float truth_y;
  float truth_z;
  // Observer chassis pose in Godot world frame (for fusion distance/aim).
  float self_x;
  float self_y;
  float self_z;
};

struct SpWorkerReply {
  int32_t ok;
  int32_t robot_id;
  SpEngineResult result;
  char error[512];
};

struct SpWorkerHello {
  int32_t ok;
  SpSimulationConfig simulation;
  char message[512];
};

extern "C" {
// Parses only the simulation-facing keys of the YAML config; never touches
// models or the filesystem beyond reading the config itself.
int sp_engine_load_simulation_config(
  const char *config_path, SpSimulationConfig *config, char *error, std::size_t error_size);
// Creates an isolated engine instance (detector + solver + tracker + planner).
// The engine never mutates process-global state: relative model paths in the
// config are resolved against the config file's directory internally.
// team selects the enemy color (SP_TEAM_RED hunts blue and vice versa);
// debug_tag names this instance in debug windows/artifacts; enable_gui opens
// OpenCV debug windows (enable for at most one engine per process).
void *sp_engine_create(
  const char *config_path, const char *debug_tag, int team, int enable_gui, char *error,
  std::size_t error_size);
void sp_engine_destroy(void *engine);
int sp_engine_get_simulation_config(void *engine, SpSimulationConfig *config);
int sp_engine_set_camera_state(void *engine, const SpCameraState *camera);
void sp_engine_set_ground_truth(void *engine, int valid, float x, float y, float z);
int sp_engine_process(
  void *engine, const uint8_t *pixels, int width, int height, int channels,
  float qx, float qy, float qz, float qw, int64_t timestamp_usec, double bullet_speed,
  SpEngineResult *result, char *error, std::size_t error_size);
}

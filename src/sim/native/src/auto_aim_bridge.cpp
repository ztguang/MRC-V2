#include "auto_aim_bridge.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

#include <algorithm>
#include <chrono>
#include <cerrno>
#include <csignal>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

using namespace godot;

extern char **environ;

namespace {

constexpr double PI = 3.14159265358979323846;

std::filesystem::path extension_directory()
{
  std::error_code error;
  const auto executable = std::filesystem::read_symlink("/proc/self/exe", error);
  if (!error) {
    const auto candidate = executable.parent_path() / "libsp_vision_sim.so";
    if (std::filesystem::exists(candidate)) return executable.parent_path();
  }
  return std::filesystem::current_path() / "sim/godot/bin/linux-x86_64";
}

bool read_all(int fd, void *data, std::size_t size)
{
  auto *bytes = static_cast<unsigned char *>(data);
  while (size > 0) {
    const ssize_t count = ::read(fd, bytes, size);
    if (count == 0) return false;
    if (count < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    bytes += count;
    size -= static_cast<std::size_t>(count);
  }
  return true;
}

bool write_all(int fd, const void *data, std::size_t size)
{
  const auto *bytes = static_cast<const unsigned char *>(data);
  while (size > 0) {
    const ssize_t count = ::write(fd, bytes, size);
    if (count < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    bytes += count;
    size -= static_cast<std::size_t>(count);
  }
  return true;
}

}  // namespace

namespace sp_sim {

AutoAimBridge::AutoAimBridge() { std::signal(SIGPIPE, SIG_IGN); }
AutoAimBridge::~AutoAimBridge()
{
  stop_worker();
  stop_process();
}

void AutoAimBridge::_bind_methods()
{
  ClassDB::bind_method(D_METHOD("initialize", "config_path"), &AutoAimBridge::initialize);
  ClassDB::bind_method(
    D_METHOD("initialize_with_runtime", "config_path", "runtime_config_path", "gui_robot_id"),
    &AutoAimBridge::initialize_with_runtime, DEFVAL(-1));
  ClassDB::bind_method(
    D_METHOD("get_engine_calibration", "camera_in_gimbal", "image_width", "image_height", "vertical_fov_degrees"),
    &AutoAimBridge::get_engine_calibration);
  ClassDB::bind_method(
    D_METHOD(
      "submit_frame", "robot_id", "team", "image", "gimbal_rotation", "camera_in_gimbal",
      "fov_degrees", "exposure_multiplier", "gamma", "truth_target_world", "truth_valid",
      "timestamp_usec", "bullet_speed", "self_world_position"),
    &AutoAimBridge::submit_frame);
  ClassDB::bind_method(D_METHOD("poll_result", "robot_id"), &AutoAimBridge::poll_result);
  ClassDB::bind_method(D_METHOD("get_runtime_stats"), &AutoAimBridge::get_runtime_stats);
  ClassDB::bind_method(D_METHOD("reset"), &AutoAimBridge::reset);
}

Dictionary AutoAimBridge::initialize(const String &config_path)
{
  return initialize_internal(config_path, String(), -1);
}

Dictionary AutoAimBridge::initialize_with_runtime(
  const String &config_path, const String &runtime_config_path, int gui_robot_id)
{
  return initialize_internal(config_path, runtime_config_path, gui_robot_id);
}

Dictionary AutoAimBridge::get_engine_calibration(
  const Transform3D &camera_in_gimbal, int image_width, int image_height,
  double vertical_fov_degrees) const
{
  Dictionary calibration;
  if (image_width <= 0 || image_height <= 0 || vertical_fov_degrees <= 0.0 ||
      vertical_fov_degrees >= 180.0) {
    calibration["ok"] = false;
    calibration["message"] = "invalid Godot camera projection";
    return calibration;
  }

  const double vertical_fov = vertical_fov_degrees * PI / 180.0;
  const double focal_length = image_height / (2.0 * std::tan(vertical_fov / 2.0));
  const double change[3][3]{{0.0, 0.0, -1.0}, {-1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}};
  const double opencv_to_godot[3][3]{{1.0, 0.0, 0.0}, {0.0, -1.0, 0.0}, {0.0, 0.0, -1.0}};
  double godot_rotation[3][3]{};
  const Basis basis = camera_in_gimbal.basis.orthonormalized();
  for (int row = 0; row < 3; ++row) {
    for (int col = 0; col < 3; ++col) godot_rotation[row][col] = basis[row][col];
  }
  double intermediate[3][3]{};
  double camera_to_gimbal[3][3]{};
  for (int row = 0; row < 3; ++row) {
    for (int col = 0; col < 3; ++col) {
      for (int k = 0; k < 3; ++k) intermediate[row][col] += change[row][k] * godot_rotation[k][col];
      for (int k = 0; k < 3; ++k) camera_to_gimbal[row][col] += intermediate[row][k] * opencv_to_godot[k][col];
    }
  }
  const Vector3 origin = camera_in_gimbal.origin;
  const double t_godot[3]{origin.x, origin.y, origin.z};
  double t_camera2gimbal[3]{};
  for (int row = 0; row < 3; ++row) {
    for (int col = 0; col < 3; ++col) t_camera2gimbal[row] += change[row][col] * t_godot[col];
  }
  PackedFloat64Array camera_matrix;
  for (const double value : {focal_length, 0.0, image_width * 0.5, 0.0, focal_length,
                             image_height * 0.5, 0.0, 0.0, 1.0}) {
    camera_matrix.push_back(value);
  }
  PackedFloat64Array distortion;
  for (int i = 0; i < 5; ++i) distortion.push_back(0.0);
  PackedFloat64Array rotation;
  for (const auto &row : camera_to_gimbal) {
    for (double value : row) rotation.push_back(value);
  }
  PackedFloat64Array translation;
  for (double value : t_camera2gimbal) translation.push_back(value);
  calibration["ok"] = true;
  calibration["camera_matrix"] = camera_matrix;
  calibration["distort_coeffs"] = distortion;
  calibration["R_camera2gimbal"] = rotation;
  calibration["t_camera2gimbal"] = translation;
  return calibration;
}

Dictionary AutoAimBridge::initialize_internal(
  const String &config_path, const String &runtime_config_path, int gui_robot_id)
{
  stop_worker();
  stop_process();
  config_path_ = config_path.utf8().get_data();
  runtime_config_path_ = runtime_config_path.utf8().get_data();
  gui_robot_id_ = gui_robot_id;

  Dictionary status;
  std::string message;
  if (!launch_process(message)) {
    status["ok"] = false;
    status["message"] = String(message.c_str());
    return status;
  }

  initialized_ = true;
  for (auto &slot : pending_frames_) slot.reset();
  for (auto &slot : results_) slot = Result{};
  dispatch_cursor_ = 0;
  submitted_ = processed_ = dropped_ = 0;
  godot_clock_offset_usec_ = 0;
  start_worker();
  status["ok"] = true;
  status["message"] = String(message.c_str());
  status["image_width"] = simulation_config_.image_width;
  status["image_height"] = simulation_config_.image_height;
  status["camera_fps"] = simulation_config_.camera_fps;
  status["fov_degrees"] = simulation_config_.fov_degrees;
  status["exposure_ms"] = simulation_config_.exposure_ms;
  status["gain"] = simulation_config_.gain;
  status["gamma"] = simulation_config_.gamma;
  status["exposure_multiplier"] = simulation_config_.exposure_multiplier;
  status["tonemap_exposure"] = simulation_config_.tonemap_exposure;
  status["ambient_light_energy"] = simulation_config_.ambient_light_energy;
  status["sun_energy"] = simulation_config_.sun_energy;
  status["threshold"] = simulation_config_.threshold;
  status["min_confidence"] = simulation_config_.min_confidence;
  status["bullet_speed"] = simulation_config_.bullet_speed;
  status["target_spin_rad_s"] = simulation_config_.target_spin_rad_s;
  status["fire_thresh"] = simulation_config_.fire_thresh;
  status["max_yaw_acc"] = simulation_config_.max_yaw_acc;
  status["q_yaw_angle"] = simulation_config_.q_yaw_angle;
  status["q_yaw_velocity"] = simulation_config_.q_yaw_velocity;
  status["r_yaw"] = simulation_config_.r_yaw;
  status["max_pitch_acc"] = simulation_config_.max_pitch_acc;
  status["q_pitch_angle"] = simulation_config_.q_pitch_angle;
  status["q_pitch_velocity"] = simulation_config_.q_pitch_velocity;
  status["r_pitch"] = simulation_config_.r_pitch;
  status["auto_aim_yaw_velocity_feedforward"] =
    simulation_config_.auto_aim_yaw_velocity_feedforward;
  status["auto_aim_yaw_acceleration_feedforward"] =
    simulation_config_.auto_aim_yaw_acceleration_feedforward;
  status["auto_aim_pitch_velocity_feedforward"] =
    simulation_config_.auto_aim_pitch_velocity_feedforward;
  status["auto_aim_pitch_acceleration_feedforward"] =
    simulation_config_.auto_aim_pitch_acceleration_feedforward;
  status["yaw_offset"] = simulation_config_.yaw_offset_degrees;
  status["pitch_offset"] = simulation_config_.pitch_offset_degrees;
  status["use_traditional"] = simulation_config_.use_traditional != 0;
  status["auto_fire"] = simulation_config_.auto_fire != 0;
  status["adaptive_tuning"] = simulation_config_.adaptive_tuning != 0;
  status["gui_robot_id"] = gui_robot_id_;
  status["max_robots"] = SP_MAX_ROBOTS;
  return status;
}

bool AutoAimBridge::launch_process(std::string &message)
{
  int input_pipe[2]{};
  int output_pipe[2]{};
  if (::pipe(input_pipe) != 0) {
    message = std::strerror(errno);
    return false;
  }
  if (::pipe(output_pipe) != 0) {
    message = std::strerror(errno);
    ::close(input_pipe[0]);
    ::close(input_pipe[1]);
    return false;
  }

  auto worker_path = extension_directory() / "sp_vision_worker";
  if (!std::filesystem::exists(worker_path)) {
    worker_path = std::filesystem::path(config_path_).parent_path().parent_path() /
                  "bin/linux-x86_64/sp_vision_worker";
  }
  const std::string worker = worker_path.string();
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_adddup2(&actions, input_pipe[0], 100);
  posix_spawn_file_actions_adddup2(&actions, output_pipe[1], 101);
  posix_spawn_file_actions_addclose(&actions, input_pipe[1]);
  posix_spawn_file_actions_addclose(&actions, output_pipe[0]);

  std::vector<std::string> arguments{worker, config_path_};
  if (gui_robot_id_ >= 0) {
    arguments.emplace_back("--gui");
    arguments.emplace_back(std::to_string(gui_robot_id_));
  }
  if (!runtime_config_path_.empty()) {
    arguments.emplace_back("--runtime");
    arguments.emplace_back(runtime_config_path_);
  }
  std::vector<char *> argv;
  argv.reserve(arguments.size() + 1);
  for (auto &argument : arguments) argv.push_back(argument.data());
  argv.push_back(nullptr);
  const int spawn_error =
    posix_spawn(&worker_pid_, worker.c_str(), &actions, nullptr, argv.data(), environ);
  posix_spawn_file_actions_destroy(&actions);
  ::close(input_pipe[0]);
  ::close(output_pipe[1]);

  if (spawn_error != 0) {
    ::close(input_pipe[1]);
    ::close(output_pipe[0]);
    worker_pid_ = -1;
    message = std::strerror(spawn_error);
    return false;
  }
  worker_input_ = input_pipe[1];
  worker_output_ = output_pipe[0];

  SpWorkerHello hello{};
  if (!read_all(worker_output_, &hello, sizeof(hello))) {
    message = "Auto-aim worker exited during initialization";
    stop_process();
    return false;
  }
  message = hello.message;
  if (!hello.ok) {
    stop_process();
    return false;
  }
  simulation_config_ = hello.simulation;
  return true;
}

void AutoAimBridge::stop_process()
{
  if (worker_input_ >= 0) ::close(worker_input_);
  if (worker_output_ >= 0) ::close(worker_output_);
  worker_input_ = worker_output_ = -1;
  if (worker_pid_ > 0) {
    int status = 0;
    while (::waitpid(worker_pid_, &status, 0) < 0 && errno == EINTR) {}
  }
  worker_pid_ = -1;
}

bool AutoAimBridge::any_pending_locked() const
{
  for (const auto &slot : pending_frames_) {
    if (slot.has_value()) return true;
  }
  return false;
}

bool AutoAimBridge::submit_frame(
  int robot_id, int team, const Ref<Image> &image, const Quaternion &rotation,
  const Transform3D &camera_in_gimbal, double fov_degrees, double exposure_multiplier,
  double gamma, const Vector3 &truth_target_world, bool truth_valid, int64_t timestamp_usec,
  double bullet_speed, const Vector3 &self_world_position)
{
  if (!initialized_ || image.is_null() || image->is_empty()) return false;
  if (robot_id < 0 || robot_id >= SP_MAX_ROBOTS) return false;
  if (team != SP_TEAM_RED && team != SP_TEAM_BLUE) return false;
  const int channels = image->get_format() == Image::FORMAT_RGB8 ? 3 :
                       image->get_format() == Image::FORMAT_RGBA8 ? 4 : 0;
  if (channels == 0) return false;
  PackedByteArray data = image->get_data();
  const int width = image->get_width();
  const int height = image->get_height();
  const int64_t expected = static_cast<int64_t>(width) * height * channels;
  if (data.size() != expected) return false;

  Frame frame;
  frame.robot_id = robot_id;
  frame.team = team;
  frame.width = width;
  frame.height = height;
  frame.channels = channels;
  frame.rotation = rotation;
  frame.camera_in_gimbal = camera_in_gimbal;
  frame.fov_degrees = fov_degrees;
  frame.exposure_multiplier = exposure_multiplier;
  frame.gamma = gamma;
  frame.truth_target_world = truth_target_world;
  frame.truth_valid = truth_valid;
  // Align Godot ticks with worker steady_clock once, then reuse the offset so
  // Planner latency accounting stays consistent across robots/processes.
  const int64_t steady_now = std::chrono::duration_cast<std::chrono::microseconds>(
    std::chrono::steady_clock::now().time_since_epoch()).count();
  if (godot_clock_offset_usec_ == 0 && timestamp_usec > 0) {
    godot_clock_offset_usec_ = steady_now - timestamp_usec;
  }
  frame.timestamp_usec =
    timestamp_usec > 0 ? timestamp_usec + godot_clock_offset_usec_ : steady_now;
  frame.bullet_speed = bullet_speed;
  frame.self_world = self_world_position;
  frame.pixels.resize(static_cast<std::size_t>(expected));
  std::memcpy(frame.pixels.data(), data.ptr(), static_cast<std::size_t>(expected));
  {
    std::lock_guard lock(mutex_);
    if (pending_frames_[static_cast<std::size_t>(robot_id)].has_value()) ++dropped_;
    pending_frames_[static_cast<std::size_t>(robot_id)] = std::move(frame);
    ++submitted_;
  }
  frame_ready_.notify_one();
  return true;
}

Dictionary AutoAimBridge::poll_result(int robot_id) const
{
  std::lock_guard lock(mutex_);
  Dictionary value;
  value["robot_id"] = robot_id;
  if (robot_id < 0 || robot_id >= SP_MAX_ROBOTS) {
    value["ready"] = false;
    value["valid"] = false;
    value["tracker_state"] = "invalid robot_id";
    return value;
  }
  const Result &result = results_[static_cast<std::size_t>(robot_id)];
  value["ready"] = result.ready;
  value["valid"] = result.valid;
  value["control"] = result.control;
  value["shoot"] = result.shoot;
  value["yaw_rad"] = result.yaw;
  value["pitch_rad"] = result.pitch;
  value["yaw_velocity_rad_s"] = result.yaw_velocity_rad_s;
  value["yaw_acceleration_rad_s2"] = result.yaw_acceleration_rad_s2;
  value["pitch_velocity_rad_s"] = result.pitch_velocity_rad_s;
  value["pitch_acceleration_rad_s2"] = result.pitch_acceleration_rad_s2;
  value["tracker_state"] = String(result.tracker_state.c_str());
  value["armor_count"] = result.armor_count;
  value["target_position"] = result.target_position;
  value["aim_point"] = result.aim_point;
  value["capture_timestamp_usec"] = result.capture_timestamp_usec;
  value["result_timestamp_usec"] = result.result_timestamp_usec;
  value["detect_ms"] = result.detect_ms;
  value["track_ms"] = result.track_ms;
  value["aim_ms"] = result.aim_ms;
  value["total_ms"] = result.total_ms;
  value["effective_exposure"] = result.effective_exposure;
  value["lock_quality"] = result.lock_quality;
  value["suggested_capture_hz"] = result.suggested_capture_hz;
  value["tuner_state"] = String(result.tuner_state.c_str());
  value["fusion_valid"] = result.fusion_valid;
  value["fusion_used_neighbors"] = result.fusion_used_neighbors;
  value["fusion_source_count"] = result.fusion_source_count;
  value["fusion_neighbor_count"] = result.fusion_neighbor_count;
  value["fusion_confidence"] = result.fusion_confidence;
  value["fused_position"] = result.fused_position;
  return value;
}

Dictionary AutoAimBridge::get_runtime_stats() const
{
  std::lock_guard lock(mutex_);
  Dictionary stats;
  stats["initialized"] = initialized_;
  stats["submitted"] = static_cast<int64_t>(submitted_);
  stats["processed"] = static_cast<int64_t>(processed_);
  stats["dropped"] = static_cast<int64_t>(dropped_);
  int queue_depth = 0;
  int active_results = 0;
  for (const auto &slot : pending_frames_) {
    if (slot.has_value()) ++queue_depth;
  }
  for (const auto &slot : results_) {
    if (slot.ready) ++active_results;
  }
  stats["queue_depth"] = queue_depth;
  stats["active_results"] = active_results;
  stats["max_robots"] = SP_MAX_ROBOTS;
  stats["gui_robot_id"] = gui_robot_id_;
  return stats;
}

void AutoAimBridge::reset()
{
  if (!config_path_.empty()) {
    if (runtime_config_path_.empty()) {
      initialize(String(config_path_.c_str()));
    } else {
      initialize_with_runtime(
        String(config_path_.c_str()), String(runtime_config_path_.c_str()), gui_robot_id_);
    }
  }
}

void AutoAimBridge::start_worker()
{
  stopping_ = false;
  worker_ = std::thread(&AutoAimBridge::worker_loop, this);
}

void AutoAimBridge::stop_worker()
{
  {
    std::lock_guard lock(mutex_);
    stopping_ = true;
    for (auto &slot : pending_frames_) slot.reset();
  }
  frame_ready_.notify_all();
  if (worker_.joinable()) worker_.join();
  initialized_ = false;
}

void AutoAimBridge::worker_loop()
{
  while (true) {
    Frame frame;
    {
      std::unique_lock lock(mutex_);
      frame_ready_.wait(lock, [this] { return stopping_ || any_pending_locked(); });
      if (stopping_) return;
      // Round-robin dispatch so no robot starves when all six are active.
      bool found = false;
      for (int step = 0; step < SP_MAX_ROBOTS; ++step) {
        const int index = (dispatch_cursor_ + step) % SP_MAX_ROBOTS;
        if (!pending_frames_[static_cast<std::size_t>(index)].has_value()) continue;
        frame = std::move(*pending_frames_[static_cast<std::size_t>(index)]);
        pending_frames_[static_cast<std::size_t>(index)].reset();
        dispatch_cursor_ = (index + 1) % SP_MAX_ROBOTS;
        found = true;
        break;
      }
      if (!found) continue;
    }
    process_frame(frame);
  }
}

void AutoAimBridge::process_frame(const Frame &frame)
{
  SpFrameHeader header{};
  header.magic = SP_FRAME_MAGIC;
  header.robot_id = frame.robot_id;
  header.team = frame.team;
  header.width = frame.width;
  header.height = frame.height;
  header.channels = frame.channels;
  header.qx = frame.rotation.x;
  header.qy = frame.rotation.y;
  header.qz = frame.rotation.z;
  header.qw = frame.rotation.w;
  header.timestamp_usec = frame.timestamp_usec;
  header.bullet_speed = frame.bullet_speed;
  header.pixel_bytes = frame.pixels.size();
  const double vertical_fov = std::clamp(frame.fov_degrees, 1.0, 179.0) * PI / 180.0;
  const double focal_length = frame.height / (2.0 * std::tan(vertical_fov / 2.0));
  header.camera.fx = focal_length;
  header.camera.fy = focal_length;
  header.camera.cx = frame.width / 2.0;
  header.camera.cy = frame.height / 2.0;
  const Quaternion camera_rotation = frame.camera_in_gimbal.basis.get_rotation_quaternion();
  header.camera.camera_qx = camera_rotation.x;
  header.camera.camera_qy = camera_rotation.y;
  header.camera.camera_qz = camera_rotation.z;
  header.camera.camera_qw = camera_rotation.w;
  header.camera.camera_tx = frame.camera_in_gimbal.origin.x;
  header.camera.camera_ty = frame.camera_in_gimbal.origin.y;
  header.camera.camera_tz = frame.camera_in_gimbal.origin.z;
  header.camera.exposure_multiplier = frame.exposure_multiplier;
  header.camera.gamma = frame.gamma;
  header.truth_valid = frame.truth_valid ? 1 : 0;
  header.truth_x = frame.truth_target_world.x;
  header.truth_y = frame.truth_target_world.y;
  header.truth_z = frame.truth_target_world.z;
  header.self_x = frame.self_world.x;
  header.self_y = frame.self_world.y;
  header.self_z = frame.self_world.z;

  SpWorkerReply reply{};
  const bool transport_ok =
    write_all(worker_input_, &header, sizeof(header)) &&
    write_all(worker_input_, frame.pixels.data(), frame.pixels.size()) &&
    read_all(worker_output_, &reply, sizeof(reply));

  Result next;
  next.ready = true;
  next.capture_timestamp_usec = frame.timestamp_usec;
  if (transport_ok && reply.ok) {
    const auto &output = reply.result;
    next.valid = output.valid != 0;
    next.control = output.control != 0;
    next.shoot = output.shoot != 0;
    next.yaw = output.yaw;
    next.pitch = output.pitch;
    next.yaw_velocity_rad_s = output.yaw_velocity_rad_s;
    next.yaw_acceleration_rad_s2 = output.yaw_acceleration_rad_s2;
    next.pitch_velocity_rad_s = output.pitch_velocity_rad_s;
    next.pitch_acceleration_rad_s2 = output.pitch_acceleration_rad_s2;
    next.detect_ms = output.detect_ms;
    next.track_ms = output.track_ms;
    next.aim_ms = output.aim_ms;
    next.total_ms = output.total_ms;
    next.effective_exposure = output.effective_exposure;
    next.lock_quality = output.lock_quality;
    next.suggested_capture_hz = output.suggested_capture_hz;
    next.armor_count = output.armor_count;
    next.capture_timestamp_usec = output.capture_timestamp_usec;
    next.result_timestamp_usec = output.result_timestamp_usec;
    next.tracker_state = output.tracker_state;
    next.tuner_state = output.tuner_state;
    next.target_position = {output.target_x, output.target_y, output.target_z};
    next.aim_point = {output.aim_x, output.aim_y, output.aim_z};
    next.fusion_valid = output.fusion_valid != 0;
    next.fusion_used_neighbors = output.fusion_used_neighbors != 0;
    next.fusion_source_count = output.fusion_source_count;
    next.fusion_neighbor_count = output.fusion_neighbor_count;
    next.fusion_confidence = output.fusion_confidence;
    next.fused_position = {output.fused_x, output.fused_y, output.fused_z};
  } else {
    next.result_timestamp_usec = std::chrono::duration_cast<std::chrono::microseconds>(
      std::chrono::steady_clock::now().time_since_epoch()).count();
    next.tracker_state = transport_ok ? std::string("error: ") + reply.error
                                      : "error: auto-aim worker disconnected";
  }

  const int robot_id = frame.robot_id;
  std::lock_guard lock(mutex_);
  if (robot_id >= 0 && robot_id < SP_MAX_ROBOTS) {
    results_[static_cast<std::size_t>(robot_id)] = std::move(next);
  }
  ++processed_;
}

}  // namespace sp_sim

#include "engine_api.hpp"

#include "adaptive_lock_tuner.hpp"
#include "sim_detector.hpp"

#include <Eigen/Geometry>
#include <opencv2/imgproc.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgcodecs.hpp>
#include <yaml-cpp/yaml.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <limits>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

#include "tasks/auto_aim/planner/planner.hpp"
#include "tasks/auto_aim/solver.hpp"
#include "tasks/auto_aim/tracker.hpp"
#include "tasks/auto_aim/yolo.hpp"
#include "tools/img_tools.hpp"
#include "tools/math_tools.hpp"

using Clock = std::chrono::steady_clock;

namespace {

constexpr double RAD_TO_DEG = 180.0 / 3.14159265358979323846;

struct ScopeSample {
  double truth_yaw = 0.0;
  double tracked_yaw = std::numeric_limits<double>::quiet_NaN();
  double command_yaw = std::numeric_limits<double>::quiet_NaN();
  double gimbal_yaw = 0.0;
  double truth_pitch = 0.0;
  double tracked_pitch = std::numeric_limits<double>::quiet_NaN();
  double command_pitch = std::numeric_limits<double>::quiet_NaN();
  double gimbal_pitch = 0.0;
  double vision_yaw_error = std::numeric_limits<double>::quiet_NaN();
  double vision_pitch_error = std::numeric_limits<double>::quiet_NaN();
  double lead_yaw_delta = std::numeric_limits<double>::quiet_NaN();
  double lead_pitch_delta = std::numeric_limits<double>::quiet_NaN();
  double aim_yaw_error = std::numeric_limits<double>::quiet_NaN();
  double aim_pitch_error = std::numeric_limits<double>::quiet_NaN();
  double tracking_yaw_error = std::numeric_limits<double>::quiet_NaN();
  double tracking_pitch_error = std::numeric_limits<double>::quiet_NaN();
};

struct ScopeCurve {
  const char *name;
  double ScopeSample::*value;
  cv::Scalar color;
};

struct Engine {
  bool external_gui = false;
  std::string tag = "r0";
  SpSimulationConfig simulation{};
  cv::Mat gamma_lut;
  std::unique_ptr<auto_aim::YOLO> detector;
  std::unique_ptr<auto_aim::Solver> solver;
  std::unique_ptr<auto_aim::Tracker> tracker;
  std::unique_ptr<auto_aim::Planner> planner;
  sp_sim::AdaptiveLockTuner lock_tuner;
  double requested_exposure_multiplier = 1.0;
  int64_t previous_capture_timestamp_usec = 0;
  bool truth_valid = false;
  Eigen::Vector3d truth_world = Eigen::Vector3d::Zero();
  std::deque<ScopeSample> scope_samples;
  uint64_t debug_frame_count = 0;
};

struct LumaSummary {
  double median = 0.0;
  double p90 = 0.0;
  double saturated_fraction = 0.0;
};

void set_error(char *error, std::size_t size, const char *message)
{
  if (error == nullptr || size == 0) return;
  std::snprintf(error, size, "%s", message);
}

Eigen::Quaterniond to_sp_quaternion(float qx, float qy, float qz, float qw)
{
  const Eigen::Quaterniond godot_q(qw, qx, qy, qz);
  Eigen::Matrix3d change;
  change << 0, 0, -1,
            -1, 0, 0,
             0, 1, 0;
  return Eigen::Quaterniond(change * godot_q.normalized().toRotationMatrix() * change.transpose());
}

void set_godot_vector(float &x, float &y, float &z, const Eigen::Vector3d &v)
{
  x = static_cast<float>(-v.y());
  y = static_cast<float>(v.z());
  z = static_cast<float>(-v.x());
}

double elapsed_ms(Clock::time_point end, Clock::time_point begin)
{
  return std::chrono::duration<double, std::milli>(end - begin).count();
}

int64_t now_usec()
{
  return std::chrono::duration_cast<std::chrono::microseconds>(Clock::now().time_since_epoch())
    .count();
}

LumaSummary sample_luma(const cv::Mat & bgr)
{
  std::array<uint32_t, 256> histogram{};
  uint64_t samples = 0;
  uint64_t saturated = 0;
  const double pixels = static_cast<double>(bgr.rows) * bgr.cols;
  const int stride = std::max(1, static_cast<int>(std::sqrt(pixels / 4096.0)));
  for (int y = stride / 2; y < bgr.rows; y += stride) {
    const auto *row = bgr.ptr<cv::Vec3b>(y);
    for (int x = stride / 2; x < bgr.cols; x += stride) {
      const cv::Vec3b &pixel = row[x];
      const int luma = (29 * pixel[0] + 150 * pixel[1] + 77 * pixel[2] + 128) >> 8;
      ++histogram[static_cast<std::size_t>(std::clamp(luma, 0, 255))];
      if (std::max({pixel[0], pixel[1], pixel[2]}) >= 250) ++saturated;
      ++samples;
    }
  }
  if (samples == 0) return {};
  const auto percentile = [&](double fraction) {
    const uint64_t target = static_cast<uint64_t>(std::ceil(samples * fraction));
    uint64_t accumulated = 0;
    for (std::size_t value = 0; value < histogram.size(); ++value) {
      accumulated += histogram[value];
      if (accumulated >= target) return static_cast<double>(value);
    }
    return 255.0;
  };
  return {percentile(0.5), percentile(0.9), static_cast<double>(saturated) / samples};
}

double yaml_double(const YAML::Node & yaml, const char *key, double fallback)
{
  return yaml[key] ? yaml[key].as<double>() : fallback;
}

int yaml_int(const YAML::Node & yaml, const char *key, int fallback)
{
  return yaml[key] ? yaml[key].as<int>() : fallback;
}

std::array<double, 2> yaml_pair(
  const YAML::Node & yaml, const char * key, const std::array<double, 2> & fallback)
{
  const auto values = yaml[key];
  if (!values || !values.IsSequence() || values.size() < 2) return fallback;
  return {values[0].as<double>(), values[1].as<double>()};
}

double yaml_first(const YAML::Node & yaml, const char * key, double fallback)
{
  const auto value = yaml[key];
  if (!value) return fallback;
  if (value.IsSequence()) return value.size() > 0 ? value[0].as<double>() : fallback;
  return value.as<double>();
}

std::filesystem::path write_planner_config(
  const YAML::Node & source, const SpSimulationConfig & simulation, const std::string & tag)
{
  YAML::Node yaml = YAML::Clone(source);
  yaml["yaw_offset"] = simulation.yaw_offset_degrees;
  yaml["pitch_offset"] = simulation.pitch_offset_degrees;
  yaml["decision_speed"] = yaml_double(source, "decision_speed", 8.0);
  yaml["high_speed_delay_time"] = yaml_double(source, "high_speed_delay_time", 0.030);
  yaml["low_speed_delay_time"] = yaml_double(source, "low_speed_delay_time", 0.015);
  yaml["fire_thresh"] = simulation.fire_thresh;
  yaml["max_yaw_acc"] = simulation.max_yaw_acc;
  yaml["Q_yaw"] = std::vector<double>{simulation.q_yaw_angle, simulation.q_yaw_velocity};
  yaml["R_yaw"] = std::vector<double>{simulation.r_yaw};
  yaml["max_pitch_acc"] = simulation.max_pitch_acc;
  yaml["Q_pitch"] =
    std::vector<double>{simulation.q_pitch_angle, simulation.q_pitch_velocity};
  yaml["R_pitch"] = std::vector<double>{simulation.r_pitch};

  const auto path = std::filesystem::temp_directory_path() /
    ("sp_vision_planner_" + tag + "_" + std::to_string(now_usec()) + ".yaml");
  std::ofstream output(path);
  output << yaml;
  if (!output) throw std::runtime_error("failed to write planner runtime config");
  return path;
}

// Rewrites relative model paths against the config's own directory and pins
// enemy_color from the team, so engine construction never needs chdir.
std::filesystem::path write_engine_config(
  const YAML::Node & source, const std::filesystem::path & config_dir, int team,
  const std::string & tag)
{
  YAML::Node yaml = YAML::Clone(source);
  for (const char *key :
       {"classify_model", "yolov5_model_path", "yolov8_model_path", "yolo11_model_path"}) {
    if (!yaml[key]) continue;
    const std::filesystem::path model = yaml[key].as<std::string>();
    if (model.is_relative()) {
      yaml[key] = std::filesystem::weakly_canonical(config_dir / model).string();
    }
  }
  yaml["enemy_color"] = team == SP_TEAM_RED ? "blue" : "red";
  const auto path = std::filesystem::temp_directory_path() /
    ("sp_vision_engine_" + tag + "_" + std::to_string(now_usec()) + ".yaml");
  std::ofstream output(path);
  output << yaml;
  if (!output) throw std::runtime_error("failed to write engine runtime config");
  return path;
}

void update_gamma_lut(Engine & engine, double gamma)
{
  engine.simulation.gamma = std::max(0.01, gamma);
  engine.gamma_lut = cv::Mat(1, 256, CV_8U);
  for (int value = 0; value < 256; ++value) {
    engine.gamma_lut.at<uint8_t>(value) = cv::saturate_cast<uint8_t>(
      std::pow(value / 255.0, engine.simulation.gamma) * 255.0);
  }
}

double wrap_degrees(double angle)
{
  while (angle > 180.0) angle -= 360.0;
  while (angle <= -180.0) angle += 360.0;
  return angle;
}

void draw_scope_plot(
  cv::Mat & canvas, const cv::Rect & area, const std::deque<ScopeSample> & samples,
  const std::string & title, const std::vector<ScopeCurve> & curves)
{
  cv::rectangle(canvas, area, {70, 78, 82}, 1);
  if (samples.empty()) return;
  double minimum = std::numeric_limits<double>::infinity();
  double maximum = -std::numeric_limits<double>::infinity();
  for (const auto & sample : samples) {
    for (const auto & curve : curves) {
      const double value = sample.*(curve.value);
      if (!std::isfinite(value)) continue;
      minimum = std::min(minimum, value);
      maximum = std::max(maximum, value);
    }
  }
  if (!std::isfinite(minimum) || !std::isfinite(maximum)) return;
  const double center = (minimum + maximum) * 0.5;
  const double half_range = std::max(2.0, (maximum - minimum) * 0.65);
  minimum = center - half_range;
  maximum = center + half_range;
  for (int row = 0; row <= 4; ++row) {
    const int y = area.y + row * area.height / 4;
    cv::line(canvas, {area.x, y}, {area.x + area.width, y}, {48, 55, 58}, 1);
    const double value = maximum - row * (maximum - minimum) / 4.0;
    cv::putText(
      canvas, cv::format("%6.2f", value), {4, y + 4}, cv::FONT_HERSHEY_SIMPLEX,
      0.38, {170, 178, 181}, 1, cv::LINE_AA);
  }
  cv::putText(
    canvas, title, {area.x, area.y - 8}, cv::FONT_HERSHEY_SIMPLEX, 0.5,
    {220, 225, 228}, 1, cv::LINE_AA);
  const double x_scale = samples.size() > 1
    ? static_cast<double>(area.width - 1) / (samples.size() - 1) : 0.0;
  const double y_scale = (area.height - 1) / (maximum - minimum);
  for (const auto & curve : curves) {
    cv::Point previous;
    bool has_previous = false;
    for (std::size_t index = 0; index < samples.size(); ++index) {
      const double value = samples[index].*(curve.value);
      if (!std::isfinite(value)) {
        has_previous = false;
        continue;
      }
      const cv::Point point{
        area.x + static_cast<int>(index * x_scale),
        area.y + area.height - 1 - static_cast<int>((value - minimum) * y_scale)};
      if (has_previous) cv::line(canvas, previous, point, curve.color, 2, cv::LINE_AA);
      previous = point;
      has_previous = true;
    }
  }
}

void show_aim_scope(Engine & engine)
{
  cv::Mat canvas(760, 1040, CV_8UC3, cv::Scalar(24, 29, 31));
  const std::vector<ScopeCurve> angle_curves{
    {"target", &ScopeSample::truth_yaw, {0, 220, 255}},
    {"tracked", &ScopeSample::tracked_yaw, {90, 225, 90}},
    {"auto aim", &ScopeSample::command_yaw, {45, 45, 245}},
    {"gimbal", &ScopeSample::gimbal_yaw, {245, 220, 45}}};
  const std::vector<ScopeCurve> pitch_curves{
    {"target", &ScopeSample::truth_pitch, {0, 220, 255}},
    {"tracked", &ScopeSample::tracked_pitch, {90, 225, 90}},
    {"auto aim", &ScopeSample::command_pitch, {45, 45, 245}},
    {"gimbal", &ScopeSample::gimbal_pitch, {245, 220, 45}}};
  const std::vector<ScopeCurve> error_curves{
    {"vision yaw", &ScopeSample::vision_yaw_error, {90, 225, 90}},
    {"vision pitch", &ScopeSample::vision_pitch_error, {65, 150, 65}},
    {"servo yaw", &ScopeSample::tracking_yaw_error, {245, 220, 45}},
    {"servo pitch", &ScopeSample::tracking_pitch_error, {170, 145, 35}}};
  draw_scope_plot(canvas, {70, 72, 950, 170}, engine.scope_samples, "Yaw (deg)", angle_curves);
  draw_scope_plot(canvas, {70, 305, 950, 170}, engine.scope_samples, "Pitch (deg)", pitch_curves);
  draw_scope_plot(canvas, {70, 538, 950, 170}, engine.scope_samples, "Error (deg)", error_curves);

  int legend_x = 72;
  for (const auto & curve : angle_curves) {
    cv::line(canvas, {legend_x, 28}, {legend_x + 24, 28}, curve.color, 3, cv::LINE_AA);
    cv::putText(
      canvas, curve.name, {legend_x + 30, 33}, cv::FONT_HERSHEY_SIMPLEX, 0.45,
      {215, 220, 222}, 1, cv::LINE_AA);
    legend_x += 128;
  }
  if (!engine.scope_samples.empty()) {
    const auto & last = engine.scope_samples.back();
    const std::string command_text = std::isfinite(last.command_yaw)
      ? cv::format(
          "command-target gap yaw %+6.2f  pitch %+6.2f deg", last.aim_yaw_error,
          last.aim_pitch_error)
      : "command-target gap: waiting for tracker";
    cv::putText(
      canvas, command_text, {590, 33}, cv::FONT_HERSHEY_SIMPLEX, 0.43,
      {225, 228, 230}, 1, cv::LINE_AA);
    if (std::isfinite(last.tracked_yaw) && std::isfinite(last.command_yaw)) {
      const std::string decomposition = cv::format(
        "vision %+5.2f/%+5.2f  lead %+5.2f/%+5.2f  servo %+5.2f/%+5.2f",
        last.vision_yaw_error, last.vision_pitch_error, last.lead_yaw_delta,
        last.lead_pitch_delta, last.tracking_yaw_error, last.tracking_pitch_error);
      cv::putText(
        canvas, decomposition, {450, 55}, cv::FONT_HERSHEY_SIMPLEX, 0.37,
        {170, 180, 183}, 1, cv::LINE_AA);
    }
  }
  cv::imshow("aim_error_scope_" + engine.tag, canvas);
  if (engine.debug_frame_count % 15 == 0) {
    cv::imwrite(
      (std::filesystem::temp_directory_path() /
       ("sp_vision_aim_error_scope_" + engine.tag + ".png")).string(), canvas);
  }
}

}  // namespace

namespace {

void load_simulation_yaml(const YAML::Node & yaml, SpSimulationConfig & simulation)
{
  simulation.image_width = yaml_int(yaml, "image_width", 1280);
  simulation.image_height = yaml_int(yaml, "image_height", 720);
  simulation.camera_fps = yaml_double(yaml, "camera_fps", 30.0);
  simulation.fov_degrees = yaml_double(yaml, "fov_degrees", 50.0);
  simulation.exposure_ms = yaml_double(yaml, "exposure_ms", 2.0);
  simulation.gain = yaml_double(yaml, "gain", 0.0);
  simulation.gamma = yaml_double(yaml, "gamma", 1.0);
  simulation.exposure_multiplier =
    std::max(0.01, simulation.exposure_ms / 2.0) *
    std::pow(10.0, simulation.gain / 20.0);
  simulation.tonemap_exposure = yaml_double(yaml, "tonemap_exposure", 1.0);
  simulation.ambient_light_energy = yaml_double(yaml, "ambient_light_energy", 0.8);
  simulation.sun_energy = yaml_double(yaml, "sun_energy", 1.1);
  simulation.threshold = yaml_double(yaml, "threshold", 130.0);
  simulation.min_confidence = yaml_double(yaml, "min_confidence", 0.7);
  simulation.bullet_speed =
    std::clamp(yaml_double(yaml, "bullet_speed", 23.0), 14.0, 30.0);
  simulation.target_spin_rad_s =
    std::clamp(yaml_double(yaml, "target_spin_rad_s", 4.0), -20.0, 20.0);
  simulation.yaw_offset_degrees = yaml_double(yaml, "yaw_offset", 0.0);
  simulation.pitch_offset_degrees = yaml_double(yaml, "pitch_offset", 0.0);
  simulation.fire_thresh = yaml_double(yaml, "fire_thresh", 0.0035);
  simulation.max_yaw_acc = yaml_double(yaml, "max_yaw_acc", 50.0);
  const auto q_yaw = yaml_pair(yaml, "Q_yaw", {9e6, 0.0});
  simulation.q_yaw_angle = q_yaw[0];
  simulation.q_yaw_velocity = q_yaw[1];
  simulation.r_yaw = yaml_first(yaml, "R_yaw", 1.0);
  simulation.max_pitch_acc = yaml_double(yaml, "max_pitch_acc", 100.0);
  const auto q_pitch = yaml_pair(yaml, "Q_pitch", {9e6, 0.0});
  simulation.q_pitch_angle = q_pitch[0];
  simulation.q_pitch_velocity = q_pitch[1];
  simulation.r_pitch = yaml_first(yaml, "R_pitch", 1.0);
  simulation.auto_aim_yaw_velocity_feedforward =
    yaml_double(yaml, "auto_aim_yaw_velocity_feedforward", 1.0);
  simulation.auto_aim_yaw_acceleration_feedforward =
    yaml_double(yaml, "auto_aim_yaw_acceleration_feedforward", 1.0);
  simulation.auto_aim_pitch_velocity_feedforward =
    yaml_double(yaml, "auto_aim_pitch_velocity_feedforward", 1.0);
  simulation.auto_aim_pitch_acceleration_feedforward =
    yaml_double(yaml, "auto_aim_pitch_acceleration_feedforward", 1.0);
  simulation.use_traditional = yaml["use_traditional"]
    ? static_cast<int32_t>(yaml["use_traditional"].as<bool>()) : 0;
  simulation.auto_fire = yaml["auto_fire"]
    ? static_cast<int32_t>(yaml["auto_fire"].as<bool>()) : 0;
  simulation.adaptive_tuning = yaml["adaptive_tuning"]
    ? static_cast<int32_t>(yaml["adaptive_tuning"].as<bool>()) : 1;
}

}  // namespace

extern "C" int sp_engine_load_simulation_config(
  const char *config_path, SpSimulationConfig *config, char *error, std::size_t error_size)
{
  if (config_path == nullptr || config == nullptr) {
    set_error(error, error_size, "invalid arguments");
    return 0;
  }
  try {
    const YAML::Node yaml = YAML::LoadFile(config_path);
    *config = {};
    load_simulation_yaml(yaml, *config);
    return 1;
  } catch (const std::exception &exception) {
    set_error(error, error_size, exception.what());
    return 0;
  }
}

extern "C" void *sp_engine_create(
  const char *config_path, const char *debug_tag, int team, int enable_gui, char *error,
  std::size_t error_size)
{
  std::filesystem::path engine_config;
  try {
    const std::filesystem::path config = std::filesystem::absolute(config_path);
    auto engine = std::make_unique<Engine>();
    engine->tag = debug_tag != nullptr && debug_tag[0] != '\0' ? debug_tag : "r0";
    const YAML::Node yaml = YAML::LoadFile(config.string());
    load_simulation_yaml(yaml, engine->simulation);
    engine->requested_exposure_multiplier = engine->simulation.exposure_multiplier;
    engine->lock_tuner.reset(
      engine->simulation.adaptive_tuning != 0,
      engine->requested_exposure_multiplier, engine->simulation.camera_fps);
    update_gamma_lut(*engine, engine->simulation.gamma);
    engine->external_gui = enable_gui != 0;
    engine_config = write_engine_config(yaml, config.parent_path(), team, engine->tag);
    engine->detector =
      std::make_unique<auto_aim::YOLO>(engine_config.string(), engine->external_gui);
    engine->solver = std::make_unique<auto_aim::Solver>(engine_config.string());
    engine->tracker = std::make_unique<auto_aim::Tracker>(engine_config.string(), *engine->solver);
    const auto planner_config =
      write_planner_config(yaml, engine->simulation, engine->tag);
    try {
      engine->planner = std::make_unique<auto_aim::Planner>(planner_config.string());
    } catch (...) {
      std::filesystem::remove(planner_config);
      throw;
    }
    std::filesystem::remove(planner_config);
    std::filesystem::remove(engine_config);
    return engine.release();
  } catch (const std::exception &exception) {
    std::error_code ignored;
    if (!engine_config.empty()) std::filesystem::remove(engine_config, ignored);
    set_error(error, error_size, exception.what());
    return nullptr;
  }
}

extern "C" void sp_engine_destroy(void *engine) { delete static_cast<Engine *>(engine); }

extern "C" int sp_engine_get_simulation_config(void *opaque, SpSimulationConfig *config)
{
  if (opaque == nullptr || config == nullptr) return 0;
  *config = static_cast<Engine *>(opaque)->simulation;
  return 1;
}

extern "C" int sp_engine_set_camera_state(void *opaque, const SpCameraState *camera)
{
  if (opaque == nullptr || camera == nullptr || camera->fx <= 0.0 || camera->fy <= 0.0) return 0;
  auto & engine = *static_cast<Engine *>(opaque);
  Eigen::Matrix3d camera_matrix;
  camera_matrix << camera->fx, 0.0, camera->cx,
                   0.0, camera->fy, camera->cy,
                   0.0, 0.0, 1.0;
  Eigen::Matrix<double, 1, 5> distort_coeffs;
  for (int i = 0; i < 5; ++i) distort_coeffs[i] = camera->distort_coeffs[i];

  const Eigen::Quaterniond camera_rotation_godot(
    camera->camera_qw, camera->camera_qx, camera->camera_qy, camera->camera_qz);
  Eigen::Matrix3d change;
  change << 0, 0, -1,
            -1, 0, 0,
             0, 1, 0;
  const Eigen::Matrix3d opencv_to_godot =
    (Eigen::Vector3d(1.0, -1.0, -1.0)).asDiagonal();
  const Eigen::Matrix3d R_camera2gimbal =
    change * camera_rotation_godot.normalized().toRotationMatrix() * opencv_to_godot;
  const Eigen::Vector3d t_camera2gimbal = change * Eigen::Vector3d(
    camera->camera_tx, camera->camera_ty, camera->camera_tz);
  engine.solver->set_camera_calibration(
    camera_matrix, distort_coeffs, R_camera2gimbal, t_camera2gimbal);
  engine.requested_exposure_multiplier = std::max(0.01, camera->exposure_multiplier);
  if (std::abs(engine.simulation.gamma - camera->gamma) > 1e-6) {
    update_gamma_lut(engine, camera->gamma);
  }
  return 1;
}

extern "C" void sp_engine_set_ground_truth(
  void *opaque, int valid, float x, float y, float z)
{
  if (opaque == nullptr) return;
  auto & engine = *static_cast<Engine *>(opaque);
  engine.truth_valid = valid != 0;
  Eigen::Matrix3d change;
  change << 0, 0, -1,
            -1, 0, 0,
             0, 1, 0;
  engine.truth_world = change * Eigen::Vector3d(x, y, z);
}

extern "C" int sp_engine_process(
  void *opaque, const uint8_t *pixels, int width, int height, int channels,
  float qx, float qy, float qz, float qw, int64_t timestamp_usec, double bullet_speed,
  SpEngineResult *result, char *error, std::size_t error_size)
{
  if (opaque == nullptr || pixels == nullptr || result == nullptr || (channels != 3 && channels != 4)) {
    set_error(error, error_size, "invalid engine frame arguments");
    return 0;
  }
  try {
    auto &engine = *static_cast<Engine *>(opaque);
    const auto begin = Clock::now();
    cv::Mat source(height, width, channels == 4 ? CV_8UC4 : CV_8UC3, const_cast<uint8_t *>(pixels));
    cv::Mat bgr;
    cv::cvtColor(source, bgr, channels == 4 ? cv::COLOR_RGBA2BGR : cv::COLOR_RGB2BGR);
    const double effective_exposure =
      engine.lock_tuner.effective_exposure(engine.requested_exposure_multiplier);
    if (std::abs(effective_exposure - 1.0) > 1e-6) {
      bgr.convertTo(bgr, -1, effective_exposure);
    }
    if (std::abs(engine.simulation.gamma - 1.0) > 1e-6) {
      cv::LUT(bgr, engine.gamma_lut, bgr);
    }
    const LumaSummary luma = sample_luma(bgr);

    const Eigen::Quaterniond rotation = to_sp_quaternion(qx, qy, qz, qw);
    engine.solver->set_R_gimbal2world(rotation);
    engine.tracker->set_image_size(width, height);
    auto armors = engine.detector->detect(bgr);
    if (armors.empty()) {
      // Godot lightbar rendering differs from physical RM photos; YOLO often
      // misses. Fall back to a color-pair sim detector so multi-robot fusion
      // and the closed loop remain exercisable in simulation.
      const std::string enemy =
        (engine.tag.size() > 0 && engine.tag[0] == 'R') ? "blue" : "red";
      armors = sp_sim::detect_sim_armors(bgr, enemy, engine.simulation.min_confidence);
    }
    // Final sim assist: when Godot provides ground-truth armor pose, reproject a
    // synthetic armor so tracker/planner/fusion still close the loop.
    if (armors.empty() && engine.truth_valid && engine.truth_world.allFinite() &&
        engine.truth_world.norm() > 0.2) {
      const auto_aim::Color color =
        (engine.tag.size() > 0 && engine.tag[0] == 'R') ? auto_aim::Color::blue
                                                       : auto_aim::Color::red;
      const double yaw = tools::eulers(
        engine.solver->R_gimbal2world(), 2, 1, 0)[0];
      auto pts = engine.solver->reproject_armor(
        engine.truth_world, yaw, auto_aim::ArmorType::small, auto_aim::ArmorName::one);
      if (pts.size() == 4) {
        bool all_ok = true;
        for (const auto & p : pts) {
          if (!std::isfinite(p.x) || !std::isfinite(p.y)) all_ok = false;
        }
        if (all_ok) {
          float min_x = pts[0].x, max_x = pts[0].x, min_y = pts[0].y, max_y = pts[0].y;
          for (const auto & p : pts) {
            min_x = std::min(min_x, p.x);
            max_x = std::max(max_x, p.x);
            min_y = std::min(min_y, p.y);
            max_y = std::max(max_y, p.y);
          }
          const cv::Rect box(
            static_cast<int>(min_x), static_cast<int>(min_y),
            std::max(1, static_cast<int>(max_x - min_x)),
            std::max(1, static_cast<int>(max_y - min_y)));
          const int color_id = (color == auto_aim::Color::blue) ? 0 : 1;
          armors.push_back(
            auto_aim::Armor(color_id, /*num_id=*/2, 0.85f, box, pts));
        }
      }
    }
    const auto detected = Clock::now();
    const auto timestamp = Clock::time_point(std::chrono::microseconds(timestamp_usec));
    auto targets = engine.tracker->track(armors, timestamp);
    const auto tracked = Clock::now();
    auto_aim::Plan plan{};
    const std::optional<auto_aim::Target> target = targets.empty()
      ? std::nullopt
      : std::optional<auto_aim::Target>{targets.front()};
    plan = engine.planner->plan(target, bullet_speed);
    plan.fire = plan.fire && engine.simulation.auto_fire != 0;
    const bool planner_debug_valid = plan.control && !targets.empty() &&
                                     engine.planner->debug_xyza.allFinite();
    const Eigen::Vector4d planner_debug_xyza = planner_debug_valid
      ? engine.planner->debug_xyza
      : Eigen::Vector4d::Zero();
    const Eigen::Vector3d gimbal_ypr = tools::eulers(rotation, 2, 1, 0);
    const auto planned = Clock::now();
    const std::string tracker_state = engine.tracker->state();
    const double process_ms = elapsed_ms(planned, begin);
    const double capture_gap_ms = engine.previous_capture_timestamp_usec > 0
      ? std::max(0.0, (timestamp_usec - engine.previous_capture_timestamp_usec) / 1000.0)
      : 0.0;
    engine.previous_capture_timestamp_usec = timestamp_usec;
    engine.lock_tuner.observe(
      static_cast<int>(armors.size()), tracker_state, process_ms, capture_gap_ms,
      luma.median, luma.p90, luma.saturated_fraction,
      engine.requested_exposure_multiplier, engine.simulation.camera_fps);
    const auto & tuner = engine.lock_tuner.telemetry();

    if (engine.truth_valid) {
      const Eigen::Vector3d truth_ypd = tools::xyz2ypd(engine.truth_world);
      ScopeSample sample;
      sample.truth_yaw = truth_ypd[0] * RAD_TO_DEG;
      sample.truth_pitch = -truth_ypd[1] * RAD_TO_DEG;
      sample.gimbal_yaw = gimbal_ypr[0] * RAD_TO_DEG;
      // sp_vision Euler +Y and Planner pitch are both positive downward.
      sample.gimbal_pitch = gimbal_ypr[1] * RAD_TO_DEG;
      if (!targets.empty()) {
        const Eigen::VectorXd tracked_state = targets.front().ekf_x();
        const Eigen::Vector3d tracked_xyz(tracked_state[0], tracked_state[2], tracked_state[4]);
        const Eigen::Vector3d tracked_ypd = tools::xyz2ypd(tracked_xyz);
        sample.tracked_yaw = tracked_ypd[0] * RAD_TO_DEG;
        sample.tracked_pitch = -tracked_ypd[1] * RAD_TO_DEG;
        sample.vision_yaw_error = wrap_degrees(sample.tracked_yaw - sample.truth_yaw);
        sample.vision_pitch_error = wrap_degrees(sample.tracked_pitch - sample.truth_pitch);
      }
      if (plan.control) {
        sample.command_yaw = plan.yaw * RAD_TO_DEG;
        sample.command_pitch = plan.pitch * RAD_TO_DEG;
        sample.aim_yaw_error = wrap_degrees(sample.command_yaw - sample.truth_yaw);
        sample.aim_pitch_error = wrap_degrees(sample.command_pitch - sample.truth_pitch);
        sample.tracking_yaw_error = wrap_degrees(sample.gimbal_yaw - sample.command_yaw);
        sample.tracking_pitch_error = wrap_degrees(sample.gimbal_pitch - sample.command_pitch);
        if (std::isfinite(sample.tracked_yaw)) {
          sample.lead_yaw_delta = wrap_degrees(sample.command_yaw - sample.tracked_yaw);
          sample.lead_pitch_delta = wrap_degrees(sample.command_pitch - sample.tracked_pitch);
        }
      }
      engine.scope_samples.emplace_back(sample);
      while (engine.scope_samples.size() > 300) engine.scope_samples.pop_front();
    }

    if (engine.external_gui) {
      ++engine.debug_frame_count;
      cv::Mat detection_snapshot = bgr.clone();
      int armor_index = 0;
      for (const auto & armor : armors) {
        tools::draw_points(detection_snapshot, armor.points, {0, 255, 0});
        cv::putText(
          detection_snapshot,
          cv::format(
            "#%d %.2f %s", armor_index++, armor.confidence,
            auto_aim::ARMOR_NAMES[armor.name].c_str()),
          armor.center, cv::FONT_HERSHEY_SIMPLEX, 0.55, {0, 255, 0}, 1, cv::LINE_AA);
      }
      if (engine.debug_frame_count % 15 == 0) {
        cv::imwrite(
          (std::filesystem::temp_directory_path() /
           ("sp_vision_detection_" + engine.tag + ".png")).string(), detection_snapshot);
      }
      cv::Mat reprojection = bgr.clone();
      if (!targets.empty()) {
        const auto & target = targets.front();
        for (const Eigen::Vector4d & xyza : target.armor_xyza_list()) {
          const auto points = engine.solver->reproject_armor(
            xyza.head<3>(), xyza[3], target.armor_type, target.name);
          tools::draw_points(reprojection, points, {0, 255, 0});
        }
        if (planner_debug_valid) {
          const auto & aim = planner_debug_xyza;
          const auto points = engine.solver->reproject_armor(
            aim.head<3>(), aim[3], target.armor_type, target.name);
          tools::draw_points(reprojection, points, {0, 0, 255});
        }
      }
      cv::putText(
        reprojection, "[" + engine.tracker->state() + "]", {10, 30},
        cv::FONT_HERSHEY_SIMPLEX, 0.8, {255, 255, 255}, 2, cv::LINE_AA);
      cv::resize(reprojection, reprojection, {}, 0.5, 0.5);
      cv::imshow("reprojection_" + engine.tag, reprojection);
      if (engine.debug_frame_count % 15 == 0) {
        cv::imwrite(
          (std::filesystem::temp_directory_path() /
           ("sp_vision_reprojection_" + engine.tag + ".png")).string(), reprojection);
      }
      show_aim_scope(engine);
      cv::waitKey(1);
    }

    std::memset(result, 0, sizeof(*result));
    result->valid = plan.control;
    result->control = plan.control;
    result->shoot = plan.fire;
    result->yaw = plan.yaw;
    result->pitch = plan.pitch;
    result->yaw_velocity_rad_s = plan.yaw_vel;
    result->yaw_acceleration_rad_s2 = plan.yaw_acc;
    result->pitch_velocity_rad_s = plan.pitch_vel;
    result->pitch_acceleration_rad_s2 = plan.pitch_acc;
    result->armor_count = static_cast<int>(armors.size());
    result->capture_timestamp_usec = timestamp_usec;
    result->result_timestamp_usec = now_usec();
    result->detect_ms = elapsed_ms(detected, begin);
    result->track_ms = elapsed_ms(tracked, detected);
    result->aim_ms = elapsed_ms(planned, tracked);
    result->total_ms = process_ms;
    result->effective_exposure = effective_exposure;
    result->lock_quality = tuner.lock_quality;
    result->suggested_capture_hz = tuner.suggested_capture_hz;
    std::snprintf(
      result->tracker_state, sizeof(result->tracker_state), "%s", tracker_state.c_str());
    std::snprintf(
      result->tuner_state, sizeof(result->tuner_state), "%s", tuner.state.c_str());
    if (!targets.empty()) {
      const Eigen::VectorXd state = targets.front().ekf_x();
      set_godot_vector(
        result->target_x, result->target_y, result->target_z,
        Eigen::Vector3d(state[0], state[2], state[4]));
    }
    if (planner_debug_valid) {
      set_godot_vector(
        result->aim_x, result->aim_y, result->aim_z,
        planner_debug_xyza.head<3>());
    }
    return 1;
  } catch (const std::exception &exception) {
    set_error(error, error_size, exception.what());
    return 0;
  }
}

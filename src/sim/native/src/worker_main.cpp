#include "engine_api.hpp"
#include "shared_target_board.hpp"

#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>
#include <unistd.h>

namespace {

constexpr int PROTOCOL_INPUT = 100;
constexpr int PROTOCOL_OUTPUT = 101;

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

// One isolated engine per robot_id (detector/solver/tracker/planner state).
// Compatible with prebuilt libsp_vision_engine.so that exposes sp_engine_create
// but may not export sp_engine_load_simulation_config.
class EnginePool {
public:
  EnginePool(std::string config, int gui_robot)
  : config_(std::move(config)), gui_robot_(gui_robot) {}

  ~EnginePool()
  {
    for (auto &entry : engines_) sp_engine_destroy(entry.second);
  }

  void *acquire(int robot_id, int team, char *error, std::size_t error_size)
  {
    const auto it = engines_.find(robot_id);
    if (it != engines_.end()) return it->second;
    const std::string tag = (team == SP_TEAM_RED ? "R" : "B") + std::to_string(robot_id);
    const int enable_gui = (robot_id == gui_robot_) ? 1 : 0;
    void *engine =
      sp_engine_create(config_.c_str(), tag.c_str(), team, enable_gui, error, error_size);
    if (engine != nullptr) engines_.emplace(robot_id, engine);
    return engine;
  }

  // Boot a throwaway red engine just to read SpSimulationConfig defaults.
  bool load_hello_config(SpSimulationConfig *config, char *error, std::size_t error_size)
  {
    void *engine = sp_engine_create(config_.c_str(), "boot", SP_TEAM_RED, 0, error, error_size);
    if (engine == nullptr) return false;
    const int ok = sp_engine_get_simulation_config(engine, config);
    sp_engine_destroy(engine);
    if (!ok) {
      std::snprintf(error, error_size, "sp_engine_get_simulation_config failed");
      return false;
    }
    return true;
  }

private:
  std::string config_;
  int gui_robot_;
  std::unordered_map<int, void *> engines_;
};

}  // namespace

int main(int argc, char **argv)
{
  SpWorkerHello hello{};
  if (argc < 2) {
    std::snprintf(
      hello.message, sizeof(hello.message),
      "usage: sp_vision_worker <config> [--gui [robot_id]] [--runtime <yaml>]");
    write_all(PROTOCOL_OUTPUT, &hello, sizeof(hello));
    return 2;
  }

  int gui_robot = -1;
  std::string effective_config = argv[1];
  for (int i = 2; i < argc; ++i) {
    const std::string_view argument(argv[i]);
    if (argument == "--gui") {
      gui_robot = 0;
      if (i + 1 < argc && argv[i + 1][0] != '-') gui_robot = std::atoi(argv[++i]);
    } else if (argument == "--runtime" && i + 1 < argc) {
      ++i;  // optional; model paths live in base config
    } else {
      std::snprintf(hello.message, sizeof(hello.message), "invalid worker argument");
      write_all(PROTOCOL_OUTPUT, &hello, sizeof(hello));
      return 2;
    }
  }

  char error[512]{};
  EnginePool pool(effective_config, gui_robot);
  hello.ok = pool.load_hello_config(&hello.simulation, error, sizeof(error)) ? 1 : 0;
  std::snprintf(
    hello.message, sizeof(hello.message), "%s",
    hello.ok ? "OpenVINO CPU auto-aim worker ready (multi-robot)" : error);
  if (!write_all(PROTOCOL_OUTPUT, &hello, sizeof(hello)) || !hello.ok) {
    return hello.ok ? 0 : 3;
  }

  while (true) {
    SpFrameHeader header{};
    if (!read_all(PROTOCOL_INPUT, &header, sizeof(header))) break;
    SpWorkerReply reply{};
    reply.robot_id = header.robot_id;
    if (
      header.magic != SP_FRAME_MAGIC || header.width <= 0 || header.height <= 0 ||
      header.robot_id < 0 || header.robot_id >= SP_MAX_ROBOTS ||
      (header.channels != 3 && header.channels != 4) ||
      header.pixel_bytes != static_cast<uint64_t>(header.width) * header.height * header.channels) {
      std::snprintf(reply.error, sizeof(reply.error), "invalid frame header");
      write_all(PROTOCOL_OUTPUT, &reply, sizeof(reply));
      break;
    }

    std::vector<uint8_t> pixels(header.pixel_bytes);
    if (!read_all(PROTOCOL_INPUT, pixels.data(), pixels.size())) break;

    void *engine = pool.acquire(header.robot_id, header.team, reply.error, sizeof(reply.error));
    if (engine == nullptr) {
      write_all(PROTOCOL_OUTPUT, &reply, sizeof(reply));
      continue;
    }
    if (!sp_engine_set_camera_state(engine, &header.camera)) {
      std::snprintf(reply.error, sizeof(reply.error), "invalid camera state");
    } else {
      sp_engine_set_ground_truth(
        engine, header.truth_valid, header.truth_x, header.truth_y, header.truth_z);
      reply.ok = sp_engine_process(
 engine, pixels.data(), header.width, header.height, header.channels,
 header.qx, header.qy, header.qz, header.qw, header.timestamp_usec, header.bullet_speed,
 &reply.result, reply.error, sizeof(reply.error));
 if (reply.ok) {
        // Engine targets are robot-centric (origin at gimbal, world-oriented axes).
        // Convert to Godot absolute world before cross-robot sharing/fusion.
        const bool has_local_target =
          (reply.result.target_x != 0.0f || reply.result.target_y != 0.0f ||
           reply.result.target_z != 0.0f) ||
          reply.result.control != 0;
        float local_conf = 0.0f;
        if (reply.result.lock_quality > 0.0) {
          local_conf = static_cast<float>(std::min(1.0, reply.result.lock_quality));
        } else if (reply.result.armor_count > 0) {
          local_conf = 0.6f;
        } else if (has_local_target) {
          local_conf = 0.4f;
        }
        const float abs_tx = header.self_x + reply.result.target_x;
        const float abs_ty = header.self_y + reply.result.target_y;
        const float abs_tz = header.self_z + reply.result.target_z;
        if (has_local_target && local_conf > 0.0f) {
          sp_sim::SharedObservation obs;
          obs.valid = true;
          obs.robot_id = header.robot_id;
          obs.team = header.team;
          obs.self_x = header.self_x;
          obs.self_y = header.self_y;
          obs.self_z = header.self_z;
          obs.target_x = abs_tx;
          obs.target_y = abs_ty;
          obs.target_z = abs_tz;
          obs.confidence = local_conf;
          obs.timestamp_usec = header.timestamp_usec;
          sp_sim::SharedTargetBoard::instance().publish(obs);
        }
        const auto fusion = sp_sim::SharedTargetBoard::instance().fuse(
          header.robot_id, header.team, header.self_x, header.self_y, header.self_z,
          header.timestamp_usec, has_local_target && local_conf > 0.0f,
          abs_tx, abs_ty, abs_tz, local_conf);
        sp_sim::apply_fusion_to_result(&reply.result, fusion, true);
      }
    }
    if (!write_all(PROTOCOL_OUTPUT, &reply, sizeof(reply))) break;
  }

  return 0;
}

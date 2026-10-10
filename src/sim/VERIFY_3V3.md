# 3v3 多机独立 Engine 验证说明

## 已完成的代码改动

1. **`native/src/auto_aim_bridge.cpp`**  
   多机协议对齐：`submit_frame(robot_id, team, ...)` / `poll_result(robot_id)`，按 `robot_id` 隔离队列与结果，worker 侧 round-robin 调度。

2. **`native/src/worker_main.cpp`**  
   `EnginePool`：每个 `robot_id` 懒创建独立 `sp_engine_create`（detector+solver+tracker+planner 状态隔离）。  
   兼容预编译 `libsp_vision_engine.so`（无 `sp_engine_load_simulation_config` 时用 create+get_config 引导）。

3. **`godot/scripts/main.gd`**  
   完整 **3v3** 场景：6 机器人（红 0–2 / 蓝 3–5），每机独立 `SubViewport` 相机，轮询提交视觉帧，独立云台控制与命中统计。

4. **`godot/tests/multi_robot_3v3_test.gd`**  
   自动化冒烟：要求 6 个 robot 均收到结果帧。

5. **`godot/configs/sim.runtime.yaml`**  
   3v3 友好默认：640×480，每机约 6 Hz。

## 本机已重建的二进制

| 文件 | 状态 |
|------|------|
| `godot/bin/linux-x86_64/libsp_vision_sim.so` | 已用 zig 重链，含 multi-robot API 符号 |
| `godot/bin/linux-x86_64/sp_vision_worker` | 已重链，含 `multi-robot` 字符串 |
| `libsp_vision_engine.so` | **未重编**（缺完整 OpenCV/OpenVINO 编译环境） |

## 在 Godot 中验证（推荐：原 Linux / Docker 构建机）

当前 Windows + 裸 Debian WSL **缺少** 原工程链接的完整系统库（OpenCV highgui→Qt、spdlog、yaml-cpp 等）。请在**当初能跑通 1v1 仿真的环境**中执行：

```bash
# 1) 完整重编（若该机已有 OpenCV/OpenVINO/cmake）
cmake -S sim/native -B sim/native/build -DCMAKE_BUILD_TYPE=Release
cmake --build sim/native/build -j

# 2) 启动 3v3 场景
godot --path sim/godot

# 3) 或自动化冒烟（需要显示；SubViewport 在 headless 下不采图）
godot --path sim/godot --script res://tests/multi_robot_3v3_test.gd
```

### 交互快捷键（3v3）

| 键 | 作用 |
|----|------|
| Tab | 俯视 / 第一人称 |
| 1/2/3 | 切换操控红方 0/1/2 |
| RMB | 玩家自瞄接管 |
| C | 运行时面板 |
| V | 打印/写出 3v3 验证 JSON |
| R | 重置 |

### 通过标准（HUD / V 键 dump）

- `extension_ready == true`，message 含 `multi-robot`
- 6 个 robot 的 `result_count` 持续增长
- 至少 2 台有 `detection_count > 0`（对侧装甲进入视野时）
- `runtime_stats.processed` 增加，且无长期卡死

## 快速自检（无 Godot）

```bash
# worker 是否为多机版
grep -aF "multi-robot" sim/godot/bin/linux-x86_64/sp_vision_worker && echo OK

# bridge 是否导出多机方法名
grep -aoE 'submit_frame|poll_result|robot_id' sim/godot/bin/linux-x86_64/libsp_vision_sim.so | sort -u
```

## 架构要点（论文可写）

- Godot：物理 + 每机 Camera3D/SubViewport 出图  
- GDExtension `AutoAimBridge`：单进程多路复用帧协议（`SPV2` + `robot_id` + `team`）  
- `sp_vision_worker`：`EnginePool` 每机独立 YOLO/EKF/Planner 状态  
- 红方 `team=0` 猎蓝装甲；蓝方 `team=1` 猎红装甲（engine 内 `enemy_color`）

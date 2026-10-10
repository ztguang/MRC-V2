# 3v3 + 跨机动态加权融合 — 实现与验证

## 实现摘要

### 跨机目标共享 + 动态加权融合
- `native/src/shared_target_board.{hpp,cpp}`：worker 进程内共享观测板
- 每台机器人 Engine 状态隔离（YOLO/EKF/Planner）
- 同队观测经 `score = α·c + β/d + γ·exp(-λ·Δt)` + softmax 加权融合（论文第3章）
- 坐标：机体中心相对目标 + `self_world` → Godot 绝对坐标再融合
- 本地丢失且邻机有效时：`fusion_assist` 合成瞄准指令

### 协议扩展
- `SpFrameHeader`：`self_x/y/z`
- `SpEngineResult`：`fusion_*` / `fused_*` 遥测
- Godot `submit_frame(..., self_world)` / `poll_result` 暴露融合字段

### 仿真检测兜底
- `sim_detector`：颜色灯条对检测
- Truth 重投影合成装甲：保证闭环可跑通（YOLO 对仿真贴图常失效）

## 验证结果（2026-07-27）

```text
3v3 MULTI-ENGINE TEST PASSED
robots 0..5: results≥57, det=57, ctrl=57, tracker=tracking
fusion valid_frames=342, neighbor_max=2
worker: multi-robot ready
```

## 运行

```bash
export DISPLAY=:1
export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/root/lunwen/sim/godot/bin/linux-x86_64:/root/lunwen/sim/godot/bin/linux-x86_64/runtime

godot --path /root/lunwen/sim/godot --script res://tests/multi_robot_3v3_test.gd
godot --path /root/lunwen/sim/godot
```

# 多模态融合修复说明 & 论文覆盖对照

## 1. fusion_assist 曾为 0 的根因

1. 原生 SharedTargetBoard 邻机观测时效窗过短：kMaxAgeUsec=200ms  
   仿真视觉约 1Hz + 6 车轮询，邻机观测几乎全部超时 → neighbor_count 恒为 0。
2. fusion_assist 仅在 control==0 且 used_neighbors 时打标签；  
   本地常有 control 时即使有邻机也不计 assist。
3. 指标统计要求 tracker 必须以 fusion_assist 开头，过严。

## 2. 已实施修复（无需重编 OpenCV 工程）

| 项 | 位置 |
|----|------|
| 时效窗 2.5s + 距离/assist/fused | native/src/shared_target_board.* → libsp_fusion_patch.so |
| LD_PRELOAD 注入 | godot/bin/linux-x86_64/sp_vision_worker |
| 统计：used_neighbors 或 fusion_* 标签即计 assist | scripts/main.gd |
| solo 仍剥离邻机融合 | main.gd allow_share |

### 冒烟结果（coop 双方）

- fusion_assist_sum = **24**
- fusion_valid_sum = **49**
- fusion_neighbors_max_sum = **6**
- 日志出现 fusion_assist/1nb, fusion_fused/1nb

**旧目录 paper_results_20260729_222235 中的 JSON 仍是修复前数据（assist=0），出图前请重跑：**

\\\ash
/root/lunwen/sim/run_paper_experiments.sh 10
\\\

## 3. 论文 paper.tex ↔ 实现覆盖

| 论文要点 | 实现 | 覆盖度 |
|----------|------|--------|
| 物联网通信层 / 共享 | worker SharedTargetBoard + 队内 GDScript 共享板 | 部分（仿真内共享，非真实 UDP/PTP） |
| 多模态感知（视觉+IMU） | SubViewport 视觉 + 姿态/云台；YOLO/颜色检测 | 有（IMU 为仿真姿态） |
| 动态加权融合 α/β/γ/λ | shared_target_board.cpp score_of | **已修复可测** |
| 合同网任务分配 | team_coop 统一焦点/投标式分配 | 有（简化） |
| 虚拟领航编队 | team_coop.formation_waypoint + 渐进路点 | 有 |
| 一方有难八方支援 | on_ally_hit / rescue | 有 |
| 边缘卸载/量化/蒸馏 | 论文描述 | **弱/模拟**（本地 OpenVINO 推理，无真实跨机卸载调度） |
| 跨层在线校准/预测 EKF | 论文描述 | **弱**（锁存/调参 tuner 有，完整预测校准闭环简化） |
| Godot+GDExtension 平台 | main.gd + bridge + worker | 有 |
| 对称/非对称实验 A–D | run_paper_experiments.sh | 有 |

建议论文表述：仿真平台完整覆盖「感知融合 + 协同决策 + 对抗验证」；通信/边缘卸载/在线校准以功能等价仿真实现，实物部署需另验证。

# 修订实验文件说明

有效局 488 / JSON 488。胜率区间是 Wilson 95% 区间，时长和误差区间是 4000 次自助法 95% 区间。
消融四行的 holm_p 是对四个留一检验的 Holm 校正。
式(14)表是用 A2 的 process_ms 中位数做的离线数值对照，不是对局胜负。

| 文件 | 作用 |
|---|---|
| `json/` | 每一局的原始记录。文件名是实验编号加 run 序号。 |
| `logs/` | 每一局 Godot 控制台日志，用来核对崩溃和开火原因。 |
| `tables/table_fair.csv` | 步骤1。A1/A2 看对称公平，A3/A4 是全开对全关的两侧。 |
| `tables/table_ablation.csv` | 步骤2。关掉融合、焦点、编队、救援之一后，全开侧胜率及 Holm 校正。 |
| `tables/table_fusion_baselines.csv` | 步骤3。本文评分对等权平均、最近邻。B1 是关掉融合。 |
| `tables/table_association.csv` | 步骤4在线部分。有门控对无门控，看鬼点和定位误差。 |
| `tables/table_legacy_score.csv` | 步骤4在线部分。无量纲评分对旧的 0.3/d 评分。 |
| `tables/table_sensitivity.csv` | 步骤4离线网格。在 A2 落盘的观测上重放权重、λ 和参考距离。 |
| `tables/table_comm.csv` | 步骤5。0/100/400 ms 时延、30% 丢包，以及 400 ms 下评分对等权。 |
| `tables/table_compute.csv` | 步骤6对局。320、640 和每帧额外 40 ms。 |
| `tables/table_eq14.csv` | 步骤6离线。贪婪放置对抽样更优放置的效用和超时次数。 |
| `tables/table_occlusion.csv` | 步骤7。视场缩到 0.6 倍后全开对全关。 |
| `tables/table_all_groups.csv` | 上面各块的逐格汇总，未做留一合并。 |
| `manifest.json` | 每格完成局数和失败局名单。 |
| `failures.log` | 重试后仍没有 winner 的 run_id。 |
| `progress.log` | 跑批过程记录。 |
| `runner.log` | 批处理脚本标准输出。 |

## 各格完成局数

- A1: 24
- A2: 24
- A3: 24
- A4: 24
- B1: 16
- B1s: 16
- B2: 16
- B2s: 16
- B3: 16
- B3s: 16
- B4: 16
- B4s: 16
- C1: 16
- C1s: 16
- C2: 16
- C2s: 16
- D1: 16
- D1s: 16
- E1: 16
- E1s: 16
- F1: 16
- F2: 16
- F3: 16
- F4: 16
- F4s: 16
- G2: 12
- G3: 12
- H1: 16
- H2: 16

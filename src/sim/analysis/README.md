# 论文实验自动化说明

## 1. 全自动跑 4×10 局

```bash
/root/lunwen/sim/run_paper_experiments.sh 10
```

结果目录示例：

```
/root/lunwen/sim/godot/logs/paper_results_YYYYMMDD_HHMMSS/
  expA_solo_both/expA_solo_both_run01.json ... run10.json
  expB_coop_both/...
  expC_red_solo_blue_coop/...
  expD_red_coop_blue_solo/...
  logs/*.log
  manifests/runs_manifest.csv
  manifests/all_runs.csv
  manifests/all_runs.json
```

软链接：`/root/lunwen/sim/godot/logs/latest_paper_results`

## 2. 生成论文图表（手动）

```bash
# 可选：安装更好看的 PNG/PDF 输出
pip3 install matplotlib --user

python3 /root/lunwen/sim/analysis/plot_exp1_symmetric.py
python3 /root/lunwen/sim/analysis/plot_exp2_asymmetric.py
python3 /root/lunwen/sim/analysis/plot_exp3_mechanism.py

# 或一次全跑
python3 /root/lunwen/sim/analysis/plot_all.py
```

可显式指定结果目录：

```bash
python3 /root/lunwen/sim/analysis/plot_all.py /root/lunwen/sim/godot/logs/paper_results_XXXX
```

图表输出在：`<results>/figures/exp1_symmetric|exp2_asymmetric|exp3_mechanism/`

## 3. 文件命名

| 组 | 含义 | 文件名模式 |
|----|------|------------|
| A | 双方无协同 | `expA_solo_both_run01.json` … `run10.json` |
| B | 双方有协同 | `expB_coop_both_run01.json` … |
| C | 红solo 蓝coop | `expC_red_solo_blue_coop_run01.json` … |
| D | 红coop 蓝solo | `expD_red_coop_blue_solo_run01.json` … |

每局至少 1 个 JSON（论文数据主文件）；完整控制台日志在 `logs/` 下同名 `.log`。

#!/usr/bin/env python3
"""
plot_all_2.py — 生成论文用 3 张组合图（避免红/蓝柱色，防止误读为红蓝队）

输出（默认到 paper_results_.../figures/）：
  exp1_symmetric.png  — 对称基线 A vs B（4 子图）
  exp2_asymmetric.png — 非对称消融 C/D（4 子图）
  exp3_mechanism.png  — 机制证据（4 子图）

用法：
  /root/lunwen/sim/analysis/.venv/bin/python plot_all_2.py \\
      /root/lunwen/sim/godot/logs/paper_results_20260730_122316
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from statistics import mean, stdev
from typing import Any, Dict, List, Optional

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib import font_manager as _fm

# Register CJK fonts for Chinese labels
for _fp in (
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
):
    if Path(_fp).exists():
        try:
            _fm.fontManager.addfont(_fp)
        except Exception:
            pass

# 非红非蓝配色（避免读者误以为是红/蓝队）
C_A = "#5B8C5A"       # 苔绿 — A
C_B = "#C47B2C"       # 琥珀 — B
C_C = "#6B5B95"       # 紫灰 — C
C_D = "#8B6B4A"       # 赭石 — D
C_MUTE = "#7A7A7A"
C_TEAL = "#3D8B8B"
C_OLIVE = "#8A9A5B"
C_PLUM = "#8E5A7A"
C_SAND = "#B8956C"

plt.rcParams.update({
    "font.sans-serif": [
        "Noto Sans CJK SC",
        "Noto Sans CJK JP",
        "WenQuanYi Micro Hei",
        "DejaVu Sans",
    ],
    "axes.unicode_minus": False,
    "figure.dpi": 150,
    "savefig.dpi": 220,
    "axes.titlesize": 19,
    "axes.labelsize": 19,
    "xtick.labelsize": 19,
    "ytick.labelsize": 19,
    "legend.fontsize": 19,
})


def load_group(root: Path, folder: str) -> List[Dict[str, Any]]:
    rows = []
    d = root / folder
    for p in sorted(d.glob("*.json")):
        try:
            r = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        if r.get("error") or r.get("winner") is None or r.get("sim_time") is None:
            continue
        rows.append(r)
    return rows


def fnum(x, default=0.0) -> float:
    try:
        return float(x) if x is not None else default
    except Exception:
        return default


def mstd(xs: List[float]):
    if not xs:
        return 0.0, 0.0
    if len(xs) == 1:
        return xs[0], 0.0
    return mean(xs), stdev(xs)


def bar_with_err(ax, labels, means, stds, colors, title, ylabel, ylim=None):
    x = np.arange(len(labels))
    bars = ax.bar(x, means, yerr=stds, capsize=3, color=colors,
                  edgecolor="#333333", linewidth=0.4, error_kw={"elinewidth": 1})
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=0)
    ax.set_title(title)
    ax.set_ylabel(ylabel)
    ax.grid(axis="y", alpha=0.28, linestyle="--")
    if ylim is not None:
        ax.set_ylim(*ylim)
    for b, m in zip(bars, means):
        ax.text(b.get_x() + b.get_width() / 2, b.get_height(),
                f"{m:.1f}", ha="center", va="bottom", fontsize=19)


def plot_exp1(A: List[dict], B: List[dict], out: Path):
    def pack(rs, key):
        return [fnum(r.get(key)) for r in rs]

    nA, nB = len(A), len(B)
    wrA = sum(1 for r in A if r.get("winner") == "red") / max(nA, 1) * 100
    wbA = sum(1 for r in A if r.get("winner") == "blue") / max(nA, 1) * 100
    wdA = 100 - wrA - wbA
    wrB = sum(1 for r in B if r.get("winner") == "red") / max(nB, 1) * 100
    wbB = sum(1 for r in B if r.get("winner") == "blue") / max(nB, 1) * 100
    wdB = 100 - wrB - wbB

    tA, tAs = mstd(pack(A, "sim_time"))
    tB, tBs = mstd(pack(B, "sim_time"))
    aA, aAs = mstd(pack(A, "overall_accuracy_pct"))
    aB, aBs = mstd(pack(B, "overall_accuracy_pct"))
    hA, hAs = mstd(pack(A, "total_hits"))
    hB, hBs = mstd(pack(B, "total_hits"))
    sA, sAs = mstd(pack(A, "total_shots"))
    sB, sBs = mstd(pack(B, "total_shots"))

    #fig, axes = plt.subplots(2, 2, figsize=(10.2, 7.6))
    fig, axes = plt.subplots(2, 2, figsize=(10.2, 11.6))
    #fig.suptitle("实验1 对称基线：双方无协同(A) vs 双方有协同(B)", fontsize=13, fontweight="bold")

    # (a) winrate grouped
    ax = axes[0, 0]
    labs = ["红方胜", "蓝方胜", "其他"]
    x = np.arange(len(labs))
    w = 0.36
    ax.bar(x - w / 2, [wrA, wbA, wdA], w, label=f"A 无协同(n={nA})", color=C_A, edgecolor="#333")
    ax.bar(x + w / 2, [wrB, wbB, wdB], w, label=f"B 有协同(n={nB})", color=C_B, edgecolor="#333")
    ax.set_xticks(x)
    ax.set_xticklabels(labs)
    ax.set_ylabel("比例 (%)")
    ax.set_ylim(0, 100)
    ax.set_title("(a) 胜负分布")
    ax.legend(loc="upper right")
    ax.grid(axis="y", alpha=0.28, linestyle="--")

    # (b) duration
    ax = axes[0, 1]
    data = [pack(A, "sim_time"), pack(B, "sim_time")]
    bp = ax.boxplot(data, tick_labels=[f"A 无协同", f"B 有协同"], showmeans=True,
                    patch_artist=True, meanprops=dict(marker="D", markerfacecolor=C_MUTE))
    for patch, c in zip(bp["boxes"], [C_A, C_B]):
        patch.set_facecolor(c)
        patch.set_alpha(0.75)
    ax.set_ylabel("对局时长 (s)")
    ax.set_title(f"(b) 对局时长分布 (μ={tA:.1f}/{tB:.1f}s)")
    ax.grid(axis="y", alpha=0.28, linestyle="--")

    # (c) accuracy
    ax = axes[1, 0]
    bar_with_err(ax, ["A 无协同", "B 有协同"], [aA, aB], [aAs, aBs],
                 [C_A, C_B], "(c) 平均总命中率", "命中率 (%)", ylim=(0, 100))

    # (d) hits/shots
    ax = axes[1, 1]
    labs = ["总命中", "总发射"]
    x = np.arange(len(labs))
    w = 0.36
    ax.bar(x - w / 2, [hA, sA], w, yerr=[hAs, sAs], capsize=3,
           label="A 无协同", color=C_A, edgecolor="#333")
    ax.bar(x + w / 2, [hB, sB], w, yerr=[hBs, sBs], capsize=3,
           label="B 有协同", color=C_B, edgecolor="#333")
    ax.set_xticks(x)
    ax.set_xticklabels(labs)
    ax.set_ylabel("平均次数")
    ax.set_title("(d) 平均总命中 / 总发射")
    ax.legend()
    ax.grid(axis="y", alpha=0.28, linestyle="--")

    fig.tight_layout(rect=[0, 0, 1, 1])
    fig.savefig(out / "exp1_symmetric.png")
    fig.savefig(out / "exp1_symmetric.pdf")
    plt.close(fig)
    print("wrote", out / "exp1_symmetric.png")


def plot_exp2(C: List[dict], D: List[dict], out: Path):
    nC, nD = len(C), len(D)
    # expected: C blue wins, D red wins
    expC = sum(1 for r in C if r.get("winner") == "blue") / max(nC, 1) * 100
    expD = sum(1 for r in D if r.get("winner") == "red") / max(nD, 1) * 100
    cswC = sum(1 for r in C if r.get("coop_side_won") or r.get("winner") == "blue") / max(nC, 1) * 100
    cswD = sum(1 for r in D if r.get("coop_side_won") or r.get("winner") == "red") / max(nD, 1) * 100

    def hit_diff(rs, coop_side):
        diffs = []
        for r in rs:
            if coop_side == "blue":
                diffs.append(fnum(r.get("blue_hits")) - fnum(r.get("red_hits")))
            else:
                diffs.append(fnum(r.get("red_hits")) - fnum(r.get("blue_hits")))
        return diffs

    dC = hit_diff(C, "blue")
    dD = hit_diff(D, "red")
    tC = [fnum(r.get("sim_time")) for r in C]
    tD = [fnum(r.get("sim_time")) for r in D]

    #fig, axes = plt.subplots(2, 2, figsize=(10.2, 7.6))
    fig, axes = plt.subplots(2, 2, figsize=(10.2, 11.6))
    #fig.suptitle("实验2 非对称消融：有协同方 vs 无协同方", fontsize=13, fontweight="bold")

    ax = axes[0, 0]
    bar_with_err(ax,
                 [f"C 蓝协同\n(n={nC})", f"D 红协同\n(n={nD})"],
                 [cswC, cswD], [0, 0],
                 [C_C, C_D],
                 "(a) 有协同侧胜率", "胜率 (%)", ylim=(0, 110))
    ax.axhline(100, color=C_MUTE, ls="--", lw=0.9, alpha=0.7)

    ax = axes[0, 1]
    bar_with_err(ax,
                 [f"C 期望蓝胜", f"D 期望红胜"],
                 [expC, expD], [0, 0],
                 [C_TEAL, C_SAND],
                 "(b) 符合理论预期的胜率", "胜率 (%)", ylim=(0, 110))

    ax = axes[1, 0]
    bp = ax.boxplot([dC, dD], tick_labels=["C", "D"], showmeans=True, patch_artist=True,
                    meanprops=dict(marker="D", markerfacecolor=C_MUTE))
    for patch, c in zip(bp["boxes"], [C_C, C_D]):
        patch.set_facecolor(c)
        patch.set_alpha(0.75)
    ax.axhline(0, color=C_MUTE, ls="--", lw=0.9)
    ax.set_ylabel("命中差 (协同 − 无协同)")
    ax.set_title(f"(c) 命中优势 (μ={mean(dC):.1f}/{mean(dD):.1f})")
    ax.grid(axis="y", alpha=0.28, linestyle="--")

    ax = axes[1, 1]
    bp = ax.boxplot([tC, tD], tick_labels=["C", "D"], showmeans=True, patch_artist=True,
                    meanprops=dict(marker="D", markerfacecolor=C_MUTE))
    for patch, c in zip(bp["boxes"], [C_OLIVE, C_PLUM]):
        patch.set_facecolor(c)
        patch.set_alpha(0.75)
    ax.set_ylabel("对局时长 (s)")
    ax.set_title(f"(d) 对局时长 (μ={mean(tC):.1f}/{mean(tD):.1f}s)")
    ax.grid(axis="y", alpha=0.28, linestyle="--")

    fig.tight_layout(rect=[0, 0, 1, 1])
    fig.savefig(out / "exp2_asymmetric.png")
    fig.savefig(out / "exp2_asymmetric.pdf")
    plt.close(fig)
    print("wrote", out / "exp2_asymmetric.png")


def plot_exp3(A, B, C, D, out: Path):
    groups = [
        ("A\n无协同", A, C_A),
        ("B\n有协同", B, C_B),
        ("C\n蓝协同", C, C_C),
        ("D\n红协同", D, C_D),
    ]

    def series(key):
        means, stds, labs, cols = [], [], [], []
        for lab, rs, col in groups:
            xs = [fnum(r.get(key)) for r in rs]
            m, s = mstd(xs)
            means.append(m)
            stds.append(s)
            labs.append(lab)
            cols.append(col)
        return labs, means, stds, cols

    #fig, axes = plt.subplots(2, 2, figsize=(10.2, 7.6))
    fig, axes = plt.subplots(2, 2, figsize=(10.2, 11.6))
    #fig.suptitle("实验3 机制证据：融合 / 集火 / 检测", fontsize=13, fontweight="bold")

    ax = axes[0, 0]
    labs, means, stds, cols = series("fusion_assist_sum")
    bar_with_err(ax, labs, means, stds, cols,
                 "(a) 多模态融合协助次数", "平均次数 / 局")
#                "(a) 多模态融合协助次数 (fusion_assist)", "平均次数 / 局")
                 
    ax = axes[0, 1]
    # focus fire: prefer log_fire_coop_focus
    labs, means, stds, cols = [], [], [], []
    for lab, rs, col in groups:
        xs = [fnum(r.get("log_fire_coop_focus", r.get("fusion_assist_sum"))) for r in rs]
        m, s = mstd(xs)
        labs.append(lab)
        means.append(m)
        stds.append(s)
        cols.append(col)
    bar_with_err(ax, labs, means, stds, cols,
                 "(b) 协同集火开火次数", "平均次数 / 局")
#                "(b) 协同集火开火次数 (coop_focus_fire)", "平均次数 / 局")

    ax = axes[1, 0]
    labs, means, stds, cols = series("detection_sum")
    bar_with_err(ax, labs, means, stds, cols,
                 "(c) 视觉检测累计", "平均次数 / 局")
#                "(c) 视觉检测累计 (detection_sum)", "平均次数 / 局")

    ax = axes[1, 1]
    fa_A = [fnum(r.get("fusion_assist_sum")) for r in A]
    fa_B = [fnum(r.get("fusion_assist_sum")) for r in B]
    bp = ax.boxplot([fa_A, fa_B], tick_labels=["A 无协同", "B 有协同"], showmeans=True,
                    patch_artist=True, meanprops=dict(marker="D", markerfacecolor=C_MUTE))
    for patch, c in zip(bp["boxes"], [C_A, C_B]):
        patch.set_facecolor(c)
        patch.set_alpha(0.75)
    ax.set_ylabel("fusion_assist / 局")
    ax.set_title("(d) A/B 融合协助次数分布")
    ax.grid(axis="y", alpha=0.28, linestyle="--")

    fig.tight_layout(rect=[0, 0, 1, 1])
    fig.savefig(out / "exp3_mechanism.png")
    fig.savefig(out / "exp3_mechanism.pdf")
    plt.close(fig)
    print("wrote", out / "exp3_mechanism.png")


def main():
    default = Path("/root/lunwen/sim/godot/logs/paper_results_20260730_122316")
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    if not root.exists():
        raise SystemExit(f"results dir not found: {root}")
    out = root / "figures"
    out.mkdir(parents=True, exist_ok=True)

    A = load_group(root, "expA_solo_both")
    B = load_group(root, "expB_coop_both")
    C = load_group(root, "expC_red_solo_blue_coop")
    D = load_group(root, "expD_red_coop_blue_solo")
    print(f"loaded A={len(A)} B={len(B)} C={len(C)} D={len(D)}")

    plot_exp1(A, B, out)
    plot_exp2(C, D, out)
    plot_exp3(A, B, C, D, out)

    # summary json for paper
    summary = {
        "results_dir": str(root),
        "n": {"A": len(A), "B": len(B), "C": len(C), "D": len(D)},
        "A_wins": {w: sum(1 for r in A if r.get("winner") == w) for w in ("red", "blue")},
        "B_wins": {w: sum(1 for r in B if r.get("winner") == w) for w in ("red", "blue")},
        "C_coop_win_rate": sum(1 for r in C if r.get("winner") == "blue") / max(len(C), 1),
        "D_coop_win_rate": sum(1 for r in D if r.get("winner") == "red") / max(len(D), 1),
        "A_sim_time_mean": mean([fnum(r.get("sim_time")) for r in A]) if A else 0,
        "B_sim_time_mean": mean([fnum(r.get("sim_time")) for r in B]) if B else 0,
        "A_acc_mean": mean([fnum(r.get("overall_accuracy_pct")) for r in A]) if A else 0,
        "B_acc_mean": mean([fnum(r.get("overall_accuracy_pct")) for r in B]) if B else 0,
        "A_fusion_assist_mean": mean([fnum(r.get("fusion_assist_sum")) for r in A]) if A else 0,
        "B_fusion_assist_mean": mean([fnum(r.get("fusion_assist_sum")) for r in B]) if B else 0,
        "C_sim_time_mean": mean([fnum(r.get("sim_time")) for r in C]) if C else 0,
        "D_sim_time_mean": mean([fnum(r.get("sim_time")) for r in D]) if D else 0,
    }
    (out / "plot_all_2_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print("ALL DONE ->", out)


if __name__ == "__main__":
    main()

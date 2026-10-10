#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
plot_all_3.py — 论文用 3 张组合图（灰度 + 填充图案；汉字宋体、英文新罗马）

相对 plot_all_2.py 的改进：
  1) 汉字使用宋体风格字体（优先 SimSun / 思源宋体 Noto Serif CJK SC）；
     纯英文字符与数字使用 Times New Roman（若无则 Liberation Serif 度量兼容替代）。
  2) 期刊黑白印刷：灰度填充 + 不同 hatch 图案区分组别，黑边线。

输出（默认到 paper_results_.../figures/）：
  exp1_symmetric.png / .pdf
  exp2_asymmetric.png / .pdf
  exp3_mechanism.png / .pdf

用法：
  /root/lunwen/sim/analysis/.venv/bin/python plot_all_3.py \\
      /root/lunwen/sim/godot/logs/paper_results_20260730_122316
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from statistics import mean, stdev
from typing import Any, Dict, List, Optional, Sequence, Tuple

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib import font_manager as _fm
from matplotlib.font_manager import FontProperties
from matplotlib.patches import Patch

# ---------------------------------------------------------------------------
# 字体：汉字宋体 / 英文 Times New Roman
# ---------------------------------------------------------------------------
_CANDIDATE_SONG = [
    # Windows / 自备
    "C:/Windows/Fonts/simsun.ttc",
    "C:/Windows/Fonts/SimSun.ttf",
    "/usr/share/fonts/truetype/fonts-japanese-mincho.ttf",
    # 思源宋体 / Noto Serif CJK（衬线宋体风格，Linux 常见）
    "/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc",
    "/usr/share/fonts/noto-cjk/NotoSerifCJK-Regular.ttc",
    "/usr/share/fonts/opentype/noto/NotoSerifCJKsc-Regular.otf",
]
_CANDIDATE_TIMES = [
    "C:/Windows/Fonts/times.ttf",
    "C:/Windows/Fonts/timesnr.ttf",
    "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman.ttf",
    "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman.ttf".replace("_", " "),
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",  # 度量兼容 Times
    "/usr/share/fonts/opentype/urw-base35/NimbusRoman-Regular.otf",
]


def _first_existing(paths: Sequence[str]) -> Optional[str]:
    for p in paths:
        if Path(p).exists():
            return p
    return None


def _register_font(path: str) -> None:
    try:
        _fm.fontManager.addfont(path)
    except Exception:
        pass


_SONG_PATH = _first_existing(_CANDIDATE_SONG)
_TIMES_PATH = _first_existing(_CANDIDATE_TIMES)

if _SONG_PATH:
    _register_font(_SONG_PATH)
if _TIMES_PATH:
    _register_font(_TIMES_PATH)

# 名称回退（系统已注册时）
_SONG_NAME_CANDIDATES = [
    "SimSun",
    "Noto Serif CJK SC",
    "Source Han Serif SC",
    "Songti SC",
    "STSong",
]
_TIMES_NAME_CANDIDATES = [
    "Times New Roman",
    "Liberation Serif",
    "Nimbus Roman",
    "Times",
]


def _resolve_family(preferred, path=None, force_family=None):
    available = {f.name for f in _fm.fontManager.ttflist}
    if force_family and force_family in available:
        return force_family, FontProperties(family=force_family)
    for n in preferred:
        if n in available:
            return n, FontProperties(family=n)
    if path:
        fp = FontProperties(fname=path)
        return fp.get_name(), fp
    return preferred[0], FontProperties(family=preferred[0])


_SONG_FAMILY, FP_SONG = _resolve_family(
    _SONG_NAME_CANDIDATES, _SONG_PATH, force_family="Noto Serif CJK SC"
)
_TIMES_FAMILY, FP_TIMES = _resolve_family(
    _TIMES_NAME_CANDIDATES, _TIMES_PATH, force_family="Times New Roman"
)

# 默认以 Times 为主（坐标刻度数字/英文）；含汉字的文本在绘制后切换为宋体
plt.rcParams.update(
    {
        "font.family": "serif",
        "font.serif": [_SONG_FAMILY, _TIMES_FAMILY, "DejaVu Serif"],
        "mathtext.fontset": "stix",  # 公式接近 Times
        "axes.unicode_minus": False,
        "figure.dpi": 150,
        "savefig.dpi": 220,
        "axes.titlesize": 19,
        "axes.labelsize": 19,
        "xtick.labelsize": 19,
        "ytick.labelsize": 19,
        "legend.fontsize": 16,
        "hatch.linewidth": 1.0,
        "hatch.color": "0.15",
        "axes.edgecolor": "0.0",
        "axes.labelcolor": "0.0",
        "xtick.color": "0.0",
        "ytick.color": "0.0",
        "text.color": "0.0",
        "axes.facecolor": "1.0",
        "figure.facecolor": "1.0",
        "savefig.facecolor": "1.0",
        "pdf.fonttype": 42,  # TrueType，便于编辑
        "ps.fonttype": 42,
    }
)

print(
    f"[plot_all_3] Song(CJK)={_SONG_FAMILY} path={_SONG_PATH}; "
    f"Times(Latin)={_TIMES_FAMILY} path={_TIMES_PATH}"
)


def _has_cjk(s: str) -> bool:
    return any("\u4e00" <= ch <= "\u9fff" for ch in (s or ""))


def apply_dual_fonts(fig: plt.Figure) -> None:
    """含汉字的文本用宋体，纯英文/数字用 Times New Roman。"""
    texts = []
    for ax in fig.axes:
        texts.append(ax.title)
        texts.append(ax.xaxis.label)
        texts.append(ax.yaxis.label)
        texts.extend(ax.get_xticklabels())
        texts.extend(ax.get_yticklabels())
        texts.extend(ax.texts)
        leg = ax.get_legend()
        if leg is not None:
            texts.extend(leg.get_texts())
            if leg.get_title() is not None:
                texts.append(leg.get_title())
    # figure-level texts (suptitle etc.)
    texts.extend(getattr(fig, "texts", []) or [])

    for t in texts:
        if t is None:
            continue
        try:
            s = t.get_text()
        except Exception:
            continue
        if not s or not str(s).strip():
            continue
        try:
            size = t.get_fontsize()
            weight = t.get_fontweight()
            fam = _SONG_FAMILY if _has_cjk(str(s)) else _TIMES_FAMILY
            t.set_fontproperties(FontProperties(family=fam, size=size, weight=weight))
        except Exception:
            pass


# ---------------------------------------------------------------------------
# 灰度 + hatch（期刊黑白印刷可区分）
# ---------------------------------------------------------------------------
# 灰度填充（由浅到深）
G_A = "0.92"
G_B = "0.70"
G_C = "0.50"
G_D = "0.32"
G_MUTE = "0.45"
G_ALT1 = "0.82"
G_ALT2 = "0.58"
G_WHITE = "1.0"
G_EDGE = "0.0"

# 填充图案
H_A = "///"
H_B = "\\\\\\"
H_C = "xxx"
H_D = "..."
H_ALT1 = "+++"
H_ALT2 = "|||"

STYLE = {
    "A": {"face": G_A, "hatch": H_A, "edge": G_EDGE},
    "B": {"face": G_B, "hatch": H_B, "edge": G_EDGE},
    "C": {"face": G_C, "hatch": H_C, "edge": G_EDGE},
    "D": {"face": G_D, "hatch": H_D, "edge": G_EDGE},
    "ALT1": {"face": G_ALT1, "hatch": H_ALT1, "edge": G_EDGE},
    "ALT2": {"face": G_ALT2, "hatch": H_ALT2, "edge": G_EDGE},
}


def _style_bars(bars, faces, hatches, edge=G_EDGE, lw=0.9):
    for b, face, hatch in zip(bars, faces, hatches):
        b.set_facecolor(face)
        b.set_edgecolor(edge)
        b.set_linewidth(lw)
        b.set_hatch(hatch)


def _style_boxplot(bp, faces, hatches, edge=G_EDGE):
    for patch, face, hatch in zip(bp["boxes"], faces, hatches):
        patch.set_facecolor(face)
        patch.set_edgecolor(edge)
        patch.set_linewidth(0.9)
        patch.set_hatch(hatch)
        patch.set_alpha(1.0)
    for key in ("whiskers", "caps", "medians"):
        for line in bp[key]:
            line.set_color(edge)
            line.set_linewidth(0.9)
    for line in bp.get("fliers", []):
        line.set_markeredgecolor(edge)
        line.set_markerfacecolor("0.7")
    for line in bp.get("means", []):
        line.set_markerfacecolor("0.2")
        line.set_markeredgecolor(edge)


def legend_handles(keys: Sequence[str], labels: Sequence[str]) -> List[Patch]:
    hs = []
    for k, lab in zip(keys, labels):
        st = STYLE[k]
        hs.append(
            Patch(
                facecolor=st["face"],
                edgecolor=st["edge"],
                hatch=st["hatch"],
                label=lab,
                linewidth=0.9,
            )
        )
    return hs


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


def bar_with_err(
    ax,
    labels,
    means,
    stds,
    faces,
    hatches,
    title,
    ylabel,
    ylim=None,
    bar_width=0.62,
):
    x = np.arange(len(labels))
    bars = ax.bar(
        x,
        means,
        yerr=stds,
        width=bar_width,
        capsize=3,
        color=faces,
        edgecolor=G_EDGE,
        linewidth=0.9,
        error_kw={"elinewidth": 1, "ecolor": "0.1", "capthick": 0.9},
    )
    _style_bars(bars, faces, hatches)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=0)
    ax.set_title(title)
    ax.set_ylabel(ylabel)
    ax.grid(axis="y", alpha=0.35, linestyle="--", color="0.5", linewidth=0.6)
    ax.set_axisbelow(True)
    if ylim is not None:
        ax.set_ylim(*ylim)
    for b, m in zip(bars, means):
        ax.text(
            b.get_x() + b.get_width() / 2,
            b.get_height(),
            f"{m:.1f}",
            ha="center",
            va="bottom",
            fontsize=16,
            color="0.0",
        )
    return bars


def _savefig(fig: plt.Figure, out: Path, stem: str) -> None:
    apply_dual_fonts(fig)
    # 灰度保险：若有任何彩色 artist 再压一次（本脚本已用灰度）
    for ax in fig.axes:
        ax.set_facecolor("white")
    png = out / f"{stem}.png"
    pdf = out / f"{stem}.pdf"
    fig.savefig(png, dpi=220, facecolor="white", edgecolor="none", bbox_inches="tight")
    fig.savefig(pdf, dpi=220, facecolor="white", edgecolor="none", bbox_inches="tight")
    plt.close(fig)
    print("wrote", png)


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

    fig, axes = plt.subplots(2, 2, figsize=(10.2, 11.6))

    # (a) winrate grouped
    ax = axes[0, 0]
    labs = ["红方胜", "蓝方胜", "其他"]
    x = np.arange(len(labs))
    w = 0.36
    b1 = ax.bar(
        x - w / 2,
        [wrA, wbA, wdA],
        w,
        label=f"A 无协同(n={nA})",
        color=STYLE["A"]["face"],
        edgecolor=G_EDGE,
        linewidth=0.9,
        hatch=STYLE["A"]["hatch"],
    )
    b2 = ax.bar(
        x + w / 2,
        [wrB, wbB, wdB],
        w,
        label=f"B 有协同(n={nB})",
        color=STYLE["B"]["face"],
        edgecolor=G_EDGE,
        linewidth=0.9,
        hatch=STYLE["B"]["hatch"],
    )
    ax.set_xticks(x)
    ax.set_xticklabels(labs)
    ax.set_ylabel("比例 (%)")
    ax.set_ylim(0, 100)
    ax.set_title("(a) 胜负分布")
    ax.legend(
        handles=legend_handles(["A", "B"], [f"A 无协同(n={nA})", f"B 有协同(n={nB})"]),
        loc="upper right",
        frameon=True,
        fancybox=False,
        edgecolor="0.3",
    )
    ax.grid(axis="y", alpha=0.35, linestyle="--", color="0.5", linewidth=0.6)
    ax.set_axisbelow(True)

    # (b) duration boxplot
    ax = axes[0, 1]
    data = [pack(A, "sim_time"), pack(B, "sim_time")]
    bp = ax.boxplot(
        data,
        tick_labels=[f"A 无协同", f"B 有协同"],
        showmeans=True,
        patch_artist=True,
        meanprops=dict(marker="D", markerfacecolor="0.2", markeredgecolor="0.0", markersize=6),
    )
    _style_boxplot(bp, [STYLE["A"]["face"], STYLE["B"]["face"]], [STYLE["A"]["hatch"], STYLE["B"]["hatch"]])
    ax.set_ylabel("对局时长 (s)")
    ax.set_title(f"(b) 对局时长分布 (μ={tA:.1f}/{tB:.1f}s)")
    ax.grid(axis="y", alpha=0.35, linestyle="--", color="0.5", linewidth=0.6)
    ax.set_axisbelow(True)

    # (c) accuracy
    ax = axes[1, 0]
    bar_with_err(
        ax,
        ["A 无协同", "B 有协同"],
        [aA, aB],
        [aAs, aBs],
        [STYLE["A"]["face"], STYLE["B"]["face"]],
        [STYLE["A"]["hatch"], STYLE["B"]["hatch"]],
        "(c) 平均总命中率",
        "命中率 (%)",
        ylim=(0, 100),
    )

    # (d) hits/shots
    ax = axes[1, 1]
    labs = ["总命中", "总发射"]
    x = np.arange(len(labs))
    w = 0.36
    ax.bar(
        x - w / 2,
        [hA, sA],
        w,
        yerr=[hAs, sAs],
        capsize=3,
        label="A 无协同",
        color=STYLE["A"]["face"],
        edgecolor=G_EDGE,
        linewidth=0.9,
        hatch=STYLE["A"]["hatch"],
        error_kw={"elinewidth": 1, "ecolor": "0.1"},
    )
    ax.bar(
        x + w / 2,
        [hB, sB],
        w,
        yerr=[hBs, sBs],
        capsize=3,
        label="B 有协同",
        color=STYLE["B"]["face"],
        edgecolor=G_EDGE,
        linewidth=0.9,
        hatch=STYLE["B"]["hatch"],
        error_kw={"elinewidth": 1, "ecolor": "0.1"},
    )
    ax.set_xticks(x)
    ax.set_xticklabels(labs)
    ax.set_ylabel("平均次数")
    ax.set_title("(d) 平均总命中 / 总发射")
    ax.legend(
        handles=legend_handles(["A", "B"], ["A 无协同", "B 有协同"]),
        frameon=True,
        fancybox=False,
        edgecolor="0.3",
    )
    ax.grid(axis="y", alpha=0.35, linestyle="--", color="0.5", linewidth=0.6)
    ax.set_axisbelow(True)

    apply_dual_fonts(fig)
    fig.tight_layout(rect=[0, 0, 1, 1])
    _savefig(fig, out, "exp1_symmetric")


def plot_exp2(C: List[dict], D: List[dict], out: Path):
    nC, nD = len(C), len(D)
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

    fig, axes = plt.subplots(2, 2, figsize=(10.2, 11.6))

    ax = axes[0, 0]
    bar_with_err(
        ax,
        [f"C 蓝协同\n(n={nC})", f"D 红协同\n(n={nD})"],
        [cswC, cswD],
        [0, 0],
        [STYLE["C"]["face"], STYLE["D"]["face"]],
        [STYLE["C"]["hatch"], STYLE["D"]["hatch"]],
        "(a) 有协同侧胜率",
        "胜率 (%)",
        ylim=(0, 110),
    )
    ax.axhline(100, color="0.35", ls="--", lw=0.9, alpha=0.9)

    ax = axes[0, 1]
    bar_with_err(
        ax,
        [f"C 期望蓝胜", f"D 期望红胜"],
        [expC, expD],
        [0, 0],
        [STYLE["ALT1"]["face"], STYLE["ALT2"]["face"]],
        [STYLE["ALT1"]["hatch"], STYLE["ALT2"]["hatch"]],
        "(b) 符合理论预期的胜率",
        "胜率 (%)",
        ylim=(0, 110),
    )

    ax = axes[1, 0]
    bp = ax.boxplot(
        [dC, dD],
        tick_labels=["C", "D"],
        showmeans=True,
        patch_artist=True,
        meanprops=dict(marker="D", markerfacecolor="0.2", markeredgecolor="0.0", markersize=6),
    )
    _style_boxplot(bp, [STYLE["C"]["face"], STYLE["D"]["face"]], [STYLE["C"]["hatch"], STYLE["D"]["hatch"]])
    ax.axhline(0, color="0.35", ls="--", lw=0.9)
    ax.set_ylabel("命中差 (协同 − 无协同)")
    ax.set_title(f"(c) 命中优势 (μ={mean(dC):.1f}/{mean(dD):.1f})")
    ax.grid(axis="y", alpha=0.35, linestyle="--", color="0.5", linewidth=0.6)
    ax.set_axisbelow(True)

    ax = axes[1, 1]
    bp = ax.boxplot(
        [tC, tD],
        tick_labels=["C", "D"],
        showmeans=True,
        patch_artist=True,
        meanprops=dict(marker="D", markerfacecolor="0.2", markeredgecolor="0.0", markersize=6),
    )
    _style_boxplot(
        bp,
        [STYLE["ALT1"]["face"], STYLE["ALT2"]["face"]],
        [STYLE["ALT1"]["hatch"], STYLE["ALT2"]["hatch"]],
    )
    ax.set_ylabel("对局时长 (s)")
    ax.set_title(f"(d) 对局时长 (μ={mean(tC):.1f}/{mean(tD):.1f}s)")
    ax.grid(axis="y", alpha=0.35, linestyle="--", color="0.5", linewidth=0.6)
    ax.set_axisbelow(True)

    apply_dual_fonts(fig)
    fig.tight_layout(rect=[0, 0, 1, 1])
    _savefig(fig, out, "exp2_asymmetric")


def plot_exp3(A, B, C, D, out: Path):
    groups = [
        ("A\n无协同", A, "A"),
        ("B\n有协同", B, "B"),
        ("C\n蓝协同", C, "C"),
        ("D\n红协同", D, "D"),
    ]

    def series(key):
        means, stds, labs, faces, hatches = [], [], [], [], []
        for lab, rs, sk in groups:
            xs = [fnum(r.get(key)) for r in rs]
            m, s = mstd(xs)
            means.append(m)
            stds.append(s)
            labs.append(lab)
            faces.append(STYLE[sk]["face"])
            hatches.append(STYLE[sk]["hatch"])
        return labs, means, stds, faces, hatches

    fig, axes = plt.subplots(2, 2, figsize=(10.2, 11.6))

    ax = axes[0, 0]
    labs, means, stds, faces, hatches = series("fusion_assist_sum")
    bar_with_err(
        ax,
        labs,
        means,
        stds,
        faces,
        hatches,
        "(a) 多模态融合协助次数",
        "平均次数 / 局",
    )

    ax = axes[0, 1]
    labs, means, stds, faces, hatches = [], [], [], [], []
    for lab, rs, sk in groups:
        xs = [fnum(r.get("log_fire_coop_focus", r.get("fusion_assist_sum"))) for r in rs]
        m, s = mstd(xs)
        labs.append(lab)
        means.append(m)
        stds.append(s)
        faces.append(STYLE[sk]["face"])
        hatches.append(STYLE[sk]["hatch"])
    bar_with_err(
        ax,
        labs,
        means,
        stds,
        faces,
        hatches,
        "(b) 协同集火开火次数",
        "平均次数 / 局",
    )

    ax = axes[1, 0]
    labs, means, stds, faces, hatches = series("detection_sum")
    bar_with_err(
        ax,
        labs,
        means,
        stds,
        faces,
        hatches,
        "(c) 视觉检测累计",
        "平均次数 / 局",
    )

    ax = axes[1, 1]
    fa_A = [fnum(r.get("fusion_assist_sum")) for r in A]
    fa_B = [fnum(r.get("fusion_assist_sum")) for r in B]
    bp = ax.boxplot(
        [fa_A, fa_B],
        tick_labels=["A 无协同", "B 有协同"],
        showmeans=True,
        patch_artist=True,
        meanprops=dict(marker="D", markerfacecolor="0.2", markeredgecolor="0.0", markersize=6),
    )
    _style_boxplot(bp, [STYLE["A"]["face"], STYLE["B"]["face"]], [STYLE["A"]["hatch"], STYLE["B"]["hatch"]])
    ax.set_ylabel("平均次数 / 局")
    ax.set_title("(d) A/B 融合协助次数分布")
    ax.grid(axis="y", alpha=0.35, linestyle="--", color="0.5", linewidth=0.6)
    ax.set_axisbelow(True)

    apply_dual_fonts(fig)
    fig.tight_layout(rect=[0, 0, 1, 1])
    _savefig(fig, out, "exp3_mechanism")


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

    summary = {
        "results_dir": str(root),
        "script": "plot_all_3.py",
        "fonts": {
            "song_family": _SONG_FAMILY,
            "song_path": _SONG_PATH,
            "times_family": _TIMES_FAMILY,
            "times_path": _TIMES_PATH,
        },
        "style": "grayscale+hatch",
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
    (out / "plot_all_3_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("ALL DONE ->", out)


if __name__ == "__main__":
    main()

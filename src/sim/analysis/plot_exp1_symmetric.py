#!/usr/bin/env python3
"""
实验1：对称基线 A vs B
  A = solo both, B = coop both
图表：
  1) 胜率（红/蓝/平）
  2) 对局时长箱线/柱状
  3) 命中率对比
  4) 总命中与总发射
输出目录：<results>/figures/exp1_symmetric/
"""
from __future__ import annotations
import sys, csv, json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from exp_common import results_root, load_runs, by_exp, fnum, mean, std, ensure_dir, try_matplotlib

def main():
    root = results_root(sys.argv[1] if len(sys.argv) > 1 else None)
    out = ensure_dir(root / "figures" / "exp1_symmetric")
    rows = load_runs(root)
    groups = by_exp(rows)
    # also key by exp_name
    A = groups.get("expA") or [r for r in rows if r.get("exp_name") == "solo_both" or (r.get("mode_red")=="solo" and r.get("mode_blue")=="solo" and r.get("exp_id") in (None,"","expA","A"))]
    B = groups.get("expB") or [r for r in rows if r.get("exp_name") == "coop_both" or (r.get("mode_red")=="coop" and r.get("mode_blue")=="coop")]
    # filter strict
    A = [r for r in rows if str(r.get("exp_id","")) in ("expA","A") or r.get("exp_name")=="solo_both"]
    B = [r for r in rows if str(r.get("exp_id","")) in ("expB","B") or r.get("exp_name")=="coop_both"]
    if not A and not B:
        # fallback modes
        A = [r for r in rows if r.get("mode_red")=="solo" and r.get("mode_blue")=="solo"]
        B = [r for r in rows if r.get("mode_red")=="coop" and r.get("mode_blue")=="coop"]

    def stats(rs, label):
        n = len(rs)
        wr = sum(1 for r in rs if r.get("winner")=="red")
        wb = sum(1 for r in rs if r.get("winner")=="blue")
        wd = sum(1 for r in rs if r.get("winner") not in ("red","blue"))
        times = [fnum(r.get("sim_time")) for r in rs]
        racc = [fnum(r.get("red_accuracy_pct")) for r in rs]
        bacc = [fnum(r.get("blue_accuracy_pct")) for r in rs]
        oacc = [fnum(r.get("overall_accuracy_pct")) for r in rs]
        rh = [fnum(r.get("red_hits")) for r in rs]
        bh = [fnum(r.get("blue_hits")) for r in rs]
        th = [fnum(r.get("total_hits")) for r in rs]
        ts = [fnum(r.get("total_shots")) for r in rs]
        fus = [fnum(r.get("fusion_assist_sum")) for r in rs]
        return {
            "label": label, "n": n,
            "win_red": wr, "win_blue": wb, "draw": wd,
            "win_red_rate": wr/n if n else 0, "win_blue_rate": wb/n if n else 0, "draw_rate": wd/n if n else 0,
            "sim_time_mean": mean(times), "sim_time_std": std(times), "sim_time": times,
            "red_acc_mean": mean(racc), "blue_acc_mean": mean(bacc), "overall_acc_mean": mean(oacc),
            "overall_acc": oacc, "total_hits_mean": mean(th), "total_shots_mean": mean(ts),
            "fusion_assist_mean": mean(fus), "fusion_assist": fus,
            "red_hits_mean": mean(rh), "blue_hits_mean": mean(bh),
        }

    sa, sb = stats(A, "A_solo_both"), stats(B, "B_coop_both")
    summary = {"A": sa, "B": sb}
    # strip long arrays for json summary table
    table = {}
    for k, s in summary.items():
        table[k] = {kk: vv for kk, vv in s.items() if kk not in ("sim_time","overall_acc","fusion_assist")}
    (out / "exp1_summary.json").write_text(json.dumps(table, ensure_ascii=False, indent=2), encoding="utf-8")

    # CSV table for paper
    with (out / "exp1_summary.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["group","n","win_red","win_blue","draw","win_red_rate","win_blue_rate",
                    "sim_time_mean","sim_time_std","overall_acc_mean","total_hits_mean",
                    "total_shots_mean","fusion_assist_mean"])
        for s in (sa, sb):
            w.writerow([s["label"], s["n"], s["win_red"], s["win_blue"], s["draw"],
                        f"{s['win_red_rate']:.3f}", f"{s['win_blue_rate']:.3f}",
                        f"{s['sim_time_mean']:.2f}", f"{s['sim_time_std']:.2f}",
                        f"{s['overall_acc_mean']:.2f}", f"{s['total_hits_mean']:.2f}",
                        f"{s['total_shots_mean']:.2f}", f"{s['fusion_assist_mean']:.2f}"])

    plt = try_matplotlib()
    if plt is None:
        print("matplotlib missing: writing SVG fallbacks only")
        _svg_bar(out / "fig1_winrate.svg", ["A-solo 红胜","A-solo 蓝胜","B-coop 红胜","B-coop 蓝胜"],
                 [sa["win_red_rate"]*100, sa["win_blue_rate"]*100, sb["win_red_rate"]*100, sb["win_blue_rate"]*100],
                 "实验1 对称基线：胜率 (%)", "胜率%")
        _svg_bar(out / "fig2_duration.svg", ["A-solo","B-coop"],
                 [sa["sim_time_mean"], sb["sim_time_mean"]],
                 "实验1 平均对局时长 (s)", "秒")
        _svg_bar(out / "fig3_accuracy.svg", ["A overall","B overall"],
                 [sa["overall_acc_mean"], sb["overall_acc_mean"]],
                 "实验1 平均命中率 (%)", "%")
        _svg_bar(out / "fig4_hits_shots.svg", ["A hits","B hits","A shots","B shots"],
                 [sa["total_hits_mean"], sb["total_hits_mean"], sa["total_shots_mean"], sb["total_shots_mean"]],
                 "实验1 平均总命中/发射", "次数")
    else:
        # 尽量启用中文字体，避免缺字警告
        plt.rcParams["font.sans-serif"] = [
            "SimHei", "Microsoft YaHei", "Noto Sans CJK SC",
            "WenQuanYi Micro Hei", "Source Han Sans SC", "DejaVu Sans",
        ]
        plt.rcParams["axes.unicode_minus"] = False
        # fig1 winrate grouped
        fig, ax = plt.subplots(figsize=(7, 4.2))
        labels = ["红胜", "蓝胜", "平局"]
        x = range(len(labels))
        w = 0.35
        ax.bar([i - w/2 for i in x], [sa["win_red_rate"]*100, sa["win_blue_rate"]*100, sa["draw_rate"]*100], w, label="A solo双方", color="#c0392b")
        ax.bar([i + w/2 for i in x], [sb["win_red_rate"]*100, sb["win_blue_rate"]*100, sb["draw_rate"]*100], w, label="B coop双方", color="#2980b9")
        ax.set_xticks(list(x)); ax.set_xticklabels(labels)
        ax.set_ylabel("比例 (%)"); ax.set_title("实验1 对称基线：胜负分布")
        ax.legend(); ax.set_ylim(0, 100); ax.grid(axis="y", alpha=0.3)
        fig.tight_layout(); fig.savefig(out / "fig1_winrate.png", dpi=200); fig.savefig(out / "fig1_winrate.pdf"); plt.close()

        fig, ax = plt.subplots(figsize=(6, 4))
        data = [sa["sim_time"], sb["sim_time"]]
        ax.boxplot(data, tick_labels=["A solo双方", "B coop双方"], showmeans=True)
        ax.set_ylabel("对局时长 (s)"); ax.set_title("实验1 对局时长分布")
        ax.grid(axis="y", alpha=0.3)
        fig.tight_layout(); fig.savefig(out / "fig2_duration.png", dpi=200); fig.savefig(out / "fig2_duration.pdf"); plt.close()

        fig, ax = plt.subplots(figsize=(6, 4))
        ax.bar(["A solo", "B coop"], [sa["overall_acc_mean"], sb["overall_acc_mean"]], color=["#c0392b", "#2980b9"])
        ax.set_ylabel("平均总命中率 (%)"); ax.set_title("实验1 命中率对比")
        ax.grid(axis="y", alpha=0.3)
        fig.tight_layout(); fig.savefig(out / "fig3_accuracy.png", dpi=200); fig.savefig(out / "fig3_accuracy.pdf"); plt.close()

        fig, ax = plt.subplots(figsize=(7, 4))
        import numpy as np
        labs = ["总命中", "总发射"]
        x = np.arange(len(labs)); w = 0.35
        ax.bar(x - w/2, [sa["total_hits_mean"], sa["total_shots_mean"]], w, label="A solo", color="#c0392b")
        ax.bar(x + w/2, [sb["total_hits_mean"], sb["total_shots_mean"]], w, label="B coop", color="#2980b9")
        ax.set_xticks(x); ax.set_xticklabels(labs)
        ax.set_ylabel("平均次数"); ax.set_title("实验1 平均总命中/发射")
        ax.legend(); ax.grid(axis="y", alpha=0.3)
        fig.tight_layout(); fig.savefig(out / "fig4_hits_shots.png", dpi=200); fig.savefig(out / "fig4_hits_shots.pdf"); plt.close()

    print("EXP1 done ->", out)
    print("A runs", len(A), "B runs", len(B))

def _svg_bar(path: Path, labels, values, title, ylab):
    w, h = 640, 400
    m = max(values) if values else 1
    m = m if m > 0 else 1
    bw = 80
    gap = 40
    left = 80
    bottom = 320
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}">',
             f'<text x="20" y="28" font-size="16">{title}</text>',
             f'<text x="12" y="180" font-size="12" transform="rotate(-90 12,180)">{ylab}</text>']
    colors = ["#c0392b", "#2980b9", "#27ae60", "#8e44ad", "#f39c12", "#16a085"]
    for i, (lab, val) in enumerate(zip(labels, values)):
        bh = (val / m) * 220
        x = left + i * (bw + gap)
        y = bottom - bh
        c = colors[i % len(colors)]
        parts.append(f'<rect x="{x}" y="{y}" width="{bw}" height="{bh}" fill="{c}"/>')
        parts.append(f'<text x="{x}" y="{bottom+18}" font-size="11">{lab}</text>')
        parts.append(f'<text x="{x}" y="{y-6}" font-size="11">{val:.2f}</text>')
    parts.append("</svg>")
    path.write_text("\n".join(parts), encoding="utf-8")

if __name__ == "__main__":
    main()

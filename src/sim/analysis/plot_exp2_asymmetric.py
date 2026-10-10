#!/usr/bin/env python3
"""
实验2：非对称消融 C & D
  C = red solo, blue coop  → 期望蓝胜
  D = red coop, blue solo  → 期望红胜
图表：
  1) 有协同侧胜率
  2) 胜负计数
  3) 命中差 (协同侧 - 无协同侧)
  4) 对局时长
"""
from __future__ import annotations
import sys, csv, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from exp_common import results_root, load_runs, fnum, mean, std, ensure_dir, try_matplotlib

def coop_hits(r):
    side = r.get("coop_side")
    if side == "red":
        return fnum(r.get("red_hits")), fnum(r.get("blue_hits"))
    if side == "blue":
        return fnum(r.get("blue_hits")), fnum(r.get("red_hits"))
    return 0.0, 0.0

def main():
    root = results_root(sys.argv[1] if len(sys.argv) > 1 else None)
    out = ensure_dir(root / "figures" / "exp2_asymmetric")
    rows = load_runs(root)
    C = [r for r in rows if str(r.get("exp_id")) in ("expC","C") or r.get("exp_name")=="red_solo_blue_coop"]
    D = [r for r in rows if str(r.get("exp_id")) in ("expD","D") or r.get("exp_name")=="red_coop_blue_solo"]
    if not C:
        C = [r for r in rows if r.get("mode_red")=="solo" and r.get("mode_blue")=="coop"]
    if not D:
        D = [r for r in rows if r.get("mode_red")=="coop" and r.get("mode_blue")=="solo"]

    def summarize(rs, label, expect_winner):
        n = len(rs)
        # coop side won
        csw = 0
        for r in rs:
            if "coop_side_won" in r:
                csw += 1 if r.get("coop_side_won") else 0
            else:
                side = r.get("coop_side")
                if side and r.get("winner") == side:
                    csw += 1
        exp_ok = sum(1 for r in rs if r.get("winner")==expect_winner)
        times = [fnum(r.get("sim_time")) for r in rs]
        diffs = []
        for r in rs:
            ch, sh = coop_hits(r)
            diffs.append(ch - sh)
        return {
            "label": label, "n": n, "expect_winner": expect_winner,
            "coop_side_wins": csw, "coop_side_win_rate": csw/n if n else 0,
            "expected_wins": exp_ok, "expected_win_rate": exp_ok/n if n else 0,
            "sim_time_mean": mean(times), "sim_time_std": std(times), "sim_time": times,
            "hit_diff_coop_minus_solo_mean": mean(diffs), "hit_diff": diffs,
            "winners": [r.get("winner") for r in rs],
        }

    sc = summarize(C, "C redSOLO blueCOOP", "blue")
    sd = summarize(D, "D redCOOP blueSOLO", "red")
    table = {k: {kk: vv for kk, vv in s.items() if kk not in ("sim_time","hit_diff","winners")} for k,s in {"C":sc,"D":sd}.items()}
    (out / "exp2_summary.json").write_text(json.dumps(table, ensure_ascii=False, indent=2), encoding="utf-8")
    with (out / "exp2_summary.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["group","n","coop_side_wins","coop_side_win_rate","expected_wins","expected_win_rate",
                    "sim_time_mean","hit_diff_coop_minus_solo_mean"])
        for s in (sc, sd):
            w.writerow([s["label"], s["n"], s["coop_side_wins"], f"{s['coop_side_win_rate']:.3f}",
                        s["expected_wins"], f"{s['expected_win_rate']:.3f}",
                        f"{s['sim_time_mean']:.2f}", f"{s['hit_diff_coop_minus_solo_mean']:.2f}"])

    plt = try_matplotlib()
    if plt is None:
        from plot_exp1_symmetric import _svg_bar
        _svg_bar(out / "fig1_coop_winrate.svg", ["C 协同胜率","D 协同胜率"],
                 [sc["coop_side_win_rate"]*100, sd["coop_side_win_rate"]*100],
                 "实验2 有协同侧胜率 (%)", "%")
        _svg_bar(out / "fig2_expected.svg", ["C 期望蓝胜","D 期望红胜"],
                 [sc["expected_win_rate"]*100, sd["expected_win_rate"]*100],
                 "实验2 符合预期胜率 (%)", "%")
        _svg_bar(out / "fig3_hit_diff.svg", ["C 命中差","D 命中差"],
                 [sc["hit_diff_coop_minus_solo_mean"], sd["hit_diff_coop_minus_solo_mean"]],
                 "实验2 协同侧-无协同侧 平均命中差", "命中")
        _svg_bar(out / "fig4_duration.svg", ["C","D"],
                 [sc["sim_time_mean"], sd["sim_time_mean"]],
                 "实验2 平均对局时长", "秒")
    else:
        # 尽量启用中文字体，避免缺字警告
        plt.rcParams["font.sans-serif"] = [
            "SimHei", "Microsoft YaHei", "Noto Sans CJK SC",
            "WenQuanYi Micro Hei", "Source Han Sans SC", "DejaVu Sans",
        ]
        plt.rcParams["axes.unicode_minus"] = False
        fig, ax = plt.subplots(figsize=(6.5, 4))
        ax.bar(["C 红solo/蓝coop", "D 红coop/蓝solo"],
               [sc["coop_side_win_rate"]*100, sd["coop_side_win_rate"]*100],
               color=["#2980b9", "#c0392b"])
        ax.axhline(100, color="gray", ls="--", alpha=0.5)
        ax.set_ylim(0, 105); ax.set_ylabel("有协同侧胜率 (%)")
        ax.set_title("实验2 非对称消融：有协同侧胜率")
        ax.grid(axis="y", alpha=0.3)
        fig.tight_layout(); fig.savefig(out/"fig1_coop_winrate.png", dpi=200); fig.savefig(out/"fig1_coop_winrate.pdf"); plt.close()

        fig, ax = plt.subplots(figsize=(6.5, 4))
        ax.bar(["C 期望蓝胜", "D 期望红胜"],
               [sc["expected_win_rate"]*100, sd["expected_win_rate"]*100],
               color=["#3498db", "#e74c3c"])
        ax.set_ylim(0, 105); ax.set_ylabel("符合理论预期的胜率 (%)")
        ax.set_title("实验2 理论预期胜负符合率")
        ax.grid(axis="y", alpha=0.3)
        fig.tight_layout(); fig.savefig(out/"fig2_expected.png", dpi=200); fig.savefig(out/"fig2_expected.pdf"); plt.close()

        fig, ax = plt.subplots(figsize=(6.5, 4))
        ax.boxplot([sc["hit_diff"], sd["hit_diff"]], tick_labels=["C", "D"], showmeans=True)
        ax.axhline(0, color="gray", ls="--")
        ax.set_ylabel("命中差 (协同 - 无协同)")
        ax.set_title("实验2 命中优势分布")
        ax.grid(axis="y", alpha=0.3)
        fig.tight_layout(); fig.savefig(out/"fig3_hit_diff.png", dpi=200); fig.savefig(out/"fig3_hit_diff.pdf"); plt.close()

        fig, ax = plt.subplots(figsize=(6.5, 4))
        ax.boxplot([sc["sim_time"], sd["sim_time"]], tick_labels=["C", "D"], showmeans=True)
        ax.set_ylabel("对局时长 (s)"); ax.set_title("实验2 对局时长")
        ax.grid(axis="y", alpha=0.3)
        fig.tight_layout(); fig.savefig(out/"fig4_duration.png", dpi=200); fig.savefig(out/"fig4_duration.pdf"); plt.close()

    print("EXP2 done ->", out, "C", len(C), "D", len(D))

if __name__ == "__main__":
    main()

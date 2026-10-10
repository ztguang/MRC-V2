#!/usr/bin/env python3
"""
实验3：机制证据（多模态共享 / 救援 / 协同开火）
对比 A(solo双方) vs B(coop双方) vs C/D(非对称中协同侧机制)
图表：
  1) fusion_assist / fusion_valid 均值
  2) rescue_events / log_coop_rescue
  3) coop_focus_fire 次数
  4) detection/control 汇总
"""
from __future__ import annotations
import sys, csv, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from exp_common import results_root, load_runs, fnum, mean, std, ensure_dir, try_matplotlib

def main():
    root = results_root(sys.argv[1] if len(sys.argv) > 1 else None)
    out = ensure_dir(root / "figures" / "exp3_mechanism")
    rows = load_runs(root)

    def pick(*keys):
        outl = []
        for r in rows:
            eid = str(r.get("exp_id",""))
            en = r.get("exp_name","")
            if eid in keys or en in keys:
                outl.append(r)
        return outl

    A = pick("expA", "A", "solo_both")
    B = pick("expB", "B", "coop_both")
    C = pick("expC", "C", "red_solo_blue_coop")
    D = pick("expD", "D", "red_coop_blue_solo")

    def mech(rs, label):
        n = len(rs)
        fa = [fnum(r.get("fusion_assist_sum")) for r in rs]
        fv = [fnum(r.get("fusion_valid_sum")) for r in rs]
        re = [fnum(r.get("rescue_events", r.get("log_coop_rescue", 0))) for r in rs]
        ff = [fnum(r.get("log_fire_coop_focus")) for r in rs]
        fr = [fnum(r.get("log_fire_coop_rescue")) for r in rs]
        det = [fnum(r.get("detection_sum")) for r in rs]
        ctrl = [fnum(r.get("control_sum")) for r in rs]
        return {
            "label": label, "n": n,
            "fusion_assist_mean": mean(fa), "fusion_assist": fa,
            "fusion_valid_mean": mean(fv), "fusion_valid": fv,
            "rescue_mean": mean(re), "rescue": re,
            "coop_focus_fire_mean": mean(ff), "coop_focus_fire": ff,
            "coop_rescue_fire_mean": mean(fr),
            "detection_mean": mean(det), "control_mean": mean(ctrl),
        }

    sm = {
        "A": mech(A, "A solo双方"),
        "B": mech(B, "B coop双方"),
        "C": mech(C, "C 非对称蓝协同"),
        "D": mech(D, "D 非对称红协同"),
    }
    table = {k: {kk: vv for kk, vv in v.items() if not isinstance(vv, list)} for k, v in sm.items()}
    (out / "exp3_summary.json").write_text(json.dumps(table, ensure_ascii=False, indent=2), encoding="utf-8")
    with (out / "exp3_summary.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["group","n","fusion_assist_mean","fusion_valid_mean","rescue_mean",
                    "coop_focus_fire_mean","coop_rescue_fire_mean","detection_mean","control_mean"])
        for s in sm.values():
            w.writerow([s["label"], s["n"], f"{s['fusion_assist_mean']:.2f}", f"{s['fusion_valid_mean']:.2f}",
                        f"{s['rescue_mean']:.2f}", f"{s['coop_focus_fire_mean']:.2f}",
                        f"{s['coop_rescue_fire_mean']:.2f}", f"{s['detection_mean']:.2f}", f"{s['control_mean']:.2f}"])

    labels = [sm[k]["label"] for k in ("A","B","C","D")]
    plt = try_matplotlib()
    if plt is None:
        from plot_exp1_symmetric import _svg_bar
        _svg_bar(out/"fig1_fusion.svg", labels,
                 [sm[k]["fusion_assist_mean"] for k in ("A","B","C","D")],
                 "实验3 平均 fusion_assist", "次数")
        _svg_bar(out/"fig2_rescue.svg", labels,
                 [sm[k]["rescue_mean"] for k in ("A","B","C","D")],
                 "实验3 平均救援事件", "次数")
        _svg_bar(out/"fig3_focus_fire.svg", labels,
                 [sm[k]["coop_focus_fire_mean"] for k in ("A","B","C","D")],
                 "实验3 平均协同集火开火", "次数")
        _svg_bar(out/"fig4_detection.svg", labels,
                 [sm[k]["detection_mean"] for k in ("A","B","C","D")],
                 "实验3 平均检测计数", "次数")
    else:
        # 尽量启用中文字体，避免缺字警告
        plt.rcParams["font.sans-serif"] = [
            "SimHei", "Microsoft YaHei", "Noto Sans CJK SC",
            "WenQuanYi Micro Hei", "Source Han Sans SC", "DejaVu Sans",
        ]
        plt.rcParams["axes.unicode_minus"] = False
        import numpy as np
        keys = ("A","B","C","D")
        def bar(path, title, field, ylab):
            fig, ax = plt.subplots(figsize=(7.5, 4.2))
            vals = [sm[k][field] for k in keys]
            cols = ["#7f8c8d", "#2980b9", "#27ae60", "#c0392b"]
            ax.bar(labels, vals, color=cols)
            ax.set_title(title); ax.set_ylabel(ylab); ax.grid(axis="y", alpha=0.3)
            fig.tight_layout(); fig.savefig(path.with_suffix(".png"), dpi=200); fig.savefig(path.with_suffix(".pdf")); plt.close()
        bar(out/"fig1_fusion", "实验3 多模态融合协助 (fusion_assist)", "fusion_assist_mean", "平均次数")
        bar(out/"fig2_rescue", "实验3 一方有难八方支援 (rescue_events)", "rescue_mean", "平均次数")
        bar(out/"fig3_focus_fire", "实验3 协同集火开火 (coop_focus_fire)", "coop_focus_fire_mean", "平均次数")
        bar(out/"fig4_detection", "实验3 视觉检测累计 (detection_sum)", "detection_mean", "平均次数")

        # box fusion A vs B
        fig, ax = plt.subplots(figsize=(6, 4))
        ax.boxplot([sm["A"]["fusion_assist"], sm["B"]["fusion_assist"]], tick_labels=["A solo", "B coop"], showmeans=True)
        ax.set_title("实验3 A/B fusion_assist 分布"); ax.set_ylabel("次数"); ax.grid(axis="y", alpha=0.3)
        fig.tight_layout(); fig.savefig(out/"fig5_fusion_box_AB.png", dpi=200); fig.savefig(out/"fig5_fusion_box_AB.pdf"); plt.close()

    print("EXP3 done ->", out)

if __name__ == "__main__":
    main()

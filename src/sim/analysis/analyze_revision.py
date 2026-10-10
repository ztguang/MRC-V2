#!/usr/bin/env python3
"""Summarize revision_20260924 match JSON into tables and a file index."""
import csv
import json
import math
import random
from collections import defaultdict
from pathlib import Path

OUT = Path("/root/lunwen/sim/godot/logs/revision_20260924")
JSON_DIR = OUT / "json"
TAB = OUT / "tables"
TAB.mkdir(parents=True, exist_ok=True)
random.seed(20260924)


def load_rows():
    rows = []
    if not JSON_DIR.exists():
        return rows
    for p in sorted(JSON_DIR.glob("*.json")):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except Exception as exc:
            rows.append({"run_id": p.stem, "error": str(exc), "path": str(p)})
            continue
        d["_path"] = str(p)
        rows.append(d)
    return rows


def valid(r):
    return r.get("winner") not in (None, "") and r.get("sim_time") is not None and not r.get("error")


def fnum(v, default=0.0):
    try:
        if v is None:
            return default
        return float(v)
    except (TypeError, ValueError):
        return default


def mean(xs):
    xs = list(xs)
    return sum(xs) / len(xs) if xs else float("nan")


def wilson(k, n, z=1.96):
    if n <= 0:
        return (float("nan"), float("nan"), float("nan"))
    p = k / n
    den = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / den
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return p, max(0.0, centre - half), min(1.0, centre + half)


def binom_p(k, n, p0=0.5):
    if n <= 0:
        return float("nan")
    # two-sided exact
    def pmf(i):
        return math.comb(n, i) * (p0 ** i) * ((1 - p0) ** (n - i))
    pk = pmf(k)
    tail = sum(pmf(i) for i in range(n + 1) if pmf(i) <= pk + 1e-15)
    return min(1.0, tail)


def bootstrap_ci(xs, reps=4000):
    xs = list(xs)
    if not xs:
        return float("nan"), float("nan"), float("nan")
    n = len(xs)
    stats = []
    for _ in range(reps):
        sample = [xs[random.randrange(n)] for _ in range(n)]
        stats.append(sum(sample) / n)
    stats.sort()
    lo = stats[int(0.025 * (reps - 1))]
    hi = stats[int(0.975 * (reps - 1))]
    return sum(xs) / n, lo, hi


def per_min(count, sim_time, robots=3):
    minutes = max(fnum(sim_time), 0.1) / 60.0
    return fnum(count) / minutes / robots


def side_flags(r, side):
    return (
        int(r.get(f"fusion_{side}", 0)),
        int(r.get(f"focus_{side}", 0)),
        int(r.get(f"formation_{side}", 0)),
        int(r.get(f"rescue_{side}", 0)),
    )


def is_full(flags):
    return flags == (1, 1, 1, 1)


def treatment_side(r):
    eid = str(r.get("exp_id", ""))
    if eid in ("C1", "E1", "F4"):
        return "red"
    if eid in ("C1s", "E1s", "F4s"):
        return "blue"
    if eid == "C2":
        return "red"
    if eid == "C2s":
        return "blue"
    if eid == "D1":
        return "red"
    if eid == "D1s":
        return "blue"
    rf, bf = side_flags(r, "red"), side_flags(r, "blue")
    if is_full(rf) and not is_full(bf):
        return "red"
    if is_full(bf) and not is_full(rf):
        return "blue"
    return "none"


def wins(rows, side):
    if side == "red":
        return sum(1 for r in rows if r.get("winner") == "red")
    if side == "blue":
        return sum(1 for r in rows if r.get("winner") == "blue")
    return 0


def write_csv(path, header, records):
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=header, extrasaction="ignore")
        w.writeheader()
        for rec in records:
            w.writerow(rec)


def summarize_group(name, rows, side):
    rows = [r for r in rows if valid(r)]
    n = len(rows)
    k = wins(rows, side) if side in ("red", "blue") else sum(1 for r in rows if r.get("winner") == "red")
    p, lo, hi = wilson(k, n)
    pv = binom_p(k, n) if side in ("red", "blue") else float("nan")
    dur = [fnum(r.get("sim_time")) for r in rows]
    dm, dlo, dhi = bootstrap_ci(dur)
    pos = [fnum(r.get("pos_err_mean_m"), float("nan")) for r in rows if fnum(r.get("pos_err_mean_m"), -1) >= 0]
    pm, plo, phi = bootstrap_ci(pos) if pos else (float("nan"), float("nan"), float("nan"))
    aim = [fnum(r.get("aim_err_mean_deg"), float("nan")) for r in rows if fnum(r.get("aim_err_mean_deg"), -1) >= 0]
    am, alo, ahi = bootstrap_ci(aim) if aim else (float("nan"), float("nan"), float("nan"))
    def rate(key):
        return mean(per_min(r.get(key), r.get("sim_time")) for r in rows)
    return {
        "group": name,
        "n": n,
        "treatment_side": side,
        "treatment_wins": k if side in ("red", "blue") else "",
        "win_rate": round(p, 4) if n else "",
        "win_lo": round(lo, 4) if n else "",
        "win_hi": round(hi, 4) if n else "",
        "binom_p_vs_half": round(pv, 4) if pv == pv else "",
        "duration_mean_s": round(dm, 2) if dm == dm else "",
        "duration_lo": round(dlo, 2) if dlo == dlo else "",
        "duration_hi": round(dhi, 2) if dhi == dhi else "",
        "pos_err_mean_m": round(pm, 3) if pm == pm else "",
        "pos_err_lo": round(plo, 3) if plo == plo else "",
        "pos_err_hi": round(phi, 3) if phi == phi else "",
        "aim_err_mean_deg": round(am, 2) if am == am else "",
        "aim_err_lo": round(alo, 2) if alo == alo else "",
        "aim_err_hi": round(ahi, 2) if ahi == ahi else "",
        "assist_per_robot_min": round(rate("assist_red") + rate("assist_blue"), 3),
        "focus_fire_per_robot_min": round(rate("focus_fire_red") + rate("focus_fire_blue"), 3),
        "rescue_per_robot_min": round(rate("rescue_events_red") + rate("rescue_events_blue"), 3),
        "process_ms_p50": round(mean(fnum(r.get("process_ms_p50")) for r in rows), 2),
        "process_ms_p95": round(mean(fnum(r.get("process_ms_p95")) for r in rows), 2),
        "queue_p95": round(mean(fnum(r.get("queue_p95")) for r in rows), 2),
        "dropped_mean": round(mean(fnum(r.get("dropped")) for r in rows), 2),
        "ghost_rate": round(mean(fnum(r.get("ghost_rate"), float("nan")) for r in rows if fnum(r.get("ghost_rate"), -1) >= 0), 3)
        if any(fnum(r.get("ghost_rate"), -1) >= 0 for r in rows) else "",
        "all_tracked_t_red": round(mean(fnum(r.get("all_tracked_t_red"), float("nan")) for r in rows if fnum(r.get("all_tracked_t_red"), -1) >= 0), 2)
        if any(fnum(r.get("all_tracked_t_red"), -1) >= 0 for r in rows) else "",
    }


def holm(records, key="binom_p_vs_half"):
    indexed = [(i, fnum(r.get(key), float("nan"))) for i, r in enumerate(records) if fnum(r.get(key), -1) >= 0]
    indexed.sort(key=lambda t: t[1])
    m = len(indexed)
    adj = {}
    running = 0.0
    for rank, (i, p) in enumerate(indexed):
        val = min(1.0, (m - rank) * p)
        running = max(running, val)
        adj[i] = running
    for i, r in enumerate(records):
        r["holm_p"] = round(adj[i], 4) if i in adj else ""
    return records


def score_obs(obs, mode, alpha=0.5, beta=0.3, gamma=0.2, lam=1.0, d_ref=5.0):
    # Replay a logged track list. Distance is not stored; use age and confidence,
    # and a unit distance of 5 m when the log has no observer range.
    if not obs:
        return None
    if mode == "nearest":
        return obs[0]
    weights = []
    max_s = -1e30
    raw = []
    for item in obs:
        c = fnum(item.get("c"), 0.5)
        age = fnum(item.get("age"))
        d = 5.0
        if mode == "legacy":
            s = 0.5 * c + 0.3 / max(d, 0.15) + 0.2 * math.exp(-0.1 * age)
        elif mode == "uniform":
            s = 1.0
        elif mode == "conf":
            s = c
        elif mode == "dist":
            s = math.exp(-d / (d_ref if d_ref else 5.0))
        else:
            s = alpha * c + beta * math.exp(-d / d_ref) + gamma * math.exp(-lam * age)
        raw.append(s)
        max_s = max(max_s, s)
    for s in raw:
        weights.append(math.exp(s - max_s))
    z = sum(weights) or 1.0
    x = y = zz = 0.0
    for w, item in zip(weights, obs):
        ww = w / z
        x += ww * fnum(item["x"])
        y += ww * fnum(item["y"])
        zz += ww * fnum(item["z"])
    return {"x": x, "y": y, "z": zz}


def nearest_enemy(pos, enemies):
    best = None
    for e in enemies:
        d = math.dist((pos["x"], pos["y"], pos["z"]), (fnum(e["x"]), fnum(e["y"]), fnum(e["z"])))
        if best is None or d < best:
            best = d
    return best


def sensitivity(rows):
    modes = {
        "proposed": ("proposed", 0.5, 0.3, 0.2, 1.0, 5.0),
        "conf_heavy": ("proposed", 0.7, 0.15, 0.15, 1.0, 5.0),
        "dist_heavy": ("proposed", 0.2, 0.6, 0.2, 1.0, 5.0),
        "fresh_heavy": ("proposed", 0.2, 0.2, 0.6, 1.0, 5.0),
        "equal": ("proposed", 1 / 3, 1 / 3, 1 / 3, 1.0, 5.0),
        "lambda_0.1": ("proposed", 0.5, 0.3, 0.2, 0.1, 5.0),
        "lambda_2": ("proposed", 0.5, 0.3, 0.2, 2.0, 5.0),
        "dref_3": ("proposed", 0.5, 0.3, 0.2, 1.0, 3.0),
        "dref_8": ("proposed", 0.5, 0.3, 0.2, 1.0, 8.0),
        "legacy": ("legacy", 0, 0, 0, 0, 0),
        "uniform": ("uniform", 0, 0, 0, 0, 0),
        "conf_only": ("conf", 0, 0, 0, 0, 0),
        "dist_only": ("dist", 0, 0, 0, 0, 0),
    }
    acc = {k: [] for k in modes}
    ghost = {k: [] for k in modes}
    for r in rows:
        if str(r.get("exp_id")) != "A2":
            continue
        for sample in r.get("samples") or []:
            obs = sample.get("obs") or []
            enemies = sample.get("enemies") or []
            if not obs or not enemies:
                continue
            for name, (mode, a, b, g, lam, dref) in modes.items():
                pos = score_obs(obs, mode, a, b, g, lam, dref)
                if pos is None:
                    continue
                err = nearest_enemy(pos, enemies)
                if err is None:
                    continue
                acc[name].append(err)
                ghost[name].append(1.0 if err > 1.5 else 0.0)
    out = []
    for name in modes:
        m, lo, hi = bootstrap_ci(acc[name]) if acc[name] else (float("nan"),) * 3
        out.append({
            "setting": name,
            "n_samples": len(acc[name]),
            "pos_err_mean_m": round(m, 3) if m == m else "",
            "pos_err_lo": round(lo, 3) if lo == lo else "",
            "pos_err_hi": round(hi, 3) if hi == hi else "",
            "ghost_rate": round(mean(ghost[name]), 3) if ghost[name] else "",
        })
    return out


def eq14(rows):
    samples = [fnum(r.get("process_ms_p50")) for r in rows if str(r.get("exp_id")) == "A2" and fnum(r.get("process_ms_p50")) > 0]
    base_ms = mean(samples) if samples else 30.0
    # Image payload at 320x240 BGRA.
    nbytes = 320 * 240 * 4
    results = []
    for rate_mbps in (10, 50, 100):
        tx_ms = (nbytes * 8) / (rate_mbps * 1e6) * 1000.0
        for tmax in (50.0, 100.0):
            # 6 tasks, capacity 1 per node. Search all permutations is 720.
            import itertools
            local = [base_ms] * 6
            best_u = -1e18
            best_viol = 6
            ident_u = 0.0
            ident_viol = 0
            for i, t in enumerate(local):
                viol = 1 if t > tmax else 0
                ident_viol += viol
                ident_u += -(t + 5.0 * viol)
            # Greedy: keep local if within deadline, else first feasible neighbor.
            greedy_assign = list(range(6))
            used = set()
            g_u = 0.0
            g_viol = 0
            for i in range(6):
                options = []
                for j in range(6):
                    if j != i and j in used:
                        continue
                    t = local[i] if j == i else tx_ms + local[i]
                    viol = 1 if t > tmax else 0
                    u = -(t + 50.0 * viol)
                    options.append((u, viol, j, t))
                options.sort(reverse=True)
                u, viol, j, _t = options[0]
                greedy_assign[i] = j
                if j != i:
                    used.add(j)
                g_u += u
                g_viol += viol
            # Optimal among assignments with at most one extra task per node is expensive;
            # compare identity vs greedy and a random sample of 2000 feasible maps.
            best_u = ident_u
            best_viol = ident_viol
            rng = random.Random(0)
            for _ in range(2000):
                assign = [rng.randrange(6) for _ in range(6)]
                load = [0] * 6
                ok = True
                for j in assign:
                    load[j] += 1
                    if load[j] > 2:
                        ok = False
                        break
                if not ok:
                    continue
                u = 0.0
                viol = 0
                for i, j in enumerate(assign):
                    t = local[i] if j == i else tx_ms + base_ms
                    v = 1 if t > tmax else 0
                    u += -(t + 50.0 * v)
                    viol += v
                if u > best_u:
                    best_u = u
                    best_viol = viol
            results.append({
                "rate_mbps": rate_mbps,
                "t_max_ms": tmax,
                "local_process_ms": round(base_ms, 2),
                "tx_ms": round(tx_ms, 2),
                "identity_utility": round(ident_u, 2),
                "identity_violations": ident_viol,
                "greedy_utility": round(g_u, 2),
                "greedy_violations": g_viol,
                "sampled_best_utility": round(best_u, 2),
                "sampled_best_violations": best_viol,
                "note": "offline numerical check; not a match outcome",
            })
    return results


def main():
    rows = load_rows()
    good = [r for r in rows if valid(r)]
    by = defaultdict(list)
    for r in good:
        by[str(r.get("exp_id"))].append(r)
    order = [
        "A1", "A2", "A3", "A4",
        "B1", "B1s", "B2", "B2s", "B3", "B3s", "B4", "B4s",
        "C1", "C1s", "C2", "C2s",
        "D1", "D1s", "E1", "E1s",
        "F1", "F2", "F3", "F4", "F4s",
        "G2", "G3", "H1", "H2",
    ]
    header = list(summarize_group("x", [], "none").keys()) + ["holm_p"]
    groups = []
    for eid in order:
        side = treatment_side(by[eid][0]) if by[eid] else (
            "red" if eid in ("A3", "B1", "B2", "B3", "B4", "C1", "C2", "D1", "E1", "F4", "H1") else
            "blue" if eid in ("A4", "B1s", "B2s", "B3s", "B4s", "C1s", "C2s", "D1s", "E1s", "F4s", "H2") else
            "none"
        )
        groups.append(summarize_group(eid, by.get(eid, []), side))
    # Holm only on the four leave-one-out contrasts, pooled later in the ablation file.
    write_csv(TAB / "table_all_groups.csv", header, groups)

    def pick(ids):
        return [g for g in groups if g["group"] in ids]

    write_csv(TAB / "table_fair.csv", header, pick(["A1", "A2", "A3", "A4"]))
    ab = pick(["B1", "B1s", "B2", "B2s", "B3", "B3s", "B4", "B4s"])
    # Pool each contrast.
    pooled = []
    for name, a, b in (("nofusion", "B1", "B1s"), ("nofocus", "B2", "B2s"), ("noformation", "B3", "B3s"), ("norescue", "B4", "B4s")):
        merged = by[a] + by[b]
        # Flip B*s so treatment wins are counted as the full side.
        # summarize uses treatment_side of first row; pass a synthetic by rewriting winner.
        flipped = []
        for r in merged:
            rr = dict(r)
            side = treatment_side(r)
            if side == "blue" and r.get("winner") == "blue":
                rr["winner"] = "red"
            elif side == "blue" and r.get("winner") == "red":
                rr["winner"] = "blue"
            elif side == "blue":
                rr["winner"] = r.get("winner")
            flipped.append(rr)
        rec = summarize_group("LOO_" + name, flipped, "red")
        pooled.append(rec)
    pooled = holm(pooled)
    write_csv(TAB / "table_ablation.csv", header, pooled)
    write_csv(TAB / "table_fusion_baselines.csv", header, pick(["C1", "C1s", "C2", "C2s", "B1", "B1s"]))
    write_csv(TAB / "table_association.csv", header, pick(["D1", "D1s", "A2"]))
    write_csv(TAB / "table_legacy_score.csv", header, pick(["E1", "E1s"]))
    write_csv(TAB / "table_comm.csv", header, pick(["A2", "F1", "F2", "F3", "F4", "F4s"]))
    write_csv(TAB / "table_compute.csv", header, pick(["A2", "G2", "G3"]))
    write_csv(TAB / "table_occlusion.csv", header, pick(["H1", "H2", "A3", "A4"]))
    sens = sensitivity(good)
    write_csv(TAB / "table_sensitivity.csv", list(sens[0].keys()) if sens else ["setting"], sens)
    eq = eq14(good)
    write_csv(TAB / "table_eq14.csv", list(eq[0].keys()) if eq else ["note"], eq)

    failures = OUT / "failures.log"
    fail_txt = failures.read_text(encoding="utf-8") if failures.exists() else ""
    manifest = {
        "n_json": len(rows),
        "n_valid": len(good),
        "by_exp": {k: len(v) for k, v in sorted(by.items())},
        "failures": fail_txt.strip().splitlines(),
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = []
    lines.append("# 修订实验文件说明")
    lines.append("")
    lines.append(f"有效局 {len(good)} / JSON {len(rows)}。胜率区间是 Wilson 95% 区间，时长和误差区间是 4000 次自助法 95% 区间。")
    lines.append("消融四行的 holm_p 是对四个留一检验的 Holm 校正。")
    lines.append("式(14)表是用 A2 的 process_ms 中位数做的离线数值对照，不是对局胜负。")
    lines.append("")
    lines.append("| 文件 | 作用 |")
    lines.append("|---|---|")
    desc = {
        "json/": "每一局的原始记录。文件名是实验编号加 run 序号。",
        "logs/": "每一局 Godot 控制台日志，用来核对崩溃和开火原因。",
        "tables/table_fair.csv": "步骤1。A1/A2 看对称公平，A3/A4 是全开对全关的两侧。",
        "tables/table_ablation.csv": "步骤2。关掉融合、焦点、编队、救援之一后，全开侧胜率及 Holm 校正。",
        "tables/table_fusion_baselines.csv": "步骤3。本文评分对等权平均、最近邻。B1 是关掉融合。",
        "tables/table_association.csv": "步骤4在线部分。有门控对无门控，看鬼点和定位误差。",
        "tables/table_legacy_score.csv": "步骤4在线部分。无量纲评分对旧的 0.3/d 评分。",
        "tables/table_sensitivity.csv": "步骤4离线网格。在 A2 落盘的观测上重放权重、λ 和参考距离。",
        "tables/table_comm.csv": "步骤5。0/100/400 ms 时延、30% 丢包，以及 400 ms 下评分对等权。",
        "tables/table_compute.csv": "步骤6对局。320、640 和每帧额外 40 ms。",
        "tables/table_eq14.csv": "步骤6离线。贪婪放置对抽样更优放置的效用和超时次数。",
        "tables/table_occlusion.csv": "步骤7。视场缩到 0.6 倍后全开对全关。",
        "tables/table_all_groups.csv": "上面各块的逐格汇总，未做留一合并。",
        "manifest.json": "每格完成局数和失败局名单。",
        "failures.log": "重试后仍没有 winner 的 run_id。",
        "progress.log": "跑批过程记录。",
        "runner.log": "批处理脚本标准输出。",
    }
    for k, v in desc.items():
        lines.append(f"| `{k}` | {v} |")
    lines.append("")
    lines.append("## 各格完成局数")
    lines.append("")
    for k, n in manifest["by_exp"].items():
        lines.append(f"- {k}: {n}")
    if manifest["failures"]:
        lines.append("")
        lines.append("## 失败局")
        for line in manifest["failures"]:
            lines.append(f"- {line}")
    (OUT / "README_结果说明.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Offline gate and weight replay on pre-gate raw detections.

Each logged row is one detection before association. At a replay instant the
candidate set is the latest fresh detection of each observer (age <= 2.5 s).
That is the set the fusion step sees: one report per robot, not a position trail.

Enemy ids come only from *.eval.jsonl and are used after association, to score
error, ghosts, and mixed-target sets. Win rate is not computed.

Default weights change only when exactly one grid cell has a localization-error
interval entirely below the default cell.
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

R_GATE = 1.5
AGE_MAX = 2.5
DT = 0.5
BOOT = 4000
SEED = 20260929

WEIGHTS = [
    (0.5, 0.3, 0.2),
    (0.7, 0.15, 0.15),
    (0.2, 0.6, 0.2),
    (0.2, 0.2, 0.6),
    (1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0),
]
LAMBDAS = [0.1, 1.0, 2.0]
DREFS = [3.0, 5.0, 8.0]
DEFAULT = (0.5, 0.3, 0.2, 1.0, 5.0)


def dist(a, b) -> float:
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def load_match(raw_path: Path, eval_path: Path):
    raw_lines = [ln for ln in raw_path.read_text(encoding="utf-8").splitlines() if ln.strip()]
    eval_lines = [ln for ln in eval_path.read_text(encoding="utf-8").splitlines() if ln.strip()]
    if len(raw_lines) != len(eval_lines):
        raise RuntimeError(f"length mismatch {raw_path.name}: {len(raw_lines)} vs {len(eval_lines)}")
    recs = []
    for raw_line, eval_line in zip(raw_lines, eval_lines):
        if '"enemies"' in raw_line:
            raise RuntimeError(f"truth leaked into raw file {raw_path.name}")
        raw = json.loads(raw_line)
        ev = json.loads(eval_line)
        if abs(float(raw["t"]) - float(ev["t"])) > 1e-3 or int(raw["obs"]) != int(ev["obs"]):
            raise RuntimeError(f"raw/eval misaligned {raw_path.name}")
        recs.append({
            "t": float(raw["t"]),
            "team": int(raw["team"]),
            "obs": int(raw["obs"]),
            "pos": (float(raw["x"]), float(raw["y"]), float(raw["z"])),
            "c": float(raw["c"]),
            "friends": raw["friends"],
            "enemies": ev["enemies"],
        })
    recs.sort(key=lambda r: (r["t"], r["team"], r["obs"]))
    return recs


def bisect_right(recs, t):
    lo, hi = 0, len(recs)
    while lo < hi:
        mid = (lo + hi) // 2
        if recs[mid]["t"] <= t:
            lo = mid + 1
        else:
            hi = mid
    return lo


def latest_team_record(recs, end, team):
    for i in range(end - 1, -1, -1):
        if recs[i]["team"] == team:
            return recs[i]
    return None


def nearest_id(pos, enemies, gate: float):
    best_id = None
    best_d = 1.0e9
    for en in enemies:
        d = dist(pos, (float(en["x"]), float(en["y"]), float(en["z"])))
        if d < best_d:
            best_d = d
            best_id = int(en["id"])
    if best_id is None or best_d > gate:
        return None, best_d
    return best_id, best_d


def score_of(origin, cand, params) -> float:
    alpha, beta, gamma, lam, dref = params
    d = max(dist(origin, cand["pos"]), 0.15)
    age = max(0.0, float(cand["age"]))
    return (
        alpha * float(cand["c"])
        + beta * math.exp(-d / max(dref, 0.5))
        + gamma * math.exp(-lam * age)
    )


def blend(origin, members, params):
    scores = [score_of(origin, cand, params) for cand in members]
    mx = max(scores)
    weights = [math.exp(s - mx) for s in scores]
    z = sum(weights)
    acc = [0.0, 0.0, 0.0]
    for cand, w in zip(members, weights):
        f = w / z
        acc[0] += cand["pos"][0] * f
        acc[1] += cand["pos"][1] * f
        acc[2] += cand["pos"][2] * f
    return (acc[0], acc[1], acc[2])


def cluster(cands):
    tracks = []
    for cand in sorted(cands, key=lambda c: c["t"]):
        best_i = -1
        best_d = R_GATE
        for i, tr in enumerate(tracks):
            d = dist(cand["pos"], tr["pos"])
            if d < best_d:
                best_d = d
                best_i = i
        if best_i < 0:
            tracks.append({"pos": cand["pos"], "members": [cand]})
        else:
            tracks[best_i]["pos"] = cand["pos"]
            tracks[best_i]["members"].append(cand)
    return tracks


def select_members(origin, cands, params, gate: bool):
    if not gate:
        return cands
    tracks = cluster(cands)
    best_s = -1.0e30
    best = tracks[0]
    for tr in tracks:
        for cand in tr["members"]:
            s = score_of(origin, cand, params)
            if s > best_s:
                best_s = s
                best = tr
    return best["members"]


def true_ids(members):
    return {cand["true_id"] for cand in members if cand["true_id"] is not None}


def build_samples(recs):
    if not recs:
        return []
    teams = sorted({r["team"] for r in recs})
    by_team = {team: [r for r in recs if r["team"] == team] for team in teams}
    samples = []
    # Sample at each detection. A fixed grid can fall entirely before the only
    # detection and then stop at that detection's timestamp.
    times = sorted({round(float(r["t"]), 3) for r in recs})
    for t in times:
        end_all = bisect_right(recs, t)
        for team, rows in by_team.items():
            end = bisect_right(rows, t)
            start = bisect_right(rows, t - AGE_MAX)
            latest = {}
            for rec in rows[start:end]:
                latest[rec["obs"]] = rec
            if not latest:
                continue
            now = latest_team_record(recs, end_all, team)
            if now is None or not now["enemies"]:
                continue
            cands = []
            for rec in latest.values():
                tid, _ = nearest_id(rec["pos"], rec["enemies"], R_GATE)
                cands.append({
                    "t": rec["t"],
                    "pos": rec["pos"],
                    "c": rec["c"],
                    "age": t - rec["t"],
                    "obs": rec["obs"],
                    "true_id": tid,
                })
            origins = []
            for fr in now["friends"]:
                origins.append((float(fr["x"]), float(fr["y"]), float(fr["z"])))
            if not origins:
                continue
            samples.append({
                "cands": cands,
                "enemies": now["enemies"],
                "origins": origins,
                "n_cands": len(cands),
                "n_ids": len(true_ids(cands)),
            })
    return samples


def summarize_match(samples, params):
    if not samples:
        return None
    err_on, err_off = [], []
    ghost_on, ghost_off = [], []
    err_on_multi, err_off_multi = [], []
    fresh_err = []
    pre_flags, post_flags = [], []
    n_multi = 0
    n_cands = []
    for sample in samples:
        cands = sample["cands"]
        n_cands.append(sample["n_cands"])
        multi = sample["n_cands"] >= 2
        fresh = min(c["age"] for c in cands) <= 0.3
        if multi:
            n_multi += 1
            pre_flags.append(1.0 if sample["n_ids"] >= 2 else 0.0)
        for origin in sample["origins"]:
            members = select_members(origin, cands, params, True)
            pos = blend(origin, members, params)
            _, err = nearest_id(pos, sample["enemies"], 1.0e9)
            err_on.append(err)
            ghost_on.append(1.0 if err > R_GATE else 0.0)
            if fresh:
                fresh_err.append(err)
            if multi:
                post_flags.append(1.0 if len(true_ids(members)) >= 2 else 0.0)
                err_on_multi.append(err)
            pos_off = blend(origin, cands, params)
            _, err2 = nearest_id(pos_off, sample["enemies"], 1.0e9)
            err_off.append(err2)
            ghost_off.append(1.0 if err2 > R_GATE else 0.0)
            if multi:
                err_off_multi.append(err2)
    def mean(xs):
        return sum(xs) / len(xs) if xs else None
    return {
        "err_on": mean(err_on),
        "err_off": mean(err_off),
        "ghost_on": mean(ghost_on),
        "ghost_off": mean(ghost_off),
        "pre_mixed": mean(pre_flags),
        "post_mixed": mean(post_flags),
        "err_on_multi": mean(err_on_multi),
        "err_off_multi": mean(err_off_multi),
        "fresh_err": mean(fresh_err),
        "n_samples": len(samples),
        "n_multi": n_multi,
        "mean_cands": mean(n_cands),
    }


def grid_error(samples, params):
    errs = []
    for sample in samples:
        for origin in sample["origins"]:
            members = select_members(origin, sample["cands"], params, True)
            pos = blend(origin, members, params)
            _, err = nearest_id(pos, sample["enemies"], 1.0e9)
            errs.append(err)
    if not errs:
        return None
    return sum(errs) / len(errs)


def bootstrap(values):
    vals = [v for v in values if v is not None]
    if not vals:
        return {"n": 0, "mean": None, "lo": None, "hi": None}
    rng = random.Random(SEED)
    n = len(vals)
    means = []
    for _ in range(BOOT):
        acc = 0.0
        for _k in range(n):
            acc += vals[rng.randrange(n)]
        means.append(acc / n)
    means.sort()
    return {
        "n": n,
        "mean": sum(vals) / n,
        "lo": means[int(0.025 * (BOOT - 1))],
        "hi": means[int(0.975 * (BOOT - 1))],
    }


def cell_name(params) -> str:
    a, b, g, lam, dref = params
    return f"a={a:.3f},b={b:.3f},g={g:.3f},lam={lam:.1f},dref={dref:.0f}"


def lower_and_disjoint(cell, default) -> bool:
    vals = (cell["hi"], cell["lo"], default["hi"], default["lo"])
    if any(v is None for v in vals):
        return False
    return cell["hi"] < default["lo"]


def grid_spec():
    ordered = [DEFAULT]
    seen = {DEFAULT}
    for a, b, g in WEIGHTS:
        params = (a, b, g, 1.0, 5.0)
        if params not in seen:
            seen.add(params)
            ordered.append(params)
    for lam in LAMBDAS:
        params = (0.5, 0.3, 0.2, lam, 5.0)
        if params not in seen:
            seen.add(params)
            ordered.append(params)
    for dref in DREFS:
        params = (0.5, 0.3, 0.2, 1.0, dref)
        if params not in seen:
            seen.add(params)
            ordered.append(params)
    return ordered


def main():
    cand = Path(sys.argv[1] if len(sys.argv) > 1 else "/root/lunwen/sim/godot/logs/revision_20260924_raw/cand")
    out = Path(sys.argv[2] if len(sys.argv) > 2 else "/root/lunwen/sim/godot/logs/revision_20260924_raw/replay")
    require = int(sys.argv[3]) if len(sys.argv) > 3 else 16
    out.mkdir(parents=True, exist_ok=True)
    paths = sorted(cand.glob("*.raw.jsonl"))
    if len(paths) < require:
        raise SystemExit(f"expected at least {require} raw logs in {cand}, found {len(paths)}")
    ordered = grid_spec()
    pooled = {key: [] for key in (
        "err_on", "err_off", "ghost_on", "ghost_off", "pre_mixed", "post_mixed",
        "err_on_multi", "err_off_multi", "fresh_err",
    )}
    grid_values = {params: [] for params in ordered}
    total_sets = 0
    total_multi = 0
    total_raw = 0
    cand_means = []
    for raw_path in paths:
        eval_path = Path(str(raw_path).replace(".raw.jsonl", ".eval.jsonl"))
        recs = load_match(raw_path, eval_path)
        samples = build_samples(recs)
        got = summarize_match(samples, DEFAULT)
        if got is None:
            raise SystemExit(f"no samples in {raw_path.name}")
        for key in pooled:
            pooled[key].append(got[key])
        total_sets += got["n_samples"]
        total_multi += got["n_multi"]
        total_raw += len(recs)
        cand_means.append(got["mean_cands"])
        for params in ordered:
            grid_values[params].append(grid_error(samples, params))
        pre_s = "na" if got["pre_mixed"] is None else f"{got['pre_mixed']:.3f}"
        post_s = "na" if got["post_mixed"] is None else f"{got['post_mixed']:.3f}"
        print(
            f"OK {raw_path.name} sets={got['n_samples']} cands={got['mean_cands']:.2f} "
            f"err_on={got['err_on']:.3f} err_off={got['err_off']:.3f} pre={pre_s} post={post_s}",
            flush=True,
        )
    summary = {
        "n_matches": len(paths),
        "total_raw": total_raw,
        "total_sets": total_sets,
        "total_multi": total_multi,
        "mean_cands": sum(cand_means) / len(cand_means),
        "multi_fraction_of_sets": (total_multi / total_sets) if total_sets else None,
        "candidate_rule": "at each detection, latest fresh report per observer, age<=2.5s",
        "gate": {key: bootstrap(pooled[key]) for key in pooled},
        "grid": [],
    }
    default_ci = None
    for params in ordered:
        ci = bootstrap(grid_values[params])
        item = {"params": list(params), "name": cell_name(params), **ci}
        if params == DEFAULT:
            default_ci = item
        summary["grid"].append(item)
    winners = []
    for item in summary["grid"]:
        item["lower_disjoint"] = lower_and_disjoint(item, default_ci)
        if item["lower_disjoint"] and tuple(item["params"]) != DEFAULT:
            winners.append(item["name"])
    summary["default"] = default_ci
    summary["lower_cells"] = winners
    summary["keep_default"] = len(winners) != 1
    gate = summary["gate"]
    pre, post = gate["pre_mixed"], gate["post_mixed"]
    summary["mixed_reduced"] = (
        pre.get("hi") is not None and post.get("hi") is not None and post["hi"] < pre["lo"]
    )
    summary["error_reduced"] = (
        gate["err_on"].get("hi") is not None
        and gate["err_off"].get("lo") is not None
        and gate["err_on"]["hi"] < gate["err_off"]["lo"]
    )
    summary["rarely_mixed"] = pre.get("mean") is None or pre["mean"] < 0.05
    out_json = out / "summary.json"
    out_json.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    show = {
        "n_matches": summary["n_matches"],
        "total_raw": summary["total_raw"],
        "mean_cands": summary["mean_cands"],
        "multi_fraction_of_sets": summary["multi_fraction_of_sets"],
        "gate": summary["gate"],
        "grid": summary["grid"],
        "keep_default": summary["keep_default"],
        "lower_cells": summary["lower_cells"],
        "mixed_reduced": summary["mixed_reduced"],
        "error_reduced": summary["error_reduced"],
        "rarely_mixed": summary["rarely_mixed"],
    }
    print(json.dumps(show, ensure_ascii=False, indent=2))
    print("WROTE", out_json)


if __name__ == "__main__":
    main()

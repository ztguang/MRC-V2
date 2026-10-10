# -*- coding: utf-8 -*-
"""Wilson intervals for the small fair asymmetric batch. No paper update."""
import json
import math
import sys
from pathlib import Path

import numpy as np

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "/root/lunwen/sim/godot/logs/revision_20260929_aimfair")


def wilson(k, n, z=1.96):
    if n <= 0:
        return float("nan"), float("nan"), float("nan")
    p = k / n
    den = 1.0 + z * z / n
    centre = (p + z * z / (2.0 * n)) / den
    half = z * math.sqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n)) / den
    return p, centre - half, centre + half


def boot_mean(xs, seed):
    xs = np.asarray(xs, dtype=float)
    if xs.size == 0:
        return float("nan"), float("nan"), float("nan")
    rng = np.random.default_rng(seed)
    means = xs[rng.integers(0, xs.size, size=(4000, xs.size))].mean(axis=1)
    return float(xs.mean()), float(np.quantile(means, 0.025)), float(np.quantile(means, 0.975))


def num(d, *keys):
    for k in keys:
        if k in d and isinstance(d[k], (int, float)) and d[k] is not None:
            return float(d[k])
    return None


def side_shots(d, team):
    total = 0.0
    found = False
    robots = d.get("robots") or d.get("robot_metrics") or []
    if isinstance(robots, list):
        for r in robots:
            if not isinstance(r, dict):
                continue
            rt = r.get("team", r.get("team_id"))
            if rt is None:
                continue
            if int(rt) != team and str(rt).lower() != ("red" if team == 0 else "blue"):
                continue
            for k in ("shots", "shot", "fires"):
                if k in r:
                    total += float(r[k])
                    found = True
                    break
    key = "shots_red" if team == 0 else "shots_blue"
    if key in d:
        return float(d[key])
    return total if found else None


def load_group(prefix):
    rows = []
    for p in sorted((OUT / "json").glob(prefix + "*.json")):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        if d.get("winner") in (None, "") or d.get("error"):
            continue
        rows.append(d)
    return rows


def report(name, rows, win_value):
    n = len(rows)
    k = sum(1 for d in rows if str(d.get("winner")) == win_value)
    p, lo, hi = wilson(k, n)
    pos = [num(d, "pos_err_mean_m") for d in rows]
    pos = [x for x in pos if x is not None and x >= 0.0]
    aim = [num(d, "aim_err_mean_deg") for d in rows]
    aim = [x for x in aim if x is not None and x >= 0.0]
    pm, plo, phi = boot_mean(pos, 20260929)
    sr = [side_shots(d, 0) for d in rows]
    sb = [side_shots(d, 1) for d in rows]
    sr = [x for x in sr if x is not None]
    sb = [x for x in sb if x is not None]
    print(
        "%s n=%d wins=%d rate=%.3f wilson=(%.3f, %.3f) above_0.5=%s"
        % (name, n, k, p, lo, hi, str(lo > 0.5))
    )
    print("  pos_m mean=%.3f ci=(%.3f, %.3f) n=%d" % (pm, plo, phi, len(pos)))
    if aim:
        print("  aim_deg mean=%.2f" % (sum(aim) / len(aim)))
    if sr and sb:
        print("  shots red=%.2f blue=%.2f per match" % (sum(sr) / len(sr), sum(sb) / len(sb)))
    else:
        print("  shots unavailable")
    draws = sum(1 for d in rows if str(d.get("winner")) not in (win_value, "red" if win_value == "blue" else "blue"))
    print("  other_winner_or_draw=%d" % draws)


def main():
    red = load_group("A3_red_full_")
    blue = load_group("A4_blue_full_")
    print("dir", OUT)
    if red:
        print("sample_keys", ",".join(sorted(red[0].keys())[:40]))
    report("red_coop", red, "red")
    report("blue_coop", blue, "blue")
    print("planned", 12, "red_done", len(red), "blue_done", len(blue))


if __name__ == "__main__":
    main()

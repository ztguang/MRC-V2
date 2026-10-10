#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fresh 120s matrix. Category 1 is 20 games per pairing. Category 2 is 10 per id.

Does not edit the simulator or the paper. Does not read older result directories.
A finished win or loss is kept. A crash is retried once.
"""
import json
import math
import os
import random
import signal
import subprocess
import time
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path("/root/lunwen/sim")
OUT = Path("/root/lunwen/sim/godot/logs/revision_20261003_formal220")
JSON_DIR = OUT / "json"
LOG_DIR = OUT / "logs"
TIMEOUT = "1500"
GODOT_MARK = "/usr/local/bin/godot --path /root/lunwen/sim/godot"
FULL = (1, 1, 1, 1)
NONE = (0, 0, 0, 0)
DROPS = {
    "fusion": (0, 1, 1, 1),
    "focus": (1, 0, 1, 1),
    "formation": (1, 1, 0, 1),
    "rescue": (1, 1, 1, 0),
}


def kill_godot():
    marks = (
        GODOT_MARK,
        "/root/lunwen/sim/run_godot_nvidia.sh",
        "sp_vision_worker",
    )
    victims = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        if pid == os.getpid():
            continue
        try:
            cmd = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
        except OSError:
            continue
        if any(mark in cmd for mark in marks):
            victims.append(pid)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    if victims:
        time.sleep(0.8)
    for pid in victims:
        try:
            os.kill(pid, 0)
        except OSError:
            continue
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def valid_json(path: Path) -> bool:
    if not path.exists():
        return False
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    winner = data.get("winner")
    return winner not in (None, "") and data.get("sim_time") is not None and not data.get("error")


def job(block, exp_id, name, idx, red, blue, mode="proposed", gate=1,
        delay=0, loss=0.0, cam=(320, 240), calib=(0, 0)):
    return {
        "block": block, "exp_id": exp_id, "name": name, "idx": idx,
        "red": red, "blue": blue, "mode": mode, "gate": gate,
        "delay": delay, "loss": loss, "cam": cam, "calib": calib,
    }


def build_jobs():
    jobs = []
    for i in range(1, 21):
        jobs.append(job("W", "W_redfull", "red_coop", i, FULL, NONE))
        jobs.append(job("W", "W_bluefull", "blue_coop", i, NONE, FULL))
        jobs.append(job("S", "S_bothon", "both_on", i, FULL, FULL))
        jobs.append(job("S", "S_bothoff", "both_off", i, NONE, NONE))
    for i in range(1, 11):
        for key, dropped in DROPS.items():
            if i % 2 == 1:
                red, blue, side = FULL, dropped, "redfull"
            else:
                red, blue, side = dropped, FULL, "bluefull"
            jobs.append(job("L", "L_%s" % key, "%s_%s" % (key, side), i, red, blue))
    both = FULL
    for i in range(1, 11):
        jobs.append(job("C", "C_d100", "delay100", i, both, both, delay=100))
        jobs.append(job("C", "C_d400", "delay400", i, both, both, delay=400))
        jobs.append(job("C", "C_d100_loss", "delay100_loss30", i, both, both, delay=100, loss=0.3))
        jobs.append(job("P", "P_640", "cam640", i, both, both, cam=(640, 480)))
        jobs.append(job("F", "F_uniform", "uniform", i, both, both, mode="uniform"))
        jobs.append(job("F", "F_nearest", "nearest", i, both, both, mode="nearest"))
        jobs.append(job("F", "F_legacy", "legacy", i, both, both, mode="legacy"))
        jobs.append(job("G", "G_gateoff", "gate_off", i, both, both, gate=0))
        jobs.append(job("K", "K_calib0", "calib_0ms", i, both, both, calib=(1, 1)))
        jobs.append(job("K", "K_calib400", "calib_400ms", i, both, both, delay=400, calib=(1, 1)))
    return jobs


def check_jobs(jobs):
    counts = Counter(item["exp_id"] for item in jobs)
    expect = {
        "W_redfull": 20, "W_bluefull": 20, "S_bothon": 20, "S_bothoff": 20,
        "L_fusion": 10, "L_focus": 10, "L_formation": 10, "L_rescue": 10,
        "C_d100": 10, "C_d400": 10, "C_d100_loss": 10, "P_640": 10,
        "F_uniform": 10, "F_nearest": 10, "F_legacy": 10, "G_gateoff": 10,
        "K_calib0": 10, "K_calib400": 10,
    }
    if counts != Counter(expect) or len(jobs) != 220:
        raise SystemExit("JOB_COUNT %s" % dict(counts))
    sides = Counter((item["exp_id"], item["name"]) for item in jobs if item["block"] == "L")
    for key in DROPS:
        if sides[("L_%s" % key, "%s_redfull" % key)] != 5:
            raise SystemExit("SIDE_COUNT %s" % key)
        if sides[("L_%s" % key, "%s_bluefull" % key)] != 5:
            raise SystemExit("SIDE_COUNT %s" % key)


def run_id(item):
    return "%s_run%02d" % (item["exp_id"], item["idx"])


def run_one(item):
    rid = run_id(item)
    dest = JSON_DIR / ("%s.json" % rid)
    log_path = LOG_DIR / ("%s.log" % rid)
    if valid_json(dest):
        print("SKIP %s" % rid, flush=True)
        return True
    red, blue = item["red"], item["blue"]
    env = os.environ.copy()
    env.pop("SIM_RAW_DIR", None)
    env.update({
        "SIM_EXP_PROTOCOL": "1",
        "SIM_AUTO_QUIT": "1",
        "SIM_SHOW_GUI": "0",
        "SIM_USE_GODOT_HEADLESS": "0",
        "SIM_FUSION_RED": str(red[0]),
        "SIM_FOCUS_RED": str(red[1]),
        "SIM_FORMATION_RED": str(red[2]),
        "SIM_RESCUE_RED": str(red[3]),
        "SIM_FUSION_BLUE": str(blue[0]),
        "SIM_FOCUS_BLUE": str(blue[1]),
        "SIM_FORMATION_BLUE": str(blue[2]),
        "SIM_RESCUE_BLUE": str(blue[3]),
        "SIM_FUSION_MODE": item["mode"],
        "SIM_FUSION_MODE_RED": item["mode"],
        "SIM_FUSION_MODE_BLUE": item["mode"],
        "SIM_GATE": str(item["gate"]),
        "SIM_GATE_RED": str(item["gate"]),
        "SIM_GATE_BLUE": str(item["gate"]),
        "SIM_DELAY_MS": str(item["delay"]),
        "SIM_LOSS": str(item["loss"]),
        "SIM_FOV_SCALE": "1",
        "SIM_CAM_W": str(item["cam"][0]),
        "SIM_CAM_H": str(item["cam"][1]),
        "SIM_EXTRA_MS": "0",
        "SIM_MATCH_SECONDS": "120",
        "SIM_ALPHA": "0.5",
        "SIM_BETA": "0.3",
        "SIM_GAMMA": "0.2",
        "SIM_LAMBDA": "1",
        "SIM_D_REF": "5",
        "SIM_CALIB_RED": str(item["calib"][0]),
        "SIM_CALIB_BLUE": str(item["calib"][1]),
        "SIM_BLOCK": item["block"],
        "SIM_EXP_ID": item["exp_id"],
        "SIM_EXP_NAME": item["name"],
        "SIM_RUN_INDEX": str(item["idx"]),
        "SIM_RUN_ID": rid,
        "SIM_METRICS_OUT": str(dest),
    })
    for attempt in (1, 2):
        print("RUN %s attempt=%d" % (rid, attempt), flush=True)
        kill_godot()
        with log_path.open("w", encoding="utf-8") as handle:
            proc = subprocess.run(
                ["timeout", TIMEOUT, str(ROOT / "run_godot_nvidia.sh"), "solo"],
                env=env, stdout=handle, stderr=subprocess.STDOUT,
            )
        if valid_json(dest):
            print("OK %s rc=%s" % (rid, proc.returncode), flush=True)
            return True
        print("RETRY %s attempt=%d rc=%s" % (rid, attempt, proc.returncode), flush=True)
    print("FAIL %s" % rid, flush=True)
    with (OUT / "failures.log").open("a", encoding="utf-8") as handle:
        handle.write(rid + "\n")
    return False


def gate_fixture():
    def same_track(distance_m, gate_m=1.5):
        return distance_m <= gate_m
    rows = [(0.5, same_track(0.5)), (1.5, same_track(1.5)), (3.0, same_track(3.0))]
    path = OUT / "gate_fixture.json"
    path.write_text(json.dumps({
        "rule": "written 1.5 m rule only; this does not call the engine",
        "rows": [{"distance_m": d, "same_track": bool(s)} for d, s in rows],
    }, indent=2), encoding="utf-8")
    print("GATE_FIXTURE", rows, flush=True)


def wilson(k, n, z=1.959963984540054):
    if n <= 0:
        return None
    p = k / float(n)
    z2 = z * z
    den = 1.0 + z2 / n
    center = (p + z2 / (2.0 * n)) / den
    half = z * math.sqrt(p * (1.0 - p) / n + z2 / (4.0 * n * n)) / den
    return [center - half, center + half]


def binom_sf(k, n):
    if n <= 0:
        return None
    if k <= 0:
        return 1.0
    pmf = 1.0
    total = 0.0
    for i in range(n + 1):
        if i >= k:
            total += pmf
        if i < n:
            pmf = pmf * (n - i) / (i + 1)
    return total / (2.0 ** n)


def holm(pvals):
    order = sorted(range(len(pvals)), key=lambda i: pvals[i])
    adj = [0.0] * len(pvals)
    running = 0.0
    m = len(pvals)
    for rank, i in enumerate(order):
        running = max(running, (m - rank) * pvals[i])
        adj[i] = min(1.0, running)
    return adj


def bootstrap_mean(values, rng):
    xs = [float(v) for v in values if v is not None]
    if not xs:
        return None
    n = len(xs)
    means = []
    for _ in range(4000):
        total = 0.0
        for _j in range(n):
            total += xs[rng.randrange(n)]
        means.append(total / n)
    means.sort()
    return {
        "n": n,
        "mean": sum(xs) / n,
        "lo": means[int(0.025 * (len(means) - 1))],
        "hi": means[int(0.975 * (len(means) - 1))],
    }


def full_side_won(data):
    name = str(data.get("exp_name") or "")
    winner = data.get("winner")
    if name.endswith("redfull") or name == "red_coop":
        return winner == "red"
    if name.endswith("bluefull") or name == "blue_coop":
        return winner == "blue"
    return None


def summarize():
    rows = []
    for path in sorted(JSON_DIR.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if data.get("winner") in (None, "") or data.get("sim_time") is None:
            continue
        rows.append(data)
    grouped = defaultdict(list)
    for data in rows:
        grouped[str(data.get("exp_id"))].append(data)
    rng = random.Random(0)
    cells = {}
    for exp_id, items in sorted(grouped.items()):
        reds = sum(1 for d in items if d.get("winner") == "red")
        coop = [full_side_won(d) for d in items]
        coop = [v for v in coop if v is not None]
        cell = {
            "n": len(items),
            "red_wins": reds,
            "blue_wins": len(items) - reds,
            "red_wilson": wilson(reds, len(items)),
            "pos_err": bootstrap_mean([d.get("pos_err_mean_m") for d in items], rng),
            "aim_err": bootstrap_mean([d.get("aim_err_mean_deg") for d in items], rng),
            "process_p50": bootstrap_mean([d.get("process_ms_p50") for d in items], rng),
            "queue_p95_max": max([float(d.get("queue_p95") or 0) for d in items] or [0]),
            "dropped_max": max([int(d.get("dropped") or 0) for d in items] or [0]),
            "zero_shot": [
                d.get("run_id") for d in items
                if int(d.get("red_shots") or 0) == 0 or int(d.get("blue_shots") or 0) == 0
            ],
            "bad_limit": [
                d.get("run_id") for d in items
                if float(d.get("match_time_limit") or 0) != 120.0
            ],
        }
        if coop:
            wins = sum(1 for v in coop if v)
            cell["full_side_wins"] = wins
            cell["full_side_n"] = len(coop)
            cell["full_side_wilson"] = wilson(wins, len(coop))
            cell["full_side_p_ge"] = binom_sf(wins, len(coop))
        cells[exp_id] = cell
    l_ids = ["L_fusion", "L_focus", "L_formation", "L_rescue"]
    pvals = []
    for exp_id in l_ids:
        cell = cells.get(exp_id) or {}
        pvals.append(float(cell.get("full_side_p_ge") or 1.0))
    adjusted = holm(pvals) if len(pvals) == 4 else []
    for exp_id, p_adj in zip(l_ids, adjusted):
        if exp_id in cells:
            cells[exp_id]["holm_p"] = p_adj
    payload = {"n_json": len(rows), "cells": cells}
    (OUT / "summary.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print("SUMMARY", len(rows), flush=True)


def _self_check():
    if abs(binom_sf(20, 20) - 1.0 / float(2 ** 20)) > 1e-12:
        raise SystemExit("BINOM_CHECK")
    if abs(binom_sf(0, 10) - 1.0) > 1e-12:
        raise SystemExit("BINOM_CHECK")
    if abs(binom_sf(10, 20) - 0.5880985260009766) > 1e-9:
        raise SystemExit("BINOM_CHECK")
    lo, hi = wilson(15, 20)
    if not (lo > 0.5 and hi < 1.0):
        raise SystemExit("WILSON_CHECK")


def main():
    _self_check()
    if not Path("/tmp/.X11-unix/X1").exists():
        raise SystemExit("NO_DISPLAY_X1")
    OUT.mkdir(parents=True, exist_ok=True)
    JSON_DIR.mkdir(exist_ok=True)
    LOG_DIR.mkdir(exist_ok=True)
    jobs = build_jobs()
    check_jobs(jobs)
    (OUT / "status.txt").write_text("running\n", encoding="utf-8")
    (OUT / "runner.pid").write_text(str(os.getpid()) + "\n", encoding="utf-8")
    (OUT / "设计说明.txt").write_text(
        "新批次 revision_20261003_formal220。每局 120 秒。\n"
        "第一类四种对阵各 20 局：W_redfull、W_bluefull、S_bothon、S_bothoff。\n"
        "第二类每个编号 10 局。L_fusion、L_focus、L_formation、L_rescue\n"
        "各为 5 局红方四项全开对蓝方只关该项，加 5 局交换出生侧。\n"
        "同一编号内种子为 1 到该编号的局数。胜或负都保留。崩溃只重试一次。\n"
        "不读取以前的结果目录，也不修改论文。\n",
        encoding="utf-8",
    )
    print("JOBS %d" % len(jobs), flush=True)
    failed = 0
    done = 0
    for item in jobs:
        ok = run_one(item)
        done += 1
        if not ok:
            failed += 1
        if done % 5 == 0:
            print("PROGRESS %d/%d failed=%d" % (done, len(jobs), failed), flush=True)
    gate_fixture()
    try:
        summarize()
    except Exception as exc:
        print("SUMMARY_FAIL %s" % exc, flush=True)
    state = "done" if failed == 0 else "incomplete"
    (OUT / "status.txt").write_text(state + "\n", encoding="utf-8")
    print("STATUS %s failed=%d" % (state, failed), flush=True)
    print("BOTH_DONE", flush=True)


if __name__ == "__main__":
    main()

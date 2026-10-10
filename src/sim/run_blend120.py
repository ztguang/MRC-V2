#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Score, sensitivity, and calibration matches with SIM_BLEND_AIM=1.

Does not read or write revision_20261003_formal220. A finished game is kept.
A crash, or a game whose blend path did not run, stops the batch.
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
OUT = Path("/root/lunwen/sim/godot/logs/revision_20261004_blend")
JSON_DIR = OUT / "json"
LOG_DIR = OUT / "logs"
TIMEOUT = "1500"
GODOT_MARK = "/usr/local/bin/godot --path /root/lunwen/sim/godot"
FULL = (1, 1, 1, 1)
# mode, alpha, beta, gamma, lambda, delay_ms, calib pair
CELLS = [
    ("B_proposed", "proposed", 0.5, 0.3, 0.2, 1.0, 0, (0, 0)),
    ("B_uniform", "uniform", 0.5, 0.3, 0.2, 1.0, 0, (0, 0)),
    ("B_nearest", "nearest", 0.5, 0.3, 0.2, 1.0, 0, (0, 0)),
    ("B_legacy", "legacy", 0.5, 0.3, 0.2, 1.0, 0, (0, 0)),
    ("B_eq", "proposed", 0.333, 0.333, 0.334, 1.0, 0, (0, 0)),
    ("B_conf", "proposed", 0.8, 0.1, 0.1, 1.0, 0, (0, 0)),
    ("B_dist", "proposed", 0.1, 0.8, 0.1, 1.0, 0, (0, 0)),
    ("B_lam05", "proposed", 0.5, 0.3, 0.2, 0.5, 0, (0, 0)),
    ("B_lam20", "proposed", 0.5, 0.3, 0.2, 2.0, 0, (0, 0)),
    ("B_d400", "proposed", 0.5, 0.3, 0.2, 1.0, 400, (0, 0)),
    ("B_calib0", "proposed", 0.5, 0.3, 0.2, 1.0, 0, (1, 1)),
    ("B_calib400", "proposed", 0.5, 0.3, 0.2, 1.0, 400, (1, 1)),
]


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


def build_jobs():
    jobs = []
    for idx in range(1, 11):
        for exp_id, mode, alpha, beta, gamma, lam, delay, calib in CELLS:
            jobs.append({
                "exp_id": exp_id, "idx": idx, "mode": mode,
                "alpha": alpha, "beta": beta, "gamma": gamma, "lam": lam,
                "delay": delay, "calib": calib,
            })
    return jobs


def check_jobs(jobs):
    counts = Counter(item["exp_id"] for item in jobs)
    expect = {row[0]: 10 for row in CELLS}
    if counts != Counter(expect) or len(jobs) != 120:
        raise SystemExit("JOB_COUNT %s" % dict(counts))


def run_id(item):
    return "%s_run%02d" % (item["exp_id"], item["idx"])


def path_ok(data):
    if int(data.get("blend_aim") or 0) != 1:
        return False
    if int(data.get("blend_n") or 0) <= 0:
        return False
    if int(data.get("protocol") or 0) != 1:
        return False
    if float(data.get("match_time_limit") or 0) != 120.0:
        return False
    if int(data.get("red_shots") or 0) <= 0 or int(data.get("blue_shots") or 0) <= 0:
        return False
    return True


def run_one(item):
    rid = run_id(item)
    dest = JSON_DIR / ("%s.json" % rid)
    log_path = LOG_DIR / ("%s.log" % rid)
    if valid_json(dest):
        data = json.loads(dest.read_text(encoding="utf-8"))
        if not path_ok(data):
            print("BAD_KEPT %s" % rid, flush=True)
            return False
        print("SKIP %s" % rid, flush=True)
        return True
    env = os.environ.copy()
    env.pop("SIM_RAW_DIR", None)
    env.update({
        "SIM_EXP_PROTOCOL": "1",
        "SIM_AUTO_QUIT": "1",
        "SIM_SHOW_GUI": "0",
        "SIM_USE_GODOT_HEADLESS": "0",
        "SIM_BLEND_AIM": "1",
        "SIM_FUSION_RED": "1", "SIM_FOCUS_RED": "1",
        "SIM_FORMATION_RED": "1", "SIM_RESCUE_RED": "1",
        "SIM_FUSION_BLUE": "1", "SIM_FOCUS_BLUE": "1",
        "SIM_FORMATION_BLUE": "1", "SIM_RESCUE_BLUE": "1",
        "SIM_FUSION_MODE": item["mode"],
        "SIM_FUSION_MODE_RED": item["mode"],
        "SIM_FUSION_MODE_BLUE": item["mode"],
        "SIM_GATE": "1", "SIM_GATE_RED": "1", "SIM_GATE_BLUE": "1",
        "SIM_DELAY_MS": str(item["delay"]),
        "SIM_LOSS": "0",
        "SIM_FOV_SCALE": "1",
        "SIM_CAM_W": "320", "SIM_CAM_H": "240",
        "SIM_EXTRA_MS": "0",
        "SIM_MATCH_SECONDS": "120",
        "SIM_ALPHA": str(item["alpha"]),
        "SIM_BETA": str(item["beta"]),
        "SIM_GAMMA": str(item["gamma"]),
        "SIM_LAMBDA": str(item["lam"]),
        "SIM_D_REF": "5",
        "SIM_CALIB_RED": str(item["calib"][0]),
        "SIM_CALIB_BLUE": str(item["calib"][1]),
        "SIM_BLOCK": "B",
        "SIM_EXP_ID": item["exp_id"],
        "SIM_EXP_NAME": item["exp_id"],
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
            data = json.loads(dest.read_text(encoding="utf-8"))
            if path_ok(data):
                print(
                    "OK %s rc=%s blend_n=%s multi=%s pos=%s"
                    % (rid, proc.returncode, data.get("blend_n"), data.get("blend_multi_n"), data.get("pos_err_mean_m")),
                    flush=True,
                )
                return True
            print("BAD_PATH %s blend_n=%s multi=%s shots=%s/%s" % (
                rid, data.get("blend_n"), data.get("blend_multi_n"),
                data.get("red_shots"), data.get("blue_shots"),
            ), flush=True)
            dest.rename(dest.with_suffix(".badjson"))
        else:
            print("RETRY %s attempt=%d rc=%s" % (rid, attempt, proc.returncode), flush=True)
    print("FAIL %s" % rid, flush=True)
    return False


def wilson(k, n, z=1.959963984540054):
    if n <= 0:
        return None
    p = k / float(n)
    z2 = z * z
    den = 1.0 + z2 / n
    center = (p + z2 / (2.0 * n)) / den
    half = z * math.sqrt(p * (1.0 - p) / n + z2 / (4.0 * n * n)) / den
    return [center - half, center + half]


def bootstrap_mean(values, rng):
    xs = [float(v) for v in values if isinstance(v, (int, float)) and float(v) >= 0.0]
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
        cells[exp_id] = {
            "n": len(items),
            "red_wins": reds,
            "red_wilson": wilson(reds, len(items)),
            "pos_err": bootstrap_mean([d.get("pos_err_mean_m") for d in items], rng),
            "aim_err": bootstrap_mean([d.get("aim_err_mean_deg") for d in items], rng),
            "blend_n": bootstrap_mean([d.get("blend_n") for d in items], rng),
            "blend_multi_n": bootstrap_mean([d.get("blend_multi_n") for d in items], rng),
            "lambda_eff": bootstrap_mean([d.get("lambda_eff_red") for d in items], rng),
            "lambda_n": bootstrap_mean([d.get("lambda_n_red") for d in items], rng),
            "age_ema": bootstrap_mean([d.get("age_ema_red") for d in items], rng),
            "capture_scale": bootstrap_mean([d.get("capture_scale_red") for d in items], rng),
            "formation_scale": bootstrap_mean([d.get("formation_scale_red") for d in items], rng),
            "alpha": items[0].get("alpha"),
            "beta": items[0].get("beta"),
            "gamma": items[0].get("gamma"),
            "lambda": items[0].get("lambda"),
            "delay_ms": items[0].get("delay_ms"),
            "calib_red": items[0].get("calib_red"),
            "fusion_mode": items[0].get("fusion_mode_red"),
        }
    (OUT / "summary.json").write_text(
        json.dumps({"n_json": len(rows), "cells": cells}, indent=2),
        encoding="utf-8",
    )
    print("SUMMARY", len(rows), flush=True)


def main():
    if not Path("/tmp/.X11-unix/X1").exists():
        raise SystemExit("NO_DISPLAY_X1")
    OUT.mkdir(parents=True, exist_ok=True)
    JSON_DIR.mkdir(exist_ok=True)
    LOG_DIR.mkdir(exist_ok=True)
    note = OUT / "设计说明.txt"
    if not note.exists():
        note.write_text(
            "SIM_BLEND_AIM=1。双方四项都打开。评分只作用在已选共享跟踪的1.5 m邻域内。\n"
            "开火仍要本车相机锁定。不改射速、移速、规避，不把敌方真值送进融合或瞄准。\n"
            "B_proposed 是本组对照。区间重叠则不写某种评分更好。\n"
            "不把权重改成误差最小的那一格。默认权重仍是 0.5、0.3、0.2，lambda=1。\n"
            "B_calib0 对 B_proposed，B_calib400 对 B_d400。只有区间不相交才写分开。\n"
            "不与 formal220 的定位误差混成同一列。不重跑第一类。\n"
            "blend_n 为 0 的局视为失败，不进入结论。\n",
            encoding="utf-8",
        )
    jobs = build_jobs()
    check_jobs(jobs)
    (OUT / "status.txt").write_text("running\n", encoding="utf-8")
    failed = 0
    for item in jobs:
        if not run_one(item):
            failed += 1
            (OUT / "status.txt").write_text("failed\n", encoding="utf-8")
            (OUT / "runner.log").open("a", encoding="utf-8").write("FAILED %s\n" % run_id(item))
            raise SystemExit(1)
    summarize()
    (OUT / "status.txt").write_text("done\n", encoding="utf-8")
    print("BOTH_DONE", flush=True)


if __name__ == "__main__":
    main()

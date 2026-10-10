#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""New 120s matrix on today's source. Does not touch older result directories."""
import json
import os
import signal
import subprocess
import time
from pathlib import Path

ROOT = Path("/root/lunwen/sim")
OUT = Path("/root/lunwen/sim/godot/logs/revision_20261003_fresh120")
JSON_DIR = OUT / "json"
LOG_DIR = OUT / "logs"
TIMEOUT = "1500"
GODOT_MARK = "/usr/local/bin/godot --path /root/lunwen/sim/godot"


def kill_godot():
    proc = Path("/proc")
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            raw = (entry / "cmdline").read_bytes()
        except OSError:
            continue
        cmd = raw.replace(b"\0", b" ").decode("utf-8", "replace")
        if GODOT_MARK in cmd:
            try:
                os.kill(int(entry.name), signal.SIGTERM)
            except OSError:
                pass
    time.sleep(0.4)


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
        delay=0, loss=0.0, fov=1.0, cam=(320, 240), extra=0,
        calib=(0, 0), weights=(0.5, 0.3, 0.2)):
    return {
        "block": block, "exp_id": exp_id, "name": name, "idx": idx,
        "red": red, "blue": blue, "mode": mode, "gate": gate,
        "delay": delay, "loss": loss, "fov": fov, "cam": cam, "extra": extra,
        "calib": calib, "weights": weights,
    }


def build_jobs():
    jobs = []
    # Category 1. Paired seeds across birth sides.
    for i in range(1, 21):
        jobs.append(job("W", "W_redfull", "red_coop", i, (1, 1, 1, 1), (0, 0, 0, 0)))
        jobs.append(job("W", "W_bluefull", "blue_coop", i, (0, 0, 0, 0), (1, 1, 1, 1)))
    # Category 2. Symmetric camp and mechanism baseline.
    for i in range(1, 13):
        jobs.append(job("S", "S_bothoff", "both_off", i, (0, 0, 0, 0), (0, 0, 0, 0)))
        jobs.append(job("S", "S_bothon", "both_on", i, (1, 1, 1, 1), (1, 1, 1, 1)))
    # Leave-one-out. Full side keeps four switches. Other side drops one.
    drops = {
        "fusion": (0, 1, 1, 1),
        "focus": (1, 0, 1, 1),
        "formation": (1, 1, 0, 1),
        "rescue": (1, 1, 1, 0),
    }
    for key, dropped in drops.items():
        for i in range(1, 9):
            jobs.append(job("L", f"L_{key}_redfull", key, i, (1, 1, 1, 1), dropped))
            jobs.append(job("L", f"L_{key}_bluefull", key, i, dropped, (1, 1, 1, 1)))
    for i in range(1, 9):
        both = (1, 1, 1, 1)
        jobs.append(job("C", "C_d100", "delay100", i, both, both, delay=100))
        jobs.append(job("C", "C_d400", "delay400", i, both, both, delay=400))
        jobs.append(job("C", "C_d100_loss", "delay100_loss30", i, both, both, delay=100, loss=0.3))
    for i in range(1, 9):
        both = (1, 1, 1, 1)
        jobs.append(job("P", "P_640", "cam640", i, both, both, cam=(640, 480)))
        jobs.append(job("F", "F_uniform", "uniform", i, both, both, mode="uniform"))
        jobs.append(job("F", "F_nearest", "nearest", i, both, both, mode="nearest"))
        jobs.append(job("F", "F_legacy", "legacy", i, both, both, mode="legacy"))
        jobs.append(job("G", "G_gateoff", "gate_off", i, both, both, gate=0))
        jobs.append(job("K", "K_calib0", "calib_0ms", i, both, both, calib=(1, 1)))
        jobs.append(job("K", "K_calib400", "calib_400ms", i, both, both, delay=400, calib=(1, 1)))
    return jobs


def run_id(item):
    return f"{item['exp_id']}_run{item['idx']:02d}"


def run_one(item):
    rid = run_id(item)
    dest = JSON_DIR / f"{rid}.json"
    log_path = LOG_DIR / f"{rid}.log"
    if valid_json(dest):
        print(f"SKIP {rid}", flush=True)
        return True
    red, blue = item["red"], item["blue"]
    alpha, beta, gamma = item["weights"]
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
        "SIM_FOV_SCALE": str(item["fov"]),
        "SIM_CAM_W": str(item["cam"][0]),
        "SIM_CAM_H": str(item["cam"][1]),
        "SIM_EXTRA_MS": str(item["extra"]),
        "SIM_MATCH_SECONDS": "120",
        "SIM_ALPHA": str(alpha),
        "SIM_BETA": str(beta),
        "SIM_GAMMA": str(gamma),
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
        print(f"RUN {rid} attempt={attempt}", flush=True)
        kill_godot()
        with log_path.open("w", encoding="utf-8") as handle:
            proc = subprocess.run(
                ["timeout", TIMEOUT, str(ROOT / "run_godot_nvidia.sh"), "solo"],
                env=env, stdout=handle, stderr=subprocess.STDOUT,
            )
        if valid_json(dest):
            print(f"OK {rid} rc={proc.returncode}", flush=True)
            return True
        print(f"RETRY {rid} attempt={attempt} rc={proc.returncode}", flush=True)
    print(f"FAIL {rid}", flush=True)
    with (OUT / "failures.log").open("a", encoding="utf-8") as handle:
        handle.write(rid + "\n")
    return False


def gate_fixture():
    """Distance gate on two synthetic observations. Not a match."""
    def same_track(distance_m, gate_m=1.5):
        return distance_m <= gate_m
    rows = [
        (0.5, same_track(0.5)),
        (1.5, same_track(1.5)),
        (3.0, same_track(3.0)),
    ]
    path = OUT / "gate_fixture.json"
    path.write_text(json.dumps({
        "rule": "two observations farther than 1.5 m are different tracks",
        "rows": [{"distance_m": d, "same_track": s} for d, s in rows],
    }, indent=2), encoding="utf-8")
    print("GATE_FIXTURE", rows, flush=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    JSON_DIR.mkdir(exist_ok=True)
    LOG_DIR.mkdir(exist_ok=True)
    if not Path("/tmp/.X11-unix/X1").exists():
        (OUT / "status.txt").write_text("failed_no_display\n", encoding="utf-8")
        raise SystemExit("NO_DISPLAY_X1")
    jobs = build_jobs()
    (OUT / "job_count.txt").write_text(str(len(jobs)) + "\n", encoding="utf-8")
    (OUT / "status.txt").write_text("running\n", encoding="utf-8")
    (OUT / "runner.pid").write_text(str(os.getpid()) + "\n", encoding="utf-8")
    print(f"JOBS {len(jobs)}", flush=True)
    failed = 0
    for item in jobs:
        if not run_one(item):
            failed += 1
    gate_fixture()
    state = "done" if failed == 0 else "incomplete"
    (OUT / "status.txt").write_text(state + "\n", encoding="utf-8")
    print(f"STATUS {state} failed={failed}", flush=True)


if __name__ == "__main__":
    main()

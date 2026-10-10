#!/bin/bash
# Small fair asymmetric batch. Both birth sides run the full count before any judgment.
# Red-full: fusion+focus+formation+rescue on red only. Blue-full: the same on blue only.
# Calibration off. Shot cooldown, speed, and evade stay at the fair protocol scales.
# Do not mix this directory with revision_20260924*.
set -u
ROOT=/root/lunwen/sim
OUT=$ROOT/godot/logs/revision_20261003_lanes
mkdir -p "$OUT/json" "$OUT/logs"
STATUS=$OUT/status.txt
echo "running" > "$STATUS"
echo $$ > "$OUT/runner.pid"
TIMEOUT_SEC=${SIM_MATCH_TIMEOUT:-1200}
N=12
unset SIM_RAW_DIR

kill_godot() {
  local proc cmd
  for proc in /proc/[0-9]*; do
    cmd=$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)
    case "$cmd" in
      *"/usr/local/bin/godot --path /root/lunwen/sim/godot"*)
        kill "${proc##*/}" 2>/dev/null || true
        ;;
    esac
  done
  sleep 0.4
}

run_one() {
  local block="$1" exp_id="$2" exp_name="$3" idx="$4"
  local fr="$5" fo="$6" fm="$7" fs="$8"
  local br="$9" bo="${10}" bm="${11}" bs="${12}"
  local mode_r="${13}" mode_b="${14}" gate_r="${15}" gate_b="${16}"
  local delay="${17}" loss="${18}" fov="${19}" camw="${20}" camh="${21}" extra="${22}"
  local run_idx
  run_idx=$(printf "%02d" "$idx")
  local run_id="${exp_id}_${exp_name}_run${run_idx}"
  local json="$OUT/json/${run_id}.json"
  local log="$OUT/logs/${run_id}.log"
  if python3 - "$json" << 'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    raise SystemExit(1)
try:
    d = json.loads(p.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(1)
ok = d.get("winner") not in (None, "") and d.get("sim_time") is not None and not d.get("error")
raise SystemExit(0 if ok else 1)
PY
  then
    echo "SKIP $run_id"
    return 0
  fi
  echo "RUN $run_id"
  export SIM_EXP_PROTOCOL=1
  export SIM_AUTO_QUIT=1
  export SIM_SHOW_GUI=0
  export SIM_USE_GODOT_HEADLESS=0
  export SIM_FUSION_RED="$fr" SIM_FOCUS_RED="$fo" SIM_FORMATION_RED="$fm" SIM_RESCUE_RED="$fs"
  export SIM_FUSION_BLUE="$br" SIM_FOCUS_BLUE="$bo" SIM_FORMATION_BLUE="$bm" SIM_RESCUE_BLUE="$bs"
  export SIM_FUSION_MODE=proposed
  export SIM_FUSION_MODE_RED="$mode_r"
  export SIM_FUSION_MODE_BLUE="$mode_b"
  export SIM_GATE=1
  export SIM_GATE_RED="$gate_r"
  export SIM_GATE_BLUE="$gate_b"
  export SIM_DELAY_MS="$delay"
  export SIM_LOSS="$loss"
  export SIM_FOV_SCALE="$fov"
  export SIM_CAM_W="$camw"
  export SIM_CAM_H="$camh"
  export SIM_EXTRA_MS="$extra"
  export SIM_MATCH_SECONDS=180
  export SIM_CALIB_RED=0 SIM_CALIB_BLUE=0
  export SIM_ALPHA=0.5 SIM_BETA=0.3 SIM_GAMMA=0.2 SIM_LAMBDA=1 SIM_D_REF=5
  export SIM_BLOCK="$block"
  export SIM_EXP_ID="$exp_id"
  export SIM_EXP_NAME="$exp_name"
  export SIM_RUN_INDEX="$idx"
  export SIM_RUN_ID="$run_id"
  export SIM_METRICS_OUT="$json"
  unset SIM_RAW_DIR
  local attempt
  for attempt in 1 2; do
    kill_godot
    set +e
    timeout "$TIMEOUT_SEC" "$ROOT/run_godot_nvidia.sh" solo >"$log" 2>&1
    local rc=$?
    set -e
    if python3 - "$json" << 'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    raise SystemExit(1)
d = json.loads(p.read_text(encoding="utf-8"))
raise SystemExit(0 if d.get("winner") not in (None, "") and d.get("sim_time") is not None else 1)
PY
    then
      echo "OK $run_id rc=$rc"
      echo "$run_id ok" >> "$OUT/progress.log"
      return 0
    fi
    echo "RETRY $run_id attempt=$attempt rc=$rc"
  done
  echo "FAIL $run_id" | tee -a "$OUT/failures.log"
  echo "$run_id fail" >> "$OUT/progress.log"
  return 0
}

echo "OUT=$OUT N=$N" | tee -a "$OUT/progress.log"
i=1
while [ "$i" -le "$N" ]; do
  run_one A A3 red_full "$i" 1 1 1 1  0 0 0 0  proposed proposed 1 1  0 0 1 320 240 0
  run_one A A4 blue_full "$i" 0 0 0 0  1 1 1 1  proposed proposed 1 1  0 0 1 320 240 0
  i=$((i + 1))
done
python3 /root/lunwen/sim/summarize_aimfair.py "$OUT" | tee "$OUT/summary.txt"
if [ -s "$OUT/failures.log" ]; then
  echo "incomplete" > "$STATUS"
else
  echo "complete" > "$STATUS"
fi

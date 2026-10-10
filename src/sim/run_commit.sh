#!/bin/bash
# Fresh-track commitment. Both sides keep cooperation. Fire rate unchanged.
set -u
ROOT=/root/lunwen/sim
OUT=/root/lunwen/sim/godot/logs/revision_20260924_commit2
mkdir -p "$OUT/json" "$OUT/logs"
echo running > "$OUT/status.txt"
TIMEOUT_SEC=1200

run_one() {
  local exp_id="$1" exp_name="$2" idx="$3" delay="$4" cred="$5" cblue="$6"
  local run_id
  run_id=$(printf "%s_%s_run%02d" "$exp_id" "$exp_name" "$idx")
  local json="$OUT/json/${run_id}.json"
  if python3 - "$json" << 'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    raise SystemExit(1)
d = json.loads(p.read_text(encoding="utf-8"))
raise SystemExit(0 if d.get("winner") not in (None, "") else 1)
PY
  then
    echo "SKIP $run_id"
    return 0
  fi
  echo "RUN $run_id"
  export SIM_EXP_PROTOCOL=1 SIM_AUTO_QUIT=1 SIM_SHOW_GUI=0 SIM_USE_GODOT_HEADLESS=0
  export SIM_FUSION_RED=1 SIM_FOCUS_RED=1 SIM_FORMATION_RED=1 SIM_RESCUE_RED=1
  export SIM_FUSION_BLUE=1 SIM_FOCUS_BLUE=1 SIM_FORMATION_BLUE=1 SIM_RESCUE_BLUE=1
  export SIM_FUSION_MODE=proposed SIM_GATE=1 SIM_LOSS=0 SIM_FOV_SCALE=1 SIM_EXTRA_MS=0
  export SIM_CAM_W=320 SIM_CAM_H=240
  export SIM_ALPHA=0.5 SIM_BETA=0.3 SIM_GAMMA=0.2 SIM_LAMBDA=1 SIM_D_REF=5
  export SIM_MATCH_SECONDS=180
  export SIM_DELAY_MS="$delay" SIM_CALIB_RED="$cred" SIM_CALIB_BLUE="$cblue"
  export SIM_EXP_ID="$exp_id" SIM_EXP_NAME="$exp_name" SIM_RUN_INDEX="$idx" SIM_RUN_ID="$run_id"
  export SIM_METRICS_OUT="$json"
  local attempt
  for attempt in 1 2; do
    ps -eo pid,cmd | awk '/\/usr\/local\/bin\/godot --path \/root\/lunwen\/sim\/godot/ {print $1}' | while read -r pid; do kill "$pid" 2>/dev/null || true; done
    sleep 0.4
    timeout "$TIMEOUT_SEC" "$ROOT/run_godot_nvidia.sh" solo >"$OUT/logs/${run_id}.log" 2>&1 || true
    if python3 - "$json" << 'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    raise SystemExit(1)
d = json.loads(p.read_text(encoding="utf-8"))
raise SystemExit(0 if d.get("winner") not in (None, "") else 1)
PY
    then
      echo "OK $run_id" | tee -a "$OUT/progress.log"
      return 0
    fi
    echo "RETRY $run_id"
  done
  echo "FAIL $run_id" | tee -a "$OUT/failures.log"
  return 0
}

calib_behind() {
  python3 - << 'PY'
import json
from pathlib import Path
root = Path("/root/lunwen/sim/godot/logs/revision_20260924_commit2/json")
w = n = w0 = w1 = 0
if root.exists():
    for p in root.glob("*.json"):
        d = json.loads(p.read_text(encoding="utf-8"))
        if d.get("winner") in (None, "") or d.get("sim_time") is None:
            continue
        eid = str(d.get("exp_id"))
        if eid == "W0":
            w0 += 1
            n += 1
            w += int(d.get("winner") == "red")
        elif eid == "W1":
            w1 += 1
            n += 1
            w += int(d.get("winner") == "blue")
print(f"SCORE {w}/{n} W0={w0} W1={w1}")
# Judge only after both birth sides have at least 4 matches.
if w0 >= 4 and w1 >= 4 and (2 * w) <= (n - 2):
    raise SystemExit(2)
raise SystemExit(0)
PY
}

loop_n() {
  local n="$1"; shift
  local i
  for i in $(seq 1 "$n"); do
    run_one "$1" "$2" "$i" "$3" "$4" "$5"
    if [ "$1" = "W0" ] || [ "$1" = "W1" ]; then
      if ! calib_behind; then
        echo "STOP_LOSING" | tee -a "$OUT/progress.log"
        echo stopped_losing > "$OUT/status.txt"
        exit 2
      fi
    fi
  done
}

for i in $(seq 1 16); do
  run_one W0 red_d0 "$i" 0 1 0
  run_one W1 blue_d0 "$i" 0 0 1
  if ! calib_behind; then
    echo "STOP_LOSING" | tee -a "$OUT/progress.log"
    echo stopped_losing > "$OUT/status.txt"
    exit 2
  fi
done
loop_n 12 W2 both_d0   0   1 1
loop_n 12 W3 both_d400 400 1 1
echo complete > "$OUT/status.txt"
echo "COMPLETE $(date -Is)" >> "$OUT/progress.log"

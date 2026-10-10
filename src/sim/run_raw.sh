#!/bin/bash
# Experiment S: both sides cooperative, calibration off, delay 0, 320x240.
# Logs raw pre-gate candidates. Does not change fire rate or feed truth into decisions.
set -u
ROOT=/root/lunwen/sim
OUT=/root/lunwen/sim/godot/logs/revision_20260924_raw
mkdir -p "$OUT/json" "$OUT/logs" "$OUT/cand"
echo running > "$OUT/status.txt"
: > "$OUT/failures.log"
TIMEOUT_SEC=1200

run_one() {
  local exp_id="$1" exp_name="$2" idx="$3"
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
  export SIM_ALPHA=0.5 SIM_BETA=0.3 SIM_GAMMA=0.2 SIM_LAMBDA=1 SIM_D_REF=5
  export SIM_MATCH_SECONDS=180
  export SIM_DELAY_MS=0 SIM_CALIB_RED=0 SIM_CALIB_BLUE=0
  export SIM_CAM_W=320 SIM_CAM_H=240
  export SIM_EXP_ID="$exp_id" SIM_EXP_NAME="$exp_name" SIM_RUN_INDEX="$idx" SIM_RUN_ID="$run_id"
  export SIM_METRICS_OUT="$json"
  export SIM_RAW_DIR="$OUT/cand"
  local attempt
  for attempt in 1 2; do
    local sweep
    for sweep in 1 2 3 4 5 6 7 8; do
      if ! ps -eo cmd | grep -q '/usr/local/bin/godot --path /root/lunwen/sim/godot'; then
        break
      fi
      ps -eo pid,cmd | awk '/\/usr\/local\/bin\/godot --path \/root\/lunwen\/sim\/godot/ {print $1}' | while read -r pid; do kill "$pid" 2>/dev/null || true; done
      sleep 0.4
    done
    timeout "$TIMEOUT_SEC" "$ROOT/run_godot_nvidia.sh" solo >"$OUT/logs/${run_id}.log" 2>&1 || true
    if python3 - "$json" "$OUT/cand/${run_id}.raw.jsonl" << 'PY'
import json, sys
from pathlib import Path
meta = Path(sys.argv[1])
raw = Path(sys.argv[2])
if not meta.exists() or not raw.exists():
    raise SystemExit(1)
d = json.loads(meta.read_text(encoding="utf-8"))
if d.get("winner") in (None, ""):
    raise SystemExit(1)
n = sum(1 for line in raw.open(encoding="utf-8") if line.strip())
if int(d.get("raw_n", 0)) <= 0 or n <= 0:
    raise SystemExit(1)
raise SystemExit(0)
PY
    then
      if grep -E "SCRIPT ERROR|Parse Error" "$OUT/logs/${run_id}.log" >/dev/null; then
        echo "SCRIPT $run_id" | tee -a "$OUT/failures.log"
        return 0
      fi
      echo "OK $run_id" | tee -a "$OUT/progress.log"
      return 0
    fi
    echo "RETRY $run_id"
  done
  echo "FAIL $run_id" | tee -a "$OUT/failures.log"
  return 0
}

i=1
while [ "$i" -le 16 ]; do
  run_one S0 both_d0 "$i"
  i=$((i + 1))
done

if [ -s "$OUT/failures.log" ]; then
  echo failed > "$OUT/status.txt"
  echo "FAILED $(date -Is)" >> "$OUT/progress.log"
  exit 1
fi
echo complete > "$OUT/status.txt"
echo "COMPLETE $(date -Is)" >> "$OUT/progress.log"
exit 0

#!/bin/bash
# Revision experiment matrix. Resumable: a JSON with winner is skipped.
set -u
ROOT=/root/lunwen/sim
OUT=${SIM_REVISION_OUT:-$ROOT/godot/logs/revision_20260924}
mkdir -p "$OUT/json" "$OUT/logs"
STATUS="$OUT/status.txt"
echo "running" > "$STATUS"
TIMEOUT_SEC=${SIM_MATCH_TIMEOUT:-1200}

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
raise SystemExit(0 if d.get("winner") not in (None, "") and d.get("sim_time") is not None and not d.get("error") else 1)
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
  export SIM_ALPHA=0.5 SIM_BETA=0.3 SIM_GAMMA=0.2 SIM_LAMBDA=1 SIM_D_REF=5
  export SIM_BLOCK="$block"
  export SIM_EXP_ID="$exp_id"
  export SIM_EXP_NAME="$exp_name"
  export SIM_RUN_INDEX="$idx"
  export SIM_RUN_ID="$run_id"
  export SIM_METRICS_OUT="$json"
  local attempt
  for attempt in 1 2; do
    pkill -f 'godot --path /root/lunwen/sim/godot' 2>/dev/null || true
    sleep 0.4
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

# block exp n  red(f,o,m,s) blue(f,o,m,s) modeR modeB gateR gateB delay loss fov camw camh extra
cell() {
  local n="$3"
  local i
  for i in $(seq 1 "$n"); do
    run_one "$@" 
    # run_one args are the cell args with idx inserted as 4th — call explicitly below
  done
}

# Explicit loops keep the argument order obvious.
loop_n() {
  local n="$1"; shift
  local i
  for i in $(seq 1 "$n"); do
    run_one "$1" "$2" "$3" "$i" "${@:4}"
  done
}

FULL_ON="1 1 1 1"
OFF="0 0 0 0"

echo "OUT=$OUT" | tee -a "$OUT/progress.log"

# Block A
loop_n 24 A A1 both_off            0 0 0 0  0 0 0 0  proposed proposed 1 1  0 0 1 320 240 0
loop_n 24 A A2 both_full           1 1 1 1  1 1 1 1  proposed proposed 1 1  0 0 1 320 240 0
loop_n 24 A A3 red_full_blue_off   1 1 1 1  0 0 0 0  proposed proposed 1 1  0 0 1 320 240 0
loop_n 24 A A4 red_off_blue_full   0 0 0 0  1 1 1 1  proposed proposed 1 1  0 0 1 320 240 0

# Block B leave-one-out, full side vs missing one module. Side swap.
loop_n 16 B B1 full_vs_nofusion_redfull   1 1 1 1  0 1 1 1  proposed proposed 1 1  0 0 1 320 240 0
loop_n 16 B B1s full_vs_nofusion_bluefull 0 1 1 1  1 1 1 1  proposed proposed 1 1  0 0 1 320 240 0
loop_n 16 B B2 full_vs_nofocus_redfull    1 1 1 1  1 0 1 1  proposed proposed 1 1  0 0 1 320 240 0
loop_n 16 B B2s full_vs_nofocus_bluefull  1 0 1 1  1 1 1 1  proposed proposed 1 1  0 0 1 320 240 0
loop_n 16 B B3 full_vs_noform_redfull     1 1 1 1  1 1 0 1  proposed proposed 1 1  0 0 1 320 240 0
loop_n 16 B B3s full_vs_noform_bluefull   1 1 0 1  1 1 1 1  proposed proposed 1 1  0 0 1 320 240 0
loop_n 16 B B4 full_vs_norescue_redfull   1 1 1 1  1 1 1 0  proposed proposed 1 1  0 0 1 320 240 0
loop_n 16 B B4s full_vs_norescue_bluefull 1 1 1 0  1 1 1 1  proposed proposed 1 1  0 0 1 320 240 0

# Block C fusion baselines, both teams decision on
loop_n 16 C C1 proposed_vs_uniform        1 1 1 1  1 1 1 1  proposed uniform 1 1  0 0 1 320 240 0
loop_n 16 C C1s uniform_vs_proposed       1 1 1 1  1 1 1 1  uniform proposed 1 1  0 0 1 320 240 0
loop_n 16 C C2 proposed_vs_nearest        1 1 1 1  1 1 1 1  proposed nearest 1 1  0 0 1 320 240 0
loop_n 16 C C2s nearest_vs_proposed       1 1 1 1  1 1 1 1  nearest proposed 1 1  0 0 1 320 240 0

# Block D association gate
loop_n 16 D D1 gate_vs_nogate             1 1 1 1  1 1 1 1  proposed proposed 1 0  0 0 1 320 240 0
loop_n 16 D D1s nogate_vs_gate            1 1 1 1  1 1 1 1  proposed proposed 0 1  0 0 1 320 240 0

# Block E legacy dimensional score vs nondimensional
loop_n 16 E E1 proposed_vs_legacy         1 1 1 1  1 1 1 1  proposed legacy 1 1  0 0 1 320 240 0
loop_n 16 E E1s legacy_vs_proposed        1 1 1 1  1 1 1 1  legacy proposed 1 1  0 0 1 320 240 0

# Block F channel
loop_n 16 F F1 delay100                   1 1 1 1  1 1 1 1  proposed proposed 1 1  100 0 1 320 240 0
loop_n 16 F F2 delay400                   1 1 1 1  1 1 1 1  proposed proposed 1 1  400 0 1 320 240 0
loop_n 16 F F3 delay100_loss30            1 1 1 1  1 1 1 1  proposed proposed 1 1  100 0.3 1 320 240 0
loop_n 16 F F4 delay400_proposed_vs_uniform 1 1 1 1  1 1 1 1  proposed uniform 1 1  400 0 1 320 240 0
loop_n 16 F F4s delay400_uniform_vs_proposed 1 1 1 1  1 1 1 1  uniform proposed 1 1  400 0 1 320 240 0

# Block G compute
loop_n 12 G G2 res640                     1 1 1 1  1 1 1 1  proposed proposed 1 1  0 0 1 640 480 0
loop_n 12 G G3 stall40                    1 1 1 1  1 1 1 1  proposed proposed 1 1  0 0 1 320 240 40

# Block H occlusion FOV
loop_n 16 H H1 fov_red_full               1 1 1 1  0 0 0 0  proposed proposed 1 1  0 0 0.6 320 240 0
loop_n 16 H H2 fov_blue_full              0 0 0 0  1 1 1 1  proposed proposed 1 1  0 0 0.6 320 240 0

echo "complete" > "$STATUS"
echo "COMPLETE $(date -Is)" | tee -a "$OUT/progress.log"

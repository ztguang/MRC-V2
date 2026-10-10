#!/bin/bash
# =============================================================================
# Fully automated paper experiments: groups A/B/C/D × N runs (default 10)
# Each run writes ONE primary metrics JSON (+ companion log).
#
# Naming:
#   expA_solo_both_run01.json
#   expB_coop_both_run01.json
#   expC_red_solo_blue_coop_run01.json
#   expD_red_coop_blue_solo_run01.json
#
# Usage:
#   /root/lunwen/sim/run_paper_experiments.sh           # all 40
#   /root/lunwen/sim/run_paper_experiments.sh 10         # N=10
#   /root/lunwen/sim/run_paper_experiments.sh 10 A       # only group A
#   /root/lunwen/sim/run_paper_experiments.sh 10 CD      # groups C and D
# =============================================================================
set -euo pipefail

ROOT=/root/lunwen/sim
GODOT_DIR=$ROOT/godot
STAMP=$(date +%Y%m%d_%H%M%S)
OUT_ROOT=${SIM_RESULTS_DIR:-$ROOT/godot/logs/paper_results_${STAMP}}
N=${1:-10}
ONLY=${2:-ABCD}

mkdir -p "$OUT_ROOT"/{expA_solo_both,expB_coop_both,expC_red_solo_blue_coop,expD_red_coop_blue_solo,logs,manifests}
export SIM_AUTO_QUIT=1
export GODOT_SILENCE_ROOT_WARNING=1
# Force no Godot GUI window for batch paper runs (overrides SSH/desktop DISPLAY)
export SIM_SHOW_GUI=0
export SIM_USE_GODOT_HEADLESS=1
unset DISPLAY
unset WAYLAND_DISPLAY

# Kill leftover Godot to avoid GPU contention
pkill -f 'godot --path /root/lunwen/sim/godot' 2>/dev/null || true
sleep 1

MANIFEST="$OUT_ROOT/manifests/runs_manifest.csv"
echo "exp_id,exp_name,run_index,run_id,json_path,log_path,cli_args,status,winner,sim_time,coop_side_won" > "$MANIFEST"

enrich_json_from_log() {
  local json="$1"
  local log="$2"
  python3 - "$json" "$log" <<'PY'
import json, re, sys
from pathlib import Path
jp, lp = Path(sys.argv[1]), Path(sys.argv[2])
if not jp.exists():
    sys.exit(0)
rec = json.loads(jp.read_text(encoding="utf-8"))
text = lp.read_text(encoding="utf-8", errors="replace") if lp.exists() else ""
# Count mechanism events from console
rec["log_coop_rescue"] = len(re.findall(r"COOP RESCUE", text))
rec["log_fire_coop_focus"] = len(re.findall(r"reason=coop_focus_fire", text))
rec["log_fire_coop_rescue"] = len(re.findall(r"reason=coop_rescue_fire", text))
rec["log_fire_coop_shared"] = len(re.findall(r"reason=coop_shared", text))
rec["log_fire_vision"] = len(re.findall(r"FIRE VISION", text))
rec["log_fire_sensor"] = len(re.findall(r"FIRE SENSOR", text))
rec["log_out_count"] = len(re.findall(r"^OUT id=", text, re.M))
rec["log_hit_count"] = len(re.findall(r"HIT robot=", text))
# Prefer rescue_events from game if present; else log
if int(rec.get("rescue_events", 0) or 0) == 0 and rec["log_coop_rescue"] > 0:
    rec["rescue_events"] = rec["log_coop_rescue"]
jp.write_text(json.dumps(rec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("enriched", jp)
PY
}

run_group() {
  local exp_id="$1"
  local exp_name="$2"
  local subdir="$3"
  shift 3
  local args=("$@")
  local i
  for i in $(seq 1 "$N"); do
    local run_idx
    run_idx=$(printf "%02d" "$i")
    local run_id="${exp_id}_${exp_name}_run${run_idx}"
    local json="$OUT_ROOT/${subdir}/${run_id}.json"
    local log="$OUT_ROOT/logs/${run_id}.log"
    echo "============================================================"
    echo "[paper-exp] ${run_id}  args: ${args[*]}"
    echo "[paper-exp] json -> $json"
    echo "[paper-exp] log  -> $log"

    export SIM_EXP_ID="$exp_id"
    export SIM_EXP_NAME="$exp_name"
    export SIM_RUN_INDEX="$i"
    export SIM_RUN_ID="$run_id"
    export SIM_METRICS_OUT="$json"
    export SIM_AUTO_QUIT=1

    pkill -f 'godot --path /root/lunwen/sim/godot' 2>/dev/null || true
    sleep 0.5

    local status=0
    # 180s match + startup + quit margin
    set +e
    timeout 260 "$ROOT/run_godot_nvidia.sh" "${args[@]}" >"$log" 2>&1
    local rc=$?
    set -e
    if [ $rc -eq 0 ] || [ $rc -eq 124 ]; then
      status=ok
    else
      status="rc$rc"
    fi

    # If Godot failed to write JSON, synthesize from METRICS_JSON line
    if [ ! -f "$json" ]; then
      echo "[paper-exp] WARN missing JSON, trying log parse..."
      python3 - "$json" "$log" "$exp_id" "$exp_name" "$i" "$run_id" <<'PY'
import json, re, sys
from pathlib import Path
jp, lp, exp_id, exp_name, run_idx, run_id = sys.argv[1:7]
text = Path(lp).read_text(encoding="utf-8", errors="replace") if Path(lp).exists() else ""
m = re.search(r"METRICS_JSON (\{.*\})", text)
rec = {}
if m:
    try:
        rec = json.loads(m.group(1))
    except Exception as e:
        rec = {"parse_error": str(e)}
else:
    rec = {"error": "no METRICS_JSON in log", "log_tail": text[-2000:]}
rec.setdefault("exp_id", exp_id)
rec.setdefault("exp_name", exp_name)
rec.setdefault("run_index", int(run_idx))
rec.setdefault("run_id", run_id)
Path(jp).parent.mkdir(parents=True, exist_ok=True)
Path(jp).write_text(json.dumps(rec, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print("synthesized", jp)
PY
    fi

    enrich_json_from_log "$json" "$log"

    # Retry once if metrics incomplete (crash/timeout mid-match)
    if ! python3 - "$json" <<'PY'
import json, sys
from pathlib import Path
p=Path(sys.argv[1])
if not p.exists():
    sys.exit(1)
d=json.loads(p.read_text())
if d.get("error") or d.get("winner") is None or d.get("sim_time") is None:
    sys.exit(2)
sys.exit(0)
PY
    then
      echo "[paper-exp] RETRY invalid metrics for ${run_id}"
      pkill -f 'godot --path /root/lunwen/sim/godot' 2>/dev/null || true
      sleep 1
      set +e
      timeout 280 "$ROOT/run_godot_nvidia.sh" "${args[@]}" >"$log" 2>&1
      set -e
      enrich_json_from_log "$json" "$log"
    fi

    local winner="?"
    local simt="?"
    local csw="?"
    if [ -f "$json" ]; then
      winner=$(python3 -c "import json; d=json.load(open('$json')); print(d.get('winner','?'))" 2>/dev/null || echo "?")
      simt=$(python3 -c "import json; d=json.load(open('$json')); print(d.get('sim_time','?'))" 2>/dev/null || echo "?")
      csw=$(python3 -c "import json; d=json.load(open('$json')); print(d.get('coop_side_won','?'))" 2>/dev/null || echo "?")
    fi
    echo "${exp_id},${exp_name},${i},${run_id},${json},${log},${args[*]},${status},${winner},${simt},${csw}" >> "$MANIFEST"
    echo "[paper-exp] done ${run_id} status=${status} winner=${winner} t=${simt}"
  done
}

echo "[paper-exp] OUT_ROOT=$OUT_ROOT  N=$N  ONLY=$ONLY"

if [[ "$ONLY" == *A* ]]; then
  run_group expA solo_both expA_solo_both solo
fi
if [[ "$ONLY" == *B* ]]; then
  run_group expB coop_both expB_coop_both coop
fi
if [[ "$ONLY" == *C* ]]; then
  run_group expC red_solo_blue_coop expC_red_solo_blue_coop red solo blue coop
fi
if [[ "$ONLY" == *D* ]]; then
  run_group expD red_coop_blue_solo expD_red_coop_blue_solo red coop blue solo
fi

# Aggregate index
python3 - "$OUT_ROOT" <<'PY'
import json, csv
from pathlib import Path
root = Path(__import__("sys").argv[1])
rows = []
for p in sorted(root.rglob("exp*_run*.json")):
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        d = {"error": str(e), "path": str(p)}
    d["_path"] = str(p)
    rows.append(d)
idx = root / "manifests" / "all_runs.json"
idx.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
# flat CSV for Excel
fields = [
    "exp_id","exp_name","run_index","run_id","mode_red","mode_blue","winner","coop_side",
    "coop_side_won","sim_time","red_hits","blue_hits","red_shots","blue_shots",
    "red_accuracy_pct","blue_accuracy_pct","overall_accuracy_pct","red_alive","blue_alive",
    "fusion_assist_sum","fusion_valid_sum","rescue_events",
    "log_coop_rescue","log_fire_coop_focus","log_fire_vision","log_fire_sensor","_path"
]
csv_path = root / "manifests" / "all_runs.csv"
with csv_path.open("w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
    w.writeheader()
    for r in rows:
        w.writerow(r)
print("index", idx)
print("csv", csv_path)
print("n_json", len(rows))
PY

# Pointer for plot scripts
echo "$OUT_ROOT" > /root/lunwen/sim/godot/logs/LATEST_PAPER_RESULTS.txt
ln -sfn "$OUT_ROOT" /root/lunwen/sim/godot/logs/latest_paper_results

echo "============================================================"
echo "[paper-exp] COMPLETE"
echo "[paper-exp] Results dir: $OUT_ROOT"
echo "[paper-exp] JSON count:  $(find "$OUT_ROOT" -name 'exp*_run*.json' | wc -l)"
echo "[paper-exp] Manifest:    $MANIFEST"
echo "[paper-exp] Next: python3 /root/lunwen/sim/analysis/plot_exp1_symmetric.py"
echo "[paper-exp]        python3 /root/lunwen/sim/analysis/plot_exp2_asymmetric.py"
echo "[paper-exp]        python3 /root/lunwen/sim/analysis/plot_exp3_mechanism.py"

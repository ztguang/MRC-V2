#!/bin/bash
# One new-paper match, with a visible window.
# Usage: run_paper_match.sh <编号> <局序号>
# The launcher argument stays "solo". The four switches are set here.
# Results go to a new directory and do not replace the locked paper logs.
set -euo pipefail

ROOT="/root/lunwen/sim"
OUT="$ROOT/godot/logs/revision_rerun_gui"
JSON_DIR="$OUT/json"
LOG_DIR="$OUT/logs"

usage() {
    cat <<'EOF'
用法: run_paper_match.sh <编号> <局序号>

打开 GUI 窗口，只跑新版论文中的一局。局序号从 1 开始。
窗口在显示 :1 上。请用 TigerVNC 连接该显示来看。
结果写入 godot/logs/revision_rerun_gui，不覆盖已有论文记录。
同一时间只开一局。

第一批，不把式（3）用到瞄准上。前四格每格 20 局，其余每格 10 局。
  W_redfull      只开红方
  W_bluefull     只开蓝方
  S_bothon       双方都开。表3的 0 ms 用这 20 局
  S_bothoff      双方都关
  L_fusion       只关融合。奇数局红方全开，偶数局蓝方全开
  L_focus        只关优先级焦点。奇偶局同上
  L_formation    只关编队。奇偶局同上
  L_rescue       只关受击救援。奇偶局同上
  C_d100         双方都开，时延 100 ms
  C_d400         双方都开，时延 400 ms
  C_d100_loss    双方都开，时延 100 ms，丢包 30%
  P_640          双方都开，图像 640x480，时延 0
  G_gateoff      双方都开，关掉队内 1.5 m 距离检查

第二批，把式（3）用到已选跟踪上。双方四个开关都打开。每格 10 局。
  B_proposed     默认评分，权重 0.5、0.3、0.2，年龄系数 1，时延 0
  B_uniform      各观测同样权重，再对位置求平均
  B_nearest      只取距离最近的观测
  B_eq           三项权重大约各三分之一
  B_lam05        年龄系数 0.5，其余同默认
  B_lam20        年龄系数 2，其余同默认
  B_d400         未打开校准，时延 400 ms
  B_calib0       两侧打开校准，时延 0
  B_calib400     两侧打开校准，时延 400 ms

原稿脚本多跑、当前论文表未列入的格子也可以用同样命令跑:
  F_uniform F_nearest F_legacy K_calib0 K_calib400
  B_legacy B_conf B_dist

示例:
  run_paper_match.sh W_redfull 1
  run_paper_match.sh L_focus 2
  run_paper_match.sh B_calib400 7
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -ne 2 ]; then
    usage
    exit 0
fi

CELL="$1"
INDEX="$2"
if ! [[ "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -lt 1 ]; then
    echo "局序号必须是从 1 开始的整数: $INDEX" >&2
    exit 1
fi

case "$CELL" in
    W_redfull|W_bluefull|S_bothon|S_bothoff) MAX=20 ;;
    L_fusion|L_focus|L_formation|L_rescue) MAX=10 ;;
    C_d100|C_d400|C_d100_loss|P_640|G_gateoff) MAX=10 ;;
    F_uniform|F_nearest|F_legacy|K_calib0|K_calib400) MAX=10 ;;
    B_proposed|B_uniform|B_nearest|B_eq|B_lam05|B_lam20) MAX=10 ;;
    B_d400|B_calib0|B_calib400|B_legacy|B_conf|B_dist) MAX=10 ;;
    *)
        echo "未知编号: $CELL" >&2
        usage >&2
        exit 1
        ;;
esac
if [ "$INDEX" -gt "$MAX" ]; then
    echo "$CELL 的局序号只能是 1 到 $MAX，当前是 $INDEX" >&2
    exit 1
fi

# Defaults match the finished paper batches.
BLEND=0
MODE="proposed"
ALPHA=0.5
BETA=0.3
GAMMA=0.2
LAMBDA=1
DELAY=0
LOSS=0
GATE=1
CAM_W=320
CAM_H=240
CALIB_RED=0
CALIB_BLUE=0
RED="1 1 1 1"
BLUE="1 1 1 1"
BLOCK="S"
NAME="$CELL"

apply_drop() {
    local dropped="$1"
    if [ $((INDEX % 2)) -eq 1 ]; then
        RED="1 1 1 1"
        BLUE="$dropped"
        NAME="${CELL#L_}_redfull"
    else
        RED="$dropped"
        BLUE="1 1 1 1"
        NAME="${CELL#L_}_bluefull"
    fi
    BLOCK="L"
}

case "$CELL" in
    W_redfull)
        RED="1 1 1 1"; BLUE="0 0 0 0"; BLOCK="W"; NAME="red_coop" ;;
    W_bluefull)
        RED="0 0 0 0"; BLUE="1 1 1 1"; BLOCK="W"; NAME="blue_coop" ;;
    S_bothon)
        RED="1 1 1 1"; BLUE="1 1 1 1"; BLOCK="S"; NAME="both_on" ;;
    S_bothoff)
        RED="0 0 0 0"; BLUE="0 0 0 0"; BLOCK="S"; NAME="both_off" ;;
    L_fusion)    apply_drop "0 1 1 1" ;;
    L_focus)     apply_drop "1 0 1 1" ;;
    L_formation) apply_drop "1 1 0 1" ;;
    L_rescue)    apply_drop "1 1 1 0" ;;
    C_d100)      DELAY=100; BLOCK="C"; NAME="delay100" ;;
    C_d400)      DELAY=400; BLOCK="C"; NAME="delay400" ;;
    C_d100_loss) DELAY=100; LOSS=0.3; BLOCK="C"; NAME="delay100_loss30" ;;
    P_640)       CAM_W=640; CAM_H=480; BLOCK="P"; NAME="cam640" ;;
    G_gateoff)   GATE=0; BLOCK="G"; NAME="gate_off" ;;
    F_uniform)   MODE="uniform"; BLOCK="F"; NAME="uniform" ;;
    F_nearest)   MODE="nearest"; BLOCK="F"; NAME="nearest" ;;
    F_legacy)    MODE="legacy"; BLOCK="F"; NAME="legacy" ;;
    K_calib0)    CALIB_RED=1; CALIB_BLUE=1; BLOCK="K"; NAME="calib_0ms" ;;
    K_calib400)  DELAY=400; CALIB_RED=1; CALIB_BLUE=1; BLOCK="K"; NAME="calib_400ms" ;;
    B_proposed)  BLEND=1; BLOCK="B" ;;
    B_uniform)   BLEND=1; MODE="uniform"; BLOCK="B" ;;
    B_nearest)   BLEND=1; MODE="nearest"; BLOCK="B" ;;
    B_legacy)    BLEND=1; MODE="legacy"; BLOCK="B" ;;
    B_eq)        BLEND=1; ALPHA=0.333; BETA=0.333; GAMMA=0.334; BLOCK="B" ;;
    B_conf)      BLEND=1; ALPHA=0.8; BETA=0.1; GAMMA=0.1; BLOCK="B" ;;
    B_dist)      BLEND=1; ALPHA=0.1; BETA=0.8; GAMMA=0.1; BLOCK="B" ;;
    B_lam05)     BLEND=1; LAMBDA=0.5; BLOCK="B" ;;
    B_lam20)     BLEND=1; LAMBDA=2; BLOCK="B" ;;
    B_d400)      BLEND=1; DELAY=400; BLOCK="B" ;;
    B_calib0)    BLEND=1; CALIB_RED=1; CALIB_BLUE=1; BLOCK="B" ;;
    B_calib400)  BLEND=1; DELAY=400; CALIB_RED=1; CALIB_BLUE=1; BLOCK="B" ;;
esac

read -r RF RO RM RS <<<"$RED"
read -r BF BO BM BS <<<"$BLUE"
RID=$(printf "%s_run%02d" "$CELL" "$INDEX")
mkdir -p "$JSON_DIR" "$LOG_DIR"
DEST="$JSON_DIR/${RID}.json"
LOG="$LOG_DIR/${RID}.log"

if [ -e /tmp/.X11-unix/X1 ]; then
    :
else
    echo "没有显示 :1。请先打开 TigerVNC 的 :1，再运行本命令。" >&2
    exit 1
fi

echo "编号=$CELL 局序号=$INDEX 运行名=$RID"
echo "红方开关 融合=$RF 焦点=$RO 编队=$RM 救援=$RS"
echo "蓝方开关 融合=$BF 焦点=$BO 编队=$BM 救援=$BS"
echo "评分=$MODE 权重=$ALPHA,$BETA,$GAMMA 年龄系数=$LAMBDA"
echo "时延=${DELAY}ms 丢包=$LOSS 距离检查=$GATE 图像=${CAM_W}x${CAM_H}"
echo "校准 红=$CALIB_RED 蓝=$CALIB_BLUE 式（3）瞄准=$BLEND"
echo "窗口在显示 :1。记录: $DEST"

unset SIM_RAW_DIR || true
export SIM_EXP_PROTOCOL=1
export SIM_AUTO_QUIT=1
export SIM_SHOW_GUI=1
export SIM_USE_GODOT_HEADLESS=0
export FORCE_NVIDIA_X=1
export DISPLAY=:1
export SIM_BLEND_AIM="$BLEND"
export SIM_FUSION_RED="$RF" SIM_FOCUS_RED="$RO" SIM_FORMATION_RED="$RM" SIM_RESCUE_RED="$RS"
export SIM_FUSION_BLUE="$BF" SIM_FOCUS_BLUE="$BO" SIM_FORMATION_BLUE="$BM" SIM_RESCUE_BLUE="$BS"
export SIM_FUSION_MODE="$MODE"
export SIM_FUSION_MODE_RED="$MODE"
export SIM_FUSION_MODE_BLUE="$MODE"
export SIM_GATE="$GATE" SIM_GATE_RED="$GATE" SIM_GATE_BLUE="$GATE"
export SIM_DELAY_MS="$DELAY"
export SIM_LOSS="$LOSS"
export SIM_FOV_SCALE=1
export SIM_CAM_W="$CAM_W" SIM_CAM_H="$CAM_H"
export SIM_EXTRA_MS=0
export SIM_MATCH_SECONDS=120
export SIM_ALPHA="$ALPHA" SIM_BETA="$BETA" SIM_GAMMA="$GAMMA"
export SIM_LAMBDA="$LAMBDA" SIM_D_REF=5
export SIM_CALIB_RED="$CALIB_RED" SIM_CALIB_BLUE="$CALIB_BLUE"
export SIM_BLOCK="$BLOCK"
export SIM_EXP_ID="$CELL"
export SIM_EXP_NAME="$NAME"
export SIM_RUN_INDEX="$INDEX"
export SIM_RUN_ID="$RID"
export SIM_METRICS_OUT="$DEST"

# "solo" keeps the old cooperative fire-rate path off. Switches above decide cooperation.
"$ROOT/run_godot_nvidia.sh" solo >"$LOG" 2>&1
echo "本局结束。日志: $LOG"

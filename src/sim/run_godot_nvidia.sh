#!/bin/bash
set -euo pipefail

export LIBDIR=/root/lunwen/sim/godot/bin/linux-x86_64
export LD_LIBRARY_PATH="$LIBDIR:$LIBDIR/runtime${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GODOT_SILENCE_ROOT_WARNING=1

# Force NVIDIA proprietary GLX/EGL
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __NV_PRIME_RENDER_OFFLOAD=1
export __VK_LAYER_NV_optimus=NVIDIA_only
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
if [ -f /usr/share/vulkan/icd.d/nvidia_icd.json ]; then
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
fi

# No sound needed for sim — avoid ALSA ERR_CANT_OPEN spam
export SDL_AUDIODRIVER=dummy
export PULSE_SERVER=none

# ---------------------------------------------------------------------------
# Mode: per-team solo (无协同) | coop (有协同)
#
# Usage:
#   ./run_godot_nvidia.sh                         # both solo (default)
#   ./run_godot_nvidia.sh solo                    # both solo
#   ./run_godot_nvidia.sh coop                    # both coop
#   ./run_godot_nvidia.sh red solo blue coop      # red 无协同, blue 有协同
#   ./run_godot_nvidia.sh red coop blue solo
#   ./run_godot_nvidia.sh --red=solo --blue=coop
#   SIM_COOP_RED=solo SIM_COOP_BLUE=coop ./run_godot_nvidia.sh
#
# Extra Godot args after mode tokens are forwarded.
# ---------------------------------------------------------------------------

normalize_mode() {
  case "${1,,}" in
    solo|no_coop|none|0|off|false) echo "solo" ;;
    coop|with_coop|1|on|true|yes) echo "coop" ;;
    *) echo "" ;;
  esac
}

RED_MODE="solo"
BLUE_MODE="solo"
GODOT_EXTRA=()

print_help() {
  cat <<EOF
Usage: $0 [mode...] [godot-args...]

Global (both teams):
  solo | coop

Per-team (flexible A/B):
  red <solo|coop> blue <solo|coop>
  --red=solo --blue=coop

Env overrides (optional):
  SIM_COOP_MODE=solo|coop     # sets BOTH teams
  SIM_COOP_RED=solo|coop
  SIM_COOP_BLUE=solo|coop

Meaning:
  solo  无队内协同 — 3 车各自独立感知/决策（论文基线）
  coop  有队内协同 — 共享感知 + 角色/目标分配 + 虚拟领航编队（完整方法）

Examples:
  $0
  $0 solo
  $0 coop
  $0 red solo blue coop
  $0 red coop blue solo
  $0 --red=coop --blue=solo
  SIM_COOP_RED=solo SIM_COOP_BLUE=coop $0
EOF
}

# Parse CLI tokens
while [ $# -gt 0 ]; do
  arg="${1}"
  low="${arg,,}"
  case "$low" in
    -h|--help)
      print_help
      exit 0
      ;;
    solo|no_coop|0)
      RED_MODE="solo"; BLUE_MODE="solo"; shift ;;
    coop|with_coop|1)
      RED_MODE="coop"; BLUE_MODE="coop"; shift ;;
    --coop=0|--mode=solo)
      RED_MODE="solo"; BLUE_MODE="solo"; shift ;;
    --coop=1|--mode=coop)
      RED_MODE="coop"; BLUE_MODE="coop"; shift ;;
    --coop=*)
      m="$(normalize_mode "${arg#--coop=}")"
      if [ -n "$m" ]; then RED_MODE="$m"; BLUE_MODE="$m"; fi
      shift
      ;;
    --mode=*)
      m="$(normalize_mode "${arg#--mode=}")"
      if [ -n "$m" ]; then RED_MODE="$m"; BLUE_MODE="$m"; fi
      shift
      ;;
    --red=*)
      m="$(normalize_mode "${arg#--red=}")"
      if [ -n "$m" ]; then RED_MODE="$m"; fi
      shift
      ;;
    --blue=*)
      m="$(normalize_mode "${arg#--blue=}")"
      if [ -n "$m" ]; then BLUE_MODE="$m"; fi
      shift
      ;;
    red|r)
      shift
      if [ $# -eq 0 ]; then echo "ERROR: red needs solo|coop" >&2; exit 1; fi
      m="$(normalize_mode "$1")"
      if [ -z "$m" ]; then echo "ERROR: bad red mode: $1" >&2; exit 1; fi
      RED_MODE="$m"
      shift
      ;;
    blue|b)
      shift
      if [ $# -eq 0 ]; then echo "ERROR: blue needs solo|coop" >&2; exit 1; fi
      m="$(normalize_mode "$1")"
      if [ -z "$m" ]; then echo "ERROR: bad blue mode: $1" >&2; exit 1; fi
      BLUE_MODE="$m"
      shift
      ;;
    *)
      # Remaining args go to Godot
      break
      ;;
  esac
done

# Env overrides (explicit SIM_COOP_RED/BLUE win; SIM_COOP_MODE sets both if set)
if [ -n "${SIM_COOP_MODE:-}" ]; then
  m="$(normalize_mode "$SIM_COOP_MODE")"
  if [ -n "$m" ]; then RED_MODE="$m"; BLUE_MODE="$m"; fi
fi
if [ -n "${SIM_COOP_RED:-}" ]; then
  m="$(normalize_mode "$SIM_COOP_RED")"
  if [ -n "$m" ]; then RED_MODE="$m"; fi
fi
if [ -n "${SIM_COOP_BLUE:-}" ]; then
  m="$(normalize_mode "$SIM_COOP_BLUE")"
  if [ -n "$m" ]; then BLUE_MODE="$m"; fi
fi

# Legacy single mode for scripts that only read SIM_COOP_MODE
if [ "$RED_MODE" = "$BLUE_MODE" ]; then
  SIM_MODE="$RED_MODE"
else
  SIM_MODE="mixed"
fi

export SIM_COOP_MODE="$SIM_MODE"
export SIM_COOP_RED="$RED_MODE"
export SIM_COOP_BLUE="$BLUE_MODE"

echo "[run_godot_nvidia] SIM_COOP_RED=$SIM_COOP_RED  SIM_COOP_BLUE=$SIM_COOP_BLUE  (solo=无协同, coop=有协同)"

# ---------------------------------------------------------------------------
# Display / GUI policy
#
# Default: NO visible Godot window (batch / paper experiments).
#   SIM_SHOW_GUI=0 (default)  -> Godot --headless, or invisible virtual X
#   SIM_SHOW_GUI=1            -> allow real window (desktop debugging)
#   SIM_USE_GODOT_HEADLESS=1  (default when SIM_SHOW_GUI=0)
#   FORCE_NVIDIA_X=1          -> prefer NVIDIA virtual X :1 (no desktop :0)
# ---------------------------------------------------------------------------
SIM_SHOW_GUI="${SIM_SHOW_GUI:-0}"
if [ "$SIM_SHOW_GUI" = "1" ]; then
  SIM_USE_GODOT_HEADLESS="${SIM_USE_GODOT_HEADLESS:-0}"
else
  SIM_USE_GODOT_HEADLESS="${SIM_USE_GODOT_HEADLESS:-1}"
fi

start_nvidia_virtual_x() {
  # NEVER attach to desktop :0 — that is what makes the Godot GUI pop up.
  # Reuse the already-running TigerVNC/X server on :1 instead of starting a second Xorg.
  if [ -S /tmp/.X11-unix/X1 ]; then
    export DISPLAY=:1
    echo "[run_godot_nvidia] reusing existing DISPLAY=:1"
    return 0
  fi
  if pgrep -f 'Xorg :1' >/dev/null 2>&1; then
    export DISPLAY=:1
    return 0
  fi
  if ! command -v Xorg >/dev/null 2>&1; then
    return 1
  fi
  if [ ! -f /etc/X11/xorg.conf.d/10-nvidia-headless.conf ]; then
    return 1
  fi
  echo "[run_godot_nvidia] starting virtual NVIDIA Xorg :1 (no desktop GUI)..."
  # Drop inherited DISPLAY so Xorg child does not attach to a real session
  env -u DISPLAY Xorg :1 -config /etc/X11/xorg.conf.d/10-nvidia-headless.conf \
    -noreset -nolisten tcp +extension GLX \
    >/tmp/xorg-nvidia-1.log 2>&1 &
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.5
    if pgrep -f 'Xorg :1' >/dev/null 2>&1; then
      export DISPLAY=:1
      return 0
    fi
  done
  echo "[run_godot_nvidia] WARN: NVIDIA Xorg :1 failed to start (see /tmp/xorg-nvidia-1.log)"
  return 1
}

start_xvfb() {
  if pgrep -f 'Xvfb :99' >/dev/null 2>&1 || pgrep -x Xvfb >/dev/null 2>&1; then
    # Prefer :99 if already up
    if [ -S /tmp/.X11-unix/X99 ] || [ -e /tmp/.X99-lock ]; then
      export DISPLAY=:99
      return 0
    fi
  fi
  if ! command -v Xvfb >/dev/null 2>&1; then
    return 1
  fi
  echo "[run_godot_nvidia] starting Xvfb :99 (no desktop GUI)..."
  env -u DISPLAY Xvfb :99 -screen 0 1440x900x24 -ac +extension GLX +render -noreset \
    >/tmp/xvfb99.log 2>&1 &
  local i
  for i in 1 2 3 4 5 6 7 8; do
    sleep 0.4
    if [ -S /tmp/.X11-unix/X99 ] || pgrep -f 'Xvfb :99' >/dev/null 2>&1; then
      export DISPLAY=:99
      return 0
    fi
  done
  return 1
}

GODOT_DISPLAY_ARGS=()

if [ "$SIM_SHOW_GUI" = "1" ]; then
  echo "[run_godot_nvidia] SIM_SHOW_GUI=1 -> windowed mode allowed"
  # Only in GUI mode may we use an existing user display
  if [ -z "${DISPLAY:-}" ] || [ "${FORCE_NVIDIA_X:-0}" = "1" ]; then
    if ! start_nvidia_virtual_x; then
      if ! start_xvfb; then
        echo "[run_godot_nvidia] ERROR: no display available for GUI mode" >&2
        exit 2
      fi
    fi
  fi
  GODOT_DISPLAY_ARGS=(--audio-driver Dummy)
else
  # ---- Batch / paper mode: never show a window ----
  # Clear SSH/X11-forwarded or desktop DISPLAY so Godot cannot open on :0
  if [ -n "${DISPLAY:-}" ]; then
    echo "[run_godot_nvidia] ignoring inherited DISPLAY=$DISPLAY (SIM_SHOW_GUI=0)"
  fi
  unset DISPLAY
  unset WAYLAND_DISPLAY

  if [ "$SIM_USE_GODOT_HEADLESS" = "1" ]; then
    echo "[run_godot_nvidia] headless mode: godot --headless (no GUI window)"
    # --headless implies display-driver headless + audio Dummy
    GODOT_DISPLAY_ARGS=(--headless)
  else
    # Off-screen X only (still no window on the physical desktop)
    if [ "${FORCE_NVIDIA_X:-0}" = "1" ] && start_nvidia_virtual_x; then
      :
    elif start_nvidia_virtual_x; then
      :
    elif start_xvfb; then
      :
    else
      echo "[run_godot_nvidia] WARN: no virtual X; falling back to --headless"
      GODOT_DISPLAY_ARGS=(--headless)
    fi
    if [ ${#GODOT_DISPLAY_ARGS[@]} -eq 0 ]; then
      GODOT_DISPLAY_ARGS=(--audio-driver Dummy --display-driver x11)
      echo "[run_godot_nvidia] virtual DISPLAY=$DISPLAY (not desktop :0)"
    fi
  fi
fi

if [ -n "${DISPLAY:-}" ] && command -v glxinfo >/dev/null 2>&1; then
  renderer=$(DISPLAY="$DISPLAY" glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL renderer/{print $2; exit}')
  vendor=$(DISPLAY="$DISPLAY" glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL vendor/{print $2; exit}')
  echo "[run_godot_nvidia] DISPLAY=$DISPLAY"
  echo "[run_godot_nvidia] OpenGL vendor:   ${vendor:-n/a}"
  echo "[run_godot_nvidia] OpenGL renderer: ${renderer:-n/a}"
  # Do not hard-fail on software GL in headless batch mode (NVIDIA driver may be down)
  if [ "$SIM_SHOW_GUI" = "1" ] && echo "${renderer:-}" | grep -qi 'llvmpipe\|softpipe\|swrast'; then
    echo "[run_godot_nvidia] ERROR: software GL (llvmpipe). Try FORCE_NVIDIA_X=1 $0"
    exit 2
  fi
elif [ -n "${DISPLAY:-}" ]; then
  echo "[run_godot_nvidia] DISPLAY=$DISPLAY"
else
  echo "[run_godot_nvidia] DISPLAY=(none) headless engine display"
fi

cd /root/lunwen/sim/godot
# Pass per-team modes as user args after -- so Godot scripts can read OS.get_cmdline_user_args()
exec /usr/local/bin/godot --path /root/lunwen/sim/godot \
  "${GODOT_DISPLAY_ARGS[@]}" \
  -- --coop-red="$RED_MODE" --coop-blue="$BLUE_MODE" --coop="$SIM_MODE" "$@"

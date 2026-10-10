#!/bin/bash
# Bootstrap minimal toolchain in Debian WSL and rebuild the multi-robot sim.
set -euo pipefail

ROOT=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim
export DEBIAN_FRONTEND=noninteractive

echo "=== install packages ==="
sudo apt-get update -y
sudo apt-get install -y \
  build-essential cmake ninja-build pkg-config git curl ca-certificates \
  libopencv-dev libeigen3-dev libfmt-dev libspdlog-dev libyaml-cpp-dev \
  binutils file wget xz-utils

echo "=== check openvino paths ==="
# Prefer bundled runtime already next to the engine; for linking use sysroot if present.
SYSROOT="$ROOT/third_party/sysroot/usr"
if [ -d "$SYSROOT/lib/cmake" ]; then
  echo "sysroot cmake: $(ls "$SYSROOT/lib/cmake")"
fi

# OpenVINO from previous build was at /opt/openvino-dl - may be missing in this WSL.
if [ ! -d /opt/openvino-dl ]; then
  echo "OpenVINO toolkit path missing; will try OpenVINO_DIR from sysroot cmake"
fi

echo "=== download Godot 4.4 stable if missing ==="
GODOT_DIR=/home/ztg/godot
mkdir -p "$GODOT_DIR"
GODOT_BIN="$GODOT_DIR/Godot_v4.4.1-stable_linux.x86_64"
if [ ! -x "$GODOT_BIN" ]; then
  cd /tmp
  # 4.4.x matches compatibility_minimum 4.4 in gdextension
  URL="https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip"
  echo "Downloading $URL"
  wget -q --show-progress -O godot.zip "$URL" || curl -L -o godot.zip "$URL"
  unzip -o godot.zip -d "$GODOT_DIR"
  chmod +x "$GODOT_BIN" || chmod +x "$GODOT_DIR"/Godot*
  ls -la "$GODOT_DIR"
fi

echo "=== configure cmake ==="
cd "$ROOT/native"
BUILD="$ROOT/native/build_wsl"
mkdir -p "$BUILD"

# Try to locate OpenVINOConfig.cmake
OPENVINO_DIR=""
for cand in \
  "$SYSROOT/lib/cmake/openvino*" \
  /opt/openvino*/runtime/cmake \
  /usr/lib/cmake/openvino*; do
  for d in $cand; do
    if [ -f "$d/OpenVINOConfig.cmake" ] || [ -f "$d/openvinoConfig.cmake" ]; then
      OPENVINO_DIR="$d"
      break 2
    fi
  done
done

echo "OpenVINO_DIR candidate: ${OPENVINO_DIR:-none}"
CMAKE_ARGS=(
  -S "$ROOT/native"
  -B "$BUILD"
  -DCMAKE_BUILD_TYPE=Release
  -DGODOT_CPP_DIR="$ROOT/third_party/godot-cpp"
  -DSP_VISION_ROOT="$ROOT/../sp_vision_25"
  -DSP_LOCAL_SYSROOT="$ROOT/third_party/sysroot"
)
if [ -n "$OPENVINO_DIR" ]; then
  CMAKE_ARGS+=(-DOpenVINO_DIR="$OPENVINO_DIR")
fi

cmake "${CMAKE_ARGS[@]}"
cmake --build "$BUILD" -j"$(nproc)"

echo "=== outputs ==="
ls -la "$ROOT/godot/bin/linux-x86_64/"
echo "BUILD OK"

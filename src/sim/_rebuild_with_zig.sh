#!/bin/bash
set -euo pipefail

ROOT=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim
NATIVE="$ROOT/native"
BIN="$ROOT/godot/bin/linux-x86_64"
SYSROOT="$ROOT/third_party/sysroot/usr"
GODOT_CPP="$ROOT/third_party/godot-cpp"
GEN="$NATIVE/build/godot-cpp/gen/include"
GODOT_LIB="$NATIVE/build/bin/libgodot-cpp.linux.template_debug.x86_64.a"
ZIG=/mnt/c/Users/ztg/tools/zig/zig

echo "zig version: $($ZIG version)"
CXX=("$ZIG" c++)

INC=(
  -I"$GODOT_CPP/include"
  -I"$GODOT_CPP/gen/include"
  -I"$GODOT_CPP/gdextension"
  -I"$GEN"
  -I"$NATIVE/src"
)
FLAGS=(-std=c++17 -O2 -fPIC -DNDEBUG -target x86_64-linux-gnu)

echo "=== compile bridge ==="
"${CXX[@]}" "${FLAGS[@]}" "${INC[@]}" -c "$NATIVE/src/auto_aim_bridge.cpp" -o /tmp/auto_aim_bridge.o
"${CXX[@]}" "${FLAGS[@]}" "${INC[@]}" -c "$NATIVE/src/register_types.cpp" -o /tmp/register_types.o

echo "=== link libsp_vision_sim.so ==="
"${CXX[@]}" -target x86_64-linux-gnu -shared -o "$BIN/libsp_vision_sim.so" \
  /tmp/auto_aim_bridge.o /tmp/register_types.o "$GODOT_LIB" \
  -ldl -lpthread -lc -lm -lstdc++ \
  -Wl,-rpath,'$ORIGIN:$ORIGIN/runtime'

echo "=== compile worker ==="
"${CXX[@]}" "${FLAGS[@]}" -I"$NATIVE/src" -I"$SYSROOT/include" \
  -c "$NATIVE/src/worker_main.cpp" -o /tmp/worker_main.o

echo "=== link sp_vision_worker ==="
# Copy yaml-cpp next to worker if needed for SONAME resolution at runtime.
if [ -f "$SYSROOT/lib/libyaml-cpp.so.0.9" ] && [ ! -f "$BIN/libyaml-cpp.so.0.9" ]; then
  cp -n "$SYSROOT/lib/libyaml-cpp.so"* "$BIN/" 2>/dev/null || true
fi
# LIBRARY_PATH helps the linker find libsp_vision_engine without -rpath-link.
export LIBRARY_PATH="$BIN:$BIN/runtime:$SYSROOT/lib:${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="$BIN:$BIN/runtime:$SYSROOT/lib:${LD_LIBRARY_PATH:-}"
"${CXX[@]}" -target x86_64-linux-gnu -o "$BIN/sp_vision_worker" /tmp/worker_main.o \
  -L"$BIN" -lsp_vision_engine \
  -L"$SYSROOT/lib" -lyaml-cpp \
  -Wl,-rpath,'$ORIGIN:$ORIGIN/runtime' \
  -lc -lm -lstdc++ -lpthread -ldl

echo "=== verify ==="
ls -la "$BIN/libsp_vision_sim.so" "$BIN/sp_vision_worker"
if grep -aF "multi-robot" "$BIN/sp_vision_worker" >/dev/null; then
  echo "OK: multi-robot marker present"
else
  echo "WARN: multi-robot marker missing"
fi
file "$BIN/libsp_vision_sim.so" "$BIN/sp_vision_worker" 2>/dev/null || true
echo "REBUILD DONE"

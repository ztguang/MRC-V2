#!/bin/bash
# Rebuild only sp_vision_worker with libstdc++ ABI to match prebuilt engine/yaml-cpp.
set -euo pipefail

ROOT=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim
NATIVE="$ROOT/native"
BIN="$ROOT/godot/bin/linux-x86_64"
SYSROOT="$ROOT/third_party/sysroot/usr"
ZIG=/mnt/c/Users/ztg/tools/zig/zig

# Prefer system libstdc++ headers if present
STDINC=()
for d in /usr/include/c++/* /usr/include/x86_64-linux-gnu/c++/*; do
  [ -d "$d" ] && STDINC+=(-I"$d")
done

# Use zig c++ but force libstdc++ and glibc target
CXX=("$ZIG" c++ -target x86_64-linux-gnu -stdlib=libstdc++)

echo "=== compile worker_main with libstdc++ ==="
"${CXX[@]}" -std=c++17 -O2 -fPIC -DNDEBUG \
  -I"$NATIVE/src" -I"$SYSROOT/include" \
  -c "$NATIVE/src/worker_main.cpp" -o /tmp/worker_main.o

echo "=== link worker ==="
# Explicit .so paths avoid zig's selective library search quirks.
ENGINE_SO="$BIN/libsp_vision_engine.so"
YAML_SO=""
for cand in "$SYSROOT/lib/libyaml-cpp.so" "$SYSROOT/lib/libyaml-cpp.so.0.9" "$BIN/libyaml-cpp.so"; do
  if [ -f "$cand" ]; then YAML_SO="$cand"; break; fi
done
echo "engine=$ENGINE_SO yaml=$YAML_SO"

# Copy yaml next to binary for runtime
if [ -n "$YAML_SO" ]; then
  cp -f "$SYSROOT/lib"/libyaml-cpp.so* "$BIN/" 2>/dev/null || true
fi

"${CXX[@]}" -o "$BIN/sp_vision_worker" /tmp/worker_main.o \
  "$ENGINE_SO" "$YAML_SO" \
  -lc -lm -lstdc++ -lpthread -ldl \
  -Wl,-rpath,'$ORIGIN:$ORIGIN/runtime'

echo "=== verify ==="
ls -la "$BIN/sp_vision_worker"
if grep -aF "multi-robot" "$BIN/sp_vision_worker" >/dev/null; then
  echo "OK: multi-robot marker present"
else
  echo "WARN: multi-robot marker missing"
fi
# Quick symbol check
if command -v nm >/dev/null; then
  nm -D "$BIN/sp_vision_worker" 2>/dev/null | head || true
fi
echo "WORKER REBUILD DONE"

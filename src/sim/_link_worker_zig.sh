#!/bin/bash
set -euo pipefail
ROOT=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim
NATIVE="$ROOT/native"
BIN="$ROOT/godot/bin/linux-x86_64"
ZIG=/mnt/c/Users/ztg/tools/zig/zig

echo "=== compile worker (no yaml-cpp) ==="
"$ZIG" c++ -target x86_64-linux-gnu -std=c++17 -O2 -fPIC -DNDEBUG \
  -I"$NATIVE/src" \
  -c "$NATIVE/src/worker_main.cpp" -o /tmp/worker_main.o

echo "=== link worker against engine.so ==="
# Use --export-dynamic and force needed shared lib
"$ZIG" c++ -target x86_64-linux-gnu -o "$BIN/sp_vision_worker" /tmp/worker_main.o \
  -L"$BIN" -Wl,--no-as-needed -lsp_vision_engine -Wl,--as-needed \
  -lc -lm -lstdc++ -lpthread -ldl \
  -Wl,-rpath,'$ORIGIN:$ORIGIN/runtime'

echo "=== verify ==="
ls -la "$BIN/sp_vision_worker"
grep -aF "multi-robot" "$BIN/sp_vision_worker" && echo OK_MULTI || echo NO_MULTI
# Try loading
export LD_LIBRARY_PATH="$BIN:$BIN/runtime:${LD_LIBRARY_PATH:-}"
"$BIN/sp_vision_worker" 2>&1 | head -3 || true
# Run with config to see hello path — will hang waiting for pipe; use timeout
timeout 1 "$BIN/sp_vision_worker" "$ROOT/godot/configs/sim.yaml" 2>&1 || true
echo DONE

#!/bin/bash
BIN=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/godot/bin/linux-x86_64
# Use zig nm or objdump
ZIG=/mnt/c/Users/ztg/tools/zig/zig
echo "=== exports from engine ==="
if command -v nm >/dev/null; then
  nm -D "$BIN/libsp_vision_engine.so" | grep sp_engine | head -30
elif [ -x "$ZIG" ]; then
  "$ZIG" nm -D "$BIN/libsp_vision_engine.so" 2>/dev/null | grep sp_engine | head -30 || \
  "$ZIG" objdump -T "$BIN/libsp_vision_engine.so" 2>/dev/null | grep sp_engine | head -30
else
  # pure grep on binary
  grep -aoE 'sp_engine_[a-z_]+' "$BIN/libsp_vision_engine.so" | sort -u
fi
echo "=== readelf if any ==="
command -v readelf && readelf -Ws "$BIN/libsp_vision_engine.so" | grep sp_engine | head
# Try linking with absolute path
ls -la "$BIN/libsp_vision_engine.so"
# Check if loadable
export LD_LIBRARY_PATH="$BIN:$BIN/runtime"
ldd "$BIN/libsp_vision_engine.so" 2>&1 | head -20

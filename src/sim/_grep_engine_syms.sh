#!/bin/bash
BIN=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/godot/bin/linux-x86_64
echo "=== string symbols ==="
grep -aoE 'sp_engine_[a-zA-Z0-9_]+' "$BIN/libsp_vision_engine.so" | sort -u
echo "=== try zig objcopy/nm ==="
ZIG=/mnt/c/Users/ztg/tools/zig/zig
"$ZIG" objcopy --dump-section .dynstr=/tmp/dynstr "$BIN/libsp_vision_engine.so" 2>&1 || true
if [ -f /tmp/dynstr ]; then
  tr '\0' '\n' < /tmp/dynstr | grep sp_engine | head
fi
# Use llvm-nm from zig
ls /mnt/c/Users/ztg/tools/zig/lib 2>/dev/null | head
# Direct link test with verbose
"$ZIG" c++ -target x86_64-linux-gnu -v -o /tmp/tworker /tmp/worker_main.o \
  -L"$BIN" -lsp_vision_engine 2>&1 | tail -40

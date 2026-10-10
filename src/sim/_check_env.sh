#!/bin/bash
set -e
BIN=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/godot/bin/linux-x86_64
echo "=== binaries ==="
ls -la "$BIN"
echo "=== worker strings ==="
if command -v strings >/dev/null; then
  strings "$BIN/sp_vision_worker" | grep -E 'multi-robot|invalid frame|robot' | head -30
  strings "$BIN/libsp_vision_sim.so" | grep -E 'submit_frame|AutoAim|robot' | head -30
else
  echo "no strings"
  # fallback with grep on binary
  grep -aoE 'multi-robot|invalid frame header|OpenVINO CPU' "$BIN/sp_vision_worker" | head
fi
echo "=== tools ==="
command -v cmake || true
command -v g++ || true
command -v apt-get || true
echo "=== home ==="
ls -la /home/ztg | head -40
echo "=== godot search limited ==="
ls /home/ztg/Godot* 2>/dev/null || true
ls /opt/Godot* 2>/dev/null || true
ls /usr/local/bin 2>/dev/null || true

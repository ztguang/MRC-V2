#!/bin/bash
BIN=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/godot/bin/linux-x86_64
ls -la "$BIN/libsp_vision_sim.so" "$BIN/sp_vision_worker"
echo "=== sim.so markers ==="
grep -aoE 'submit_frame|poll_result|robot_id|multi-robot|initialize_with_runtime|AutoAimBridge' "$BIN/libsp_vision_sim.so" | sort -u | head -30
echo "=== worker markers ==="
grep -aoE 'multi-robot|invalid frame header|robot_id|OpenVINO CPU' "$BIN/sp_vision_worker" | sort -u | head -30
echo "=== mtimes ==="
stat -c '%y %n' "$BIN/libsp_vision_sim.so" "$BIN/sp_vision_worker"

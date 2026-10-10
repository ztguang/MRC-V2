#!/bin/bash
ROOT=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim
echo "=== sysroot ==="
ls -la "$ROOT/third_party/sysroot/usr" 2>/dev/null | head
ls "$ROOT/third_party/sysroot/usr/lib" 2>/dev/null | head -30
ls "$ROOT/third_party/sysroot/usr/include" 2>/dev/null | head -30
echo "=== packages ==="
ls -la "$ROOT/third_party/packages" 2>/dev/null
echo "=== build artifacts ==="
ls -la "$ROOT/native/build" | head -30
find "$ROOT/native/build" -name "libgodot*" 2>/dev/null | head
find "$ROOT/native/build" -name "CMakeCache.txt" 2>/dev/null
if [ -f "$ROOT/native/build/CMakeCache.txt" ]; then
  grep -E "CMAKE_CXX_COMPILER|OpenVINO|OpenCV_DIR|CMAKE_BUILD_TYPE" "$ROOT/native/build/CMakeCache.txt" | head -20
fi
echo "=== ldd worker ==="
ldd "$ROOT/godot/bin/linux-x86_64/sp_vision_worker" 2>&1 | head -40
echo "=== grep multi ==="
grep -ao 'multi-robot' "$ROOT/godot/bin/linux-x86_64/sp_vision_worker" || echo "no multi-robot string"
grep -ao 'SPV2\|SPV1\|0x535056' "$ROOT/godot/bin/linux-x86_64/sp_vision_worker" || true
grep -aoE '.{0,20}robot_id.{0,20}' "$ROOT/godot/bin/linux-x86_64/libsp_vision_sim.so" 2>/dev/null | head || true

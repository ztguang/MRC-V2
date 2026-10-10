#!/bin/bash
set -euo pipefail
OUT=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/godot/bin/linux-x86_64/runtime
cd "$OUT"

# OpenCV SONAME .406
for mod in core imgproc imgcodecs highgui calib3d dnn features2d flann; do
  if [ -f "libopencv_${mod}.so.4.6.0" ]; then
    ln -sfn "libopencv_${mod}.so.4.6.0" "libopencv_${mod}.so.406"
    ln -sfn "libopencv_${mod}.so.4.6.0" "libopencv_${mod}.so"
    echo "linked opencv $mod"
  fi
done

# fmt
if [ -f libfmt.so.9.1.0 ]; then
  ln -sfn libfmt.so.9.1.0 libfmt.so.9
  ln -sfn libfmt.so.9.1.0 libfmt.so
fi

# spdlog / yaml if present
ls -la libspdlog* libyaml* 2>/dev/null || echo "spdlog/yaml missing"

# Also copy into parent bin for non-rpath lookups
BIN=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/godot/bin/linux-x86_64
for f in libopencv_*.so* libfmt.so* libspdlog* libyaml*; do
  [ -e "$f" ] || continue
  cp -a "$f" "$BIN/" 2>/dev/null || true
done

echo "=== test worker deps ==="
export LD_LIBRARY_PATH="$BIN:$OUT:${LD_LIBRARY_PATH:-}"
ldd "$BIN/sp_vision_worker" 2>&1 | head -40

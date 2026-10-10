#!/bin/sh
# Run inside docker-desktop WSL (root Alpine) to rebuild multi-robot bridge+worker.
set -eu

ROOT=/mnt/host/c/Users/ztg/Desktop/lunwen/lunwen/sim
NATIVE="$ROOT/native"
BIN="$ROOT/godot/bin/linux-x86_64"
SYSROOT="$ROOT/third_party/sysroot/usr"
GODOT_CPP="$ROOT/third_party/godot-cpp"
BUILD_GEN="$NATIVE/build/godot-cpp/gen/include"
GODOT_LIB="$NATIVE/build/bin/libgodot-cpp.linux.template_debug.x86_64.a"

echo "=== install alpine build tools ==="
apk add --no-cache g++ make cmake linux-headers musl-dev 2>/dev/null || \
  apk add g++ make cmake linux-headers musl-dev

echo "=== CXX ==="
g++ --version | head -1

# Note: musl vs glibc - the existing libsp_vision_engine.so is glibc.
# Linking worker with musl g++ against glibc .so will FAIL at runtime.
# We only build bridge which is pure C++/godot-cpp static, but godot-cpp.a is also glibc!
# So we cannot use alpine musl toolchain against glibc objects.

echo "Alpine musl cannot link glibc godot-cpp/engine. Aborting this path."
echo "Need glibc-based compiler (Debian with packages or Ubuntu container)."
exit 2

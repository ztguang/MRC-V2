#!/bin/bash
# Install miniconda in user space and rebuild with real g++/libstdc++.
set -euo pipefail

ROOT=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim
NATIVE="$ROOT/native"
BIN="$ROOT/godot/bin/linux-x86_64"
SYSROOT="$ROOT/third_party/sysroot/usr"
GODOT_CPP="$ROOT/third_party/godot-cpp"
GEN="$NATIVE/build/godot-cpp/gen/include"
GODOT_LIB="$NATIVE/build/bin/libgodot-cpp.linux.template_debug.x86_64.a"
CONDA_ROOT=/home/ztg/miniconda3

if [ ! -x "$CONDA_ROOT/bin/conda" ]; then
  echo "=== install miniconda (user space) ==="
  # Download via PowerShell-placed installer if present, else fetch with perl sockets
  INSTALLER=/tmp/miniconda.sh
  if [ -f /mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/third_party/Miniconda3-latest-Linux-x86_64.sh ]; then
    INSTALLER=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/third_party/Miniconda3-latest-Linux-x86_64.sh
  elif [ ! -f "$INSTALLER" ]; then
    echo "Miniconda installer missing; download on Windows first."
    exit 2
  fi
  bash "$INSTALLER" -b -p "$CONDA_ROOT"
fi

export PATH="$CONDA_ROOT/bin:$PATH"
# Install compilers if missing
if [ ! -x "$CONDA_ROOT/bin/x86_64-conda-linux-gnu-g++" ] && [ ! -x "$CONDA_ROOT/bin/g++" ]; then
  echo "=== conda install compilers ==="
  conda install -y -c conda-forge gxx_linux-64 gcc_linux-64 binutils_linux-64 make
fi

# Find g++
GXX=""
for cand in \
  "$CONDA_ROOT/bin/x86_64-conda-linux-gnu-g++" \
  "$CONDA_ROOT/bin/g++" \
  $(ls "$CONDA_ROOT"/bin/*g++ 2>/dev/null || true); do
  if [ -x "$cand" ]; then GXX="$cand"; break; fi
done
echo "Using GXX=$GXX"
"$GXX" --version | head -1

echo "=== compile bridge ==="
"$GXX" -std=c++17 -O2 -fPIC -DNDEBUG \
  -I"$GODOT_CPP/include" -I"$GODOT_CPP/gen/include" -I"$GODOT_CPP/gdextension" \
  -I"$GEN" -I"$NATIVE/src" \
  -c "$NATIVE/src/auto_aim_bridge.cpp" -o /tmp/auto_aim_bridge.o
"$GXX" -std=c++17 -O2 -fPIC -DNDEBUG \
  -I"$GODOT_CPP/include" -I"$GODOT_CPP/gen/include" -I"$GODOT_CPP/gdextension" \
  -I"$GEN" -I"$NATIVE/src" \
  -c "$NATIVE/src/register_types.cpp" -o /tmp/register_types.o

echo "=== link bridge ==="
"$GXX" -shared -o "$BIN/libsp_vision_sim.so" \
  /tmp/auto_aim_bridge.o /tmp/register_types.o "$GODOT_LIB" \
  -ldl -lpthread -Wl,-rpath,'$ORIGIN:$ORIGIN/runtime'

echo "=== compile worker ==="
"$GXX" -std=c++17 -O2 -fPIC -DNDEBUG \
  -I"$NATIVE/src" -I"$SYSROOT/include" \
  -c "$NATIVE/src/worker_main.cpp" -o /tmp/worker_main.o

echo "=== link worker ==="
cp -f "$SYSROOT/lib"/libyaml-cpp.so* "$BIN/" 2>/dev/null || true
"$GXX" -o "$BIN/sp_vision_worker" /tmp/worker_main.o \
  -L"$BIN" -lsp_vision_engine \
  -L"$SYSROOT/lib" -lyaml-cpp \
  -Wl,-rpath,'$ORIGIN:$ORIGIN/runtime' \
  -lpthread -ldl

echo "=== verify ==="
ls -la "$BIN/libsp_vision_sim.so" "$BIN/sp_vision_worker"
grep -aF "multi-robot" "$BIN/sp_vision_worker" && echo OK_MULTI || echo NO_MULTI
echo "CONDA BUILD DONE"

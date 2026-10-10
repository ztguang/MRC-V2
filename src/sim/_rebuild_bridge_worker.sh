#!/bin/bash
# Rebuild only multi-robot bridge + worker against existing libsp_vision_engine.so
# without full OpenCV/OpenVINO recompilation.
set -euo pipefail

ROOT=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim
NATIVE="$ROOT/native"
BIN="$ROOT/godot/bin/linux-x86_64"
SYSROOT="$ROOT/third_party/sysroot/usr"
GODOT_CPP="$ROOT/third_party/godot-cpp"
BUILD_CPP="$ROOT/native/build/bin"
TOOLS=/home/ztg/tools
mkdir -p "$TOOLS"

export PATH="$TOOLS/cmake/bin:$TOOLS/clang/bin:$PATH"

have_cxx() {
  command -v clang++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1
}

if ! have_cxx; then
  echo "Fetching portable clang+cmake into $TOOLS ..."
  python3 - <<'PY'
import os, tarfile, urllib.request, shutil
tools = "/home/ztg/tools"
os.makedirs(tools, exist_ok=True)
os.chdir(tools)

def fetch(url, name):
    print("download", url)
    urllib.request.urlretrieve(url, name)
    print("done", name)

# CMake portable
if not os.path.exists("cmake/bin/cmake"):
    fetch("https://github.com/Kitware/CMake/releases/download/v3.30.5/cmake-3.30.5-linux-x86_64.tar.gz", "cmake.tar.gz")
    with tarfile.open("cmake.tar.gz") as t:
        t.extractall(".")
    if os.path.exists("cmake"):
        shutil.rmtree("cmake")
    os.rename("cmake-3.30.5-linux-x86_64", "cmake")

# LLVM portable (large ~1GB) — only if no system compiler
import shutil as sh
if sh.which("g++") is None and sh.which("clang++") is None:
    # Smaller alternative: download only if needed; try gcc from deadsnakes? Use llvm.
    url = "https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz"
    fetch(url, "llvm.tar.xz")
    with tarfile.open("llvm.tar.xz") as t:
        t.extractall(".")
    # symlink clang dir
    for name in os.listdir("."):
        if name.startswith("clang+llvm") and os.path.isdir(name):
            if os.path.islink("clang") or os.path.exists("clang"):
                if os.path.islink("clang"):
                    os.remove("clang")
                else:
                    shutil.rmtree("clang")
            os.symlink(name, "clang")
            break
print("tools ready")
PY
fi

if command -v clang++ >/dev/null 2>&1; then
  CXX=clang++
elif command -v g++ >/dev/null 2>&1; then
  CXX=g++
else
  CXX="$TOOLS/clang/bin/clang++"
fi
echo "Using CXX=$CXX"
"$CXX" --version | head -1

GODOT_INC=(
  -I"$GODOT_CPP/include"
  -I"$GODOT_CPP/gen/include"
  -I"$GODOT_CPP/gdextension"
  -I"$NATIVE/build/godot-cpp/gen/include"
  -I"$NATIVE/src"
)
# godot-cpp gen headers may live under build
if [ -d "$NATIVE/build/godot-cpp/gen/include" ]; then
  GODOT_INC+=(-I"$NATIVE/build/godot-cpp/gen/include")
fi

COMMON_FLAGS=(-std=c++17 -O2 -fPIC -DNDEBUG)

echo "=== compile auto_aim_bridge + register_types ==="
"$CXX" "${COMMON_FLAGS[@]}" "${GODOT_INC[@]}" -c "$NATIVE/src/auto_aim_bridge.cpp" -o /tmp/auto_aim_bridge.o
"$CXX" "${COMMON_FLAGS[@]}" "${GODOT_INC[@]}" -c "$NATIVE/src/register_types.cpp" -o /tmp/register_types.o

GODOT_LIB=""
for cand in \
  "$BUILD_CPP/libgodot-cpp.linux.template_debug.x86_64.a" \
  "$BUILD_CPP/libgodot-cpp.linux.template_release.x86_64.a" \
  "$NATIVE/build/bin/libgodot-cpp.linux.template_debug.x86_64.a"; do
  if [ -f "$cand" ]; then GODOT_LIB="$cand"; break; fi
done
if [ -z "$GODOT_LIB" ]; then
  echo "godot-cpp static lib not found"; exit 1
fi
echo "godot-cpp: $GODOT_LIB"

echo "=== link libsp_vision_sim.so ==="
"$CXX" -shared -o "$BIN/libsp_vision_sim.so" /tmp/auto_aim_bridge.o /tmp/register_types.o \
  "$GODOT_LIB" -ldl -lpthread \
  -Wl,-rpath,'$ORIGIN:$ORIGIN/runtime'

echo "=== compile worker_main ==="
"$CXX" "${COMMON_FLAGS[@]}" -I"$NATIVE/src" -I"$SYSROOT/include" \
  -c "$NATIVE/src/worker_main.cpp" -o /tmp/worker_main.o

echo "=== link sp_vision_worker ==="
"$CXX" -o "$BIN/sp_vision_worker" /tmp/worker_main.o \
  -L"$BIN" -lsp_vision_engine \
  -L"$SYSROOT/lib" -lyaml-cpp \
  -Wl,-rpath,'$ORIGIN:$ORIGIN/runtime' \
  -Wl,-rpath-link,"$BIN:$BIN/runtime:$SYSROOT/lib"

echo "=== verify ==="
ls -la "$BIN/libsp_vision_sim.so" "$BIN/sp_vision_worker"
# multi-robot marker
if grep -aF "multi-robot" "$BIN/sp_vision_worker" >/dev/null; then
  echo "OK: multi-robot string present in worker"
else
  echo "WARN: multi-robot string missing"
fi
echo "REBUILD DONE"

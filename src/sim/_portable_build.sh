#!/bin/bash
# User-space build without sudo: fetch portable clang + use project sysroot OpenVINO.
set -euo pipefail
ROOT=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim
HOME_TOOLS=/home/ztg/tools
mkdir -p "$HOME_TOOLS"
cd "$HOME_TOOLS"

if [ ! -x "$HOME_TOOLS/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04/bin/clang++" ]; then
  echo "Downloading portable LLVM 18..."
  URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz"
  if command -v wget >/dev/null; then
    wget -q --show-progress -O llvm.tar.xz "$URL"
  else
    # busybox-style fetch via python
    python3 - <<'PY'
import urllib.request
url="https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz"
urllib.request.urlretrieve(url, "llvm.tar.xz")
print("downloaded")
PY
  fi
  tar -xf llvm.tar.xz
fi

CLANG="$HOME_TOOLS/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04/bin/clang++"
"$CLANG" --version | head -1

# Need cmake - try downloading binary cmake
if [ ! -x "$HOME_TOOLS/cmake/bin/cmake" ]; then
  echo "Downloading cmake..."
  python3 - <<'PY'
import urllib.request, tarfile, os
url="https://github.com/Kitware/CMake/releases/download/v3.30.5/cmake-3.30.5-linux-x86_64.tar.gz"
urllib.request.urlretrieve(url, "cmake.tar.gz")
with tarfile.open("cmake.tar.gz") as t:
    t.extractall(".")
os.rename("cmake-3.30.5-linux-x86_64", "cmake")
print("cmake ready")
PY
fi
export PATH="$HOME_TOOLS/cmake/bin:$HOME_TOOLS/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04/bin:$PATH"
cmake --version | head -1

# OpenCV still needed - without system packages this is hard.
# Check if available
python3 - <<'PY'
import ctypes, os
print("looking for libopencv...")
for p in ["/usr/lib/x86_64-linux-gnu/libopencv_core.so",
          "/usr/lib/libopencv_core.so"]:
    print(p, os.path.exists(p))
PY

echo "Portable tools installed. Full build still needs OpenCV headers/libs via apt/sudo or docker."

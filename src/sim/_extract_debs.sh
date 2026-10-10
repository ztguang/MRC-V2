#!/bin/bash
set -euo pipefail
ROOT=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim
DEBDIR="$ROOT/third_party/runtime_debs"
OUT="$ROOT/godot/bin/linux-x86_64/runtime"
STAGE=/tmp/debstage
mkdir -p "$OUT" "$STAGE"
# Prefer miniconda python for ar if needed
export PATH="/home/ztg/miniconda3/bin:$PATH"

extract_deb() {
  local deb="$1"
  local name
  name=$(basename "$deb" .deb)
  local d="$STAGE/$name"
  rm -rf "$d"
  mkdir -p "$d"
  cd "$d"
  # deb = ar archive
  if command -v ar >/dev/null; then
    ar x "$deb"
  else
    # python ar extractor
    python3 - <<PY
import struct, os, sys
path = r"$deb"
with open(path, "rb") as f:
    magic = f.read(8)
    assert magic.startswith(b"!<arch>\n"), magic
    while True:
        header = f.read(60)
        if len(header) < 60: break
        name = header[0:16].decode().strip()
        size = int(header[48:58].decode().strip())
        data = f.read(size)
        if size % 2 == 1: f.read(1)
        name = name.rstrip("/")
        open(name, "wb").write(data)
        print("member", name, size)
PY
  fi
  if [ -f data.tar.zst ]; then
    if command -v zstd >/dev/null; then zstd -d data.tar.zst -o data.tar; tar -xf data.tar
    else python3 - <<'PY'
import zstandard, tarfile, io, os
dctx=zstandard.ZstdDecompressor()
with open("data.tar.zst","rb") as f:
    data=dctx.decompress(f.read())
import io
tar=tarfile.open(fileobj=io.BytesIO(data))
tar.extractall(".")
print("extracted zst")
PY
    fi
  elif [ -f data.tar.xz ]; then tar -xJf data.tar.xz
  elif [ -f data.tar.gz ]; then tar -xzf data.tar.gz
  elif [ -f data.tar ]; then tar -xf data.tar
  fi
  find "$d" -type f -name '*.so*' -exec cp -f {} "$OUT/" \;
  echo "done $name"
}

for deb in "$DEBDIR"/*.deb; do
  [ -f "$deb" ] || continue
  echo "=== $deb ==="
  extract_deb "$deb" || echo "failed $deb"
done

echo "=== runtime so ==="
ls -la "$OUT"/libopencv* "$OUT"/libfmt* "$OUT"/libspdlog* "$OUT"/libyaml* 2>/dev/null || ls -la "$OUT" | head -50

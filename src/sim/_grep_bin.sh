#!/bin/bash
BIN=/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/godot/bin/linux-x86_64
for s in "multi-robot" "auto-aim worker" "invalid frame header" "SPV2" "usage: sp_vision"; do
  echo -n "search '$s': "
  if grep -aF "$s" "$BIN/sp_vision_worker" >/dev/null 2>&1; then echo YES; else echo NO; fi
done
echo "=== worker_main.o date ==="
find /mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/native/build -name '*worker*' 2>/dev/null
ls -la /mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim/native/build/CMakeFiles 2>/dev/null | head
# Dump first 200 printable strings of length>8 from worker via tr/sed
echo "=== printable sample ==="
tr -cd '[:print:]\n' < "$BIN/sp_vision_worker" | tr ' ' '\n' | grep -E 'worker|robot|OpenVINO|frame|engine' | sort -u | head -40

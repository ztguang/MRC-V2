#!/usr/bin/env python3
"""Run all three paper figure scripts."""
import sys, subprocess
from pathlib import Path
here = Path(__file__).resolve().parent
root = sys.argv[1] if len(sys.argv) > 1 else None
args = [sys.executable]
for name in ("plot_exp1_symmetric.py", "plot_exp2_asymmetric.py", "plot_exp3_mechanism.py"):
    cmd = args + [str(here / name)] + ([root] if root else [])
    print("RUN", " ".join(cmd))
    subprocess.check_call(cmd)
print("ALL PLOTS DONE")

#!/usr/bin/env python3
"""Shared loaders for paper experiment plots."""
from __future__ import annotations
import json, os, math
from pathlib import Path
from typing import Any, Dict, List, Optional

def results_root(cli_arg: Optional[str] = None) -> Path:
    if cli_arg:
        p = Path(cli_arg)
        if p.exists():
            return p
    env = os.environ.get("SIM_RESULTS_DIR", "").strip()
    if env and Path(env).exists():
        return Path(env)
    latest = Path("/root/lunwen/sim/godot/logs/LATEST_PAPER_RESULTS.txt")
    if latest.exists():
        p = Path(latest.read_text(encoding="utf-8").strip())
        if p.exists():
            return p
    link = Path("/root/lunwen/sim/godot/logs/latest_paper_results")
    if link.exists():
        return link.resolve()
    # fallback: newest paper_results_*
    logs = Path("/root/lunwen/sim/godot/logs")
    cands = sorted(logs.glob("paper_results_*"), key=lambda x: x.stat().st_mtime, reverse=True)
    if cands:
        return cands[0]
    raise SystemExit("No results dir found. Run /root/lunwen/sim/run_paper_experiments.sh first.")

def load_runs(root: Path) -> List[Dict[str, Any]]:
    rows = []
    for p in sorted(root.rglob("exp*_run*.json")):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:
            d = {"error": str(e)}
        d["_path"] = str(p)
        d["_file"] = p.name
        rows.append(d)
    if not rows:
        # try aggregate
        agg = root / "manifests" / "all_runs.json"
        if agg.exists():
            rows = json.loads(agg.read_text(encoding="utf-8"))
    return rows

def by_exp(rows: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    out: Dict[str, List[Dict[str, Any]]] = {}
    for r in rows:
        k = str(r.get("exp_id") or r.get("exp_name") or "unknown")
        # normalize expA / A
        if k.startswith("exp"):
            k = k
        out.setdefault(k, []).append(r)
    return out

def fnum(x, default=0.0) -> float:
    try:
        if x is None:
            return default
        return float(x)
    except Exception:
        return default

def mean(xs: List[float]) -> float:
    return sum(xs) / len(xs) if xs else 0.0

def std(xs: List[float]) -> float:
    if len(xs) < 2:
        return 0.0
    m = mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))

def ensure_dir(p: Path) -> Path:
    p.mkdir(parents=True, exist_ok=True)
    return p

def try_matplotlib():
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        return plt
    except Exception:
        return None

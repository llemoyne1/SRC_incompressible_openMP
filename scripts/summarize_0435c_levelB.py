#!/usr/bin/env python3
"""Concise Level-B diagnostic summary for SRC/MPCD 0435c validation runs.

Usage from repo root:
  python3 scripts/summarize_0435c_levelB.py [run/output dirs...]

If no directories are supplied, the script inspects the four reduced validation
outputs used for 0435c injection/io_box src/src-resampling.
"""
from __future__ import annotations

import csv
import math
import os
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

DEFAULT_DIRS = [
    "runs/0434_injection_type1_into_type2_120x30_g4/src/output",
    "runs/0434_injection_type1_into_type2_120x30_g4/src-resampling/output",
    "runs/0434_io_box_same_face_120x30_g4/src/output",
    "runs/0434_io_box_same_face_120x30_g4/src-resampling/output",
]

IMPORTANT_TOKENS = (
    "step", "time", "t", "fluid", "inactive", "latent", "np", "nparticles",
    "mass", "rho", "density", "kbt", "temperature", "stdn", "resm", "q6",
    "meanux", "meanuy", "meanvx", "meanvy", "ux", "uy", "vx", "vy",
    "inlet", "outlet", "backflow", "deleted", "delta", "insert", "extract",
    "guard", "empty", "refill", "split", "nan", "inf", "error",
)

BOUNDARY_TOKENS = (
    "inlet", "outlet", "backflow", "deleted", "delta", "hit", "hits", "segment", "flux",
)


def is_number(s: str) -> bool:
    try:
        float(s)
        return True
    except Exception:
        return False


def is_nonfinite(s: str) -> bool:
    try:
        x = float(s)
    except Exception:
        return False
    return not math.isfinite(x)


def pick_columns(header: List[str], max_cols: int = 18) -> List[int]:
    scored: List[Tuple[int, int, str]] = []
    for i, col in enumerate(header):
        lc = col.strip().lower()
        score = 0
        for tok in IMPORTANT_TOKENS:
            if tok in lc:
                score += 1
        if lc in ("step", "t", "time", "nsteps"):
            score += 4
        if any(tok in lc for tok in BOUNDARY_TOKENS):
            score += 2
        if score > 0:
            scored.append((-score, i, col))
    if not scored:
        return list(range(min(len(header), max_cols)))
    scored.sort()
    idx = sorted(i for _, i, _ in scored[:max_cols])
    return idx


def read_csv_summary(path: Path) -> Dict[str, object]:
    size = path.stat().st_size
    with path.open("r", newline="", errors="replace") as f:
        sample = f.read(4096)
        f.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",;\t ")
        except Exception:
            dialect = csv.excel
        reader = csv.reader(f, dialect)
        try:
            header = next(reader)
        except StopIteration:
            return {"file": path.name, "size": size, "rows": 0, "header": [], "first": [], "last": [], "nonfinite": 0}
        first: Optional[List[str]] = None
        last: Optional[List[str]] = None
        rows = 0
        nonfinite = 0
        for row in reader:
            if not row or all(not c.strip() for c in row):
                continue
            rows += 1
            if first is None:
                first = row
            last = row
            for cell in row:
                if is_nonfinite(cell.strip()):
                    nonfinite += 1
        return {
            "file": path.name,
            "size": size,
            "rows": rows,
            "header": header,
            "first": first or [],
            "last": last or [],
            "nonfinite": nonfinite,
        }


def render_row(header: List[str], row: List[str], idx: List[int]) -> str:
    parts = []
    for i in idx:
        if i >= len(header):
            continue
        val = row[i] if i < len(row) else ""
        parts.append(f"{header[i]}={val}")
    return "; ".join(parts)


def summarize_dir(d: Path) -> str:
    lines: List[str] = []
    lines.append(f"=== {d} ===")
    if not d.exists():
        lines.append("MISSING")
        return "\n".join(lines)
    files = sorted(p for p in d.iterdir() if p.is_file())
    csvs = [p for p in files if p.suffix.lower() == ".csv"]
    others = [p for p in files if p.suffix.lower() != ".csv"]
    lines.append(f"files={len(files)} csv={len(csvs)} other={len(others)}")
    if others:
        compact = ", ".join(f"{p.name}:{p.stat().st_size}" for p in others[:12])
        if len(others) > 12:
            compact += f", ... (+{len(others)-12})"
        lines.append(f"non_csv: {compact}")
    if not csvs:
        return "\n".join(lines)
    for csv_path in csvs:
        try:
            info = read_csv_summary(csv_path)
        except Exception as e:
            lines.append(f"--- {csv_path.name} --- ERROR {e}")
            continue
        header = info["header"]  # type: ignore[assignment]
        first = info["first"]  # type: ignore[assignment]
        last = info["last"]  # type: ignore[assignment]
        idx = pick_columns(header) if isinstance(header, list) else []
        lines.append(f"--- {csv_path.name} --- size={info['size']} rows={info['rows']} nonfinite={info['nonfinite']}")
        if header and first:
            lines.append("first: " + render_row(header, first, idx))
        if header and last:
            lines.append("last : " + render_row(header, last, idx))
    return "\n".join(lines)


def main(argv: List[str]) -> int:
    dirs = [Path(a) for a in argv[1:]] if len(argv) > 1 else [Path(d) for d in DEFAULT_DIRS]
    print("# SRC/MPCD 0435c Level-B concise diagnostic summary")
    print(f"# cwd={Path.cwd()}")
    print(f"# dirs={len(dirs)}")
    for d in dirs:
        print()
        print(summarize_dir(d))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

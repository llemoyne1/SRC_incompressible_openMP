#!/usr/bin/env python3
import csv
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        "usage: analyze_0493x10p_initial_overlap.py "
        "<cuda_phase_kinetic_crossing_0493x9z.csv>"
    )

p = Path(sys.argv[1])
if not p.exists():
    raise SystemExit(f"[0493x10p] missing CSV: {p}")

with p.open(newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit("[0493x10p] empty CSV")

required = [
    "x10pInitialOutside",
    "x10pInitialOverlapResolved",
    "x10pInitialOverlapOutwardReflected",
    "x10pInitialOverlapInwardReleased",
    "x10pInitialOutsideTooDeep",
    "x10pInitialOverlapPenetrationSum",
    "x10pInitialOverlapMaxPenetration",
]
missing = [k for k in required if k not in rows[0]]
if missing:
    raise SystemExit("[0493x10p] missing CSV columns: " + ", ".join(missing))

def isum(k):
    return sum(int(float(r.get(k) or 0)) for r in rows)

def fsum(k):
    return sum(float(r.get(k) or 0.0) for r in rows)

def fmax(k):
    return max(float(r.get(k) or 0.0) for r in rows)

outside = isum("x10pInitialOutside")
resolved = isum("x10pInitialOverlapResolved")
outward = isum("x10pInitialOverlapOutwardReflected")
inward = isum("x10pInitialOverlapInwardReleased")
too_deep = isum("x10pInitialOutsideTooDeep")
pen_sum = fsum("x10pInitialOverlapPenetrationSum")
pen_max = fmax("x10pInitialOverlapMaxPenetration")

print("===== 0493x10p INITIAL OVERLAP =====")
print(f"file={p} rows={len(rows)}")
print(
    f"initialOutside={outside} resolved={resolved} "
    f"outwardReflected={outward} inwardReleased={inward} tooDeep={too_deep}"
)
print(
    f"meanPenetration={(pen_sum/resolved if resolved else 0.0):.12g} "
    f"maxPenetration={pen_max:.12g}"
)
contract = (
    resolved == outward + inward
    and too_deep == 0
    and resolved <= outside
)
print("initialOverlapResolutionContract=" + ("PASS" if contract else "FAIL"))

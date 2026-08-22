#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(".").resolve()
src = root / "src/cuda_q6_resident_0400.cu"
if not src.exists():
    raise SystemExit(f"[0493x10p-check] missing {src}")
t = src.read_text()

markers = {
    "contract tag": "0493x10p-initial-overlap-resolution",
    "overlap field": "x10pInitialOverlapResolved",
    "nearest helper": "q6_x10p_closest_current_segment",
    "resolver helper": "q6_x10p_resolve_initial_overlap",
    "runtime flag": "MPCD_X10P_INITIAL_OVERLAP_RESOLUTION",
    "kernel flag": "resolveInitialOverlap0493x10p",
}
bad = []
for label, marker in markers.items():
    n = t.count(marker)
    print(f"{label}: {marker} count={n}")
    if n == 0:
        bad.append(label)

if bad:
    raise SystemExit("[0493x10p-check] FAIL missing: " + ", ".join(bad))
print("[0493x10p-check] PASS source-side x10p markers present")

#!/usr/bin/env python3
import csv, math, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: analyze_0493x9x_crossing.py <cuda_phase_kinetic_crossing_0493x9x.csv>")
path = Path(sys.argv[1])
with path.open(newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit("[0493x9x-check] ERROR empty CSV")

def I(r, k): return int(float(r.get(k, 0) or 0))
def F(r, k): return float(r.get(k, 0) or 0)
def isum(k): return sum(I(r, k) for r in rows)
def maxabs(k): return max((abs(F(r, k)) for r in rows), default=0.0)

first, last = rows[0], rows[-1]
outer0, outer1 = I(first,"phaseAOuterCellParticles"), I(last,"phaseAOuterCellParticles")
deep0, deep1 = I(first,"deepOuterParticles"), I(last,"deepOuterParticles")
interior = isum("interiorCrossings")
shell = isum("shellGuardCrossings")
selected = isum("selectedReflections")
applied = isum("appliedReflections")
unsupported = isum("unsupportedReflections")
still_out = isum("appliedStillOutwardRelative")
pred_out = isum("appliedInteriorPredictedOutside")
max_dp = max(maxabs("deltaPx"), maxabs("deltaPy"))
max_de = maxabs("deltaKineticEnergy")
conservative = max_dp <= 1e-10 and max_de <= 1e-10

print("===== 0493x9x PRE-CROSSING KINETIC REFLECTION =====")
print(f"file={path}")
print(f"rows={len(rows)} lastStep={last.get('step','?')} reflectionFraction={last.get('reflectionFraction','?')}")
print("--- crossing population ---")
print(f"interiorCrossings={interior} shellGuardCrossings={shell} total={interior+shell}")
print(f"selected={selected} applied={applied} unsupported={unsupported} unsupportedFraction={(unsupported/selected if selected else 0.0):.6%}")
print("--- post-reflection ---")
print(f"appliedStillOutwardRelative={still_out}/{applied} ({(still_out/applied if applied else 0.0):.6%})")
print(f"appliedInteriorPredictedOutside={pred_out}/{applied} ({(pred_out/applied if applied else 0.0):.6%})")
print("--- halo proxies ---")
print(f"outerCellParticles first={outer0} last={outer1} growth={outer1-outer0:+d}")
print(f"deepOuterParticles first={deep0} last={deep1} growth={deep1-deep0:+d}")
print("--- last-row crossing timing ---")
print(f"crossingFractionMean={F(last,'crossingFractionMean'):.9g} positionCorrectionAbsMean={F(last,'positionCorrectionAbsMean'):.9g} outwardRelativeNormalSpeedMean={F(last,'outwardRelativeNormalSpeedMean'):.9g}")
print("--- conservation ---")
print(f"max|deltaP|={max_dp:.6e} max|deltaKE|={max_de:.6e} conservative={int(conservative)}")
print(f"status={'PASS-structural' if conservative and selected > 0 and applied > 0 else 'FAIL'}")

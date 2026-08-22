#!/usr/bin/env python3
import csv, math, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: analyze_0493x9z_individual.py <cuda_phase_kinetic_crossing_0493x9z.csv>")
path = Path(sys.argv[1])
with path.open(newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit("[0493x9z-check] ERROR empty CSV")

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def fsum(k): return sum(F(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def ratio(a,b): return a/b if b else 0.0

first,last=rows[0],rows[-1]
interior=isum("interiorCrossings")
shell=isum("shellGuardCrossings")
selected=isum("selectedReflections")
applied=isum("appliedReflections")
individual=isum("individualDonorReflections")
receivers=isum("receiverCorrectedParticles")
unsupported=isum("unsupportedReflections")
still_out=isum("appliedStillOutwardRelative")
pred_out=isum("appliedInteriorPredictedOutside")
active=isum("reactionActiveCells")
feasible=isum("reactionFeasibleCells")
no_recv=isum("reactionNoReceiverCells")
floor=isum("reactionEnergyFloorCells")
deg=isum("reactionThermalDegenerateCells")
residual=fsum("reactionEnergyResidualAbs")

outer0=I(first,"phaseAOuterCellParticles")
outer1=I(last,"phaseAOuterCellParticles")
deep0=I(first,"deepOuterParticles")
deep1=I(last,"deepOuterParticles")
max_dp=max(maxabs("deltaPx"),maxabs("deltaPy"))
max_de=maxabs("deltaKineticEnergy")

print("===== 0493x9z INDIVIDUAL KINETIC REFLECTION =====")
print(f"file={path}")
print(f"rows={len(rows)} lastStep={last.get('step','?')} reflectionFraction={last.get('reflectionFraction','?')}")
print("--- individual donor invariant ---")
print(f"selected={selected} applied={applied} individual={individual} unsupported={unsupported} "
      f"unsupportedFraction={ratio(unsupported,selected):.6%}")
print(f"appliedStillOutwardRelative={still_out}/{individual} ({ratio(still_out,individual):.6%})")
print(f"appliedInteriorPredictedOutside={pred_out}/{interior} ({ratio(pred_out,interior):.6%} of interior crossings)")
print("--- receiver reaction ---")
print(f"activeCells={active} feasibleCells={feasible} noReceiverCells={no_recv} "
      f"energyFloorCells={floor} thermalDegenerateCells={deg}")
print(f"receiverCorrectedParticles={receivers} reactionEnergyResidualAbsSum={residual:.6e}")
print(f"last mean|deltaU|={F(last,'reactionDeltaUMagnitudeMean'):.6e} "
      f"last mean|lambda-1|={F(last,'reactionLambdaDeviationAbsMean'):.6e}")
print("--- halo proxies ---")
print(f"outer first={outer0} last={outer1} growth={outer1-outer0:+d}")
print(f"deepOuter first={deep0} last={deep1} growth={deep1-deep0:+d}")
print("--- conservation ---")
print(f"max|deltaP|={max_dp:.6e} max|deltaKE|={max_de:.6e}")
conservative = max_dp <= 1e-10 and max_de <= 1e-10 and residual <= 1e-10
individual_ok = still_out == 0 and individual == applied and applied > 0
print(f"individualInwardOK={int(individual_ok)} conservative={int(conservative)}")
print(f"status={'PASS-structural' if individual_ok and conservative else 'FAIL'}")

print("\nstep outer deep intX shellX applied postOut predOut active noRecv floor dEres")
for r in rows:
    print(I(r,"step"),I(r,"phaseAOuterCellParticles"),I(r,"deepOuterParticles"),
          I(r,"interiorCrossings"),I(r,"shellGuardCrossings"),I(r,"appliedReflections"),
          I(r,"appliedStillOutwardRelative"),I(r,"appliedInteriorPredictedOutside"),
          I(r,"reactionActiveCells"),I(r,"reactionNoReceiverCells"),
          I(r,"reactionEnergyFloorCells"),f"{F(r,'reactionEnergyResidualAbs'):.3e}")

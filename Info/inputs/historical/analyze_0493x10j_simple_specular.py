#!/usr/bin/env python3
import csv
import math
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        "usage: analyze_0493x10j_simple_specular.py "
        "<cuda_phase_kinetic_crossing_0493x9z.csv>")

p = Path(sys.argv[1])
with p.open(newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit("[0493x10j-check] ERROR empty CSV")

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def fsum(k): return sum(F(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)

refl = isum("simpleSpecularReflections")
interior = isum("simpleSpecularInteriorCollisions")
shell = isum("simpleSpecularShellReflections")
nonpos = isum("simpleSpecularNonPositiveLabNormal")
int_out = isum("simpleSpecularInteriorFinalOutside")
shell_out = isum("simpleSpecularShellFinalOutside")
speed_err = fsum("simpleSpecularSpeedSqAbsErrorSum")
speed_ref = fsum("simpleSpecularSpeedSqReferenceSum")
rel_speed_err = speed_err / max(speed_ref, 1.0e-300)
pos_shift = fsum("simpleSpecularPositionShiftAbsSum")
receiver = isum("receiverCorrectedParticles")
reaction = isum("reactionActiveCells")
meso = isum("mesoReactionActiveReservoirs")
de = maxabs("deltaKineticEnergy")
dp = max(math.hypot(F(r,"deltaPx"), F(r,"deltaPy")) for r in rows)
deep = [I(r,"deepOuterParticles") for r in rows]
shell_pop = [I(r,"shellParticles") for r in rows]
outer = [I(r,"phaseAOuterCellParticles") for r in rows]

print("===== 0493x10j SIMPLE LAB-FRAME SPECULAR ABLATION =====")
print(f"file={p} rows={len(rows)} lastStep={I(rows[-1],'step')}")
print("--- simple reflection path ---")
print(f"reflections={refl} interior={interior} shell={shell} "
      f"nonPositiveLabNormal={nonpos}")
print(f"interiorFinalOutside={int_out} shellFinalOutside={shell_out}")
print(f"speedSqAbsErrorSum={speed_err:.12e}")
print(f"speedSqRelativeError={rel_speed_err:.12e}")
print(f"max|deltaKE(row)|={de:.12e}")
print(f"interfaceImpulseIgnored max|deltaP(row)|={dp:.12e}")
print(f"collisionPositionShiftAbsSum={pos_shift:.12e}")
print("--- disabled collective machinery ---")
print(f"receiverCorrectedParticles={receiver} reactionActiveCells={reaction} "
      f"mesoReactionActiveReservoirs={meso}")
print("--- halo context ---")
print(f"outer first/max/last={outer[0]}/{max(outer)}/{outer[-1]}")
print(f"shell first/max/last={shell_pop[0]}/{max(shell_pop)}/{shell_pop[-1]}")
print(f"deepOuter first/max/last={deep[0]}/{max(deep)}/{deep[-1]}")

path_ok = refl > 0 and receiver == 0 and reaction == 0 and meso == 0
speed_ok = rel_speed_err < 1.0e-12 and de < 1.0e-9
print("simplePathContract=" + ("PASS" if path_ok else "FAIL"))
print("speedNormContract=" + ("PASS" if speed_ok else "FAIL"))
print("momentumContract=INTENTIONALLY_NOT_ENFORCED_INTERFACE_IMPULSE_IGNORED")
print("retentionOutcome=VISUAL_PLUS_FINAL_OUTSIDE_AND_DEEPOUTER_REVIEW")
print("shapeContract=VISUAL_PENDING")

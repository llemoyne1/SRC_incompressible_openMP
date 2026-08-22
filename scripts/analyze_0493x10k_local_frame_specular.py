#!/usr/bin/env python3
import csv
import math
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        "usage: analyze_0493x10k_local_frame_specular.py "
        "<cuda_phase_kinetic_crossing_0493x9z.csv>")

p = Path(sys.argv[1])
with p.open(newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit("[0493x10k-check] ERROR empty CSV")

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def fsum(k): return sum(F(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)

refl = isum("localFrameSpecularReflections")
interior = isum("localFrameInteriorCollisions")
shell = isum("localFrameShellReflections")
still = isum("localFrameRelativeStillOutward")
int_outer = isum("localFrameInteriorEndpointOuter")
shell_outer = isum("localFrameShellEndpointOuter")
rel_err = fsum("localFrameRelativeSpeedSqAbsErrorSum")
rel_ref = fsum("localFrameRelativeSpeedSqReferenceSum")
rel_err_ratio = rel_err / max(rel_ref, 1.0e-300)
lab_delta = fsum("localFrameLabSpeedSqChangeSum")
lab_abs_delta = fsum("localFrameLabSpeedSqAbsChangeSum")
pos_shift = fsum("localFramePositionShiftAbsSum")
x10j_refl = isum("simpleSpecularReflections")
receiver = isum("receiverCorrectedParticles")
reaction = isum("reactionActiveCells")
meso = isum("mesoReactionActiveReservoirs")
dp = max(math.hypot(F(r,"deltaPx"), F(r,"deltaPy")) for r in rows)
de = maxabs("deltaKineticEnergy")
deep = [I(r,"deepOuterParticles") for r in rows]
shell_pop = [I(r,"shellParticles") for r in rows]
outer = [I(r,"phaseAOuterCellParticles") for r in rows]

print("===== 0493x10k LOCAL-LIQUID-FRAME SPECULAR ABLATION =====")
print(f"file={p} rows={len(rows)} lastStep={I(rows[-1],'step')}")
print("--- local-frame reflection path ---")
print(f"reflections={refl} interior={interior} shell={shell} "
      f"relativeStillOutward={still}")
print(f"interiorEndpointOuter={int_outer} shellEndpointOuter={shell_outer}")
print(f"relativeSpeedSqAbsErrorSum={rel_err:.12e}")
print(f"relativeSpeedSqRelativeError={rel_err_ratio:.12e}")
print(f"labSpeedSqChangeSum={lab_delta:.12e} "
      f"labSpeedSqAbsChangeSum={lab_abs_delta:.12e}")
print(f"max|deltaKE(row)|={de:.12e}")
print(f"interfaceImpulseIgnored max|deltaP(row)|={dp:.12e}")
print(f"collisionPositionShiftAbsSum={pos_shift:.12e}")
print("--- disabled collective machinery ---")
print(f"x10jLabReflections={x10j_refl} receiverCorrectedParticles={receiver} "
      f"reactionActiveCells={reaction} mesoReactionActiveReservoirs={meso}")
print("--- halo context ---")
print(f"outer first/max/last={outer[0]}/{max(outer)}/{outer[-1]}")
print(f"shell first/max/last={shell_pop[0]}/{max(shell_pop)}/{shell_pop[-1]}")
print(f"deepOuter first/max/last={deep[0]}/{max(deep)}/{deep[-1]}")

path_ok = (
    refl > 0 and x10j_refl == 0 and receiver == 0 and reaction == 0 and meso == 0)
relative_ok = rel_err_ratio < 1.0e-12 and still == 0
print("localFramePathContract=" + ("PASS" if path_ok else "FAIL"))
print("relativeSpeedNormContract=" + ("PASS" if relative_ok else "FAIL"))
print("labEnergyContract=NOT_ENFORCED_MOVING_LOCAL_FRAME")
print("momentumContract=INTENTIONALLY_NOT_ENFORCED_INTERFACE_IMPULSE_IGNORED")
print("endpointOuter=CONTEXT_NOT_FAILURE_INTERFACE_MAY_ADVECT")
print("retentionOutcome=VISUAL_PLUS_HALO_REVIEW")
print("shapeContract=VISUAL_PENDING")

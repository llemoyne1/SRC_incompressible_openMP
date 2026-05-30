#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_mass_guard_smoke_0123"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_mass_guard_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path("runs/resampling_mass_guard_smoke_0123")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_mass_guard_v2.smpcd"
Nx = 8
Ny = 4
Nlatent = 5
Ninactive = 7

x=[]; y=[]; vx=[]; vy=[]; type_=[]; mass=[]; role=[]
for iy in range(Ny):
    for ix in range(Nx):
        c = ix + Nx * iy
        if c == 0:
            masses = [0.2, 0.4, 0.4]        # poor receiver and below guard min
        elif c == 2:
            masses = [0.875] * 8             # rich donor, total mass 7
        elif c == 3:
            masses = [0.1, 2.5, 0.7, 0.7]   # target mass already OK but outside bounds
        else:
            masses = [1.0] * 4
        for p, mp in enumerate(masses):
            fx = 0.16 + 0.15 * (p % 4)
            fy = 0.20 + 0.12 * (p // 4)
            x.append((ix + fx) / Nx)
            y.append((iy + fy) / Ny)
            vx.append(0.04 * (p - 1.5) + 0.0025 * c)
            vy.append(-0.035 * ((p % 3) - 1.0) - 0.0015 * c)
            type_.append(p % 2)
            mass.append(mp)
            role.append(1)

Nfluid = len(x)
assert abs(sum(mass) - 128.0) < 1e-12, sum(mass)
for i in range(Nlatent):
    x.append(1.2 + 0.01 * i); y.append(1.1 + 0.01 * i)
    vx.append(3.0); vy.append(-3.0); type_.append(5); mass.append(10.0); role.append(2)
for i in range(Ninactive):
    x.append(-0.2 - 0.01 * i); y.append(-0.2 - 0.01 * i)
    vx.append(-4.0); vy.append(4.0); type_.append(6); mass.append(20.0); role.append(0)

Np = len(x)
with path.open("wb") as f:
    f.write(b"SRCMPCD_STATE" + b"\0\0\0")
    f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, Np, 1, 1, Nx, Ny))
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    f.write(struct.pack("<8Q", *reserved))
    for arr in (x, y, vx, vy):
        f.write(struct.pack("<" + "d" * Np, *arr))
    f.write(struct.pack("<" + "I" * Np, *type_))
    f.write(struct.pack("<" + "d" * Np, *mass))
    f.write(struct.pack("<" + "B" * Np, *role))
print(path)
print(f"Nfluid={Nfluid} Nlatent={Nlatent} Ninactive={Ninactive} Np={Np} mass={sum(mass[:Nfluid])}")
PY

cat > "$RUN_DIR/params_mass_guard.kv" <<KV
inputState = $STATE
outputDir = $RUN_DIR/out
Lx = 1.0
Ly = 1.0
Nx = 8
Ny = 4
dt = 0.001
nSteps = 1
alphaDeg = 120
randomRotationSign = true
gridShiftEnable = false
rngSeed = 1230
bcX = periodic
bcY = periodic
method = classic
thermostatEnable = false
kBT = 0.01
resamplingEnable = true
resamplingTargetCellMass = 4.0
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = 0.5
resamplingRichCellMassFraction = 1.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = 0.5
resamplingParticleMassMax = 2.0
summaryEvery = 1
dumpStateEvery = 1
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_mass_guard.kv"

python3 - <<'PY'
import csv
import pathlib

base = pathlib.Path("runs/resampling_mass_guard_smoke_0123")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 2, len(rows)
initial, final = rows

assert int(initial["resampMassGuardAttempted"]) == 0
assert int(final["resampExtractionApplyAttempted"]) == 1
assert int(final["resampInsertionApplyAttempted"]) == 1
assert int(final["resampRemapApplyAttempted"]) == 1
assert int(final["resampThermalRenormAttempted"]) == 1
assert int(final["resampMassGuardAttempted"]) == 1
assert int(final["resampMassGuardApplied"]) == 1
assert int(final["resampMassGuardCellsConsidered"]) == 32
assert int(final["resampMassGuardSkippedInfeasibleCells"]) == 0
assert int(final["resampMassGuardSkippedInvalidMassCells"]) == 0
assert int(final["resampMassGuardAllCellsFeasible"]) == 1
assert int(final["resampMassGuardParticlesBelowMinBefore"]) > 0
assert int(final["resampMassGuardParticlesAboveMaxBefore"]) > 0
assert int(final["resampMassGuardParticlesBelowMinAfter"]) == 0
assert int(final["resampMassGuardParticlesAboveMaxAfter"]) == 0
assert float(final["resampParticleMassMin"]) >= 0.5 - 1e-10
assert float(final["resampParticleMassMax"]) <= 2.0 + 1e-10
assert abs(float(final["resampMRelRms"])) < 1e-12
assert abs(float(final["resampMRelMaxAbs"])) < 1e-12
assert abs(float(final["resampMassGuardMassResidualRms"])) < 1e-12
assert abs(float(final["resampMassGuardMassResidualMaxAbs"])) < 1e-12
assert abs(float(final["resampMassGuardThermalEnergyAfter"]) - float(final["resampMassGuardThermalEnergyTarget"])) < 1e-12
assert abs(float(final["resampMassGuardThermalEnergyResidualRms"])) < 1e-12
assert abs(float(final["resampMassGuardMomentumResidualRms"])) < 1e-12

print(
    "mass guard:",
    f"cells={final['resampMassGuardCellsGuarded']}",
    f"particlesAdjusted={final['resampMassGuardParticlesAdjusted']}",
    f"minAfter={final['resampParticleMassMin']}",
    f"maxAfter={final['resampParticleMassMax']}",
    f"belowBefore={final['resampMassGuardParticlesBelowMinBefore']}",
    f"aboveBefore={final['resampMassGuardParticlesAboveMaxBefore']}",
    f"MRelRms={final['resampMRelRms']}",
)
PY

printf '\n[0123 resampling mass guard smoke] OK: bounded particle-mass renormalization enforces m_min/m_max while preserving local M,U,E_th.\n'

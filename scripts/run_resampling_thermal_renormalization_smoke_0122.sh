#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_thermal_renormalization_smoke_0122"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_thermal_renorm_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path("runs/resampling_thermal_renormalization_smoke_0122")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_thermal_renorm_v2.smpcd"
Nx = 8
Ny = 4
Nlatent = 5
Ninactive = 7

x=[]; y=[]; vx=[]; vy=[]; type_=[]; mass=[]; role=[]
# Same mass-layout as the 0121 remap smoke.  The velocities are deliberately
# non-uniform within each cell so that the local relative thermal energy is
# non-zero and the 0122 thermal renormalisation has something to restore after
# mass scaling.
for iy in range(Ny):
    for ix in range(Nx):
        c = ix + Nx * iy
        if c == 0:
            masses = []
        elif c == 1:
            masses = [1.0]
        elif c == 2:
            masses = [1.5]*6 + [1.0]*2
        else:
            masses = [1.0]*4
        for p, mp in enumerate(masses):
            fx = 0.18 + 0.13 * (p % 4)
            fy = 0.22 + 0.12 * (p // 4)
            x.append((ix + fx) / Nx)
            y.append((iy + fy) / Ny)
            # Non-zero relative velocities, plus a cell-dependent drift.
            vx.append(0.05 * (p - 1.5) + 0.003 * c)
            vy.append(-0.04 * ((p % 3) - 1.0) - 0.002 * c)
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

cat > "$RUN_DIR/params_thermal_renorm.kv" <<KV
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
rngSeed = 1220
bcX = periodic
bcY = periodic
projectionEnable = false
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
summaryEvery = 1
dumpStateEvery = 1
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_thermal_renorm.kv"

python3 - <<'PY'
import csv
import pathlib

Nx = 8
Ny = 4
base = pathlib.Path("runs/resampling_thermal_renormalization_smoke_0122")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 2, len(rows)
initial, final = rows

assert int(initial["resampThermalRenormAttempted"]) == 0
assert int(final["resampExtractionApplyAttempted"]) == 1
assert int(final["resampInsertionApplyAttempted"]) == 1
assert int(final["resampRemapApplyAttempted"]) == 1
assert int(final["resampThermalRenormAttempted"]) == 1
assert int(final["resampThermalRenormApplied"]) == 1
assert int(final["resampThermalRenormCellsConsidered"]) == Nx * Ny
assert int(final["resampThermalRenormSkippedEmptyCells"]) == 0
assert int(final["resampThermalRenormSkippedInvalidEnergyCells"]) == 0
assert int(final["resampThermalRenormCellsRenormalized"]) >= 2
assert int(final["resampThermalRenormParticlesRenormalized"]) == 125
assert abs(float(final["resampMRelRms"])) < 1e-12
assert abs(float(final["resampMRelMaxAbs"])) < 1e-12
assert abs(float(final["resampThermalRenormEnergyAfter"]) - float(final["resampThermalRenormTargetEnergy"])) < 1e-12
assert abs(float(final["resampThermalRenormEnergyResidualRms"])) < 1e-12
assert abs(float(final["resampThermalRenormEnergyResidualMaxAbs"])) < 1e-12
assert abs(float(final["resampThermalRenormMomentumResidualRms"])) < 1e-12
assert abs(float(final["resampThermalRenormMomentumResidualMaxAbs"])) < 1e-12
assert float(final["resampThermalRenormVelocityScaleMin"]) < 1.0
assert float(final["resampThermalRenormVelocityScaleMax"]) > 1.0
assert int(final["resampThermalRenormAllCellsNonEmpty"]) == 1

print(
    "thermal renorm:",
    f"cells={final['resampThermalRenormCellsRenormalized']}",
    f"particles={final['resampThermalRenormParticlesRenormalized']}",
    f"Etarget={final['resampThermalRenormTargetEnergy']}",
    f"Ebefore={final['resampThermalRenormEnergyBefore']}",
    f"Eafter={final['resampThermalRenormEnergyAfter']}",
    f"vscaleMin={final['resampThermalRenormVelocityScaleMin']}",
    f"vscaleMax={final['resampThermalRenormVelocityScaleMax']}",
)
PY

printf '\n[0122 resampling thermal renormalization smoke] OK: local M,U,E_th renormalization restores thermal energy after mass remap.\n'

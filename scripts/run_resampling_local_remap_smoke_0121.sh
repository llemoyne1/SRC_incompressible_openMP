#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_local_remap_smoke_0121"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_local_remap_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path("runs/resampling_local_remap_smoke_0121")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_local_remap_v2.smpcd"
Nx = 8
Ny = 4
Nlatent = 5
Ninactive = 7

x=[]; y=[]; vx=[]; vy=[]; type_=[]; mass=[]; role=[]
# Target mass is 4 per wet cell.  The total true-fluid mass is exactly
# 32*4=128, but the extraction/insertion step overshoots cell 0 by 0.5 and
# undershoots donor cell 2 by 0.5.  Patch 0121 must remove that residual by
# local mass scaling while preserving cell velocities.
for iy in range(Ny):
    for ix in range(Nx):
        c = ix + Nx * iy
        if c == 0:
            masses = []                 # empty wet receiver, deficit 4
        elif c == 1:
            masses = [1.0]              # poor receiver, deficit 3
        elif c == 2:
            masses = [1.5]*6 + [1.0]*2  # rich donor, mass 11, excess 7
        else:
            masses = [1.0]*4            # target band
        for p, mp in enumerate(masses):
            fx = 0.18 + 0.13 * (p % 4)
            fy = 0.22 + 0.12 * (p // 4)
            x.append((ix + fx) / Nx)
            y.append((iy + fy) / Ny)
            vx.append(0.01 * (p + 1 + c))
            vy.append(-0.02 * (p + 1))
            type_.append(p % 2)
            mass.append(mp)
            role.append(1)  # Fluid

Nfluid = len(x)
assert abs(sum(mass) - 128.0) < 1e-12, sum(mass)
for i in range(Nlatent):
    x.append(1.2 + 0.01 * i)
    y.append(1.1 + 0.01 * i)
    vx.append(3.0)
    vy.append(-3.0)
    type_.append(5)
    mass.append(10.0)
    role.append(2)  # Latent
for i in range(Ninactive):
    x.append(-0.2 - 0.01 * i)
    y.append(-0.2 - 0.01 * i)
    vx.append(-4.0)
    vy.append(4.0)
    type_.append(6)
    mass.append(20.0)
    role.append(0)  # Inactive / free-list

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

cat > "$RUN_DIR/params_local_remap.kv" <<KV
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
rngSeed = 1210
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
summaryEvery = 1
dumpStateEvery = 1
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_local_remap.kv"

python3 - <<'PY'
import csv
import pathlib
import struct

Nx = 8
Ny = 4
base = pathlib.Path("runs/resampling_local_remap_smoke_0121")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 2, len(rows)
initial, final = rows

assert int(initial["resampRemapApplyAttempted"]) == 0
assert int(final["resampExtractionApplyAttempted"]) == 1
assert int(final["resampInsertionApplyAttempted"]) == 1
assert int(final["resampRemapApplyAttempted"]) == 1
assert int(final["resampRemapApplied"]) == 1
assert int(final["resampRemapCellsConsidered"]) == Nx * Ny
assert int(final["resampRemapSkippedEmptyCells"]) == 0
assert int(final["resampRemapSkippedInvalidMassCells"]) == 0
assert int(final["resampRemapCellsRemapped"]) == 2
assert int(final["resampRemapParticlesRemapped"]) == 125
assert abs(float(final["resampRemapTargetCellMass"]) - 4.0) < 1e-12
assert abs(float(final["resampRemapMassBefore"]) - 128.0) < 1e-12
assert abs(float(final["resampRemapMassAfter"]) - 128.0) < 1e-12
assert abs(float(final["resampRemapMassDelta"])) < 1e-12
assert abs(float(final["resampRemapMomentumResidualRms"])) < 1e-12
assert abs(float(final["resampRemapMomentumResidualMaxAbs"])) < 1e-12
assert abs(float(final["resampRemapMaxCellMassRelResidual"])) < 1e-12
assert abs(float(final["resampTotalMass"]) - 128.0) < 1e-12
assert abs(float(final["resampMRelRms"])) < 1e-12
assert abs(float(final["resampMRelMaxAbs"])) < 1e-12
assert int(final["resampPoorCells"]) == 0
assert int(final["resampRichCells"]) == 0
assert int(final["resampTargetBandCells"]) == Nx * Ny
assert float(final["resampParticleMassRelStd"]) > 0.0
assert float(final["resampRemapScaleMin"]) < 1.0
assert float(final["resampRemapScaleMax"]) > 1.0

# Verify V2 state and exact cell masses after remap.
state_path = base / "out" / "state_step_00000001.smpcd"
with state_path.open("rb") as f:
    magic = f.read(16)
    assert magic == b"SRCMPCD_STATE" + b"\0\0\0"
    version, endian, dim, flags, Np, has_type, has_mass, Nx_file, Ny_file = struct.unpack("<IIIIQIIII", f.read(40))
    assert version == 2 and has_type == 1 and has_mass == 1
    assert Nx_file == Nx and Ny_file == Ny
    reserved = struct.unpack("<8Q", f.read(64))
    assert reserved[0] == 1
    x = struct.unpack("<" + "d" * Np, f.read(8 * Np))
    y = struct.unpack("<" + "d" * Np, f.read(8 * Np))
    vx = struct.unpack("<" + "d" * Np, f.read(8 * Np))
    vy = struct.unpack("<" + "d" * Np, f.read(8 * Np))
    types = struct.unpack("<" + "I" * Np, f.read(4 * Np))
    masses = struct.unpack("<" + "d" * Np, f.read(8 * Np))
    roles = struct.unpack("<" + "B" * Np, f.read(Np))
cell_mass = [0.0 for _ in range(Nx*Ny)]
for i, r in enumerate(roles):
    if r != 1:
        continue
    cx = min(Nx - 1, max(0, int(x[i] * Nx)))
    cy = min(Ny - 1, max(0, int(y[i] * Ny)))
    cell_mass[cx + Nx*cy] += masses[i]
for c, m in enumerate(cell_mass):
    assert abs(m - 4.0) < 2e-12, (c, m)

print(
    "local remap:",
    f"remappedCells={final['resampRemapCellsRemapped']}",
    f"particles={final['resampRemapParticlesRemapped']}",
    f"MRelRms={final['resampMRelRms']}",
    f"scaleMin={final['resampRemapScaleMin']}",
    f"scaleMax={final['resampRemapScaleMax']}",
)
PY

printf '\n[0121 resampling local remap smoke] OK: local mass/momentum remap enforces M_c target while preserving cell velocities.\n'

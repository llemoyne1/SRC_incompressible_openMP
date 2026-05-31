#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_cell_classification_smoke_0114"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_classification_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path("runs/resampling_cell_classification_smoke_0114")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_classification_v2.smpcd"
Nx = 8
Ny = 4
gamma = 4
Nlatent = 5
Ninactive = 7

x=[]; y=[]; vx=[]; vy=[]; type_=[]; mass=[]; role=[]
# Cell 0: empty wet void pocket -> poor + emptyWet.
# Cell 1: one real particle -> poor.
# Cell 2: eight real particles -> rich.
# All other active-domain cells: target population/mass = 4.
for iy in range(Ny):
    for ix in range(Nx):
        c = ix + Nx * iy
        if c == 0:
            count = 0
        elif c == 1:
            count = 1
        elif c == 2:
            count = 8
        else:
            count = gamma
        for p in range(count):
            fx = 0.18 + 0.13 * (p % 4)
            fy = 0.22 + 0.12 * (p // 4)
            x.append((ix + fx) / Nx)
            y.append((iy + fy) / Ny)
            vx.append(0.0)
            vy.append(0.0)
            type_.append(p % 2)
            mass.append(1.0)
            role.append(1)  # Fluid

Nfluid = len(x)
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
    role.append(0)  # Inactive

Np = len(x)
with path.open("wb") as f:
    f.write(b"SRCMPCD_STATE" + b"\0\0\0")
    f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, Np, 1, 1, 8, 4))
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
print(f"Nfluid={Nfluid} Nlatent={Nlatent} Ninactive={Ninactive} Np={Np}")
PY

cat > "$RUN_DIR/params_classification.kv" <<KV
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
rngSeed = 1140
bcX = periodic
bcY = periodic
projectionEnable = false
thermostatEnable = false
kBT = 0.01
resamplingTargetCellMass = 4.0
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = 0.5
resamplingRichCellMassFraction = 1.5
summaryEvery = 1
dumpStateEvery = 1
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_classification.kv"

python3 - <<'PY'
import csv
import math
import pathlib

base = pathlib.Path("runs/resampling_cell_classification_smoke_0114")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) >= 2

Nx, Ny = 8, 4
nCells = Nx * Ny
Nfluid = 125
Nlatent = 5
Ninactive = 7
expected = {
    "resampCellClassificationComputed": 1,
    "resampActiveCells": nCells,
    "resampWetCells": nCells,
    "resampDryCells": 0,
    "resampPoorCells": 2,
    "resampRichCells": 1,
    "resampTargetBandCells": nCells - 3,
    "resampEmptyWetCells": 1,
    "resampOccupiedDryCells": 0,
}
# Relative mass RMS is computed over wet active-domain cells only.
rel2 = (0 - 4) ** 2 / 4**2 + (1 - 4) ** 2 / 4**2 + (8 - 4) ** 2 / 4**2
expected_mrel = math.sqrt(rel2 / nCells)

for row in rows:
    assert int(row["nFluidParticles"]) == Nfluid
    assert int(row["nLatentParticles"]) == Nlatent
    assert int(row["nInactiveParticles"]) == Ninactive
    assert int(row["resampComputed"]) == 1
    assert abs(float(row["resampTotalMass"]) - Nfluid) < 1e-9
    assert abs(float(row["resampTargetCellMass"]) - 4.0) < 1e-15
    assert abs(float(row["resampPoorMassThreshold"]) - 2.0) < 1e-15
    assert abs(float(row["resampRichMassThreshold"]) - 6.0) < 1e-15
    for key, val in expected.items():
        assert int(row[key]) == val, (key, row[key], val)
    assert abs(float(row["resampWetCellFraction"]) - 1.0) < 1e-15
    assert abs(float(row["resampDryCellFraction"])) < 1e-15
    assert abs(float(row["resampPoorCellFraction"]) - 2 / nCells) < 1e-15
    assert abs(float(row["resampRichCellFraction"]) - 1 / nCells) < 1e-15
    assert abs(float(row["resampEmptyWetCellFraction"]) - 1 / nCells) < 1e-15
    assert abs(float(row["resampMRelRms"]) - expected_mrel) < 1e-14

last = rows[-1]
print(
    "classification:",
    f"wet={last['resampWetCells']}",
    f"dry={last['resampDryCells']}",
    f"poor={last['resampPoorCells']}",
    f"rich={last['resampRichCells']}",
    f"emptyWet={last['resampEmptyWetCells']}",
    f"targetBand={last['resampTargetBandCells']}",
    f"MRelRms={last['resampMRelRms']}",
)
PY

printf '\n[0114 resampling cell classification smoke] OK: active-domain wet/dry and poor/rich masks are passive and deterministic.\n'

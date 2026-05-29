#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_candidate_lists_smoke_0115"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_candidates_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path("runs/resampling_candidate_lists_smoke_0115")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_candidates_v2.smpcd"
Nx = 8
Ny = 4
gamma = 4
Nlatent = 5
Ninactive = 7

x=[]; y=[]; vx=[]; vy=[]; type_=[]; mass=[]; role=[]
# Cell 0: empty wet receiver, mass 0.
# Cell 1: poor receiver, mass 1.
# Cell 2: rich donor, mass 8.
# Other cells: target-band mass 4.
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
    role.append(0)  # Inactive / future free-list

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

cat > "$RUN_DIR/params_candidates.kv" <<KV
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
rngSeed = 1150
bcX = periodic
bcY = periodic
method = classic
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

./build/src_mpcd_base "$RUN_DIR/params_candidates.kv"

python3 - <<'PY'
import csv
import math
import pathlib

base = pathlib.Path("runs/resampling_candidate_lists_smoke_0115")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) >= 2

Nx, Ny = 8, 4
nCells = Nx * Ny
Nfluid = 125
Nlatent = 5
Ninactive = 7
for row in rows:
    assert int(row["resampComputed"]) == 1
    assert int(row["resampCellClassificationComputed"]) == 1
    assert int(row["resampCandidateListsBuilt"]) == 1
    assert int(row["resampNFluid"]) == Nfluid
    assert int(row["resampNLatent"]) == Nlatent
    assert int(row["resampNInactive"]) == Ninactive
    assert int(row["resampWetCells"]) == nCells
    assert int(row["resampPoorCells"]) == 2
    assert int(row["resampRichCells"]) == 1
    assert int(row["resampReceiverCells"]) == 2
    assert int(row["resampDonorCells"]) == 1
    assert int(row["resampEmptyWetCells"]) == 1
    assert int(row["resampEmptyWetReceiverCells"]) == 1
    assert int(row["resampFirstReceiverCell"]) == 0
    assert int(row["resampLastReceiverCell"]) == 1
    assert int(row["resampFirstDonorCell"]) == 2
    assert int(row["resampLastDonorCell"]) == 2
    assert abs(float(row["resampReceiverMassDeficitToTarget"]) - 7.0) < 1e-12
    assert abs(float(row["resampDonorMassExcessAboveTarget"]) - 4.0) < 1e-12
    assert abs(float(row["resampDonorReceiverMassBalance"]) + 3.0) < 1e-12
    assert abs(float(row["resampPotentialTransferMass"]) - 4.0) < 1e-12
    assert abs(float(row["resampReceiverFractionOfWetCells"]) - 2 / nCells) < 1e-15
    assert abs(float(row["resampDonorFractionOfWetCells"]) - 1 / nCells) < 1e-15
    assert int(row["resampPoolBuilt"]) == 1
    assert int(row["resampPoolFreeSlots"]) == Ninactive
    assert int(row["resampPoolCanSeedReceivers"]) == 1

last = rows[-1]
print(
    "candidates:",
    f"receivers={last['resampReceiverCells']}",
    f"donors={last['resampDonorCells']}",
    f"emptyReceivers={last['resampEmptyWetReceiverCells']}",
    f"deficit={last['resampReceiverMassDeficitToTarget']}",
    f"excess={last['resampDonorMassExcessAboveTarget']}",
    f"potential={last['resampPotentialTransferMass']}",
    f"poolCanSeed={last['resampPoolCanSeedReceivers']}",
)
PY

printf '\n[0115 resampling candidate lists smoke] OK: donor/receiver lists are passive, deterministic, and pool-aware.\n'

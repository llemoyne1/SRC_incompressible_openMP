#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_mutating_insertion_smoke_0120"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_mutating_insertion_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path("runs/resampling_mutating_insertion_smoke_0120")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_mutating_insertion_v2.smpcd"
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
            vx.append(0.01 * (p + 1))
            vy.append(-0.02 * (p + 1))
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
print(f"Nfluid={Nfluid} Nlatent={Nlatent} Ninactive={Ninactive} Np={Np}")
PY

cat > "$RUN_DIR/params_mutating_insertion.kv" <<KV
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
rngSeed = 1200
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
summaryEvery = 1
dumpStateEvery = 1
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_mutating_insertion.kv"

python3 - <<'PY'
import csv
import pathlib
import struct

Nx = 8
Ny = 4
base = pathlib.Path("runs/resampling_mutating_insertion_smoke_0120")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 2, len(rows)
initial, final = rows

Nfluid0 = 125
Nlatent = 5
Ninactive0 = 7
moved = 4

# Initial row remains passive.
assert int(initial["resampNFluid"]) == Nfluid0
assert int(initial["resampNLatent"]) == Nlatent
assert int(initial["resampNInactive"]) == Ninactive0
assert int(initial["resampExtractionPlanBuilt"]) == 1
assert int(initial["resampExtractionOps"]) == moved
assert int(initial["resampExtractionApplyAttempted"]) == 0
assert int(initial["resampInsertionApplyAttempted"]) == 0

# Final row is post extraction+insertion: storage roles return to original counts.
assert int(final["resampExtractionApplyAttempted"]) == 1
assert int(final["resampExtractionApplied"]) == 1
assert int(final["resampExtractionApplyOpsApplied"]) == moved
assert int(final["resampExtractionApplyPoolFreeSlotsBefore"]) == Ninactive0
assert int(final["resampExtractionApplyPoolFreeSlotsAfter"]) == Ninactive0 + moved
assert int(final["resampExtractionApplyPoolFreeSlotDelta"]) == moved
assert abs(float(final["resampExtractionApplyMass"]) - moved) < 1e-12

assert int(final["resampInsertionApplyAttempted"]) == 1
assert int(final["resampInsertionApplied"]) == 1
assert int(final["resampInsertionApplyOpsConsidered"]) == moved
assert int(final["resampInsertionApplyOpsApplied"]) == moved
assert int(final["resampInsertionApplyRoleChanges"]) == moved
assert int(final["resampInsertionApplySkippedInvalidSourceParticles"]) == 0
assert int(final["resampInsertionApplySkippedSourceNotInactive"]) == 0
assert int(final["resampInsertionApplySkippedInvalidReceiverCells"]) == 0
assert int(final["resampInsertionApplySkippedNoFreeSlots"]) == 0
assert int(final["resampInsertionApplySkippedInvalidMass"]) == 0
assert int(final["resampInsertionApplyPoolFreeSlotsBefore"]) == Ninactive0 + moved
assert int(final["resampInsertionApplyPoolFreeSlotsAfter"]) == Ninactive0
assert int(final["resampInsertionApplyPoolFreeSlotDelta"]) == moved
assert abs(float(final["resampInsertionApplyMass"]) - moved) < 1e-12
assert abs(float(final["resampInsertionApplyPlannedMass"]) - moved) < 1e-12
assert abs(float(final["resampInsertionApplyMassResidualVsPlan"])) < 1e-12
assert int(final["resampInsertionApplyNoInvalidReceiverCells"]) == 1
assert int(final["resampInsertionApplyAllSourcesWereInactive"]) == 1

assert int(final["resampNFluid"]) == Nfluid0
assert int(final["resampNLatent"]) == Nlatent
assert int(final["resampNInactive"]) == Ninactive0
assert int(final["resampPoolFreeSlots"]) == Ninactive0
assert abs(float(final["resampTotalMass"]) - Nfluid0) < 1e-12
assert int(final["resampRichCells"]) == 0
assert int(final["resampDonorCells"]) == 0
assert int(final["resampPoorCells"]) == 1
assert int(final["resampReceiverCells"]) == 1

# Check V2 role persistence and that four recycled particles landed in receiver cells.
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
assert roles.count(1) == Nfluid0
assert roles.count(2) == Nlatent
assert roles.count(0) == Ninactive0
receiver_cells = []
for idx in range(1, 5):
    assert roles[idx] == 1, (idx, roles[idx])
    assert abs(masses[idx] - 1.0) < 1e-12
    cx = min(Nx - 1, max(0, int(x[idx] * Nx)))
    cy = min(Ny - 1, max(0, int(y[idx] * Ny)))
    receiver_cells.append(cx + Nx * cy)
assert sorted(receiver_cells).count(1) == 3, receiver_cells
assert sorted(receiver_cells).count(0) == 1, receiver_cells

print(
    "mutating insertion:",
    f"inserted={final['resampInsertionApplyOpsApplied']}",
    f"mass={final['resampInsertionApplyMass']}",
    f"fluid={final['resampNFluid']}",
    f"inactive={final['resampNInactive']}",
    f"poolFree={final['resampPoolFreeSlots']}",
    f"poorAfter={final['resampPoorCells']}",
)
PY

printf '\n[0120 resampling mutating insertion smoke] OK: controlled Inactive->Fluid insertion recycles extracted particles into receiver cells.\n'

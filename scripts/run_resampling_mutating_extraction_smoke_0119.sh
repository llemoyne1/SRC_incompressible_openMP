#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_mutating_extraction_smoke_0119"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_mutating_extraction_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path("runs/resampling_mutating_extraction_smoke_0119")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_mutating_extraction_v2.smpcd"
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

cat > "$RUN_DIR/params_mutating_extraction.kv" <<KV
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
rngSeed = 1190
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
resamplingExtractionEnable = true
summaryEvery = 1
dumpStateEvery = 1
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_mutating_extraction.kv"

python3 - <<'PY'
import csv
import pathlib
import struct

base = pathlib.Path("runs/resampling_mutating_extraction_smoke_0119")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 2, len(rows)
initial, final = rows

Nfluid0 = 125
Nlatent = 5
Ninactive0 = 7
extracted = 4

# Initial row remains passive: plan exists, but no mutation has occurred.
assert int(initial["resampNFluid"]) == Nfluid0
assert int(initial["resampNLatent"]) == Nlatent
assert int(initial["resampNInactive"]) == Ninactive0
assert int(initial["resampExtractionPlanBuilt"]) == 1
assert int(initial["resampExtractionOps"]) == extracted
assert int(initial["resampExtractionApplyAttempted"]) == 0
assert int(initial["resampExtractionApplied"]) == 0

# Final row is post-extraction: four donor particles were converted Fluid->Inactive.
assert int(final["resampExtractionApplyAttempted"]) == 1
assert int(final["resampExtractionApplied"]) == 1
assert int(final["resampExtractionApplyOpsConsidered"]) == extracted
assert int(final["resampExtractionApplyOpsApplied"]) == extracted
assert int(final["resampExtractionApplyRoleChanges"]) == extracted
assert int(final["resampExtractionApplySkippedInvalidParticles"]) == 0
assert int(final["resampExtractionApplySkippedNonFluidParticles"]) == 0
assert int(final["resampExtractionApplySkippedDuplicateParticles"]) == 0
assert int(final["resampExtractionApplyPoolFreeSlotsBefore"]) == Ninactive0
assert int(final["resampExtractionApplyPoolFreeSlotsAfter"]) == Ninactive0 + extracted
assert int(final["resampExtractionApplyPoolFreeSlotDelta"]) == extracted
assert abs(float(final["resampExtractionApplyMass"]) - extracted) < 1e-12
assert abs(float(final["resampExtractionApplyPlannedMass"]) - extracted) < 1e-12
assert abs(float(final["resampExtractionApplyMassResidualVsPlan"])) < 1e-12
assert int(final["resampFirstAppliedExtractionParticle"]) == 1
assert int(final["resampLastAppliedExtractionParticle"]) == 4
assert int(final["resampExtractionApplyNoDuplicateParticles"]) == 1
assert int(final["resampExtractionApplyAllAppliedWereFluid"]) == 1

assert int(final["resampNFluid"]) == Nfluid0 - extracted
assert int(final["resampNLatent"]) == Nlatent
assert int(final["resampNInactive"]) == Ninactive0 + extracted
assert int(final["resampPoolFreeSlots"]) == Ninactive0 + extracted
assert abs(float(final["resampTotalMass"]) - (Nfluid0 - extracted)) < 1e-12

# Donor cell 2 is no longer rich after removal of four unit-mass particles.
assert int(final["resampRichCells"]) == 0
assert int(final["resampDonorCells"]) == 0
assert int(final["resampSelectedDonorParticles"]) == 0
assert int(final["resampExtractionOps"]) == 0

# Check V2 role persistence in the final dump.
state_path = base / "out" / "state_step_00000001.smpcd"
with state_path.open("rb") as f:
    magic = f.read(16)
    assert magic == b"SRCMPCD_STATE" + b"\0\0\0"
    version, endian, dim, flags, Np, has_type, has_mass, Nx, Ny = struct.unpack("<IIIIQIIII", f.read(40))
    assert version == 2 and has_type == 1 and has_mass == 1
    reserved = struct.unpack("<8Q", f.read(64))
    has_role = reserved[0]
    assert has_role == 1
    for _ in range(4):
        f.seek(8 * Np, 1)
    f.seek(4 * Np, 1)
    f.seek(8 * Np, 1)
    roles = struct.unpack("<" + "B" * Np, f.read(Np))
assert roles.count(1) == Nfluid0 - extracted
assert roles.count(2) == Nlatent
assert roles.count(0) == Ninactive0 + extracted
for idx in range(1, 5):
    assert roles[idx] == 0, (idx, roles[idx])

print(
    "mutating extraction:",
    f"applied={final['resampExtractionApplyOpsApplied']}",
    f"mass={final['resampExtractionApplyMass']}",
    f"fluid={final['resampNFluid']}",
    f"inactive={final['resampNInactive']}",
    f"poolFree={final['resampPoolFreeSlots']}",
    f"richAfter={final['resampRichCells']}",
)
PY

printf '\n[0119 resampling mutating extraction smoke] OK: Fluid->Inactive extraction applies deterministically and persists roles.\n'

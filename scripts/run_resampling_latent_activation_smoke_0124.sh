#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_latent_activation_smoke_0124"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_latent_activation_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path("runs/resampling_latent_activation_smoke_0124")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_latent_activation_v2.smpcd"
Nx = 8
Ny = 4
Nlatent = 5
Ninactive = 3

x=[]; y=[]; vx=[]; vy=[]; type_=[]; mass=[]; role=[]
for iy in range(Ny):
    for ix in range(Nx):
        c = ix + Nx * iy
        if c == 0:
            continue  # empty wet void pocket that must be seeded from latent slots
        for p in range(4):
            x.append((ix + 0.2 + 0.2 * (p % 2)) / Nx)
            y.append((iy + 0.2 + 0.2 * (p // 2)) / Ny)
            vx.append(0.0)
            vy.append(0.0)
            type_.append(p % 2)
            mass.append(1.0)
            role.append(1)  # Fluid

Nfluid = len(x)
assert Nfluid == 124
assert abs(sum(mass) - 124.0) < 1e-12

# Latent particles carry species/type information but are ignored until activated.
for i in range(Nlatent):
    x.append(1.2 + 0.01 * i)
    y.append(1.1 + 0.01 * i)
    vx.append(7.0)
    vy.append(-7.0)
    type_.append(9 + i)
    mass.append(10.0)
    role.append(2)  # Latent
for i in range(Ninactive):
    x.append(-0.2 - 0.01 * i)
    y.append(-0.2 - 0.01 * i)
    vx.append(-3.0)
    vy.append(3.0)
    type_.append(99)
    mass.append(20.0)
    role.append(0)  # Inactive free pool, not consumed by this test

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
print(f"Nfluid={Nfluid} Nlatent={Nlatent} Ninactive={Ninactive} Np={Np} realMass={sum(mass[:Nfluid])}")
PY

cat > "$RUN_DIR/params_latent_activation.kv" <<KV
inputState = $STATE
outputDir = $RUN_DIR/out
Lx = 1.0
Ly = 1.0
Nx = 8
Ny = 4
dt = 0.001
nSteps = 1
alphaDeg = 120
randomRotationSign = false
gridShiftEnable = false
rngSeed = 1240
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
resamplingLatentActivationEnable = true
resamplingLatentActivationMaxPerCell = 4
resamplingLatentActivationParticleMass = 1.0
summaryEvery = 1
dumpStateEvery = 1
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_latent_activation.kv"

python3 - <<'PY'
import csv
import pathlib
import struct

base = pathlib.Path("runs/resampling_latent_activation_smoke_0124")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 2, len(rows)
initial, final = rows

assert int(initial["resampLatentActivationAttempted"]) == 0
assert int(final["resampLatentActivationAttempted"]) == 1
assert int(final["resampLatentActivationApplied"]) == 1
assert int(final["resampLatentActivationReceiverCellsConsidered"]) == 1
assert int(final["resampLatentActivationCellsActivated"]) == 1
assert int(final["resampLatentActivationParticlesActivated"]) == 4
assert int(final["resampLatentActivationRoleChanges"]) == 4
assert int(final["resampLatentActivationSkippedNoLatentSlots"]) == 0
assert int(final["resampLatentActivationSkippedReceiverNotWet"]) == 0
assert int(final["resampLatentActivationSkippedReceiverNotPoor"]) == 0
assert int(final["resampLatentActivationAllSourcesWereLatent"]) == 1
assert int(final["resampLatentActivationNoDryCellsActivated"]) == 1
assert int(final["resampNFluid"]) == 128
assert int(final["resampNLatent"]) == 1
assert int(final["resampNInactive"]) == 3
assert int(final["resampPoolLatentSlots"]) == 1
assert int(final["resampPoolFreeSlots"]) == 3
assert abs(float(final["resampLatentActivationMass"]) - 4.0) < 1e-12
assert abs(float(final["resampTotalMass"]) - 128.0) < 1e-12
assert abs(float(final["resampMRelRms"])) < 1e-12
assert int(final["resampEmptyWetCells"]) == 0
assert int(final["resampPoorCells"]) == 0

# Check V2 role persistence: final state has 128 Fluid, 1 Latent, 3 Inactive.
state_path = base / "out" / "state_step_00000001.smpcd"
with state_path.open("rb") as f:
    magic = f.read(16)
    assert magic == b"SRCMPCD_STATE" + b"\0\0\0"
    version, endian, dim, flags, Np, has_type, has_mass, Nx, Ny = struct.unpack("<IIIIQIIII", f.read(40))
    assert version == 2 and has_type == 1 and has_mass == 1
    f.read(8 * 8)
    f.read(8 * Np * 4)  # x,y,vx,vy
    f.read(4 * Np)      # type
    f.read(8 * Np)      # mass
    roles = list(struct.unpack("<" + "B" * Np, f.read(Np)))
assert roles.count(1) == 128, roles.count(1)
assert roles.count(2) == 1, roles.count(2)
assert roles.count(0) == 3, roles.count(0)

print(
    "latent activation:",
    f"activated={final['resampLatentActivationParticlesActivated']}",
    f"cells={final['resampLatentActivationCellsActivated']}",
    f"fluid={final['resampNFluid']}",
    f"latent={final['resampNLatent']}",
    f"inactive={final['resampNInactive']}",
    f"MRelRms={final['resampMRelRms']}",
)
PY

printf '\n[0124 resampling latent activation smoke] OK: Latent->Fluid activation seeds empty wet cells without consuming Inactive pool slots.\n'

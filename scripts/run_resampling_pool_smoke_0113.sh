#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_pool_smoke_0113"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_pool_roles_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import random
import struct

root = pathlib.Path("runs/resampling_pool_smoke_0113")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_pool_roles_v2.smpcd"
Nx = 10
Ny = 8
gamma = 3
Nfluid = Nx * Ny * gamma
Nlatent = 9
Ninactive = 11
Np = Nfluid + Nlatent + Ninactive
rng = random.Random(1130)

x=[]; y=[]; vx=[]; vy=[]; type_=[]; mass=[]; role=[]
for iy in range(Ny):
    for ix in range(Nx):
        for p in range(gamma):
            x.append((ix + 0.2 + 0.2*p) / Nx)
            y.append((iy + 0.25 + 0.15*p) / Ny)
            vx.append(0.01 * rng.gauss(0.0, 1.0))
            vy.append(0.01 * rng.gauss(0.0, 1.0))
            type_.append(p % 2)
            mass.append(1.0)
            role.append(1)  # Fluid

# Latent slots are allocated but not free. They should not be returned by the
# inactive free-list. Their type is deliberately distinct to keep type/species
# independent from role.
for i in range(Nlatent):
    x.append(1.3 + 0.01 * i)
    y.append(1.2 + 0.01 * i)
    vx.append(5.0)
    vy.append(-4.0)
    type_.append(7)
    mass.append(100.0)
    role.append(2)  # Latent

# Inactive slots form the pool/free-list prepared by patch 0113.
for i in range(Ninactive):
    x.append(-0.2 - 0.01 * i)
    y.append(-0.1 - 0.01 * i)
    vx.append(-6.0)
    vy.append(6.0)
    type_.append(8)
    mass.append(200.0)
    role.append(0)  # Inactive

assert len(x) == Np
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
PY

cat > "$RUN_DIR/params_pool.kv" <<KV
inputState = $STATE
outputDir = $RUN_DIR/out
Lx = 1.0
Ly = 1.0
Nx = 10
Ny = 8
dt = 0.001
nSteps = 2
alphaDeg = 120
randomRotationSign = true
gridShiftEnable = true
rngSeed = 1130
bcX = periodic
bcY = periodic
projectionEnable = false
thermostatEnable = false
kBT = 0.01
summaryEvery = 1
dumpStateEvery = 2
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_pool.kv"

python3 - <<'PY'
import csv
import math
import pathlib
import struct

base = pathlib.Path("runs/resampling_pool_smoke_0113")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) >= 2
first = rows[0]
last = rows[-1]
Nx = 10
Ny = 8
gamma = 3
Nfluid = Nx * Ny * gamma
Nlatent = 9
Ninactive = 11
Np = Nfluid + Nlatent + Ninactive
first_free = Nfluid + Nlatent
last_free = Np - 1

for row in (first, last):
    assert int(row["Np"]) == Np
    assert int(row["nFluidParticles"]) == Nfluid
    assert int(row["nLatentParticles"]) == Nlatent
    assert int(row["nInactiveParticles"]) == Ninactive
    assert int(row["resampComputed"]) == 1
    assert int(row["resampPoolBuilt"]) == 1
    assert int(row["resampPoolStorageSlots"]) == Np
    assert int(row["resampPoolFreeSlots"]) == Ninactive
    assert int(row["resampPoolLatentSlots"]) == Nlatent
    assert int(row["resampPoolFluidSlots"]) == Nfluid
    assert int(row["resampPoolFirstFreeIndex"]) == first_free
    assert int(row["resampPoolLastFreeIndex"]) == last_free
    assert abs(float(row["resampPoolFreeSlotFraction"]) - Ninactive / Np) < 1e-15
    assert abs(float(row["resampPoolDormantSlotFraction"]) - (Ninactive + Nlatent) / Np) < 1e-15
    assert abs(float(row["totalMass"]) - Nfluid) < 1e-9
    assert abs(float(row["resampTotalMass"]) - Nfluid) < 1e-9

# Confirm role persistence after the run and no activation/deactivation yet.
def read_roles(path):
    with path.open("rb") as f:
        magic = f.read(16)
        if magic != b"SRCMPCD_STATE" + b"\0\0\0":
            raise RuntimeError("bad magic")
        version, endian, dim, layout, Np_read, hasType, hasMass, realSize, typeSize = struct.unpack("<IIIIQIIII", f.read(40))
        reserved = struct.unpack("<8Q", f.read(64))
        f.seek(4 * 8 * Np_read, 1)
        f.seek(4 * Np_read, 1)
        f.seek(8 * Np_read, 1)
        roles = list(struct.unpack("<" + "B" * Np_read, f.read(Np_read)))
    return version, reserved, roles

version, reserved, roles = read_roles(base / "out" / "state_step_00000002.smpcd")
assert version == 2 and reserved[0] == 1 and reserved[1] == 1
assert roles.count(1) == Nfluid
assert roles.count(2) == Nlatent
assert roles.count(0) == Ninactive
print(
    "pool:",
    f"fluid={Nfluid}",
    f"latent={Nlatent}",
    f"inactive/free={Ninactive}",
    f"firstFree={first_free}",
    f"lastFree={last_free}",
    f"freeFraction={last['resampPoolFreeSlotFraction']}",
)
PY

printf '\n[0113 resampling pool smoke] OK: inactive pool/free-list diagnostics remain passive and persistent.\n'

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/particle_roles_smoke_0111"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_roles_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import random
import struct

root = pathlib.Path("runs/particle_roles_smoke_0111")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_roles_v2.smpcd"
Nx = 16
Ny = 16
gamma = 4
Nfluid = Nx * Ny * gamma
Nlatent = 16
Ninactive = 16
Np = Nfluid + Nlatent + Ninactive
rng = random.Random(1111)

x = [rng.random() for _ in range(Nfluid)] + [1.25 + 0.001*i for i in range(Nlatent)] + [-0.25 - 0.001*i for i in range(Ninactive)]
y = [rng.random() for _ in range(Nfluid)] + [1.25 + 0.001*i for i in range(Nlatent)] + [-0.25 - 0.001*i for i in range(Ninactive)]
vx = [0.01 * rng.gauss(0.0, 1.0) for _ in range(Nfluid)] + [7.0 for _ in range(Nlatent)] + [-7.0 for _ in range(Ninactive)]
vy = [0.01 * rng.gauss(0.0, 1.0) for _ in range(Nfluid)] + [5.0 for _ in range(Nlatent)] + [-5.0 for _ in range(Ninactive)]
type_ = [0 for _ in range(Nfluid)] + [1 for _ in range(Nlatent)] + [2 for _ in range(Ninactive)]
mass = [1.0 for _ in range(Nfluid)] + [1000.0 for _ in range(Nlatent + Ninactive)]
role = [1 for _ in range(Nfluid)] + [2 for _ in range(Nlatent)] + [0 for _ in range(Ninactive)]

with path.open("wb") as f:
    f.write(b"SRCMPCD_STATE" + b"\0\0\0")
    f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, Np, 1, 1, 8, 4))
    reserved = [0] * 8
    reserved[0] = 1  # hasRole
    reserved[1] = 1  # role byte size
    f.write(struct.pack("<8Q", *reserved))
    for arr in (x, y, vx, vy):
        f.write(struct.pack("<" + "d" * Np, *arr))
    f.write(struct.pack("<" + "I" * Np, *type_))
    f.write(struct.pack("<" + "d" * Np, *mass))
    f.write(struct.pack("<" + "B" * Np, *role))
print(path)
PY

cat > "$RUN_DIR/params_roles.kv" <<KV
inputState = $STATE
outputDir = $RUN_DIR/out
Lx = 1.0
Ly = 1.0
Nx = 16
Ny = 16
dt = 0.001
nSteps = 2
alphaDeg = 120
randomRotationSign = true
gridShiftEnable = true
rngSeed = 1111
bcX = periodic
bcY = periodic
projectionEnable = false
thermostatEnable = false
kBT = 0.01
summaryEvery = 1
dumpStateEvery = 2
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_roles.kv"

python3 - <<'PY'
import csv
import math
import pathlib
import struct

base = pathlib.Path("runs/particle_roles_smoke_0111")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
first = rows[0]
last = rows[-1]
expected_fluid = 16 * 16 * 4
expected_latent = 16
expected_inactive = 16
assert int(first["Np"]) == expected_fluid + expected_latent + expected_inactive
assert int(first["nFluidParticles"]) == expected_fluid
assert int(first["nLatentParticles"]) == expected_latent
assert int(first["nInactiveParticles"]) == expected_inactive
assert abs(float(first["totalMass"]) - expected_fluid) < 1e-9, first["totalMass"]
assert abs(float(first["meanN"]) - 4.0) < 1e-12, first["meanN"]
assert int(last["nFluidParticles"]) == expected_fluid
assert int(last["nLatentParticles"]) == expected_latent
assert int(last["nInactiveParticles"]) == expected_inactive

def read_state(path):
    with path.open("rb") as f:
        magic = f.read(16)
        if magic != b"SRCMPCD_STATE" + b"\0\0\0":
            raise RuntimeError("bad magic")
        version, endian, dim, layout, Np, hasType, hasMass, realSize, typeSize = struct.unpack("<IIIIQIIII", f.read(40))
        reserved = struct.unpack("<8Q", f.read(64))
        arrays = []
        for _ in range(4):
            arrays.append(list(struct.unpack("<" + "d" * Np, f.read(8 * Np))))
        type_ = list(struct.unpack("<" + "I" * Np, f.read(4 * Np)))
        mass = list(struct.unpack("<" + "d" * Np, f.read(8 * Np)))
        role = list(struct.unpack("<" + "B" * Np, f.read(Np)))
    return version, reserved, arrays, type_, mass, role

v0, r0, arr0, type0, mass0, role0 = read_state(base / "initial_roles_v2.smpcd")
v1, r1, arr1, type1, mass1, role1 = read_state(base / "out" / "state_step_00000002.smpcd")
assert v0 == 2 and v1 == 2
assert r1[0] == 1 and r1[1] == 1
assert role1.count(1) == expected_fluid
assert role1.count(2) == expected_latent
assert role1.count(0) == expected_inactive
start_nonfluid = expected_fluid
for arr_in, arr_out in zip(arr0, arr1):
    for a, b in zip(arr_in[start_nonfluid:], arr_out[start_nonfluid:]):
        if a != b:
            raise AssertionError("latent/inactive particle changed although it must be dormant")
print(f"roles: fluid={expected_fluid} latent={expected_latent} inactive={expected_inactive} mass={last['totalMass']} meanN={last['meanN']}")
PY

printf '\n[0111 roles smoke] OK: Fluid/Latent/Inactive masks and V2 .smpcd role persistence completed.\n'

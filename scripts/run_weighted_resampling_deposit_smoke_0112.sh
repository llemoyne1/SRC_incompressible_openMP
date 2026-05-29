#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/weighted_resampling_deposit_smoke_0112"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_weighted_roles_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path("runs/weighted_resampling_deposit_smoke_0112")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_weighted_roles_v2.smpcd"
Nx = 8
Ny = 8
masses_per_cell = [0.5, 1.0, 1.5, 2.0]
velocities_per_cell = [(0.0, 0.0), (0.02, 0.0), (0.0, -0.01), (-0.01, 0.015)]
Nfluid = Nx * Ny * len(masses_per_cell)
Nlatent = 7
Ninactive = 5
Np = Nfluid + Nlatent + Ninactive

x = []
y = []
vx = []
vy = []
type_ = []
mass = []
role = []
for iy in range(Ny):
    for ix in range(Nx):
        x0 = ix / Nx
        y0 = iy / Ny
        offsets = [(0.22, 0.22), (0.78, 0.22), (0.22, 0.78), (0.78, 0.78)]
        for p, ((ox, oy), m, (ux, uy)) in enumerate(zip(offsets, masses_per_cell, velocities_per_cell)):
            x.append(x0 + ox / Nx)
            y.append(y0 + oy / Ny)
            vx.append(ux)
            vy.append(uy)
            type_.append(p % 2)  # keep species/type independent from role
            mass.append(m)
            role.append(1)       # Fluid

# Dormant slots deliberately carry huge masses and out-of-domain coordinates.
# The 0112 diagnostics must ignore them completely.
for i in range(Nlatent):
    x.append(1.4 + 0.01 * i)
    y.append(1.3 + 0.01 * i)
    vx.append(9.0)
    vy.append(-8.0)
    type_.append(3)
    mass.append(1000.0)
    role.append(2)  # Latent
for i in range(Ninactive):
    x.append(-0.4 - 0.01 * i)
    y.append(-0.3 - 0.01 * i)
    vx.append(-7.0)
    vy.append(6.0)
    type_.append(4)
    mass.append(2000.0)
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

cat > "$RUN_DIR/params_weighted_deposit.kv" <<KV
inputState = $STATE
outputDir = $RUN_DIR/out
Lx = 1.0
Ly = 1.0
Nx = 8
Ny = 8
dt = 0.001
nSteps = 1
alphaDeg = 120
randomRotationSign = true
gridShiftEnable = true
rngSeed = 1122
bcX = solid
bcY = solid
wallAccommodation = 1.0
wallVpGamma = 4.0
wallVpMass = 1.0
wallThermalNoise = 0.0
method = classic
thermostatEnable = false
kBT = 0.01
summaryEvery = 1
dumpStateEvery = 1
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_weighted_deposit.kv"

python3 - <<'PY'
import csv
import math
import pathlib

base = pathlib.Path("runs/weighted_resampling_deposit_smoke_0112")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) >= 2
first = rows[0]
last = rows[-1]

Nx = 8
Ny = 8
Ncells = Nx * Ny
Nfluid = Ncells * 4
Nlatent = 7
Ninactive = 5
expected_total_mass = Ncells * 5.0
expected_particle_mean = 1.25
expected_particle_std = math.sqrt(0.3125)
expected_particle_relstd = expected_particle_std / expected_particle_mean

for row in (first, last):
    assert int(row["resampComputed"]) == 1
    assert int(row["resampNFluid"]) == Nfluid
    assert int(row["resampNLatent"]) == Nlatent
    assert int(row["resampNInactive"]) == Ninactive
    assert abs(float(row["resampTotalMass"]) - expected_total_mass) < 1e-10, row["resampTotalMass"]
    assert abs(float(row["totalMass"]) - expected_total_mass) < 1e-10, row["totalMass"]
    assert abs(float(row["resampMeanN"]) - 4.0) < 1e-12, row["resampMeanN"]
    assert abs(float(row["resampStdN"])) < 1e-12, row["resampStdN"]
    assert int(row["resampMinN"]) == 4
    assert int(row["resampMaxN"]) == 4
    assert abs(float(row["resampMeanMass"]) - 5.0) < 1e-12, row["resampMeanMass"]
    assert abs(float(row["resampStdMass"])) < 1e-12, row["resampStdMass"]
    assert abs(float(row["resampMinMass"]) - 5.0) < 1e-12, row["resampMinMass"]
    assert abs(float(row["resampMaxMass"]) - 5.0) < 1e-12, row["resampMaxMass"]
    assert abs(float(row["resampMRelRms"])) < 1e-12, row["resampMRelRms"]
    assert abs(float(row["resampParticleMassMean"]) - expected_particle_mean) < 1e-12
    assert abs(float(row["resampParticleMassStd"]) - expected_particle_std) < 1e-12
    assert abs(float(row["resampParticleMassRelStd"]) - expected_particle_relstd) < 1e-12
    assert abs(float(row["resampParticleMassMin"]) - 0.5) < 1e-12
    assert abs(float(row["resampParticleMassMax"]) - 2.0) < 1e-12

# The collision path has wall virtual mass in the last row, but the real-fluid
# resampling deposit must remain exactly the transported fluid mass.
assert float(last["virtualMass"]) > 0.0, last["virtualMass"]
assert abs(float(last["resampTotalMass"]) - expected_total_mass) < 1e-10
print(
    "weighted deposit:",
    f"fluid={Nfluid}",
    f"latent={Nlatent}",
    f"inactive={Ninactive}",
    f"realMass={last['resampTotalMass']}",
    f"virtualMass={last['virtualMass']}",
    f"mRelRms={last['resampMRelRms']}",
    f"mParticleRelStd={last['resampParticleMassRelStd']}",
)
PY

printf '\n[0112 weighted deposit smoke] OK: real-fluid weighted deposit excludes dormant particles and wall/immersed virtual mass.\n'

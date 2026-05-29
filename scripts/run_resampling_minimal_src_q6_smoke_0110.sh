#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_minimal_src_q6_smoke_0110"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_32x32_g4.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import random
import struct

root = pathlib.Path("runs/resampling_minimal_src_q6_smoke_0110")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_32x32_g4.smpcd"
Nx = 32
Ny = 32
gamma = 4
Np = Nx * Ny * gamma
rng = random.Random(12345)

x = [rng.random() for _ in range(Np)]
y = [rng.random() for _ in range(Np)]
vx = [0.02 * rng.gauss(0.0, 1.0) for _ in range(Np)]
vy = [0.02 * rng.gauss(0.0, 1.0) for _ in range(Np)]
type_ = [0 for _ in range(Np)]
mass = [1.0 for _ in range(Np)]

with path.open("wb") as f:
    f.write(b"SRCMPCD_STATE" + b"\0\0\0")
    f.write(struct.pack("<IIIIQIIII", 1, 0x01020304, 2, 1, Np, 1, 1, 8, 4))
    f.write(struct.pack("<8Q", *([0] * 8)))
    for arr in (x, y, vx, vy):
        f.write(struct.pack("<" + "d" * Np, *arr))
    f.write(struct.pack("<" + "I" * Np, *type_))
    f.write(struct.pack("<" + "d" * Np, *mass))
print(path)
PY

cat > "$RUN_DIR/params_classic.kv" <<KV
inputState = $STATE
outputDir = $RUN_DIR/classic
Lx = 1.0
Ly = 1.0
Nx = 32
Ny = 32
dt = 0.001
nSteps = 20
alphaDeg = 120
randomRotationSign = true
gridShiftEnable = true
rngSeed = 12345
bcX = periodic
bcY = periodic
method = classic
thermostatEnable = false
kBT = 0.01
summaryEvery = 10
dumpStateEvery = 0
numThreads = $THREADS
KV

cat > "$RUN_DIR/params_q6.kv" <<KV
inputState = $STATE
outputDir = $RUN_DIR/q6
Lx = 1.0
Ly = 1.0
Nx = 32
Ny = 32
dt = 0.001
nSteps = 20
alphaDeg = 120
randomRotationSign = true
gridShiftEnable = true
rngSeed = 12345
bcX = periodic
bcY = periodic
method = q6
projectionOperator = periodic_fv_cg
projectionMaxIterations = 300
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
thermostatEnable = false
kBT = 0.01
summaryEvery = 10
dumpStateEvery = 0
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_classic.kv"
./build/src_mpcd_base "$RUN_DIR/params_q6.kv"

python3 - <<'PY'
import csv
from pathlib import Path
base = Path("runs/resampling_minimal_src_q6_smoke_0110")
for label in ("classic", "q6"):
    path = base / label / "summary_runtime.csv"
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    last = rows[-1]
    forbidden = [c for c in rows[0].keys() if c.startswith("q9") or c.startswith("virial")]
    if forbidden:
        raise SystemExit(f"Unexpected removed columns in {path}: {forbidden[:5]}")
    print(f"{label}: Np={last['Np']} stdN={last['stdN']} kBT={last['kBTEstimate']} q6={last['q6DivAfterProjectedFluxRms']}")
PY

printf '\n[0110 smoke] OK: classic + q6 reduced baseline completed.\n'

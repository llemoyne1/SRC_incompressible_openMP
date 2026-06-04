#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/taylor_green_forcing_smoke_0130"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_tg_force_v2.smpcd"

python3 - <<'PY'
import pathlib
import struct
root=pathlib.Path('runs/taylor_green_forcing_smoke_0130')
root.mkdir(parents=True, exist_ok=True)
path=root/'initial_tg_force_v2.smpcd'
# Four fluid particles at points where the TG force is non-zero. Zero velocity.
x=[0.25,0.75,0.25,0.75]
y=[0.00,0.00,0.50,0.50]
vx=[0.0]*4
vy=[0.0]*4
typ=[0]*4
mass=[1.0]*4
role=[1]*4
Np=len(x)
with path.open('wb') as f:
    f.write(b'SRCMPCD_STATE' + b'\0\0\0')
    f.write(struct.pack('<IIIIQIIII', 2, 0x01020304, 2, 1, Np, 1, 1, 8, 4))
    reserved=[0]*8; reserved[0]=1; reserved[1]=1
    f.write(struct.pack('<8Q', *reserved))
    for arr in (x,y,vx,vy):
        f.write(struct.pack('<'+'d'*Np, *arr))
    f.write(struct.pack('<'+'I'*Np, *typ))
    f.write(struct.pack('<'+'d'*Np, *mass))
    f.write(struct.pack('<'+'B'*Np, *role))
print(path)
PY

write_params() {
    local label=$1
    local forcing_enable=$2
    local forcing_amp=$3
    local out_dir="$RUN_DIR/$label"
    local params="$RUN_DIR/params_${label}.kv"
    mkdir -p "$out_dir"
    cat > "$params" <<KV
inputState = $STATE
outputDir = $out_dir
Lx = 1.0
Ly = 1.0
Nx = 2
Ny = 2
dt = 0.1
nSteps = 1
rotationAngle = 0.0
randomRotationSign = false
gridShiftEnable = false
rngSeed = 1300
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = $forcing_enable
taylorGreenForcingAmplitude = $forcing_amp
taylorGreenForcingModeX = 1
taylorGreenForcingModeY = 1
bcX = periodic
bcY = periodic
projectionEnable = false
thermostatEnable = false
kBT = 0.0
summaryEvery = 1
dumpStateEvery = 0
numThreads = ${NUM_THREADS:-2}
KV
    echo "$params"
}

./build/src_mpcd_base "$(write_params off false 0.0)"
./build/src_mpcd_base "$(write_params on true 1.0)"

python3 - <<'PY'
import csv
from pathlib import Path
base=Path('runs/taylor_green_forcing_smoke_0130')
def final_row(label):
    with (base/label/'summary_runtime.csv').open(newline='') as f:
        rows=list(csv.DictReader(f))
    return rows[-1]
off=final_row('off')
on=final_row('on')
ke_off=float(off['meanKinetic'])
ke_on=float(on['meanKinetic'])
assert abs(ke_off) < 1e-14, ke_off
assert ke_on > 1e-6, ke_on
# Four particles receive |dv|=0.1 at the chosen locations, so mean kinetic is 0.5*0.1^2.
assert abs(ke_on - 0.005) < 1e-12, ke_on
print(f"forcing smoke: meanKinetic off={ke_off:.6g} on={ke_on:.6g}")
PY

printf '\n[0130 Taylor--Green forcing smoke] OK: periodic TG body acceleration changes velocities with the expected amplitude.\n'

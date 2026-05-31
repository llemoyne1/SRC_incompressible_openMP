#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_cadence_smoke_0129"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_cadence_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path('runs/resampling_cadence_smoke_0129')
root.mkdir(parents=True, exist_ok=True)
path = root / 'initial_cadence_v2.smpcd'
Nx = 8
Ny = 4
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
for iy in range(Ny):
    for ix in range(Nx):
        c = ix + Nx*iy
        if c == 0:
            masses = [1.0]                    # poor receiver
        elif c == 2:
            masses = [1.0]*8                  # rich donor
        else:
            masses = [1.0]*4
        for p, m in enumerate(masses):
            fx = 0.15 + 0.17*(p % 4)
            fy = 0.20 + 0.14*(p // 4)
            x.append((ix + fx)/Nx)
            y.append((iy + fy)/Ny)
            vx.append(0.03*(p - 1.5) + 0.001*c)
            vy.append(-0.02*((p % 3)-1.0) - 0.001*c)
            typ.append(0)
            mass.append(m)
            role.append(1)
# inactive pool for insertion
for i in range(8):
    x.append(-0.1 - 0.01*i); y.append(-0.1 - 0.01*i)
    vx.append(9.0); vy.append(-9.0); typ.append(0); mass.append(1.0); role.append(0)
Np=len(x)
with path.open('wb') as f:
    f.write(b'SRCMPCD_STATE' + b'\0\0\0')
    f.write(struct.pack('<IIIIQIIII', 2, 0x01020304, 2, 1, Np, 1, 1, Nx, Ny))
    reserved=[0]*8; reserved[0]=1; reserved[1]=1
    f.write(struct.pack('<8Q', *reserved))
    for arr in (x,y,vx,vy):
        f.write(struct.pack('<' + 'd'*Np, *arr))
    f.write(struct.pack('<' + 'I'*Np, *typ))
    f.write(struct.pack('<' + 'd'*Np, *mass))
    f.write(struct.pack('<' + 'B'*Np, *role))
print(path)
PY

write_params() {
    local label=$1
    local resampling_enable=$2
    local out_dir="$RUN_DIR/$label"
    local params="$RUN_DIR/params_${label}.kv"
    mkdir -p "$out_dir"
    cat > "$params" <<KV
inputState = $STATE
outputDir = $out_dir
Lx = 1.0
Ly = 1.0
Nx = 8
Ny = 4
dt = 0.001
nSteps = 3
alphaDeg = 120
randomRotationSign = true
gridShiftEnable = false
rngSeed = 1290
bcX = periodic
bcY = periodic
projectionEnable = false
thermostatEnable = false
kBT = 0.01
resamplingTargetCellMass = 4.0
resamplingWetMaskMode = active_domain
resamplingPoorCellMassFraction = 0.5
resamplingRichCellMassFraction = 1.5
resamplingEnable = $resampling_enable
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = 2
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = 0.5
resamplingParticleMassMax = 2.0
summaryEvery = 1
dumpStateEvery = 0
numThreads = $THREADS
KV
    echo "$params"
}

./build/src_mpcd_base "$(write_params disabled false)"
./build/src_mpcd_base "$(write_params cadence true)"

python3 - <<'PY'
import csv
import pathlib

base = pathlib.Path('runs/resampling_cadence_smoke_0129')

def rows(label):
    with (base/label/'summary_runtime.csv').open(newline='') as f:
        return list(csv.DictReader(f))

disabled = rows('disabled')
assert len(disabled) == 4, len(disabled)
for r in disabled[1:]:
    assert int(r['resampExtractionApplyAttempted']) == 0
    assert int(r['resampInsertionApplyAttempted']) == 0
    assert int(r['resampRemapApplyAttempted']) == 0
    assert int(r['resampThermalRenormAttempted']) == 0
    assert int(r['resampMassGuardAttempted']) == 0

cadence = rows('cadence')
assert len(cadence) == 4, len(cadence)
step1, step2, step3 = cadence[1], cadence[2], cadence[3]
assert int(step1['resampExtractionApplyAttempted']) == 1
assert int(step1['resampInsertionApplyAttempted']) == 1
assert int(step1['resampRemapApplyAttempted']) == 0
assert int(step1['resampThermalRenormAttempted']) == 1
assert int(step1['resampMassGuardAttempted']) == 0
assert int(step2['resampRemapApplyAttempted']) == 1
assert int(step2['resampMassGuardAttempted']) == 1
assert int(step2['resampThermalRenormAttempted']) == 1
assert int(step3['resampRemapApplyAttempted']) == 0
assert int(step3['resampThermalRenormAttempted']) == 1
assert int(step3['resampMassGuardAttempted']) == 0
print('cadence:',
      f"step1 extract={step1['resampExtractionApplyOpsApplied']} remap={step1['resampRemapApplyAttempted']} thermal={step1['resampThermalRenormAttempted']}",
      f"step2 remap={step2['resampRemapApplyAttempted']} massGuard={step2['resampMassGuardAttempted']}",
      f"step3 remap={step3['resampRemapApplyAttempted']} thermal={step3['resampThermalRenormAttempted']}")
PY

printf '\n[0129 resampling cadence smoke] OK: top-level resampling switch gates role changes, mass remap/guard follow K-period, thermal renorm runs every step.\n'

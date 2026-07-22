#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490h}"
RUN_ROOT="${RUN_ROOT:-runs/0490h_cuda_species_cell_deposit_smoke}"
NX="${NX:-6}"
NY="${NY:-2}"
GAMMA="${GAMMA:-6}"
SEED="${SEED:-1628499}"

[[ -x "$BIN" ]] || { echo "[0490h] ERROR missing binary: $BIN" >&2; exit 127; }
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/output" "$RUN_ROOT/logs"

STATE="$RUN_ROOT/init/state.smpcd"
PARAMS="$RUN_ROOT/params_0490h.kv"
LOG="$RUN_ROOT/logs/run.log"

python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$STATE" \
  --Lx 3.0 --Ly 1.0 --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" \
  --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 1 --inactive-type 0 --inactive-slots 16

python3 - "$STATE" "$GAMMA" <<'PY_STATE_0490H'
import struct, sys
p=sys.argv[1]
gamma=int(sys.argv[2])
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
if version != 2 or dim != 2 or has_mass != 1 or has_role != 1 or type_bytes != 4:
    raise SystemExit('[0490h] FAIL unsupported state layout')
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
x_off=off
y_off=off+8*n
vx_off=off+2*8*n
vy_off=off+3*8*n
type_off=off+4*8*n
mass_off=type_off+4*n
role_off=mass_off+8*n

vel={1:(0.25,-0.5),2:(-1.0,0.25),3:(0.5,1.0)}
mass={1:2.0,2:1.0,3:0.5}
for i in range(n):
    role=struct.unpack_from('<B',b,role_off+i)[0]
    if role != 1:
        struct.pack_into('<I',b,type_off+4*i,0)
        struct.pack_into('<d',b,mass_off+8*i,0.0)
        continue
    cell=i//gamma
    local=i%gamma
    mode=cell%4
    if mode == 0:
        typ=1
    elif mode == 1:
        typ=1 if local%2 == 0 else 2
    elif mode == 2:
        typ=(1,2,3)[local%3]
    else:
        typ=3
    vx,vy=vel[typ]
    struct.pack_into('<I',b,type_off+4*i,typ)
    struct.pack_into('<d',b,mass_off+8*i,mass[typ])
    struct.pack_into('<d',b,vx_off+8*i,vx)
    struct.pack_into('<d',b,vy_off+8*i,vy)
open(p,'wb').write(b)
PY_STATE_0490H

cat > "$PARAMS" <<PARAMS_0490H
inputState = $STATE
outputDir = $RUN_ROOT/output
Lx = 3.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = 0.001
nSteps = 1
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
srcClassicCudaModeEnable = false
projectionEnable = false
resamplingEnable = false
thermostatEnable = false
rotationAngle = 0.0
randomRotationSign = false
gridShiftEnable = false
rngSeed = $SEED
summaryEvery = 1
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
numThreads = 4
speciesRegistryEnable = true
speciesCount = 3
species0 = 1 liquid_A liquid 1.0 1.0 12.0
species1 = 2 gas_B gas 0.0 0.0 6.0
species2 = 3 liquid_C liquid 1.0 1.0 3.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490h.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490h.csv
speciesCellCudaDepositEnable = true
speciesCellCudaComparisonFilename = species_cell_cuda_equivalence_0490h.csv
speciesCellCudaComparisonTolerance = 1.0e-12
speciesCellCudaThreadsPerBlock = 128
PARAMS_0490H

MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0 \
MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0 \
MPCD_CUDA_STREAMING_PERIODIC_0245=0 \
  "$BIN" "$PARAMS" | tee "$LOG"

EQ_CSV="$RUN_ROOT/output/species_cell_cuda_equivalence_0490h.csv"
CELL_CSV="$RUN_ROOT/output/species_cell_runtime_0490h.csv"
[[ -s "$EQ_CSV" ]] || { echo "[0490h] FAIL missing $EQ_CSV" >&2; exit 3; }
[[ -s "$CELL_CSV" ]] || { echo "[0490h] FAIL missing $CELL_CSV" >&2; exit 3; }

python3 - "$EQ_CSV" "$NX" "$NY" "$GAMMA" <<'PY_CHECK_0490H'
import csv, math, sys
path=sys.argv[1]
nx,ny,gamma=map(int,sys.argv[2:])
rows=list(csv.DictReader(open(path,newline='')))
if [int(r['step']) for r in rows] != [0,1]:
    raise SystemExit(f"[0490h] FAIL steps={[r['step'] for r in rows]}")
fields=[
    'maxAbsMassError','maxAbsPxError','maxAbsPyError',
    'maxAbsTotalMassError','maxAbsTotalOccupancyWeightError',
    'maxAbsMassFractionError','maxAbsOccupancyFractionError',
    'maxAbsLiquidFractionError','maxAbsGasFractionError']
maxerr=0.0
for r in rows:
    if int(r['pass']) != 1:
        raise SystemExit(f"[0490h] FAIL equivalence row={r}")
    if int(r['invalidTypeCount']) != 0 or int(r['countMismatches']) != 0:
        raise SystemExit('[0490h] FAIL invalid type or count mismatch')
    if int(r['particlesScanned']) != nx*ny*gamma:
        raise SystemExit(f"[0490h] FAIL particlesScanned={r['particlesScanned']}")
    for f in fields:
        v=abs(float(r[f])); maxerr=max(maxerr,v)
        if v > 1.0e-12:
            raise SystemExit(f"[0490h] FAIL {f}={v}")
if int(rows[0]['reusedAllocation']) != 0 or int(rows[1]['reusedAllocation']) != 1:
    raise SystemExit('[0490h] FAIL resident workspace allocation was not reused')
if int(rows[0]['numCells']) != nx*ny or int(rows[0]['speciesCount']) != 3:
    raise SystemExit('[0490h] FAIL workspace dimensions')
print('[0490h] PASS')
print(f'[0490h] rows={len(rows)} cells={nx*ny} species=3 particles={nx*ny*gamma}')
print(f'[0490h] max_cuda_cpu_error={maxerr:.17g}')
print('[0490h] resident_workspace_reused=1')
PY_CHECK_0490H

echo "[0490h] EQUIVALENCE_CSV=$EQ_CSV"
echo "[0490h] CELL_CSV=$CELL_CSV"
echo "[0490h] LOG=$LOG"

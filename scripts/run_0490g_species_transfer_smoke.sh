#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490g}"
RUN_ROOT="${RUN_ROOT:-runs/0490g_species_transfer_smoke}"
SEED="${SEED:-1628498}"

[[ -x "$BIN" ]] || { echo "[0490g] ERROR missing binary: $BIN" >&2; exit 127; }
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/output" "$RUN_ROOT/logs"

STATE="$RUN_ROOT/init/state.smpcd"
PARAMS="$RUN_ROOT/params_0490g.kv"
LOG="$RUN_ROOT/logs/run.log"

python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$STATE" \
  --Lx 3.0 --Ly 1.0 --Nx 3 --Ny 1 --gamma 6 \
  --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 1 --inactive-type 0 --inactive-slots 12

python3 - "$STATE" <<'PY_STATE_0490G'
import struct, sys
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
if version != 2 or dim != 2 or has_mass != 1 or has_role != 1 or type_bytes != 4:
    raise SystemExit('[0490g] FAIL unsupported state layout')
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
x_off=off
y_off=off+8*n
vx_off=off+2*8*n
vy_off=off+3*8*n
type_off=off+4*8*n
mass_off=type_off+4*n
role_off=mass_off+8*n

# Cell 0: poor pure liquid, M=2.
# Cell 1: nearest rich donor but pure gas, M=6 (must be rejected).
# Cell 2: rich liquid donor, M=6 (must supply exactly two liquid slots).
active=[]
for q in range(2):
    active.append((0.20+0.20*q,0.50,1,1.0))
for q in range(6):
    active.append((1.08+0.13*q,0.35+0.05*(q%2),2,1.0))
for q in range(6):
    active.append((2.08+0.13*q,0.60-0.05*(q%2),1,1.0))

for i in range(n):
    if i < len(active):
        x,y,t,m=active[i]; role=1
    else:
        x=y=0.0; t=0; m=0.0; role=0
    struct.pack_into('<d',b,x_off+8*i,x)
    struct.pack_into('<d',b,y_off+8*i,y)
    struct.pack_into('<d',b,vx_off+8*i,0.0)
    struct.pack_into('<d',b,vy_off+8*i,0.0)
    struct.pack_into('<I',b,type_off+4*i,t)
    struct.pack_into('<d',b,mass_off+8*i,m)
    struct.pack_into('<B',b,role_off+i,role)
open(p,'wb').write(b)
PY_STATE_0490G

cat > "$PARAMS" <<PARAMS_0490G
inputState = $STATE
outputDir = $RUN_ROOT/output
Lx = 3.0
Ly = 1.0
Nx = 3
Ny = 1
dt = 0.001
nSteps = 1
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
srcClassicCudaModeEnable = false
projectionEnable = false
resamplingEnable = true
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = false
resamplingThermalRenormalizationEnable = false
resamplingMassGuardEnable = false
resamplingLatentActivationEnable = false
resamplingTargetCellMass = 4.0
resamplingPoorCellMassFraction = 0.75
resamplingRichCellMassFraction = 1.25
resamplingPopulationNMin = 1
resamplingPopulationNTarget = 4
resamplingPopulationNMax = 100
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
speciesCount = 2
species0 = 1 liquid_phase liquid 1.0 1.0 4.0
species1 = 2 gas_phase gas 0.0 0.0 4.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490g.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490g.csv
speciesResamplingTransferEnable = true
PARAMS_0490G

MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0 \
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=0 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=0 \
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=0 \
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0 \
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0 \
MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0 \
MPCD_CUDA_STREAMING_PERIODIC_0245=0 \
  "$BIN" "$PARAMS" | tee "$LOG"

CELL_CSV="$RUN_ROOT/output/species_cell_runtime_0490g.csv"
SPECIES_CSV="$RUN_ROOT/output/species_runtime_0490g.csv"
[[ -s "$CELL_CSV" ]] || { echo "[0490g] FAIL missing $CELL_CSV" >&2; exit 3; }
[[ -s "$SPECIES_CSV" ]] || { echo "[0490g] FAIL missing $SPECIES_CSV" >&2; exit 3; }

python3 - "$CELL_CSV" "$SPECIES_CSV" <<'PY_CHECK_0490G'
import csv, math, sys
from collections import defaultdict
cell_rows=list(csv.DictReader(open(sys.argv[1],newline='')))
species_rows=list(csv.DictReader(open(sys.argv[2],newline='')))
by_cell=defaultdict(dict)
for r in cell_rows:
    if int(r['step']) == 1:
        by_cell[int(r['cell'])][int(r['type'])]=r

expected_mass={(0,1):4.0,(1,2):6.0,(2,1):4.0}
expected_count={(0,1):4,(1,2):6,(2,1):4}
for key,m in expected_mass.items():
    c,t=key
    got=float(by_cell[c][t]['mass'])
    if not math.isclose(got,m,rel_tol=0.0,abs_tol=1e-12):
        raise SystemExit(f'[0490g] FAIL cell={c} type={t} mass={got} expected={m}')
    n=int(by_cell[c][t]['count'])
    if n != expected_count[key]:
        raise SystemExit(f'[0490g] FAIL cell={c} type={t} count={n} expected={expected_count[key]}')
if (float(by_cell[1][1]['mass']) > 1e-12 or
    float(by_cell[0][2]['mass']) > 1e-12 or
    float(by_cell[2][2]['mass']) > 1e-12):
    raise SystemExit('[0490g] FAIL cross-species transfer detected')

by_step=defaultdict(dict)
for r in species_rows:
    by_step[int(r['step'])][int(r['type'])]=r
for t,expected in ((1,8.0),(2,6.0)):
    m0=float(by_step[0][t]['totalMass'])
    m1=float(by_step[1][t]['totalMass'])
    if not math.isclose(m0,expected,abs_tol=1e-12) or not math.isclose(m1,expected,abs_tol=1e-12):
        raise SystemExit(f'[0490g] FAIL global type={t} mass0={m0} mass1={m1}')

print('[0490g] PASS')
print('[0490g] receiver_cell0=liquid_mass:4,gas_mass:0')
print('[0490g] wrong_nearest_donor_cell1=gas_mass:6,unchanged:1')
print('[0490g] matched_donor_cell2=liquid_mass:4')
print('[0490g] liquid_mass_initial=8 liquid_mass_final=8')
print('[0490g] gas_mass_initial=6 gas_mass_final=6')
PY_CHECK_0490G

echo "[0490g] CELL_CSV=$CELL_CSV"
echo "[0490g] SPECIES_CSV=$SPECIES_CSV"
echo "[0490g] LOG=$LOG"

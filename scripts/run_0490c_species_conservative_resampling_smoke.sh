#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490c}"
RUN_ROOT="${RUN_ROOT:-runs/0490c_species_conservative_resampling_smoke}"
SEED="${SEED:-1628492}"

[[ -x "$BIN" ]] || { echo "[0490c] ERROR missing binary: $BIN" >&2; exit 127; }
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT"

export SRC_LIVE_VIS_ENABLE=0
# 0490c-fix1: the shared persistent collision requires a resident periodic
# streaming producer so the 0251 device state is fresh before collision.
export MPCD_CUDA_STREAMING_PERIODIC_0245=1
export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY=1
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN=0
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET=5
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX=4
export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1

# Case A: closed mixed-species CUDA merge.
A="$RUN_ROOT/merge"
mkdir -p "$A/init" "$A/output" "$A/logs"
python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$A/init/state.smpcd" \
  --Lx 2.0 --Ly 1.0 --Nx 4 --Ny 2 --gamma 6 \
  --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 1 --inactive-type 0 --inactive-slots 48

python3 - "$A/init/state.smpcd" <<'PY_MERGE_STATE_0490C'
import struct, sys
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
type_off=off+4*8*n
mass_off=type_off+4*n
role_off=mass_off+8*n
local={}
for i in range(n):
    if struct.unpack_from('<B',b,role_off+i)[0] != 1:
        continue
    cell=i//6
    q=local.get(cell,0)
    local[cell]=q+1
    typ=1 if q%2==0 else 2
    mass=1.0 if typ==1 else 2.0
    struct.pack_into('<I',b,type_off+4*i,typ)
    struct.pack_into('<d',b,mass_off+8*i,mass)
open(p,'wb').write(b)
PY_MERGE_STATE_0490C

cat > "$A/params.kv" <<PARAMS_MERGE_0490C
inputState = $A/init/state.smpcd
outputDir = $A/output
Lx = 2.0
Ly = 1.0
Nx = 4
Ny = 2
dt = 0.005
nSteps = 1
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
srcClassicCudaModeEnable = true
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
speciesCount = 2
species0 = 1 liquid_phase liquid 1.0 1.0 6.0
species1 = 2 gas_phase gas 0.0 0.0 12.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490c.csv
PARAMS_MERGE_0490C

"$BIN" "$A/params.kv" | tee "$A/logs/run.log"

python3 - "$A/output/species_runtime_0490c.csv" <<'PY_MERGE_CHECK_0490C'
import csv, math, sys
rows=list(csv.DictReader(open(sys.argv[1],newline='')))
by={}
for r in rows:
    by.setdefault(int(r['step']),{})[int(r['type'])]=r
for t in (1,2):
    m0=float(by[0][t]['totalMass'])
    m1=float(by[1][t]['totalMass'])
    if not math.isclose(m0,m1,rel_tol=0.0,abs_tol=1e-12):
        raise SystemExit(f'[0490c] FAIL merge type={t} mass0={m0} mass1={m1}')
print('[0490c] merge PASS')
print(f"[0490c] merge_type1_mass={float(by[1][1]['totalMass']):.17g}")
print(f"[0490c] merge_type2_mass={float(by[1][2]['totalMass']):.17g}")
PY_MERGE_CHECK_0490C

# Case A2: the CPU population guard must obey the same invariant.
C="$RUN_ROOT/cpu_merge"
mkdir -p "$C/output" "$C/logs"
cat > "$C/params.kv" <<PARAMS_CPU_MERGE_0490C
inputState = $A/init/state.smpcd
outputDir = $C/output
Lx = 2.0
Ly = 1.0
Nx = 4
Ny = 2
dt = 0.005
nSteps = 1
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
srcClassicCudaModeEnable = false
projectionEnable = false
resamplingEnable = true
resamplingExtractionEnable = false
resamplingInsertionEnable = false
resamplingRemapEnable = false
resamplingThermalRenormalizationEnable = false
resamplingMassGuardEnable = false
resamplingLatentActivationEnable = false
resamplingPopulationNMin = 1
resamplingPopulationNTarget = 4
resamplingPopulationNMax = 5
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
species0 = 1 liquid_phase liquid 1.0 1.0 6.0
species1 = 2 gas_phase gas 0.0 0.0 12.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490c.csv
PARAMS_CPU_MERGE_0490C

MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0 \
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0 \
MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0 \
MPCD_CUDA_STREAMING_PERIODIC_0245=0 \
  "$BIN" "$C/params.kv" | tee "$C/logs/run.log"
python3 - "$C/output/species_runtime_0490c.csv" <<'PY_CPU_MERGE_CHECK_0490C'
import csv, math, sys
rows=list(csv.DictReader(open(sys.argv[1],newline='')))
by={}
for r in rows:
    by.setdefault(int(r['step']),{})[int(r['type'])]=r
for t in (1,2):
    m0=float(by[0][t]['totalMass'])
    m1=float(by[1][t]['totalMass'])
    if not math.isclose(m0,m1,rel_tol=0.0,abs_tol=1e-12):
        raise SystemExit(f'[0490c] FAIL cpu_merge type={t} mass0={m0} mass1={m1}')
print('[0490c] cpu_merge PASS')
print(f"[0490c] cpu_merge_type1_mass={float(by[1][1]['totalMass']):.17g}")
print(f"[0490c] cpu_merge_type2_mass={float(by[1][2]['totalMass']):.17g}")
PY_CPU_MERGE_CHECK_0490C

# Case B: empty refill must restore remembered type 2, never type 0.
B="$RUN_ROOT/refill"
mkdir -p "$B/init" "$B/output" "$B/logs"
python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$B/init/state.smpcd" \
  --Lx 2.0 --Ly 1.0 --Nx 2 --Ny 1 --gamma 4 \
  --kBT 0.0 --mass 1.0 --seed "$((SEED+1))" --u0 0.0 \
  --velocity-mode zero --background-type 2 --inactive-type 0 --inactive-slots 8

python3 - "$B/init/state.smpcd" <<'PY_REFILL_STATE_0490C'
import struct, sys
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
x_off=off
y_off=off+8*n
vx_off=off+2*8*n
vy_off=off+3*8*n
type_off=off+4*8*n
mass_off=type_off+4*n
role_off=mass_off+8*n
for i in range(n):
    active=i<4
    struct.pack_into('<B',b,role_off+i,1 if active else 0)
    struct.pack_into('<I',b,type_off+4*i,2 if active else 0)
    struct.pack_into('<d',b,mass_off+8*i,1.0 if active else 0.0)
    struct.pack_into('<d',b,x_off+8*i,0.25+0.05*i if active else 0.0)
    struct.pack_into('<d',b,y_off+8*i,0.25+0.1*i if active else 0.0)
    struct.pack_into('<d',b,vx_off+8*i,0.4 if active else 0.0)
    struct.pack_into('<d',b,vy_off+8*i,0.0)
open(p,'wb').write(b)
PY_REFILL_STATE_0490C

cat > "$B/params.kv" <<PARAMS_REFILL_0490C
inputState = $B/init/state.smpcd
outputDir = $B/output
Lx = 2.0
Ly = 1.0
Nx = 2
Ny = 1
dt = 1.0
nSteps = 2
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
srcClassicCudaModeEnable = true
projectionEnable = false
resamplingEnable = false
thermostatEnable = false
rotationAngle = 0.0
randomRotationSign = false
gridShiftEnable = false
rngSeed = $((SEED+1))
summaryEvery = 1
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
numThreads = 4
cudaResamplingEmptyRefillEnable = true
cudaResamplingEmptyRefillTargetFraction = 1.0
cudaResamplingEmptyRefillReference = gamma
cudaResamplingEmptyRefillGamma = 4
cudaResamplingEmptyRefillMemoryMaxAge = 10
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 liquid_phase liquid 1.0 1.0 4.0
species1 = 2 gas_phase gas 0.0 0.0 4.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490c.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490c.csv
PARAMS_REFILL_0490C

export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET=4
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX=0
"$BIN" "$B/params.kv" | tee "$B/logs/run.log"

python3 - "$B/output/species_runtime_0490c.csv" "$B/output/species_cell_runtime_0490c.csv" <<'PY_REFILL_CHECK_0490C'
import csv, math, sys
srows=list(csv.DictReader(open(sys.argv[1],newline='')))
final={int(r['type']):r for r in srows if int(r['step'])==2}
if int(final[1]['nFluid']) != 0 or abs(float(final[1]['totalMass'])) > 1e-12:
    raise SystemExit('[0490c] FAIL refill created liquid/type1 mass')
if not math.isclose(float(final[2]['totalMass']),4.0,rel_tol=0.0,abs_tol=1e-10):
    raise SystemExit('[0490c] FAIL refill did not preserve type2 mass')
crows=list(csv.DictReader(open(sys.argv[2],newline='')))
cell0={int(r['type']):r for r in crows if int(r['step'])==2 and int(r['cell'])==0}
if int(cell0[2]['count']) <= 0 or int(cell0[1]['count']) != 0:
    raise SystemExit('[0490c] FAIL refilled cell composition')
print('[0490c] refill PASS')
print(f"[0490c] refill_type2_mass={float(final[2]['totalMass']):.17g}")
print(f"[0490c] refill_cell0_type2_count={int(cell0[2]['count'])}")
PY_REFILL_CHECK_0490C

echo "[0490c] PASS"
echo "[0490c] MERGE_LOG=$A/logs/run.log"
echo "[0490c] CPU_MERGE_LOG=$C/logs/run.log"
echo "[0490c] REFILL_LOG=$B/logs/run.log"

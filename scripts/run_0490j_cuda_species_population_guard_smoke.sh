#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490j}"
RUN_ROOT="${RUN_ROOT:-runs/0490j_cuda_species_population_guard_smoke}"
SEED="${SEED:-1628501}"

[[ -x "$BIN" ]] || { echo "[0490j] ERROR missing binary: $BIN" >&2; exit 127; }
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/output" "$RUN_ROOT/logs"

export SRC_LIVE_VIS_ENABLE=0
export MPCD_CUDA_STREAMING_PERIODIC_0245=1
export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY=1
export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1

STATE="$RUN_ROOT/init/state.smpcd"
python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$STATE" \
  --Lx 2.0 --Ly 1.0 --Nx 2 --Ny 1 --gamma 6 \
  --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 1 --inactive-type 0 --inactive-slots 12

python3 - "$STATE" <<'PY_STATE_0490J'
import struct, sys
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
if version != 2 or dim != 2 or has_mass != 1 or has_role != 1 or type_bytes != 4:
    raise SystemExit('[0490j] FAIL unsupported state layout')
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
x_off=off; y_off=off+8*n; vx_off=off+2*8*n; vy_off=off+3*8*n
type_off=off+4*8*n; mass_off=type_off+4*n; role_off=mass_off+8*n
active=[]
active += [(0.25,0.50,1,1.0),(0.75,0.50,2,1.0)]
for q in range(4): active.append((1.10+0.10*q,0.35,1,0.25))
for q in range(2): active.append((1.65+0.10*q,0.65,2,1.50))
for i in range(n):
    if i < len(active): x,y,t,m=active[i]; role=1
    else: x=y=0.0; t=0; m=0.0; role=0
    struct.pack_into('<d',b,x_off+8*i,x); struct.pack_into('<d',b,y_off+8*i,y)
    struct.pack_into('<d',b,vx_off+8*i,0.0); struct.pack_into('<d',b,vy_off+8*i,0.0)
    struct.pack_into('<I',b,type_off+4*i,t); struct.pack_into('<d',b,mass_off+8*i,m)
    struct.pack_into('<B',b,role_off+i,role)
open(p,'wb').write(b)
PY_STATE_0490J

cat > "$RUN_ROOT/params.kv" <<PARAMS_0490J
inputState = $STATE
outputDir = $RUN_ROOT/output
Lx = 2.0
Ly = 1.0
Nx = 2
Ny = 1
dt = 0.001
nSteps = 2
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
srcClassicCudaModeEnable = true
projectionEnable = false
resamplingEnable = true
resamplingExtractionEnable = false
resamplingInsertionEnable = false
resamplingRemapEnable = false
resamplingThermalRenormalizationEnable = false
resamplingMassGuardEnable = false
resamplingLatentActivationEnable = false
resamplingTargetCellMass = 4.0
resamplingPopulationNMin = 3
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
species0 = 1 liquid_phase liquid 1.0 1.0 4.0
species1 = 2 gas_phase gas 0.0 0.0 4.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490j.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490j.csv
speciesResamplingPopulationGuardEnable = true
speciesResamplingPopulationGuardCudaEnable = true
PARAMS_0490J

"$BIN" "$RUN_ROOT/params.kv" | tee "$RUN_ROOT/logs/run.log"

CELL_CSV="$RUN_ROOT/output/species_cell_runtime_0490j.csv"
SPECIES_CSV="$RUN_ROOT/output/species_runtime_0490j.csv"
GUARD_CSV="$RUN_ROOT/output/cuda_resampling_population_guard_0297.csv"
[[ -s "$CELL_CSV" && -s "$SPECIES_CSV" && -s "$GUARD_CSV" ]] || {
  echo "[0490j] FAIL missing diagnostics" >&2; exit 3;
}

python3 - "$CELL_CSV" "$SPECIES_CSV" "$GUARD_CSV" <<'PY_CHECK_0490J'
import csv, math, sys
from collections import defaultdict
cell_rows=list(csv.DictReader(open(sys.argv[1],newline='')))
species_rows=list(csv.DictReader(open(sys.argv[2],newline='')))
guard_rows=list(csv.DictReader(open(sys.argv[3],newline='')))
by_cell=defaultdict(dict)
for r in cell_rows:
    if int(r['step']) == 2: by_cell[int(r['cell'])][int(r['type'])]=r
expected={(0,1):2,(0,2):2,(1,1):2,(1,2):2}
for (c,t),n in expected.items():
    got=int(by_cell[c][t]['count'])
    if got != n: raise SystemExit(f'[0490j] FAIL cell={c} type={t} count={got} expected={n}')
expected_mass={(0,1):1.0,(0,2):1.0,(1,1):1.0,(1,2):3.0}
for (c,t),m in expected_mass.items():
    got=float(by_cell[c][t]['mass'])
    if not math.isclose(got,m,rel_tol=0.0,abs_tol=1e-12):
        raise SystemExit(f'[0490j] FAIL cell={c} type={t} mass={got} expected={m}')
by_step=defaultdict(dict)
for r in species_rows: by_step[int(r['step'])][int(r['type'])]=r
for t,expected_mass_global in ((1,2.0),(2,4.0)):
    for step in (0,1,2):
        got=float(by_step[step][t]['totalMass'])
        if not math.isclose(got,expected_mass_global,rel_tol=0.0,abs_tol=1e-12):
            raise SystemExit(f'[0490j] FAIL type={t} step={step} mass={got}')
if len(guard_rows) != 2: raise SystemExit(f'[0490j] FAIL guard rows={len(guard_rows)} expected=2')
for r in guard_rows:
    if int(r['handled']) != 1 or int(r['speciesPopulationGuardCuda0490j']) != 1:
        raise SystemExit('[0490j] FAIL CUDA species guard not handled')
    if int(r['speciesInvalidTypeCount0490j']) != 0:
        raise SystemExit('[0490j] FAIL invalid registered type')
if sum(int(r['speciesDirectedSplits0490j']) for r in guard_rows) != 2:
    raise SystemExit('[0490j] FAIL expected two species-directed splits')
if sum(int(r['speciesDirectedMerges0490j']) for r in guard_rows) != 2:
    raise SystemExit('[0490j] FAIL expected two species-directed merges')
if int(guard_rows[-1]['speciesWorkspaceReused0490j']) != 1:
    raise SystemExit('[0490j] FAIL resident species workspace was not reused')
max_mass=max(float(r['maxAbsCellMassError']) for r in guard_rows)
max_mom=max(float(r['maxAbsCellMomentumError']) for r in guard_rows)
if max_mass > 1e-12 or max_mom > 1e-12:
    raise SystemExit(f'[0490j] FAIL conservation mass={max_mass} momentum={max_mom}')
print('[0490j] PASS')
print('[0490j] final_counts=cell0:liquid2,gas2;cell1:liquid2,gas2')
print('[0490j] directed_splits=2')
print('[0490j] directed_merges=2')
print('[0490j] liquid_mass_initial=2 liquid_mass_final=2')
print('[0490j] gas_mass_initial=4 gas_mass_final=4')
print(f'[0490j] max_cell_mass_error={max_mass:.17g}')
print(f'[0490j] max_cell_momentum_error={max_mom:.17g}')
print('[0490j] resident_species_workspace_reused=1')
PY_CHECK_0490J

echo "[0490j] CELL_CSV=$CELL_CSV"
echo "[0490j] SPECIES_CSV=$SPECIES_CSV"
echo "[0490j] GUARD_CSV=$GUARD_CSV"
echo "[0490j] LOG=$RUN_ROOT/logs/run.log"

#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490f}"
RUN_ROOT="${RUN_ROOT:-runs/0490f_mixed_species_refill_smoke}"
SEED="${SEED:-1628496}"

[[ -x "$BIN" ]] || { echo "[0490f] ERROR missing binary: $BIN" >&2; exit 127; }
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/output" "$RUN_ROOT/logs"

export SRC_LIVE_VIS_ENABLE=0
export MPCD_CUDA_STREAMING_PERIODIC_0245=1
export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY=1
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN=0
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET=4
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX=0
export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1

python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$RUN_ROOT/init/state.smpcd" \
  --Lx 2.0 --Ly 1.0 --Nx 2 --Ny 1 --gamma 4 \
  --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 1 --inactive-type 0 --inactive-slots 12

python3 - "$RUN_ROOT/init/state.smpcd" <<'PY_STATE_0490F'
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
    typ=(1 if i<2 else 2) if active else 0
    m=(1.0 if typ==1 else 2.0) if active else 0.0
    struct.pack_into('<I',b,type_off+4*i,typ)
    struct.pack_into('<d',b,mass_off+8*i,m)
    struct.pack_into('<d',b,x_off+8*i,0.20+0.05*i if active else 0.0)
    struct.pack_into('<d',b,y_off+8*i,0.20+0.15*i if active else 0.0)
    struct.pack_into('<d',b,vx_off+8*i,0.40 if active else 0.0)
    struct.pack_into('<d',b,vy_off+8*i,0.0)
open(p,'wb').write(b)
PY_STATE_0490F

cat > "$RUN_ROOT/params.kv" <<PARAMS_0490F
inputState = $RUN_ROOT/init/state.smpcd
outputDir = $RUN_ROOT/output
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
rngSeed = $SEED
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
cudaResamplingEmptyRefillSpeciesCompositionEnable = true
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 liquid_phase liquid 1.0 1.0 4.0
species1 = 2 gas_phase gas 0.0 0.0 4.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490f.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490f.csv
PARAMS_0490F

"$BIN" "$RUN_ROOT/params.kv" | tee "$RUN_ROOT/logs/run.log"

python3 - \
  "$RUN_ROOT/output/species_runtime_0490f.csv" \
  "$RUN_ROOT/output/species_cell_runtime_0490f.csv" \
  "$RUN_ROOT/output/cuda_resampling_population_guard_0297.csv" <<'PY_CHECK_0490F'
import csv, math, sys
species_csv, cell_csv, guard_csv=sys.argv[1:]
srows=list(csv.DictReader(open(species_csv,newline='')))
by={}
for r in srows:
    by.setdefault(int(r['step']),{})[int(r['type'])]=r
for typ,expected in ((1,2.0),(2,4.0)):
    m0=float(by[0][typ]['totalMass'])
    m2=float(by[2][typ]['totalMass'])
    if not math.isclose(m0,expected,rel_tol=0.0,abs_tol=1e-12):
        raise SystemExit(f'[0490f] FAIL initial type={typ} mass={m0}')
    if not math.isclose(m2,m0,rel_tol=0.0,abs_tol=1e-10):
        raise SystemExit(f'[0490f] FAIL species mass type={typ} initial={m0} final={m2}')

crows=list(csv.DictReader(open(cell_csv,newline='')))
cell0={int(r['type']):r for r in crows if int(r['step'])==2 and int(r['cell'])==0}
if set(cell0) != {1,2}:
    raise SystemExit(f'[0490f] FAIL final mixed cell types={sorted(cell0)}')
if int(cell0[1]['count']) != 2 or int(cell0[2]['count']) != 2:
    raise SystemExit('[0490f] FAIL mixed refill counts')
m1=float(cell0[1]['mass'])
m2=float(cell0[2]['mass'])
if not math.isclose(m2/m1,2.0,rel_tol=0.0,abs_tol=1e-10):
    raise SystemExit(f'[0490f] FAIL mixed refill mass ratio={m2/m1}')

grows=list(csv.DictReader(open(guard_csv,newline='')))
last=grows[-1]
if int(last['emptyRefillSpeciesCompositionEnable0490f']) != 1:
    raise SystemExit('[0490f] FAIL composition refill diagnostic disabled')
if int(last['emptyRefillMixedCells0490f']) < 1:
    raise SystemExit('[0490f] FAIL no mixed cell refilled')
if int(last['emptyRefillSkippedMixedSpecies0490c']) != 0:
    raise SystemExit('[0490f] FAIL mixed cell still rejected by 0490c fallback')
if float(last['emptyRefillMaxAbsSpeciesMassError0490f']) > 1e-10:
    raise SystemExit('[0490f] FAIL per-species mass correction error')
if float(last['emptyRefillMaxAbsSpeciesMomentumError0490f']) > 1e-10:
    raise SystemExit('[0490f] FAIL per-species momentum correction error')

print('[0490f] PASS')
print(f"[0490f] final_species_masses=liquid:{float(by[2][1]['totalMass']):.17g},gas:{float(by[2][2]['totalMass']):.17g}")
print(f"[0490f] refilled_cell0_counts=liquid:{int(cell0[1]['count'])},gas:{int(cell0[2]['count'])}")
print(f"[0490f] refilled_cell0_mass_ratio_gas_liquid={m2/m1:.17g}")
print(f"[0490f] max_species_mass_error={float(last['emptyRefillMaxAbsSpeciesMassError0490f']):.17g}")
print(f"[0490f] max_species_momentum_error={float(last['emptyRefillMaxAbsSpeciesMomentumError0490f']):.17g}")
PY_CHECK_0490F

echo "[0490f] CELL_CSV=$RUN_ROOT/output/species_cell_runtime_0490f.csv"
echo "[0490f] SPECIES_CSV=$RUN_ROOT/output/species_runtime_0490f.csv"
echo "[0490f] GUARD_CSV=$RUN_ROOT/output/cuda_resampling_population_guard_0297.csv"
echo "[0490f] LOG=$RUN_ROOT/logs/run.log"

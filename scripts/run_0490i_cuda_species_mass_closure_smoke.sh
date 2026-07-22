#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490i}"
RUN_ROOT="${RUN_ROOT:-runs/0490i_cuda_species_mass_closure_smoke}"
SEED="${SEED:-1628494}"

[[ -x "$BIN" ]] || { echo "[0490i] ERROR missing binary: $BIN" >&2; exit 127; }
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/cpu/output" "$RUN_ROOT/cpu/logs" \
         "$RUN_ROOT/gpu/output" "$RUN_ROOT/gpu/logs"

STATE="$RUN_ROOT/init/state.smpcd"
CPU_PARAMS="$RUN_ROOT/cpu/params_0490i_cpu.kv"
GPU_PARAMS="$RUN_ROOT/gpu/params_0490i_gpu.kv"
CPU_LOG="$RUN_ROOT/cpu/logs/run.log"
GPU_LOG="$RUN_ROOT/gpu/logs/run.log"

python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$STATE" \
  --Lx 6.0 --Ly 1.0 --Nx 6 --Ny 1 --gamma 4 \
  --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 1 --inactive-slots 24

python3 - "$STATE" <<'PY_STATE_0490I'
import struct, sys
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
if version != 2 or dim != 2 or has_mass != 1 or has_role != 1 or type_bytes != 4:
    raise SystemExit('[0490i] FAIL unsupported state layout')
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
type_off=off+4*8*n
mass_off=type_off+4*n
role_off=mass_off+8*n
for i in range(n):
    role=struct.unpack_from('<B',b,role_off+i)[0]
    if role != 1:
        continue
    cell=i//4
    local=i%4
    mass=0.5 if cell in (0,2,4) else 1.5
    if cell in (0,1):
        typ=1
    elif cell in (2,3):
        typ=1 if local < 2 else 2
    else:
        typ=2
    struct.pack_into('<I',b,type_off+4*i,typ)
    struct.pack_into('<d',b,mass_off+8*i,mass)
open(p,'wb').write(b)
PY_STATE_0490I

write_params_0490i() {
  local path="$1"
  local outdir="$2"
  local cuda_enable="$3"
  cat > "$path" <<PARAMS_0490I
inputState = $STATE
outputDir = $outdir
Lx = 6.0
Ly = 1.0
Nx = 6
Ny = 1
dt = 0.005
nSteps = 2
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
srcClassicCudaModeEnable = false
projectionEnable = false
resamplingEnable = true
resamplingExtractionEnable = false
resamplingInsertionEnable = false
resamplingRemapEnable = true
resamplingThermalRenormalizationEnable = false
resamplingMassRenormalizationPeriod = 1
resamplingMassGuardEnable = false
resamplingLatentActivationEnable = false
resamplingTargetCellMass = 4.0
resamplingPopulationNMin = 1
resamplingPopulationNTarget = 4
resamplingPopulationNMax = 8
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
speciesDiagnosticsFilename = species_runtime_0490i.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490i.csv
speciesResamplingMassClosureEnable = true
speciesResamplingMassClosureCudaEnable = $cuda_enable
speciesMassClosureCudaDiagnosticsFilename = cuda_species_mass_closure_0490i.csv
speciesMassClosureCudaComparisonTolerance = 1.0e-11
PARAMS_0490I
}

write_params_0490i "$CPU_PARAMS" "$RUN_ROOT/cpu/output" false
write_params_0490i "$GPU_PARAMS" "$RUN_ROOT/gpu/output" true

COMMON_ENV=(
  MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0
  MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
  MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
  MPCD_CUDA_STREAMING_PERIODIC_0245=0
)

env "${COMMON_ENV[@]}" "$BIN" "$CPU_PARAMS" | tee "$CPU_LOG"
env "${COMMON_ENV[@]}" "$BIN" "$GPU_PARAMS" | tee "$GPU_LOG"

CPU_CELL="$RUN_ROOT/cpu/output/species_cell_runtime_0490i.csv"
GPU_CELL="$RUN_ROOT/gpu/output/species_cell_runtime_0490i.csv"
CPU_SPECIES="$RUN_ROOT/cpu/output/species_runtime_0490i.csv"
GPU_SPECIES="$RUN_ROOT/gpu/output/species_runtime_0490i.csv"
CUDA_DIAG="$RUN_ROOT/gpu/output/cuda_species_mass_closure_0490i.csv"
for f in "$CPU_CELL" "$GPU_CELL" "$CPU_SPECIES" "$GPU_SPECIES" "$CUDA_DIAG"; do
  [[ -s "$f" ]] || { echo "[0490i] FAIL missing $f" >&2; exit 3; }
done

python3 - "$CPU_CELL" "$GPU_CELL" "$CPU_SPECIES" "$GPU_SPECIES" "$CUDA_DIAG" <<'PY_CHECK_0490I'
import csv, math, sys
from collections import defaultdict
cpu_cell=list(csv.DictReader(open(sys.argv[1],newline='')))
gpu_cell=list(csv.DictReader(open(sys.argv[2],newline='')))
cpu_species=list(csv.DictReader(open(sys.argv[3],newline='')))
gpu_species=list(csv.DictReader(open(sys.argv[4],newline='')))
diag=list(csv.DictReader(open(sys.argv[5],newline='')))

def key_cell(r): return (int(r['step']),int(r['cell']),int(r['type']))
def key_species(r): return (int(r['step']),int(r['type']))
cc={key_cell(r):r for r in cpu_cell}
gc={key_cell(r):r for r in gpu_cell}
cs={key_species(r):r for r in cpu_species}
gs={key_species(r):r for r in gpu_species}
if cc.keys()!=gc.keys(): raise SystemExit('[0490i] FAIL CPU/GPU cell key mismatch')
if cs.keys()!=gs.keys(): raise SystemExit('[0490i] FAIL CPU/GPU species key mismatch')
maxerr=0.0
for k in cc:
    for col in ('mass','Px','Py','occupancyWeight','fractionProxy','liquidFractionProxy','gasFractionProxy'):
        a=float(cc[k][col]); b=float(gc[k][col]); maxerr=max(maxerr,abs(a-b))
for k in cs:
    for col in ('totalMass','Px','Py'):
        a=float(cs[k][col]); b=float(gs[k][col]); maxerr=max(maxerr,abs(a-b))
if maxerr>1e-11: raise SystemExit(f'[0490i] FAIL max CPU/GPU error={maxerr}')
expected={
  1:[4.0,4.0,3.0,5.0,2.0,6.0],
  2:[4.0,4.0,3.5,4.5,2.0,6.0],
}
for step, totals in expected.items():
    for c,want in enumerate(totals):
        got=sum(float(gc[(step,c,t)]['mass']) for t in (1,2))
        if not math.isclose(got,want,rel_tol=0.0,abs_tol=1e-11):
            raise SystemExit(f'[0490i] FAIL step={step} cell={c} mass={got} expected={want}')
for step in (0,1,2):
    for typ in (1,2):
        cm=float(cs[(step,typ)]['totalMass'])
        gm=float(gs[(step,typ)]['totalMass'])
        if not math.isclose(cm,12.0,abs_tol=1e-11) or not math.isclose(gm,12.0,abs_tol=1e-11):
            raise SystemExit(f'[0490i] FAIL species mass step={step} type={typ} cpu={cm} gpu={gm}')
if len(diag)!=2: raise SystemExit(f'[0490i] FAIL diagnostics rows={len(diag)}')
if any(int(r['handled'])!=1 or int(r['sharedStatePreserved'])!=1 for r in diag):
    raise SystemExit('[0490i] FAIL resident CUDA closure not handled/preserved')
if int(diag[-1]['speciesWorkspaceReused'])!=1 or int(diag[-1]['closureWorkspaceReused'])!=1:
    raise SystemExit('[0490i] FAIL resident workspaces were not reused on step 2')
max_dep=max(float(r['maxAbsDepositMassError']) for r in diag)
if max_dep>1e-11: raise SystemExit(f'[0490i] FAIL deposit error={max_dep}')
print('[0490i] PASS')
print('[0490i] max_cuda_cpu_error=' + format(maxerr,'.17g'))
print('[0490i] max_pre_remap_deposit_error=' + format(max_dep,'.17g'))
print('[0490i] step1_final_cell_masses=4,4,3,5,2,6')
print('[0490i] step2_final_cell_masses=4,4,3.5,4.5,2,6')
print('[0490i] liquid_mass_initial=12 liquid_mass_final=12')
print('[0490i] gas_mass_initial=12 gas_mass_final=12')
print('[0490i] resident_species_workspace_reused=1')
print('[0490i] resident_closure_workspace_reused=1')
PY_CHECK_0490I

echo "[0490i] CUDA_DIAG=$CUDA_DIAG"
echo "[0490i] CPU_CELL_CSV=$CPU_CELL"
echo "[0490i] GPU_CELL_CSV=$GPU_CELL"
echo "[0490i] CPU_LOG=$CPU_LOG"
echo "[0490i] GPU_LOG=$GPU_LOG"

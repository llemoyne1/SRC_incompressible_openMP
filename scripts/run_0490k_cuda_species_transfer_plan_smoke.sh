#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490k}"
RUN_ROOT="${RUN_ROOT:-runs/0490k_cuda_species_transfer_plan_smoke}"
SEED="${SEED:-1628499}"

[[ -x "$BIN" ]] || { echo "[0490k] ERROR missing binary: $BIN" >&2; exit 127; }
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/cpu/output" "$RUN_ROOT/cpu/logs" \
         "$RUN_ROOT/gpu/output" "$RUN_ROOT/gpu/logs"

STATE="$RUN_ROOT/init/state.smpcd"

python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$STATE" \
  --Lx 3.0 --Ly 1.0 --Nx 3 --Ny 1 --gamma 6 \
  --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 1 --inactive-type 0 --inactive-slots 12

python3 - "$STATE" <<'PY_STATE_0490K'
import struct, sys
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
if version != 2 or dim != 2 or has_mass != 1 or has_role != 1 or type_bytes != 4:
    raise SystemExit('[0490k] FAIL unsupported state layout')
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
x_off=off; y_off=off+8*n; vx_off=off+2*8*n; vy_off=off+3*8*n
type_off=off+4*8*n; mass_off=type_off+4*n; role_off=mass_off+8*n

# Cell 0: poor pure liquid, M=2.
# Cell 1: nearest rich donor, but pure gas, M=6.
# Cell 2: compatible rich liquid donor, M=6.
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
PY_STATE_0490K

write_params() {
  local mode="$1" out="$2" params="$3"
  cat > "$params" <<PARAMS_0490K
inputState = $STATE
outputDir = $out
Lx = 3.0
Ly = 1.0
Nx = 3
Ny = 1
dt = 0.001
nSteps = 2
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
speciesDiagnosticsFilename = species_runtime_0490k.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490k.csv
speciesResamplingTransferEnable = true
speciesResamplingTransferCudaEnable = $mode
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490k.csv
speciesTransferCudaComparisonTolerance = 1e-11
PARAMS_0490K
}

CPU_PARAMS="$RUN_ROOT/cpu/params_0490k_cpu.kv"
GPU_PARAMS="$RUN_ROOT/gpu/params_0490k_gpu.kv"
write_params false "$RUN_ROOT/cpu/output" "$CPU_PARAMS"
write_params true  "$RUN_ROOT/gpu/output" "$GPU_PARAMS"

COMMON_ENV=(
  MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0
  MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=0
  MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=0
  MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=0
  MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
  MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
  MPCD_CUDA_STREAMING_PERIODIC_0245=0
)

env "${COMMON_ENV[@]}" "$BIN" "$CPU_PARAMS" | tee "$RUN_ROOT/cpu/logs/run.log"
env "${COMMON_ENV[@]}" "$BIN" "$GPU_PARAMS" | tee "$RUN_ROOT/gpu/logs/run.log"

CPU_CELL="$RUN_ROOT/cpu/output/species_cell_runtime_0490k.csv"
GPU_CELL="$RUN_ROOT/gpu/output/species_cell_runtime_0490k.csv"
CPU_SPECIES="$RUN_ROOT/cpu/output/species_runtime_0490k.csv"
GPU_SPECIES="$RUN_ROOT/gpu/output/species_runtime_0490k.csv"
GPU_DIAG="$RUN_ROOT/gpu/output/cuda_species_transfer_plan_0490k.csv"
for f in "$CPU_CELL" "$GPU_CELL" "$CPU_SPECIES" "$GPU_SPECIES" "$GPU_DIAG"; do
  [[ -s "$f" ]] || { echo "[0490k] FAIL missing $f" >&2; exit 3; }
done

python3 - "$CPU_CELL" "$GPU_CELL" "$CPU_SPECIES" "$GPU_SPECIES" "$GPU_DIAG" <<'PY_CHECK_0490K'
import csv, math, sys
from collections import defaultdict
cpu_cell=list(csv.DictReader(open(sys.argv[1],newline='')))
gpu_cell=list(csv.DictReader(open(sys.argv[2],newline='')))
cpu_species=list(csv.DictReader(open(sys.argv[3],newline='')))
gpu_species=list(csv.DictReader(open(sys.argv[4],newline='')))
diag=list(csv.DictReader(open(sys.argv[5],newline='')))

def cell_map(rows):
    out={}
    for r in rows:
        out[(int(r['step']),int(r['cell']),int(r['type']))]=r
    return out
cm,gm=cell_map(cpu_cell),cell_map(gpu_cell)
if cm.keys()!=gm.keys():
    raise SystemExit('[0490k] FAIL CPU/GPU cell key mismatch')
max_err=0.0
for k in cm:
    if int(cm[k]['count']) != int(gm[k]['count']):
        raise SystemExit(f'[0490k] FAIL count mismatch key={k}')
    for name in ('mass','Px','Py'):
        e=abs(float(cm[k][name])-float(gm[k][name])); max_err=max(max_err,e)
        if e>1e-12:
            raise SystemExit(f'[0490k] FAIL {name} mismatch key={k} error={e}')

# Final physical state: liquid moved from cell 2 to cell 0; gas donor unchanged.
final=defaultdict(dict)
for r in gpu_cell:
    if int(r['step'])==2:
        final[int(r['cell'])][int(r['type'])]=r
expected={(0,1):(4,4.0),(1,2):(6,6.0),(2,1):(4,4.0)}
for (c,t),(n,m) in expected.items():
    r=final[c][t]
    if int(r['count'])!=n or not math.isclose(float(r['mass']),m,abs_tol=1e-12):
        raise SystemExit(f'[0490k] FAIL final cell={c} type={t}')
if float(final[0][2]['mass'])>1e-12 or float(final[1][1]['mass'])>1e-12:
    raise SystemExit('[0490k] FAIL cross-species transfer detected')

def species_map(rows):
    return {(int(r['step']),int(r['type'])):r for r in rows}
cs,gs=species_map(cpu_species),species_map(gpu_species)
if cs.keys()!=gs.keys():
    raise SystemExit('[0490k] FAIL CPU/GPU species key mismatch')
for k in cs:
    if abs(float(cs[k]['totalMass'])-float(gs[k]['totalMass']))>1e-12:
        raise SystemExit(f'[0490k] FAIL species mass mismatch key={k}')
for t,expected_mass in ((1,8.0),(2,6.0)):
    if not math.isclose(float(gs[(2,t)]['totalMass']),expected_mass,abs_tol=1e-12):
        raise SystemExit(f'[0490k] FAIL final global type={t}')

if len(diag)!=2:
    raise SystemExit(f'[0490k] FAIL diagnostics rows={len(diag)} expected=2')
for r in diag:
    if r['handled']!='1' or r['pass']!='1' or r['accepted']!='1':
        raise SystemExit(f"[0490k] FAIL gate row step={r['step']}")
    if int(r['planMismatch'])!=0 or int(r['typeMismatch'])!=0 or int(r['overflowCount'])!=0:
        raise SystemExit(f"[0490k] FAIL mismatch row step={r['step']}")
step1=next(r for r in diag if int(r['step'])==1)
if (int(step1['gpuPlanEntries'])!=1 or int(step1['firstDonorCell'])!=2 or
    int(step1['firstReceiverCell'])!=0 or int(step1['firstParticleType'])!=1):
    raise SystemExit('[0490k] FAIL native GPU planner selected wrong donor/type')
if not any(int(r['speciesWorkspaceReused'])==1 and int(r['planWorkspaceReused'])==1 for r in diag):
    raise SystemExit('[0490k] FAIL resident workspaces were not reused')

print('[0490k] PASS')
print(f'[0490k] max_cuda_cpu_state_error={max_err:.17g}')
print('[0490k] native_gpu_plan_accepted=1')
print('[0490k] step1_plan=donor2->receiver0,type1,mass2')
print('[0490k] wrong_nearest_gas_donor_unchanged=1')
print('[0490k] liquid_mass_initial=8 liquid_mass_final=8')
print('[0490k] gas_mass_initial=6 gas_mass_final=6')
print('[0490k] resident_species_workspace_reused=1')
print('[0490k] resident_plan_workspace_reused=1')
PY_CHECK_0490K

echo "[0490k] GPU_DIAG=$GPU_DIAG"
echo "[0490k] CPU_CELL_CSV=$CPU_CELL"
echo "[0490k] GPU_CELL_CSV=$GPU_CELL"
echo "[0490k] CPU_LOG=$RUN_ROOT/cpu/logs/run.log"
echo "[0490k] GPU_LOG=$RUN_ROOT/gpu/logs/run.log"

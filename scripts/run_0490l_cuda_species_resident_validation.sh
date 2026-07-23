#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490l}"
RUN_ROOT="${RUN_ROOT:-runs/0490l_cuda_species_resident_validation}"
SEED="${SEED:-1628501}"

[[ -x "$BIN" ]] || { echo "[0490l] ERROR missing binary: $BIN" >&2; exit 127; }
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/logs"

run_subtest() {
  local tag="$1" script="$2"
  echo "[0490l] running $tag"
  BIN="$BIN" RUN_ROOT="$RUN_ROOT/$tag" LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
    bash "$script" 2>&1 | tee "$RUN_ROOT/logs/${tag}.log"
  grep -q "^\[$3\] PASS" "$RUN_ROOT/logs/${tag}.log" || {
    echo "[0490l] FAIL subtest $tag" >&2
    exit 20
  }
}

# Revalidate the resident species cell deposit, mass closure, population guard,
# and mixed-cell refill with the final 0490l binary.
run_subtest deposit scripts/run_0490h_cuda_species_cell_deposit_smoke.sh 0490h
run_subtest mass_closure scripts/run_0490i_cuda_species_mass_closure_smoke.sh 0490i
run_subtest population_guard scripts/run_0490j_cuda_species_population_guard_smoke.sh 0490j
run_subtest mixed_refill scripts/run_0490f_mixed_species_refill_smoke.sh 0490f

# Strict resident transfer case. The CPU 0490g plan and CPU passive operation
# mirror are disabled by speciesResamplingCudaResidentValidationEnable.
STRICT="$RUN_ROOT/strict_transfer"
mkdir -p "$STRICT/init" "$STRICT/output" "$STRICT/logs"
STATE="$STRICT/init/state.smpcd"

python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$STATE" \
  --Lx 3.0 --Ly 1.0 --Nx 3 --Ny 1 --gamma 6 \
  --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 1 --inactive-type 0 --inactive-slots 12

python3 - "$STATE" <<'PY_STATE_0490L'
import struct, sys
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
if version != 2 or dim != 2 or has_mass != 1 or has_role != 1 or type_bytes != 4:
    raise SystemExit('[0490l] FAIL unsupported state layout')
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
x_off=off; y_off=off+8*n; vx_off=off+2*8*n; vy_off=off+3*8*n
type_off=off+4*8*n; mass_off=type_off+4*n; role_off=mass_off+8*n
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
PY_STATE_0490L

cat > "$STRICT/params.kv" <<PARAMS_0490L
inputState = $STATE
outputDir = $STRICT/output
Lx = 3.0
Ly = 1.0
Nx = 3
Ny = 1
dt = 0.001
nSteps = 3
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
speciesDiagnosticsFilename = species_runtime_0490l.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490l.csv
speciesResamplingTransferEnable = true
speciesResamplingTransferCudaEnable = true
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490l.csv
speciesTransferCudaComparisonTolerance = 1e-11
speciesResamplingCudaResidentValidationEnable = true
PARAMS_0490L

MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1 \
MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1 \
MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1 \
MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=1 \
MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B=1 \
MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A=1 \
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=1 \
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_EVERY_0453=1 \
MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=0 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=0 \
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0 \
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0 \
MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0 \
MPCD_CUDA_STREAMING_PERIODIC_0245=0 \
"$BIN" "$STRICT/params.kv" 2>&1 | tee "$STRICT/logs/run.log"

CELL="$STRICT/output/species_cell_runtime_0490l.csv"
SPECIES="$STRICT/output/species_runtime_0490l.csv"
PLAN="$STRICT/output/cuda_species_transfer_plan_0490l.csv"
MAT="$STRICT/output/cuda_resampling_operation_materialize_0453.csv"
APPLY="$STRICT/output/cuda_resampling_pipeline_apply_0448.csv"
for f in "$CELL" "$SPECIES" "$PLAN" "$MAT" "$APPLY"; do
  [[ -s "$f" ]] || { echo "[0490l] FAIL missing $f" >&2; exit 30; }
done

python3 - "$CELL" "$SPECIES" "$PLAN" "$MAT" "$APPLY" <<'PY_CHECK_0490L'
import csv, math, sys
from collections import defaultdict
cell=list(csv.DictReader(open(sys.argv[1],newline='')))
species=list(csv.DictReader(open(sys.argv[2],newline='')))
plan=list(csv.DictReader(open(sys.argv[3],newline='')))
mat=list(csv.DictReader(open(sys.argv[4],newline='')))
apply=list(csv.DictReader(open(sys.argv[5],newline='')))

p1=next((r for r in plan if int(r['step'])==1),None)
if p1 is None:
    raise SystemExit('[0490l] FAIL missing step-1 native plan diagnostics')
for key in ('handled','pass','accepted','strictResidentMode','cpuReferenceSkipped'):
    if int(p1[key]) != 1:
        raise SystemExit(f'[0490l] FAIL plan {key}={p1[key]}')
if int(p1['cpuPlanEntries']) != 0:
    raise SystemExit('[0490l] FAIL CPU transfer plan was not skipped')
if int(p1['gpuPlanEntries']) != 1 or int(p1['firstDonorCell']) != 2 or int(p1['firstReceiverCell']) != 0 or int(p1['firstParticleType']) != 1:
    raise SystemExit('[0490l] FAIL native GPU transfer plan mismatch')

m1=next((r for r in mat if int(r['step'])==1),None)
if m1 is None:
    raise SystemExit('[0490l] FAIL missing step-1 materializer diagnostics')
for key in ('handled','applied','pass','strictResidentMode','cpuReferenceSkipped'):
    if int(m1[key]) != 1:
        raise SystemExit(f'[0490l] FAIL materializer {key}={m1[key]}')
if int(m1['cpuOps']) != 0 or int(m1['gpuOps']) < 1 or int(m1['invalidOps']) != 0:
    raise SystemExit('[0490l] FAIL strict GPU operation materializer audit')

a1=next((r for r in apply if int(r['step'])==1 and r['stage']=='particle_edits_0448'),None)
if a1 is None:
    raise SystemExit('[0490l] FAIL missing CUDA particle apply diagnostics')
if int(a1['handled']) != 1 or int(a1['applied']) != 1 or int(a1['skipped']) != 0:
    raise SystemExit('[0490l] FAIL CUDA particle edit backend not authoritative')
if int(a1['gpuExtractionApplied']) < 1 or int(a1['gpuInsertionApplied']) < 1 or int(a1['gpuInvalidOperations']) != 0:
    raise SystemExit('[0490l] FAIL invalid CUDA extraction/insertion counts')

final=defaultdict(dict)
for r in cell:
    if int(r['step'])==3:
        final[int(r['cell'])][int(r['type'])]=r
expected={(0,1):(4,4.0),(1,2):(6,6.0),(2,1):(4,4.0)}
for (c,t),(n,m) in expected.items():
    r=final[c][t]
    if int(r['count']) != n or not math.isclose(float(r['mass']),m,abs_tol=1e-12):
        raise SystemExit(f'[0490l] FAIL final cell={c} type={t}')
if float(final[0][2]['mass']) > 1e-12 or float(final[1][1]['mass']) > 1e-12:
    raise SystemExit('[0490l] FAIL cross-species transfer detected')

by={(int(r['step']),int(r['type'])):r for r in species}
for t,expected_mass in ((1,8.0),(2,6.0)):
    if not math.isclose(float(by[(3,t)]['totalMass']),expected_mass,abs_tol=1e-12):
        raise SystemExit(f'[0490l] FAIL global species mass type={t}')

if not any(int(r['speciesWorkspaceReused'])==1 and int(r['planWorkspaceReused'])==1 for r in plan):
    raise SystemExit('[0490l] FAIL resident planner workspaces were not reused')

print('[0490l] strict_transfer PASS')
print('[0490l] cpu_transfer_plan_entries=0')
print('[0490l] cpu_passive_operation_entries=0')
print('[0490l] gpu_plan_entries_step1=1')
print(f"[0490l] gpu_materialized_ops_step1={int(m1['gpuOps'])}")
print(f"[0490l] gpu_particle_edits_step1=extract:{int(a1['gpuExtractionApplied'])},insert:{int(a1['gpuInsertionApplied'])}")
print('[0490l] liquid_mass_initial=8 liquid_mass_final=8')
print('[0490l] gas_mass_initial=6 gas_mass_final=6')
print('[0490l] resident_species_workspace_reused=1')
print('[0490l] resident_plan_workspace_reused=1')
PY_CHECK_0490L

echo "[0490l] PASS"
echo "[0490l] validated_modules=deposit,mass_closure,population_guard,mixed_refill,native_transfer_plan,gpu_materializer,gpu_particle_apply"
echo "[0490l] STRICT_PLAN_CSV=$PLAN"
echo "[0490l] STRICT_MATERIALIZER_CSV=$MAT"
echo "[0490l] STRICT_APPLY_CSV=$APPLY"
echo "[0490l] LOG_ROOT=$RUN_ROOT/logs"

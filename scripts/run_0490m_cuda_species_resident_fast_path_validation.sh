#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490m}"
RUN_ROOT="${RUN_ROOT:-runs/0490m_cuda_species_resident_fast_path_validation}"
STEPS="${STEPS:-100}"
SEEDS="${SEEDS:-1628501 1628502 1628503}"

[[ -x "$BIN" ]] || { echo "[0490m] ERROR missing binary: $BIN" >&2; exit 127; }
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/logs"

# First retain the complete 0490l validation suite as a non-regression gate.
echo "[0490m] running 0490l non-regression suite"
BIN="$BIN" RUN_ROOT="$RUN_ROOT/nonregression_0490l" LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
  bash scripts/run_0490l_cuda_species_resident_validation.sh \
  2>&1 | tee "$RUN_ROOT/logs/nonregression_0490l.log"
grep -q '^\[0490l\] PASS' "$RUN_ROOT/logs/nonregression_0490l.log" || {
  echo "[0490m] FAIL 0490l non-regression suite" >&2
  exit 20
}

# ---------------------------------------------------------------------------
# Direct device-plan handoff smoke. The compatible donor is mixed and stores
# gas particles before liquid particles, so the 0490m kernel must reject wrong
# types inside the selected donor cell while never using the nearer gas donor.
# ---------------------------------------------------------------------------
DIRECT="$RUN_ROOT/direct_handoff"
mkdir -p "$DIRECT/init" "$DIRECT/output" "$DIRECT/logs"
STATE="$DIRECT/init/state.smpcd"
python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$STATE" \
  --Lx 3.0 --Ly 1.0 --Nx 3 --Ny 1 --gamma 6 \
  --kBT 0.0 --mass 1.0 --seed 1628501 --u0 0.0 \
  --velocity-mode zero --background-type 1 --inactive-type 0 --inactive-slots 16

python3 - "$STATE" <<'PY_STATE_DIRECT_0490M'
import struct,sys
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
if version != 2 or dim != 2 or has_mass != 1 or has_role != 1 or type_bytes != 4:
    raise SystemExit('[0490m] FAIL unsupported direct-smoke state layout')
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
x_off=off; y_off=off+8*n; vx_off=off+2*8*n; vy_off=off+3*8*n
type_off=off+4*8*n; mass_off=type_off+4*n; role_off=mass_off+8*n
active=[]
# Receiver: two liquid particles, total mass 2.
active += [(0.20,0.45,1,1.0),(0.55,0.55,1,1.0)]
# Nearest but incompatible donor: six gas particles.
active += [(1.08+0.14*q,0.35+0.08*(q%2),2,1.0) for q in range(6)]
# Compatible mixed donor: gas entries deliberately precede liquid entries.
active += [(2.08,0.35,2,1.0),(2.22,0.55,2,1.0)]
active += [(2.36+0.14*q,0.35+0.08*(q%2),1,1.0) for q in range(4)]
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
PY_STATE_DIRECT_0490M

cat > "$DIRECT/params.kv" <<PARAMS_DIRECT_0490M
inputState = $STATE
outputDir = $DIRECT/output
Lx = 3.0
Ly = 1.0
Nx = 3
Ny = 1
dt = 0.001
nSteps = 5
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
rngSeed = 1628501
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
speciesDiagnosticsFilename = species_runtime_0490m.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490m.csv
speciesResamplingTransferEnable = true
speciesResamplingTransferCudaEnable = true
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490m.csv
speciesTransferCudaComparisonTolerance = 1e-11
speciesResamplingCudaResidentValidationEnable = false
speciesResamplingCudaResidentFastPathEnable = true
speciesCudaResidentFastPathDiagnosticsFilename = cuda_species_resident_fast_path_0490m.csv
PARAMS_DIRECT_0490M

MPCD_INTERNAL_PROFILES=1 \
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=0 \
MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0 \
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=0 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=0 \
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0 \
MPCD_CUDA_STREAMING_PERIODIC_0245=0 \
"$BIN" "$DIRECT/params.kv" 2>&1 | tee "$DIRECT/logs/run.log"

python3 - "$DIRECT/output" <<'PY_CHECK_DIRECT_0490M'
import csv,math,pathlib,sys
out=pathlib.Path(sys.argv[1])
plan=list(csv.DictReader(open(out/'cuda_species_transfer_plan_0490m.csv',newline='')))
fast=list(csv.DictReader(open(out/'cuda_species_resident_fast_path_0490m.csv',newline='')))
cell=list(csv.DictReader(open(out/'species_cell_runtime_0490m.csv',newline='')))
species=list(csv.DictReader(open(out/'species_runtime_0490m.csv',newline='')))
p1=next(r for r in plan if int(r['step'])==1)
f1=next(r for r in fast if int(r['step'])==1)
for k in ('handled','pass','accepted','strictResidentMode','productionFastPath','cpuReferenceSkipped','planArrayDownloadSkipped','directDeviceHandoffReady'):
    if int(p1[k]) != 1: raise SystemExit(f'[0490m] FAIL direct plan {k}={p1[k]}')
if int(p1['cpuPlanEntries']) != 0 or int(p1['gpuPlanEntries']) != 1:
    raise SystemExit('[0490m] FAIL direct plan count/reference audit')
if (int(p1['firstDonorCell']),int(p1['firstReceiverCell']),int(p1['firstParticleType'])) != (2,0,1):
    raise SystemExit('[0490m] FAIL direct plan selected wrong donor/receiver/type')
for k in ('handled','applied','pass','directDevicePlanHandoff','planArrayDownloadSkipped','planArrayUploadSkipped','operationRoundTripSkipped','fullStateCopySkipped','fullStateDownloadSkipped'):
    if int(f1[k]) != 1: raise SystemExit(f'[0490m] FAIL direct fast path {k}={f1[k]}')
if int(f1['operations']) != 2 or int(f1['invalidOperations']) != 0:
    raise SystemExit('[0490m] FAIL direct operation count')
if int(f1['typeRejectedCandidates']) < 2:
    raise SystemExit('[0490m] FAIL direct path did not exercise same-donor type rejection')
if int(f1['compactPatchbackBytes']) <= 0:
    raise SystemExit('[0490m] FAIL compact host patchback missing')
if (out/'cuda_resampling_operation_materialize_0453.csv').exists() or (out/'cuda_resampling_pipeline_apply_0448.csv').exists():
    raise SystemExit('[0490m] FAIL transitional 0453/0448 path executed')
final={(int(r['cell']),int(r['type'])):r for r in cell if int(r['step'])==5}
expected={(0,1):(4,4.0),(1,2):(6,6.0),(2,1):(2,2.0),(2,2):(2,2.0)}
for key,(n,m) in expected.items():
    r=final[key]
    if int(r['count']) != n or not math.isclose(float(r['mass']),m,abs_tol=1e-12):
        raise SystemExit(f'[0490m] FAIL direct final cell/type {key}')
by={(int(r['step']),int(r['type'])):r for r in species}
for t,m in ((1,6.0),(2,8.0)):
    if not math.isclose(float(by[(5,t)]['totalMass']),m,abs_tol=1e-12):
        raise SystemExit(f'[0490m] FAIL direct global species mass type={t}')
print('[0490m] direct_handoff PASS')
print('[0490m] direct_plan_array_roundtrip=0')
print('[0490m] direct_operation_array_roundtrip=0')
print('[0490m] direct_full_state_copy=0')
print('[0490m] direct_full_state_download=0')
print(f"[0490m] direct_compact_patchback_bytes={int(f1['compactPatchbackBytes'])}")
print(f"[0490m] direct_type_rejected_candidates={int(f1['typeRejectedCandidates'])}")
PY_CHECK_DIRECT_0490M

# ---------------------------------------------------------------------------
# Long integrated suite: species population guard, native transfer planner,
# direct device handoff, mixed refill support and phase registry, plus resident
# species mass closure. Every cell starts with identical 50/50 composition so
# global per-species conservation is an exact test despite strong poor/rich
# mass and population perturbations.
# ---------------------------------------------------------------------------
for SEED in $SEEDS; do
  CASE="$RUN_ROOT/long_seed_${SEED}"
  mkdir -p "$CASE/init" "$CASE/output" "$CASE/logs"
  STATE="$CASE/init/state.smpcd"
  python3 scripts/src_mpcd_case_generator_0434.py \
    --case uniform --state "$STATE" \
    --Lx 8.0 --Ly 2.0 --Nx 8 --Ny 2 --gamma 6 \
    --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
    --velocity-mode zero --background-type 1 --inactive-type 0 --inactive-slots 256

  python3 - "$STATE" "$SEED" <<'PY_STATE_LONG_0490M'
import math,random,struct,sys
p=sys.argv[1]; seed=int(sys.argv[2]); rng=random.Random(seed)
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
if version != 2 or dim != 2 or has_mass != 1 or has_role != 1 or type_bytes != 4:
    raise SystemExit('[0490m] FAIL unsupported long state layout')
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
x_off=off; y_off=off+8*n; vx_off=off+2*8*n; vy_off=off+3*8*n
type_off=off+4*8*n; mass_off=type_off+4*n; role_off=mass_off+8*n
active=[]
Nx,Ny=8,2
for c in range(Nx*Ny):
    count=2 if c%2==0 else 10
    pairs=count//2
    ix=c%Nx; iy=c//Nx
    for q in range(pairs):
        # Paired species share exact position/velocity, preserving a 50/50
        # composition under streaming until a species-aware resampling event.
        fx=0.08+0.84*((q+0.37*rng.random())/max(1,pairs))
        fy=0.15+0.70*rng.random()
        x=ix+min(0.94,max(0.06,fx)); y=iy+fy
        vx=0.18*(2.0*rng.random()-1.0)
        vy=0.10*(2.0*rng.random()-1.0)
        # Alternate order by cell to exercise type filtering deterministically.
        order=(2,1) if (c+q)%2==0 else (1,2)
        for t in order:
            active.append((x,y,vx,vy,t,1.0))
if len(active)!=96:
    raise SystemExit(f'[0490m] FAIL long active count {len(active)}')
for i in range(n):
    if i < len(active):
        x,y,vx,vy,t,m=active[i]; role=1
    else:
        x=y=vx=vy=0.0; t=0; m=0.0; role=0
    struct.pack_into('<d',b,x_off+8*i,x)
    struct.pack_into('<d',b,y_off+8*i,y)
    struct.pack_into('<d',b,vx_off+8*i,vx)
    struct.pack_into('<d',b,vy_off+8*i,vy)
    struct.pack_into('<I',b,type_off+4*i,t)
    struct.pack_into('<d',b,mass_off+8*i,m)
    struct.pack_into('<B',b,role_off+i,role)
open(p,'wb').write(b)
PY_STATE_LONG_0490M

  cat > "$CASE/params.kv" <<PARAMS_LONG_0490M
inputState = $STATE
outputDir = $CASE/output
Lx = 8.0
Ly = 2.0
Nx = 8
Ny = 2
dt = 0.01
nSteps = $STEPS
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
# The long integrated case validates the complete resident upstream path as
# well as resident species resampling. 0490j deliberately refuses to mutate a
# stale shared device state, so periodic streaming and SRC collision must leave
# the CUDA state authoritative before the population guard.
srcClassicCudaModeEnable = true
projectionEnable = false
resamplingEnable = true
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingThermalRenormalizationEnable = false
resamplingMassRenormalizationPeriod = 1
resamplingMassGuardEnable = false
resamplingLatentActivationEnable = false
resamplingTargetCellMass = 6.0
resamplingPoorCellMassFraction = 0.75
resamplingRichCellMassFraction = 1.25
resamplingPopulationNMin = 3
resamplingPopulationNTarget = 6
resamplingPopulationNMax = 9
cudaResamplingEmptyRefillEnable = true
cudaResamplingEmptyRefillTargetFraction = 1.0
cudaResamplingEmptyRefillReference = gamma
cudaResamplingEmptyRefillGamma = 6
cudaResamplingEmptyRefillMemoryMaxAge = 50
cudaResamplingEmptyRefillSpeciesCompositionEnable = true
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
species1 = 2 gas_phase gas 1.0 1.0 6.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490m.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490m.csv
speciesResamplingPopulationGuardEnable = true
speciesResamplingPopulationGuardCudaEnable = true
speciesResamplingTransferEnable = true
speciesResamplingTransferCudaEnable = true
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490m.csv
speciesTransferCudaComparisonTolerance = 1e-11
speciesResamplingMassClosureEnable = true
speciesResamplingMassClosureCudaEnable = true
speciesMassClosureCudaDiagnosticsFilename = cuda_species_mass_closure_0490m.csv
speciesMassClosureCudaComparisonTolerance = 1e-11
speciesResamplingCudaResidentValidationEnable = false
speciesResamplingCudaResidentFastPathEnable = true
speciesCudaResidentFastPathDiagnosticsFilename = cuda_species_resident_fast_path_0490m.csv
PARAMS_LONG_0490M

  MPCD_INTERNAL_PROFILES=1 \
  MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=0 \
  MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0 \
  MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=0 \
  MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=0 \
  MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1 \
  MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1 \
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1 \
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1 \
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 \
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 \
  MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1 \
  MPCD_CUDA_STREAMING_PERIODIC_0245=1 \
  MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0 \
  "$BIN" "$CASE/params.kv" 2>&1 | tee "$CASE/logs/run.log"

done

python3 - "$RUN_ROOT" "$STEPS" $SEEDS <<'PY_CHECK_LONG_0490M'
import csv,math,pathlib,sys
root=pathlib.Path(sys.argv[1]); steps=int(sys.argv[2]); seeds=[int(x) for x in sys.argv[3:]]
summary=[]
for seed in seeds:
    out=root/f'long_seed_{seed}'/'output'
    required=['cuda_species_transfer_plan_0490m.csv','cuda_species_resident_fast_path_0490m.csv',
              'cuda_species_mass_closure_0490m.csv','cuda_resampling_population_guard_0297.csv',
              'species_runtime_0490m.csv','species_cell_runtime_0490m.csv','phase_profile_0163.csv']
    for name in required:
        if not (out/name).is_file(): raise SystemExit(f'[0490m] FAIL seed={seed} missing {name}')
    if (out/'cuda_resampling_operation_materialize_0453.csv').exists() or (out/'cuda_resampling_pipeline_apply_0448.csv').exists():
        raise SystemExit(f'[0490m] FAIL seed={seed} transitional 0453/0448 path executed')
    plan=list(csv.DictReader(open(out/'cuda_species_transfer_plan_0490m.csv',newline='')))
    fast=list(csv.DictReader(open(out/'cuda_species_resident_fast_path_0490m.csv',newline='')))
    close=list(csv.DictReader(open(out/'cuda_species_mass_closure_0490m.csv',newline='')))
    species=list(csv.DictReader(open(out/'species_runtime_0490m.csv',newline='')))
    guard=list(csv.DictReader(open(out/'cuda_resampling_population_guard_0297.csv',newline='')))
    if len(plan)!=steps or len(fast)!=steps or len(close)!=steps:
        raise SystemExit(f'[0490m] FAIL seed={seed} incomplete per-step diagnostics')
    for r in plan:
        for k in ('handled','pass','accepted','strictResidentMode','productionFastPath','cpuReferenceSkipped','planArrayDownloadSkipped','directDeviceHandoffReady'):
            if int(r[k]) != 1: raise SystemExit(f'[0490m] FAIL seed={seed} plan step={r["step"]} {k}')
        if int(r['cpuPlanEntries']) != 0:
            raise SystemExit(f'[0490m] FAIL seed={seed} CPU plan entry detected')
    for r in fast:
        for k in ('handled','pass','directDevicePlanHandoff','planArrayDownloadSkipped','planArrayUploadSkipped','operationRoundTripSkipped','fullStateCopySkipped','fullStateDownloadSkipped'):
            if int(r[k]) != 1: raise SystemExit(f'[0490m] FAIL seed={seed} fast step={r["step"]} {k}')
        if int(r['invalidOperations']) != 0:
            raise SystemExit(f'[0490m] FAIL seed={seed} invalid direct operation')
    for r in close:
        for k in ('handled','productionFastPath','diagnosticCellDownloadSkipped','cpuDepositComparisonSkipped'):
            if int(r[k]) != 1: raise SystemExit(f'[0490m] FAIL seed={seed} closure step={r["step"]} {k}')
        if not math.isfinite(float(r['particleDownloadSeconds'])):
            raise SystemExit(f'[0490m] FAIL seed={seed} invalid closure sync timing')
    if sum(int(r['operations']) for r in fast) <= 0:
        raise SystemExit(f'[0490m] FAIL seed={seed} no direct transfer operation exercised')
    if not any(int(r['workspaceReused'])==1 for r in fast[1:]):
        raise SystemExit(f'[0490m] FAIL seed={seed} fast workspace not reused')
    if not any(int(r['planWorkspaceReused'])==1 and int(r['speciesWorkspaceReused'])==1 for r in plan[1:]):
        raise SystemExit(f'[0490m] FAIL seed={seed} planner workspaces not reused')
    if not any(int(r.get('speciesDirectedSplits0490j','0'))>0 for r in guard):
        raise SystemExit(f'[0490m] FAIL seed={seed} no CUDA species-directed split')
    if not any(int(r.get('speciesDirectedMerges0490j','0'))>0 for r in guard):
        raise SystemExit(f'[0490m] FAIL seed={seed} no CUDA species-directed merge')
    by={(int(r['step']),int(r['type'])):r for r in species}
    for t in (1,2):
        m0=float(by[(0,t)]['totalMass']); mf=float(by[(steps,t)]['totalMass'])
        if not math.isclose(m0,48.0,abs_tol=1e-10) or not math.isclose(mf,m0,rel_tol=0.0,abs_tol=2e-8):
            raise SystemExit(f'[0490m] FAIL seed={seed} species mass type={t} initial={m0} final={mf}')
    profile={r['phase']:float(r['ms_per_step']) for r in csv.DictReader(open(out/'phase_profile_0163.csv',newline=''))}
    cpu_remaining=sum(profile.get(k,0.0) for k in (
        'resampling_pool_initial','resampling_deposit_initial','resampling_post_guard_pool',
        'resampling_post_guard_deposit','resampling_post_edit_pool','resampling_post_edit_deposit',
        'resampling_post_remap_deposit'))
    closure_sync=sum(float(r['particleDownloadSeconds']) for r in close)/max(1,len(close))*1000.0
    operations=sum(int(r['operations']) for r in fast)
    patchbytes=sum(int(r['compactPatchbackBytes']) for r in fast)
    summary.append((seed,operations,patchbytes,cpu_remaining,closure_sync))
    print(f'[0490m] long_seed_{seed} PASS operations={operations} compact_patchback_bytes={patchbytes} remaining_cpu_resampling_ms_per_step={cpu_remaining:.9g} closure_active_sync_ms_per_step={closure_sync:.9g}')
print('[0490m] long_validation PASS')
print(f'[0490m] seeds={len(seeds)} steps_per_seed={steps}')
print('[0490m] cpu_transfer_plan_entries=0')
print('[0490m] cpu_passive_operation_entries=0')
print('[0490m] plan_array_d2h_h2d_roundtrip=0')
print('[0490m] operation_array_d2h_h2d_roundtrip=0')
print('[0490m] full_particle_state_rollback_copy=0')
print('[0490m] full_particle_state_download_after_transfer=0')
print('[0490m] remaining_cpu_scope=weighted_deposit,pool_rebuild,post_edit_deposit,post_remap_deposit')
PY_CHECK_LONG_0490M

echo "[0490m] PASS"
echo "[0490m] validated=0490l_nonregression,direct_device_plan_handoff,type_filtered_materialize_apply,long_multispecies_resampling,fast_mass_closure_diagnostics"
echo "[0490m] RUN_ROOT=$RUN_ROOT"

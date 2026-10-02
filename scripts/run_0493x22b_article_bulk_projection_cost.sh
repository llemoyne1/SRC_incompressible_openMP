#!/usr/bin/env bash
# 0493x22b — JCP Section 3.6 bulk-liquid particle/field projection timing.
# No source/physics modification. Same state/seed/binary for A0 and A1.

ROOT="${ROOT:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)" || exit 2
cd "$ROOT" || exit 2

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
EXPECTED_BIN_SHA="${EXPECTED_BIN_SHA:-422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc}"
GEN="${GEN:-scripts/generate_0493w1_src_fluid_calibrator_states.py}"
ANALYZER="${ANALYZER:-scripts/analyze_0493x22b_bulk_projection_cost.py}"
ROOTOUT="${ROOTOUT:-runs/0493x22b_article_bulk_projection_cost}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
RESTART="${RESTART:-1}"

NX="${NX:-256}"; NY="${NY:-256}"
H="${H:-0.00390625}"; LX="${LX:-1.0}"; LY="${LY:-1.0}"
GAMMA="${GAMMA:-8}"
KBT="${KBT:-0.125}"; MASS="${MASS:-1.0}"
DT="${DT:-0.0063471328149122585}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
SEED="${SEED:-4933301}"
THREADS="${THREADS:-8}"
WARMUP_STEPS="${WARMUP_STEPS:-100}"
TIMING_STEPS="${TIMING_STEPS:-1500}"
TIMING_REPS="${TIMING_REPS:-5}"

fail(){ echo "[0493x22b] ERROR: $*" >&2; exit 2; }
truthy(){ case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON) return 0;; *) return 1;; esac; }

[[ -x "$BIN" ]] || fail "binary not executable: $BIN"
[[ -f "$GEN" ]] || fail "missing generator: $GEN"
[[ -f "$ANALYZER" ]] || fail "missing analyzer: $ANALYZER"
for c in python3 sha256sum awk sed grep; do command -v "$c" >/dev/null 2>&1 || fail "missing command: $c"; done
ACTUAL_SHA="$(sha256sum "$BIN" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "$EXPECTED_BIN_SHA" ]] || fail "binary SHA mismatch actual=$ACTUAL_SHA expected=$EXPECTED_BIN_SHA"
[[ "$NX" == 256 && "$NY" == 256 && "$GAMMA" == 8 ]] || fail "article benchmark defaults require NX=NY=256 GAMMA=8"
[[ "$TIMING_REPS" == 5 ]] || fail "article benchmark requires TIMING_REPS=5"

mkdir -p "$ROOTOUT"/{init,params,logs,outputs,analysis}
STATE="$ROOTOUT/init/bulk_nominal_seed${SEED}.smpcd"
TIMING_CSV="$ROOTOUT/timing_bulk_raw.csv"
GPU_CSV="$ROOTOUT/gpu_state_bulk.csv"

if [[ ! -s "$STATE" ]]; then
  python3 "$GEN" --case msd --output "$STATE" --Lx "$LX" --Ly "$LY" --Nx "$NX" --Ny "$NY" \
    --gamma "$GAMMA" --dt "$DT" --kBT "$KBT" --mass "$MASS" --seed "$SEED" >/dev/null || fail "state generation failed"
fi

# Runtime gates copied from the qualified 0493w1 standalone path. Diagnostics,
# LiveVis, recording and resampling are explicitly disabled for timing purity.
export OMP_NUM_THREADS="$THREADS" OMP_DYNAMIC=false OMP_PLACES=cores OMP_PROC_BIND=close
export LIVE_PROGRESS=0 SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 SRC_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_LIVE_VIS_HOLD_ON_EXIT=0
export MPCD_FILTERED_FIELD_RECORDING_0432=0
export MPCD_CUDA_STREAMING_PERIODIC_0245=1 MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1 MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0
export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0 MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0 MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0 MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1=0
export MPCD_CUDA_INACTIVE_TAIL_POOL_0313=1 MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1 MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
export MPCD_CUDA_RESAMPLING_PRODUCTION_STRIP_0484=0 MPCD_CUDA_RESAMPLING_DIAG_CSV_0484=0 MPCD_CUDA_RESAMPLING_FULL_GATE_0484=0
export MPCD_CUDA_RESAMPLING_REMAP_CELL_COUNT_DIAG_0484=0 MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0 MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=0
export MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461=0 MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=0 MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=0
export MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=0 MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474=0 MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=0
export MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A=0 MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B=0 MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=0
export MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=0 MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_EVERY_0453=1 MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=0 MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=0
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=0 MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=0 MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0 MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0 MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE=0 MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298=0 MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=0

sample_gpu(){
  stage="$1"
  command -v nvidia-smi >/dev/null 2>&1 || return 0
  if [[ ! -s "$GPU_CSV" ]]; then
    echo 'stage,timestamp,name,driver_version,pstate,temperature_gpu,power_draw_w,clocks_sm_mhz,utilization_gpu_pct,memory_used_mib' > "$GPU_CSV"
  fi
  line="$(nvidia-smi --query-gpu=timestamp,name,driver_version,pstate,temperature.gpu,power.draw,clocks.sm,utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null | head -n1)"
  [[ -n "$line" ]] && printf '%s,%s\n' "$stage" "$line" >> "$GPU_CSV"
}

set_runtime_variant(){
  variant="$1"
  if [[ "$variant" == A0 ]]; then
    export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=0 MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=0 MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404=0 MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=0
    export MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=0 MPCD_CUDA_Q6_RESIDENT_0400=0 MPCD_CUDA_Q6_RESIDENT_STRICT_0400=0
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1
    export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=0 MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0 MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=0 MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=0
    export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0 MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=0 MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=0 MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0 MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=0
  else
    export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1 MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=0 MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404=0 MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=0
    export MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=1 MPCD_CUDA_Q6_RESIDENT_0400=1 MPCD_CUDA_Q6_RESIDENT_STRICT_0400=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=0
    export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1 MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0 MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1 MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
    export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0 MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G=0 MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0 MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=0
    export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=0 MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=0 MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0 MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1 MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  fi
}

write_params(){
  variant="$1" steps="$2" tag="$3" p="$4" outdir="$5"
  mkdir -p "$outdir"
  if [[ "$variant" == A0 ]]; then srcclassic=true; proj=false; pmcorr=true; else srcclassic=false; proj=true; pmcorr=false; fi
  cat > "$p" <<EOF
inputState = $STATE
outputDir = $outdir
Lx = $LX
Ly = $LY
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $steps
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = false
taylorGreenForcingEnable = false
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
srcClassicCudaModeEnable = $srcclassic
projectionEnable = $proj
projectionBackend = cuda
projectionOperator = auto_fv_cg
projectionMaxIterations = 2500
projectionTolerance = 1.0e-5
projectionMomentumCorrectionEnable = $pmcorr
q6ProjectionStrength = 1.0
resamplingEnable = false
cudaResamplingChiFilterEnable = false
cudaResamplingEmptyRefillEnable = false
speciesResamplingMassClosureEnable = false
speciesResamplingPopulationGuardEnable = false
speciesResamplingTransferEnable = false
rotationAngle = $ROTATION_ANGLE
randomRotationSign = true
gridShiftEnable = true
rngSeed = $SEED
thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = $KBT
thermostatMinParticles = 3
kBT = $KBT
summaryEvery = $steps
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
initialInactiveSlots = 0
numThreads = $THREADS
EOF
  if [[ "$variant" == A0 ]]; then
    cat >> "$p" <<EOF
speciesRegistryEnable = false
speciesQ6Enable = false
EOF
  else
    cat >> "$p" <<EOF
q6ForceProjectionMode = prestream_single_fused
virialDensityKickEnable = false
kVirial = 0.0
betaEOS = 0.0
virialMomentumCorrectionEnable = false
q6DensityRelaxationBeta = 0.0
q6DensityRelaxationTime = 0.25
q6DensityRelaxationCompressionGateEnable = true
q6DensityRelaxationCompressionThresholdFill = 0.375
q6DensityRelaxationTractionThresholdFill = 0.75
q6DensityRelaxationTractionGain = 1.0
speciesRegistryEnable = true
speciesCount = 1
species0 = 0 q6_g_f_liquid liquid 1.0 1.0 8
species0ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = 0.10
EOF
  fi
}

validate_params(){
  p="$1" variant="$2" steps="$3"
  python3 - "$p" "$variant" "$steps" <<'PY'
import sys
p,v,steps=sys.argv[1:]; d={}
for raw in open(p):
    s=raw.strip()
    if not s or s.startswith('#') or '=' not in s: continue
    k,val=map(str.strip,s.split('=',1))
    if k in d: raise SystemExit(f'duplicate key {k}')
    d[k]=val
req={'Nx':'256','Ny':'256','dt':'0.0063471328149122585','nSteps':steps,'bcX':'periodic','bcY':'periodic','resamplingEnable':'false','kBT':'0.125','rngSeed':'4933301','dumpStateEvery':'0'}
for k,x in req.items():
    if d.get(k)!=x: raise SystemExit(f'bad {k}={d.get(k)} expected {x}')
if v=='A0':
    exp={'srcClassicCudaModeEnable':'true','projectionEnable':'false','speciesRegistryEnable':'false','speciesQ6Enable':'false'}
else:
    exp={'srcClassicCudaModeEnable':'false','projectionEnable':'true','projectionMomentumCorrectionEnable':'false','speciesRegistryEnable':'true','speciesQ6Enable':'true','speciesQ6Mode':'free_surface_masked','q6ForceProjectionMode':'prestream_single_fused'}
for k,x in exp.items():
    if d.get(k)!=x: raise SystemExit(f'bad {k}={d.get(k)} expected {x}')
print(f'[0493x22b] params audit PASS variant={v} steps={steps}')
PY
}

# Pre-create both measured parameter templates and verify the contract.
for v in A0 A1; do
  set_runtime_variant "$v"
  p="$ROOTOUT/params/${v}_template.kv"
  write_params "$v" "$TIMING_STEPS" template "$p" "$ROOTOUT/outputs/template_${v}"
  validate_params "$p" "$v" "$TIMING_STEPS" || exit 2
done

cat > "$ROOTOUT/benchmark_contract.txt" <<EOF
campaign=0493x22b_article_bulk_projection_cost
binary=$BIN
binarySha256=$ACTUAL_SHA
state=$STATE
grid=${NX}x${NY}
gamma=$GAMMA
alphaDeg=120
lambdaMeanOverH=0.72
ell=0.5744768837780632
h=$H
dt=$DT
kBT=$KBT
particleMass=$MASS
seed=$SEED
warmupSteps=$WARMUP_STEPS
measuredSteps=$TIMING_STEPS
pairs=$TIMING_REPS
A0=underlying SRC
A1=SRC + liquid particle/field projection
liveVis=OFF
recording=OFF
dumps=OFF
EOF

if truthy "$PREFLIGHT_ONLY"; then
  echo "[0493x22b] PREFLIGHT PASS"
  cat "$ROOTOUT/benchmark_contract.txt"
  exit 0
fi

# Start a fresh timing table unless RESTART and a complete result already exists.
if truthy "$RESTART" && [[ -s "$ROOTOUT/analysis/timing_bulk_summary.json" ]]; then
  echo "[0493x22b] complete analysis already exists; RESTART=1 -> no rerun"
  cat "$ROOTOUT/analysis/timing_bulk_summary.txt"
  exit 0
fi
rm -f "$TIMING_CSV" "$GPU_CSV"
echo 'variant,rep,order,steps,elapsed,user,sys,seconds_per_step,time_file' > "$TIMING_CSV"

run_solver(){
  variant="$1" rep="$2" order="$3" steps="$4" kind="$5"
  set_runtime_variant "$variant"
  tag="${kind}_${variant,,}_r${rep}"
  p="$ROOTOUT/params/${tag}.kv"; outdir="$ROOTOUT/outputs/${tag}"; log="$ROOTOUT/logs/${tag}.log"; tf="$ROOTOUT/logs/${tag}.time"
  rm -rf "$outdir"; mkdir -p "$outdir"
  write_params "$variant" "$steps" "$tag" "$p" "$outdir"
  validate_params "$p" "$variant" "$steps" || return 2
  sample_gpu "pre_${variant,,}_r${rep}"
  echo "[0493x22b] START kind=$kind variant=$variant rep=$rep order=$order steps=$steps"
  if [[ -x /usr/bin/time ]]; then
    /usr/bin/time -o "$tf" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$p" >"$log" 2>&1
    rc=$?
  else
    t0="$(python3 -c 'import time; print(time.time())')"
    "$BIN" "$p" >"$log" 2>&1; rc=$?
    t1="$(python3 -c 'import time; print(time.time())')"
    python3 - "$t0" "$t1" "$tf" <<'PY'
import sys
open(sys.argv[3],'w').write(f'elapsed={float(sys.argv[2])-float(sys.argv[1]):.9f} user=NA sys=NA\n')
PY
  fi
  [[ $rc -eq 0 ]] || { echo "[0493x22b] solver failed rc=$rc log=$log" >&2; return $rc; }
  sample_gpu "post_${variant,,}_r${rep}"
  if [[ "$kind" == measured ]]; then
    line="$(cat "$tf")"
    elapsed="$(printf '%s\n' "$line" | sed -n 's/.*elapsed=\([^ ]*\).*/\1/p')"
    user="$(printf '%s\n' "$line" | sed -n 's/.*user=\([^ ]*\).*/\1/p')"
    sysv="$(printf '%s\n' "$line" | sed -n 's/.*sys=\([^ ]*\).*/\1/p')"
    [[ -n "$elapsed" ]] || return 2
    sps="$(awk -v e="$elapsed" -v n="$steps" 'BEGIN{printf "%.17g",e/n}')"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$variant" "$rep" "$order" "$steps" "$elapsed" "$user" "$sysv" "$sps" "$tf" >> "$TIMING_CSV"
    echo "[0493x22b] DONE variant=$variant rep=$rep s/step=$sps"
  fi
  return 0
}

# Identical excluded warm-up for each path.
run_solver A0 0 0 "$WARMUP_STEPS" warmup || exit $?
run_solver A1 0 0 "$WARMUP_STEPS" warmup || exit $?

rep=1
while [[ $rep -le $TIMING_REPS ]]; do
  if (( rep % 2 == 1 )); then
    run_solver A0 "$rep" 1 "$TIMING_STEPS" measured || exit $?
    run_solver A1 "$rep" 2 "$TIMING_STEPS" measured || exit $?
  else
    run_solver A1 "$rep" 1 "$TIMING_STEPS" measured || exit $?
    run_solver A0 "$rep" 2 "$TIMING_STEPS" measured || exit $?
  fi
  rep=$((rep+1))
done

python3 "$ANALYZER" "$TIMING_CSV" "$GPU_CSV" "$ROOTOUT/analysis" || exit $?
sha256sum "$BIN" > "$ROOTOUT/binary.sha256"
echo "[0493x22b] COMPLETE root=$ROOTOUT"

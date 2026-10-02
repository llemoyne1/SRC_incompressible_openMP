#!/usr/bin/env bash
# 0493x22i — short very-large-grid scaling extension of x22g/x22h.
# Diagnostic-only. Frozen article binary; no solver/source/physics modification.
set -euo pipefail
ROOT="${ROOT:-$PWD}"; ROOT="$(cd "$ROOT" && pwd)"; cd "$ROOT"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
EXPECTED_BIN_SHA="${EXPECTED_BIN_SHA:-422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc}"
GEN="${GEN:-scripts/generate_0493x22i_large_homogeneous_state.py}"
ANALYZER="${ANALYZER:-scripts/analyze_0493x22i_large_grid_scaling.py}"
ROOTOUT="${ROOTOUT:-runs/0493x22i_large_grid_scaling}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
GRID_SIZES="${GRID_SIZES:-512 1024 2048}"
GAMMA="${GAMMA:-20}"
H="${H:-0.00390625}"
KBT="${KBT:-0.125}"
MASS="${MASS:-1.0}"
DT="${DT:-0.0063471328149122585}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
SEED="${SEED:-4933501}"
THREADS="${THREADS:-8}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-5000}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
CHUNK_CELLS="${CHUNK_CELLS:-8192}"
KEEP_STATES="${KEEP_STATES:-0}"
# Intentionally short; profile timing, not process elapsed, is the primary metric.
STEPS_512="${STEPS_512:-96}"
STEPS_1024="${STEPS_1024:-32}"
STEPS_2048="${STEPS_2048:-12}"

fail(){ echo "[0493x22i] ERROR: $*" >&2; exit 2; }
[[ -x "$BIN" ]] || fail "binary missing: $BIN"
[[ -f "$GEN" ]] || fail "large-state generator missing: $GEN"
[[ -f "$ANALYZER" ]] || fail "analyzer missing: $ANALYZER"
python3 -c 'import numpy' >/dev/null 2>&1 || fail "numpy is required by the memory-bounded large-state generator"
sha="$(sha256sum "$BIN" | awk '{print $1}')"
[[ "$sha" == "$EXPECTED_BIN_SHA" ]] || fail "binary SHA mismatch $sha"
mkdir -p "$ROOTOUT"/{init,params,logs,outputs,analysis}

steps_for_grid(){
  case "$1" in
    512) echo "$STEPS_512" ;;
    1024) echo "$STEPS_1024" ;;
    2048) echo "$STEPS_2048" ;;
    *) python3 - "$1" <<'PY'
import sys
n=int(sys.argv[1])
# Fallback keeps approximate N^2 work budget relative to 512^2, with >=6 steps.
print(max(6, int(round(96.0*(512.0/n)**2))))
PY
       ;;
  esac
}

state_bytes(){ python3 - "$1" "$GAMMA" <<'PY'
import sys
n=int(sys.argv[1]); g=int(sys.argv[2]); np=n*n*g
print(120 + 45*np)
PY
}

print_resource_preflight(){
  local n="$1"; local b np
  b="$(state_bytes "$n")"; np=$((n*n*GAMMA))
  python3 - "$n" "$np" "$b" "$ROOTOUT" <<'PY'
import shutil,sys
n=int(sys.argv[1]); np=int(sys.argv[2]); b=int(sys.argv[3]); root=sys.argv[4]
du=shutil.disk_usage(root)
print(f"[0493x22i] resource N={n} Np={np} state={b/2**30:.3f}GiB disk_free={du.free/2**30:.2f}GiB")
if du.free < int(1.25*b):
    raise SystemExit(f"[0493x22i] insufficient disk headroom for N={n}: need >=1.25x state size")
PY
  if command -v nvidia-smi >/dev/null 2>&1; then
    local gm
    gm="$(nvidia-smi --query-gpu=memory.total,memory.free --format=csv,noheader,nounits 2>/dev/null | head -1 || true)"
    [[ -z "$gm" ]] || echo "[0493x22i] gpu_memory_MiB total,free=$gm (informational; actual Q6 workspace is allocated by the solver)"
  fi
}

export OMP_NUM_THREADS=$THREADS OMP_DYNAMIC=false OMP_PLACES=cores OMP_PROC_BIND=close
export LIVE_PROGRESS=0 SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 SRC_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_FILTERED_FIELD_RECORDING_0432=0
# Profiles ON intentionally: for these short huge-state runs they isolate timestep
# cost from multi-GB state read/startup/final-summary overhead. Chrono timers do not
# add CUDA synchronizations themselves (same x22h diagnostic mechanism).
export MPCD_INTERNAL_PROFILES=1 MPCD_CUDA_RESIDENT_PROFILE_0266=0
export MPCD_CUDA_STREAMING_PERIODIC_0245=1 MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1 MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0 MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0 MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0 MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0 MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0 MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1=0
export MPCD_CUDA_INACTIVE_TAIL_POOL_0313=1 MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1 MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1 MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
for x in MPCD_CUDA_RESAMPLING_PRODUCTION_STRIP_0484 MPCD_CUDA_RESAMPLING_DIAG_CSV_0484 MPCD_CUDA_RESAMPLING_FULL_GATE_0484 MPCD_CUDA_RESAMPLING_REMAP_CELL_COUNT_DIAG_0484 MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448 MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455 MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461 MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471 MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472 MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473 MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474 MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475 MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458 MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453 MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450 MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451 MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295 MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304 MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296 MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319 MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297 MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298 MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307; do export "$x=0"; done

clear_q6(){
  export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=0 MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=0 MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404=0 MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=0
  export MPCD_CUDA_Q6_RESIDENT_0400=0 MPCD_CUDA_Q6_RESIDENT_STRICT_0400=0 MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1
  export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=0 MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0 MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=0 MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=0 MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0 MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=0 MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=0 MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0 MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=0
  export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=0 MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
}
set_variant(){
  local v="$1"; clear_q6
  case "$v" in
    SRC_PROD) ;;
    Q6GF_PROD_X7J)
      export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1 MPCD_CUDA_Q6_RESIDENT_0400=1 MPCD_CUDA_Q6_RESIDENT_STRICT_0400=1 MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=1
      export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=0
      export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1 MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1 MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1 MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1
      export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1 MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
      ;;
    *) fail "unknown variant $v" ;;
  esac
}

state_path(){ echo "$ROOTOUT/init/g${GAMMA}_${1}x${1}_seed${SEED}_large.smpcd"; }
prepare_state(){
  local n="$1"; local lx state expected actual
  lx="$(python3 - <<PY
print(float('$H')*int('$n'))
PY
)"
  state="$(state_path "$n")"; expected="$(state_bytes "$n")"
  if [[ -s "$state" ]]; then
    actual="$(stat -c '%s' "$state")"
    if [[ "$actual" == "$expected" ]]; then echo "[0493x22i] reuse state N=$n path=$state"; return; fi
    rm -f "$state"
  fi
  python3 "$GEN" --output "$state" --Lx "$lx" --Ly "$lx" --Nx "$n" --Ny "$n" --gamma "$GAMMA" --kBT "$KBT" --mass "$MASS" --seed "$SEED" --chunk-cells "$CHUNK_CELLS"
}

write_params(){
  local n="$1" v="$2" out="$3" p="$4" nsteps="$5"; local classic=true proj=false lx state comp traction
  [[ "$v" == SRC_PROD ]] || { classic=false; proj=true; }
  lx="$(python3 - <<PY
print(float('$H')*int('$n'))
PY
)"
  state="$(state_path "$n")"
  cat > "$p" <<EOF2
inputState = $state
outputDir = $out
Lx = $lx
Ly = $lx
Nx = $n
Ny = $n
dt = $DT
nSteps = $nsteps
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
srcClassicCudaModeEnable = $classic
projectionEnable = $proj
projectionBackend = cuda
projectionOperator = auto_fv_cg
projectionMaxIterations = $PROJECTION_MAX_ITERATIONS
projectionTolerance = $PROJECTION_TOLERANCE
projectionMomentumCorrectionEnable = false
q6ProjectionStrength = 1.0
resamplingEnable = false
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
summaryEvery = $nsteps
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
initialInactiveSlots = 0
numThreads = $THREADS
EOF2
  if [[ "$v" == Q6GF_PROD_X7J ]]; then
    comp="$(python3 - <<PY
print(3.0/float('$GAMMA'))
PY
)"; traction="$(python3 - <<PY
print(6.0/float('$GAMMA'))
PY
)"
    cat >> "$p" <<EOF2
q6ForceProjectionMode = prestream_single_fused
virialDensityKickEnable = false
kVirial = 0.0
betaEOS = 0.0
virialMomentumCorrectionEnable = false
q6DensityRelaxationBeta = 0.0
q6DensityRelaxationTime = 0.25
q6DensityRelaxationCompressionGateEnable = true
q6DensityRelaxationCompressionThresholdFill = $comp
q6DensityRelaxationTractionThresholdFill = $traction
q6DensityRelaxationTractionGain = 1.0
speciesRegistryEnable = true
speciesCount = 1
species0 = 0 q6_g_f_liquid liquid 1.0 1.0 $GAMMA
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
EOF2
  else
    cat >> "$p" <<EOF2
speciesRegistryEnable = false
speciesQ6Enable = false
EOF2
  fi
}

validate_params(){
  python3 - "$1" "$2" "$3" "$GAMMA" <<'PY'
import sys
p,v,n,g=sys.argv[1:]; d={}
for raw in open(p):
    s=raw.strip()
    if not s or s.startswith('#') or '=' not in s: continue
    k,val=map(str.strip,s.split('=',1))
    if k in d: raise SystemExit('duplicate key '+k)
    d[k]=val
assert int(d['Nx'])==int(n) and int(d['Ny'])==int(n)
assert d['bcX']=='periodic' and d['bcY']=='periodic'
assert d['projectionTolerance']=='1.0e-5'
if v=='SRC_PROD':
    assert d['srcClassicCudaModeEnable']=='true' and d['projectionEnable']=='false'
else:
    assert d['srcClassicCudaModeEnable']=='false' and d['projectionEnable']=='true'
    assert d['speciesQ6Mode']=='free_surface_masked'
    assert d['q6ForceProjectionMode']=='prestream_single_fused'
    assert d['species0'].split()[-1] == g
print(f'[0493x22i] params PASS N={n} {v}')
PY
}

# Preflight is deliberately light: NO multi-GB state generation.
for n in $GRID_SIZES; do
  ns="$(steps_for_grid "$n")"; print_resource_preflight "$n"
  for v in SRC_PROD Q6GF_PROD_X7J; do
    set_variant "$v"
    out="$ROOTOUT/outputs/template_N${n}_${v}"; p="$ROOTOUT/params/template_N${n}_${v}.kv"
    mkdir -p "$out"; write_params "$n" "$v" "$out" "$p" "$ns"; validate_params "$p" "$v" "$n"
  done
  echo "[0493x22i] preflight N=$n cells=$((n*n)) Np=$((n*n*GAMMA)) steps=$ns gamma=$GAMMA h=$H maxIter=$PROJECTION_MAX_ITERATIONS tol=$PROJECTION_TOLERANCE profiles=ON Q6GF=x7j/0407off"
done
if [[ "$PREFLIGHT_ONLY" == 1 ]]; then echo '[0493x22i] PREFLIGHT PASS (no large states generated)'; exit 0; fi

STATUS="$ROOTOUT/analysis/run_status.csv"
echo 'N,variant,status,exit_code,steps' > "$STATUS"
for n in $GRID_SIZES; do
  ns="$(steps_for_grid "$n")"
  prepare_state "$n"
  # Alternate pair order across sizes to reduce monotonic temperature/order bias.
  if (( (n/512) % 2 == 1 )); then seq='SRC_PROD Q6GF_PROD_X7J'; else seq='Q6GF_PROD_X7J SRC_PROD'; fi
  for v in $seq; do
    set_variant "$v"
    out="$ROOTOUT/outputs/N${n}_${v}"; p="$ROOTOUT/params/N${n}_${v}.kv"; log="$ROOTOUT/logs/N${n}_${v}.log"; tf="$ROOTOUT/logs/N${n}_${v}.time"
    rm -rf "$out"; mkdir -p "$out"; write_params "$n" "$v" "$out" "$p" "$ns"; validate_params "$p" "$v" "$n" >/dev/null
    echo "[0493x22i] RUN N=$n variant=$v steps=$ns"
    set +e
    /usr/bin/time -o "$tf" -f '%e' "$BIN" "$p" >"$log" 2>&1
    rc=$?
    set -e
    if (( rc == 0 )); then
      echo "$n,$v,PASS,$rc,$ns" >> "$STATUS"
      echo "[0493x22i] PASS N=$n variant=$v process_elapsed=$(cat "$tf")s"
    else
      echo "$n,$v,FAIL,$rc,$ns" >> "$STATUS"
      echo "[0493x22i] FAIL N=$n variant=$v rc=$rc see=$log" >&2
      # Preserve completed smaller grids and continue to the analyzer.
      break
    fi
  done
  if [[ "$KEEP_STATES" != 1 ]]; then
    rm -f "$(state_path "$n")"
    echo "[0493x22i] removed large state N=$n (KEEP_STATES=0)"
  fi
  # Stop after an incomplete pair; larger grids are unlikely to recover.
  if ! grep -q "^$n,SRC_PROD,PASS" "$STATUS" || ! grep -q "^$n,Q6GF_PROD_X7J,PASS" "$STATUS"; then
    echo "[0493x22i] stopping after incomplete pair N=$n; completed smaller grids are retained" >&2
    break
  fi
done

python3 "$ANALYZER" "$ROOTOUT" "$ROOTOUT/analysis/large_grid_scaling_summary.txt" "$ROOTOUT/analysis/large_grid_scaling.csv"
echo "[0493x22i] DONE summary=$ROOTOUT/analysis/large_grid_scaling_summary.txt"

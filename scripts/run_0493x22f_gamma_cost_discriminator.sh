#!/usr/bin/env bash
# 0493x22f — diagnostic-only gamma dependence of current production Q6-G-F cost.
# Frozen binary, no source/physics modification, no internal profiling during primary timings.
set -euo pipefail
ROOT="${ROOT:-$PWD}"; ROOT="$(cd "$ROOT" && pwd)"; cd "$ROOT"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
EXPECTED_BIN_SHA="${EXPECTED_BIN_SHA:-422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc}"
GEN="${GEN:-scripts/generate_0493w1_src_fluid_calibrator_states.py}"
ANALYZER="${ANALYZER:-scripts/analyze_0493x22f_gamma_cost_discriminator.py}"
ROOTOUT="${ROOTOUT:-runs/0493x22f_gamma_cost_discriminator}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
STEPS="${STEPS:-800}"
REPS="${REPS:-3}"
NX=128; NY=128; LX=0.5; LY=0.5
KBT=0.125; MASS=1.0; DT=0.0063471328149122585
ROTATION_ANGLE=2.0943951023931953
SEED=4933301; THREADS=8
PROJECTION_MAX_ITERATIONS=800; PROJECTION_TOLERANCE=1.0e-5
GAMMAS="${GAMMAS:-8 20}"
fail(){ echo "[0493x22f] ERROR: $*" >&2; exit 2; }
[[ -x "$BIN" ]] || fail "binary missing: $BIN"
[[ -f "$GEN" ]] || fail "generator missing: $GEN"
[[ -f "$ANALYZER" ]] || fail "analyzer missing: $ANALYZER"
sha="$(sha256sum "$BIN"|awk '{print $1}')"; [[ "$sha" == "$EXPECTED_BIN_SHA" ]] || fail "binary SHA mismatch $sha"
mkdir -p "$ROOTOUT"/{init,params,logs,outputs,analysis}

export OMP_NUM_THREADS=$THREADS OMP_DYNAMIC=false OMP_PLACES=cores OMP_PROC_BIND=close
export LIVE_PROGRESS=0 SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 SRC_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_FILTERED_FIELD_RECORDING_0432=0
# Critical: primary wall timing is unprofiled.
export MPCD_INTERNAL_PROFILES=0 MPCD_CUDA_RESIDENT_PROFILE_0266=0
export MPCD_CUDA_STREAMING_PERIODIC_0245=1 MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1 MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0 MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0 MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0 MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0 MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0 MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1=0
export MPCD_CUDA_INACTIVE_TAIL_POOL_0313=1 MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1 MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1 MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
# No resampling.
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
state_for_gamma(){
  local g="$1"; STATE="$ROOTOUT/init/g${g}_128x128_seed${SEED}.smpcd"
  if [[ ! -s "$STATE" ]]; then
    python3 "$GEN" --case msd --output "$STATE" --Lx "$LX" --Ly "$LY" --Nx "$NX" --Ny "$NY" --gamma "$g" --dt "$DT" --kBT "$KBT" --mass "$MASS" --seed "$SEED" >/dev/null || fail "state generation gamma=$g"
  fi
}
write_params(){
  local g="$1" v="$2" out="$3" p="$4"; local classic=true proj=false
  [[ "$v" == SRC_PROD ]] || { classic=false; proj=true; }
  cat > "$p" <<EOF2
inputState = $STATE
outputDir = $out
Lx = $LX
Ly = $LY
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
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
summaryEvery = $STEPS
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
initialInactiveSlots = 0
numThreads = $THREADS
EOF2
  if [[ "$v" == Q6GF_PROD_X7J ]]; then
    local comp traction
    comp="$(python3 - <<PY
print(3.0/float($g))
PY
)"
    traction="$(python3 - <<PY
print(6.0/float($g))
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
species0 = 0 q6_g_f_liquid liquid 1.0 1.0 $g
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
validate(){
 python3 - "$1" "$2" "$3" <<'PY'
import sys
p,v,g=sys.argv[1:]; d={}
for raw in open(p):
 s=raw.strip()
 if not s or s.startswith('#') or '=' not in s: continue
 k,val=map(str.strip,s.split('=',1))
 if k in d: raise SystemExit('duplicate key '+k)
 d[k]=val
if v=='SRC_PROD':
 assert d['srcClassicCudaModeEnable']=='true' and d['projectionEnable']=='false'
else:
 assert d['srcClassicCudaModeEnable']=='false' and d['projectionEnable']=='true'
 assert d['speciesQ6Mode']=='free_surface_masked'
 assert d['q6ForceProjectionMode']=='prestream_single_fused'
 assert d['species0'].split()[-1]==g
print('[0493x22f] params PASS gamma='+g+' '+v)
PY
}

for g in $GAMMAS; do
  state_for_gamma "$g"
  for v in SRC_PROD Q6GF_PROD_X7J; do
    set_variant "$v"; out="$ROOTOUT/outputs/template_g${g}_${v}"; p="$ROOTOUT/params/template_g${g}_${v}.kv"; mkdir -p "$out"; write_params "$g" "$v" "$out" "$p"; validate "$p" "$v" "$g"
  done
  echo "[0493x22f] preflight gamma=$g particles_nominal=$((NX*NY*g)) grid=${NX}x${NY} Q6GF=x7j/0407off profiles=OFF"
done
if [[ "$PREFLIGHT_ONLY" == 1 ]]; then echo '[0493x22f] PREFLIGHT PASS'; exit 0; fi

CSV="$ROOTOUT/timing_gamma_raw.csv"
echo 'gamma,pair,order,variant,steps,elapsed_s,seconds_per_step' > "$CSV"
for g in $GAMMAS; do
  state_for_gamma "$g"
  for ((r=1;r<=REPS;r++)); do
    if (( r % 2 == 1 )); then order='SRC-Q6GF'; seq='SRC_PROD Q6GF_PROD_X7J'; else order='Q6GF-SRC'; seq='Q6GF_PROD_X7J SRC_PROD'; fi
    for v in $seq; do
      set_variant "$v"
      out="$ROOTOUT/outputs/g${g}_pair${r}_${v}"; p="$ROOTOUT/params/g${g}_pair${r}_${v}.kv"; log="$ROOTOUT/logs/g${g}_pair${r}_${v}.log"; tf="$ROOTOUT/logs/g${g}_pair${r}_${v}.time"
      rm -rf "$out"; mkdir -p "$out"; write_params "$g" "$v" "$out" "$p"; validate "$p" "$v" "$g" >/dev/null
      /usr/bin/time -o "$tf" -f '%e' "$BIN" "$p" >"$log" 2>&1 || { echo "[0493x22f] FAIL gamma=$g pair=$r v=$v; see $log" >&2; exit 2; }
      e="$(cat "$tf")"; sps="$(python3 - <<PY
print(float('$e')/float('$STEPS'))
PY
)"
      echo "$g,$r,$order,$v,$STEPS,$e,$sps" >> "$CSV"
      echo "[0493x22f] gamma=$g pair=$r $v elapsed=$e s s/step=$sps"
    done
  done
done
python3 "$ANALYZER" "$CSV" "$ROOTOUT/analysis/gamma_cost_summary.txt" "$ROOTOUT/analysis/gamma_cost_pairs.csv"
echo "[0493x22f] DONE summary=$ROOTOUT/analysis/gamma_cost_summary.txt"

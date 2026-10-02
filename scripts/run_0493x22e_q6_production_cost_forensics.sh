#!/usr/bin/env bash
# 0493x22e: performance forensics using ONLY the explicit production Q6 profiles.
# No source/physics modification; no rebuild.
set -euo pipefail

ROOT="${ROOT:-$PWD}"; ROOT="$(cd "$ROOT" && pwd)"; cd "$ROOT"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
EXPECTED_BIN_SHA="${EXPECTED_BIN_SHA:-422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc}"
GEN="${GEN:-scripts/generate_0493w1_src_fluid_calibrator_states.py}"
ANALYZER="${ANALYZER:-scripts/analyze_0493x22e_q6_production_cost_forensics.py}"
ROOTOUT="${ROOTOUT:-runs/0493x22e_q6_production_cost_forensics}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
STEPS="${STEPS:-400}"
GAMMA=8; KBT=0.125; MASS=1.0
DT=0.0063471328149122585
ROTATION_ANGLE=2.0943951023931953
SEED=4933301; THREADS=8
PROJECTION_MAX_ITERATIONS=800
PROJECTION_TOLERANCE=1.0e-5

fail(){ echo "[0493x22e] ERROR: $*" >&2; exit 2; }
[[ -x "$BIN" ]] || fail "binary missing: $BIN"
[[ -f "$GEN" ]] || fail "generator missing: $GEN"
[[ -f "$ANALYZER" ]] || fail "analyzer missing: $ANALYZER"
sha="$(sha256sum "$BIN"|awk '{print $1}')"; [[ "$sha" == "$EXPECTED_BIN_SHA" ]] || fail "binary SHA mismatch $sha"
mkdir -p "$ROOTOUT"/{init,params,logs,outputs,analysis}

export OMP_NUM_THREADS=$THREADS OMP_DYNAMIC=false OMP_PLACES=cores OMP_PROC_BIND=close
export LIVE_PROGRESS=0 SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 SRC_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_FILTERED_FIELD_RECORDING_0432=0
export MPCD_INTERNAL_PROFILES=1 MPCD_CUDA_RESIDENT_PROFILE_0266=0
export MPCD_CUDA_STREAMING_PERIODIC_0245=1 MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1 MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0 MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0 MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0 MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0 MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0 MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1=0
export MPCD_CUDA_INACTIVE_TAIL_POOL_0313=1 MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1 MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1 MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_MAX_CELLS_0407=65536
# No resampling in this diagnostic.
for x in MPCD_CUDA_RESAMPLING_PRODUCTION_STRIP_0484 MPCD_CUDA_RESAMPLING_DIAG_CSV_0484 MPCD_CUDA_RESAMPLING_FULL_GATE_0484 MPCD_CUDA_RESAMPLING_REMAP_CELL_COUNT_DIAG_0484 MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448 MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455 MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461 MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471 MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472 MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473 MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474 MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475 MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458 MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453 MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450 MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451 MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295 MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304 MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296 MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319 MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297 MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298 MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307; do export "$x=0"; done

set_grid(){
  local g="$1"
  case "$g" in
    G128) NX=128; NY=128; LX=0.5; LY=0.5 ;;
    G256) NX=256; NY=256; LX=1.0; LY=1.0 ;;
    *) fail "unknown grid $g" ;;
  esac
  STATE="$ROOTOUT/init/${g}_nominal_seed${SEED}.smpcd"
  if [[ ! -s "$STATE" ]]; then
    python3 "$GEN" --case msd --output "$STATE" --Lx "$LX" --Ly "$LY" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --dt "$DT" --kBT "$KBT" --mass "$MASS" --seed "$SEED" >/dev/null || fail "state generation failed $g"
  fi
}

clear_q6_flags(){
  export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=0 MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=0 MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404=0 MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=0
  export MPCD_CUDA_Q6_RESIDENT_0400=0 MPCD_CUDA_Q6_RESIDENT_STRICT_0400=0 MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1
  export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=0 MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0 MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=0 MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=0 MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0 MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=0 MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=0 MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0 MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=0
  export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=0 MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
}

set_variant(){
  local v="$1"; clear_q6_flags
  case "$v" in
    SRC_PROD)
      ;;
    Q6_PROD_0407)
      # Exact x7r/x14 historical-Q6 production policy for <=65536 cells.
      export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1 MPCD_CUDA_Q6_RESIDENT_0400=1 MPCD_CUDA_Q6_RESIDENT_STRICT_0400=1 MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=1
      export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=0
      export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=0
      export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=1
      ;;
    Q6GF_PROD_X7J)
      # Exact x7r/x14 current-Q6-G-F production policy.
      export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1 MPCD_CUDA_Q6_RESIDENT_0400=1 MPCD_CUDA_Q6_RESIDENT_STRICT_0400=1 MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=1
      export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=0
      export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1 MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1 MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1 MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1
      export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
      export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
      ;;
    *) fail "unknown variant $v" ;;
  esac
}

write_params(){
  local v="$1" out="$2" p="$3"; local classic=true proj=false pm=true
  [[ "$v" == SRC_PROD ]] || { classic=false; proj=true; }
  [[ "$v" == Q6GF_PROD_X7J ]] && pm=false
  cat > "$p" <<EOF
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
projectionMomentumCorrectionEnable = $pm
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
EOF
  if [[ "$v" == Q6GF_PROD_X7J ]]; then
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
  else
    cat >> "$p" <<EOF
speciesRegistryEnable = false
speciesQ6Enable = false
EOF
  fi
}

validate(){
 python3 - "$1" "$2" <<'PY'
import sys
p,v=sys.argv[1:]; d={}
for raw in open(p):
 s=raw.strip()
 if not s or s.startswith('#') or '=' not in s: continue
 k,val=map(str.strip,s.split('=',1))
 if k in d: raise SystemExit('duplicate key '+k)
 d[k]=val
if v=='SRC_PROD': assert d['srcClassicCudaModeEnable']=='true' and d['projectionEnable']=='false'
else: assert d['srcClassicCudaModeEnable']=='false' and d['projectionEnable']=='true'
if v=='Q6GF_PROD_X7J': assert d.get('speciesQ6Mode')=='free_surface_masked' and d.get('q6ForceProjectionMode')=='prestream_single_fused'
else: assert d.get('speciesQ6Enable')=='false'
print('[0493x22e] params PASS',v)
PY
}

grids="G128 G256"
variants="SRC_PROD Q6_PROD_0407 Q6GF_PROD_X7J"
for g in $grids; do
  set_grid "$g"
  for v in $variants; do
    set_variant "$v"; out="$ROOTOUT/outputs/${g}_${v}"; p="$ROOTOUT/params/${g}_${v}.kv"; mkdir -p "$out"; write_params "$v" "$out" "$p"; validate "$p" "$v" || exit 2
    case "$v" in
      SRC_PROD) profile="classic SRC" ;;
      Q6_PROD_0407) profile="legacy Q6 production: 0407=1 x7j=0" ;;
      Q6GF_PROD_X7J) profile="current Q6-G-F production: 0407=0 x7j=1" ;;
    esac
    echo "[0493x22e] preflight grid=$g cells=$((NX*NY)) h=$(python3 - <<PY
print($LX/$NX)
PY
) variant=$v profile=$profile"
  done
done
if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[0493x22e] PREFLIGHT PASS"
  exit 0
fi

CSV="$ROOTOUT/forensic_wall.csv"; echo 'grid,variant,nx,ny,cells,steps,elapsed_s' > "$CSV"
for g in $grids; do
  set_grid "$g"
  for v in $variants; do
    set_variant "$v"; out="$ROOTOUT/outputs/${g}_${v}"; p="$ROOTOUT/params/${g}_${v}.kv"; log="$ROOTOUT/logs/${g}_${v}.log"; tf="$ROOTOUT/logs/${g}_${v}.time"
    rm -rf "$out"; mkdir -p "$out"; write_params "$v" "$out" "$p"; validate "$p" "$v" >/dev/null
    /usr/bin/time -o "$tf" -f '%e' "$BIN" "$p" >"$log" 2>&1 || { echo "[0493x22e] FAIL $g $v; see $log" >&2; exit 2; }
    e="$(cat "$tf")"; echo "$g,$v,$NX,$NY,$((NX*NY)),$STEPS,$e" >> "$CSV"; echo "[0493x22e] $g $v elapsed=$e s"
  done
done
python3 "$ANALYZER" "$ROOTOUT" || exit 2
echo "[0493x22e] DONE summary=$ROOTOUT/analysis/q6_production_cost_forensics_summary.txt"

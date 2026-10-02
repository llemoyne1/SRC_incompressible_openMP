#!/usr/bin/env bash
# Diagnostic only: identify why x22b reported a 3.7x cost.
# A0 = historical SRC path
# A1 = historical plain src-q6 path (projection only; no Q6-G-F free-surface machinery)
# A2 = reproduce the invalid x22b A1 architecture for attribution.

ROOT="${ROOT:-$PWD}"; ROOT="$(cd "$ROOT" && pwd)" || exit 2; cd "$ROOT" || exit 2
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
EXPECTED_BIN_SHA="${EXPECTED_BIN_SHA:-422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc}"
GEN="${GEN:-scripts/generate_0493w1_src_fluid_calibrator_states.py}"
ANALYZER="${ANALYZER:-scripts/analyze_0493x22b_fix1_path_diagnostic.py}"
ROOTOUT="${ROOTOUT:-runs/0493x22b_fix1_path_diagnostic}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
NX=256; NY=256; LX=1.0; LY=1.0; GAMMA=8; KBT=0.125; MASS=1.0
DT=0.0063471328149122585; ROTATION_ANGLE=2.0943951023931953; SEED=4933301; THREADS=8
WARMUP_STEPS="${WARMUP_STEPS:-50}"; TIMING_STEPS="${TIMING_STEPS:-500}"
fail(){ echo "[0493x22b-fix1] ERROR: $*" >&2; exit 2; }
[[ -x "$BIN" ]] || fail "binary missing"; [[ -f "$GEN" ]] || fail "generator missing"; [[ -f "$ANALYZER" ]] || fail "analyzer missing"
sha="$(sha256sum "$BIN"|awk '{print $1}')"; [[ "$sha" == "$EXPECTED_BIN_SHA" ]] || fail "binary SHA mismatch $sha"
mkdir -p "$ROOTOUT"/{init,params,logs,outputs,analysis}
STATE="$ROOTOUT/init/bulk_nominal_seed${SEED}.smpcd"
if [[ ! -s "$STATE" ]]; then
 python3 "$GEN" --case msd --output "$STATE" --Lx "$LX" --Ly "$LY" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --dt "$DT" --kBT "$KBT" --mass "$MASS" --seed "$SEED" >/dev/null || fail "state generation failed"
fi

# Common CUDA base for all three variants.
export OMP_NUM_THREADS=$THREADS OMP_DYNAMIC=false OMP_PLACES=cores OMP_PROC_BIND=close
export LIVE_PROGRESS=0 SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 SRC_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_FILTERED_FIELD_RECORDING_0432=0
export MPCD_CUDA_STREAMING_PERIODIC_0245=1 MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1 MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0 MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0 MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0 MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0 MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0 MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1=0
export MPCD_CUDA_INACTIVE_TAIL_POOL_0313=1 MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1 MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1 MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
# Everything resampling-related OFF.
for v in MPCD_CUDA_RESAMPLING_PRODUCTION_STRIP_0484 MPCD_CUDA_RESAMPLING_DIAG_CSV_0484 MPCD_CUDA_RESAMPLING_FULL_GATE_0484 MPCD_CUDA_RESAMPLING_REMAP_CELL_COUNT_DIAG_0484 MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448 MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455 MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461 MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471 MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472 MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473 MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474 MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475 MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458 MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453 MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450 MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451 MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295 MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304 MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296 MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319 MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297 MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298 MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307; do export "$v=0"; done

set_variant(){
  local v="$1"
  # clear all path-specific gates first
  export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=0 MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=0 MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404=0 MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=0
  export MPCD_CUDA_Q6_RESIDENT_0400=0 MPCD_CUDA_Q6_RESIDENT_STRICT_0400=0 MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1
  export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=0 MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0 MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=0 MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=0 MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0 MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=0 MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=0 MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0 MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=0
  export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=0 MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  if [[ "$v" != A0_SRC ]]; then
    export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1 MPCD_CUDA_Q6_RESIDENT_0400=1 MPCD_CUDA_Q6_RESIDENT_STRICT_0400=1 MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=0
  fi
  if [[ "$v" == A2_OLD_X22B_Q6GF ]]; then
    export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1 MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1 MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1 MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1 MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
  fi
}

write_params(){
 local v="$1" steps="$2" p="$3" out="$4"; mkdir -p "$out"
 local classic=true proj=false pm=true
 [[ "$v" == A0_SRC ]] || { classic=false; proj=true; }
 [[ "$v" == A2_OLD_X22B_Q6GF ]] && pm=false
 cat > "$p" <<EOF
inputState = $STATE
outputDir = $out
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
srcClassicCudaModeEnable = $classic
projectionEnable = $proj
projectionBackend = cuda
projectionOperator = auto_fv_cg
projectionMaxIterations = 2500
projectionTolerance = 1.0e-5
projectionMomentumCorrectionEnable = $pm
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
 if [[ "$v" == A1_SRC_Q6 ]]; then
   # Historical plain src-q6: no species registry and no free-surface geometry.
   cat >> "$p" <<EOF
speciesRegistryEnable = false
speciesQ6Enable = false
EOF
 elif [[ "$v" == A0_SRC ]]; then
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

validate(){ python3 - "$1" "$2" <<'PY'
import sys
p,v=sys.argv[1:]; d={}
for raw in open(p):
 s=raw.strip()
 if not s or s.startswith('#') or '=' not in s: continue
 k,val=map(str.strip,s.split('=',1))
 if k in d: raise SystemExit('duplicate '+k)
 d[k]=val
if v=='A0_SRC':
 assert d['srcClassicCudaModeEnable']=='true' and d['projectionEnable']=='false'
elif v=='A1_SRC_Q6':
 assert d['srcClassicCudaModeEnable']=='false' and d['projectionEnable']=='true'
 assert d.get('speciesRegistryEnable')=='false' and d.get('speciesQ6Enable')=='false'
 for bad in ('speciesQ6Mode','q6ForceProjectionMode','q6DensityRelaxationTime'):
  assert bad not in d, f'unexpected {bad}'
else:
 assert d.get('speciesQ6Mode')=='free_surface_masked' and d.get('q6ForceProjectionMode')=='prestream_single_fused'
print('[0493x22b-fix1] params PASS',v)
PY
}

# templates + explicit diff artifact
for v in A0_SRC A1_SRC_Q6 A2_OLD_X22B_Q6GF; do set_variant "$v"; write_params "$v" "$TIMING_STEPS" "$ROOTOUT/params/${v}.kv" "$ROOTOUT/outputs/template_${v}"; validate "$ROOTOUT/params/${v}.kv" "$v" || exit 2; done
python3 - "$ROOTOUT/params/A0_SRC.kv" "$ROOTOUT/params/A1_SRC_Q6.kv" "$ROOTOUT/analysis/A0_vs_A1_param_diff.txt" <<'PY'
import sys
def rd(p):
 d={}
 for x in open(p):
  s=x.strip()
  if s and not s.startswith('#') and '=' in s:
   k,v=map(str.strip,s.split('=',1)); d[k]=v
 return d
a,b=rd(sys.argv[1]),rd(sys.argv[2]); ks=sorted(set(a)|set(b))
with open(sys.argv[3],'w') as f:
 for k in ks:
  if a.get(k)!=b.get(k): f.write(f'{k}: A0={a.get(k)} | A1={b.get(k)}\n')
PY
if [[ "$PREFLIGHT_ONLY" == 1 ]]; then echo '[0493x22b-fix1] PREFLIGHT PASS'; cat "$ROOTOUT/analysis/A0_vs_A1_param_diff.txt"; exit 0; fi

CSV="$ROOTOUT/path_diagnostic_raw.csv"; echo 'variant,rep,order,steps,elapsed,seconds_per_step' > "$CSV"
run_one(){
 local v="$1" rep="$2" ord="$3" steps="$4" kind="$5"; set_variant "$v"; local p="$ROOTOUT/params/${kind}_${v}_r${rep}.kv" out="$ROOTOUT/outputs/${kind}_${v}_r${rep}" log="$ROOTOUT/logs/${kind}_${v}_r${rep}.log" tf="$ROOTOUT/logs/${kind}_${v}_r${rep}.time"; rm -rf "$out"; mkdir -p "$out"; write_params "$v" "$steps" "$p" "$out"; validate "$p" "$v" >/dev/null || return 2; /usr/bin/time -o "$tf" -f '%e' "$BIN" "$p" >"$log" 2>&1 || return $?; local e="$(cat "$tf")"; if [[ "$kind" == measured ]]; then local sps="$(awk -v e="$e" -v n="$steps" 'BEGIN{printf "%.17g",e/n}')"; echo "$v,$rep,$ord,$steps,$e,$sps" >> "$CSV"; echo "[0493x22b-fix1] $v rep=$rep s/step=$sps"; fi
}
# short excluded warm-up each path
for v in A0_SRC A1_SRC_Q6 A2_OLD_X22B_Q6GF; do run_one "$v" 0 0 "$WARMUP_STEPS" warmup || exit $?; done
# balanced two repetitions
run_one A0_SRC 1 1 "$TIMING_STEPS" measured || exit $?
run_one A1_SRC_Q6 1 2 "$TIMING_STEPS" measured || exit $?
run_one A2_OLD_X22B_Q6GF 1 3 "$TIMING_STEPS" measured || exit $?
run_one A2_OLD_X22B_Q6GF 2 1 "$TIMING_STEPS" measured || exit $?
run_one A1_SRC_Q6 2 2 "$TIMING_STEPS" measured || exit $?
run_one A0_SRC 2 3 "$TIMING_STEPS" measured || exit $?
python3 "$ANALYZER" "$CSV" "$ROOTOUT/analysis" || exit $?

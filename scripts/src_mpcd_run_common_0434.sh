#!/usr/bin/env bash
# Common helpers for homogeneous SRC/MPCD CUDA run scripts, 0434c.
# Source this file from scripts/run_0434_*.sh.  It centralizes:
#   - INTEG_PATH selection: src | src-resampling | src-q6 | src-q6-resampling
#   - CUDA resident/Q6/resampling flags
#   - gamma-relative resampling thresholds
#   - livevis + 0433a WYSIWYR filtered recording controls
#   - autonomous initial-state / chi generation.

set -euo pipefail

suite_truthy_0434() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac
}

suite_path_has_q6_0434() {
  case "${1:-src}" in src-q6|q6|src-q6-resampling|q6-resampling) return 0 ;; *) return 1 ;; esac
}

suite_path_has_resampling_0434() {
  case "${1:-src}" in src-resampling|resampling|src-q6-resampling|q6-resampling) return 0 ;; *) return 1 ;; esac
}

suite_validate_path_0434() {
  case "${1:-src}" in
    src|classic|src-resampling|resampling|src-q6|q6|src-q6-resampling|q6-resampling) return 0 ;;
    *) echo "[0434-suite] ERROR unsupported INTEG_PATH/RUN_MODE=$1" >&2; exit 2 ;;
  esac
}

suite_bool_kv_0434() { if suite_truthy_0434 "${1:-0}"; then printf true; else printf false; fi; }
suite_path_src_classic_kv_0434() { if suite_path_has_q6_0434 "${1:-src}"; then printf false; else printf true; fi; }
suite_path_projection_kv_0434() { if suite_path_has_q6_0434 "${1:-src}"; then printf true; else printf false; fi; }
suite_path_resampling_kv_0434() { if suite_path_has_resampling_0434 "${1:-src}"; then printf true; else printf false; fi; }

suite_int_round_0434() {
  python3 - "$1" <<'PY'
import math, sys
print(int(math.floor(float(sys.argv[1]) + 0.5)))
PY
}

suite_int_ceil_0434() {
  python3 - "$1" <<'PY'
import math, sys
print(int(math.ceil(float(sys.argv[1]))))
PY
}

suite_compute_derived_0434() {
  RESAMPLING_NMIN_COEF="${RESAMPLING_NMIN_COEF:-0.40}"
  RESAMPLING_NMAX_COEF="${RESAMPLING_NMAX_COEF:-0.60}"
  GUARD_NMIN="${GUARD_NMIN:-$(python3 - <<PY
import math
print(max(1, int(math.ceil(float(${GAMMA})*(1.0-float(${RESAMPLING_NMIN_COEF}))))))
PY
)}"
  GUARD_NTARGET="${GUARD_NTARGET:-${GAMMA}}"
  GUARD_NMAX="${GUARD_NMAX:-$(python3 - <<PY
import math
print(max(1, int(math.ceil(float(${GAMMA})*(1.0+float(${RESAMPLING_NMAX_COEF}))))))
PY
)}"
  EMPTY_REFILL_GAMMA="${EMPTY_REFILL_GAMMA:-${GAMMA}}"
  EMPTY_REFILL_REFERENCE="${EMPTY_REFILL_REFERENCE:-gamma}"
  EMPTY_REFILL_TARGET_FRACTION="${EMPTY_REFILL_TARGET_FRACTION:-0.10}"
  EMPTY_REFILL_MEMORY_MAX_AGE="${EMPTY_REFILL_MEMORY_MAX_AGE:-1000}"
  INACTIVE_SLOTS="${INACTIVE_SLOTS:-$(python3 - <<PY
import math
print(int(math.ceil(float(${NX})*float(${NY})*float(${INACTIVE_SLOTS_CELL_FRACTION:-0.25}))))
PY
)}"
}

suite_root_cd_0434() {
  ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)}"
  cd "$ROOT"
  GENERATOR_0434="${GENERATOR_0434:-scripts/src_mpcd_case_generator_0434.py}"
  if [[ ! -f "$GENERATOR_0434" ]]; then
    echo "[0434-suite] ERROR missing generator: $GENERATOR_0434" >&2
    exit 127
  fi
}

suite_mode_list_0434() {
  if [[ -n "${RUN_MODES:-}" ]]; then
    printf '%s\n' $RUN_MODES
  elif [[ -n "${INTEG_PATH:-${SRC_INTEG_PATH:-}}" ]]; then
    printf '%s\n' "${INTEG_PATH:-${SRC_INTEG_PATH:-src}}"
  else
    printf '%s\n' src src-resampling src-q6 src-q6-resampling
  fi
}

suite_prepare_dirs_0434() {
  local run_root=$1
  if suite_truthy_0434 "${CLEAN_RUN_ROOT:-1}"; then rm -rf "$run_root"; fi
  mkdir -p "$run_root/init" "$run_root/chi" "$run_root/params" "$run_root/logs" "$run_root/output" "$run_root/analysis"
}

suite_ensure_binary_0434() {
  BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0477}"
  FORCE_BUILD="${FORCE_BUILD:-0}"
  AUTO_BUILD="${AUTO_BUILD:-1}"
  BUILD_IF_STALE="${BUILD_IF_STALE:-1}"
  local needs=0
  if suite_truthy_0434 "$FORCE_BUILD" || [[ ! -x "$BIN" ]]; then
    needs=1
  elif suite_truthy_0434 "$BUILD_IF_STALE"; then
    if find src include scripts/build_src_mpcd_cuda_q6_resident_0400.sh scripts/build_src_mpcd_cuda_0315b.sh -type f -newer "$BIN" -print -quit 2>/dev/null | grep -q .; then
      needs=1
    fi
  fi
  if [[ "$needs" == 1 ]]; then
    if ! suite_truthy_0434 "$AUTO_BUILD"; then
      echo "[0434-suite] ERROR missing/stale binary and AUTO_BUILD=0: $BIN" >&2
      exit 127
    fi
    local helper=""
    for h in scripts/build_src_mpcd_cuda_q6_resident_0400.sh scripts/build_src_mpcd_cuda_0315b.sh; do
      [[ -f "$h" ]] && { helper="$h"; break; }
    done
    [[ -n "$helper" ]] || { echo "[0434-suite] ERROR no build helper found" >&2; exit 127; }
    echo "[0434-suite] build $BIN using $helper"
    MPCD_ENABLE_LIVE_VIS="${MPCD_ENABLE_LIVE_VIS:-1}" OUT="$BIN" bash "$helper"
  fi
  [[ -x "$BIN" ]] || { echo "[0434-suite] ERROR binary not executable: $BIN" >&2; exit 127; }
}

suite_clear_cuda_flags_0434() {
  export MPCD_CUDA_STREAMING_PERIODIC_0245=0
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
  export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0
  export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=0
  export MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=0
  export MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404=0
  export MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=0
}

suite_export_cuda_flags_0434() {
  local mode=$1 topology=$2
  suite_clear_cuda_flags_0434

  export MPCD_CUDA_INACTIVE_TAIL_POOL_0313="${MPCD_CUDA_INACTIVE_TAIL_POOL_0313:-1}"
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE="${MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE:-1}"
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE="${MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE:-1}"
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE="${MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT="${MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="${MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT="${MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT:-1}"

  case "$topology" in
    periodic)
      export MPCD_CUDA_STREAMING_PERIODIC_0245=1
      export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
      if suite_path_has_q6_0434 "$mode"; then export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1; fi
      ;;
    wall)
      export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
      export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=1
      export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
      if suite_path_has_q6_0434 "$mode"; then export MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=1; fi
      ;;
    io_fullface)
      export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
      export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=1
      if suite_path_has_q6_0434 "$mode"; then export MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404=1; fi
      ;;
    segmented)
      export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
      export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
      export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=1
      if suite_path_has_q6_0434 "$mode"; then export MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=1; fi
      ;;
    *) echo "[0434-suite] ERROR unsupported topology=$topology" >&2; exit 2 ;;
  esac

  if suite_path_has_q6_0434 "$mode"; then
    export MPCD_CUDA_Q6_RESIDENT_0400=1
    export MPCD_CUDA_Q6_RESIDENT_STRICT_0400="${Q6_STRICT:-1}"
    export MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=0
  else
    export MPCD_CUDA_Q6_RESIDENT_0400=0
    export MPCD_CUDA_Q6_RESIDENT_STRICT_0400=0
    export MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=0
  fi

  if suite_path_has_resampling_0434 "$mode"; then
    # Validated 0471-0477 resident chain. These are backend-routing controls,
    # not physical parameters. Unsupported physics keeps its solver fallback.
    export MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1
    export MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=1
    export MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461=1
    export MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_GATE_EVERY_0461="${RESIDENT_GATE_EVERY:-${SUMMARY_EVERY:-100}}"
    export MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1
    export MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1
    export MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1
    export MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474=1
    export MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=1
    export MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A=1
    export MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B=1
    export MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=1
    export MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1
    export MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1
    export MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450="${RESIDENT_GATE_EVERY:-${SUMMARY_EVERY:-100}}"
    export MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_EVERY_0451="${RESIDENT_GATE_EVERY:-${SUMMARY_EVERY:-100}}"
    export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295="${RESAMPLING_SURVEY_ENABLE:-1}"
    export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="${RESAMPLING_SURVEY_EVERY:-${SUMMARY_EVERY:-100}}"
    export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304="${RESAMPLING_ADAPTIVE_FLAG_ENABLE:-1}"
    export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY="${FLAG_EVERY:-50}"
    export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN="$GUARD_NMIN"
    export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY=1
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296="${MASS_RECONDITION_ENABLE:-1}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY="${MASS_RECONDITION_EVERY:-${GUARD_EVERY:-5}}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH="${MASS_RECONDITION_STRENGTH:-1.0}"
    export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=1
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="${GUARD_EVERY:-5}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="$GUARD_NMIN"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="$GUARD_NTARGET"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="$GUARD_NMAX"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION="${GUARD_SPLIT_FRACTION:-0.5}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="${BOUNDARY_AWARE:-1}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS="${OPEN_BOUNDARY_HALO_CELLS:-1}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS="${BOUNDARY_HALO_CELLS:-0}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS="${SOLID_HALO_CELLS:-0}"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="${RESTORE_ENABLE:-1}"
    export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1
    export MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1
    export MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307="${SPLIT_DONOR_MIN_MASS:-0.5}"
    export MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307="${SPLIT_NEW_PARTICLE_MIN_MASS:-0.25}"
  else
    export MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0
    export MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=0
    export MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461=0
    export MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=0
    export MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=0
    export MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=0
    export MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474=0
    export MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=0
    export MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A=0
    export MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B=0
    export MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=0
    export MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=0
    export MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=0
    export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=0
    export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=0
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
    export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE=0
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298=0
    export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=0
  fi
}

suite_prepare_livevis_control_0434() {
  local run_root=$1 mode=$2
  LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}"
  mkdir -p "$(dirname "$LIVE_VIS_CONTROL_FILE")"
  if [[ ! -f "$LIVE_VIS_CONTROL_FILE" || "${OVERWRITE_LIVEVIS_CONTROL:-1}" == 1 ]]; then
    cat > "$LIVE_VIS_CONTROL_FILE" <<CONTROL
# 0434b livevis + filtered recorder runtime controls.
# 0433a WYSIWYR: if recordEvery is absent or <=0, recording follows liveEvery.
field = ${LIVE_VIS_FIELD}
colormap = ${LIVE_VIS_COLORMAP}
clip = ${LIVE_VIS_CLIP}
gain = ${LIVE_VIS_GAIN}
smoothPasses = ${LIVE_VIS_SMOOTH_PASSES}
liveGridNx = ${LIVE_VIS_NX}
liveGridNy = ${LIVE_VIS_NY}
liveEvery = ${LIVE_VIS_EVERY}
filterMode = ${FILTER_MODE}
filterTau = ${FILTER_TAU}
filterSampleEvery = ${FILTER_SAMPLE_EVERY}
recordEnable = ${RECORD_ENABLE}
recordSession = ${RECORD_SESSION_PREFIX}_${mode}
recordFields = ${RECORD_FIELDS}
recordFormat = ${RECORD_FORMAT}
recordStride = ${RECORD_STRIDE}
CONTROL
    if [[ -n "${RECORD_EVERY:-}" ]]; then echo "recordEvery = ${RECORD_EVERY}" >> "$LIVE_VIS_CONTROL_FILE"; fi
  fi
  echo "[0434-livevis] control=$LIVE_VIS_CONTROL_FILE"
}

suite_export_livevis_0434() {
  export SRC_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
  export MPCD_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
  export SRC_LIVE_VIS_FIELD="$LIVE_VIS_FIELD"
  export SRC_LIVE_VIS_EVERY="$LIVE_VIS_EVERY"
  export SRC_LIVE_VIS_NX="$LIVE_VIS_NX"
  export SRC_LIVE_VIS_NY="$LIVE_VIS_NY"
  export SRC_LIVE_VIS_CLIP="$LIVE_VIS_CLIP"
  export SRC_LIVE_VIS_GAIN="$LIVE_VIS_GAIN"
  export SRC_LIVE_VIS_SMOOTH_PASSES="$LIVE_VIS_SMOOTH_PASSES"
  export SRC_LIVE_VIS_COLORMAP="$LIVE_VIS_COLORMAP"
  export SRC_LIVE_VIS_WINDOW_SCALE="$LIVE_VIS_WINDOW_SCALE"
  export SRC_LIVE_VIS_VSYNC="$LIVE_VIS_VSYNC"
  export SRC_LIVE_VIS_CUDA_FIELD="$LIVE_VIS_CUDA_FIELD"
  export SRC_LIVE_VIS_CUDA_SNAPSHOT="$LIVE_VIS_CUDA_SNAPSHOT"
  export SRC_LIVE_VIS_LOG_SOURCE="$LIVE_VIS_LOG_SOURCE"
  export SRC_LIVE_VIS_CONTROL_FILE="$LIVE_VIS_CONTROL_FILE"
  export SRC_LIVE_VIS_CONTROL_EVERY="$LIVE_VIS_CONTROL_EVERY"
  export SRC_LIVE_VIS_CONTROL_LOG="$LIVE_VIS_CONTROL_LOG"
  export SRC_LIVE_VIS_HOLD_ON_EXIT="$LIVE_VIS_HOLD_ON_EXIT"
  export MPCD_FILTERED_FIELD_RECORDING_0432="$FILTERED_RECORDING_ENABLE"
}

suite_write_common_params_0434() {
  local mode=$1
  local path_resampling
  path_resampling="$(suite_path_resampling_kv_0434 "$mode")"
  cat <<PARAMS
srcClassicCudaModeEnable = $(suite_path_src_classic_kv_0434 "$mode")
projectionEnable = $(suite_path_projection_kv_0434 "$mode")
projectionBackend = ${PROJECTION_BACKEND}
projectionOperator = ${PROJECTION_OPERATOR}
projectionMaxIterations = ${PROJECTION_MAX_ITERATIONS}
projectionTolerance = ${PROJECTION_TOLERANCE}
projectionMomentumCorrectionEnable = ${PROJECTION_MOMENTUM_CORRECTION_ENABLE}
q6ProjectionStrength = ${Q6_PROJECTION_STRENGTH}
resamplingEnable = ${WEIGHTED_RESAMPLING_ENABLE_OVERRIDE:-$path_resampling}
cudaResamplingChiFilterEnable = ${CUDA_RESAMPLING_CHI_FILTER_ENABLE}
cudaResamplingChiMin = ${CUDA_RESAMPLING_CHI_MIN}
cudaResamplingEmptyRefillEnable = ${CUDA_EMPTY_REFILL_ENABLE_OVERRIDE:-$path_resampling}
cudaResamplingEmptyRefillReference = ${EMPTY_REFILL_REFERENCE}
cudaResamplingEmptyRefillGamma = ${EMPTY_REFILL_GAMMA}
cudaResamplingEmptyRefillTargetFraction = ${EMPTY_REFILL_TARGET_FRACTION}
cudaResamplingEmptyRefillMemoryMaxAge = ${EMPTY_REFILL_MEMORY_MAX_AGE}
resamplingPopulationNMin = ${GUARD_NMIN}
resamplingPopulationNTarget = ${GUARD_NTARGET}
resamplingPopulationNMax = ${GUARD_NMAX}
resamplingTargetCellMass = ${GAMMA}
resamplingWetMaskMode = occupied
resamplingWetCellMassThreshold = 0.0
resamplingExtractionEnable = ${RESAMPLING_EXTRACTION_ENABLE:-true}
resamplingInsertionEnable = ${RESAMPLING_INSERTION_ENABLE:-true}
resamplingRemapEnable = ${RESAMPLING_REMAP_ENABLE:-true}
resamplingThermalRenormalizationEnable = ${RESAMPLING_THERMAL_RENORMALIZATION_ENABLE:-true}
resamplingMassGuardEnable = ${RESAMPLING_MASS_GUARD_ENABLE:-true}
resamplingParticleMassMin = ${RESAMPLING_PARTICLE_MASS_MIN:-0.5}
resamplingParticleMassMax = ${RESAMPLING_PARTICLE_MASS_MAX:-2.0}
resamplingLatentActivationEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false
rotationAngle = ${ROTATION_ANGLE}
randomRotationSign = ${RANDOM_ROTATION_SIGN}
gridShiftEnable = ${GRID_SHIFT_ENABLE}
rngSeed = ${SEED}
thermostatEnable = ${THERMOSTAT_ENABLE}
thermostatMode = ${THERMOSTAT_MODE}
thermostatEvery = ${THERMOSTAT_EVERY}
thermostatTargetKBT = ${THERMOSTAT_TARGET_KBT}
thermostatMinParticles = ${THERMOSTAT_MIN_PARTICLES}
kBT = ${KBT}
summaryEvery = ${SUMMARY_EVERY}
dumpStateEvery = ${DUMP_STATE_EVERY}
summaryRoleFilter = ${SUMMARY_ROLE_FILTER}
dumpRoleFilter = ${DUMP_ROLE_FILTER}
initialInactiveSlots = ${INACTIVE_SLOTS}
numThreads = ${THREADS}
PARAMS
}

suite_write_darcy_params_0434() {
  local chi=$1
  cat <<PARAMS
darcyBrinkmanEnable = true
darcyChiMode = file
darcyChiFile = ${chi}
darcyChiNx = ${NX}
darcyChiNy = ${NY}
darcyChiFileFormat = float32
darcyAlphaMin = ${ALPHA_MIN}
darcyAlphaMax = ${ALPHA}
darcyQ = ${DARCY_Q}
darcyUSolidX = ${DARCY_USOLID_X}
darcyUSolidY = ${DARCY_USOLID_Y}
darcyCostEvery = ${DARCY_COST_EVERY}
darcyCostFilename = darcy_cost_0343.csv
darcyThreadsPerBlock = ${DARCY_THREADS_PER_BLOCK}
darcyInitialDeactivateBelowChi = ${DARCY_INITIAL_DEACTIVATE_BELOW_CHI}
darcyBrinkmanForcingMode = ${DARCY_BRINKMAN_FORCING_MODE}
darcyChiCollisionVpEnable = ${DARCY_CHI_COLLISION_VP_ENABLE}
darcyChiCollisionVpMode = ${DARCY_CHI_COLLISION_VP_MODE}
darcyChiCollisionVpGamma = ${DARCY_CHI_COLLISION_VP_GAMMA}
darcyChiCollisionVpMass = ${DARCY_CHI_COLLISION_VP_MASS}
darcyChiCollisionVpLayers = ${DARCY_CHI_COLLISION_VP_LAYERS}
darcyChiCollisionVpThreshold = ${DARCY_CHI_COLLISION_VP_THRESHOLD}
darcyChiCollisionVpStrength = ${DARCY_CHI_COLLISION_VP_STRENGTH}
topoBenchmarkEnable = ${TOPO_BENCHMARK_ENABLE}
topoBenchmarkEvery = ${TOPO_BENCHMARK_EVERY}
topoBenchmarkFilename = ${TOPO_BENCHMARK_FILENAME}
topoBenchmarkForceEnable = ${TOPO_BENCHMARK_FORCE_ENABLE}
topoBenchmarkDragLiftEnable = ${TOPO_BENCHMARK_DRAG_LIFT_ENABLE}
topoBenchmarkFlowDirX = ${TOPO_BENCHMARK_FLOW_DIR_X}
topoBenchmarkFlowDirY = ${TOPO_BENCHMARK_FLOW_DIR_Y}
topoBenchmarkLiftDirX = ${TOPO_BENCHMARK_LIFT_DIR_X}
topoBenchmarkLiftDirY = ${TOPO_BENCHMARK_LIFT_DIR_Y}
PARAMS
}

suite_generate_case_0434() {
  local state=$1 chi=${2:-}
  local chi_args=()
  [[ -n "$chi" ]] && chi_args=(--chi "$chi")
  python3 "$GENERATOR_0434" \
    --case "$GEN_CASE" --state "$state" "${chi_args[@]}" \
    --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" \
    --kBT "$KBT" --mass "$PARTICLE_MASS" --seed "$SEED" --u0 "$U0" \
    --velocity-mode "$VELOCITY_MODE" --background-type "$BACKGROUND_TYPE" \
    --inactive-type "$INACTIVE_TYPE" --inactive-slots "$INACTIVE_SLOTS" \
    --skip-solid-cells "$SKIP_SOLID_CELLS" --skip-solid-particles "$SKIP_SOLID_PARTICLES" \
    --tg-hole-enable "$TG_HOLE_ENABLE" --hole-xmin "$HOLE_XMIN" --hole-xmax "$HOLE_XMAX" --hole-ymin "$HOLE_YMIN" --hole-ymax "$HOLE_YMAX" \
    --step-xmin "$STEP_XMIN" --step-xmax "$STEP_XMAX" --step-ymin "$STEP_YMIN" --step-ymax "$STEP_YMAX" \
    --cylinder-cx "$CYLINDER_CX" --cylinder-cy "$CYLINDER_CY" --cylinder-r "$CYLINDER_R" \
    --bend-width "$BEND_WIDTH" --bend-xmid "$BEND_XMID" --bend-y-top "$BEND_Y_TOP" --bend-y-bottom "$BEND_Y_BOTTOM" \
    --naca-chord "$NACA_CHORD" --naca-cx "$NACA_CX" --naca-cy "$NACA_CY" --naca-alpha-deg "$NACA_ALPHA_DEG" --naca-thickness "$NACA_THICKNESS"
}

suite_run_binary_0434() {
  local params=$1 log=$2 time=$3 out=$4
  suite_ensure_binary_0434
  echo "[0434-suite] binary=$BIN"
  echo "[0434-suite] params=$params"
  echo "[0434-suite] output=$out"
  local rc=0
  /usr/bin/time -o "$time" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" | tee "$log" || rc=$?
  if [[ "$rc" != 0 ]]; then
    echo "[0434-suite] ERROR rc=$rc" >&2
    tail -80 "$log" >&2 || true
    return "$rc"
  fi
  echo "[0434-suite] time=$(cat "$time")"
}

suite_write_env_file_0434() {
  local file=$1 mode=$2
  mkdir -p "$(dirname "$file")"
  env | grep -E '^(MPCD_CUDA_|SRC_LIVE_VIS_|MPCD_LIVE_VIS_|MPCD_FILTERED_FIELD_RECORDING_0432=|OMP_|BIN=|INTEG_PATH=|SRC_INTEG_PATH=|RUN_MODES=|NX=|NY=|GAMMA=|U0=|UIN=|KBT=|DT=|ALPHA=|DARCY_|TOPO_)' | sort > "$file"
  cat >> "$file" <<META
mode=${mode}
GUARD_NMIN=${GUARD_NMIN}
GUARD_NTARGET=${GUARD_NTARGET}
GUARD_NMAX=${GUARD_NMAX}
RESAMPLING_NMIN_COEF=${RESAMPLING_NMIN_COEF}
RESAMPLING_NMAX_COEF=${RESAMPLING_NMAX_COEF}
INACTIVE_SLOTS=${INACTIVE_SLOTS}
LIVE_VIS_CONTROL_FILE=${LIVE_VIS_CONTROL_FILE}
META
}

suite_defaults_common_0434() {
  THREADS="${THREADS:-8}"
  export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
  export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
  export OMP_PLACES="${OMP_PLACES:-cores}"
  export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

  BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0477}"
  CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
  PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
  BACKGROUND_TYPE="${BACKGROUND_TYPE:-0}"
  INACTIVE_TYPE="${INACTIVE_TYPE:-0}"
  SKIP_SOLID_CELLS="${SKIP_SOLID_CELLS:-true}"
  SKIP_SOLID_PARTICLES="${SKIP_SOLID_PARTICLES:-true}"

  SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
  DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000000}"
  DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"
  SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"

  PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
  PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
  PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
  PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-10}"
  PROJECTION_MOMENTUM_CORRECTION_ENABLE="${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}"
  Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
  Q6_STRICT="${Q6_STRICT:-1}"

  ROTATION_ANGLE="${ROTATION_ANGLE:-1.5}"
  RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
  GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
  THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
  THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
  THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
  THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:--1.0}"
  THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

  CUDA_RESAMPLING_CHI_FILTER_ENABLE="${CUDA_RESAMPLING_CHI_FILTER_ENABLE:-false}"
  CUDA_RESAMPLING_CHI_MIN="${CUDA_RESAMPLING_CHI_MIN:-0.05}"

  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
  LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
  LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-25}"
  LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"
  LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
  LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
  LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
  LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
  LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-gray}"
  LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
  LIVE_VIS_VSYNC="${LIVE_VIS_VSYNC:-0}"
  LIVE_VIS_CUDA_FIELD="${LIVE_VIS_CUDA_FIELD:-1}"
  LIVE_VIS_CUDA_SNAPSHOT="${LIVE_VIS_CUDA_SNAPSHOT:-1}"
  LIVE_VIS_LOG_SOURCE="${LIVE_VIS_LOG_SOURCE:-0}"
  LIVE_VIS_CONTROL_EVERY="${LIVE_VIS_CONTROL_EVERY:-1}"
  LIVE_VIS_CONTROL_LOG="${LIVE_VIS_CONTROL_LOG:-0}"
  LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"

  FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
  RECORD_ENABLE="${RECORD_ENABLE:-true}"
  RECORD_SESSION_PREFIX="${RECORD_SESSION_PREFIX:-${CASE_LABEL}_0434}"
  RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
  RECORD_FORMAT="${RECORD_FORMAT:-f32}"
  RECORD_STRIDE="${RECORD_STRIDE:-1}"
  FILTER_MODE="${FILTER_MODE:-none}"
  FILTER_TAU="${FILTER_TAU:-0.0}"
  FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-1}"

  ALPHA="${ALPHA:-800000.0}"
  ALPHA_MIN="${ALPHA_MIN:-0.0}"
  DARCY_Q="${DARCY_Q:-0.1}"
  DARCY_USOLID_X="${DARCY_USOLID_X:-0.0}"
  DARCY_USOLID_Y="${DARCY_USOLID_Y:-0.0}"
  DARCY_COST_EVERY="${DARCY_COST_EVERY:-$SUMMARY_EVERY}"
  DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"
  DARCY_INITIAL_DEACTIVATE_BELOW_CHI="${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:-0.05}"
  DARCY_BRINKMAN_FORCING_MODE="${DARCY_BRINKMAN_FORCING_MODE:-mean_outward_bath}"
  DARCY_CHI_COLLISION_VP_ENABLE="${DARCY_CHI_COLLISION_VP_ENABLE:-true}"
  DARCY_CHI_COLLISION_VP_MODE="${DARCY_CHI_COLLISION_VP_MODE:-interface_band}"
  DARCY_CHI_COLLISION_VP_GAMMA="${DARCY_CHI_COLLISION_VP_GAMMA:--1}"
  DARCY_CHI_COLLISION_VP_MASS="${DARCY_CHI_COLLISION_VP_MASS:-1.0}"
  DARCY_CHI_COLLISION_VP_LAYERS="${DARCY_CHI_COLLISION_VP_LAYERS:-1}"
  DARCY_CHI_COLLISION_VP_THRESHOLD="${DARCY_CHI_COLLISION_VP_THRESHOLD:-0.5}"
  DARCY_CHI_COLLISION_VP_STRENGTH="${DARCY_CHI_COLLISION_VP_STRENGTH:-0.25}"
  TOPO_BENCHMARK_ENABLE="${TOPO_BENCHMARK_ENABLE:-true}"
  TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-$DARCY_COST_EVERY}"
  TOPO_BENCHMARK_FILENAME="${TOPO_BENCHMARK_FILENAME:-topo_benchmark_0348.csv}"
  TOPO_BENCHMARK_FORCE_ENABLE="${TOPO_BENCHMARK_FORCE_ENABLE:-true}"
  TOPO_BENCHMARK_DRAG_LIFT_ENABLE="${TOPO_BENCHMARK_DRAG_LIFT_ENABLE:-true}"
  TOPO_BENCHMARK_FLOW_DIR_X="${TOPO_BENCHMARK_FLOW_DIR_X:-1.0}"
  TOPO_BENCHMARK_FLOW_DIR_Y="${TOPO_BENCHMARK_FLOW_DIR_Y:-0.0}"
  TOPO_BENCHMARK_LIFT_DIR_X="${TOPO_BENCHMARK_LIFT_DIR_X:-0.0}"
  TOPO_BENCHMARK_LIFT_DIR_Y="${TOPO_BENCHMARK_LIFT_DIR_Y:-1.0}"

  TG_HOLE_ENABLE="${TG_HOLE_ENABLE:-false}"
  HOLE_XMIN="${HOLE_XMIN:-0.45}"; HOLE_XMAX="${HOLE_XMAX:-0.55}"
  HOLE_YMIN="${HOLE_YMIN:-0.45}"; HOLE_YMAX="${HOLE_YMAX:-0.55}"
  STEP_XMIN="${STEP_XMIN:-0.0}"; STEP_XMAX="${STEP_XMAX:-1.0}"
  STEP_YMIN="${STEP_YMIN:-0.0}"; STEP_YMAX="${STEP_YMAX:-0.52}"
  CYLINDER_CX="${CYLINDER_CX:-1.0}"; CYLINDER_CY="${CYLINDER_CY:-0.5}"; CYLINDER_R="${CYLINDER_R:-0.08}"
  BEND_WIDTH="${BEND_WIDTH:-0.25}"; BEND_XMID="${BEND_XMID:-0.5}"; BEND_Y_TOP="${BEND_Y_TOP:-0.875}"; BEND_Y_BOTTOM="${BEND_Y_BOTTOM:-0.125}"
  NACA_CHORD="${NACA_CHORD:-0.55}"; NACA_CX="${NACA_CX:-0.5}"; NACA_CY="${NACA_CY:-0.5}"; NACA_ALPHA_DEG="${NACA_ALPHA_DEG:-5.0}"; NACA_THICKNESS="${NACA_THICKNESS:-0.12}"
}

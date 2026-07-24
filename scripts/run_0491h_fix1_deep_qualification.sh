#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
RUN_ROOT="${RUN_ROOT:-runs/0491h_fix1_deep_qualification}"
VALIDATION_PROFILE="${VALIDATION_PROFILE:-full}" # software | full
NX="${NX:-8}"
NY="${NY:-4}"
GAMMA="${GAMMA:-6}"
DT="${DT:-0.005}"
KBT="${KBT:-0.005}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_TOLERANCE="${THERMOSTAT_TOLERANCE:-1.0e-9}"
TRACE_MASS_FRACTION="${TRACE_MASS_FRACTION:-1.0e-7}"
TRACE_Q6_STRENGTH="${TRACE_Q6_STRENGTH:-4.0}"
SPECIES_Q6_COMPARISON_TOLERANCE="${SPECIES_Q6_COMPARISON_TOLERANCE:-1.0e-11}"
MASS_RELATIVE_TOLERANCE="${MASS_RELATIVE_TOLERANCE:-1.0e-12}"
INTERFACE_CONTRAST_RETENTION_MIN="${INTERFACE_CONTRAST_RETENTION_MIN:-0.95}"
WEIGHTED_OVERHEAD_MAX="${WEIGHTED_OVERHEAD_MAX:-0.25}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
GUARD_PROBE_STEPS="${GUARD_PROBE_STEPS:-2}"

case "$VALIDATION_PROFILE" in
  software)
    MATRIX_SEEDS="${MATRIX_SEEDS:-491201}"
    MATRIX_STEPS="${MATRIX_STEPS:-20}"
    EQUIVALENCE_STEPS="${EQUIVALENCE_STEPS:-20}"
    INTERFACE_STEPS="${INTERFACE_STEPS:-20}"
    TRACE_STEPS="${TRACE_STEPS:-20}"
    CLOSED_LONG_STEPS="${CLOSED_LONG_STEPS:-100}"
    STATE_EQUIVALENCE_TOLERANCE="${STATE_EQUIVALENCE_TOLERANCE:-1.0e-13}"
    ;;
  full)
    MATRIX_SEEDS="${MATRIX_SEEDS:-491201 491202 491203}"
    MATRIX_STEPS="${MATRIX_STEPS:-1000}"
    EQUIVALENCE_STEPS="${EQUIVALENCE_STEPS:-1000}"
    INTERFACE_STEPS="${INTERFACE_STEPS:-1000}"
    TRACE_STEPS="${TRACE_STEPS:-1000}"
    CLOSED_LONG_STEPS="${CLOSED_LONG_STEPS:-10000}"
    STATE_EQUIVALENCE_TOLERANCE="${STATE_EQUIVALENCE_TOLERANCE:-1.0e-9}"
    ;;
  *)
    echo "[0491h-fix1] ERROR VALIDATION_PROFILE must be software or full, got '$VALIDATION_PROFILE'" >&2
    exit 2
    ;;
esac

if (( GAMMA < 4 )); then
  echo "[0491h-fix1] ERROR GAMMA must be >=4" >&2
  exit 2
fi

if [[ "${CLEAN_RUN_ROOT:-1}" == 1 ]]; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT/logs" "$RUN_ROOT/states"
STATUS="$RUN_ROOT/stage_status_0491h_fix1.csv"
printf 'case,kind,mode,seed,expected_steps,exit_code,log,artifact_root\n' > "$STATUS"

suite_ensure_binary_0434

json_value_0491h_fix1() {
  local file=$1 key=$2
  python3 - "$file" "$key" <<'PY_JSON_0491H_FIX1'
import json, sys
obj = json.load(open(sys.argv[1]))
value = obj[sys.argv[2]]
print("" if value is None else value)
PY_JSON_0491H_FIX1
}

write_params_0491h_fix1() {
  local case_dir=$1
  local state=$2
  local mode=$3
  local steps=$4
  local seed=$5
  local q6_enable=$6
  local q6_mode=$7
  local q6_sensitivity=$8
  local species_count=$9
  local cell_diag=${10}
  local dump_final=${11}
  local strict_species_resampling=${12}
  local trace_mass=${13:-0}
  local summary_every=${14:-1}
  local params="$case_dir/params/params.kv"
  local q6_path=false
  local resampling_path=false
  local src_classic=true
  if suite_path_has_q6_0434 "$mode"; then q6_path=true; src_classic=false; fi
  if suite_path_has_resampling_0434 "$mode"; then resampling_path=true; fi
  local dump_every=0
  if [[ "$dump_final" == true ]]; then dump_every=$steps; fi

  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  cat > "$params" <<PARAMS_0491H_FIX1
inputState = $state
outputDir = $case_dir/output
Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $steps
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
srcClassicCudaModeEnable = $src_classic
projectionEnable = $q6_path
projectionBackend = cuda
projectionOperator = auto_fv_cg
projectionMaxIterations = 400
projectionTolerance = 1.0e-12
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
resamplingEnable = $resampling_path
cudaResamplingChiFilterEnable = false
cudaResamplingChiMin = 0.05
cudaResamplingEmptyRefillEnable = $resampling_path
cudaResamplingEmptyRefillReference = gamma
cudaResamplingEmptyRefillGamma = $GAMMA
cudaResamplingEmptyRefillTargetFraction = 0.10
cudaResamplingEmptyRefillMemoryMaxAge = 1000
resamplingPopulationNMin = $((GAMMA - 1))
resamplingPopulationNTarget = $GAMMA
resamplingPopulationNMax = $((GAMMA + 1))
resamplingTargetCellMass = $GAMMA
resamplingWetMaskMode = occupied
resamplingWetCellMassThreshold = 0.0
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingThermalRenormalizationEnable = false
resamplingMassGuardEnable = false
resamplingParticleMassMin = 0.10
resamplingParticleMassMax = 2.0
resamplingLatentActivationEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false
keepMeanFlowEnable = false
rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $seed
thermostatEnable = $THERMOSTAT_ENABLE
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = $KBT
thermostatMinParticles = 3
kBT = $KBT
summaryEvery = $summary_every
dumpStateEvery = $dump_every
summaryRoleFilter = fluid
dumpRoleFilter = fluid
initialInactiveSlots = 0
numThreads = 4
speciesRegistryEnable = true
speciesCount = $species_count
species0 = 1 liquid_q6 liquid 1.0 1.0 $GAMMA
species1 = 2 gas_q6 gas 0.0 1.0 $GAMMA
PARAMS_0491H_FIX1
  if [[ "$species_count" == 3 ]]; then
    cat >> "$params" <<PARAMS_0491H_FIX1_TRACE
species2 = 3 trace_q6 gas $TRACE_Q6_STRENGTH 0.0 $trace_mass
PARAMS_0491H_FIX1_TRACE
  fi
  cat >> "$params" <<PARAMS_0491H_FIX1_SPECIES
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0491h_fix1.csv
speciesCellDiagnosticsEnable = $cell_diag
speciesCellDiagnosticsFilename = species_cell_runtime_0491h_fix1.csv
speciesQ6Enable = $q6_enable
speciesQ6Mode = $q6_mode
speciesQ6Sensitivity = $q6_sensitivity
speciesQ6AlphaEpsilon = 1.0e-14
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = $SPECIES_Q6_COMPARISON_TOLERANCE
PARAMS_0491H_FIX1_SPECIES

  if [[ "$strict_species_resampling" == true ]]; then
    cat >> "$params" <<'PARAMS_0491H_FIX1_RESAMPLING'
speciesCellCudaDepositEnable = false
speciesResamplingMassClosureEnable = true
speciesResamplingMassClosureCudaEnable = true
speciesMassClosureCudaDiagnosticsFilename = cuda_species_mass_closure_0490i.csv
speciesMassClosureCudaComparisonTolerance = 1.0e-11
speciesResamplingPopulationGuardEnable = true
speciesResamplingPopulationGuardCudaEnable = true
cudaResamplingEmptyRefillSpeciesCompositionEnable = true
speciesResamplingTransferEnable = true
speciesResamplingTransferCudaEnable = true
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490k.csv
speciesTransferCudaComparisonTolerance = 1.0e-11
speciesResamplingCudaResidentValidationEnable = false
speciesResamplingCudaResidentFastPathEnable = true
speciesCudaResidentFastPathDiagnosticsFilename = cuda_species_resident_fast_path_0490m.csv
speciesResamplingCudaResidentDepositsEnable = true
speciesResamplingCudaResidentPoolEnable = true
speciesResamplingCudaResidentMaintenanceStrict = true
speciesCudaResidentMaintenanceDiagnosticsFilename = cuda_species_resident_maintenance_0490n.csv
PARAMS_0491H_FIX1_RESAMPLING
  fi
  printf '%s\n' "$params"
}

run_case_0491h_fix1() {
  local case_name=$1
  local kind=$2
  local mode=$3
  local seed=$4
  local state=$5
  local steps=$6
  local q6_enable=$7
  local q6_mode=$8
  local q6_sensitivity=$9
  local species_count=${10}
  local cell_diag=${11}
  local dump_final=${12}
  local strict_species_resampling=${13}
  local trace_mass=${14:-0}
  local summary_every=${15:-1}
  local mass_recondition_override=${16:-auto}

  local case_dir="$RUN_ROOT/$case_name"
  local log="$case_dir/logs/run.log"
  local time_file="$case_dir/logs/time.txt"
  local params
  params="$(write_params_0491h_fix1 "$case_dir" "$state" "$mode" "$steps" "$seed" \
      "$q6_enable" "$q6_mode" "$q6_sensitivity" "$species_count" "$cell_diag" \
      "$dump_final" "$strict_species_resampling" "$trace_mass" "$summary_every")"

  GUARD_NMIN=$((GAMMA - 1))
  GUARD_NTARGET=$GAMMA
  GUARD_NMAX=$((GAMMA + 1))
  GUARD_EVERY=1
  MASS_RECONDITION_EVERY=1
  if [[ "$strict_species_resampling" == true ]]; then
    if [[ "$mass_recondition_override" == auto ]]; then
      MASS_RECONDITION_ENABLE=0
    else
      MASS_RECONDITION_ENABLE="$mass_recondition_override"
    fi
  else
    MASS_RECONDITION_ENABLE=0
  fi
  SUMMARY_EVERY=$summary_every
  RESAMPLING_PRODUCTION_STRIP=1
  RESAMPLING_DIAG_CSV_ENABLE=1
  RESAMPLING_FULL_GATE_ENABLE=0
  RESAMPLING_REMAP_CELL_COUNT_DIAG_ENABLE=0
  RESAMPLING_UPSTREAM_VALIDATE_ENABLE=0
  RESAMPLING_OPERATION_MATERIALIZER_VALIDATE_ENABLE=0
  Q6_STRICT=1
  suite_export_cuda_flags_0434 "$mode" periodic
  export SRC_LIVE_VIS_ENABLE=0
  export MPCD_LIVE_VIS_ENABLE=0
  export MPCD_FILTERED_FIELD_RECORDING_0432=0
  export MPCD_DISABLED_RESAMPLING_SUMMARY_DIAGNOSTICS_0315G=0
  export MPCD_INTERNAL_PROFILES=0

  env | sort | grep -E '^(MPCD_CUDA|MPCD_DISABLED_RESAMPLING|MPCD_INTERNAL_PROFILES|SRC_LIVE_VIS|MPCD_LIVE_VIS)' \
      > "$case_dir/logs/environment.env" || true

  echo "[0491h-fix1] case=$case_name kind=$kind mode=$mode seed=$seed steps=$steps mass_recondition_0296=$MASS_RECONDITION_ENABLE thermostat=$THERMOSTAT_ENABLE"
  set +e
  /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' \
      "$BIN" "$params" 2>&1 | tee "$log"
  local rc=${PIPESTATUS[0]}
  set -e
  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$case_name" "$kind" "$mode" "$seed" "$steps" "$rc" "$log" "$case_dir" >> "$STATUS"
  if [[ "$rc" != 0 ]]; then
    echo "[0491h-fix1] FAIL case=$case_name rc=$rc"
    tail -60 "$log" || true
  fi
  return 0
}

# -----------------------------------------------------------------------------
# 1. Four-path matrix, now with the 0490p species-resident resampling path
#    explicitly enabled in SRC+resampling and SRC+resampling+Q6.
# -----------------------------------------------------------------------------
for seed in $MATRIX_SEEDS; do
  state="$RUN_ROOT/states/matrix_${seed}.smpcd"
  python3 scripts/generate_0491h_fix1_state.py \
      --output "$state" --profile imbalanced --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
      --seed "$seed" --inactive-slots $((2 * NX * NY * GAMMA))
  for mode in src src-resampling src-q6 src-q6-resampling; do
    q6_enable=false
    q6_mode=common
    q6_sensitivity=0.0
    strict_resampling=false
    if suite_path_has_q6_0434 "$mode"; then
      q6_enable=true
      q6_mode=weighted
      q6_sensitivity=1.0
    fi
    if suite_path_has_resampling_0434 "$mode"; then
      strict_resampling=true
    fi
    safe_mode="${mode//-/_}"
    run_case_0491h_fix1 "matrix_seed_${seed}_${safe_mode}" path_matrix "$mode" "$seed" \
        "$state" "$MATRIX_STEPS" "$q6_enable" "$q6_mode" "$q6_sensitivity" \
        2 false false "$strict_resampling" 0 10
  done
done

# -----------------------------------------------------------------------------
# 1b. Compatibility guard. Deliberately request legacy 0296 together with the
#     species-aware closure. The code must suppress 0296, keep 0490p active and
#     conserve every species mass.
# -----------------------------------------------------------------------------
guard_state="$RUN_ROOT/states/mass_recondition_guard.smpcd"
python3 scripts/generate_0491h_fix1_state.py \
    --output "$guard_state" --profile imbalanced --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --seed 491205 --inactive-slots $((2 * NX * NY * GAMMA))
run_case_0491h_fix1 mass_recondition_compatibility_guard compatibility_guard \
    src-resampling 491205 "$guard_state" "$GUARD_PROBE_STEPS" \
    false common 0.0 2 false false true 0 1 1

# -----------------------------------------------------------------------------
# 2. Historical Q6 versus species-Q6 common equivalence, plus an exactly paired
#    weighted run for a meaningful overhead measurement.
# -----------------------------------------------------------------------------
uniform_state="$RUN_ROOT/states/equivalence_uniform.smpcd"
python3 scripts/generate_0491h_fix1_state.py \
    --output "$uniform_state" --profile uniform --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --seed 491211 --inactive-slots 0
run_case_0491h_fix1 legacy_q6 equivalence src-q6 491211 "$uniform_state" \
    "$EQUIVALENCE_STEPS" false common 0.0 2 false true false 0 1
run_case_0491h_fix1 common_q6 equivalence src-q6 491211 "$uniform_state" \
    "$EQUIVALENCE_STEPS" true common 0.0 2 false true false 0 1
run_case_0491h_fix1 weighted_q6 paired_performance src-q6 491211 "$uniform_state" \
    "$EQUIVALENCE_STEPS" true weighted 1.0 2 false false false 0 1

# -----------------------------------------------------------------------------
# 3. Spatial interface diagnostic. Q6 flow is tangential to the initial vertical
#    interface, so loss of contrast directly exposes type/position corruption.
# -----------------------------------------------------------------------------
interface_state="$RUN_ROOT/states/interface.smpcd"
python3 scripts/generate_0491h_fix1_state.py \
    --output "$interface_state" --profile interface --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --seed 491212 --inactive-slots 0
run_case_0491h_fix1 persistent_interface spatial_interface src-q6 491212 "$interface_state" \
    "$INTERFACE_STEPS" true weighted 1.0 2 true false false 0 1

# -----------------------------------------------------------------------------
# 4. True trace species: global mass fraction <=1e-6 and nonzero, amplified Q6
#    strength. The per-cell deposit allows independent alpha-bar/weight recovery.
# -----------------------------------------------------------------------------
trace_state="$RUN_ROOT/states/trace.smpcd"
python3 scripts/generate_0491h_fix1_state.py \
    --output "$trace_state" --profile trace --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --seed 491213 --trace-mass-fraction "$TRACE_MASS_FRACTION" --inactive-slots 0
trace_mass="$(json_value_0491h_fix1 "$trace_state.json" trace_mass)"
run_case_0491h_fix1 trace_species trace_species src-q6 491213 "$trace_state" \
    "$TRACE_STEPS" true weighted 1.0 3 true false false "$trace_mass" 1

# -----------------------------------------------------------------------------
# 5. Closed 10k SRC+resampling+Q6 validation with the complete 0490p chain.
# -----------------------------------------------------------------------------
closed_state="$RUN_ROOT/states/closed_resampling_q6.smpcd"
python3 scripts/generate_0491h_fix1_state.py \
    --output "$closed_state" --profile imbalanced --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --seed 491214 --inactive-slots $((3 * NX * NY * GAMMA))
run_case_0491h_fix1 closed_long_src_resampling_q6 closed_long src-q6-resampling 491214 \
    "$closed_state" "$CLOSED_LONG_STEPS" true weighted 1.0 2 false false true 0 10

set +e
python3 scripts/summarize_0491h_fix1_deep_qualification.py \
    --root "$RUN_ROOT" \
    --status "$STATUS" \
    --profile "$VALIDATION_PROFILE" \
    --matrix-seeds "$MATRIX_SEEDS" \
    --nx "$NX" \
    --matrix-steps "$MATRIX_STEPS" \
    --equivalence-steps "$EQUIVALENCE_STEPS" \
    --interface-steps "$INTERFACE_STEPS" \
    --trace-steps "$TRACE_STEPS" \
    --closed-long-steps "$CLOSED_LONG_STEPS" \
    --guard-probe-steps "$GUARD_PROBE_STEPS" \
    --q6-tolerance "$SPECIES_Q6_COMPARISON_TOLERANCE" \
    --thermostat-enabled "$THERMOSTAT_ENABLE" \
    --thermostat-target "$KBT" \
    --thermostat-tolerance "$THERMOSTAT_TOLERANCE" \
    --state-equivalence-tolerance "$STATE_EQUIVALENCE_TOLERANCE" \
    --mass-relative-tolerance "$MASS_RELATIVE_TOLERANCE" \
    --interface-contrast-retention-min "$INTERFACE_CONTRAST_RETENTION_MIN" \
    --weighted-overhead-max "$WEIGHTED_OVERHEAD_MAX" \
    --csv "$RUN_ROOT/species_q6_deep_qualification_0491h_fix1.csv" \
    --markdown "$RUN_ROOT/species_q6_deep_qualification_0491h_fix1.md"
summary_rc=$?
set -e

echo "[0491h-fix1] audit=$RUN_ROOT/species_q6_deep_qualification_0491h_fix1.csv"
echo "[0491h-fix1] report=$RUN_ROOT/species_q6_deep_qualification_0491h_fix1.md"
exit "$summary_rc"

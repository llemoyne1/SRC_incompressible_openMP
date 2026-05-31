#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/taylor_green_forced_random_population_resampling_0130_0140}
INIT_ROOT=${INIT_ROOT:-init/taylor_green_random_population_resampling_0128}
STATE=${TG_INITIAL_STATE:-$INIT_ROOT/initial_state_tg_random_pop_0128.smpcd}
TG_NX=${TG_NX:-32}
TG_NY=${TG_NY:-32}
TG_GAMMA=${TG_GAMMA:-20}
TG_STEPS=${TG_STEPS:-1000}
TG_DT=${TG_DT:-0.001}
TG_KBT=${TG_KBT:-0.001}
TG_SEED=${TG_SEED:-1280128}
TG_SUMMARY_EVERY=${TG_SUMMARY_EVERY:-5}
TG_DUMP_EVERY=${TG_DUMP_EVERY:-100}
TG_THREADS=${TG_THREADS:-4}
TG_RESAMP_POOR_FRACTION=${TG_RESAMP_POOR_FRACTION:-0.90}
TG_RESAMP_RICH_FRACTION=${TG_RESAMP_RICH_FRACTION:-1.10}
TG_MASS_MIN=${TG_MASS_MIN:-0.5}
TG_MASS_MAX=${TG_MASS_MAX:-2.0}
TG_MASS_RENORM_PERIOD=${TG_MASS_RENORM_PERIOD:-10}
TG_FORCING_ENABLE=${TG_FORCING_ENABLE:-true}
TG_FORCING_AMPLITUDE=${TG_FORCING_AMPLITUDE:-0.02}
TG_FORCING_MODE_X=${TG_FORCING_MODE_X:-1}
TG_FORCING_MODE_Y=${TG_FORCING_MODE_Y:-1}

if [[ ! -x build/src_mpcd_base ]]; then
    ./scripts/build_src_mpcd_base.sh
fi

if [[ ! -f "$STATE" ]]; then
    cat >&2 <<MSG
Missing initial state:
  $STATE

Generate it from MATLAB before launching OpenMP. From the repository root, run:

  cd matlab

then in MATLAB:

  prepare_taylor_green_random_population_resampling_0128( ...
      'output', '../$STATE', ...
      'Nx', $TG_NX, 'Ny', $TG_NY, 'gamma', $TG_GAMMA, ...
      'populationStd', 6.0, 'populationMin', 4, 'populationMax', 36, ...
      'kBT', $TG_KBT, 'seed', $TG_SEED);

Then return to the repository root and rerun:
  $0

This 0130 launcher reuses the 0128 random-population initial state; only the C++ run is forced.
MSG
    exit 2
fi

mkdir -p "$RUN_ROOT"

write_params() {
    local label=$1
    local projection=$2
    local resampling=$3
    local out_dir="$RUN_ROOT/$label"
    local params_file="$RUN_ROOT/params_${label}.kv"
    mkdir -p "$out_dir"
    cat > "$params_file" <<PARAMS
inputState = $STATE
outputDir = $out_dir

Lx = 1.0
Ly = 1.0
Nx = $TG_NX
Ny = $TG_NY

dt = $TG_DT
nSteps = $TG_STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $TG_SEED

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = $TG_FORCING_ENABLE
taylorGreenForcingAmplitude = $TG_FORCING_AMPLITUDE
taylorGreenForcingModeX = $TG_FORCING_MODE_X
taylorGreenForcingModeY = $TG_FORCING_MODE_Y

bcX = periodic
bcY = periodic

projectionEnable = $projection
projectionOperator = periodic_fv_cg
projectionMaxIterations = 300
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $TG_KBT

summaryEvery = $TG_SUMMARY_EVERY
dumpStateEvery = $TG_DUMP_EVERY
numThreads = $TG_THREADS
PARAMS

    if [[ "$resampling" == "on" ]]; then
        cat >> "$params_file" <<PARAMS

# Weighted-resampling random-population Taylor--Green validation.
resamplingEnable = true
resamplingPopulationNMin = ${RESAMP_N_MIN:-14}
resamplingPopulationNTarget = ${RESAMP_N_TARGET:-20}
resamplingPopulationNMax = ${RESAMP_N_MAX:-26}
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}
resamplingTargetCellMass = $TG_GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $TG_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $TG_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = $TG_MASS_RENORM_PERIOD
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = $TG_MASS_MIN
resamplingParticleMassMax = $TG_MASS_MAX
resamplingLatentActivationEnable = false
PARAMS
    fi
    echo "$params_file"
}

run_case() {
    local label=$1
    local projection=$2
    local resampling=$3
    local params_file
    params_file=$(write_params "$label" "$projection" "$resampling")
    echo "[0130] Running $label (projection=$projection, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

run_case classic false off
run_case classic_resampling false on
run_case q6 true off
run_case q6_resampling true on

cat <<MSG
[0130] Forced Taylor--Green random-population resampling validation completed.
Run root: $RUN_ROOT

MATLAB post-processing command from the repository root:
  cd matlab
  analyze_taylor_green_random_population_resampling_0128('../$RUN_ROOT');
MSG

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/channel_cylinder_resampling_0135_0140}
INIT_ROOT=${INIT_ROOT:-init/channel_cylinder_resampling_0135}
STATE=${CHAN_CYL_INITIAL_STATE:-$INIT_ROOT/initial_state_channel_cylinder_0135.smpcd}

CCYL_LX=${CCYL_LX:-2.0}
CCYL_LY=${CCYL_LY:-1.0}
CCYL_NX=${CCYL_NX:-96}
CCYL_NY=${CCYL_NY:-48}
CCYL_GAMMA=${CCYL_GAMMA:-20}
CCYL_STEPS=${CCYL_STEPS:-3000}
CCYL_DT=${CCYL_DT:-0.001}
CCYL_KBT=${CCYL_KBT:-0.001}
CCYL_SEED=${CCYL_SEED:-1350135}
CCYL_BODY_ACCEL=${CCYL_BODY_ACCEL:-0.01}
CCYL_SUMMARY_EVERY=${CCYL_SUMMARY_EVERY:-25}
CCYL_DUMP_EVERY=${CCYL_DUMP_EVERY:-100}
CCYL_THREADS=${CCYL_THREADS:-8}

CCYL_CX=${CCYL_CX:-0.65}
CCYL_CY=${CCYL_CY:-0.5}
CCYL_R=${CCYL_R:-0.12}
CCYL_FRACTION_SAMPLES=${CCYL_FRACTION_SAMPLES:-4}
CCYL_PROJECTION_OPERATOR=${CCYL_PROJECTION_OPERATOR:-channel_fv_cg}

CCYL_WALL_ACCOMMODATION=${CCYL_WALL_ACCOMMODATION:-1.0}
CCYL_WALL_VP_GAMMA=${CCYL_WALL_VP_GAMMA:-$CCYL_GAMMA}
CCYL_WALL_THERMAL_NOISE=${CCYL_WALL_THERMAL_NOISE:-1.0}

CCYL_RESAMP_POOR_FRACTION=${CCYL_RESAMP_POOR_FRACTION:-0.90}
CCYL_RESAMP_RICH_FRACTION=${CCYL_RESAMP_RICH_FRACTION:-1.10}
CCYL_MASS_MIN=${CCYL_MASS_MIN:-0.5}
CCYL_MASS_MAX=${CCYL_MASS_MAX:-2.0}
CCYL_MASS_RENORM_PERIOD=${CCYL_MASS_RENORM_PERIOD:-10}

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

  prepare_channel_cylinder_resampling_0135( ...
      'output', '../$STATE', ...
      'Lx', $CCYL_LX, 'Ly', $CCYL_LY, ...
      'Nx', $CCYL_NX, 'Ny', $CCYL_NY, 'gamma', $CCYL_GAMMA, ...
      'cylinderCx', $CCYL_CX, 'cylinderCy', $CCYL_CY, 'cylinderR', $CCYL_R, ...
      'populationMode', 'random', 'populationStd', 6.0, ...
      'initialProfile', 'poiseuille', 'initialMeanUx', 0.02, ...
      'kBT', $CCYL_KBT, 'seed', $CCYL_SEED, 'makePreview', true);

Then return to the repository root and rerun:
  $0
MSG
    exit 2
fi

rm -rf "$RUN_ROOT"
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

Lx = $CCYL_LX
Ly = $CCYL_LY
Nx = $CCYL_NX
Ny = $CCYL_NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $CCYL_DT
nSteps = $CCYL_STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $CCYL_SEED

bodyAccelerationX = $CCYL_BODY_ACCEL
bodyAccelerationY = 0.0

bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid

projectionEnable = $projection
projectionOperator = $CCYL_PROJECTION_OPERATOR
projectionMaxIterations = 500
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidCloseCutFaces = true
projectionImmersedSolidFluidFractionThreshold = 0.5
projectionAllowUnmaskedImmersedSolid = false

immersedSolidEnable = true
immersedSolidShape = circle
immersedSolidCx = $CCYL_CX
immersedSolidCy = $CCYL_CY
immersedSolidR = $CCYL_R
immersedSolidFractionSamples = $CCYL_FRACTION_SAMPLES
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = $CCYL_WALL_ACCOMMODATION
wallVpGamma = $CCYL_WALL_VP_GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = $CCYL_WALL_THERMAL_NOISE

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $CCYL_KBT

summaryEvery = $CCYL_SUMMARY_EVERY
dumpStateEvery = $CCYL_DUMP_EVERY
numThreads = $CCYL_THREADS
PARAMS

    if [[ "$resampling" == "on" ]]; then
        cat >> "$params_file" <<PARAMS

# Weighted-resampling channel-cylinder validation.
resamplingEnable = true
resamplingPopulationNMin = ${RESAMP_N_MIN:-14}
resamplingPopulationNTarget = ${RESAMP_N_TARGET:-20}
resamplingPopulationNMax = ${RESAMP_N_MAX:-26}
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}
resamplingTargetCellMass = $CCYL_GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $CCYL_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $CCYL_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = $CCYL_MASS_RENORM_PERIOD
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = $CCYL_MASS_MIN
resamplingParticleMassMax = $CCYL_MASS_MAX
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
    echo "[0135] Running $label (projection=$projection, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

run_case classic false off
run_case classic_resampling false on
run_case q6 true off
run_case q6_resampling true on

cat <<MSG
[0135] Channel-cylinder resampling validation completed.
Run root: $RUN_ROOT

MATLAB post-processing command from the repository root:
  cd matlab
  analyze_channel_cylinder_resampling_0135('../$RUN_ROOT');
MSG

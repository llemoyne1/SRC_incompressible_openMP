#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/backward_step_resampling_0136}
INIT_ROOT=${INIT_ROOT:-init/backward_step_resampling_0136}
STATE=${BSTEP_INITIAL_STATE:-$INIT_ROOT/initial_state_backward_step_0136.smpcd}

BSTEP_LX=${BSTEP_LX:-4.0}
BSTEP_LY=${BSTEP_LY:-1.0}
BSTEP_NX=${BSTEP_NX:-192}
BSTEP_NY=${BSTEP_NY:-48}
BSTEP_GAMMA=${BSTEP_GAMMA:-20}
BSTEP_STEPS=${BSTEP_STEPS:-3000}
BSTEP_DT=${BSTEP_DT:-0.001}
BSTEP_KBT=${BSTEP_KBT:-0.001}
BSTEP_SEED=${BSTEP_SEED:-1360136}
BSTEP_SUMMARY_EVERY=${BSTEP_SUMMARY_EVERY:-25}
BSTEP_DUMP_EVERY=${BSTEP_DUMP_EVERY:-100}
BSTEP_THREADS=${BSTEP_THREADS:-8}

BSTEP_STEP_XMIN=${BSTEP_STEP_XMIN:-0.0}
BSTEP_STEP_XMAX=${BSTEP_STEP_XMAX:-0.8}
BSTEP_STEP_HEIGHT=${BSTEP_STEP_HEIGHT:-0.5}
BSTEP_FRACTION_SAMPLES=${BSTEP_FRACTION_SAMPLES:-4}

BSTEP_INLET_UX=${BSTEP_INLET_UX:-0.08}
BSTEP_INLET_PROFILE=${BSTEP_INLET_PROFILE:-flat_taper_y}
BSTEP_INLET_TAPER_CELLS=${BSTEP_INLET_TAPER_CELLS:-2.0}
BSTEP_INLET_RESERVOIR_CELLS=${BSTEP_INLET_RESERVOIR_CELLS:-3}
BSTEP_INLET_THERMAL_NOISE=${BSTEP_INLET_THERMAL_NOISE:-1.0}
BSTEP_RAMP_END_TIME=${BSTEP_RAMP_END_TIME:-0.5}
BSTEP_OUTLET_MODE=${BSTEP_OUTLET_MODE:-hybrid}
BSTEP_OUTLET_HYBRID_BLEND=${BSTEP_OUTLET_HYBRID_BLEND:-0.5}
BSTEP_OUTLET_FEEDBACK_GAIN=${BSTEP_OUTLET_FEEDBACK_GAIN:-0.0}
BSTEP_PROJECTION_OPERATOR=${BSTEP_PROJECTION_OPERATOR:-elliptic_fv_cg}

BSTEP_WALL_ACCOMMODATION=${BSTEP_WALL_ACCOMMODATION:-1.0}
BSTEP_WALL_VP_GAMMA=${BSTEP_WALL_VP_GAMMA:-$BSTEP_GAMMA}
BSTEP_WALL_THERMAL_NOISE=${BSTEP_WALL_THERMAL_NOISE:-1.0}

BSTEP_RESAMP_POOR_FRACTION=${BSTEP_RESAMP_POOR_FRACTION:-0.90}
BSTEP_RESAMP_RICH_FRACTION=${BSTEP_RESAMP_RICH_FRACTION:-1.10}
BSTEP_MASS_MIN=${BSTEP_MASS_MIN:-0.5}
BSTEP_MASS_MAX=${BSTEP_MASS_MAX:-2.0}
BSTEP_MASS_RENORM_PERIOD=${BSTEP_MASS_RENORM_PERIOD:-10}

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

  prepare_backward_step_resampling_0136( ...
      'output', '../$STATE', ...
      'Lx', $BSTEP_LX, 'Ly', $BSTEP_LY, ...
      'Nx', $BSTEP_NX, 'Ny', $BSTEP_NY, 'gamma', $BSTEP_GAMMA, ...
      'stepXMax', $BSTEP_STEP_XMAX, 'stepHeight', $BSTEP_STEP_HEIGHT, ...
      'populationMode', 'random', 'populationStd', 6.0, ...
      'initialProfile', 'inlet_plug', 'initialMeanUx', 0.04, ...
      'kBT', $BSTEP_KBT, 'seed', $BSTEP_SEED, 'makePreview', true);

Then return to the repository root and rerun:
  $0
MSG
    exit 2
fi

rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT"

write_params() {
    local label=$1
    local method=$2
    local resampling=$3
    local out_dir="$RUN_ROOT/$label"
    local params_file="$RUN_ROOT/params_${label}.kv"
    mkdir -p "$out_dir"
    cat > "$params_file" <<PARAMS
inputState = $STATE
outputDir = $out_dir

Lx = $BSTEP_LX
Ly = $BSTEP_LY
Nx = $BSTEP_NX
Ny = $BSTEP_NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $BSTEP_DT
nSteps = $BSTEP_STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $BSTEP_SEED

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

inletUxLeft = $BSTEP_INLET_UX
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = $BSTEP_RAMP_END_TIME
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = $BSTEP_INLET_PROFILE
inletVelocityWallTaperCells = $BSTEP_INLET_TAPER_CELLS
inletKBT = -1.0
inletThermalNoise = $BSTEP_INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $BSTEP_INLET_RESERVOIR_CELLS
inletTargetOccupancy = $BSTEP_GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryApertureEnable = true
leftOpenYMin = $BSTEP_STEP_HEIGHT
leftOpenYMax = $BSTEP_LY
rightOpenYMin = 0.0
rightOpenYMax = $BSTEP_LY
openBoundaryOutletMode = $BSTEP_OUTLET_MODE
openBoundaryOutletHybridBlend = $BSTEP_OUTLET_HYBRID_BLEND
openBoundaryOutletFeedbackGain = $BSTEP_OUTLET_FEEDBACK_GAIN

method = $method
projectionOperator = $BSTEP_PROJECTION_OPERATOR
projectionMaxIterations = 800
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidCloseCutFaces = true
projectionImmersedSolidFluidFractionThreshold = 0.5
projectionAllowUnmaskedImmersedSolid = false

immersedSolidEnable = true
immersedSolidShape = rectangle
immersedSolidXMin = $BSTEP_STEP_XMIN
immersedSolidXMax = $BSTEP_STEP_XMAX
immersedSolidYMin = 0.0
immersedSolidYMax = $BSTEP_STEP_HEIGHT
immersedSolidFractionSamples = $BSTEP_FRACTION_SAMPLES
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = $BSTEP_WALL_ACCOMMODATION
wallVpGamma = $BSTEP_WALL_VP_GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = $BSTEP_WALL_THERMAL_NOISE

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $BSTEP_KBT

summaryEvery = $BSTEP_SUMMARY_EVERY
dumpStateEvery = $BSTEP_DUMP_EVERY
numThreads = $BSTEP_THREADS
PARAMS

    if [[ "$resampling" == "on" ]]; then
        cat >> "$params_file" <<PARAMS

# Weighted-resampling backward-step validation.
resamplingEnable = true
resamplingPopulationGuardEnable = ${RESAMP_POP_GUARD_ENABLE:-true}
resamplingPopulationNMin = ${RESAMP_N_MIN:-14}
resamplingPopulationNTarget = ${RESAMP_N_TARGET:-20}
resamplingPopulationNMax = ${RESAMP_N_MAX:-26}
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}
resamplingTargetCellMass = $BSTEP_GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $BSTEP_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $BSTEP_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = $BSTEP_MASS_RENORM_PERIOD
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = $BSTEP_MASS_MIN
resamplingParticleMassMax = $BSTEP_MASS_MAX
resamplingLatentActivationEnable = false
PARAMS
    fi
    echo "$params_file"
}

run_case() {
    local label=$1
    local method=$2
    local resampling=$3
    local params_file
    params_file=$(write_params "$label" "$method" "$resampling")
    echo "[0136] Running $label ($method, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

run_case classic classic off
run_case q6 q6 off
run_case q6_resampling q6 on

cat <<MSG
[0136] Backward-step resampling validation completed.
Run root: $RUN_ROOT

MATLAB post-processing command from the repository root:
  cd matlab
  analyze_backward_step_resampling_0136('../$RUN_ROOT');
MSG

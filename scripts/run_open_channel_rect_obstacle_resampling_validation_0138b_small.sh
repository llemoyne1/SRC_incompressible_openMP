#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/open_channel_rect_obstacle_resampling_0138b_0140}
INIT_ROOT=${INIT_ROOT:-init/open_channel_rect_obstacle_resampling_0138b}
STATE=${ORECT_INITIAL_STATE:-$INIT_ROOT/initial_state_open_channel_rect_obstacle_0138b.smpcd}

ORECT_LX=${ORECT_LX:-2.0}
ORECT_LY=${ORECT_LY:-1.0}
ORECT_NX=${ORECT_NX:-128}
ORECT_NY=${ORECT_NY:-64}
ORECT_GAMMA=${ORECT_GAMMA:-20}
ORECT_STEPS=${ORECT_STEPS:-3000}
ORECT_DT=${ORECT_DT:-0.001}
ORECT_KBT=${ORECT_KBT:-0.005}
ORECT_SEED=${ORECT_SEED:-1380138}
ORECT_SUMMARY_EVERY=${ORECT_SUMMARY_EVERY:-25}
ORECT_DUMP_EVERY=${ORECT_DUMP_EVERY:-100}
ORECT_THREADS=${ORECT_THREADS:-8}

# Fixed-rectangle bluff body. Required by the current Q6 inlet/outlet guard.
ORECT_XMIN=${ORECT_XMIN:-0.25}
ORECT_XMAX=${ORECT_XMAX:-0.50}
ORECT_YMIN=${ORECT_YMIN:-0.35}
ORECT_YMAX=${ORECT_YMAX:-0.6}
ORECT_FRACTION_SAMPLES=${ORECT_FRACTION_SAMPLES:-4}

ORECT_INLET_UX=${ORECT_INLET_UX:-0.8}
ORECT_INLET_PROFILE=${ORECT_INLET_PROFILE:-flat_taper_y}
ORECT_INLET_TAPER_CELLS=${ORECT_INLET_TAPER_CELLS:-2.0}
ORECT_INLET_RESERVOIR_CELLS=${ORECT_INLET_RESERVOIR_CELLS:-3}
ORECT_INLET_THERMAL_NOISE=${ORECT_INLET_THERMAL_NOISE:-1.0}
ORECT_RAMP_END_TIME=${ORECT_RAMP_END_TIME:-0.5}
ORECT_OUTLET_MODE=${ORECT_OUTLET_MODE:-hybrid}
ORECT_OUTLET_HYBRID_BLEND=${ORECT_OUTLET_HYBRID_BLEND:-0.5}
ORECT_OUTLET_FEEDBACK_GAIN=${ORECT_OUTLET_FEEDBACK_GAIN:-0.0}
ORECT_PROJECTION_OPERATOR=${ORECT_PROJECTION_OPERATOR:-elliptic_fv_cg}

ORECT_WALL_ACCOMMODATION=${ORECT_WALL_ACCOMMODATION:-1.0}
ORECT_WALL_VP_GAMMA=${ORECT_WALL_VP_GAMMA:-$ORECT_GAMMA}
ORECT_WALL_THERMAL_NOISE=${ORECT_WALL_THERMAL_NOISE:-1.0}

ORECT_RESAMP_POOR_FRACTION=${ORECT_RESAMP_POOR_FRACTION:-0.90}
ORECT_RESAMP_RICH_FRACTION=${ORECT_RESAMP_RICH_FRACTION:-1.10}
ORECT_MASS_MIN=${ORECT_MASS_MIN:-0.5}
ORECT_MASS_MAX=${ORECT_MASS_MAX:-2.0}
ORECT_MASS_RENORM_PERIOD=${ORECT_MASS_RENORM_PERIOD:-1000}

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

  prepare_open_channel_rect_obstacle_resampling_0138b( ...
      'output', '../$STATE', ...
      'Lx', $ORECT_LX, 'Ly', $ORECT_LY, ...
      'Nx', $ORECT_NX, 'Ny', $ORECT_NY, 'gamma', $ORECT_GAMMA, ...
      'rectXMin', $ORECT_XMIN, 'rectXMax', $ORECT_XMAX, ...
      'rectYMin', $ORECT_YMIN, 'rectYMax', $ORECT_YMAX, ...
      'populationMode', 'random', 'populationStd', 6.0, ...
      'initialProfile', 'poiseuille', 'initialMeanUx', 0.05, ...
      'kBT', $ORECT_KBT, 'seed', $ORECT_SEED, 'makePreview', true);

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

Lx = $ORECT_LX
Ly = $ORECT_LY
Nx = $ORECT_NX
Ny = $ORECT_NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $ORECT_DT
nSteps = $ORECT_STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $ORECT_SEED

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

inletUxLeft = $ORECT_INLET_UX
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = $ORECT_RAMP_END_TIME
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = $ORECT_INLET_PROFILE
inletVelocityWallTaperCells = $ORECT_INLET_TAPER_CELLS
inletKBT = -1.0
inletThermalNoise = $ORECT_INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $ORECT_INLET_RESERVOIR_CELLS
inletTargetOccupancy = $ORECT_GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryApertureEnable = true
leftOpenYMin = 0.0
leftOpenYMax = $ORECT_LY
rightOpenYMin = 0.0
rightOpenYMax = $ORECT_LY
openBoundaryOutletMode = $ORECT_OUTLET_MODE
openBoundaryOutletHybridBlend = $ORECT_OUTLET_HYBRID_BLEND
openBoundaryOutletFeedbackGain = $ORECT_OUTLET_FEEDBACK_GAIN

method = $method
projectionOperator = $ORECT_PROJECTION_OPERATOR
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
immersedSolidXMin = $ORECT_XMIN
immersedSolidXMax = $ORECT_XMAX
immersedSolidYMin = $ORECT_YMIN
immersedSolidYMax = $ORECT_YMAX
immersedSolidFractionSamples = $ORECT_FRACTION_SAMPLES
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = $ORECT_WALL_ACCOMMODATION
wallVpGamma = $ORECT_WALL_VP_GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = $ORECT_WALL_THERMAL_NOISE

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $ORECT_KBT

summaryEvery = $ORECT_SUMMARY_EVERY
dumpStateEvery = $ORECT_DUMP_EVERY
numThreads = $ORECT_THREADS
PARAMS

    if [[ "$resampling" == "on" ]]; then
        cat >> "$params_file" <<PARAMS

# Weighted-resampling open-channel rectangular-obstacle validation.
resamplingEnable = true
resamplingPopulationGuardEnable = ${RESAMP_POP_GUARD_ENABLE:-true}
resamplingPopulationNMin = ${RESAMP_N_MIN:-14}
resamplingPopulationNTarget = ${RESAMP_N_TARGET:-20}
resamplingPopulationNMax = ${RESAMP_N_MAX:-26}
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}
resamplingTargetCellMass = $ORECT_GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $ORECT_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $ORECT_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = $ORECT_MASS_RENORM_PERIOD
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = $ORECT_MASS_MIN
resamplingParticleMassMax = $ORECT_MASS_MAX
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
    echo "[0138B] Running $label ($method, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

#run_case classic classic off
#run_case q6 q6 off
run_case q6_resampling q6 on

cat <<MSG
[0138B] Open-channel rectangular-obstacle resampling validation completed.
Run root: $RUN_ROOT

MATLAB post-processing command from the repository root:
  cd matlab
  analyze_open_channel_rect_obstacle_resampling_0138b('../$RUN_ROOT');
MSG

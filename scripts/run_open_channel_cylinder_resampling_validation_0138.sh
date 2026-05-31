#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/open_channel_cylinder_resampling_0138}
INIT_ROOT=${INIT_ROOT:-init/open_channel_cylinder_resampling_0138}
STATE=${OCYL_INITIAL_STATE:-$INIT_ROOT/initial_state_open_channel_cylinder_0138.smpcd}

OCYL_LX=${OCYL_LX:-4.0}
OCYL_LY=${OCYL_LY:-1.0}
OCYL_NX=${OCYL_NX:-192}
OCYL_NY=${OCYL_NY:-48}
OCYL_GAMMA=${OCYL_GAMMA:-20}
OCYL_STEPS=${OCYL_STEPS:-3000}
OCYL_DT=${OCYL_DT:-0.001}
OCYL_KBT=${OCYL_KBT:-0.001}
OCYL_SEED=${OCYL_SEED:-1380138}
OCYL_SUMMARY_EVERY=${OCYL_SUMMARY_EVERY:-25}
OCYL_DUMP_EVERY=${OCYL_DUMP_EVERY:-100}
OCYL_THREADS=${OCYL_THREADS:-8}

OCYL_CX=${OCYL_CX:-1.0}
OCYL_CY=${OCYL_CY:-0.5}
OCYL_R=${OCYL_R:-0.10}
OCYL_FRACTION_SAMPLES=${OCYL_FRACTION_SAMPLES:-4}

OCYL_INLET_UX=${OCYL_INLET_UX:-0.08}
OCYL_INLET_PROFILE=${OCYL_INLET_PROFILE:-flat_taper_y}
OCYL_INLET_TAPER_CELLS=${OCYL_INLET_TAPER_CELLS:-2.0}
OCYL_INLET_RESERVOIR_CELLS=${OCYL_INLET_RESERVOIR_CELLS:-3}
OCYL_INLET_THERMAL_NOISE=${OCYL_INLET_THERMAL_NOISE:-1.0}
OCYL_RAMP_END_TIME=${OCYL_RAMP_END_TIME:-0.5}
OCYL_OUTLET_MODE=${OCYL_OUTLET_MODE:-hybrid}
OCYL_OUTLET_HYBRID_BLEND=${OCYL_OUTLET_HYBRID_BLEND:-0.5}
OCYL_OUTLET_FEEDBACK_GAIN=${OCYL_OUTLET_FEEDBACK_GAIN:-0.0}
OCYL_PROJECTION_OPERATOR=${OCYL_PROJECTION_OPERATOR:-elliptic_fv_cg}

OCYL_WALL_ACCOMMODATION=${OCYL_WALL_ACCOMMODATION:-1.0}
OCYL_WALL_VP_GAMMA=${OCYL_WALL_VP_GAMMA:-$OCYL_GAMMA}
OCYL_WALL_THERMAL_NOISE=${OCYL_WALL_THERMAL_NOISE:-1.0}

OCYL_RESAMP_POOR_FRACTION=${OCYL_RESAMP_POOR_FRACTION:-0.90}
OCYL_RESAMP_RICH_FRACTION=${OCYL_RESAMP_RICH_FRACTION:-1.10}
OCYL_MASS_MIN=${OCYL_MASS_MIN:-0.5}
OCYL_MASS_MAX=${OCYL_MASS_MAX:-2.0}
OCYL_MASS_RENORM_PERIOD=${OCYL_MASS_RENORM_PERIOD:-10}

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

  prepare_open_channel_cylinder_resampling_0138( ...
      'output', '../$STATE', ...
      'Lx', $OCYL_LX, 'Ly', $OCYL_LY, ...
      'Nx', $OCYL_NX, 'Ny', $OCYL_NY, 'gamma', $OCYL_GAMMA, ...
      'cylinderCx', $OCYL_CX, 'cylinderCy', $OCYL_CY, 'cylinderR', $OCYL_R, ...
      'populationMode', 'random', 'populationStd', 6.0, ...
      'initialProfile', 'poiseuille', 'initialMeanUx', 0.05, ...
      'kBT', $OCYL_KBT, 'seed', $OCYL_SEED, 'makePreview', true);

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

Lx = $OCYL_LX
Ly = $OCYL_LY
Nx = $OCYL_NX
Ny = $OCYL_NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $OCYL_DT
nSteps = $OCYL_STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $OCYL_SEED

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

inletUxLeft = $OCYL_INLET_UX
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = $OCYL_RAMP_END_TIME
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = $OCYL_INLET_PROFILE
inletVelocityWallTaperCells = $OCYL_INLET_TAPER_CELLS
inletKBT = -1.0
inletThermalNoise = $OCYL_INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $OCYL_INLET_RESERVOIR_CELLS
inletTargetOccupancy = $OCYL_GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = $OCYL_OUTLET_MODE
openBoundaryOutletHybridBlend = $OCYL_OUTLET_HYBRID_BLEND
openBoundaryOutletFeedbackGain = $OCYL_OUTLET_FEEDBACK_GAIN

method = $method
projectionOperator = $OCYL_PROJECTION_OPERATOR
projectionMaxIterations = 800
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidCloseCutFaces = true
projectionImmersedSolidFluidFractionThreshold = 0.5
projectionAllowUnmaskedImmersedSolid = false

immersedSolidEnable = true
immersedSolidShape = circle
immersedSolidCx = $OCYL_CX
immersedSolidCy = $OCYL_CY
immersedSolidR = $OCYL_R
immersedSolidFractionSamples = $OCYL_FRACTION_SAMPLES
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = $OCYL_WALL_ACCOMMODATION
wallVpGamma = $OCYL_WALL_VP_GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = $OCYL_WALL_THERMAL_NOISE

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $OCYL_KBT

summaryEvery = $OCYL_SUMMARY_EVERY
dumpStateEvery = $OCYL_DUMP_EVERY
numThreads = $OCYL_THREADS
PARAMS

    if [[ "$resampling" == "on" ]]; then
        cat >> "$params_file" <<PARAMS

# Weighted-resampling open-channel-cylinder validation.
resamplingEnable = true
resamplingTargetCellMass = $OCYL_GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $OCYL_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $OCYL_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = $OCYL_MASS_RENORM_PERIOD
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = $OCYL_MASS_MIN
resamplingParticleMassMax = $OCYL_MASS_MAX
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
    echo "[0138] Running $label ($method, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

run_case classic classic off
run_case q6 q6 off
run_case q6_resampling q6 on

cat <<MSG
[0138] Open-channel-cylinder resampling validation completed.
Run root: $RUN_ROOT

MATLAB post-processing command from the repository root:
  cd matlab
  analyze_open_channel_cylinder_resampling_0138('../$RUN_ROOT');
MSG

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/same_face_segmented_io_0143}
INIT_ROOT=${INIT_ROOT:-init/injection_fill_resampling_0139}
STATE=${SEGIO_INITIAL_STATE:-$INIT_ROOT/initial_state_injection_fill_0139.smpcd}

SEGIO_LX=${SEGIO_LX:-4.0}
SEGIO_LY=${SEGIO_LY:-1.0}
SEGIO_NX=${SEGIO_NX:-192}
SEGIO_NY=${SEGIO_NY:-48}
SEGIO_GAMMA=${SEGIO_GAMMA:-20}
SEGIO_STEPS=${SEGIO_STEPS:-5000}
SEGIO_DT=${SEGIO_DT:-0.001}
SEGIO_KBT=${SEGIO_KBT:-0.001}
SEGIO_SEED=${SEGIO_SEED:-1430143}
SEGIO_SUMMARY_EVERY=${SEGIO_SUMMARY_EVERY:-25}
SEGIO_DUMP_EVERY=${SEGIO_DUMP_EVERY:-100}
SEGIO_THREADS=${SEGIO_THREADS:-8}

# Relative tangent-coordinate intervals on the left face.  y/Ly is used for left/right faces.
SEGIO_INLET_SMIN=${SEGIO_INLET_SMIN:-0.65}
SEGIO_INLET_SMAX=${SEGIO_INLET_SMAX:-0.90}
SEGIO_OUTLET_SMIN=${SEGIO_OUTLET_SMIN:-0.10}
SEGIO_OUTLET_SMAX=${SEGIO_OUTLET_SMAX:-0.35}
SEGIO_INLET_UX=${SEGIO_INLET_UX:-0.10}
SEGIO_INLET_UY=${SEGIO_INLET_UY:-0.0}
SEGIO_INLET_TYPE=${SEGIO_INLET_TYPE:-0}
SEGIO_INLET_MASS=${SEGIO_INLET_MASS:-1.0}
SEGIO_OUTLET_TYPE=${SEGIO_OUTLET_TYPE:-0}
SEGIO_OUTLET_MASS=${SEGIO_OUTLET_MASS:-1.0}
SEGIO_RAMP_END_TIME=${SEGIO_RAMP_END_TIME:-0.2}
SEGIO_INLET_THERMAL_NOISE=${SEGIO_INLET_THERMAL_NOISE:-1.0}
SEGIO_INLET_RESERVOIR_CELLS=${SEGIO_INLET_RESERVOIR_CELLS:-1}
SEGIO_OUTLET_MODE=${SEGIO_OUTLET_MODE:-neumann}
SEGIO_OUTLET_FEEDBACK_GAIN=${SEGIO_OUTLET_FEEDBACK_GAIN:-0.0}

SEGIO_WALL_ACCOMMODATION=${SEGIO_WALL_ACCOMMODATION:-1.0}
SEGIO_WALL_VP_GAMMA=${SEGIO_WALL_VP_GAMMA:-$SEGIO_GAMMA}
SEGIO_WALL_THERMAL_NOISE=${SEGIO_WALL_THERMAL_NOISE:-1.0}

SEGIO_RESAMP_POOR_FRACTION=${SEGIO_RESAMP_POOR_FRACTION:-0.50}
SEGIO_RESAMP_RICH_FRACTION=${SEGIO_RESAMP_RICH_FRACTION:-1.50}
SEGIO_MASS_MIN=${SEGIO_MASS_MIN:-0.5}
SEGIO_MASS_MAX=${SEGIO_MASS_MAX:-2.0}
SEGIO_MASS_RENORM_PERIOD=${SEGIO_MASS_RENORM_PERIOD:-10}

if [[ ! -x build/src_mpcd_base ]]; then
    ./scripts/build_src_mpcd_base.sh
fi

if [[ ! -f "$STATE" ]]; then
    cat >&2 <<MSG
Missing initial inactive-pool state:
  $STATE

Generate it with matlab/prepare_injection_fill_resampling_0139.m or point SEGIO_INITIAL_STATE to an existing .smpcd file.
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

Lx = $SEGIO_LX
Ly = $SEGIO_LY
Nx = $SEGIO_NX
Ny = $SEGIO_NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $SEGIO_DT
nSteps = $SEGIO_STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $SEGIO_SEED

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = $SEGIO_RAMP_END_TIME
inletVelocityRampInitialFactor = 0.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletKBT = -1.0
inletThermalNoise = $SEGIO_INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $SEGIO_INLET_RESERVOIR_CELLS
inletTargetOccupancy = $SEGIO_GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet  $SEGIO_INLET_SMIN  $SEGIO_INLET_SMAX  $SEGIO_INLET_UX $SEGIO_INLET_UY $SEGIO_INLET_TYPE $SEGIO_INLET_MASS
openBoundarySegment1 = left outlet $SEGIO_OUTLET_SMIN $SEGIO_OUTLET_SMAX 0.0 0.0 $SEGIO_OUTLET_TYPE $SEGIO_OUTLET_MASS
openBoundaryOutletMode = $SEGIO_OUTLET_MODE
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = $SEGIO_OUTLET_FEEDBACK_GAIN

method = $method
projectionOperator = elliptic_fv_cg
projectionMaxIterations = 800
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
projectionImmersedSolidMaskEnable = false
projectionImmersedSolidCloseCutFaces = false
projectionAllowUnmaskedImmersedSolid = true

immersedSolidEnable = false

wallAccommodation = $SEGIO_WALL_ACCOMMODATION
wallVpGamma = $SEGIO_WALL_VP_GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = $SEGIO_WALL_THERMAL_NOISE

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $SEGIO_KBT

summaryEvery = $SEGIO_SUMMARY_EVERY
dumpStateEvery = $SEGIO_DUMP_EVERY
numThreads = $SEGIO_THREADS
PARAMS

    if [[ "$resampling" == "on" ]]; then
        cat >> "$params_file" <<PARAMS

resamplingEnable = true
resamplingPopulationGuardEnable = ${RESAMP_POP_GUARD_ENABLE:-true}
resamplingPopulationNMin = ${RESAMP_N_MIN:-14}
resamplingPopulationNTarget = ${RESAMP_N_TARGET:-20}
resamplingPopulationNMax = ${RESAMP_N_MAX:-26}
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}
resamplingTargetCellMass = $SEGIO_GAMMA
resamplingWetMaskMode = occupied
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $SEGIO_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $SEGIO_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = $SEGIO_MASS_RENORM_PERIOD
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = $SEGIO_MASS_MIN
resamplingParticleMassMax = $SEGIO_MASS_MAX
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
    echo "[0143] Running $label ($method, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

run_case classic classic off
run_case q6_resampling q6 on

cat <<MSG
[0143] Same-face segmented inlet/outlet validation completed.
Run root: $RUN_ROOT

Left face segments:
  inlet  s=[$SEGIO_INLET_SMIN,$SEGIO_INLET_SMAX]
  outlet s=[$SEGIO_OUTLET_SMIN,$SEGIO_OUTLET_SMAX]
MSG

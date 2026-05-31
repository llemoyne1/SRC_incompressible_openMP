#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/injection_fill_resampling_0139_0140}
INIT_ROOT=${INIT_ROOT:-init/injection_fill_resampling_0139}
STATE=${FILL_INITIAL_STATE:-$INIT_ROOT/initial_state_injection_fill_0139.smpcd}

FILL_LX=${FILL_LX:-4.0}
FILL_LY=${FILL_LY:-1.0}
FILL_NX=${FILL_NX:-192}
FILL_NY=${FILL_NY:-48}
FILL_GAMMA=${FILL_GAMMA:-20}
FILL_STEPS=${FILL_STEPS:-3000}
FILL_DT=${FILL_DT:-0.001}
FILL_KBT=${FILL_KBT:-0.001}
FILL_SEED=${FILL_SEED:-1390139}
FILL_SUMMARY_EVERY=${FILL_SUMMARY_EVERY:-25}
FILL_DUMP_EVERY=${FILL_DUMP_EVERY:-100}
FILL_THREADS=${FILL_THREADS:-8}

FILL_INLET_UX=${FILL_INLET_UX:-0.10}
FILL_INLET_CENTER_Y=${FILL_INLET_CENTER_Y:-0.5}
FILL_INLET_HEIGHT_CELLS=${FILL_INLET_HEIGHT_CELLS:-1.0}
FILL_INLET_RESERVOIR_CELLS=${FILL_INLET_RESERVOIR_CELLS:-1}
FILL_INLET_PROFILE=${FILL_INLET_PROFILE:-uniform}
FILL_INLET_TAPER_CELLS=${FILL_INLET_TAPER_CELLS:-0.0}
FILL_INLET_THERMAL_NOISE=${FILL_INLET_THERMAL_NOISE:-1.0}
FILL_RAMP_END_TIME=${FILL_RAMP_END_TIME:-0.2}
FILL_OUTLET_MODE=${FILL_OUTLET_MODE:-hybrid}
FILL_OUTLET_HYBRID_BLEND=${FILL_OUTLET_HYBRID_BLEND:-0.5}
FILL_OUTLET_FEEDBACK_GAIN=${FILL_OUTLET_FEEDBACK_GAIN:-0.0}
FILL_PROJECTION_OPERATOR=${FILL_PROJECTION_OPERATOR:-elliptic_fv_cg}

FILL_WALL_ACCOMMODATION=${FILL_WALL_ACCOMMODATION:-1.0}
FILL_WALL_VP_GAMMA=${FILL_WALL_VP_GAMMA:-$FILL_GAMMA}
FILL_WALL_THERMAL_NOISE=${FILL_WALL_THERMAL_NOISE:-1.0}

FILL_RESAMP_POOR_FRACTION=${FILL_RESAMP_POOR_FRACTION:-0.50}
FILL_RESAMP_RICH_FRACTION=${FILL_RESAMP_RICH_FRACTION:-1.50}
FILL_MASS_MIN=${FILL_MASS_MIN:-0.5}
FILL_MASS_MAX=${FILL_MASS_MAX:-2.0}
FILL_MASS_RENORM_PERIOD=${FILL_MASS_RENORM_PERIOD:-10}

FILL_INLET_YMIN=${FILL_INLET_YMIN:-$(awk -v cy="$FILL_INLET_CENTER_Y" -v h="$FILL_INLET_HEIGHT_CELLS" -v ly="$FILL_LY" -v ny="$FILL_NY" 'BEGIN{dy=ly/ny; y=cy-0.5*h*dy; if(y<0)y=0; printf "%.17g", y}')}
FILL_INLET_YMAX=${FILL_INLET_YMAX:-$(awk -v cy="$FILL_INLET_CENTER_Y" -v h="$FILL_INLET_HEIGHT_CELLS" -v ly="$FILL_LY" -v ny="$FILL_NY" 'BEGIN{dy=ly/ny; y=cy+0.5*h*dy; if(y>ly)y=ly; printf "%.17g", y}')}

if [[ ! -x build/src_mpcd_base ]]; then
    ./scripts/build_src_mpcd_base.sh
fi

if [[ ! -f "$STATE" ]]; then
    cat >&2 <<MSG
Missing initial inactive-pool state:
  $STATE

Generate it from MATLAB before launching OpenMP. From the repository root:

  cd matlab

then in MATLAB:

  prepare_injection_fill_resampling_0139( ...
      'output', '../$STATE', ...
      'Lx', $FILL_LX, 'Ly', $FILL_LY, ...
      'Nx', $FILL_NX, 'Ny', $FILL_NY, 'gamma', $FILL_GAMMA, ...
      'capacityMultiplier', 1.0, ...
      'kBT', $FILL_KBT, ...
      'seed', $FILL_SEED, ...
      'inletYCenter', $FILL_INLET_CENTER_Y, ...
      'inletHeightCells', $FILL_INLET_HEIGHT_CELLS, ...
      'makePreview', true);

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

Lx = $FILL_LX
Ly = $FILL_LY
Nx = $FILL_NX
Ny = $FILL_NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $FILL_DT
nSteps = $FILL_STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $FILL_SEED

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid

inletUxLeft = $FILL_INLET_UX
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = $FILL_RAMP_END_TIME
inletVelocityRampInitialFactor = 0.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = $FILL_INLET_PROFILE
inletVelocityWallTaperCells = $FILL_INLET_TAPER_CELLS
inletKBT = -1.0
inletThermalNoise = $FILL_INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $FILL_INLET_RESERVOIR_CELLS
inletTargetOccupancy = $FILL_GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 1
openBoundarySegment0 = left inlet $(awk -v y="$FILL_INLET_YMIN" -v ly="$FILL_LY" 'BEGIN{printf "%.17g", y/ly}') $(awk -v y="$FILL_INLET_YMAX" -v ly="$FILL_LY" 'BEGIN{printf "%.17g", y/ly}') $FILL_INLET_UX 0.0 0 1.0
openBoundaryOutletMode = $FILL_OUTLET_MODE
openBoundaryOutletHybridBlend = $FILL_OUTLET_HYBRID_BLEND
openBoundaryOutletFeedbackGain = $FILL_OUTLET_FEEDBACK_GAIN

method = $method
projectionOperator = $FILL_PROJECTION_OPERATOR
projectionMaxIterations = 800
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
projectionImmersedSolidMaskEnable = false
projectionImmersedSolidCloseCutFaces = false
projectionAllowUnmaskedImmersedSolid = true

immersedSolidEnable = false

wallAccommodation = $FILL_WALL_ACCOMMODATION
wallVpGamma = $FILL_WALL_VP_GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = $FILL_WALL_THERMAL_NOISE

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $FILL_KBT

summaryEvery = $FILL_SUMMARY_EVERY
dumpStateEvery = $FILL_DUMP_EVERY
numThreads = $FILL_THREADS
PARAMS

    if [[ "$resampling" == "on" ]]; then
        cat >> "$params_file" <<PARAMS

# Wet/dry injection/fill stress test. Empty cells remain dry: they must not be
# forced to Mtarget before the advected front reaches them.
resamplingEnable = true
resamplingPopulationGuardEnable = ${RESAMP_POP_GUARD_ENABLE:-true}
resamplingPopulationNMin = ${RESAMP_N_MIN:-14}
resamplingPopulationNTarget = ${RESAMP_N_TARGET:-20}
resamplingPopulationNMax = ${RESAMP_N_MAX:-26}
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}
resamplingTargetCellMass = $FILL_GAMMA
resamplingWetMaskMode = occupied
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $FILL_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $FILL_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = $FILL_MASS_RENORM_PERIOD
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = $FILL_MASS_MIN
resamplingParticleMassMax = $FILL_MASS_MAX
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
    echo "[0139] Running $label ($method, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

run_case classic classic off
#run_case q6 q6 off
run_case q6_resampling q6 on

cat <<MSG
[0139] Injection/fill resampling validation completed.
Run root: $RUN_ROOT

MATLAB post-processing command from the repository root:
  cd matlab
  analyze_injection_fill_resampling_0139('../$RUN_ROOT');
MSG

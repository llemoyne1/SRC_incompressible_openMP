#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/periodic_cylinder_resampling_0134_0140}
INIT_ROOT=${INIT_ROOT:-init/periodic_cylinder_resampling_0134}
STATE=${CYL_INITIAL_STATE:-$INIT_ROOT/initial_state_periodic_cylinder_0134_0140.smpcd}

CYL_LX=${CYL_LX:-2.0}
CYL_LY=${CYL_LY:-1.0}
CYL_NX=${CYL_NX:-96}
CYL_NY=${CYL_NY:-48}
CYL_GAMMA=${CYL_GAMMA:-20}
CYL_STEPS=${CYL_STEPS:-10000}
CYL_DT=${CYL_DT:-0.001}
CYL_KBT=${CYL_KBT:-0.001}
CYL_SEED=${CYL_SEED:-1340134}
CYL_BODY_ACCEL=${CYL_BODY_ACCEL:-0.075}
CYL_SUMMARY_EVERY=${CYL_SUMMARY_EVERY:-100}
CYL_DUMP_EVERY=${CYL_DUMP_EVERY:-100}
CYL_THREADS=${CYL_THREADS:-8}

CYL_CX=${CYL_CX:-0.5}
CYL_CY=${CYL_CY:-0.485}
CYL_R=${CYL_R:-0.12}
CYL_FRACTION_SAMPLES=${CYL_FRACTION_SAMPLES:-4}
CYL_PROJECTION_OPERATOR=${CYL_PROJECTION_OPERATOR:-periodic_fv_cg}

ORECT_WALL_THERMAL_NOISE=${ORECT_WALL_THERMAL_NOISE:-1.0}

CYL_RESAMP_POOR_FRACTION=${CYL_RESAMP_POOR_FRACTION:-0.90}
CYL_RESAMP_RICH_FRACTION=${CYL_RESAMP_RICH_FRACTION:-1.10}
CYL_MASS_MIN=${CYL_MASS_MIN:-0.5}
CYL_MASS_MAX=${CYL_MASS_MAX:-2.0}
CYL_MASS_RENORM_PERIOD=${CYL_MASS_RENORM_PERIOD:-1000}

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

  prepare_periodic_cylinder_resampling_0134( ...
      'output', '../$STATE', ...
      'Lx', $CYL_LX, 'Ly', $CYL_LY, ...
      'Nx', $CYL_NX, 'Ny', $CYL_NY, 'gamma', $CYL_GAMMA, ...
      'cylinderCx', $CYL_CX, 'cylinderCy', $CYL_CY, 'cylinderR', $CYL_R, ...
      'populationMode', 'random', 'populationStd', 6.0, ...
      'kBT', $CYL_KBT, 'initialMeanUx', 0.02, 'seed', $CYL_SEED);

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

Lx = $CYL_LX
Ly = $CYL_LY
Nx = $CYL_NX
Ny = $CYL_NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $CYL_DT
nSteps = $CYL_STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $CYL_SEED

bodyAccelerationX = $CYL_BODY_ACCEL
bodyAccelerationY = 0.0

bcX = periodic
bcY = periodic
bcBottom = solid
bcTop = solid

method = $method
projectionOperator = $CYL_PROJECTION_OPERATOR
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
immersedSolidCx = $CYL_CX
immersedSolidCy = $CYL_CY
immersedSolidR = $CYL_R
immersedSolidFractionSamples = $CYL_FRACTION_SAMPLES
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = 1.0
wallVpGamma = 20.0
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 1.0

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $CYL_KBT

summaryEvery = $CYL_SUMMARY_EVERY
dumpStateEvery = $CYL_DUMP_EVERY
numThreads = $CYL_THREADS
PARAMS

    if [[ "$resampling" == "on" ]]; then
        cat >> "$params_file" <<PARAMS

# Weighted-resampling periodic-cylinder validation.
resamplingEnable = true
resamplingPopulationGuardEnable = ${RESAMP_POP_GUARD_ENABLE:-true}
resamplingPopulationNMin = ${RESAMP_N_MIN:-14}
resamplingPopulationNTarget = ${RESAMP_N_TARGET:-20}
resamplingPopulationNMax = ${RESAMP_N_MAX:-26}
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}
resamplingTargetCellMass = $CYL_GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $CYL_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $CYL_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = $CYL_MASS_RENORM_PERIOD
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = $CYL_MASS_MIN
resamplingParticleMassMax = $CYL_MASS_MAX
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
    echo "[0134] Running $label ($method, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

# run_case classic classic off
# run_case q6 q6 off
run_case q6_resampling q6 on

cat <<MSG
[0134] Periodic cylinder resampling validation completed.
Run root: $RUN_ROOT

MATLAB post-processing command from the repository root:
  cd matlab
  analyze_periodic_cylinder_resampling_0134('../$RUN_ROOT');
MSG

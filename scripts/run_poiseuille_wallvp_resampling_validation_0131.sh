#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/poiseuille_wallvp_resampling_0131}
INIT_ROOT=${INIT_ROOT:-init/poiseuille_wallvp_resampling_0131}
STATE=${POIS_INITIAL_STATE:-$INIT_ROOT/initial_state_poiseuille_wallvp_0131.smpcd}

POIS_LX=${POIS_LX:-2.0}
POIS_LY=${POIS_LY:-1.0}
POIS_NX=${POIS_NX:-64}
POIS_NY=${POIS_NY:-32}
POIS_GAMMA=${POIS_GAMMA:-20}
POIS_STEPS=${POIS_STEPS:-3000}
POIS_DT=${POIS_DT:-0.001}
POIS_KBT=${POIS_KBT:-0.001}
POIS_SEED=${POIS_SEED:-1310131}
POIS_BODY_ACCEL=${POIS_BODY_ACCEL:-0.02}
POIS_SUMMARY_EVERY=${POIS_SUMMARY_EVERY:-10}
POIS_DUMP_EVERY=${POIS_DUMP_EVERY:-100}
POIS_THREADS=${POIS_THREADS:-8}
POIS_PROJECTION_OPERATOR=${POIS_PROJECTION_OPERATOR:-channel_fv_cg}

POIS_WALL_ACCOMMODATION=${POIS_WALL_ACCOMMODATION:-1.0}
POIS_WALL_VP_GAMMA=${POIS_WALL_VP_GAMMA:-$POIS_GAMMA}
POIS_WALL_THERMAL_NOISE=${POIS_WALL_THERMAL_NOISE:-1.0}

POIS_RESAMP_POOR_FRACTION=${POIS_RESAMP_POOR_FRACTION:-0.90}
POIS_RESAMP_RICH_FRACTION=${POIS_RESAMP_RICH_FRACTION:-1.10}
POIS_MASS_MIN=${POIS_MASS_MIN:-0.5}
POIS_MASS_MAX=${POIS_MASS_MAX:-2.0}
POIS_MASS_RENORM_PERIOD=${POIS_MASS_RENORM_PERIOD:-10}

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

  prepare_poiseuille_wallvp_resampling_0131( ...
      'output', '../$STATE', ...
      'Lx', $POIS_LX, 'Ly', $POIS_LY, ...
      'Nx', $POIS_NX, 'Ny', $POIS_NY, 'gamma', $POIS_GAMMA, ...
      'kBT', $POIS_KBT, 'seed', $POIS_SEED);

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

Lx = $POIS_LX
Ly = $POIS_LY
Nx = $POIS_NX
Ny = $POIS_NY

dt = $POIS_DT
nSteps = $POIS_STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $POIS_SEED

bodyAccelerationX = $POIS_BODY_ACCEL
bodyAccelerationY = 0.0

bcX = periodic
bcY = solid

wallVpEnable = true
wallAccommodation = $POIS_WALL_ACCOMMODATION
wallVpGamma = $POIS_WALL_VP_GAMMA
wallVpMass = 1.0
wallKBT = $POIS_KBT
wallThermalNoise = $POIS_WALL_THERMAL_NOISE
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = 0.0
wallUyTop = 0.0

method = $method
projectionOperator = $POIS_PROJECTION_OPERATOR
projectionMaxIterations = 500
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $POIS_KBT

summaryEvery = $POIS_SUMMARY_EVERY
dumpStateEvery = $POIS_DUMP_EVERY
numThreads = $POIS_THREADS
PARAMS

    if [[ "$resampling" == "on" ]]; then
        cat >> "$params_file" <<PARAMS

# Weighted-resampling Poiseuille wallVP validation.
resamplingEnable = true
resamplingTargetCellMass = $POIS_GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $POIS_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $POIS_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = $POIS_MASS_RENORM_PERIOD
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = $POIS_MASS_MIN
resamplingParticleMassMax = $POIS_MASS_MAX
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
    echo "[0131] Running $label ($method, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

run_case classic classic off
run_case q6 q6 off
run_case q6_resampling q6 on

cat <<MSG
[0131] Poiseuille wallVP resampling validation completed.
Run root: $RUN_ROOT

MATLAB post-processing command from the repository root:
  cd matlab
  analyze_poiseuille_wallvp_resampling_0131('../$RUN_ROOT');
MSG

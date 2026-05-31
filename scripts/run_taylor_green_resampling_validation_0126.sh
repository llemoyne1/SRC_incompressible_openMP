#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/taylor_green_resampling_0126}
TG_NX=${TG_NX:-32}
TG_NY=${TG_NY:-32}
TG_GAMMA=${TG_GAMMA:-20}
TG_STEPS=${TG_STEPS:-1000}
TG_DT=${TG_DT:-0.001}
TG_U0=${TG_U0:-0.08}
TG_KBT=${TG_KBT:-0.001}
TG_SEED=${TG_SEED:-1260126}
TG_SUMMARY_EVERY=${TG_SUMMARY_EVERY:-10}
TG_DUMP_EVERY=${TG_DUMP_EVERY:-100}
TG_THREADS=${TG_THREADS:-4}
TG_RESAMP_POOR_FRACTION=${TG_RESAMP_POOR_FRACTION:-0.75}
TG_RESAMP_RICH_FRACTION=${TG_RESAMP_RICH_FRACTION:-1.25}
TG_MASS_MIN=${TG_MASS_MIN:-0.25}
TG_MASS_MAX=${TG_MASS_MAX:-4.0}
TG_MASS_RENORM_PERIOD=${TG_MASS_RENORM_PERIOD:-10}
TG_FORCING_ENABLE=${TG_FORCING_ENABLE:-false}
TG_FORCING_AMPLITUDE=${TG_FORCING_AMPLITUDE:-0.0}
TG_FORCING_MODE_X=${TG_FORCING_MODE_X:-1}
TG_FORCING_MODE_Y=${TG_FORCING_MODE_Y:-1}
MATLAB_BIN=${MATLAB_BIN:-matlab}
RUN_ANALYSIS=${RUN_ANALYSIS:-1}

STATE="$RUN_ROOT/initial_state_tg_0126.smpcd"
mkdir -p "$RUN_ROOT"

if [[ ! -x build/src_mpcd_base ]]; then
    ./scripts/build_src_mpcd_base.sh
fi

if ! command -v "$MATLAB_BIN" >/dev/null 2>&1; then
    echo "MATLAB executable '$MATLAB_BIN' was not found. Set MATLAB_BIN=/path/to/matlab or generate $STATE manually." >&2
    exit 127
fi

echo "[0126] Generating Taylor--Green V2 initial state: $STATE"
"$MATLAB_BIN" -batch "addpath('matlab'); generate_taylor_green_resampling_state_0126('output','$STATE','Nx',$TG_NX,'Ny',$TG_NY,'gamma',$TG_GAMMA,'flowAmplitude',$TG_U0,'kBT',$TG_KBT,'seed',$TG_SEED);"

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

# Weighted-resampling core, fully periodic Taylor--Green validation.
resamplingEnable = true
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
    echo "[0126] Running $label (projection=$projection, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

run_case classic false off
run_case classic_resampling false on
run_case q6 true off
run_case q6_resampling true on

if [[ "$RUN_ANALYSIS" == "1" || "$RUN_ANALYSIS" == "true" || "$RUN_ANALYSIS" == "on" ]]; then
    echo "[0126] MATLAB post-processing"
    "$MATLAB_BIN" -batch "addpath('matlab'); analyze_taylor_green_resampling_0126('$RUN_ROOT','makePlots',true);"
fi

echo "[0126] Taylor--Green resampling validation completed. Run root: $RUN_ROOT"

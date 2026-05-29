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
MATLAB_BIN=${MATLAB_BIN:-matlab}
PYTHON_BIN=${PYTHON_BIN:-python3}
TG_GENERATOR=${TG_GENERATOR:-auto}
RUN_ANALYSIS=${RUN_ANALYSIS:-auto}

STATE="$RUN_ROOT/initial_state_tg_0126.smpcd"
mkdir -p "$RUN_ROOT"

if [[ ! -x build/src_mpcd_base ]]; then
    ./scripts/build_src_mpcd_base.sh
fi

have_executable() {
    local exe="$1"
    command -v "$exe" >/dev/null 2>&1 || [[ -x "$exe" ]]
}

generate_state_with_python() {
    echo "[0126] Generating Taylor--Green V2 initial state with Python: $STATE"
    "$PYTHON_BIN" scripts/generate_taylor_green_resampling_state_0126.py \
        --output "$STATE" \
        --Lx 1.0 --Ly 1.0 \
        --Nx "$TG_NX" --Ny "$TG_NY" --gamma "$TG_GAMMA" \
        --flow-amplitude "$TG_U0" \
        --kBT "$TG_KBT" \
        --mass 1.0 \
        --seed "$TG_SEED"
}

generate_state_with_matlab() {
    echo "[0126] Generating Taylor--Green V2 initial state with MATLAB: $STATE"
    "$MATLAB_BIN" -batch "addpath('matlab'); generate_taylor_green_resampling_state_0126('output','$STATE','Nx',$TG_NX,'Ny',$TG_NY,'gamma',$TG_GAMMA,'flowAmplitude',$TG_U0,'kBT',$TG_KBT,'seed',$TG_SEED);"
}

case "$TG_GENERATOR" in
    python)
        if ! have_executable "$PYTHON_BIN"; then
            echo "Python executable '$PYTHON_BIN' was not found. Set PYTHON_BIN=/path/to/python3." >&2
            exit 127
        fi
        generate_state_with_python
        ;;
    matlab)
        if ! have_executable "$MATLAB_BIN"; then
            echo "MATLAB executable '$MATLAB_BIN' was not found. Set MATLAB_BIN=/path/to/matlab." >&2
            exit 127
        fi
        generate_state_with_matlab
        ;;
    auto)
        if have_executable "$PYTHON_BIN"; then
            generate_state_with_python
        elif have_executable "$MATLAB_BIN"; then
            generate_state_with_matlab
        else
            echo "Neither Python ('$PYTHON_BIN') nor MATLAB ('$MATLAB_BIN') was found for initial-state generation." >&2
            echo "Install python3, set PYTHON_BIN, or generate $STATE manually." >&2
            exit 127
        fi
        ;;
    *)
        echo "Unsupported TG_GENERATOR='$TG_GENERATOR'. Use auto, python, or matlab." >&2
        exit 2
        ;;
esac

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

bcX = periodic
bcY = periodic

method = $method
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
resamplingTargetCellMass = $TG_GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $TG_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $TG_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
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
    local method=$2
    local resampling=$3
    local params_file
    params_file=$(write_params "$label" "$method" "$resampling")
    echo "[0126] Running $label ($method, resampling=$resampling)"
    ./build/src_mpcd_base "$params_file"
}

run_case classic classic off
run_case q6 q6 off
run_case q6_resampling q6 on

run_matlab_analysis() {
    echo "[0126] MATLAB post-processing"
    "$MATLAB_BIN" -batch "addpath('matlab'); analyze_taylor_green_resampling_0126('$RUN_ROOT','makePlots',true);"
}

case "$RUN_ANALYSIS" in
    1|true|on|yes)
        if ! have_executable "$MATLAB_BIN"; then
            echo "MATLAB executable '$MATLAB_BIN' was not found for analysis." >&2
            echo "The OpenMP runs completed. Re-run analysis later with MATLAB_BIN set, or call analyze_taylor_green_resampling_0126 from MATLAB." >&2
            exit 127
        fi
        run_matlab_analysis
        ;;
    auto)
        if have_executable "$MATLAB_BIN"; then
            run_matlab_analysis
        else
            echo "[0126] MATLAB not found; skipping post-processing. OpenMP runs are available in: $RUN_ROOT"
            echo "[0126] Later, run from MATLAB: addpath('matlab'); analyze_taylor_green_resampling_0126('$RUN_ROOT','makePlots',true);"
        fi
        ;;
    0|false|off|no)
        echo "[0126] RUN_ANALYSIS=$RUN_ANALYSIS: skipping MATLAB post-processing."
        ;;
    *)
        echo "Unsupported RUN_ANALYSIS='$RUN_ANALYSIS'. Use auto, 1/true/on/yes, or 0/false/off/no." >&2
        exit 2
        ;;
esac

echo "[0126] Taylor--Green resampling validation completed. Run root: $RUN_ROOT"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/closed_capacity_wall_load_validation_0152}
INIT_ROOT=${INIT_ROOT:-init/closed_capacity_wall_load_0152}

LX=${CAP_LX:-1.0}
LY=${CAP_LY:-1.0}
NX=${CAP_NX:-48}
NY=${CAP_NY:-48}
GAMMA=${CAP_GAMMA:-20}
STEPS=${CAP_STEPS:-300}
DT=${CAP_DT:-0.001}
KBT=${CAP_KBT:-0.0}
# Static wall-load validation is virial-only by default.  Wall VP and
# thermostat are disabled so CAP_KBT=0 remains valid.  Set these explicitly
# for finite-temperature checks.
WALL_ACCOMMODATION=${CAP_WALL_ACCOMMODATION:-0.0}
WALL_KBT=${CAP_WALL_KBT:-1.0}
THERMOSTAT_ENABLE=${CAP_THERMOSTAT_ENABLE:-false}
THERMAL_RENORM_ENABLE=${CAP_THERMAL_RENORM_ENABLE:-false}
SEED=${CAP_SEED:-1520152}
SUMMARY_EVERY=${CAP_SUMMARY_EVERY:-10}
DUMP_EVERY=${CAP_DUMP_EVERY:-0}
THREADS=${CAP_THREADS:-8}

# Static overfill factors.  1.00 is the baseline with no virial overfill.
MASS_FACTORS=${CAP_STATIC_MASS_FACTORS:-"1.00 1.02 1.05 1.10"}
STATE_CAPACITY_MULTIPLIER=${CAP_STATE_CAPACITY_MULTIPLIER:-1.10}
AUTO_GENERATE_STATES=${CAP_AUTO_GENERATE_STATES:-1}
MATLAB_BIN=${MATLAB_BIN:-matlab}

CAP_Q6_ETA=${CAP_Q6_ETA:-0.005}
CAP_Q6_POWER=${CAP_Q6_POWER:-2.0}
CAP_REMAP_ETA=${CAP_REMAP_ETA:-0.005}
CAP_REMAP_POWER=${CAP_REMAP_POWER:-2.0}
CAP_VIRIAL_K=${CAP_VIRIAL_K:-100.0}
CAP_VIRIAL_GAIN=${CAP_VIRIAL_GAIN:-20.0}
CAP_VIRIAL_ETA=${CAP_VIRIAL_ETA:-0.005}
CAP_VIRIAL_POWER=${CAP_VIRIAL_POWER:-2.0}

RESAMP_N_MIN=${RESAMP_N_MIN:-14}
RESAMP_N_TARGET=${RESAMP_N_TARGET:-20}
RESAMP_N_MAX=${RESAMP_N_MAX:-26}

factor_tag() {
    # Keep the shell runner consistent with
    # prepare_closed_capacity_uniform_overfill_suite_0152.m, which writes
    # compact numeric tags: 1.00 -> 1, 1.10 -> 1p1, 1.02 -> 1p02.
    local f="$1"
    awk -v x="$f" 'BEGIN { printf "%.15g", x + 0.0 }' \
        | sed 's/-/m/g; s/\./p/g'
}

matlab_generate_state() {
    local factor="$1"
    local state="$2"
    local tag
    tag=$(factor_tag "$factor")
    if [[ "$AUTO_GENERATE_STATES" != "1" ]]; then
        return 1
    fi
    if ! command -v "$MATLAB_BIN" >/dev/null 2>&1; then
        return 1
    fi
    echo "[0152] Generating missing state with MATLAB: factor=$factor -> $state"
    "$MATLAB_BIN" -batch "cd('matlab'); prepare_closed_capacity_uniform_overfill_0152('output','../$state','Lx',$LX,'Ly',$LY,'Nx',$NX,'Ny',$NY,'gamma',$GAMMA,'massFactor',$factor,'capacityMultiplier',$STATE_CAPACITY_MULTIPLIER,'kBT',$KBT,'velocityMode','zero','seed',$SEED + round(1000*$factor),'makePreview',false);" >/tmp/closed_capacity_prepare_${tag}.log 2>&1 || {
        cat /tmp/closed_capacity_prepare_${tag}.log >&2 || true
        return 1
    }
}

if [[ ! -x build/src_mpcd_base ]]; then
    bash scripts/build_src_mpcd_base.sh
fi

mkdir -p "$INIT_ROOT"
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT"

for factor in $MASS_FACTORS; do
    tag=$(factor_tag "$factor")
    state="$INIT_ROOT/static_mf${tag}.smpcd"
    if [[ ! -f "$state" ]]; then
        if ! matlab_generate_state "$factor" "$state"; then
            cat >&2 <<MSG
Missing static overfill state:
  $state

Generate all required states from MATLAB, from the repository root:

  cd matlab
  prepare_closed_capacity_uniform_overfill_suite_0152( ...
      'outputDir', '../$INIT_ROOT', ...
      'Lx', $LX, 'Ly', $LY, ...
      'Nx', $NX, 'Ny', $NY, ...
      'gamma', $GAMMA, ...
      'massFactors', [$MASS_FACTORS], ...
      'capacityMultiplier', $STATE_CAPACITY_MULTIPLIER, ...
      'kBT', $KBT, ...
      'makePreview', true);
  cd ..

Then rerun:
  $0
MSG
            exit 2
        fi
    fi

    label="static_mf${tag}"
    out_dir="$RUN_ROOT/$label"
    params="$RUN_ROOT/params_${label}.kv"
    mkdir -p "$out_dir"

    cat > "$params" <<PARAMS
inputState = $state
outputDir = $out_dir

Lx = $LX
Ly = $LY
Nx = $NX
Ny = $NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $DT
nSteps = $STEPS
rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $SEED

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid

openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
openBoundaryOutletMode = neumann

projectionEnable = true
projectionOperator = elliptic_fv_cg
projectionMaxIterations = 800
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
projectionImmersedSolidMaskEnable = false
projectionImmersedSolidCloseCutFaces = false
projectionAllowUnmaskedImmersedSolid = true

closedCapacityResponseEnable = true
closedCapacityReferenceCellMass = $GAMMA
closedCapacityQ6Eta = $CAP_Q6_ETA
closedCapacityQ6Power = $CAP_Q6_POWER
closedCapacityMassRemapEta = $CAP_REMAP_ETA
closedCapacityMassRemapPower = $CAP_REMAP_POWER
closedCapacityMassGuardDisableOnOverfill = true
closedCapacityVirialKickEnable = false
closedCapacityVirialBaseK = $CAP_VIRIAL_K
closedCapacityVirialGain = $CAP_VIRIAL_GAIN
closedCapacityVirialEta = $CAP_VIRIAL_ETA
closedCapacityVirialPower = $CAP_VIRIAL_POWER
closedCapacityVirialKickStrength = 0.0
closedCapacityVirialMomentumCorrectionEnable = true
closedCapacityInletMassFluxEnable = false
closedCapacityInletMassFluxMultiplier = 0.0

immersedSolidEnable = false

wallAccommodation = $WALL_ACCOMMODATION
wallVpGamma = $GAMMA
wallVpMass = 1.0
wallKBT = $WALL_KBT
wallThermalNoise = 0.0

thermostatEnable = $THERMOSTAT_ENABLE
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $KBT

resamplingEnable = true
resamplingPopulationNMin = $RESAMP_N_MIN
resamplingPopulationNTarget = $RESAMP_N_TARGET
resamplingPopulationNMax = $RESAMP_N_MAX
resamplingPopulationMaxSplitsPerCell = 16
resamplingPopulationMaxSplitsPerStep = 200000
resamplingPopulationMaxExtractionsPerCell = 64
resamplingPopulationMaxExtractionsPerStep = 200000
resamplingTargetCellMass = $GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = 0.50
resamplingRichCellMassFraction = 1.50
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = 1
resamplingThermalRenormalizationEnable = $THERMAL_RENORM_ENABLE
resamplingMassGuardEnable = true
resamplingParticleMassMin = 0.5
resamplingParticleMassMax = 10.0
resamplingLatentActivationEnable = false

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_EVERY
numThreads = $THREADS
PARAMS

    echo "[0152] Running $label (massFactor=$factor)"
    ./build/src_mpcd_base "$params"
done

cat <<MSG
[0152] Closed-capacity static wall-load validation completed.
Run root: $RUN_ROOT

MATLAB analysis from repository root:
  cd matlab
  T = analyze_closed_capacity_wall_load_validation_0152('../$RUN_ROOT');
MSG

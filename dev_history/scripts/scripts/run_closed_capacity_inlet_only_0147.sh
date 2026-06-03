#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

RUN_ROOT=${RUN_ROOT:-runs/closed_capacity_inlet_only_0147}
INIT_ROOT=${INIT_ROOT:-init/injection_fill_resampling_0145}
STATE=${FILL_INITIAL_STATE:-$INIT_ROOT/initial_state_fluid_uniform_0145.smpcd}

LX=${FILL_LX:-1.0}
LY=${FILL_LY:-1.0}
NX=${FILL_NX:-48}
NY=${FILL_NY:-48}
GAMMA=${FILL_GAMMA:-20}
STEPS=${FILL_STEPS:-3000}
DT=${FILL_DT:-0.001}
KBT=${FILL_KBT:-0.001}
SEED=${FILL_SEED:-1470147}
SUMMARY_EVERY=${FILL_SUMMARY_EVERY:-25}
DUMP_EVERY=${FILL_DUMP_EVERY:-250}
THREADS=${FILL_THREADS:-8}

INLET_UX=${FILL_INLET_UX:-0.10}
INLET_SMIN=${FILL_INLET_SMIN:-0.10}
INLET_SMAX=${FILL_INLET_SMAX:-0.30}
RAMP_END_TIME=${FILL_RAMP_END_TIME:-0.2}

CAP_Q6_ETA=${CAP_Q6_ETA:-0.005}
CAP_Q6_POWER=${CAP_Q6_POWER:-2.0}
CAP_REMAP_ETA=${CAP_REMAP_ETA:-0.005}
CAP_REMAP_POWER=${CAP_REMAP_POWER:-2.0}
CAP_VIRIAL_K=${CAP_VIRIAL_K:-100.0}
CAP_VIRIAL_GAIN=${CAP_VIRIAL_GAIN:-20.0}
CAP_VIRIAL_ETA=${CAP_VIRIAL_ETA:-0.005}
CAP_VIRIAL_POWER=${CAP_VIRIAL_POWER:-2.0}
CAP_VIRIAL_KICK_STRENGTH=${CAP_VIRIAL_KICK_STRENGTH:-1.0}
CAP_INLET_FLUX_MULTIPLIER=${CAP_INLET_FLUX_MULTIPLIER:-1.0}

if [[ ! -x build/src_mpcd_base ]]; then
    bash scripts/build_src_mpcd_base.sh
fi

if [[ ! -f "$STATE" ]]; then
    cat >&2 <<MSG
Missing full-fluid initial state:
  $STATE

Generate it from MATLAB before launching this test:

  cd matlab
  prepare_injection_fill_fluid_uniform_0145( ...
      'output', '../$STATE', ...
      'Lx', $LX, 'Ly', $LY, ...
      'Nx', $NX, 'Ny', $NY, 'gamma', $GAMMA, ...
      'capacityMultiplier', 1.25, ...
      'kBT', $KBT, ...
      'seed', $SEED, ...
      'makePreview', true);
  cd ..

Then rerun:
  $0
MSG
    exit 2
fi

rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/closed_capacity_q6_resampling"
PARAMS="$RUN_ROOT/params_closed_capacity_q6_resampling.kv"

cat > "$PARAMS" <<PARAMS
inputState = $STATE
outputDir = $RUN_ROOT/closed_capacity_q6_resampling

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

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = $RAMP_END_TIME
inletVelocityRampInitialFactor = 0.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletKBT = -1.0
inletThermalNoise = 1.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 1
openBoundarySegment0 = left inlet $INLET_SMIN $INLET_SMAX $INLET_UX 0.0 0 1.0
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
closedCapacityVirialKickEnable = true
closedCapacityVirialBaseK = $CAP_VIRIAL_K
closedCapacityVirialGain = $CAP_VIRIAL_GAIN
closedCapacityVirialEta = $CAP_VIRIAL_ETA
closedCapacityVirialPower = $CAP_VIRIAL_POWER
closedCapacityVirialKickStrength = $CAP_VIRIAL_KICK_STRENGTH
closedCapacityVirialMomentumCorrectionEnable = true
closedCapacityInletMassFluxEnable = true
closedCapacityInletMassFluxMultiplier = $CAP_INLET_FLUX_MULTIPLIER

immersedSolidEnable = false

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 1.0

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $KBT

resamplingEnable = true
resamplingPopulationNMin = ${RESAMP_N_MIN:-14}
resamplingPopulationNTarget = ${RESAMP_N_TARGET:-20}
resamplingPopulationNMax = ${RESAMP_N_MAX:-26}
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}
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
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = 0.5
resamplingParticleMassMax = 10.0
resamplingLatentActivationEnable = false

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_EVERY
numThreads = $THREADS
PARAMS

./build/src_mpcd_base "$PARAMS"

cat <<MSG
[0147] Closed-capacity inlet-only smoke completed.
Run root: $RUN_ROOT
Key columns: totalMass, capacityOverfillRatio, q6ProjectionStrength,
capacityVirialKEffective, capacityVirialPressureMean,
capacityWallPressureTotalMeanAll, capacityWallForceTotalX/Y,
resampRemapMassCorrectionStrength.
MSG

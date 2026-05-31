#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AUTO_BUILD="${AUTO_BUILD:-1}"
CASE_STEPS="${CASE_STEPS:-12000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-200}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2000}"
NUM_THREADS="${NUM_THREADS:-8}"
RUN_ROOT="${RUN_ROOT:-runs/backward_step_hard_inlet_long_0067e}"
STATE_FILE="${STATE_FILE:-initial_state_backward_step_96x48_g20_kbt0p0025.smpcd}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}"

# Final 0067 long-run reference set:
#   1) Q6 hard inlet reference
#   2) Q9 hard inlet, soft/safe strength s=0.03
#   3) Q9+virial hard inlet, same Q9 strength s=0.03
#
# These parameters are deliberately local to backward-step + open boundary +
# immersed rectangle.  They do not replace the stronger Q9 settings validated
# in regular open-channel bulk cases without immersed solid.
Q9_STRENGTH_REF="${Q9_STRENGTH_REF:-0.03}"
Q9_BETA="${Q9_BETA:-0.001}"
Q9_OPEN_EXCLUSION_CELLS="${Q9_OPEN_EXCLUSION_CELLS:-5}"
Q9_IMMERSED_HALO_CELLS="${Q9_IMMERSED_HALO_CELLS:-5}"
Q9_MIN_CELL_MASS="${Q9_MIN_CELL_MASS:-8.0}"
Q9_CORRECTION_LIMITER="${Q9_CORRECTION_LIMITER:-0.003}"

VIRIAL_K="${VIRIAL_K:-0.50}"
VIRIAL_BETA="${VIRIAL_BETA:-0.05}"
VIRIAL_OPEN_EXCLUSION_CELLS="${VIRIAL_OPEN_EXCLUSION_CELLS:-5}"

if [[ "$AUTO_BUILD" == "1" ]]; then
  ./scripts/build_src_mpcd_base.sh
fi

if [[ ! -x build/src_mpcd_base ]]; then
  echo "Missing build/src_mpcd_base. Run ./scripts/build_src_mpcd_base.sh first." >&2
  exit 1
fi

if [[ ! -f "$STATE_FILE" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    matlab -batch "cd('matlab'); generate_backward_step_state('output','../${STATE_FILE}','kBT',0.0025);"
  else
    echo "Missing $STATE_FILE and matlab is not available to generate it." >&2
    exit 1
  fi
fi

mkdir -p "$RUN_ROOT/params"

write_case() {
  local label="$1"
  local method="$2"
  local q9="$3"
  local virial="$4"
  local q9_strength="$5"
  local out_dir="$RUN_ROOT/$label"
  local params_file="$RUN_ROOT/params/${label}.kv"

  cat > "$params_file" <<EOF_KV
inputState = ${STATE_FILE}
outputDir = ${out_dir}

Lx = 2.0
Ly = 1.0
Nx = 96
Ny = 48

dt = 0.001
nSteps = ${CASE_STEPS}
rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = 12345

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

inletUxLeft = 0.05
inletUyLeft = 0.0
inletKBT = 0.0025
inletThermalNoise = 1.0
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = 5
inletTargetOccupancy = 20
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = true
targetMeanUx = 0.05
targetMeanUy = 0.0

projectionEnable = true
projectionOperator = elliptic_fv_cg
projectionMaxIterations = 700
projectionTolerance = 1.0e-9
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 0.50
projectionImmersedSolidMaskEnable = true
projectionAllowUnmaskedImmersedSolid = false
projectionImmersedSolidFluidFractionThreshold = 0.5
projectionImmersedSolidCloseCutFaces = true

q9MassFluxProjectionEnable = ${q9}
q9MassFluxProjectionStrength = ${q9_strength}
q9OpenBoundaryExclusionCells = 5
q9ImmersedSolidHaloCells = 5
q9MinCellMassForCorrection = 8.0
q9CorrectionVelocityLimiter = 0.003
q9LowMassTreatment = ramp_floor
q9MassFloorForCorrection = 8.0
q9LowMassRampStart = 1.0
q9LowMassRampEnd = 8.0
q9DensityRelaxationBeta = ${Q9_BETA}
q9OpenBoundaryExclusionCells = ${Q9_OPEN_EXCLUSION_CELLS}
q9ImmersedSolidHaloCells = ${Q9_IMMERSED_HALO_CELLS}
q9MinCellMassForCorrection = ${Q9_MIN_CELL_MASS}
q9CorrectionVelocityLimiter = ${Q9_CORRECTION_LIMITER}
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 4
q9EllipticLowPassPasses = 1
q9MomentumCorrectionEnable = true

virialDiagnosticsEnable = ${virial}
virialKickEnable = ${virial}
virialK = ${VIRIAL_K}
virialBeta = ${VIRIAL_BETA}
virialOpenBoundaryExclusionCells = ${VIRIAL_OPEN_EXCLUSION_CELLS}

immersedSolidEnable = true
immersedSolidShape = rectangle
immersedSolidXMin = 0.25
immersedSolidXMax = 0.65
immersedSolidYMin = 0.0
immersedSolidYMax = 0.50
immersedSolidFractionSamples = 4
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = 1.0
wallVpGamma = 0.0
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 1.0

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = 0.0025

summaryEvery = ${SUMMARY_EVERY}
dumpStateEvery = ${DUMP_STATE_EVERY}
numThreads = ${NUM_THREADS}
EOF_KV

  echo "[0067e] running ${label}"
  echo "[0067e] params: ${params_file}"

  if [[ "$CONTINUE_ON_ERROR" == "1" ]]; then
    set +e
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/${label}.log"
    local rc=${PIPESTATUS[0]}
    set -e
    if [[ "$rc" -ne 0 ]]; then
      echo "[0067e] WARNING: ${label} failed with exit code ${rc}" | tee -a "$RUN_ROOT/FAILED_CASES.txt"
      return 0
    fi
  else
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/${label}.log"
  fi
}

SECONDS=0
write_case "backstep_q6_hard_inlet_long" "q6" "false" "false" "0.0"
write_case "backstep_q9_hard_inlet_s003_long" "q9" "true" "false" "${Q9_STRENGTH_REF}"
write_case "backstep_q9_virial_hard_inlet_s003_long" "q9_virial" "true" "true" "${Q9_STRENGTH_REF}"

elapsed=$SECONDS
printf '[0067e] done in %02d:%02d:%02d\n' $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))
echo "[0067e] Analyze with: cd matlab && S = analyze_backward_step_hard_inlet_validation_0067('root','..','runRoot','${RUN_ROOT}');"

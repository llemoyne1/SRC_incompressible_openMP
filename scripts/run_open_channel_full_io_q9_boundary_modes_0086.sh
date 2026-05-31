#!/usr/bin/env bash
set -euo pipefail

# 0086 long diagnostic matrix for the simplified full-inlet/full-outlet slip channel.
#
# Purpose
# -------
# The 0085 short sweep showed that Q6 is clean while Q9 introduces a persistent
# density/velocity pattern even in a full-height inlet/outlet channel with slip
# walls.  This script runs a longer, more discriminating matrix without touching
# the C++ core.
#
# Default matrix:
#   1. Q6 baseline, exclusion=3
#   2. Q9 only, beta=5e-4, exclusion=3
#   3. Q9 only, beta=5e-4, exclusion=1
#   4. Q9 only, beta=5e-4, exclusion=0
#   5. Q9 only, beta=0,    exclusion=0
#   6. Q9+virial, beta=5e-4, q9/virial exclusion=1
#
# The main questions are:
#   - Does the Q9 artifact disappear when q9OpenBoundaryExclusionCells=0?
#   - Does the artifact persist when q9DensityRelaxationBeta=0?
#   - Does virial change the already-isolated Q9 behavior?

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AUTO_BUILD="${AUTO_BUILD:-1}"
AUTO_ANALYZE="${AUTO_ANALYZE:-0}"
CASE_STEPS="${CASE_STEPS:-80000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-5000}"
NUM_THREADS="${NUM_THREADS:-8}"
RUN_ROOT="${RUN_ROOT:-runs/open_channel_full_io_q9_boundary_modes_0086_g30}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"

Lx="${Lx:-2.0}"
Ly="${Ly:-1.0}"
Nx="${Nx:-48}"
Ny="${Ny:-24}"
GAMMA="${GAMMA:-30}"
DT="${DT:-0.001}"
KBT="${KBT:-0.0025}"
UIN="${UIN:-0.05}"
INIT_UX="${INIT_UX:-0.0}"

INLET_RAMP_ENABLE="${INLET_RAMP_ENABLE:-true}"
INLET_RAMP_START_TIME="${INLET_RAMP_START_TIME:-0.0}"
INLET_RAMP_END_TIME="${INLET_RAMP_END_TIME:-40.0}"
INLET_RAMP_INITIAL_FACTOR="${INLET_RAMP_INITIAL_FACTOR:-0.0}"
INLET_RAMP_FINAL_FACTOR="${INLET_RAMP_FINAL_FACTOR:-1.0}"
INLET_RAMP_PROFILE="${INLET_RAMP_PROFILE:-smoothstep}"

safe_tag() {
  local x="$1"
  x="${x//-/m}"
  x="${x//./p}"
  echo "$x"
}

KBT_TAG="$(safe_tag "$KBT")"
UX_TAG="$(safe_tag "$INIT_UX")"
STATE_FILE="${STATE_FILE:-initial_state_open_channel_full_io_slip_${Nx}x${Ny}_g${GAMMA}_kbt${KBT_TAG}_ux${UX_TAG}.smpcd}"

INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-3}"

Q6_STRENGTH="${Q6_STRENGTH:-1.0}"
Q9_STRENGTH="${Q9_STRENGTH:-1.0}"
Q9_BETA_DEFAULT="${Q9_BETA_DEFAULT:-0.0005}"
Q9_LOWK_MAX_INDEX="${Q9_LOWK_MAX_INDEX:-2}"
Q9_ELLIPTIC_LOW_PASS_PASSES="${Q9_ELLIPTIC_LOW_PASS_PASSES:-1}"

Q9_CORRECTION_LIMITER_MODE="${Q9_CORRECTION_LIMITER_MODE:-thermal_soft}"
Q9_CORRECTION_LIMITER_OVER_THERMAL="${Q9_CORRECTION_LIMITER_OVER_THERMAL:-0.5}"
Q9_CORRECTION_LIMITER_THERMAL_KBT="${Q9_CORRECTION_LIMITER_THERMAL_KBT:-0.0}"
Q9_CORRECTION_LIMITER="${Q9_CORRECTION_LIMITER:-0.0}"

Q9_LOW_MASS_TREATMENT="${Q9_LOW_MASS_TREATMENT:-ramp_floor}"
Q9_MIN_CELL_MASS_OVER_GAMMA="${Q9_MIN_CELL_MASS_OVER_GAMMA:-0.40}"
Q9_MASS_FLOOR_OVER_GAMMA="${Q9_MASS_FLOOR_OVER_GAMMA:-0.40}"
Q9_LOW_MASS_RAMP_START_OVER_GAMMA="${Q9_LOW_MASS_RAMP_START_OVER_GAMMA:-0.05}"
Q9_LOW_MASS_RAMP_END_OVER_GAMMA="${Q9_LOW_MASS_RAMP_END_OVER_GAMMA:-0.40}"

Q9_MIN_CELL_MASS="${Q9_MIN_CELL_MASS:-0.0}"
Q9_MASS_FLOOR="${Q9_MASS_FLOOR:-0.0}"
Q9_LOW_MASS_RAMP_START="${Q9_LOW_MASS_RAMP_START:-0.0}"
Q9_LOW_MASS_RAMP_END="${Q9_LOW_MASS_RAMP_END:-0.0}"

VIRIAL_K="${VIRIAL_K:-0.50}"
VIRIAL_BETA="${VIRIAL_BETA:-0.05}"
KEEP_MEAN_FLOW="${KEEP_MEAN_FLOW:-false}"

# Default case switches.  Turn any case off with RUN_*=0.
RUN_Q6_EXCL3="${RUN_Q6_EXCL3:-1}"
RUN_Q9_EXCL3_BETA="${RUN_Q9_EXCL3_BETA:-1}"
RUN_Q9_EXCL1_BETA="${RUN_Q9_EXCL1_BETA:-1}"
RUN_Q9_EXCL0_BETA="${RUN_Q9_EXCL0_BETA:-1}"
RUN_Q9_EXCL0_BETA0="${RUN_Q9_EXCL0_BETA0:-1}"
RUN_Q9_VIRIAL_EXCL1_BETA="${RUN_Q9_VIRIAL_EXCL1_BETA:-1}"

if [[ "$AUTO_BUILD" == "1" ]]; then
  ./scripts/build_src_mpcd_base.sh
fi

if [[ ! -x build/src_mpcd_base ]]; then
  echo "Missing build/src_mpcd_base. Run ./scripts/build_src_mpcd_base.sh first." >&2
  exit 1
fi

if [[ ! -f "$STATE_FILE" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    matlab -batch "cd('matlab'); generate_open_channel_classic_state('output','../${STATE_FILE}','Lx',${Lx},'Ly',${Ly},'Nx',${Nx},'Ny',${Ny},'gamma',${GAMMA},'kBT',${KBT},'inletUx',${INIT_UX});"
  else
    cat >&2 <<MSG
Missing $STATE_FILE and matlab is not available to generate it.
Generate it manually from MATLAB with:

  cd matlab
  generate_open_channel_classic_state('output','../${STATE_FILE}', ...
      'Lx',${Lx},'Ly',${Ly},'Nx',${Nx},'Ny',${Ny}, ...
      'gamma',${GAMMA},'kBT',${KBT},'inletUx',${INIT_UX});
  cd ..

MSG
    exit 2
  fi
fi

mkdir -p "$RUN_ROOT/params" "$RUN_ROOT/logs"

write_case() {
  local label="$1"
  local method="$2"
  local q9="$3"
  local virial="$4"
  local q9_excl="$5"
  local virial_excl="$6"
  local q9_beta="$7"
  local out_dir="$RUN_ROOT/$label"
  local params_file="$RUN_ROOT/params/${label}.kv"

  cat > "$params_file" <<EOF_KV
inputState = ${STATE_FILE}
outputDir = ${out_dir}

Lx = ${Lx}
Ly = ${Ly}
Nx = ${Nx}
Ny = ${Ny}

dt = ${DT}
nSteps = ${CASE_STEPS}
rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = 12345

bcLeft = inlet
bcRight = outlet
bcBottom = specular
bcTop = specular
openBoundaryApertureEnable = false

inletUxLeft = ${UIN}
inletUyLeft = 0.0
inletUxRight = ${UIN}
inletUyRight = 0.0
inletVelocityRampEnable = ${INLET_RAMP_ENABLE}
inletVelocityRampStartTime = ${INLET_RAMP_START_TIME}
inletVelocityRampEndTime = ${INLET_RAMP_END_TIME}
inletVelocityRampInitialFactor = ${INLET_RAMP_INITIAL_FACTOR}
inletVelocityRampFinalFactor = ${INLET_RAMP_FINAL_FACTOR}
inletVelocityRampProfile = ${INLET_RAMP_PROFILE}
inletKBT = ${KBT}
inletThermalNoise = 1.0
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = ${INLET_RESERVOIR_CELLS}
inletTargetOccupancy = ${GAMMA}
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = ${KEEP_MEAN_FLOW}
targetMeanUx = ${UIN}
targetMeanUy = 0.0

projectionEnable = true
projectionOperator = elliptic_fv_cg
projectionMaxIterations = 500
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = ${Q6_STRENGTH}
projectionImmersedSolidMaskEnable = false
projectionAllowUnmaskedImmersedSolid = false
projectionImmersedSolidFluidFractionThreshold = 0.5
projectionImmersedSolidCloseCutFaces = false

q9MassFluxProjectionEnable = ${q9}
q9MassFluxProjectionStrength = ${Q9_STRENGTH}
q9DensityRelaxationBeta = ${q9_beta}
q9OpenBoundaryExclusionCells = ${q9_excl}
q9ImmersedSolidHaloCells = 0
q9ReferenceGamma = ${GAMMA}
q9MinCellMassForCorrection = ${Q9_MIN_CELL_MASS}
q9CorrectionVelocityLimiter = ${Q9_CORRECTION_LIMITER}
q9CorrectionLimiterMode = ${Q9_CORRECTION_LIMITER_MODE}
q9CorrectionVelocityLimiterOverThermal = ${Q9_CORRECTION_LIMITER_OVER_THERMAL}
q9CorrectionLimiterThermalKBT = ${Q9_CORRECTION_LIMITER_THERMAL_KBT}
q9LowMassTreatment = ${Q9_LOW_MASS_TREATMENT}
q9MassFloorForCorrection = ${Q9_MASS_FLOOR}
q9LowMassRampStart = ${Q9_LOW_MASS_RAMP_START}
q9LowMassRampEnd = ${Q9_LOW_MASS_RAMP_END}
q9MinCellMassForCorrectionOverGamma = ${Q9_MIN_CELL_MASS_OVER_GAMMA}
q9MassFloorForCorrectionOverGamma = ${Q9_MASS_FLOOR_OVER_GAMMA}
q9LowMassRampStartOverGamma = ${Q9_LOW_MASS_RAMP_START_OVER_GAMMA}
q9LowMassRampEndOverGamma = ${Q9_LOW_MASS_RAMP_END_OVER_GAMMA}
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = ${Q9_LOWK_MAX_INDEX}
q9EllipticLowPassPasses = ${Q9_ELLIPTIC_LOW_PASS_PASSES}
q9MomentumCorrectionEnable = true

virialDiagnosticsEnable = ${virial}
virialKickEnable = ${virial}
virialK = ${VIRIAL_K}
virialBeta = ${VIRIAL_BETA}
virialRhoEOSRefMode = current_uniform
virialRhoUniformMode = particle_mean
virialDriveTargetMode = current_uniform
virialRhoKickMode = uniform_now
virialRhoKickMinFraction = 0.10
virialMomentumCorrectionEnable = true
virialOpenBoundaryExclusionCells = ${virial_excl}

immersedSolidEnable = false
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

wallVpEnable = false
wallAccommodation = 0.0
wallVpGamma = 0.0
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 1.0
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = 0.0
wallUyTop = 0.0

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = ${KBT}

summaryEvery = ${SUMMARY_EVERY}
dumpStateEvery = ${DUMP_STATE_EVERY}
numThreads = ${NUM_THREADS}
EOF_KV

  echo "[0086] running ${label}"
  echo "[0086] method=${method}, q9=${q9}, virial=${virial}, q9Excl=${q9_excl}, virialExcl=${virial_excl}, beta=${q9_beta}"

  if [[ "$CONTINUE_ON_ERROR" == "1" ]]; then
    set +e
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/logs/${label}.log"
    local rc=${PIPESTATUS[0]}
    set -e
    if [[ "$rc" -ne 0 ]]; then
      echo "[0086] WARNING: ${label} failed with exit code ${rc}" | tee -a "$RUN_ROOT/FAILED_CASES.txt"
      return 0
    fi
  else
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/logs/${label}.log"
  fi
}

echo "[0086] full-IO slip Q9/open-boundary long diagnostic"
echo "[0086] Uin=Uex=${UIN}; ramp ${INLET_RAMP_INITIAL_FACTOR}->${INLET_RAMP_FINAL_FACTOR}, t=${INLET_RAMP_START_TIME}->${INLET_RAMP_END_TIME}, profile=${INLET_RAMP_PROFILE}"
echo "[0086] Q9 limiter: mode=${Q9_CORRECTION_LIMITER_MODE}, overThermal=${Q9_CORRECTION_LIMITER_OVER_THERMAL}"
echo "[0086] runRoot=${RUN_ROOT}; steps=${CASE_STEPS}; dumpEvery=${DUMP_STATE_EVERY}"

SECONDS=0
TAG="u${UIN//./p}_${Nx}x${Ny}"
BETA_TAG="b${Q9_BETA_DEFAULT//./p}"

if [[ "$RUN_Q6_EXCL3" == "1" ]]; then
  write_case "openchan_q6_fullio_slip_excl3_${TAG}" "q6" "false" "false" "3" "3" "0.0"
fi
if [[ "$RUN_Q9_EXCL3_BETA" == "1" ]]; then
  write_case "openchan_q9_fullio_slip_excl3_${BETA_TAG}_${TAG}" "q9" "true" "false" "3" "3" "${Q9_BETA_DEFAULT}"
fi
if [[ "$RUN_Q9_EXCL1_BETA" == "1" ]]; then
  write_case "openchan_q9_fullio_slip_excl1_${BETA_TAG}_${TAG}" "q9" "true" "false" "1" "1" "${Q9_BETA_DEFAULT}"
fi
if [[ "$RUN_Q9_EXCL0_BETA" == "1" ]]; then
  write_case "openchan_q9_fullio_slip_excl0_${BETA_TAG}_${TAG}" "q9" "true" "false" "0" "1" "${Q9_BETA_DEFAULT}"
fi
if [[ "$RUN_Q9_EXCL0_BETA0" == "1" ]]; then
  write_case "openchan_q9_fullio_slip_excl0_b0_${TAG}" "q9" "true" "false" "0" "1" "0.0"
fi
if [[ "$RUN_Q9_VIRIAL_EXCL1_BETA" == "1" ]]; then
  write_case "openchan_q9_virial_fullio_slip_excl1_${BETA_TAG}_${TAG}" "q9_virial" "true" "true" "1" "1" "${Q9_BETA_DEFAULT}"
fi

elapsed=$SECONDS
printf '[0086] done in %02d:%02d:%02d\n' $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))

echo "[0086] Analyze with: cd matlab && R = analyze_open_channel_full_io_q9_boundary_modes_0086('root','..','runRoot','${RUN_ROOT}');"

if [[ "$AUTO_ANALYZE" == "1" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    matlab -batch "cd('matlab'); analyze_open_channel_full_io_q9_boundary_modes_0086('root','..','runRoot','${RUN_ROOT}');"
  else
    echo "[0086] AUTO_ANALYZE=1 requested but matlab is not available." >&2
  fi
fi

#!/usr/bin/env bash
set -euo pipefail

# 0079 Poiseuille/open-channel hard-inlet / free-outlet validation with a
# progressive inlet velocity ramp.
# Scope: inlet/outlet only, no immersed solid.
# Purpose: avoid the impulsive hard-inlet start while preserving the final
# validated Q6/Q9 model parameters from feature/elliptic-q6-core.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AUTO_BUILD="${AUTO_BUILD:-1}"
AUTO_ANALYZE="${AUTO_ANALYZE:-0}"
CASE_STEPS="${CASE_STEPS:-60000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-5000}"
NUM_THREADS="${NUM_THREADS:-8}"
RUN_ROOT="${RUN_ROOT:-runs/poiseuille_hard_inlet_free_outlet_ramped_q9_0079}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"

# Fixed physical channel, reduced grid for response-time validation.
Lx="${Lx:-2.0}"
Ly="${Ly:-1.0}"
Nx="${Nx:-48}"
Ny="${Ny:-24}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.001}"
KBT="${KBT:-0.0025}"
UIN="${UIN:-0.05}"
INIT_UX="${INIT_UX:-0.0}"

# Progressive start-up.  Default ramp duration is 20 time units, i.e. half an
# advective time for Lx=2, Uin=0.05.  For a short technical smoke, override
# INLET_RAMP_END_TIME=1.0 so the ramp reaches Uin during the smoke.
INLET_RAMP_ENABLE="${INLET_RAMP_ENABLE:-true}"
INLET_RAMP_START_TIME="${INLET_RAMP_START_TIME:-0.0}"
INLET_RAMP_END_TIME="${INLET_RAMP_END_TIME:-20.0}"
INLET_RAMP_INITIAL_FACTOR="${INLET_RAMP_INITIAL_FACTOR:-0.0}"
INLET_RAMP_FINAL_FACTOR="${INLET_RAMP_FINAL_FACTOR:-1.0}"
INLET_RAMP_PROFILE="${INLET_RAMP_PROFILE:-smoothstep}"

safe_tag() {
  local x="$1"
  x="${x//- /m}"
  x="${x//-/m}"
  x="${x//./p}"
  echo "$x"
}

KBT_TAG="$(safe_tag "$KBT")"
UX_TAG="$(safe_tag "$INIT_UX")"
STATE_FILE="${STATE_FILE:-initial_state_poiseuille_hard_inlet_${Nx}x${Ny}_g${GAMMA}_kbt${KBT_TAG}_ux${UX_TAG}.smpcd}"

# Boundary bands.  These are open-boundary settings, not immersed-solid settings.
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-3}"
Q9_OPEN_EXCLUSION_CELLS="${Q9_OPEN_EXCLUSION_CELLS:-3}"
VIRIAL_OPEN_EXCLUSION_CELLS="${VIRIAL_OPEN_EXCLUSION_CELLS:-3}"

# Validated Q6/Q9 model parameters from feature/elliptic-q6-core Poiseuille.
Q6_STRENGTH="${Q6_STRENGTH:-1.0}"
Q9_STRENGTH="${Q9_STRENGTH:-1.0}"
Q9_BETA="${Q9_BETA:-0.0005}"
Q9_LOWK_MAX_INDEX="${Q9_LOWK_MAX_INDEX:-2}"
Q9_ELLIPTIC_LOW_PASS_PASSES="${Q9_ELLIPTIC_LOW_PASS_PASSES:-1}"
Q9_CORRECTION_LIMITER="${Q9_CORRECTION_LIMITER:-0.0}"

# Low-mass regularization remains available for hard-open-boundary runs.
# The defaults are now gamma-relative so that gamma=20, 30, 40 use the same
# dimensionless safety policy.  They reproduce the previous gamma=20 values:
# start=1, end=floor=min=8.
Q9_LOW_MASS_TREATMENT="${Q9_LOW_MASS_TREATMENT:-ramp_floor}"
Q9_MIN_CELL_MASS_OVER_GAMMA="${Q9_MIN_CELL_MASS_OVER_GAMMA:-0.40}"
Q9_MASS_FLOOR_OVER_GAMMA="${Q9_MASS_FLOOR_OVER_GAMMA:-0.40}"
Q9_LOW_MASS_RAMP_START_OVER_GAMMA="${Q9_LOW_MASS_RAMP_START_OVER_GAMMA:-0.05}"
Q9_LOW_MASS_RAMP_END_OVER_GAMMA="${Q9_LOW_MASS_RAMP_END_OVER_GAMMA:-0.40}"

# Absolute legacy overrides remain available for explicit back-compat tests.
Q9_MIN_CELL_MASS="${Q9_MIN_CELL_MASS:-0.0}"
Q9_MASS_FLOOR="${Q9_MASS_FLOOR:-0.0}"
Q9_LOW_MASS_RAMP_START="${Q9_LOW_MASS_RAMP_START:-0.0}"
Q9_LOW_MASS_RAMP_END="${Q9_LOW_MASS_RAMP_END:-0.0}"

# Virial closure defaults used in the current inlet/outlet branch.
VIRIAL_K="${VIRIAL_K:-0.50}"
VIRIAL_BETA="${VIRIAL_BETA:-0.05}"

# By default we test the inlet/outlet response without a global mean-flow reset.
# Set KEEP_MEAN_FLOW=true only for a comparison run.
KEEP_MEAN_FLOW="${KEEP_MEAN_FLOW:-false}"

RUN_CLASSIC="${RUN_CLASSIC:-0}"
RUN_Q6="${RUN_Q6:-0}"
RUN_Q9="${RUN_Q9:-0}"
RUN_Q9_VIRIAL="${RUN_Q9_VIRIAL:-1}"

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
bcBottom = solid
bcTop = solid

inletUxLeft = ${UIN}
inletUyLeft = 0.0
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

method = ${method}
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
q9DensityRelaxationBeta = ${Q9_BETA}
q9OpenBoundaryExclusionCells = ${Q9_OPEN_EXCLUSION_CELLS}
q9ImmersedSolidHaloCells = 0
q9ReferenceGamma = ${GAMMA}
q9MinCellMassForCorrection = ${Q9_MIN_CELL_MASS}
q9CorrectionVelocityLimiter = ${Q9_CORRECTION_LIMITER}
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
virialOpenBoundaryExclusionCells = ${VIRIAL_OPEN_EXCLUSION_CELLS}

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

wallAccommodation = 1.0
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

  echo "[0079] running ${label}"
  echo "[0079] params: ${params_file}"

  if [[ "$CONTINUE_ON_ERROR" == "1" ]]; then
    set +e
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/logs/${label}.log"
    local rc=${PIPESTATUS[0]}
    set -e
    if [[ "$rc" -ne 0 ]]; then
      echo "[0079] WARNING: ${label} failed with exit code ${rc}" | tee -a "$RUN_ROOT/FAILED_CASES.txt"
      return 0
    fi
  else
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/logs/${label}.log"
  fi
}

echo "[0079] inlet velocity ramp: enable=${INLET_RAMP_ENABLE}, factor ${INLET_RAMP_INITIAL_FACTOR}->${INLET_RAMP_FINAL_FACTOR}, t=${INLET_RAMP_START_TIME}->${INLET_RAMP_END_TIME}, profile=${INLET_RAMP_PROFILE}"

SECONDS=0
if [[ "$RUN_CLASSIC" == "1" ]]; then
  write_case "poiseuille_classic_ramped_hard_inlet_u${UIN//./p}_48x24" "classic" "false" "false"
fi
if [[ "$RUN_Q6" == "1" ]]; then
  write_case "poiseuille_q6_ramped_hard_inlet_u${UIN//./p}_48x24" "q6" "false" "false"
fi
if [[ "$RUN_Q9" == "1" ]]; then
  write_case "poiseuille_q9_ramped_hard_inlet_u${UIN//./p}_48x24" "q9" "true" "false"
fi
if [[ "$RUN_Q9_VIRIAL" == "1" ]]; then
  write_case "poiseuille_q9_virial_ramped_hard_inlet_u${UIN//./p}_48x24" "q9_virial" "true" "true"
fi

elapsed=$SECONDS
printf '[0079] done in %02d:%02d:%02d\n' $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))

echo "[0079] Analyze with: cd matlab && R = analyze_poiseuille_hard_inlet_free_outlet_0077('root','..','runRoot','${RUN_ROOT}');"

if [[ "$AUTO_ANALYZE" == "1" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    matlab -batch "cd('matlab'); analyze_poiseuille_hard_inlet_free_outlet_0077('root','..','runRoot','${RUN_ROOT}');"
  else
    echo "[0079] AUTO_ANALYZE=1 requested but matlab is not available." >&2
  fi
fi

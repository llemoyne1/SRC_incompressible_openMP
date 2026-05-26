#!/usr/bin/env bash
set -euo pipefail

# 0088 open-channel full inlet/outlet with VP/no-slip walls and Poiseuille inlet/outlet profile.
#
# Purpose
# -------
# The 0086 boundary-mode sweep showed that Q9 is clean when
# q9OpenBoundaryExclusionCells=0, while any inactive open-boundary band can
# act as a numerical impedance/interface.  This runner tests the complete
# q9_virial method with both Q9 and virial active up to the full open boundary:
#
#   q9OpenBoundaryExclusionCells = 0
#   virialOpenBoundaryExclusionCells = 0
#
# The geometry remains full-height inlet/outlet with no immersed solid, but the
# top/bottom boundaries are now solid thermal/VP-like walls.  The imposed
# x-face velocity/flux profile is Poiseuille in y and uses UIN as the cross-
# section mean velocity.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AUTO_BUILD="${AUTO_BUILD:-0}"
AUTO_ANALYZE="${AUTO_ANALYZE:-0}"
CASE_STEPS="${CASE_STEPS:-60000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
NUM_THREADS="${NUM_THREADS:-12}"
RUN_ROOT="${RUN_ROOT:-runs/open_channel_jet}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"

# Channel and particle scales.  Default gamma=30 matches the recent open-channel
# hard-inlet tests; override GAMMA=20 for direct comparison.
Lx="${Lx:-4.0}"
Ly="${Ly:-1.0}"
Nx="${Nx:-96}"
Ny="${Ny:-24}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.001}"
KBT="${KBT:-0.0025}"
UIN="${UIN:-0.05}"
INIT_UX="${INIT_UX:-0.0}"

# Smooth start-up avoids the impulsive hard-inlet shock while preserving the
# final target Uin=Uex.  For smokes, use INLET_RAMP_END_TIME=1.0.
INLET_RAMP_ENABLE="${INLET_RAMP_ENABLE:-true}"
INLET_RAMP_START_TIME="${INLET_RAMP_START_TIME:-0.0}"
INLET_RAMP_END_TIME="${INLET_RAMP_END_TIME:-10.0}"
INLET_RAMP_INITIAL_FACTOR="${INLET_RAMP_INITIAL_FACTOR:-0.0}"
INLET_RAMP_FINAL_FACTOR="${INLET_RAMP_FINAL_FACTOR:-1.0}"
INLET_RAMP_PROFILE="${INLET_RAMP_PROFILE:-smoothstep}"
INLET_VELOCITY_SPATIAL_PROFILE="${INLET_VELOCITY_SPATIAL_PROFILE:-poiseuille_y_mean}"

safe_tag() {
  local x="$1"
  x="${x//- /m}"
  x="${x//-/m}"
  x="${x//./p}"
  echo "$x"
}

KBT_TAG="$(safe_tag "$KBT")"
UX_TAG="$(safe_tag "$INIT_UX")"
STATE_FILE="${STATE_FILE:-initial_state_open_channel_full_io_vp_poiseuille_${Nx}x${Ny}_g${GAMMA}_kbt${KBT_TAG}_ux${UX_TAG}.smpcd}"

# Open-boundary bands are full height here.  The reservoir width is still a few
# cells in x, but there is no aperture trimming in y.
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-3}"
Q9_OPEN_EXCLUSION_CELLS="${Q9_OPEN_EXCLUSION_CELLS:-0}"
VIRIAL_OPEN_EXCLUSION_CELLS="${VIRIAL_OPEN_EXCLUSION_CELLS:-0}"

# Segmented left/right open-boundary apertures.  Defaults close two cell rows
# near each horizontal wall for Ny=24, avoiding the wall/outlet corner
# contradiction.  For other Ny, override LEFT_OPEN_YMIN/YMAX and
# RIGHT_OPEN_YMIN/YMAX explicitly.
OPEN_APERTURE_ENABLE="${OPEN_APERTURE_ENABLE:-true}"
LEFT_OPEN_YMIN="${LEFT_OPEN_YMIN:-0.4}"
LEFT_OPEN_YMAX="${LEFT_OPEN_YMAX:-0.6}"
RIGHT_OPEN_YMIN="${RIGHT_OPEN_YMIN:-0.2}"
RIGHT_OPEN_YMAX="${RIGHT_OPEN_YMAX:-0.8}"



# Validated Q6/Q9 model parameters from feature/elliptic-q6-core Poiseuille.
Q6_STRENGTH="${Q6_STRENGTH:-1.0}"
Q9_STRENGTH="${Q9_STRENGTH:-1.0}"
Q9_BETA="${Q9_BETA:-0.0005}"
Q9_LOWK_MAX_INDEX="${Q9_LOWK_MAX_INDEX:-2}"
Q9_ELLIPTIC_LOW_PASS_PASSES="${Q9_ELLIPTIC_LOW_PASS_PASSES:-1}"

# Universal Q9 correction limiter.  C=0.5 gives dU_limit=0.025 for kBT=0.0025.
Q9_CORRECTION_LIMITER_MODE="${Q9_CORRECTION_LIMITER_MODE:-thermal_soft}"
Q9_CORRECTION_LIMITER_OVER_THERMAL="${Q9_CORRECTION_LIMITER_OVER_THERMAL:-0.5}"
Q9_CORRECTION_LIMITER_THERMAL_KBT="${Q9_CORRECTION_LIMITER_THERMAL_KBT:-0.0}"
Q9_CORRECTION_LIMITER="${Q9_CORRECTION_LIMITER:-0.0}"

# Gamma-relative low-mass policy.  For gamma=30: start=1.5, end/floor/min=12.
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

# Do not reset global mean flow in this diagnostic.  The imposed open-boundary
# fluxes already set Uin=Uex in Q6/Q9.
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

openBoundaryApertureEnable = ${OPEN_APERTURE_ENABLE}
leftOpenYMin = ${LEFT_OPEN_YMIN}
leftOpenYMax = ${LEFT_OPEN_YMAX}
rightOpenYMin = ${RIGHT_OPEN_YMIN}
rightOpenYMax = ${RIGHT_OPEN_YMAX}
bottomOpenXMin = 0.0
bottomOpenXMax = ${Lx}
topOpenXMin = 0.0
topOpenXMax = ${Lx}

# Full-height hard inlet.  The matching Uex=Uin condition is imposed in Q6/Q9
# by the balanced open-boundary flux pair.  The spatial profile is Poiseuille
# in y and UIN is interpreted as the cross-section mean velocity.
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
inletVelocitySpatialProfile = ${INLET_VELOCITY_SPATIAL_PROFILE}
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

# Solid thermal top/bottom walls.  This is the first no-slip/VP-like
# compatibility test after the clean full-IO slip baseline.
wallVpEnable = true
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

  echo "[0088] running ${label}"
  echo "[0088] params: ${params_file}"

  if [[ "$CONTINUE_ON_ERROR" == "1" ]]; then
    set +e
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/logs/${label}.log"
    local rc=${PIPESTATUS[0]}
    set -e
    if [[ "$rc" -ne 0 ]]; then
      echo "[0088] WARNING: ${label} failed with exit code ${rc}" | tee -a "$RUN_ROOT/FAILED_CASES.txt"
      return 0
    fi
  else
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/logs/${label}.log"
  fi
}

echo "[0088] full-height inlet/outlet, VP/no-slip y walls, Poiseuille x-profile, no immersed solid"
echo "[0088] Umean=Uin=Uex=${UIN}; spatialProfile=${INLET_VELOCITY_SPATIAL_PROFILE}; ramp ${INLET_RAMP_INITIAL_FACTOR}->${INLET_RAMP_FINAL_FACTOR}, t=${INLET_RAMP_START_TIME}->${INLET_RAMP_END_TIME}, profile=${INLET_RAMP_PROFILE}"
echo "[0088] Q9 limiter: mode=${Q9_CORRECTION_LIMITER_MODE}, overThermal=${Q9_CORRECTION_LIMITER_OVER_THERMAL}, thermalKBT=${Q9_CORRECTION_LIMITER_THERMAL_KBT}, legacyAbs=${Q9_CORRECTION_LIMITER}"

SECONDS=0
TAG="u${UIN//./p}_${Nx}x${Ny}"
if [[ "$RUN_CLASSIC" == "1" ]]; then
  write_case "openchan_classic_jet_${TAG}" "classic" "false" "false"
fi
if [[ "$RUN_Q6" == "1" ]]; then
  write_case "openchan_q6_jet_${TAG}" "q6" "false" "false"
fi
if [[ "$RUN_Q9" == "1" ]]; then
  write_case "openchan_q9_fullio_jet_${TAG}" "q9" "true" "false"
fi
if [[ "$RUN_Q9_VIRIAL" == "1" ]]; then
  write_case "openchan_q9_virial_jet_${TAG}" "q9_virial" "true" "true"
fi

elapsed=$SECONDS
printf '[0088] done in %02d:%02d:%02d\n' $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))

echo "[0088] Analyze with: cd matlab && R = analyze_poiseuille_hard_inlet_free_outlet_0077('root','..','runRoot','${RUN_ROOT}','caseGlob','openchan_*');"

if [[ "$AUTO_ANALYZE" == "1" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    matlab -batch "cd('matlab'); analyze_poiseuille_hard_inlet_free_outlet_0077('root','..','runRoot','${RUN_ROOT}','caseGlob','openchan_*');"
  else
    echo "[0088] AUTO_ANALYZE=1 requested but matlab is not available." >&2
  fi
fi

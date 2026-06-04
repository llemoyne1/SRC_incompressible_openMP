#!/usr/bin/env bash
set -euo pipefail

# 0071 hard-inlet/open-outlet straight-channel budget test.
# Purpose: determine whether the current hard_cell_density inlet and passive
# outlet relax toward a constant mass throughput in the absence of an obstacle.
# Default grid is 48x24 at fixed physical size Lx=2, Ly=1; default duration is
# 60000 steps, i.e. t=60 = 1.5 advective times for Uin=0.05 and Lx=2.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AUTO_BUILD="${AUTO_BUILD:-1}"
AUTO_ANALYZE="${AUTO_ANALYZE:-1}"
CASE_STEPS="${CASE_STEPS:-60000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-250}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-5000}"
NUM_THREADS="${NUM_THREADS:-8}"
RUN_ROOT="${RUN_ROOT:-runs/open_channel_hard_inlet_budget_0071}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"

# Fixed physical channel, reduced grid.
Lx="${Lx:-2.0}"
Ly="${Ly:-1.0}"
Nx="${Nx:-48}"
Ny="${Ny:-24}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.001}"
KBT="${KBT:-0.0025}"
UIN="${UIN:-0.05}"
STATE_FILE="${STATE_FILE:-initial_state_open_channel_hard_inlet_48x24_g20_kbt0p0025_ux0p05.smpcd}"
INIT_UX="${INIT_UX:-${UIN}}"

# Scaled cell-band widths relative to the 96x48 backward-step diagnostic run.
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-3}"
Q9_OPEN_EXCLUSION_CELLS="${Q9_OPEN_EXCLUSION_CELLS:-3}"
VIRIAL_OPEN_EXCLUSION_CELLS="${VIRIAL_OPEN_EXCLUSION_CELLS:-3}"

Q9_STRENGTH_REF="${Q9_STRENGTH_REF:-0.03}"
Q9_BETA="${Q9_BETA:-0.001}"
Q9_MIN_CELL_MASS="${Q9_MIN_CELL_MASS:-8.0}"
Q9_CORRECTION_LIMITER="${Q9_CORRECTION_LIMITER:-0.003}"
Q9_LOW_MASS_TREATMENT="${Q9_LOW_MASS_TREATMENT:-ramp_floor}"
Q9_MASS_FLOOR="${Q9_MASS_FLOOR:-8.0}"
Q9_LOW_MASS_RAMP_START="${Q9_LOW_MASS_RAMP_START:-1.0}"
Q9_LOW_MASS_RAMP_END="${Q9_LOW_MASS_RAMP_END:-8.0}"

VIRIAL_K="${VIRIAL_K:-0.50}"
VIRIAL_BETA="${VIRIAL_BETA:-0.05}"

RUN_Q6="${RUN_Q6:-1}"
RUN_Q9="${RUN_Q9:-1}"
RUN_Q9_VIRIAL="${RUN_Q9_VIRIAL:-1}"
RUN_CLASSIC="${RUN_CLASSIC:-0}"

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
Generate it manually with:
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
  local q9_strength="$5"
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
keepMeanFlowEnable = true
targetMeanUx = ${UIN}
targetMeanUy = 0.0

projectionEnable = true
projectionOperator = elliptic_fv_cg
projectionMaxIterations = 700
projectionTolerance = 1.0e-9
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 0.50
projectionImmersedSolidMaskEnable = false
projectionAllowUnmaskedImmersedSolid = false
projectionImmersedSolidFluidFractionThreshold = 0.5
projectionImmersedSolidCloseCutFaces = false

q9MassFluxProjectionEnable = ${q9}
q9MassFluxProjectionStrength = ${q9_strength}
q9DensityRelaxationBeta = ${Q9_BETA}
q9OpenBoundaryExclusionCells = ${Q9_OPEN_EXCLUSION_CELLS}
q9ImmersedSolidHaloCells = 0
q9MinCellMassForCorrection = ${Q9_MIN_CELL_MASS}
q9CorrectionVelocityLimiter = ${Q9_CORRECTION_LIMITER}
q9LowMassTreatment = ${Q9_LOW_MASS_TREATMENT}
q9MassFloorForCorrection = ${Q9_MASS_FLOOR}
q9LowMassRampStart = ${Q9_LOW_MASS_RAMP_START}
q9LowMassRampEnd = ${Q9_LOW_MASS_RAMP_END}
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 4
q9EllipticLowPassPasses = 1
q9MomentumCorrectionEnable = true

virialDiagnosticsEnable = ${virial}
virialKickEnable = ${virial}
virialK = ${VIRIAL_K}
virialBeta = ${VIRIAL_BETA}
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

  echo "[0071] running ${label}"
  echo "[0071] params: ${params_file}"

  if [[ "$CONTINUE_ON_ERROR" == "1" ]]; then
    set +e
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/logs/${label}.log"
    local rc=${PIPESTATUS[0]}
    set -e
    if [[ "$rc" -ne 0 ]]; then
      echo "[0071] WARNING: ${label} failed with exit code ${rc}" | tee -a "$RUN_ROOT/FAILED_CASES.txt"
      return 0
    fi
  else
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/logs/${label}.log"
  fi
}

SECONDS=0
if [[ "$RUN_CLASSIC" == "1" ]]; then
  write_case "openchan_classic_hard_inlet_48x24_long" "classic" "false" "false" "0.0"
fi
if [[ "$RUN_Q6" == "1" ]]; then
  write_case "openchan_q6_hard_inlet_48x24_long" "q6" "false" "false" "0.0"
fi
if [[ "$RUN_Q9" == "1" ]]; then
  write_case "openchan_q9_hard_inlet_s003_48x24_long" "q9" "true" "false" "${Q9_STRENGTH_REF}"
fi
if [[ "$RUN_Q9_VIRIAL" == "1" ]]; then
  write_case "openchan_q9_virial_hard_inlet_s003_48x24_long" "q9_virial" "true" "true" "${Q9_STRENGTH_REF}"
fi

elapsed=$SECONDS
printf '[0071] done in %02d:%02d:%02d\n' $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))

echo "[0071] Analyze with: cd matlab && R = analyze_open_channel_hard_inlet_budget_0071('root','..','runRoot','${RUN_ROOT}');"
echo "[0071] Visuals with: cd matlab && V = make_open_channel_hard_inlet_visual_report_0071('root','..','runRoot','${RUN_ROOT}');"

if [[ "$AUTO_ANALYZE" == "1" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    matlab -batch "cd('matlab'); analyze_open_channel_hard_inlet_budget_0071('root','..','runRoot','${RUN_ROOT}'); make_open_channel_hard_inlet_visual_report_0071('root','..','runRoot','${RUN_ROOT}');"
  else
    echo "[0071] AUTO_ANALYZE=1 requested but matlab is not available." >&2
  fi
fi

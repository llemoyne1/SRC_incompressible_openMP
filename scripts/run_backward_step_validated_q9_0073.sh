#!/usr/bin/env bash
set -euo pipefail

# 0073 backward-step hard-inlet run with Q9 parameters reset to the
# Poiseuille-validation set from feature/elliptic-q6-core:
#   q9MassFluxProjectionStrength = 1.0
#   q9DensityRelaxationBeta      = 0.0005
#   q9TargetFilter               = elliptic_lowpass
#   q9LowKMaxIndex               = 2
#   q9EllipticLowPassPasses      = 1
#   q9CorrectionVelocityLimiter  = 0.0  (disabled)
# The geometry is the 48x24 backward-step inlet/outlet case, 80000 steps.
# Default run: complete chain only, method=q9_virial.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AUTO_BUILD="${AUTO_BUILD:-1}"
AUTO_ANALYZE="${AUTO_ANALYZE:-0}"
CASE_STEPS="${CASE_STEPS:-10000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-250}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-5000}"
NUM_THREADS="${NUM_THREADS:-12}"
RUN_ROOT="${RUN_ROOT:-runs/backward_step_validated_q9_0073}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"

# Fixed physical channel, reduced grid.
Lx="${Lx:-2.0}"
Ly="${Ly:-1.0}"
Nx="${Nx:-48}"
Ny="${Ny:-24}"
GAMMA="${GAMMA:-40}"
DT="${DT:-0.001}"
KBT="${KBT:-0.01}"
UIN="${UIN:-0.05}"

# Backward-step obstacle geometry. Same physical geometry as the 96x48 diagnostic.
SOLID_XMIN="${SOLID_XMIN:-0.25}"
SOLID_XMAX="${SOLID_XMAX:-0.65}"
SOLID_YMIN="${SOLID_YMIN:-0.0}"
SOLID_YMAX="${SOLID_YMAX:-0.50}"
STATE_FILE="${STATE_FILE:-initial_state_backward_step_exact_fluid_48x24_g40_kbt0p01_ux0p05.smpcd}"

# Cell-band widths scaled relative to the 96x48 case.
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-3}"
Q9_OPEN_EXCLUSION_CELLS="${Q9_OPEN_EXCLUSION_CELLS:-3}"
VIRIAL_OPEN_EXCLUSION_CELLS="${VIRIAL_OPEN_EXCLUSION_CELLS:-3}"

# Minimal non-zero immersed-solid Q9 halo: at 48x24, halo=1 is the smallest
# conservative safety layer around the obstacle while leaving Q9 active over most
# of the flow. Use Q9_IMMERSED_HALO_CELLS=0 only as a separate stress test.
Q9_IMMERSED_HALO_CELLS="${Q9_IMMERSED_HALO_CELLS:-1}"

# Q9 settings copied from the validated Poiseuille Q9 filtered run on
# feature/elliptic-q6-core, except for the open-boundary/immersed-solid safety
# masks, which do not exist in the periodic-x/solid-y Poiseuille case.
Q9_STRENGTH_REF="${Q9_STRENGTH_REF:-1.0}"
Q9_BETA="${Q9_BETA:-0.0005}"
Q9_MIN_CELL_MASS="${Q9_MIN_CELL_MASS:-0.0}"
Q9_CORRECTION_LIMITER="${Q9_CORRECTION_LIMITER:-0.0}"
Q9_LOW_MASS_TREATMENT="${Q9_LOW_MASS_TREATMENT:-suppress}"
Q9_MASS_FLOOR="${Q9_MASS_FLOOR:-0.0}"
Q9_LOW_MASS_RAMP_START="${Q9_LOW_MASS_RAMP_START:-0.0}"
Q9_LOW_MASS_RAMP_END="${Q9_LOW_MASS_RAMP_END:-0.0}"

VIRIAL_K="${VIRIAL_K:-0.50}"
VIRIAL_BETA="${VIRIAL_BETA:-0.05}"

KEEP_MEAN_FLOW_ENABLE="${KEEP_MEAN_FLOW_ENABLE:-true}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-500}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-10}"

# Save time by default: run the complete method only.
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
    matlab -batch "cd('matlab'); generate_backward_step_exact_fluid_state_0072('output','../${STATE_FILE}','Lx',${Lx},'Ly',${Ly},'Nx',${Nx},'Ny',${Ny},'gamma',${GAMMA},'kBT',${KBT},'Ux',${UIN},'Uy',0.0,'xMin',${SOLID_XMIN},'xMax',${SOLID_XMAX},'yMin',${SOLID_YMIN},'yMax',${SOLID_YMAX});"
  else
    cat >&2 <<MSG
Missing $STATE_FILE and matlab is not available on the command line.
Generate the initial state manually from MATLAB with:

  cd('/path/to/SRC_incompressible_openMP/matlab')
  generate_backward_step_exact_fluid_state_0072( ...
      'output','../${STATE_FILE}', ...
      'Lx',${Lx},'Ly',${Ly},'Nx',${Nx},'Ny',${Ny}, ...
      'gamma',${GAMMA},'kBT',${KBT},'Ux',${UIN},'Uy',0.0, ...
      'xMin',${SOLID_XMIN},'xMax',${SOLID_XMAX}, ...
      'yMin',${SOLID_YMIN},'yMax',${SOLID_YMAX});
  cd('..')

Then rerun this script.
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
keepMeanFlowEnable = ${KEEP_MEAN_FLOW_ENABLE}
targetMeanUx = ${UIN}
targetMeanUy = 0.0

projectionEnable = true
projectionOperator = elliptic_fv_cg
projectionMaxIterations = ${PROJECTION_MAX_ITERATIONS}
projectionTolerance = ${PROJECTION_TOLERANCE}
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = ${Q6_PROJECTION_STRENGTH}
projectionImmersedSolidMaskEnable = true
projectionAllowUnmaskedImmersedSolid = false
projectionImmersedSolidFluidFractionThreshold = 0.5
projectionImmersedSolidCloseCutFaces = true

q9MassFluxProjectionEnable = ${q9}
q9MassFluxProjectionStrength = ${q9_strength}
q9DensityRelaxationBeta = ${Q9_BETA}
q9OpenBoundaryExclusionCells = ${Q9_OPEN_EXCLUSION_CELLS}
q9ImmersedSolidHaloCells = ${Q9_IMMERSED_HALO_CELLS}
q9MinCellMassForCorrection = ${Q9_MIN_CELL_MASS}
q9CorrectionVelocityLimiter = ${Q9_CORRECTION_LIMITER}
q9LowMassTreatment = ${Q9_LOW_MASS_TREATMENT}
q9MassFloorForCorrection = ${Q9_MASS_FLOOR}
q9LowMassRampStart = ${Q9_LOW_MASS_RAMP_START}
q9LowMassRampEnd = ${Q9_LOW_MASS_RAMP_END}
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
q9EllipticLowPassPasses = 1
q9MomentumCorrectionEnable = true

virialDiagnosticsEnable = ${virial}
virialKickEnable = ${virial}
virialK = ${VIRIAL_K}
virialBeta = ${VIRIAL_BETA}
virialOpenBoundaryExclusionCells = ${VIRIAL_OPEN_EXCLUSION_CELLS}

immersedSolidEnable = true
immersedSolidShape = rectangle
immersedSolidXMin = ${SOLID_XMIN}
immersedSolidXMax = ${SOLID_XMAX}
immersedSolidYMin = ${SOLID_YMIN}
immersedSolidYMax = ${SOLID_YMAX}
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

  echo "[0073] running ${label}"
  echo "[0073] params: ${params_file}"

  if [[ "$CONTINUE_ON_ERROR" == "1" ]]; then
    set +e
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/logs/${label}.log"
    local rc=${PIPESTATUS[0]}
    set -e
    if [[ "$rc" -ne 0 ]]; then
      echo "[0073] WARNING: ${label} failed with exit code ${rc}" | tee -a "$RUN_ROOT/FAILED_CASES.txt"
      return 0
    fi
  else
    build/src_mpcd_base "$params_file" 2>&1 | tee "$RUN_ROOT/logs/${label}.log"
  fi
}

SECONDS=0
if [[ "$RUN_CLASSIC" == "1" ]]; then
  write_case "backstep_classic_hard_inlet_48x24_halo${Q9_IMMERSED_HALO_CELLS}_long" "classic" "false" "false" "0.0"
fi
if [[ "$RUN_Q6" == "1" ]]; then
  write_case "backstep_q6_hard_inlet_48x24_halo${Q9_IMMERSED_HALO_CELLS}_long" "q6" "false" "false" "0.0"
fi
if [[ "$RUN_Q9" == "1" ]]; then
  write_case "backstep_q9_validated_hard_inlet_48x24_halo${Q9_IMMERSED_HALO_CELLS}_long" "q9" "true" "false" "${Q9_STRENGTH_REF}"
fi
if [[ "$RUN_Q9_VIRIAL" == "1" ]]; then
  write_case "backstep_q9_virial_validated_hard_inlet_48x24_halo${Q9_IMMERSED_HALO_CELLS}_long" "q9_virial" "true" "true" "${Q9_STRENGTH_REF}"
fi

elapsed=$SECONDS
printf '[0073] done in %02d:%02d:%02d\n' $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))

echo "[0073] Analyze with: cd matlab && R = analyze_backward_step_hard_inlet_budget_0072('root','..','runRoot','${RUN_ROOT}');"
echo "[0073] Visuals with: cd matlab && V = make_backward_step_hard_inlet_visual_report_0072('root','..','runRoot','${RUN_ROOT}');"

if [[ "$AUTO_ANALYZE" == "1" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    matlab -batch "cd('matlab'); analyze_backward_step_hard_inlet_budget_0072('root','..','runRoot','${RUN_ROOT}'); make_backward_step_hard_inlet_visual_report_0072('root','..','runRoot','${RUN_ROOT}');"
  else
    echo "[0073] AUTO_ANALYZE=1 requested but matlab is not available." >&2
  fi
fi

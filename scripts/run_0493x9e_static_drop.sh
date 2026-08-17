#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="static_drop_0493x9e"
TOPOLOGY="closed_box"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"

# Reuse the calibrated 400x400 fluid and start at a moderate R/h=40.
NX="${NX:-400}"; NY="${NY:-400}"
Lx="${Lx:-1.5625}"; Ly="${Ly:-1.5625}"
GAMMA="${GAMMA:-20}"; DT="${DT:-0.002}"; KBT="${KBT:-0.125}"
STEPS="${STEPS:-20}"; SEED="${SEED:-493904}"
R_CELLS="${R_CELLS:-40}"
CENTER_X="${CENTER_X:-0.78125}"; CENTER_Y="${CENTER_Y:-0.78125}"
SIGMA="${SIGMA:-256.0}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"

read -r RX RY CELL_AREA THERMAL_PRESSURE LAPLACE_PRESSURE <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" "$R_CELLS" "$GAMMA" "$KBT" "$SIGMA" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
rc,g,kbt,sigma=float(sys.argv[5]),float(sys.argv[6]),float(sys.argv[7]),float(sys.argv[8])
dx,dy=lx/nx,ly/ny
if abs(dx-dy)>1e-12*max(1.0,abs(dx),abs(dy)):
    raise SystemExit('[0493x9e] static drop requires square cells')
r=rc*dx
area=dx*dy
pth=g*kbt/area
pl=sigma/r
print(f'{r:.17g} {r:.17g} {area:.17g} {pth:.17g} {pl:.17g}')
PY
)"

BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x9e_static_drop_${NX}x${NY}_g${GAMMA}_rc${R_CELLS}_sigma${SIGMA}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:-$LIQUID_TYPE}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-curvature_interface}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:-10.0}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"
LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-$BASE_RUN_ROOT/livevis_control_0493x9e.kv}"

THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"

Q6_GF_EXTERNAL_SPECIES=1
# x9d tests the actual p_l = p_g + sigma*kappa composition, with the x6g EOS
# gas pressure referenced to the equilibrium gamma*kBT/cellArea value.
Q6_GF_HAS_GAS_PHASE=1
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"

GEN_CASE="tg"; U0=0.0; VELOCITY_MODE="zero"; PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false

suite_defaults_common_0434
suite_compute_derived_0434

python3 - "$SIGMA" "$RX" "$RY" <<'PY_VALIDATE'
import math,sys
sigma,rx,ry=map(float,sys.argv[1:])
if not (math.isfinite(sigma) and sigma>=0): raise SystemExit('[0493x9e] SIGMA must be finite and non-negative')
if min(rx,ry)<=0: raise SystemExit('[0493x9e] radius must be positive')
PY_VALIDATE

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$BASE_RUN_ROOT"; fi
suite_prepare_dirs_0434 "$BASE_RUN_ROOT"
STATE="$BASE_RUN_ROOT/init/${CASE_LABEL}.smpcd"
OUT="$BASE_RUN_ROOT/output"
PARAMS="$BASE_RUN_ROOT/params/${CASE_LABEL}.kv"
LOG="$BASE_RUN_ROOT/logs/${CASE_LABEL}.log"
TIME_FILE="$BASE_RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"

python3 scripts/generate_0493x9b_ellipse_state.py \
  --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
  --gamma "$GAMMA" --center-x "$CENTER_X" --center-y "$CENTER_Y" \
  --radius-x "$RX" --radius-y "$RY" --angle-deg 0.0 \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
  --kBT "$KBT" --seed "$SEED"

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GAS_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"
cat > "$PARAMS" <<PARAMS_EOF
inputState = $STATE
outputDir = $OUT
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = specular
bcRight = specular
bcBottom = specular
bcTop = specular
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
wallVpEnable = false
wallAccommodation = 1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $SIGMA
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x9e.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_FILL_FRACTION
PARAMS_EOF
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
# p3 is now a production field whenever sigma>0. Keep old passive curvature
# diagnostics off here to avoid duplicate p1/p2/p3 work.
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
if awk -v s="$SIGMA" 'BEGIN{exit !(s>0)}'; then
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
else
  # sigma=0 remains a physical no-op; enable passive x9b/x9c only so LiveVis
  # can still display the selected p3 field during the no-op control run.
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
fi

suite_prepare_livevis_control_0434 "$BASE_RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$BASE_RUN_ROOT/logs/environment_0493x9e.env" "$RUN_MODE"
cat >> "$BASE_RUN_ROOT/logs/environment_0493x9e.env" <<META
GAMMA=$GAMMA
R_CELLS=$R_CELLS
RX=$RX
RY=$RY
SIGMA=$SIGMA
THERMAL_PRESSURE=$THERMAL_PRESSURE
LAPLACE_PRESSURE=$LAPLACE_PRESSURE
surfaceTensionSigma=$SIGMA
Q6_GF_HAS_GAS_PHASE=$Q6_GF_HAS_GAS_PHASE
META

printf '%s\n' \
  "[0493x9e] DIAGNOSTIC qualification of x9d Laplace jump; NO physics change from x9d" \
  "[0493x9e] grid=${NX}x${NY} gamma=$GAMMA Rcells=$R_CELLS R=$RX sigma=$SIGMA" \
  "[0493x9e] pThermal=$THERMAL_PRESSURE dPLaplace=$LAPLACE_PRESSURE ratio=$(awk -v p="$LAPLACE_PRESSURE" -v q="$THERMAL_PRESSURE" 'BEGIN{printf "%.6g",p/q}')" \
  "[0493x9e] curvature=p3 binomial3x3(3)+Scharr; LiveVis=curvature_interface by default" \
  "[0493x9e] gas-pressure coupling=x6g EOS reference; density tau=$Q6_GF_DENSITY_RELAXATION_TIME" \
  "[0493x9e] LIVE_PROGRESS=$LIVE_PROGRESS LIVE_VIS_ENABLE=$LIVE_VIS_ENABLE"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  PRESS="$OUT/cuda_static_drop_pressure_0493x9e.csv"
  VEL="$OUT/cuda_static_drop_velocity_0493x9e.csv"
  SPEC="$OUT/species_runtime_0493x9e.csv"
  REPORT="$BASE_RUN_ROOT/static_drop_0493x9e.json"
  python3 scripts/analyze_0493x9e_static_drop.py \
    --pressure "$PRESS" --velocity "$VEL" --species "$SPEC" \
    --json "$REPORT" --liquid-type "$LIQUID_TYPE"
  echo "[0493x9e] pressure_audit=$PRESS"
  echo "[0493x9e] velocity_audit=$VEL"
  echo "[0493x9e] report=$REPORT"
fi

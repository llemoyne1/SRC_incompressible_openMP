#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="ellipse_curvature_0493x9c"
TOPOLOGY="closed_box"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"

NX="${NX:-400}"; NY="${NY:-400}"
Lx="${Lx:-1.5625}"; Ly="${Ly:-1.5625}"
GAMMA="${GAMMA:-20}"; DT="${DT:-0.002}"; KBT="${KBT:-0.125}"
STEPS="${STEPS:-1}"; SEED="${SEED:-493901}"
RX="${RX:-0.3125}"; RY="${RY:-0.3125}"
R_CELLS="${R_CELLS:-}"
CENTER_X="${CENTER_X:-0.78125}"; CENTER_Y="${CENTER_Y:-0.78125}"
ANGLE_DEG="${ANGLE_DEG:-0.0}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"

# Convenient circle specification in cell radii for x9c small-drop sweeps.
if [[ -n "$R_CELLS" ]]; then
  read -r RX RY <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" "$R_CELLS" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2])
nx,ny=int(sys.argv[3]),int(sys.argv[4])
r=float(sys.argv[5])
dx,dy=lx/nx,ly/ny
if abs(dx-dy) > 1e-12*max(1.0,abs(dx),abs(dy)):
    raise SystemExit('[0493x9c] R_CELLS circle requires square cells')
print(f"{r*dx:.17g} {r*dy:.17g}")
PY
)"
fi

if [[ -n "$R_CELLS" ]]; then
  DEFAULT_RUN_ROOT="runs/0493x9c_ellipse_${NX}x${NY}_g${GAMMA}_rc${R_CELLS}_a${ANGLE_DEG}"
else
  DEFAULT_RUN_ROOT="runs/0493x9c_ellipse_${NX}x${NY}_g${GAMMA}_rx${RX}_ry${RY}_a${ANGLE_DEG}"
fi
BASE_RUN_ROOT="${BASE_RUN_ROOT:-$DEFAULT_RUN_ROOT}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
CURVATURE_AUDIT_WALL_MARGIN_CELLS="${CURVATURE_AUDIT_WALL_MARGIN_CELLS:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:-$LIQUID_TYPE}"
# LiveVis still shows the x9b one-pass resident curvature. x9c2/x9c3 are
# summary-cadence qualification candidates and do not alter the live renderer.
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-curvature}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--10.0}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
LIVE_VIS_NX="${LIVE_VIS_NX:-800}"
LIVE_VIS_NY="${LIVE_VIS_NY:-800}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}"

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
Q6_GF_HAS_GAS_PHASE=0
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

python3 - "$Lx" "$Ly" "$RX" "$RY" "$CENTER_X" "$CENTER_Y" "$ANGLE_DEG" <<'PY_VALIDATE'
import math, sys
lx,ly,rx,ry,cx,cy,ang=map(float,sys.argv[1:])
if not all(math.isfinite(x) for x in (lx,ly,rx,ry,cx,cy,ang)):
    raise SystemExit('[0493x9c] non-finite geometry parameter')
if min(lx,ly,rx,ry) <= 0:
    raise SystemExit('[0493x9c] Lx,Ly,RX,RY must be positive')
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
  --radius-x "$RX" --radius-y "$RY" --angle-deg "$ANGLE_DEG" \
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
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x9c.csv
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
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
export MPCD_Q6_PHASE_CURVATURE_AUDIT_WALL_MARGIN_CELLS_0493X9B="$CURVATURE_AUDIT_WALL_MARGIN_CELLS"
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0

suite_prepare_livevis_control_0434 "$BASE_RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$BASE_RUN_ROOT/logs/environment_0493x9c.env" "$RUN_MODE"
cat >> "$BASE_RUN_ROOT/logs/environment_0493x9c.env" <<META
GAMMA=$GAMMA
R_CELLS=$R_CELLS
RX=$RX
RY=$RY
CENTER_X=$CENTER_X
CENTER_Y=$CENTER_Y
ANGLE_DEG=$ANGLE_DEG
MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=1
MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
MPCD_Q6_PHASE_CURVATURE_AUDIT_WALL_MARGIN_CELLS_0493X9B=$CURVATURE_AUDIT_WALL_MARGIN_CELLS
MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0
META

printf '%s\n' \
  "[0493x9c] passive smoothing-support sweep; NO sigma, NO phiGamma modification, NO particle capillary kick" \
  "[0493x9c] grid=${NX}x${NY} L=${Lx}x${Ly} gamma=$GAMMA dt=$DT kBT=$KBT steps=$STEPS" \
  "[0493x9c] circle/ellipse center=($CENTER_X,$CENTER_Y) radii=($RX,$RY) Rcells=${R_CELLS:-n/a} angle=${ANGLE_DEG}deg" \
  "[0493x9c] p1=x9b binomial3x3(1) + Scharr; p2=binomial3x3(2) + Scharr; p3=binomial3x3(3) + Scharr" \
  "[0493x9c] x6c physical alpha and x6f interface remain unchanged" \
  "[0493x9c] LIVE_PROGRESS=$LIVE_PROGRESS LIVE_VIS_ENABLE=$LIVE_VIS_ENABLE"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  AUDIT_X9A="$OUT/cuda_phase_curvature_0493x9a.csv"
  AUDIT_X9B="$OUT/cuda_phase_curvature_0493x9b.csv"
  AUDIT_X9C="$OUT/cuda_phase_curvature_0493x9c.csv"
  REPORT="$BASE_RUN_ROOT/curvature_compare_0493x9c.json"
  python3 scripts/analyze_0493x9c_curvature.py \
    --x9a "$AUDIT_X9A" --x9b "$AUDIT_X9B" --x9c "$AUDIT_X9C" \
    --json "$REPORT" --gamma "$GAMMA" \
    --radius-x "$RX" --radius-y "$RY" \
    --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY"
  echo "[0493x9c] audit_x9a=$AUDIT_X9A"
  echo "[0493x9c] audit_x9b=$AUDIT_X9B"
  echo "[0493x9c] audit_x9c=$AUDIT_X9C"
  echo "[0493x9c] report=$REPORT"
fi

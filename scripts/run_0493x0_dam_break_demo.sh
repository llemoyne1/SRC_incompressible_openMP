#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# -----------------------------------------------------------------------------
# 0493x0 qualitative dam-break demonstration.
# Default size matches the current 3:1 production-like visualization grids.
# -----------------------------------------------------------------------------
CASE_LABEL="dam_break_independent_masked"
TOPOLOGY="closed_box"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-200}"; NY="${NY:-200}"
GAMMA="${GAMMA:-10}"; STEPS="${STEPS:-15000}"; DT="${DT:-0.005}"; KBT="${KBT:-0.05}"
SEED="${SEED:-493900}"
COLUMN_WIDTH="${COLUMN_WIDTH:-0.1}"; COLUMN_HEIGHT="${COLUMN_HEIGHT:-0.99}"
LIQUID_ONLY="${LIQUID_ONLY:-0}"
GRAVITY_Y="${GRAVITY_Y:--0.05}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1000.0}"; GAS_MASS="${GAS_MASS:-1.}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_OCCUPANCY_FRACTION="${SPECIES_Q6_MIN_OCCUPANCY_FRACTION:-0.5}"
SPECIES_Q6_MODE="${SPECIES_Q6_MODE:-independent_masked}"
# The 900x300 masked liquid solve is much larger than the qualification
# smokes.  Keep a demo-appropriate relative tolerance and additional CG
# headroom, while leaving both values explicitly overridable.
Q6_PROJECTION_TOLERANCE="${Q6_PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_MAX_ITERATIONS="${Q6_PROJECTION_MAX_ITERATIONS:-800}"
WALL_VP_MASS="${WALL_VP_MASS:-$LIQUID_MASS}"
WALL_ACCOMMODATION="${WALL_ACCOMMODATION:-1.0}"
BC_LEFT="${BC_LEFT:-specular}"; BC_RIGHT="${BC_RIGHT:-specular}"
BC_BOTTOM="${BC_BOTTOM:-solid}"; BC_TOP="${BC_TOP:-specular}"

if suite_truthy_0434 "$LIQUID_ONLY"; then
  DEFAULT_RUN_ROOT="runs/0493x2_liquid_only_${NX}x${NY}_g${GAMMA}"
else
  DEFAULT_RUN_ROOT="runs/0493x0_dam_break_${NX}x${NY}_g${GAMMA}"
fi
BASE_RUN_ROOT="${BASE_RUN_ROOT:-$DEFAULT_RUN_ROOT}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.5}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-500}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
RUN_MODES="${RUN_MODES:-${MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src-q6}}}}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-$ROOT/livevis_control.kv}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"; LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-2}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:-$LIQUID_TYPE}"

# Recording a 900x300 field every few steps can be very large. Enable it only
# when an export is actually required.
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_STRIDE="${RECORD_STRIDE:-1}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-10}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

# This demonstration intentionally isolates SRC + independent-masked Q6.
SPECIES_RESAMPLING_ENABLE=false
PROJECTION_MOMENTUM_CORRECTION_ENABLE=false
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"
PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"
INACTIVE_TYPE="$GAS_TYPE"
RESAMPLING_NMIN_COEF="${RESAMPLING_NMIN_COEF:-0.40}"
RESAMPLING_NMAX_COEF="${RESAMPLING_NMAX_COEF:-0.60}"
GUARD_EVERY="${GUARD_EVERY:-5}"

suite_defaults_common_0434
suite_compute_derived_0434

readarray -t MODES_0493X0 < <(suite_mode_list_0434)
for mode in "${MODES_0493X0[@]}"; do
  case "$mode" in
    src|src-q6) ;;
    *)
      echo "[0493x0] ERROR mode '$mode' unsupported: use src and/or src-q6; resampling is deliberately excluded" >&2
      exit 2
      ;;
  esac
done

python3 - "$Lx" "$Ly" "$COLUMN_WIDTH" "$COLUMN_HEIGHT" "$LIQUID_MASS" "$GAS_MASS" "$GRAVITY_Y" "$Q6_PROJECTION_TOLERANCE" "$Q6_PROJECTION_MAX_ITERATIONS" "$WALL_ACCOMMODATION" "$BC_LEFT" "$BC_RIGHT" "$BC_BOTTOM" "$BC_TOP" "$LIQUID_ONLY" "$SPECIES_Q6_MODE" <<'PY_VALIDATE'
import math
import sys
lx, ly, width, height, ml, mg, gy, q6_tol = map(float, sys.argv[1:9])
q6_max_iter = int(sys.argv[9])
accommodation = float(sys.argv[10])
boundaries = sys.argv[11:15]
liquid_only = sys.argv[15].strip().lower() in {"1", "true", "yes", "on"}
q6_mode = sys.argv[16].strip()
if q6_mode not in {"independent_masked", "common"}:
    raise SystemExit("[0493x0] SPECIES_Q6_MODE must be independent_masked or common")
if q6_mode == "common" and not liquid_only:
    raise SystemExit("[0493x0] SPECIES_Q6_MODE=common is restricted to the liquid-only control")
if (not liquid_only) and not (0.0 < width < lx and 0.0 < height < ly):
    raise SystemExit("[0493x0] invalid liquid-column dimensions")
if not (ml > 0.0 and mg > 0.0 and math.isfinite(gy) and gy < 0.0):
    raise SystemExit("[0493x0] require positive masses and downward GRAVITY_Y")
if not (math.isfinite(q6_tol) and q6_tol > 0.0 and q6_max_iter > 0):
    raise SystemExit("[0493x0] require Q6_PROJECTION_TOLERANCE > 0 and Q6_PROJECTION_MAX_ITERATIONS > 0")
if not (math.isfinite(accommodation) and 0.0 <= accommodation <= 1.0):
    raise SystemExit("[0493x0] require 0 <= WALL_ACCOMMODATION <= 1")
if any(mode not in {"solid", "specular"} for mode in boundaries):
    raise SystemExit("[0493x0] closed-box demo supports solid/specular faces only")
PY_VALIDATE

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then
  rm -rf "$BASE_RUN_ROOT"
fi
mkdir -p "$BASE_RUN_ROOT/init_shared"
if suite_truthy_0434 "$LIQUID_ONLY"; then
  STATE_BASENAME="liquid_only_${NX}x${NY}_g${GAMMA}"
  GENERATOR_PROFILE_ARGS=(--liquid-only)
else
  STATE_BASENAME="dam_break_${NX}x${NY}_g${GAMMA}"
  GENERATOR_PROFILE_ARGS=()
fi
STATE="$BASE_RUN_ROOT/init_shared/${STATE_BASENAME}.smpcd"
STATE_METADATA="$STATE.json"
python3 scripts/generate_0493x0_dam_break_state.py \
  --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --column-width "$COLUMN_WIDTH" --column-height "$COLUMN_HEIGHT" \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
  --kBT "$KBT" --seed "$SEED" "${GENERATOR_PROFILE_ARGS[@]}"

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GAS_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

write_params_0493x0() {
  local mode=$1 state=$2 out=$3 params=$4
  local species_q6_enable=false
  if suite_path_has_q6_0434 "$mode"; then species_q6_enable=true; fi
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = $BC_LEFT
bcRight = $BC_RIGHT
bcBottom = $BC_BOTTOM
bcTop = $BC_TOP
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
keepMeanFlowEnable = false
wallVpEnable = false
wallAccommodation = $WALL_ACCOMMODATION
wallVpGamma = $GAMMA
wallVpMass = $WALL_VP_MASS
wallKBT = -1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE dam_break_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species1 = $GAS_TYPE ambient_gas gas $GAS_Q6_STRENGTH 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x0.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = $species_q6_enable
speciesQ6Mode = $SPECIES_Q6_MODE
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_OCCUPANCY_FRACTION
PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
  # Override the generic common-suite defaults for this large masked solve.
  # These keys are harmless in src mode and active only when projection runs.
  cat >> "$params" <<PARAMS_Q6_SOLVER
projectionTolerance = $Q6_PROJECTION_TOLERANCE
projectionMaxIterations = $Q6_PROJECTION_MAX_ITERATIONS
PARAMS_Q6_SOLVER
}

run_one_mode_0493x0() {
  local mode=$1
  suite_validate_path_0434 "$mode"
  local run_root="$BASE_RUN_ROOT/$mode"
  suite_prepare_dirs_0434 "$run_root"
  local params="$run_root/params/dam_break_0493x0.kv"
  local out="$run_root/output"
  local log="$run_root/logs/dam_break_0493x0.log"
  local time="$run_root/logs/dam_break_0493x0.time"
  mkdir -p "$out"

  write_params_0493x0 "$mode" "$STATE" "$out" "$params"
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0493x0.env" "$mode"
  cat >> "$run_root/logs/environment_0493x0.env" <<META
COLUMN_WIDTH=$COLUMN_WIDTH
COLUMN_HEIGHT=$COLUMN_HEIGHT
LIQUID_ONLY=$LIQUID_ONLY
GRAVITY_Y=$GRAVITY_Y
LIQUID_TYPE=$LIQUID_TYPE
GAS_TYPE=$GAS_TYPE
LIQUID_MASS=$LIQUID_MASS
GAS_MASS=$GAS_MASS
SPECIES_Q6_MIN_OCCUPANCY_FRACTION=$SPECIES_Q6_MIN_OCCUPANCY_FRACTION
SPECIES_Q6_MODE=$SPECIES_Q6_MODE
Q6_PROJECTION_TOLERANCE=$Q6_PROJECTION_TOLERANCE
Q6_PROJECTION_MAX_ITERATIONS=$Q6_PROJECTION_MAX_ITERATIONS
WALL_ACCOMMODATION=$WALL_ACCOMMODATION
BC_LEFT=$BC_LEFT
BC_RIGHT=$BC_RIGHT
BC_BOTTOM=$BC_BOTTOM
BC_TOP=$BC_TOP
META
  echo "[0493x0] mode=$mode grid=${NX}x${NY} gamma=$GAMMA steps=$STEPS"
  if suite_truthy_0434 "$LIQUID_ONLY"; then
    echo "[0493x2] profile=liquid_only fullBox=1 gravityY=$GRAVITY_Y closedBox=[L:$BC_LEFT R:$BC_RIGHT B:$BC_BOTTOM T:$BC_TOP]"
  else
  echo "[0493x0] column=${COLUMN_WIDTH}x${COLUMN_HEIGHT} gravityY=$GRAVITY_Y closedBox=[L:$BC_LEFT R:$BC_RIGHT B:$BC_BOTTOM T:$BC_TOP] massRatio=$(awk -v a="$LIQUID_MASS" -v b="$GAS_MASS" 'BEGIN{printf "%.6g",a/b}')"
  fi
  echo "[0493x0] q6Mode=$SPECIES_Q6_MODE liquidStrength=$LIQUID_Q6_STRENGTH gasStrength=$GAS_Q6_STRENGTH minOcc=$SPECIES_Q6_MIN_OCCUPANCY_FRACTION"
  echo "[0493x0] q6Solver tolerance=$Q6_PROJECTION_TOLERANCE maxIterations=$Q6_PROJECTION_MAX_ITERATIONS"
  suite_run_binary_0434 "$params" "$log" "$time" "$out"
}

for mode in "${MODES_0493X0[@]}"; do
  run_one_mode_0493x0 "$mode"
done

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  python3 scripts/check_0493x0_dam_break_demo.py \
    --run-root "$BASE_RUN_ROOT" --state-metadata "$STATE_METADATA" \
    --expected-steps "$STEPS" --modes "${MODES_0493X0[@]}"
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="partial_liquid_free_surface_0493x5a"
TOPOLOGY="closed_box"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-200}"; NY="${NY:-200}"
GAMMA="${GAMMA:-10}"; STEPS="${STEPS:-1000}"; DT="${DT:-0.005}"
KBT="${KBT:-0.05}"; SEED="${SEED:-493950}"
GRAVITY_Y="${GRAVITY_Y:--0.5}"; LIQUID_FILL_HEIGHT="${LIQUID_FILL_HEIGHT:-0.5}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1000.0}"; GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.25}"
Q6_FORCE_PROJECTION_MODE="prestream_single_fused"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x5a_partial_liquid_free_surface_${NX}x${NY}_g${GAMMA}_h${LIQUID_FILL_HEIGHT}}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.5}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1200}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="false"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"
RUN_MODE="src-q6"

GEN_CASE="tg"; U0=0.0; VELOCITY_MODE="zero"; PARTICLE_MASS="$LIQUID_MASS"
TG_HOLE_ENABLE=false
suite_defaults_common_0434
suite_compute_derived_0434

if ! python3 scripts/generate_0493x0_dam_break_state.py --help 2>&1 | grep -q -- '--liquid-fill-height'; then
  echo "[0493x5a] ERROR: missing --liquid-fill-height generator extension" >&2
  exit 2
fi
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then
  rm -rf "$BASE_RUN_ROOT"
fi
suite_prepare_dirs_0434 "$BASE_RUN_ROOT"
STATE="$BASE_RUN_ROOT/init/${CASE_LABEL}.smpcd"
OUT="$BASE_RUN_ROOT/output"
PARAMS="$BASE_RUN_ROOT/params/${CASE_LABEL}.kv"
LOG="$BASE_RUN_ROOT/logs/${CASE_LABEL}.log"
TIME_FILE="$BASE_RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"

python3 scripts/generate_0493x0_dam_break_state.py \
  --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --column-width 0.1 --column-height 0.99 \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
  --kBT "$KBT" --seed "$SEED" --liquid-only \
  --liquid-fill-height "$LIQUID_FILL_HEIGHT"

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
bcBottom = solid
bcTop = specular
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
q6ForceProjectionMode = $Q6_FORCE_PROJECTION_MODE
keepMeanFlowEnable = false
wallVpEnable = false
wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $LIQUID_MASS
wallKBT = -1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE partial_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species1 = $GAS_TYPE absent_gas gas 0.0 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x5a.csv
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
suite_prepare_livevis_control_0434 "$BASE_RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$BASE_RUN_ROOT/logs/environment_0493x5a.env" "$RUN_MODE"
echo "[0493x5a] partial liquid free surface grid=${NX}x${NY} gamma=$GAMMA fillHeight=$LIQUID_FILL_HEIGHT steps=$STEPS gravityY=$GRAVITY_Y"
echo "[0493x5a] support=mass/referenceCellMass >= $SPECIES_Q6_MIN_FILL_FRACTION; interface pressure=0 at liquid-empty faces"
echo "[0493x5a] ordering=tentative-force deposit -> free-surface Q6 -> fused force+Q6 apply -> stream -> collision -> thermostat"
suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  python3 scripts/analyze_0493x5a_partial_liquid.py \
    --state "$OUT/state_step_$(printf '%08d' "$STEPS").smpcd" \
    --nx "$NX" --ny "$NY" --Lx "$Lx" --Ly "$Ly" --gamma "$GAMMA" \
    --liquid-type "$LIQUID_TYPE" --initial-fill-height "$LIQUID_FILL_HEIGHT" \
    --output "$BASE_RUN_ROOT/partial_liquid_0493x5a.json"
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="dynamic_free_surface_dam_break_0493x5a2"
TOPOLOGY="closed_box"
Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"; NX="${NX:-300}"; NY="${NY:-150}"
GAMMA="${GAMMA:-10}"; STEPS="${STEPS:-1000}"; DT="${DT:-0.005}"
KBT="${KBT:-0.05}"; SEED="${SEED:-493952}"
GRAVITY_Y="${GRAVITY_Y:--0.5}"
LIQUID_COLUMN_WIDTH="${LIQUID_COLUMN_WIDTH:-0.5}"
LIQUID_COLUMN_HEIGHT="${LIQUID_COLUMN_HEIGHT:-0.8}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1000.0}"; GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.25}"
Q6_FORCE_PROJECTION_MODE="prestream_single_fused"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x5a2_dynamic_free_surface_dam_break_${NX}x${NY}_g${GAMMA}_w${LIQUID_COLUMN_WIDTH}_h${LIQUID_COLUMN_HEIGHT}}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-50}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.5}"
MAX_POPULATION_FACTOR="${MAX_POPULATION_FACTOR:-12.0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1600}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="false"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"
RUN_MODE="src-q6"

GEN_CASE="tg"; U0=0.0; VELOCITY_MODE="zero"; PARTICLE_MASS="$LIQUID_MASS"
TG_HOLE_ENABLE=false
suite_defaults_common_0434
suite_compute_derived_0434

if ! python3 scripts/generate_0493x0_dam_break_state.py --help 2>&1 | grep -q -- '--empty-outside-column'; then
  echo "[0493x5a2] ERROR: missing --empty-outside-column generator extension" >&2
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
  --column-width "$LIQUID_COLUMN_WIDTH" --column-height "$LIQUID_COLUMN_HEIGHT" \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
  --kBT "$KBT" --seed "$SEED" --empty-outside-column

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
species0 = $LIQUID_TYPE dynamic_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species1 = $GAS_TYPE absent_gas gas 0.0 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x5a2.csv
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
suite_write_env_file_0434 "$BASE_RUN_ROOT/logs/environment_0493x5a2.env" "$RUN_MODE"
echo "[0493x5a2] liquid-vacuum dam break grid=${NX}x${NY} gamma=$GAMMA column=${LIQUID_COLUMN_WIDTH}x${LIQUID_COLUMN_HEIGHT} steps=$STEPS gravityY=$GRAVITY_Y"
echo "[0493x5a2] support=mass/referenceCellMass >= $SPECIES_Q6_MIN_FILL_FRACTION; exterior contains no gas particles"
echo "[0493x5a2] ordering=tentative-force deposit -> free-surface Q6 -> fused force+Q6 apply -> stream -> collision -> thermostat"
suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  python3 scripts/analyze_0493x5a2_dynamic_free_surface.py \
    --initial-state "$STATE" --output-dir "$OUT" \
    --mask-audit "$OUT/cuda_species_q6_independent_masked_0493w5.csv" \
    --resident-audit "$OUT/cuda_species_q6_0491.csv" \
    --nx "$NX" --ny "$NY" --Lx "$Lx" --Ly "$Ly" --gamma "$GAMMA" \
    --min-fill-fraction "$SPECIES_Q6_MIN_FILL_FRACTION" \
    --liquid-type "$LIQUID_TYPE" --max-population-factor "$MAX_POPULATION_FACTOR" \
    --json "$BASE_RUN_ROOT/dynamic_free_surface_0493x5a2.json" \
    --csv "$BASE_RUN_ROOT/dynamic_free_surface_0493x5a2.csv"
  echo "[0493x5a2] root=$BASE_RUN_ROOT"
  echo "[0493x5a2] report=$BASE_RUN_ROOT/dynamic_free_surface_0493x5a2.json"
  echo "[0493x5a2] series=$BASE_RUN_ROOT/dynamic_free_surface_0493x5a2.csv"
fi

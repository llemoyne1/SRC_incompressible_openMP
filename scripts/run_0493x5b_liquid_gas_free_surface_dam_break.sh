#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="liquid_gas_free_surface_dam_break_0493x5b"
TOPOLOGY="closed_box"
Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"; NX="${NX:-300}"; NY="${NY:-150}"
GAMMA="${GAMMA:-10}"; STEPS="${STEPS:-1000}"; DT="${DT:-0.005}"
KBT="${KBT:-0.05}"; SEED="${SEED:-493953}"
GRAVITY_Y="${GRAVITY_Y:--0.5}"
LIQUID_COLUMN_WIDTH="${LIQUID_COLUMN_WIDTH:-0.5}"
LIQUID_COLUMN_HEIGHT="${LIQUID_COLUMN_HEIGHT:-0.8}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1000.0}"; GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.25}"
LIQUID_RESAMPLING_ENABLE="${LIQUID_RESAMPLING_ENABLE:-false}"
GAS_RESAMPLING_ENABLE="${GAS_RESAMPLING_ENABLE:-false}"
SPECIES_RESAMPLING_ENABLE="${SPECIES_RESAMPLING_ENABLE:-false}"
SPECIES_RESIDENT_MODE="${SPECIES_RESIDENT_MODE:-auto}"
Q6_FORCE_PROJECTION_MODE="prestream_single_fused"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x5b_liquid_gas_free_surface_dam_break_${NX}x${NY}_g${GAMMA}_w${LIQUID_COLUMN_WIDTH}_h${LIQUID_COLUMN_HEIGHT}}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-50}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.5}"
MAX_LIQUID_POPULATION_FACTOR="${MAX_LIQUID_POPULATION_FACTOR:-12.0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
# The ambient gas fills the box in number density.  Filter to liquid by default
# so the evolving interface remains visible; set -1 explicitly for both phases.
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:-$LIQUID_TYPE}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1600}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="false"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"
RUN_MODE="${RUN_MODE:-src-q6}"

GEN_CASE="tg"; U0=0.0; VELOCITY_MODE="zero"; PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
suite_defaults_common_0434
suite_compute_derived_0434

python3 - "$Lx" "$Ly" "$LIQUID_COLUMN_WIDTH" "$LIQUID_COLUMN_HEIGHT" \
  "$LIQUID_MASS" "$GAS_MASS" "$LIQUID_Q6_STRENGTH" "$GAS_Q6_STRENGTH" \
  "$SPECIES_Q6_MIN_FILL_FRACTION" <<'PY_VALIDATE'
import math
import sys
lx, ly, width, height, ml, mg, ql, qg, threshold = map(float, sys.argv[1:])
if not (0.0 < width < lx and 0.0 < height < ly):
    raise SystemExit("[0493x5b] liquid column must lie strictly inside the box")
if not (ml > 0.0 and mg > 0.0 and math.isfinite(ml) and math.isfinite(mg)):
    raise SystemExit("[0493x5b] particle masses must be finite and positive")
if not (ql > 0.0 and qg == 0.0):
    raise SystemExit("[0493x5b] require liquid Q6 strength > 0 and gas Q6 strength = 0")
if not (0.0 <= threshold <= 1.0 and math.isfinite(threshold)):
    raise SystemExit("[0493x5b] SPECIES_Q6_MIN_FILL_FRACTION must lie in [0,1]")
PY_VALIDATE

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

# Default generator profile: liquid column plus ambient gas in every exterior cell.
python3 scripts/generate_0493x0_dam_break_state.py \
  --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --column-width "$LIQUID_COLUMN_WIDTH" --column-height "$LIQUID_COLUMN_HEIGHT" \
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
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = $LIQUID_RESAMPLING_ENABLE
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = $GAS_RESAMPLING_ENABLE
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x5b.csv
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

# 0493x6f-r2: RUN_MODE=src-q6 deliberately keeps the general resampling path
# disabled, but 0493o1 split-only can still be selected by the params-level
# insertion-only policy. Restore only the validated 0307 split safeguards
# that suite_export_cuda_flags_0434 disables for non-resampling run modes.
if suite_truthy_0434 "${RESAMPLING_INSERTION_ENABLE:-false}" && \
   ! suite_truthy_0434 "${RESAMPLING_EXTRACTION_ENABLE:-false}" && \
   ! suite_truthy_0434 "${RESAMPLING_REMAP_ENABLE:-false}"; then
  export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1
  export MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1
  export MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307="${SPLIT_DONOR_MIN_MASS:-0.5}"
  export MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307="${SPLIT_NEW_PARTICLE_MIN_MASS:-0.25}"
  echo "[0493x6f-r2] 0493o1 split-only safety: splitSafety0307=1 donorMin=${SPLIT_DONOR_MIN_MASS:-0.5} newMin=${SPLIT_NEW_PARTICLE_MIN_MASS:-0.25}"
fi
suite_prepare_livevis_control_0434 "$BASE_RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$BASE_RUN_ROOT/logs/environment_0493x5b.env" "$RUN_MODE"
cat >> "$BASE_RUN_ROOT/logs/environment_0493x5b.env" <<META
LIQUID_COLUMN_WIDTH=$LIQUID_COLUMN_WIDTH
LIQUID_COLUMN_HEIGHT=$LIQUID_COLUMN_HEIGHT
LIQUID_TYPE=$LIQUID_TYPE
GAS_TYPE=$GAS_TYPE
LIQUID_MASS=$LIQUID_MASS
GAS_MASS=$GAS_MASS
LIQUID_Q6_STRENGTH=$LIQUID_Q6_STRENGTH
GAS_Q6_STRENGTH=$GAS_Q6_STRENGTH
SPECIES_Q6_MIN_FILL_FRACTION=$SPECIES_Q6_MIN_FILL_FRACTION
RUN_MODE=$RUN_MODE
LIQUID_RESAMPLING_ENABLE=$LIQUID_RESAMPLING_ENABLE
GAS_RESAMPLING_ENABLE=$GAS_RESAMPLING_ENABLE
SPECIES_RESAMPLING_ENABLE=$SPECIES_RESAMPLING_ENABLE
SPECIES_RESIDENT_MODE=$SPECIES_RESIDENT_MODE
META

echo "[0493x5b] liquid-gas dam break grid=${NX}x${NY} gamma=$GAMMA column=${LIQUID_COLUMN_WIDTH}x${LIQUID_COLUMN_HEIGHT} steps=$STEPS gravityY=$GRAVITY_Y"
echo "[0493x5b] liquid=free_surface_masked Q6-g; gas=compressible q6Strength=0; massRatio=$(awk -v a="$LIQUID_MASS" -v b="$GAS_MASS" 'BEGIN{printf "%.6g",a/b}')"
echo "[0493x5b] runMode=$RUN_MODE speciesResampling=$SPECIES_RESAMPLING_ENABLE liquidResampling=$LIQUID_RESAMPLING_ENABLE gasResampling=$GAS_RESAMPLING_ENABLE residentMode=$SPECIES_RESIDENT_MODE"
echo "[0493x5b] ordering=tentative-force deposit -> liquid free-surface Q6 -> fused force+liquid correction -> stream -> multispecies collision -> thermostat"
suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  python3 scripts/analyze_0493x5b_liquid_gas_free_surface.py \
    --initial-state "$STATE" --output-dir "$OUT" \
    --mask-audit "$OUT/cuda_species_q6_independent_masked_0493w5.csv" \
    --resident-audit "$OUT/cuda_species_q6_0491.csv" \
    --nx "$NX" --ny "$NY" --Lx "$Lx" --Ly "$Ly" --gamma "$GAMMA" \
    --min-fill-fraction "$SPECIES_Q6_MIN_FILL_FRACTION" \
    --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
    --max-liquid-population-factor "$MAX_LIQUID_POPULATION_FACTOR" \
    --json "$BASE_RUN_ROOT/liquid_gas_free_surface_0493x5b.json" \
    --csv "$BASE_RUN_ROOT/liquid_gas_free_surface_0493x5b.csv"
  echo "[0493x5b] root=$BASE_RUN_ROOT"
  echo "[0493x5b] report=$BASE_RUN_ROOT/liquid_gas_free_surface_0493x5b.json"
  echo "[0493x5b] series=$BASE_RUN_ROOT/liquid_gas_free_surface_0493x5b.csv"
fi

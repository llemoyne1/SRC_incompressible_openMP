#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="tg_mono_dual_equivalence_0493w8"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493w8_tg_mono_dual_equivalence}"
NX="${NX:-24}"
NY="${NY:-24}"
GAMMA="${GAMMA:-32}"
STEPS="${STEPS:-300}"
DT="${DT:-0.002}"
DUMP_EVERY="${DUMP_EVERY:-10}"
SEEDS="${SEEDS:-493801}"
SCENARIOS="${SCENARIOS:-mono_legacy mono_independent dual_identical}"
RUN_MODES="${RUN_MODES:-src src-q6}"
THREADS="${THREADS:-8}"
TG_MODE="${TG_MODE:-1}"
TG_AMPLITUDE="${TG_AMPLITUDE:-0.08}"
THERMAL_AMPLITUDE="${THERMAL_AMPLITUDE:-0.04}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
INACTIVE_PER_CELL="${INACTIVE_PER_CELL:-0}"
SPECIES_Q6_MIN_OCCUPANCY_FRACTION="${SPECIES_Q6_MIN_OCCUPANCY_FRACTION:-0.0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"

if (( NX < 8 || NY < 8 || GAMMA < 8 || GAMMA % 4 != 0 )); then
  echo "[0493w8] ERROR NX/NY must be >=8 and GAMMA divisible by 4 and >=8" >&2
  exit 2
fi
if (( STEPS < DUMP_EVERY || DUMP_EVERY < 1 || STEPS % DUMP_EVERY != 0 )); then
  echo "[0493w8] ERROR require STEPS>=DUMP_EVERY>=1 and STEPS divisible by DUMP_EVERY" >&2
  exit 2
fi
python3 - "$DT" "$TG_AMPLITUDE" "$THERMAL_AMPLITUDE" "$PARTICLE_MASS" "$SPECIES_Q6_MIN_OCCUPANCY_FRACTION" <<'PY_VALIDATE'
import math, sys
vals=list(map(float,sys.argv[1:]))
if not all(math.isfinite(x) for x in vals):
    raise SystemExit('[0493w8] ERROR non-finite physical parameter')
if vals[0] <= 0 or vals[1] <= 0 or vals[2] < 0 or vals[3] <= 0 or not (0.0 <= vals[4] <= 1.0):
    raise SystemExit('[0493w8] ERROR invalid dt/U0/thermal/mass/min occupancy')
PY_VALIDATE

for scenario in $SCENARIOS; do
  case "$scenario" in
    mono_legacy|mono_independent|dual_identical) ;;
    *) echo "[0493w8] ERROR unsupported scenario=$scenario" >&2; exit 2 ;;
  esac
done
for mode in $RUN_MODES; do
  case "$mode" in
    src|src-q6) suite_validate_path_0434 "$mode" ;;
    *) echo "[0493w8] ERROR no-resampling qualification accepts only src and src-q6, got $mode" >&2; exit 2 ;;
  esac
done

export LIVE_PROGRESS OMP_NUM_THREADS="$THREADS"
Lx=1.0
Ly=1.0
KBT=0.0
U0=0.0
UIN=0.0
SUMMARY_EVERY="$DUMP_EVERY"
DUMP_STATE_EVERY="$DUMP_EVERY"
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false
SPECIES_RESIDENT_MODE=production
RESAMPLING_PRODUCTION_STRIP=1
RESAMPLING_DIAG_CSV_ENABLE=0
RESAMPLING_FULL_GATE_ENABLE=0
RESAMPLING_HOST_PATCHBACK_ENABLE=0
RESAMPLING_SPARSE_DEVICE_GATE_ENABLE=0
MASS_RECONDITION_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=200
PROJECTION_TOLERANCE=1.0e-12
# Required for a fair legacy/full-support independent comparison: the new
# independent operator deliberately omits the legacy uniform momentum patch.
PROJECTION_MOMENTUM_CORRECTION_ENABLE=false
Q6_PROJECTION_STRENGTH=1.0
ROTATION_ANGLE=2.0943951023931953
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=false
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT=0.0
THERMOSTAT_MIN_PARTICLES=2
LIVE_VIS_ENABLE=0
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false
PARTICLE_TYPE_FILTER=-1

suite_defaults_common_0434
suite_compute_derived_0434

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  if [[ "$CLEAN_RUN_ROOT" == 1 ]]; then rm -rf "$RUN_ROOT"; fi
  mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"
fi
if [[ "$PREFLIGHT_ONLY" != 1 && "$ANALYZE_ONLY" != 1 ]]; then
  suite_ensure_binary_0434
fi

MONO_STATE="$RUN_ROOT/init/tg_mono_identical_0493w8.smpcd"
DUAL_STATE="$RUN_ROOT/init/tg_dual_identical_0493w8.smpcd"
TARGET_CELL_MASS="$(python3 - "$GAMMA" "$PARTICLE_MASS" <<'PY_MASS'
import sys
print(int(sys.argv[1])*float(sys.argv[2]))
PY_MASS
)"
SPECIES_TARGET_CELL_MASS="$(python3 - "$TARGET_CELL_MASS" <<'PY_MASS'
import sys
print(0.5*float(sys.argv[1]))
PY_MASS
)"

make_states_0493w8() {
  python3 scripts/generate_0493w8_tg_identical_states.py \
    --mono-output "$MONO_STATE" --dual-output "$DUAL_STATE" \
    --nx "$NX" --ny "$NY" --gamma "$GAMMA" --tg-mode "$TG_MODE" \
    --tg-amplitude "$TG_AMPLITUDE" --thermal-amplitude "$THERMAL_AMPLITUDE" \
    --particle-mass "$PARTICLE_MASS" --inactive-per-cell "$INACTIVE_PER_CELL"
}

mode_has_q6_0493w8() {
  suite_path_has_q6_0434 "$1"
}

write_species_block_0493w8() {
  local scenario=$1 mode=$2
  local q6_enable=false
  if mode_has_q6_0493w8 "$mode"; then q6_enable=true; fi
  case "$scenario" in
    mono_legacy)
      cat <<'EOF_SPECIES'
speciesRegistryEnable = false
speciesQ6Enable = false
EOF_SPECIES
      ;;
    mono_independent)
      cat <<EOF_SPECIES
speciesRegistryEnable = true
speciesCount = 1
species0 = 1 tg_identical_fluid unspecified 1.0 0.0 $TARGET_CELL_MASS
species0ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493w8.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = $q6_enable
speciesQ6Mode = independent_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_OCCUPANCY_FRACTION
EOF_SPECIES
      ;;
    dual_identical)
      cat <<EOF_SPECIES
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 tg_identical_fluid_A unspecified 1.0 0.0 $SPECIES_TARGET_CELL_MASS
species0ResamplingEnable = false
species1 = 2 tg_identical_fluid_B unspecified 1.0 0.0 $SPECIES_TARGET_CELL_MASS
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493w8.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = $q6_enable
speciesQ6Mode = independent_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_OCCUPANCY_FRACTION
EOF_SPECIES
      ;;
  esac
}

write_params_0493w8() {
  local case_dir=$1 scenario=$2 mode=$3 seed=$4
  local state="$MONO_STATE"
  [[ "$scenario" == dual_identical ]] && state="$DUAL_STATE"
  local params="$case_dir/params/params_0493w8.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  cat > "$params" <<EOF_PARAMS
inputState = $state
outputDir = $case_dir/output
Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = false
taylorGreenForcingEnable = false
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
rngSeed = $seed
EOF_PARAMS
  write_species_block_0493w8 "$scenario" "$mode" >> "$params"
  suite_write_common_params_0434 "$mode" >> "$params"
  cat >> "$params" <<EOF_PARAMS
# 0493w8: no population mutation in any branch.
resamplingEnable = false
resamplingTargetCellMass = $TARGET_CELL_MASS
EOF_PARAMS
  printf '%s\n' "$params"
}

run_case_0493w8() {
  local seed=$1 scenario=$2 mode=$3
  SEED="$seed"
  export SEED SPECIES_RESAMPLING_ENABLE
  local case_dir="$RUN_ROOT/seed_${seed}/$scenario/$mode"
  local params log time_file
  params="$(write_params_0493w8 "$case_dir" "$scenario" "$mode" "$seed")"
  log="$case_dir/logs/run_0493w8.log"
  time_file="$case_dir/logs/time_0493w8.txt"
  suite_export_cuda_flags_0434 "$mode" periodic
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 LIVE_PROGRESS
  if ! suite_preflight_run_ok_0492 "$params"; then
    echo "$seed,$scenario,$mode,FAIL,preflight" >> "$RUN_ROOT/status_0493w8.csv"
    return 0
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "$seed,$scenario,$mode,PASS,preflight-only" >> "$RUN_ROOT/status_0493w8.csv"
    return 0
  fi
  echo "[0493w8] seed=$seed scenario=$scenario mode=$mode steps=$STEPS gamma=$GAMMA"
  set +e
  /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' \
    "$BIN" "$params" > "$log" 2>&1
  local rc=$?
  set -e
  local status=PASS reason=ok
  if [[ $rc -ne 0 ]]; then status=FAIL; reason="rc=$rc"; fi
  if grep -Eqi 'Fatal error|\[.*ERROR|CPU equivalence gate|host patchback|fallback.*CPU' "$log"; then
    status=FAIL; reason=forbidden-log-pattern
  fi
  if ! grep -q 'resampling=off' "$log"; then
    status=FAIL; reason=resampling-not-confirmed-off
  fi
  echo "$seed,$scenario,$mode,$status,$reason" >> "$RUN_ROOT/status_0493w8.csv"
  [[ "$status" == PASS ]] || tail -120 "$log" >&2 || true
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  make_states_0493w8
  printf 'seed,scenario,mode,status,reason\n' > "$RUN_ROOT/status_0493w8.csv"
  for seed in $SEEDS; do
    for scenario in $SCENARIOS; do
      for mode in $RUN_MODES; do
        run_case_0493w8 "$seed" "$scenario" "$mode"
      done
    done
  done
  cat "$RUN_ROOT/status_0493w8.csv"
  if grep -q ',FAIL,' "$RUN_ROOT/status_0493w8.csv"; then
    echo "[0493w8] FAIL runner" >&2
    exit 2
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "[0493w8] PASS preflight"
    exit 0
  fi
fi

read -r -a SEEDS_ARRAY <<< "$SEEDS"
python3 scripts/analyze_0493w8_tg_mono_dual_equivalence.py \
  --root "$RUN_ROOT" --nx "$NX" --ny "$NY" --dt "$DT" \
  --steps "$STEPS" --dump-every "$DUMP_EVERY" --tg-mode "$TG_MODE" \
  --tg-amplitude "$TG_AMPLITUDE" --thermal-amplitude "$THERMAL_AMPLITUDE" \
  --seeds "${SEEDS_ARRAY[@]}"

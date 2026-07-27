#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="tg_transport_0493k"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493k_tg_transport_matrix}"
NX="${NX:-32}"
NY="${NY:-32}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-300}"
DT="${DT:-0.002}"
DUMP_EVERY="${DUMP_EVERY:-10}"
SEEDS="${SEEDS:-493101}"
SCENARIOS="${SCENARIOS:-mono_legacy mono_species binary_species}"
RUN_MODES="${RUN_MODES:-src src-resampling src-q6 src-q6-resampling}"
THREADS="${THREADS:-8}"
TG_MODE="${TG_MODE:-1}"
TG_AMPLITUDE="${TG_AMPLITUDE:-0.08}"
COMPOSITION_AMPLITUDE="${COMPOSITION_AMPLITUDE:-0.15}"
THERMAL_AMPLITUDE="${THERMAL_AMPLITUDE:-0.04}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
INACTIVE_PER_CELL="${INACTIVE_PER_CELL:-8}"
GUARD_NMIN="${GUARD_NMIN:-$((GAMMA - 2))}"
GUARD_NTARGET="${GUARD_NTARGET:-$GAMMA}"
GUARD_NMAX="${GUARD_NMAX:-$((GAMMA + 2))}"
POOR_MASS_FRACTION="${POOR_MASS_FRACTION:-0.9}"
RICH_MASS_FRACTION="${RICH_MASS_FRACTION:-1.1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"

if (( NX < 8 || NY < 8 || GAMMA < 4 || GAMMA % 4 != 0 )); then
  echo "[0493k] ERROR NX/NY must be >=8 and GAMMA must be divisible by 4 and >=4" >&2
  exit 2
fi
if (( STEPS < DUMP_EVERY || DUMP_EVERY < 1 || STEPS % DUMP_EVERY != 0 )); then
  echo "[0493k] ERROR require STEPS>=DUMP_EVERY>=1 and STEPS divisible by DUMP_EVERY" >&2
  exit 2
fi
if (( TG_MODE < 1 || INACTIVE_PER_CELL < 2 )); then
  echo "[0493k] ERROR TG_MODE>=1 and INACTIVE_PER_CELL>=2 required" >&2
  exit 2
fi
python3 - "$DT" "$TG_AMPLITUDE" "$COMPOSITION_AMPLITUDE" "$THERMAL_AMPLITUDE" "$PARTICLE_MASS" <<'PY_VALIDATE'
import math, sys
vals=list(map(float,sys.argv[1:]))
if not all(math.isfinite(x) for x in vals):
    raise SystemExit('[0493k] ERROR non-finite physical parameter')
if vals[0] <= 0 or vals[1] <= 0 or not (0 < vals[2] < 0.45) or vals[3] < 0 or vals[4] <= 0:
    raise SystemExit('[0493k] ERROR require DT>0, U0>0, 0<composition<0.45, thermal>=0, mass>0')
PY_VALIDATE

for scenario in $SCENARIOS; do
  case "$scenario" in
    mono_legacy|mono_species|binary_species) ;;
    *) echo "[0493k] ERROR unsupported scenario=$scenario" >&2; exit 2 ;;
  esac
done
for mode in $RUN_MODES; do suite_validate_path_0434 "$mode"; done

export LIVE_PROGRESS OMP_NUM_THREADS="$THREADS"
CASE_LABEL="$CASE_LABEL"
Lx=1.0
Ly=1.0
KBT=0.0
U0=0.0
UIN=0.0
SUMMARY_EVERY="$DUMP_EVERY"
DUMP_STATE_EVERY="$DUMP_EVERY"
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
SPECIES_RESIDENT_MODE="${SPECIES_RESIDENT_MODE:-production}"
SPECIES_VALIDATION_MATERIALIZE_EVERY=1
RESAMPLING_PRODUCTION_STRIP=1
RESAMPLING_DIAG_CSV_ENABLE=0
RESAMPLING_FULL_GATE_ENABLE=0
RESAMPLING_REMAP_CELL_COUNT_DIAG_ENABLE=0
RESAMPLING_UPSTREAM_VALIDATE_ENABLE=0
RESAMPLING_OPERATION_MATERIALIZER_VALIDATE_ENABLE=0
RESAMPLING_HOST_PATCHBACK_ENABLE=0
RESAMPLING_SPARSE_DEVICE_GATE_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=true
RESAMPLING_MASS_GUARD_ENABLE=true
MASS_RECONDITION_ENABLE=0
GUARD_EVERY=1
RESTORE_ENABLE=1
RESAMPLING_SURVEY_ENABLE=0
RESAMPLING_ADAPTIVE_FLAG_ENABLE=0
FLAG_EVERY=1000000
CUDA_RESAMPLING_CHI_FILTER_ENABLE=false
RESAMPLING_EXTRACTION_ENABLE=true
RESAMPLING_INSERTION_ENABLE=true
RESAMPLING_REMAP_ENABLE=true
RESAMPLING_PARTICLE_MASS_MIN=0.05
RESAMPLING_PARTICLE_MASS_MAX=20.0
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=100
PROJECTION_TOLERANCE=1.0e-12
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true
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
INACTIVE_SLOTS=$((NX * NY * INACTIVE_PER_CELL))

suite_defaults_common_0434
suite_compute_derived_0434

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  if [[ "$CLEAN_RUN_ROOT" == 1 ]]; then rm -rf "$RUN_ROOT"; fi
  mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"
fi
if [[ "$PREFLIGHT_ONLY" != 1 && "$ANALYZE_ONLY" != 1 ]]; then
  suite_ensure_binary_0434
fi

MONO_STATE="$RUN_ROOT/init/tg_mono_0493k.smpcd"
BINARY_STATE="$RUN_ROOT/init/tg_binary_0493k.smpcd"
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

make_states_0493k() {
  python3 scripts/generate_0493k_tg_state.py \
    --output "$MONO_STATE" --scenario mono \
    --nx "$NX" --ny "$NY" --gamma "$GAMMA" --tg-mode "$TG_MODE" \
    --tg-amplitude "$TG_AMPLITUDE" --composition-amplitude "$COMPOSITION_AMPLITUDE" \
    --thermal-amplitude "$THERMAL_AMPLITUDE" --particle-mass "$PARTICLE_MASS" \
    --inactive-per-cell "$INACTIVE_PER_CELL"
  python3 scripts/generate_0493k_tg_state.py \
    --output "$BINARY_STATE" --scenario binary \
    --nx "$NX" --ny "$NY" --gamma "$GAMMA" --tg-mode "$TG_MODE" \
    --tg-amplitude "$TG_AMPLITUDE" --composition-amplitude "$COMPOSITION_AMPLITUDE" \
    --thermal-amplitude "$THERMAL_AMPLITUDE" --particle-mass "$PARTICLE_MASS" \
    --inactive-per-cell "$INACTIVE_PER_CELL"
}

mode_has_q6_0493k() {
  suite_path_has_q6_0434 "$1"
}

mode_has_resampling_0493k() {
  suite_path_has_resampling_0434 "$1"
}

write_species_block_0493k() {
  local scenario=$1 mode=$2
  local resampling_switch=false
  if mode_has_resampling_0493k "$mode"; then resampling_switch=true; fi
  case "$scenario" in
    mono_legacy)
      cat <<'EOF_SPECIES'
speciesRegistryEnable = false
speciesQ6Enable = false
EOF_SPECIES
      ;;
    mono_species)
      cat <<EOF_SPECIES
speciesRegistryEnable = true
speciesCount = 1
species0 = 1 tg_mono unspecified 1.0 1.0 $TARGET_CELL_MASS
species0ResamplingEnable = $resampling_switch
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = $(mode_has_q6_0493k "$mode" && echo true || echo false)
speciesQ6Mode = weighted
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesMassClosureCudaDiagnosticsFilename = cuda_species_mass_closure_0490i.csv
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490k.csv
speciesCudaResidentFastPathDiagnosticsFilename = cuda_species_resident_fast_path_0490m.csv
speciesCudaResidentMaintenanceDiagnosticsFilename = cuda_species_resident_maintenance_0490n.csv
EOF_SPECIES
      ;;
    binary_species)
      cat <<EOF_SPECIES
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 tg_species_A unspecified 1.0 1.0 $SPECIES_TARGET_CELL_MASS
species0ResamplingEnable = $resampling_switch
species1 = 2 tg_species_B unspecified 1.0 1.0 $SPECIES_TARGET_CELL_MASS
species1ResamplingEnable = $resampling_switch
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = $(mode_has_q6_0493k "$mode" && echo true || echo false)
speciesQ6Mode = weighted
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesMassClosureCudaDiagnosticsFilename = cuda_species_mass_closure_0490i.csv
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490k.csv
speciesCudaResidentFastPathDiagnosticsFilename = cuda_species_resident_fast_path_0490m.csv
speciesCudaResidentMaintenanceDiagnosticsFilename = cuda_species_resident_maintenance_0490n.csv
EOF_SPECIES
      ;;
  esac
}

write_params_0493k() {
  local case_dir=$1 scenario=$2 mode=$3 seed=$4
  local state="$MONO_STATE"
  [[ "$scenario" == binary_species ]] && state="$BINARY_STATE"
  local params="$case_dir/params/params_0493k.kv"
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
  write_species_block_0493k "$scenario" "$mode" >> "$params"

  # The current common helper requires empty-refill to be configured on every
  # resampling path.  0493k does not qualify it: the analyzer requires both
  # emptyRefillCells0319 and emptyRefillParticles0319 to remain exactly zero.
  suite_write_common_params_0434 "$mode" >> "$params"
  cat >> "$params" <<EOF_PARAMS
# 0493k: periodic unforced Taylor--Green transport qualification.
resamplingTargetCellMass = $TARGET_CELL_MASS
resamplingPoorCellMassFraction = $POOR_MASS_FRACTION
resamplingRichCellMassFraction = $RICH_MASS_FRACTION
EOF_PARAMS
  printf '%s\n' "$params"
}

run_case_0493k() {
  local seed=$1 scenario=$2 mode=$3
  SEED="$seed"
  if [[ "$scenario" == mono_legacy ]]; then
    SPECIES_RESAMPLING_ENABLE=false
  else
    SPECIES_RESAMPLING_ENABLE=true
  fi
  export SEED SPECIES_RESAMPLING_ENABLE
  local case_dir="$RUN_ROOT/seed_${seed}/$scenario/$mode"
  local params log time_file
  params="$(write_params_0493k "$case_dir" "$scenario" "$mode" "$seed")"
  log="$case_dir/logs/run_0493k.log"
  time_file="$case_dir/logs/time_0493k.txt"
  suite_export_cuda_flags_0434 "$mode" periodic
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 LIVE_PROGRESS
  if ! suite_preflight_run_ok_0492 "$params"; then
    echo "$seed,$scenario,$mode,FAIL,preflight" >> "$RUN_ROOT/status_0493k.csv"
    return 0
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "$seed,$scenario,$mode,PASS,preflight-only" >> "$RUN_ROOT/status_0493k.csv"
    return 0
  fi
  echo "[0493k] seed=$seed scenario=$scenario mode=$mode steps=$STEPS U0=$TG_AMPLITUDE composition=$COMPOSITION_AMPLITUDE"
  set +e
  /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" > "$log" 2>&1
  local rc=$?
  set -e
  local status=PASS reason=ok
  if [[ $rc -ne 0 ]]; then status=FAIL; reason="rc=$rc"; fi
  if grep -Eqi 'Fatal error|\[.*ERROR|CPU equivalence gate|host patchback|fallback.*CPU' "$log"; then
    status=FAIL; reason=forbidden-log-pattern
  fi
  echo "$seed,$scenario,$mode,$status,$reason" >> "$RUN_ROOT/status_0493k.csv"
  [[ "$status" == PASS ]] || tail -120 "$log" >&2 || true
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  make_states_0493k
  printf 'seed,scenario,mode,status,reason\n' > "$RUN_ROOT/status_0493k.csv"
  for seed in $SEEDS; do
    for scenario in $SCENARIOS; do
      for mode in $RUN_MODES; do
        run_case_0493k "$seed" "$scenario" "$mode"
      done
    done
  done
  cat "$RUN_ROOT/status_0493k.csv"
  if grep -q ',FAIL,' "$RUN_ROOT/status_0493k.csv"; then
    echo "[0493k] FAIL runner" >&2
    exit 2
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "[0493k] PASS preflight"
    exit 0
  fi
fi

read -r -a SEEDS_ARRAY <<< "$SEEDS"
read -r -a SCENARIOS_ARRAY <<< "$SCENARIOS"
read -r -a MODES_ARRAY <<< "$RUN_MODES"
python3 scripts/analyze_0493k_tg_transport.py \
  --root "$RUN_ROOT" --nx "$NX" --ny "$NY" --dt "$DT" \
  --steps "$STEPS" --dump-every "$DUMP_EVERY" --tg-mode "$TG_MODE" \
  --tg-amplitude "$TG_AMPLITUDE" --composition-amplitude "$COMPOSITION_AMPLITUDE" \
  --seeds "${SEEDS_ARRAY[@]}" --scenarios "${SCENARIOS_ARRAY[@]}" --modes "${MODES_ARRAY[@]}"

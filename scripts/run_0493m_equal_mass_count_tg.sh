#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="equal_mass_count_tg_0493m"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493m_equal_mass_count_tg_64_m2_1500}"
WEIGHT_REFERENCE_ROOT="${WEIGHT_REFERENCE_ROOT:-runs/0493k_tg_binary_64_m2_pilot_1500}"
NX="${NX:-64}"
NY="${NY:-64}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-1500}"
DT="${DT:-0.002}"
DUMP_EVERY="${DUMP_EVERY:-10}"
SEEDS="${SEEDS:-493101}"
RUN_MODES="${RUN_MODES:-src src-resampling}"
THREADS="${THREADS:-8}"
TG_MODE="${TG_MODE:-2}"
TG_AMPLITUDE="${TG_AMPLITUDE:-0.08}"
COMPOSITION_AMPLITUDE="${COMPOSITION_AMPLITUDE:-0.15}"
THERMAL_AMPLITUDE="${THERMAL_AMPLITUDE:-0.04}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
INACTIVE_PER_CELL="${INACTIVE_PER_CELL:-8}"
MIN_SPECIES_COUNT="${MIN_SPECIES_COUNT:-3}"
GUARD_NMIN="${GUARD_NMIN:-$((GAMMA - 2))}"
GUARD_NTARGET="${GUARD_NTARGET:-$GAMMA}"
GUARD_NMAX="${GUARD_NMAX:-$((GAMMA + 2))}"
POOR_MASS_FRACTION="${POOR_MASS_FRACTION:-0.9}"
RICH_MASS_FRACTION="${RICH_MASS_FRACTION:-1.1}"
WEIGHT_STEPS_LIST="${WEIGHT_STEPS_LIST:-0 200 400 800 1500}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"

for dep in \
  scripts/generate_0493m_equal_mass_count_tg_state.py \
  scripts/analyze_0493m_encoding_comparison.py \
  scripts/analyze_0493k_tg_transport.py \
  scripts/run_0493l_particle_weight_transport.sh; do
  [[ -f "$dep" ]] || { echo "[0493m] ERROR missing dependency $dep" >&2; exit 2; }
done

if (( NX < 8 || NY < 8 || GAMMA < 8 || GAMMA % 2 != 0 )); then
  echo "[0493m] ERROR NX/NY>=8 and even GAMMA>=8 required" >&2; exit 2
fi
if (( STEPS < DUMP_EVERY || DUMP_EVERY < 1 || STEPS % DUMP_EVERY != 0 )); then
  echo "[0493m] ERROR require STEPS>=DUMP_EVERY>=1 and STEPS divisible by DUMP_EVERY" >&2; exit 2
fi
for mode in $RUN_MODES; do
  case "$mode" in src|src-resampling|src-q6|src-q6-resampling) ;; *) echo "[0493m] ERROR unsupported mode=$mode" >&2; exit 2;; esac
  suite_validate_path_0434 "$mode"
done
for step in $WEIGHT_STEPS_LIST; do
  (( step >= 0 && step <= STEPS && step % DUMP_EVERY == 0 )) || {
    echo "[0493m] ERROR weight step $step must be in [0,$STEPS] and divisible by $DUMP_EVERY" >&2; exit 2;
  }
done

export LIVE_PROGRESS OMP_NUM_THREADS="$THREADS"
Lx=1.0; Ly=1.0; KBT=0.0; U0=0.0; UIN=0.0
SUMMARY_EVERY="$DUMP_EVERY"; DUMP_STATE_EVERY="$DUMP_EVERY"
DUMP_ROLE_FILTER=fluid; SUMMARY_ROLE_FILTER=fluid
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
RESAMPLING_PARTICLE_MASS_MIN=0.02
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
  [[ "$CLEAN_RUN_ROOT" == 1 ]] && rm -rf "$RUN_ROOT"
  mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"
fi
if [[ "$PREFLIGHT_ONLY" != 1 && "$ANALYZE_ONLY" != 1 ]]; then suite_ensure_binary_0434; fi

STATE="$RUN_ROOT/init/tg_binary_equal_mass_count_0493m.smpcd"
TARGET_CELL_MASS="$(python3 - "$GAMMA" "$PARTICLE_MASS" <<'PY'
import sys
print(int(sys.argv[1])*float(sys.argv[2]))
PY
)"
SPECIES_TARGET_CELL_MASS="$(python3 - "$TARGET_CELL_MASS" <<'PY'
import sys
print(0.5*float(sys.argv[1]))
PY
)"

make_state_0493m() {
  python3 scripts/generate_0493m_equal_mass_count_tg_state.py \
    --output "$STATE" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --tg-mode "$TG_MODE" --tg-amplitude "$TG_AMPLITUDE" \
    --composition-amplitude "$COMPOSITION_AMPLITUDE" \
    --thermal-amplitude "$THERMAL_AMPLITUDE" --particle-mass "$PARTICLE_MASS" \
    --inactive-per-cell "$INACTIVE_PER_CELL" --min-species-count "$MIN_SPECIES_COUNT"
}

mode_has_q6_0493m() { suite_path_has_q6_0434 "$1"; }
mode_has_resampling_0493m() { suite_path_has_resampling_0434 "$1"; }

write_species_block_0493m() {
  local mode=$1 switch=false
  mode_has_resampling_0493m "$mode" && switch=true
  cat <<EOF
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 tg_species_A unspecified 1.0 1.0 $SPECIES_TARGET_CELL_MASS
species0ResamplingEnable = $switch
species1 = 2 tg_species_B unspecified 1.0 1.0 $SPECIES_TARGET_CELL_MASS
species1ResamplingEnable = $switch
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = $(mode_has_q6_0493m "$mode" && echo true || echo false)
speciesQ6Mode = weighted
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesMassClosureCudaDiagnosticsFilename = cuda_species_mass_closure_0490i.csv
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490k.csv
speciesCudaResidentFastPathDiagnosticsFilename = cuda_species_resident_fast_path_0490m.csv
speciesCudaResidentMaintenanceDiagnosticsFilename = cuda_species_resident_maintenance_0490n.csv
EOF
}

write_params_0493m() {
  local case_dir=$1 mode=$2 seed=$3
  local params="$case_dir/params/params_0493m.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  cat > "$params" <<EOF
inputState = $STATE
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
EOF
  write_species_block_0493m "$mode" >> "$params"
  suite_write_common_params_0434 "$mode" >> "$params"
  cat >> "$params" <<EOF
# 0493m: equal-inertial-mass particles; composition encoded by N1/N2.
resamplingTargetCellMass = $TARGET_CELL_MASS
resamplingPoorCellMassFraction = $POOR_MASS_FRACTION
resamplingRichCellMassFraction = $RICH_MASS_FRACTION
EOF
  printf '%s\n' "$params"
}

run_case_0493m() {
  local seed=$1 mode=$2
  SEED="$seed"; SPECIES_RESAMPLING_ENABLE=true
  export SEED SPECIES_RESAMPLING_ENABLE
  local case_dir="$RUN_ROOT/seed_${seed}/binary_species/$mode"
  local params log time_file rc
  params="$(write_params_0493m "$case_dir" "$mode" "$seed")"
  log="$case_dir/logs/run_0493m.log"
  time_file="$case_dir/logs/time_0493m.txt"
  suite_export_cuda_flags_0434 "$mode" periodic
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 LIVE_PROGRESS
  if ! suite_preflight_run_ok_0492 "$params"; then
    echo "$seed,binary_species,$mode,FAIL,preflight" >> "$RUN_ROOT/status_0493m.csv"; return 0
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "$seed,binary_species,$mode,PASS,preflight-only" >> "$RUN_ROOT/status_0493m.csv"; return 0
  fi
  echo "[0493m] seed=$seed mode=$mode steps=$STEPS grid=${NX}x${NY} gamma=$GAMMA encoding=count_equal_mass"
  set +e
  if [[ "$LIVE_PROGRESS" == 1 || "$LIVE_PROGRESS" == true || "$LIVE_PROGRESS" == TRUE ]]; then
    stdbuf -oL -eL /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' \
      "$BIN" "$params" 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
  else
    /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' \
      "$BIN" "$params" > "$log" 2>&1
    rc=$?
  fi
  set -e
  local status=PASS reason=ok
  [[ $rc -eq 0 ]] || { status=FAIL; reason="rc=$rc"; }
  if grep -Eqi 'Fatal error|\[.*ERROR|CPU equivalence gate|host patchback|fallback.*CPU' "$log"; then
    status=FAIL; reason=forbidden-log-pattern
  fi
  echo "$seed,binary_species,$mode,$status,$reason" >> "$RUN_ROOT/status_0493m.csv"
  [[ "$status" == PASS ]] || tail -120 "$log" >&2 || true
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  make_state_0493m
  printf 'seed,scenario,mode,status,reason\n' > "$RUN_ROOT/status_0493m.csv"
  for seed in $SEEDS; do for mode in $RUN_MODES; do run_case_0493m "$seed" "$mode"; done; done
  cat "$RUN_ROOT/status_0493m.csv"
  if grep -q ',FAIL,' "$RUN_ROOT/status_0493m.csv"; then echo "[0493m] FAIL runner" >&2; exit 2; fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then echo "[0493m] PASS preflight"; exit 0; fi
fi

read -r -a seeds_array <<< "$SEEDS"
read -r -a modes_array <<< "$RUN_MODES"
set +e
python3 scripts/analyze_0493k_tg_transport.py \
  --root "$RUN_ROOT" --nx "$NX" --ny "$NY" --dt "$DT" --steps "$STEPS" \
  --dump-every "$DUMP_EVERY" --tg-mode "$TG_MODE" --tg-amplitude "$TG_AMPLITUDE" \
  --composition-amplitude "$COMPOSITION_AMPLITUDE" --seeds "${seeds_array[@]}" \
  --scenarios binary_species --modes "${modes_array[@]}"
audit_rc=$?
set -e

for seed in $SEEDS; do
  RUN_ROOT="$RUN_ROOT" SEED="$seed" SCENARIO=binary_species RUN_MODES="$RUN_MODES" \
  STEPS_LIST="$WEIGHT_STEPS_LIST" NX="$NX" NY="$NY" TG_MODE="$TG_MODE" \
  bash scripts/run_0493l_particle_weight_transport.sh

done

if [[ -f "$WEIGHT_REFERENCE_ROOT/tg_0493k_summary.csv" && -f "$WEIGHT_REFERENCE_ROOT/weight_transport_0493l_cells.csv" ]]; then
  python3 scripts/analyze_0493m_encoding_comparison.py \
    --count-root "$RUN_ROOT" --weight-root "$WEIGHT_REFERENCE_ROOT" \
    --seed "${seeds_array[0]}" --modes "${modes_array[@]}" --final-step "$STEPS"
else
  echo "[0493m] INFO reference comparison skipped; missing $WEIGHT_REFERENCE_ROOT summaries"
fi

if [[ $audit_rc -ne 0 ]]; then
  echo "[0493m] status=FAIL_PHYSICS audit_rc=$audit_rc diagnostics_completed=1" >&2
  exit "$audit_rc"
fi
echo "[0493m] status=PASS diagnostics_completed=1"

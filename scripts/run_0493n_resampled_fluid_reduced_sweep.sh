#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="resampled_fluid_reduced_sweep_0493n"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493n_resampled_fluid_reduced_sweep}"
STAGE="${STAGE:-core}"                       # core | grid | all
STEPS="${STEPS:-600}"
DT="${DT:-0.002}"
DUMP_EVERY="${DUMP_EVERY:-20}"
SEED="${SEED:-493101}"
THREADS="${THREADS:-8}"
TG_MODE="${TG_MODE:-2}"
TG_AMPLITUDE="${TG_AMPLITUDE:-0.08}"
THERMAL_AMPLITUDE="${THERMAL_AMPLITUDE:-0.04}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
INACTIVE_PER_CELL="${INACTIVE_PER_CELL:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-$([[ "$STAGE" == grid ]] && echo 0 || echo 1)}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
CASE_FILTER="${CASE_FILTER:-}"               # optional whitespace-separated case ids

# Historical nominal support band from the project report: 0.70/1.00/1.30 gamma.
NMIN_NUM="${NMIN_NUM:-7}"
NMIN_DEN="${NMIN_DEN:-10}"
NMAX_NUM="${NMAX_NUM:-13}"
NMAX_DEN="${NMAX_DEN:-10}"
POOR_MASS_FRACTION="${POOR_MASS_FRACTION:-0.9}"
RICH_MASS_FRACTION="${RICH_MASS_FRACTION:-1.1}"

for dep in \
  scripts/src_mpcd_run_common_0434.sh \
  scripts/generate_0493k_tg_state.py \
  scripts/analyze_0493k_tg_transport.py \
  scripts/run_0493l_particle_weight_transport.sh \
  scripts/analyze_0493n_resampled_fluid_reduced_sweep.py; do
  [[ -f "$dep" ]] || { echo "[0493n] ERROR missing dependency $dep" >&2; exit 2; }
done

case "$STAGE" in core|grid|all) ;; *) echo "[0493n] ERROR STAGE must be core, grid or all" >&2; exit 2;; esac
if (( STEPS < 200 || DUMP_EVERY < 1 || STEPS % DUMP_EVERY != 0 || STEPS % 2 != 0 )); then
  echo "[0493n] ERROR require STEPS>=200, even, and divisible by DUMP_EVERY" >&2; exit 2
fi
python3 - "$DT" "$TG_AMPLITUDE" "$THERMAL_AMPLITUDE" "$PARTICLE_MASS" <<'PY'
import math,sys
v=list(map(float,sys.argv[1:]))
if not all(math.isfinite(x) for x in v) or v[0] <= 0 or v[1] <= 0 or v[2] < 0 or abs(v[3]-1.0) > 1e-14:
    raise SystemExit('[0493n] ERROR require finite DT/U0/thermal and PARTICLE_MASS=1')
PY

export LIVE_PROGRESS OMP_NUM_THREADS="$THREADS"

selected_case() {
  local id=$1
  [[ -z "$CASE_FILTER" ]] && return 0
  local x
  for x in $CASE_FILTER; do [[ "$x" == "$id" ]] && return 0; done
  return 1
}

# case_id stage nx ny gamma guard_every modes reference_case
case_matrix() {
  if [[ "$STAGE" == core || "$STAGE" == all ]]; then
    cat <<'CASES'
g64_g10_e1,core,64,64,10,1,src+src-resampling,g64_g10_e1
g64_g20_e1,core,64,64,20,1,src+src-resampling,g64_g20_e1
g64_g40_e1,core,64,64,40,1,src+src-resampling,g64_g40_e1
g64_g20_e5,core,64,64,20,5,src-resampling,g64_g20_e1
g64_g20_e20,core,64,64,20,20,src-resampling,g64_g20_e1
CASES
  fi
  if [[ "$STAGE" == grid || "$STAGE" == all ]]; then
    cat <<'CASES'
g128_g20_e1,grid,128,128,20,1,src+src-resampling,g128_g20_e1
CASES
  fi
}

round_ratio() {
  local n=$1 num=$2 den=$3
  echo $(( (n * num + den / 2) / den ))
}

mode_list() {
  [[ "$1" == "src+src-resampling" ]] && echo "src src-resampling" || echo "$1"
}

prepare_case_environment() {
  local nx=$1 ny=$2 gamma=$3 guard_every=$4 nmin=$5 ntarget=$6 nmax=$7
  NX=$nx; NY=$ny; GAMMA=$gamma
  GUARD_EVERY=$guard_every
  GUARD_NMIN=$nmin; GUARD_NTARGET=$ntarget; GUARD_NMAX=$nmax
  Lx=1.0; Ly=1.0; KBT=0.0; U0=0.0; UIN=0.0
  SUMMARY_EVERY=$DUMP_EVERY; DUMP_STATE_EVERY=$DUMP_EVERY
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
  EMPTY_REFILL_GAMMA=$GAMMA
  suite_defaults_common_0434
  suite_compute_derived_0434
  export NX NY GAMMA GUARD_EVERY GUARD_NMIN GUARD_NTARGET GUARD_NMAX INACTIVE_SLOTS
}

write_species_block() {
  local mode=$1 switch=false
  suite_path_has_resampling_0434 "$mode" && switch=true
  cat <<EOF_SPECIES
speciesRegistryEnable = true
speciesCount = 1
species0 = 1 tg_mono unspecified 1.0 1.0 $GAMMA
species0ResamplingEnable = $switch
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = false
speciesQ6Mode = weighted
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesMassClosureCudaDiagnosticsFilename = cuda_species_mass_closure_0490i.csv
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490k.csv
speciesCudaResidentFastPathDiagnosticsFilename = cuda_species_resident_fast_path_0490m.csv
speciesCudaResidentMaintenanceDiagnosticsFilename = cuda_species_resident_maintenance_0490n.csv
EOF_SPECIES
}

write_params() {
  local case_root=$1 state=$2 mode=$3
  local run_dir="$case_root/seed_${SEED}/mono_species/$mode"
  local params="$run_dir/params/params_0493n.kv"
  mkdir -p "$run_dir/params" "$run_dir/output" "$run_dir/logs"
  cat > "$params" <<EOF_PARAMS
inputState = $state
outputDir = $run_dir/output
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
rngSeed = $SEED
EOF_PARAMS
  write_species_block "$mode" >> "$params"
  suite_write_common_params_0434 "$mode" >> "$params"
  cat >> "$params" <<EOF_PARAMS
# 0493n: active mono-species resident-CUDA resampled-fluid sweep.
# Population cadence is the actual CUDA 0297 split/merge cadence exported by the runner.
resamplingTargetCellMass = $GAMMA
resamplingPoorCellMassFraction = $POOR_MASS_FRACTION
resamplingRichCellMassFraction = $RICH_MASS_FRACTION
EOF_PARAMS
  printf '%s\n' "$params"
}

run_mode() {
  local case_id=$1 case_root=$2 state=$3 mode=$4
  local run_dir="$case_root/seed_${SEED}/mono_species/$mode"
  local params log time_file rc status reason
  SPECIES_RESAMPLING_ENABLE=true
  export SEED SPECIES_RESAMPLING_ENABLE
  params="$(write_params "$case_root" "$state" "$mode")"
  log="$run_dir/logs/run_0493n.log"
  time_file="$run_dir/logs/time_0493k.txt" # name consumed by the existing 0493k analyzer
  suite_export_cuda_flags_0434 "$mode" periodic
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 LIVE_PROGRESS
  if ! suite_preflight_run_ok_0492 "$params"; then
    echo "$case_id,$mode,FAIL,preflight" >> "$RUN_ROOT/status_0493n.csv"; return 0
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "$case_id,$mode,PASS,preflight-only" >> "$RUN_ROOT/status_0493n.csv"; return 0
  fi
  echo "[0493n] case=$case_id mode=$mode grid=${NX}x${NY} gamma=$GAMMA guardEvery=$GUARD_EVERY band=${GUARD_NMIN}:${GUARD_NTARGET}:${GUARD_NMAX} steps=$STEPS"
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
  status=PASS; reason=ok
  [[ $rc -eq 0 ]] || { status=FAIL; reason="rc=$rc"; }
  if grep -Eqi 'Fatal error|\[.*ERROR|CPU equivalence gate|host patchback|fallback.*CPU' "$log"; then
    status=FAIL; reason=forbidden-log-pattern
  fi
  echo "$case_id,$mode,$status,$reason" >> "$RUN_ROOT/status_0493n.csv"
  [[ "$status" == PASS ]] || tail -120 "$log" >&2 || true
}

analyze_case() {
  local case_id=$1 case_root=$2 nx=$3 ny=$4 gamma=$5 modes=$6
  read -r -a mode_array <<< "$modes"
  set +e
  python3 scripts/analyze_0493k_tg_transport.py \
    --root "$case_root" --nx "$nx" --ny "$ny" --dt "$DT" \
    --steps "$STEPS" --dump-every "$DUMP_EVERY" --tg-mode "$TG_MODE" \
    --tg-amplitude "$TG_AMPLITUDE" --composition-amplitude 0.15 \
    --seeds "$SEED" --scenarios mono_species --modes "${mode_array[@]}"
  local audit_rc=$?
  set -e
  echo "[0493n] case=$case_id 0493kAuditRc=$audit_rc (informational; 0493n uses dedicated go/no-go criteria)"

  local mid=$((STEPS / 2))
  mid=$((mid / DUMP_EVERY * DUMP_EVERY))
  RUN_ROOT="$case_root" SEED="$SEED" SCENARIO=mono_species RUN_MODES="$modes" \
    STEPS_LIST="0 $mid $STEPS" NX="$nx" NY="$ny" TG_MODE="$TG_MODE" OUTPUT_DIR="$case_root" \
    bash scripts/run_0493l_particle_weight_transport.sh
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  [[ "$CLEAN_RUN_ROOT" == 1 ]] && rm -rf "$RUN_ROOT"
  mkdir -p "$RUN_ROOT/cases"
  [[ -f "$RUN_ROOT/status_0493n.csv" ]] || printf 'case_id,mode,status,reason\n' > "$RUN_ROOT/status_0493n.csv"
  [[ -f "$RUN_ROOT/case_manifest_0493n.csv" ]] || printf 'case_id,stage,nx,ny,gamma,guard_every,nmin,ntarget,nmax,modes,reference_case,case_root\n' > "$RUN_ROOT/case_manifest_0493n.csv"

  # Resume-safe: replace only the selected cases, preserving a preceding core stage
  # when STAGE=grid is launched with the default CLEAN_RUN_ROOT=0.
  selected_ids="$(case_matrix | cut -d, -f1 | tr '\n' ' ')"
  python3 - "$RUN_ROOT/case_manifest_0493n.csv" "$RUN_ROOT/status_0493n.csv" "$selected_ids" <<'PY_PRUNE'
import csv,sys
from pathlib import Path
selected=set(sys.argv[3].split())
for name in sys.argv[1:3]:
    p=Path(name)
    rows=list(csv.reader(p.open(newline='',encoding='utf-8')))
    if not rows: continue
    kept=[rows[0]]+[r for r in rows[1:] if r and r[0] not in selected]
    with p.open('w',newline='',encoding='utf-8') as f: csv.writer(f).writerows(kept)
PY_PRUNE
  [[ "$PREFLIGHT_ONLY" == 1 ]] || suite_ensure_binary_0434

  while IFS=',' read -r case_id case_stage nx ny gamma guard_every modes_token reference_case; do
    selected_case "$case_id" || continue
    nmin="$(round_ratio "$gamma" "$NMIN_NUM" "$NMIN_DEN")"
    nmax="$(round_ratio "$gamma" "$NMAX_NUM" "$NMAX_DEN")"
    ntarget=$gamma
    modes="$(mode_list "$modes_token")"
    case_root="$RUN_ROOT/cases/$case_id"
    mkdir -p "$case_root/init"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$case_id" "$case_stage" "$nx" "$ny" "$gamma" "$guard_every" "$nmin" "$ntarget" "$nmax" \
      "$modes" "$reference_case" "$case_root" >> "$RUN_ROOT/case_manifest_0493n.csv"

    prepare_case_environment "$nx" "$ny" "$gamma" "$guard_every" "$nmin" "$ntarget" "$nmax"
    state="$case_root/init/tg_mono_0493n.smpcd"
    python3 scripts/generate_0493k_tg_state.py \
      --output "$state" --scenario mono --nx "$nx" --ny "$ny" --gamma "$gamma" \
      --tg-mode "$TG_MODE" --tg-amplitude "$TG_AMPLITUDE" \
      --composition-amplitude 0.15 --thermal-amplitude "$THERMAL_AMPLITUDE" \
      --particle-mass "$PARTICLE_MASS" --inactive-per-cell "$INACTIVE_PER_CELL"
    for mode in $modes; do run_mode "$case_id" "$case_root" "$state" "$mode"; done
  done < <(case_matrix)

  cat "$RUN_ROOT/status_0493n.csv"
  if grep -q ',FAIL,' "$RUN_ROOT/status_0493n.csv"; then
    echo "[0493n] FAIL runner" >&2; exit 2
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "[0493n] PASS preflight stage=$STAGE"; exit 0
  fi
fi

while IFS=',' read -r case_id case_stage nx ny gamma guard_every nmin ntarget nmax modes reference_case case_root; do
  [[ "$case_id" == case_id ]] && continue
  selected_case "$case_id" || continue
  analyze_case "$case_id" "$case_root" "$nx" "$ny" "$gamma" "$modes"
done < "$RUN_ROOT/case_manifest_0493n.csv"

python3 scripts/analyze_0493n_resampled_fluid_reduced_sweep.py \
  --root "$RUN_ROOT" --steps "$STEPS" --tg-amplitude "$TG_AMPLITUDE"

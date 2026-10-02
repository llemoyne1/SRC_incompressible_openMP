#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

# -----------------------------------------------------------------------------
# 0493x23a -- JCP Sec. 4.1 forced Taylor--Green validation.
# Two runs only, from ONE shared particle state:
#   A = SRC
#   B = SRC + particle/field liquid closure (internal path src-q6-g-f)
# No solver/CUDA physics is modified by this runner.
# -----------------------------------------------------------------------------
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
AUTO_ANALYZE="${AUTO_ANALYZE:-1}"
CLEAN_ARTICLE_ROOT="${CLEAN_ARTICLE_ROOT:-1}"

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  ARTICLE_ROOT="${ARTICLE_ROOT:-article_forced_tg_validation_preflight}"
else
  ARTICLE_ROOT="${ARTICLE_ROOT:-article_forced_tg_validation}"
fi

# Frozen nominal article point + historically discriminating continuous forcing.
CASE_LABEL="article_forced_tg"
GEN_CASE="tg"
TOPOLOGY="periodic"
Lx="1.0"
Ly="1.0"
NX="256"
NY="256"
GAMMA="8"
DT="0.0063471328149122585"
KBT="0.125"
PARTICLE_MASS="1.0"
ROTATION_ANGLE="2.0943951023931953"
RANDOM_ROTATION_SIGN="true"
GRID_SHIFT_ENABLE="true"
THERMOSTAT_ENABLE="true"
THERMOSTAT_MODE="cell_relative_rescale"
THERMOSTAT_EVERY="1"
THERMOSTAT_TARGET_KBT="$KBT"
THERMOSTAT_MIN_PARTICLES="3"
SEED="1628605"
U0="0.05"
VELOCITY_MODE="taylor_green"
TG_HOLE_ENABLE=false
TG_FORCING_AMPLITUDE="0.2"
TG_FORCING_MODE_X="1"
TG_FORCING_MODE_Y="1"

STEPS="10000"
DUMP_STATE_EVERY="125"
SUMMARY_EVERY="100"
INACTIVE_SLOTS_CELL_FRACTION="1.25"

# No resampling or recording; dumps are the source of truth.
SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
LIVE_VIS_ENABLE=0
LIVE_VIS_CONTROL_FILE=/dev/null
LIVE_VIS_HOLD_ON_EXIT=0
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false
PARTICLE_TYPE_FILTER=-1

# Current qualified liquid-closure production profile, exactly as run_ok_tg/x7r.
RUN_OK_PROJECTION_BACKEND="cuda"
RUN_OK_PROJECTION_OPERATOR="auto_fv_cg"
RUN_OK_PROJECTION_MAX_ITERATIONS="800"
RUN_OK_PROJECTION_TOLERANCE="1.0e-5"
RUN_OK_Q6_STRICT="1"
RUN_OK_PROJECTION_MOMENTUM_CORRECTION_ENABLE="true"
RUN_OK_Q6_GF_DENSITY_RELAXATION_TIME="0.25"
RUN_OK_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="1"
RUN_OK_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="3"
RUN_OK_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="6"
RUN_OK_Q6_GF_DENSITY_TRACTION_GAIN="1.0"
RUN_OK_Q6_GF_MIN_FILL_FRACTION="0.10"

PROJECTION_BACKEND="$RUN_OK_PROJECTION_BACKEND"
PROJECTION_OPERATOR="$RUN_OK_PROJECTION_OPERATOR"
PROJECTION_MAX_ITERATIONS="$RUN_OK_PROJECTION_MAX_ITERATIONS"
PROJECTION_TOLERANCE="$RUN_OK_PROJECTION_TOLERANCE"
Q6_STRICT="$RUN_OK_Q6_STRICT"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="$RUN_OK_PROJECTION_MOMENTUM_CORRECTION_ENABLE"
Q6_GF_DENSITY_RELAXATION_TIME="$RUN_OK_Q6_GF_DENSITY_RELAXATION_TIME"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="$RUN_OK_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="$RUN_OK_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="$RUN_OK_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES"
Q6_GF_DENSITY_TRACTION_GAIN="$RUN_OK_Q6_GF_DENSITY_TRACTION_GAIN"
Q6_GF_MIN_FILL_FRACTION="$RUN_OK_Q6_GF_MIN_FILL_FRACTION"
Q6_GF_SPECIES_DIAGNOSTICS_ENABLE=false
Q6_PROJECTION_STRENGTH=1.0
export MPCD_INTERNAL_PROFILES=0
Q6_GF_EXTERNAL_SPECIES=0
Q6_GF_HAS_GAS_PHASE=0

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
EXPECTED_BIN_SHA256="${EXPECTED_BIN_SHA256:-422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc}"
ALLOW_BINARY_SHA_MISMATCH="${ALLOW_BINARY_SHA_MISMATCH:-0}"

# Values consumed by common helper defaults.
RUN_MODES="src src-q6-g-f"
RESAMPLING_NMIN_COEF="0.40"
RESAMPLING_NMAX_COEF="0.60"
GUARD_EVERY="5"
THREADS="${THREADS:-8}"
BACKGROUND_TYPE="0"
INACTIVE_TYPE="4294967295"

suite_defaults_common_0434
suite_compute_derived_0434

run_ok_export_q6_cuda_profile_0493x23a() {
  local mode=$1
  if suite_path_has_q6_g_f_0493x7h "$mode"; then
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
    export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  else
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=0
    export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  fi
}

write_params_0493x23a() {
  local mode=$1 out=$2 params=$3 shared_state=$4
  cat > "$params" <<PARAMS
inputState = ${shared_state}
outputDir = ${out}
Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}
dt = ${DT}
nSteps = ${STEPS}
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = true
taylorGreenForcingAmplitude = ${TG_FORCING_AMPLITUDE}
taylorGreenForcingModeX = ${TG_FORCING_MODE_X}
taylorGreenForcingModeY = ${TG_FORCING_MODE_Y}
PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
}

check_binary_0493x23a() {
  [[ -x "$BIN" ]] || {
    echo "[0493x23a] ERROR frozen binary missing/not executable: $BIN" >&2
    return 2
  }
  local got
  got="$(sha256sum "$BIN" | awk '{print $1}')"
  if [[ "$got" != "$EXPECTED_BIN_SHA256" ]]; then
    if suite_truthy_0434 "$ALLOW_BINARY_SHA_MISMATCH"; then
      echo "[0493x23a] WARNING binary SHA mismatch expected=$EXPECTED_BIN_SHA256 got=$got" >&2
    else
      echo "[0493x23a] ERROR binary SHA mismatch expected=$EXPECTED_BIN_SHA256 got=$got" >&2
      echo "[0493x23a] Set ALLOW_BINARY_SHA_MISMATCH=1 only if this change is intentional." >&2
      return 2
    fi
  else
    echo "[0493x23a] frozen binary SHA256 PASS $got"
  fi
}

prepare_layout_0493x23a() {
  if suite_truthy_0434 "$CLEAN_ARTICLE_ROOT"; then rm -rf "$ARTICLE_ROOT"; fi
  mkdir -p "$ARTICLE_ROOT"/{init,data,figures,scripts,params,logs,runs/src/output,runs/closure/output}
  cp scripts/analyze_article_forced_tg_0493x23a.py "$ARTICLE_ROOT/scripts/analyze_article_forced_tg.py"
  cp scripts/check_0493x23a_article_forced_tg_preflight.py "$ARTICLE_ROOT/scripts/check_preflight.py"
}

shared_state="$ARTICLE_ROOT/init/initial_forced_tg.smpcd"
src_params="$ARTICLE_ROOT/params/src_params_used.kv"
closure_params="$ARTICLE_ROOT/params/closure_params_used.kv"

prepare_layout_0493x23a
check_binary_0493x23a

# Create the two parameter files before any simulation; both point to exactly
# the same shared state path.
write_params_0493x23a src "$ARTICLE_ROOT/runs/src/output" "$src_params" "$shared_state"
write_params_0493x23a src-q6-g-f "$ARTICLE_ROOT/runs/closure/output" "$closure_params" "$shared_state"

# Preflight each mode with the exact production CUDA routing.
for mode in src src-q6-g-f; do
  if [[ "$mode" == src ]]; then
    params="$src_params"; run_dir="$ARTICLE_ROOT/runs/src"
  else
    params="$closure_params"; run_dir="$ARTICLE_ROOT/runs/closure"
  fi
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  run_ok_export_q6_cuda_profile_0493x23a "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$ARTICLE_ROOT/logs/environment_${mode}.env" "$mode"
  suite_preflight_run_ok_0492 "$params"
done

python3 scripts/check_0493x23a_article_forced_tg_preflight.py \
  --src "$src_params" --closure "$closure_params" \
  --expected-nx "$NX" --expected-ny "$NY" --expected-gamma "$GAMMA" \
  --expected-dt "$DT" --expected-kbt "$KBT" --expected-angle "$ROTATION_ANGLE" \
  --expected-force "$TG_FORCING_AMPLITUDE" --expected-mode-x "$TG_FORCING_MODE_X" \
  --expected-mode-y "$TG_FORCING_MODE_Y" --expected-steps "$STEPS" \
  --expected-dump-every "$DUMP_STATE_EVERY"

cat > "$ARTICLE_ROOT/README.txt" <<README
JCP Section 4.1 forced Taylor--Green validation (0493x23a)

Two simulations only:
  SRC
  SRC + particle/field closure (internal path: src-q6-g-f)

Both simulations read exactly the same initial particle state:
  $shared_state

Nominal point:
  grid=${NX}x${NY}, L=${Lx}x${Ly}, gamma=${GAMMA}, h=$(awk -v l="$Lx" -v n="$NX" 'BEGIN{printf "%.17g",l/n}')
  dt=${DT}, kBT=${KBT}, mass=${PARTICLE_MASS}, alpha=${ROTATION_ANGLE} rad
  U0=${U0}, continuous TG forcing amplitude=${TG_FORCING_AMPLITUDE}, mode=(${TG_FORCING_MODE_X},${TG_FORCING_MODE_Y})
  steps=${STEPS}, dumpEvery=${DUMP_STATE_EVERY}, summaryEvery=${SUMMARY_EVERY}
  LiveVis=OFF, filtered recording=OFF, resampling=OFF
README

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo "[0493x23a] PREFLIGHT PASS articleRoot=$ARTICLE_ROOT"
  echo "[0493x23a] no state generated and no solver launched"
  exit 0
fi

# One and only one initial particle state is generated for both modes.
echo "[0493x23a] generating shared initial state: $shared_state"
suite_generate_case_0434 "$shared_state" ""
state_sha="$(sha256sum "$shared_state" | awk '{print $1}')"
echo "[0493x23a] shared initial state SHA256=$state_sha"

# Freeze run traceability before launch.
{
  echo "campaign=0493x23a_article_forced_tg_validation"
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_head=$(git rev-parse HEAD 2>/dev/null || echo unavailable)"
  echo "git_dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  echo "binary=$BIN"
  echo "binary_sha256=$(sha256sum "$BIN" | awk '{print $1}')"
  echo "initial_state=$shared_state"
  echo "initial_state_sha256=$state_sha"
  echo "grid=${NX}x${NY}"
  echo "Lx=$Lx"
  echo "Ly=$Ly"
  echo "gamma=$GAMMA"
  echo "particleMass=$PARTICLE_MASS"
  echo "dt=$DT"
  echo "kBT=$KBT"
  echo "rotationAngle=$ROTATION_ANGLE"
  echo "randomRotationSign=$RANDOM_ROTATION_SIGN"
  echo "gridShiftEnable=$GRID_SHIFT_ENABLE"
  echo "thermostatMode=$THERMOSTAT_MODE"
  echo "seed=$SEED"
  echo "U0=$U0"
  echo "taylorGreenForcingEnable=true"
  echo "taylorGreenForcingAmplitude=$TG_FORCING_AMPLITUDE"
  echo "taylorGreenForcingModeX=$TG_FORCING_MODE_X"
  echo "taylorGreenForcingModeY=$TG_FORCING_MODE_Y"
  echo "steps=$STEPS"
  echo "dumpEvery=$DUMP_STATE_EVERY"
  echo "summaryEvery=$SUMMARY_EVERY"
  echo "srcInternalPath=src"
  echo "closureInternalPath=src-q6-g-f"
  echo "closureResidentCG0493x7j=1"
  echo "closureSingleBlock0407=0"
  echo "projectionTolerance=$PROJECTION_TOLERANCE"
  echo "projectionMaxIterations=$PROJECTION_MAX_ITERATIONS"
  echo "q6DensityRelaxationTime=$Q6_GF_DENSITY_RELAXATION_TIME"
  echo "q6CompressionThresholdParticles=$Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES"
  echo "q6TractionThresholdParticles=$Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES"
  echo "q6TractionGain=$Q6_GF_DENSITY_TRACTION_GAIN"
  echo "q6MinFillFraction=$Q6_GF_MIN_FILL_FRACTION"
} > "$ARTICLE_ROOT/traceability.txt"

printf 'mode,status,elapsed_s\n' > "$ARTICLE_ROOT/logs/run_status.csv"

run_one_0493x23a() {
  local mode=$1 label=$2 run_subdir=$3 params=$4
  local run_dir="$ARTICLE_ROOT/runs/$run_subdir"
  local log="$ARTICLE_ROOT/logs/${run_subdir}.log"
  local timef="$ARTICLE_ROOT/logs/${run_subdir}.time"
  mkdir -p "$run_dir/output"

  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  run_ok_export_q6_cuda_profile_0493x23a "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$ARTICLE_ROOT/logs/environment_${run_subdir}.env" "$mode"

  echo "============================================================"
  echo "[0493x23a] START $label internalMode=$mode"
  echo "[0493x23a] sharedState=$shared_state sha256=$state_sha"
  echo "============================================================"

  local rc=0
  /usr/bin/time -o "$timef" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" | tee "$log" || rc=$?
  if [[ "$rc" != 0 ]]; then
    printf '%s,FAIL,\n' "$label" >> "$ARTICLE_ROOT/logs/run_status.csv"
    echo "[0493x23a] ERROR $label rc=$rc" >&2
    tail -100 "$log" >&2 || true
    return "$rc"
  fi
  local elapsed
  elapsed="$(sed -n 's/.*elapsed=\([^ ]*\).*/\1/p' "$timef" | tail -1)"
  printf '%s,PASS,%s\n' "$label" "$elapsed" >> "$ARTICLE_ROOT/logs/run_status.csv"
  echo "[0493x23a] DONE $label $(cat "$timef")"
}

run_one_0493x23a src "SRC" src "$src_params"
run_one_0493x23a src-q6-g-f "SRC + particle/field closure" closure "$closure_params"

# Reconfirm that both parameter files still reference the one initial state.
python3 scripts/check_0493x23a_article_forced_tg_preflight.py \
  --src "$src_params" --closure "$closure_params" \
  --expected-nx "$NX" --expected-ny "$NY" --expected-gamma "$GAMMA" \
  --expected-dt "$DT" --expected-kbt "$KBT" --expected-angle "$ROTATION_ANGLE" \
  --expected-force "$TG_FORCING_AMPLITUDE" --expected-mode-x "$TG_FORCING_MODE_X" \
  --expected-mode-y "$TG_FORCING_MODE_Y" --expected-steps "$STEPS" \
  --expected-dump-every "$DUMP_STATE_EVERY"

if suite_truthy_0434 "$AUTO_ANALYZE"; then
  python3 scripts/analyze_article_forced_tg_0493x23a.py --root "$ARTICLE_ROOT"
else
  echo "[0493x23a] runs complete; analyze with:"
  echo "  python3 scripts/analyze_article_forced_tg_0493x23a.py --root '$ARTICLE_ROOT'"
fi

echo "[0493x23a] COMPLETE root=$ARTICLE_ROOT"

#!/usr/bin/env bash
set -euo pipefail

# 0493o0 -- SRC-only periodic Taylor--Green baseline.
# Physical-reference bench for the future asymmetric resampling development.
# No Q6, no mutating resampling operation. Passive support diagnostics remain on.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="0493o0_src_baseline_tg"
GEN_CASE="tg"
TOPOLOGY="periodic"
MODE="src"

Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
NX="${NX:-64}"
NY="${NY:-64}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-2000}"
DT="${DT:-0.001}"
KBT="${KBT:-0.01}"
U0="${U0:-0.08}"
SEED="${SEED:-493001}"
VELOCITY_MODE="${VELOCITY_MODE:-taylor_green}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:--1.0}"

SUMMARY_EVERY="${SUMMARY_EVERY:-20}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-50}"
THREADS="${THREADS:-8}"
INACTIVE_SLOTS_PER_CELL="${INACTIVE_SLOTS_PER_CELL:-8}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((NX * NY * INACTIVE_SLOTS_PER_CELL))}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493o0_src_baseline_dual_bench/tg}"
RUN_ROOT="${RUN_ROOT:-$BASE_RUN_ROOT}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

# User-facing execution controls.  The control file is deliberately hard-wired
# to the repository root; runners must never create a case-local control file.
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-10}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"
LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
OVERWRITE_LIVEVIS_CONTROL="${OVERWRITE_LIVEVIS_CONTROL:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_SESSION_PREFIX="${RECORD_SESSION_PREFIX:-0493o0_src_baseline}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-$DUMP_STATE_EVERY}"
RECORD_STRIDE="${RECORD_STRIDE:-1}"

RESAMPLING_SURVEY_EVERY="${RESAMPLING_SURVEY_EVERY:-$SUMMARY_EVERY}"
FLAG_EVERY="${FLAG_EVERY:-$SUMMARY_EVERY}"
SUPPORT_TRIGGER_NMIN="${SUPPORT_TRIGGER_NMIN:-$(( (3 * GAMMA + 4) / 5 ))}"
OUTLIER_U_THRESHOLD="${OUTLIER_U_THRESHOLD:-1.0}"

suite_defaults_common_0434
suite_compute_derived_0434
suite_prepare_dirs_0434 "$RUN_ROOT"

STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIME="$RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"

suite_generate_case_0434 "$STATE"

cat > "$PARAMS" <<PARAMS
inputState = ${STATE}
outputDir = ${OUT}
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
openBoundarySegmentsEnable = false
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
$(suite_write_common_params_0434 "$MODE")
PARAMS

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"

# Passive population/support observability on a strictly SRC-only run.
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=1
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="$RESAMPLING_SURVEY_EVERY"
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE=full
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=1
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY="$FLAG_EVERY"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN="$SUPPORT_TRIGGER_NMIN"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY=1
export MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U="$OUTLIER_U_THRESHOLD"
export MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD="$OUTLIER_U_THRESHOLD"
export MPCD_INTERNAL_PROFILES="${MPCD_INTERNAL_PROFILES:-1}"
export MPCD_CUDA_RESIDENT_PROFILE_0266="${MPCD_CUDA_RESIDENT_PROFILE_0266:-1}"

# Hard assertion: no mutating resampling brick may be enabled in this baseline.
export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
export MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$MODE"
[[ "$LIVE_VIS_CONTROL_FILE" == "$ROOT/livevis_control.kv" ]] || {
  echo "[0493o0-tg] ERROR livevis control escaped repository root: $LIVE_VIS_CONTROL_FILE" >&2
  exit 2
}
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493o0.env" "$MODE"
cat >> "$RUN_ROOT/logs/environment_0493o0.env" <<META
MPCD_INTERNAL_PROFILES=${MPCD_INTERNAL_PROFILES}
MPCD_CUDA_RESIDENT_PROFILE_0266=${MPCD_CUDA_RESIDENT_PROFILE_0266}
RESAMPLING_SURVEY_EVERY=${RESAMPLING_SURVEY_EVERY}
FLAG_EVERY=${FLAG_EVERY}
SUPPORT_TRIGGER_NMIN=${SUPPORT_TRIGGER_NMIN}
META

printf '[0493o0-tg] SRC-only periodic Taylor--Green\n'
printf '[0493o0-tg] grid=%sx%s gamma=%s active~%s inactive=%s steps=%s dt=%s\n' \
  "$NX" "$NY" "$GAMMA" "$((NX * NY * GAMMA))" "$INACTIVE_SLOTS" "$STEPS" "$DT"
printf '[0493o0-tg] live_progress=%s livevis=%s control=%s every=%s\n' \
  "$LIVE_PROGRESS" "$LIVE_VIS_ENABLE" "$LIVE_VIS_CONTROL_FILE" "$LIVE_VIS_EVERY"
printf '[0493o0-tg] summaryEvery=%s dumpEvery=%s surveyEvery=%s flagEvery=%s\n' \
  "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$RESAMPLING_SURVEY_EVERY" "$FLAG_EVERY"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME" "$OUT"

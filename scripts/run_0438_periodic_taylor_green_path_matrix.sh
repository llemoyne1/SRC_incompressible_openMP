#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# -----------------------------------------------------------------------------
# 0438 periodic wall-free path-equivalence runner: unforced Taylor-Green decay.
# No wall, no solid/chi/Darcy, no inlet/outlet, no new solver parameter.
# -----------------------------------------------------------------------------
CASE_LABEL="periodic_taylor_green_0438"
GEN_CASE="tg"
TOPOLOGY="periodic"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-64}"; NY="${NY:-64}"
GAMMA="${GAMMA:-40}"; STEPS="${STEPS:-1000}"; DT="${DT:-0.001}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628640}"; U0="${U0:-0.04}"; VELOCITY_MODE="${VELOCITY_MODE:-taylor_green}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0438_periodic_taylor_green_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.25}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-$STEPS}"
RUN_MODES="${RUN_MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src src-resampling src-q6 src-q6-resampling}}}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-vorticity}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-25}"
LIVE_VIS_NX="${LIVE_VIS_NX:-128}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-10.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-4}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"; RECORD_STRIDE="${RECORD_STRIDE:-1}"
FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-1}"

RESAMPLING_NMIN_COEF="${RESAMPLING_NMIN_COEF:-0.40}"
RESAMPLING_NMAX_COEF="${RESAMPLING_NMAX_COEF:-0.60}"
GUARD_EVERY="${GUARD_EVERY:-5}"
TG_HOLE_ENABLE="false"
FAIL_ON_ANY="${FAIL_ON_ANY:-1}"

suite_defaults_common_0434
suite_compute_derived_0434

write_params_0438() {
  local mode=$1 state=$2 out=$3 params=$4
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
}

run_one_mode_0438() {
  local mode=$1
  suite_validate_path_0434 "$mode"
  local run_root="$BASE_RUN_ROOT/$mode"
  suite_prepare_dirs_0434 "$run_root"
  local state="$run_root/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
  local chi=""
  local params="$run_root/params/${CASE_LABEL}.kv"
  local out="$run_root/output"
  local log="$run_root/logs/${CASE_LABEL}.log"
  local time="$run_root/logs/${CASE_LABEL}.time"
  mkdir -p "$out"
  suite_generate_case_0434 "$state" "$chi"
  write_params_0438 "$mode" "$state" "$out" "$params"
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode"
  echo "[0438-tg] case=$CASE_LABEL mode=$mode root=$run_root"
  echo "[0438-tg] periodic wall-free; thresholds: Nmin=$GUARD_NMIN Ntarget=$GUARD_NTARGET Nmax=$GUARD_NMAX"
  suite_run_binary_0434 "$params" "$log" "$time" "$out"
}

mkdir -p "$BASE_RUN_ROOT"
STATUS="$BASE_RUN_ROOT/launch_status.csv"
echo "mode,exit_code" > "$STATUS"
failures=0
for mode in $RUN_MODES; do
  set +e
  run_one_mode_0438 "$mode"
  rc=$?
  set -e
  echo "$mode,$rc" >> "$STATUS"
  if [[ "$rc" != 0 ]]; then failures=$((failures+1)); fi
done

read -r -a MODES_ARRAY <<< "$RUN_MODES"
python3 scripts/analyze_periodic_modes_0438.py \
  --root "$BASE_RUN_ROOT" --case tg --modes "${MODES_ARRAY[@]}" \
  --Lx "$Lx" --Ly "$Ly" \
  --csv "$BASE_RUN_ROOT/periodic_taylor_green_summary_0438.csv" \
  --markdown "$BASE_RUN_ROOT/periodic_taylor_green_report_0438.md"

echo "[0438-tg] root=$BASE_RUN_ROOT"
echo "[0438-tg] summary=$BASE_RUN_ROOT/periodic_taylor_green_summary_0438.csv"
echo "[0438-tg] report=$BASE_RUN_ROOT/periodic_taylor_green_report_0438.md"
if [[ "$failures" != 0 && "$FAIL_ON_ANY" == 1 ]]; then
  echo "[0438-tg] FAIL: failures=$failures" >&2
  exit 1
fi

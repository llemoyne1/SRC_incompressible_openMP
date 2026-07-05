#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# -----------------------------------------------------------------------------
# USER EDIT ZONE -- common layout in all 0434 scripts
# -----------------------------------------------------------------------------
CASE_LABEL="tg_hole"
GEN_CASE="tg"
TOPOLOGY="periodic"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-64}"; NY="${NY:-64}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-10000}"; DT="${DT:-0.001}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628605}"; U0="${U0:-0.04}"; VELOCITY_MODE="${VELOCITY_MODE:-taylor_green}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0434_${CASE_LABEL}_${NX}x${NY}_g${GAMMA}}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-1.25}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10000}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0477}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"

# Path choice: set either RUN_MODES="src" or INTEG_PATH=src-q6-resampling.
# Default runs one robust path (src). To compare all paths, set:
#   RUN_MODES="src src-resampling src-q6 src-q6-resampling"
RUN_MODES="${RUN_MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src}}}"

# Livevis + 0433a WYSIWYR filtered recording.
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-vorticity}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-25}"
LIVE_VIS_NX="${LIVE_VIS_NX:-64}"; LIVE_VIS_NY="${LIVE_VIS_NY:-64}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--5}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-20.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-10}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"; RECORD_STRIDE="${RECORD_STRIDE:-1}"
FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"

# Gamma-relative resampling thresholds. Actual integer thresholds are derived in common.
RESAMPLING_NMIN_COEF="${RESAMPLING_NMIN_COEF:-0.40}"  # Nmin = ceil(gamma*(1-coef))
RESAMPLING_NMAX_COEF="${RESAMPLING_NMAX_COEF:-0.60}"  # Nmax = ceil(gamma*(1+coef))
GUARD_EVERY="${GUARD_EVERY:-5}"

TG_HOLE_ENABLE="${TG_HOLE_ENABLE:-false}"
HOLE_XMIN="${HOLE_XMIN:-0.45}"; HOLE_XMAX="${HOLE_XMAX:-0.55}"
HOLE_YMIN="${HOLE_YMIN:-0.45}"; HOLE_YMAX="${HOLE_YMAX:-0.55}"
TG_FORCING_AMPLITUDE="${TG_FORCING_AMPLITUDE:-0.2}"
# -----------------------------------------------------------------------------

suite_defaults_common_0434
suite_compute_derived_0434

write_params_0434() {
  local mode=$1 state=$2 out=$3 chi=$4 params=$5
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
taylorGreenForcingEnable = true
taylorGreenForcingAmplitude = ${TG_FORCING_AMPLITUDE}
taylorGreenForcingModeX = 1
taylorGreenForcingModeY = 1
PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
  :
}

run_one_mode_0434() {
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
  write_params_0434 "$mode" "$state" "$out" "$chi" "$params"
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode"
  echo "[0434-suite] case=$CASE_LABEL mode=$mode root=$run_root"
  echo "[0434-suite] resampling thresholds: Nmin=$GUARD_NMIN Ntarget=$GUARD_NTARGET Nmax=$GUARD_NMAX from gamma=$GAMMA"
  suite_run_binary_0434 "$params" "$log" "$time" "$out"
}

for mode in $RUN_MODES; do
  run_one_mode_0434 "$mode"
done

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
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-128}"; NY="${NY:-128}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-10000}"; DT="${DT:-0.001}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628605}"; U0="${U0:-0.04}"; VELOCITY_MODE="${VELOCITY_MODE:-taylor_green}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0434_${CASE_LABEL}_${NX}x${NY}_g${GAMMA}}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-1.25}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10000}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"

# Path choice: RUN_MODES defaults to the 0493x7h three-way comparison.
# 0493x7h comparison default: historical SRC, previous SRC-Q6, current Q6-g-f.
# Resampling paths remain available through an explicit RUN_MODES override.
RUN_MODES="${RUN_MODES:-${MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src src-q6 src-q6-g-f}}}}"

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
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

# Gamma-relative resampling thresholds. Actual integer thresholds are derived in common.
RESAMPLING_NMIN_COEF="${RESAMPLING_NMIN_COEF:-0.40}"  # Nmin = ceil(gamma*(1-coef))
RESAMPLING_NMAX_COEF="${RESAMPLING_NMAX_COEF:-0.60}"  # Nmax = ceil(gamma*(1+coef))
GUARD_EVERY="${GUARD_EVERY:-5}"

TG_HOLE_ENABLE="${TG_HOLE_ENABLE:-false}"
HOLE_XMIN="${HOLE_XMIN:-0.45}"; HOLE_XMAX="${HOLE_XMAX:-0.55}"
HOLE_YMIN="${HOLE_YMIN:-0.45}"; HOLE_YMAX="${HOLE_YMAX:-0.55}"
TG_FORCING_AMPLITUDE="${TG_FORCING_AMPLITUDE:-0.2}"
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 0493x7r standalone Q6/Q6-g-f production profile.
#
# Normal use needs no PROJECTION_*, Q6_GF_* or CUDA-Q6 variables on the command
# line. Dedicated RUN_OK_* variables below are the intentional override surface;
# inherited generic variables are overwritten so a previous shell experiment
# cannot silently change the qualified physics.
#
# Qualified signed-density profile: x7q momentum closure in code, x7j resident
# CG for Q6-g-f, tau=0.25, compression gate at +3 particles, traction branch
# at -6 particles with gain 1, minimum fill 0.10, tolerance 1e-5.
# -----------------------------------------------------------------------------
RUN_OK_PROJECTION_BACKEND="${RUN_OK_PROJECTION_BACKEND:-cuda}"
RUN_OK_PROJECTION_OPERATOR="${RUN_OK_PROJECTION_OPERATOR:-auto_fv_cg}"
RUN_OK_PROJECTION_MAX_ITERATIONS="${RUN_OK_PROJECTION_MAX_ITERATIONS:-800}"
RUN_OK_PROJECTION_TOLERANCE="${RUN_OK_PROJECTION_TOLERANCE:-1.0e-5}"
RUN_OK_Q6_STRICT="${RUN_OK_Q6_STRICT:-1}"
RUN_OK_PROJECTION_MOMENTUM_CORRECTION_ENABLE="${RUN_OK_PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}"
RUN_OK_Q6_GF_DENSITY_RELAXATION_TIME="${RUN_OK_Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
RUN_OK_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${RUN_OK_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
RUN_OK_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${RUN_OK_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3}"
RUN_OK_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${RUN_OK_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6}"
RUN_OK_Q6_GF_DENSITY_TRACTION_GAIN="${RUN_OK_Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
RUN_OK_Q6_GF_MIN_FILL_FRACTION="${RUN_OK_Q6_GF_MIN_FILL_FRACTION:-0.10}"

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
Q6_GF_EXTERNAL_SPECIES=0
Q6_GF_HAS_GAS_PHASE=0

run_ok_export_q6_cuda_profile_0493x7r() {
  local mode=$1
  local cells=$((NX * NY))
  if suite_path_has_q6_g_f_0493x7h "$mode"; then
    # x7j cooperative multi-block CG. x7q exact periodic k=0 closure is automatic
    # in the CUDA B1 full-domain periodic path and has no runtime gate.
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
    export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  elif suite_path_has_q6_0434 "$mode"; then
    # Previous Q6 keeps its proven 0407 single-block fast path where applicable.
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=0
    if (( cells <= 65536 )); then
      export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=1
    else
      export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
    fi
  else
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=0
    export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  fi
}

run_ok_append_q6_profile_audit_0493x7r() {
  local file=$1 mode=$2
  cat >> "$file" <<META_0493X7R
RUN_OK_Q6_PROFILE=0493x7r_signed1_x7q
RUN_OK_PROJECTION_BACKEND=${PROJECTION_BACKEND}
RUN_OK_PROJECTION_OPERATOR=${PROJECTION_OPERATOR}
RUN_OK_PROJECTION_MAX_ITERATIONS=${PROJECTION_MAX_ITERATIONS}
RUN_OK_PROJECTION_TOLERANCE=${PROJECTION_TOLERANCE}
RUN_OK_Q6_STRICT=${Q6_STRICT}
RUN_OK_Q6_GF_DENSITY_RELAXATION_TIME=${Q6_GF_DENSITY_RELAXATION_TIME}
RUN_OK_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE}
RUN_OK_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES}
RUN_OK_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES}
RUN_OK_Q6_GF_DENSITY_TRACTION_GAIN=${Q6_GF_DENSITY_TRACTION_GAIN}
RUN_OK_Q6_GF_MIN_FILL_FRACTION=${Q6_GF_MIN_FILL_FRACTION}
MPCD_Q6_G_F_RESIDENT_CG_0493X7J=${MPCD_Q6_G_F_RESIDENT_CG_0493X7J}
MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=${MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407}
META_0493X7R
}

run_ok_print_q6_profile_0493x7r() {
  local mode=$1
  if suite_path_has_q6_0434 "$mode"; then
    echo "[0493x7r-run-ok] mode=$mode projection=$PROJECTION_OPERATOR tol=$PROJECTION_TOLERANCE maxIt=$PROJECTION_MAX_ITERATIONS strict=$Q6_STRICT"
  fi
  if suite_path_has_q6_g_f_0493x7h "$mode"; then
    echo "[0493x7r-run-ok] Q6-g-f signed1: tau=$Q6_GF_DENSITY_RELAXATION_TIME gate=$Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE +N=$Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES -N=$Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES gain=$Q6_GF_DENSITY_TRACTION_GAIN minFill=$Q6_GF_MIN_FILL_FRACTION x7j=$MPCD_Q6_G_F_RESIDENT_CG_0493X7J singleBlock0407=$MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407"
  elif suite_path_has_q6_0434 "$mode"; then
    echo "[0493x7r-run-ok] previous Q6: singleBlock0407=$MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407 cells=$((NX * NY))"
  fi
}
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
  run_ok_export_q6_cuda_profile_0493x7r "$mode"
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode"
  run_ok_append_q6_profile_audit_0493x7r "$run_root/logs/environment_0434.env" "$mode"
  run_ok_print_q6_profile_0493x7r "$mode"
  echo "[0434-suite] case=$CASE_LABEL mode=$mode root=$run_root"
  echo "[0434-suite] resampling thresholds: Nmin=$GUARD_NMIN Ntarget=$GUARD_NTARGET Nmax=$GUARD_NMAX from gamma=$GAMMA"
  suite_run_binary_0434 "$params" "$log" "$time" "$out"
}

while IFS= read -r mode; do
  [[ -n "$mode" ]] || continue
  run_one_mode_0434 "$mode"
done < <(suite_mode_list_0434)

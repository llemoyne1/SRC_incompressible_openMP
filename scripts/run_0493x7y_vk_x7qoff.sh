#!/usr/bin/env bash
set -euo pipefail

# 0493x7y controlled x7q-off VK ablation.
# B1 remains ON; x7d-v2-fix2 pre-closure remains ON; only x7q exact
# particle-level periodic residual closure is disabled.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# -----------------------------------------------------------------------------
# USER EDIT ZONE -- common layout in all 0434 scripts
# -----------------------------------------------------------------------------
# 0434b VK follows the validated 0416 Darcy/Brinkman periodic-x cylinder case:
#   Lx=1.5, Ly=0.4, Nx=1200, Ny=640, gamma=6
#   periodic left/right, solid top/bottom
#   circular chi obstacle: xc=0.2, yc=0.205, r=0.04
#   initial state homogeneous at U0=0.9.  The x7r three-way comparison fills
#   the same fictitious Darcy/Brinkman domain in SRC, Q6 and Q6-g-f by default;
#   RUN_OK_DARCY_COMMON_FILLED_STATE=0 reproduces the historical skipped-solid
#   SRC/Q6 initialization when that legacy comparison is specifically required.
CASE_LABEL="vk_darcy_chi_periodic"
GEN_CASE="vk"
TOPOLOGY="wall"
Lx="${Lx:-1.5}"; Ly="${Ly:-0.4}"; NX="${NX:-1200}"; NY="${NY:-480}"
GAMMA="${GAMMA:-6}"; STEPS="${STEPS:-5000}"; DT="${DT:-0.0005}"; KBT="${KBT:-5.0}"
SEED="${SEED:-1628416}"; U0="${U0:-0.9}"; VELOCITY_MODE="${VELOCITY_MODE:-uniform_x}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x7y_vk_x7qoff_${NX}x${NY}_g${GAMMA}_u${U0}_kBT${KBT}}"
# 0416 used no inactive slots. 0434b keeps a small pool by default so the same
# script can run resampling / empty-refill paths without editing the state.
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.25}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"

# 0493x7h comparison default: historical SRC, previous SRC-Q6, current Q6-g-f.
# Resampling paths remain available through an explicit RUN_MODES override.
RUN_MODES="src-q6-g-f"

# Livevis + 0433a WYSIWYR filtered recording. LIVE_VIS_CONTROL_FILE defaults to
# ./livevis_control.kv in common code so every script uses the same runtime file.
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-speed}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-10}"
LIVE_VIS_NX="${LIVE_VIS_NX:-1200}"; LIVE_VIS_NY="${LIVE_VIS_NY:-320}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
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
CUDA_RESAMPLING_CHI_FILTER_ENABLE="${CUDA_RESAMPLING_CHI_FILTER_ENABLE:-true}"
CUDA_RESAMPLING_CHI_MIN="${CUDA_RESAMPLING_CHI_MIN:-0.5}"

# 0416 VK physical/numerical characteristics.
AX="${AX:-0.000005}"; AY="${AY:-0.0}"
CYLINDER_CX="${CYLINDER_CX:-0.2}"; CYLINDER_CY="${CYLINDER_CY:-0.205}"; CYLINDER_R="${CYLINDER_R:-0.04}"
ALPHA="${ALPHA:-800000.0}"; ALPHA_MIN="${ALPHA_MIN:-0.0}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_INITIAL_DEACTIVATE_BELOW_CHI="${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:--1}"
DARCY_BRINKMAN_FORCING_MODE="${DARCY_BRINKMAN_FORCING_MODE:-mean}"
DARCY_CHI_COLLISION_VP_ENABLE="${DARCY_CHI_COLLISION_VP_ENABLE:-false}"
DARCY_CHI_COLLISION_VP_STRENGTH="${DARCY_CHI_COLLISION_VP_STRENGTH:-1.0}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
TOPO_BENCHMARK_ENABLE="${TOPO_BENCHMARK_ENABLE:-true}"
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-$SUMMARY_EVERY}"
TOPO_BENCHMARK_FILENAME="${TOPO_BENCHMARK_FILENAME:-topo_benchmark_0348.csv}"
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
RUN_OK_PROJECTION_MAX_ITERATIONS="${RUN_OK_PROJECTION_MAX_ITERATIONS:-1600}"
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
# Three-way Darcy comparisons use the same filled fictitious Brinkman domain
# in SRC, Q6 and Q6-g-f. Set this to 0 only to reproduce the historical SRC/Q6
# initialization in which particles inside the chi obstacle were skipped.
RUN_OK_DARCY_COMMON_FILLED_STATE="${RUN_OK_DARCY_COMMON_FILLED_STATE:-1}"

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
bcBottom = solid
bcTop = solid
bcX = periodic
bcY = solid
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = ${AX}
bodyAccelerationY = ${AY}
wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = ${PARTICLE_MASS}
wallKBT = -1.0
wallThermalNoise = 0.0
PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
  suite_write_darcy_params_0434 "$chi" "$mode" >> "$params"
}

run_one_mode_0434() {
  local mode=$1
  suite_validate_path_0434 "$mode"
  local run_root="$BASE_RUN_ROOT/$mode"
  suite_prepare_dirs_0434 "$run_root"
  local state="$run_root/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
  local chi="${run_root}/chi/${CASE_LABEL}_circle_xc${CYLINDER_CX}_yc${CYLINDER_CY}_r${CYLINDER_R}_${NX}x${NY}.f32"
  local params="$run_root/params/${CASE_LABEL}.kv"
  local out="$run_root/output"
  local log="$run_root/logs/${CASE_LABEL}.log"
  local time="$run_root/logs/${CASE_LABEL}.time"
  mkdir -p "$out"
  suite_generate_case_for_mode_0493x7h "$mode" "$state" "$chi"
  write_params_0434 "$mode" "$state" "$out" "$chi" "$params"
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  run_ok_export_q6_cuda_profile_0493x7r "$mode"
  export MPCD_Q6_EXACT_PERIODIC_B1_CLOSURE_0493X7Y=0
  export MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0
  export MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode"
  run_ok_append_q6_profile_audit_0493x7r "$run_root/logs/environment_0434.env" "$mode"
  cat >> "$run_root/logs/environment_0434.env" <<META_0493X7Y
RUN_OK_Q6_PROFILE_ABLATION=0493x7y_vk_x7qoff
MPCD_Q6_EXACT_PERIODIC_B1_CLOSURE_0493X7Y=${MPCD_Q6_EXACT_PERIODIC_B1_CLOSURE_0493X7Y}
MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=${MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0}
MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=${MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1}
META_0493X7Y
  echo "[0493x7y] CONTROLLED ABLATION mode=$mode B1=$MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1 x7qExact=$MPCD_Q6_EXACT_PERIODIC_B1_CLOSURE_0493X7Y"
  run_ok_print_q6_profile_0493x7r "$mode"
  echo "[0434-suite] case=$CASE_LABEL mode=$mode root=$run_root"
  echo "[0434-suite] VK 0416-like: periodic-x channel, circle=($CYLINDER_CX,$CYLINDER_CY,$CYLINDER_R), U0=$U0, kBT=$KBT, AX=$AX"
  echo "[0434-suite] resampling thresholds: Nmin=$GUARD_NMIN Ntarget=$GUARD_NTARGET Nmax=$GUARD_NMAX from gamma=$GAMMA"
  suite_run_binary_0434 "$params" "$log" "$time" "$out"
}

while IFS= read -r mode; do
  [[ -n "$mode" ]] || continue
  run_one_mode_0434 "$mode"
done < <(suite_mode_list_0434)

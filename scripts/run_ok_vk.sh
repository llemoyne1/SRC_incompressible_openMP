#!/usr/bin/env bash
set -euo pipefail

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
#   initial state homogeneous at U0=0.9; historical SRC/Q6 skip active particles
#   inside the circle, while Q6-g-f fills the fictitious Darcy domain as required.
CASE_LABEL="vk_darcy_chi_periodic"
GEN_CASE="vk"
TOPOLOGY="wall"
Lx="${Lx:-1.5}"; Ly="${Ly:-0.4}"; NX="${NX:-1200}"; NY="${NY:-480}"
GAMMA="${GAMMA:-6}"; STEPS="${STEPS:-5000}"; DT="${DT:-0.0005}"; KBT="${KBT:-5.0}"
SEED="${SEED:-1628416}"; U0="${U0:-0.9}"; VELOCITY_MODE="${VELOCITY_MODE:-uniform_x}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0434_${CASE_LABEL}_${NX}x${NY}_g${GAMMA}_u${U0}_kBT${KBT}}"
# 0416 used no inactive slots. 0434b keeps a small pool by default so the same
# script can run resampling / empty-refill paths without editing the state.
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.25}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"

# 0493x7h comparison default: historical SRC, previous SRC-Q6, current Q6-g-f.
# Resampling paths remain available through an explicit RUN_MODES override.
RUN_MODES="${RUN_MODES:-${MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src src-q6 src-q6-g-f}}}}"

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
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode"
  echo "[0434-suite] case=$CASE_LABEL mode=$mode root=$run_root"
  echo "[0434-suite] VK 0416-like: periodic-x channel, circle=($CYLINDER_CX,$CYLINDER_CY,$CYLINDER_R), U0=$U0, kBT=$KBT, AX=$AX"
  echo "[0434-suite] resampling thresholds: Nmin=$GUARD_NMIN Ntarget=$GUARD_NTARGET Nmax=$GUARD_NMAX from gamma=$GAMMA"
  suite_run_binary_0434 "$params" "$log" "$time" "$out"
}

while IFS= read -r mode; do
  [[ -n "$mode" ]] || continue
  run_one_mode_0434 "$mode"
done < <(suite_mode_list_0434)

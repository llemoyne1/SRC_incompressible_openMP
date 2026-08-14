#!/usr/bin/env bash
# 0493x7w -- compact periodic Darcy backward-step discriminator.
#
# Purpose:
#   Compare SRC / legacy Q6 / Q6-g-f without open-boundary population drift.
#   The default 512x128 grid is deliberately exactly 65536 cells so legacy Q6
#   keeps its 0407 single-block fast path.
#
# Geometry (default):
#   Lx=1.024, Ly=0.256, dx=dy=0.002
#   Darcy block: x=[0.32,0.64], y=[0,0.064]
#   H=0.064, plateau length=5H, downstream periodic clearance=11H.
#   x periodic; y bounded by physical walls.
#
# Default execution is SRC only.  After SRC is inspected, run the three-way
# comparison with:
#   RUN_MODES="src src-q6 src-q6-g-f" bash scripts/run_0493x7w_periodic_darcy_step.sh
#
# This script intentionally does NOT use `set -e`.

set -uo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
COMMON="$ROOT/scripts/src_mpcd_run_common_0434.sh"

if [[ ! -f "$COMMON" ]]; then
  echo "[0493x7w] ERROR missing common runner helper: $COMMON" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$COMMON" || {
  echo "[0493x7w] ERROR failed to source $COMMON" >&2
  exit 2
}

suite_root_cd_0434 || exit $?

# -----------------------------------------------------------------------------
# Compact discriminant geometry / physics
# -----------------------------------------------------------------------------
CASE_LABEL="${CASE_LABEL:-periodic_darcy_step_0493x7w}"
GEN_CASE="step"
TOPOLOGY="wall"

Lx="${Lx:-1.024}"
Ly="${Ly:-0.256}"
NX="${NX:-512}"
NY="${NY:-128}"

GAMMA="${GAMMA:-6}"
STEPS="${STEPS:-1200}"
DT="${DT:-0.0005}"
KBT="${KBT:-5.0}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
SEED="${SEED:-1628304}"

U0="${U0:-0.9}"
VELOCITY_MODE="${VELOCITY_MODE:-uniform_x}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.3962634015954636}"  # 80 deg

STEP_XMIN="${STEP_XMIN:-0.32}"
STEP_XMAX="${STEP_XMAX:-0.64}"
STEP_YMIN="${STEP_YMIN:-0.0}"
STEP_YMAX="${STEP_YMAX:-0.064}"

# Keep the same fictitious Darcy domain populated in all three modes.
RUN_OK_DARCY_COMMON_FILLED_STATE="${RUN_OK_DARCY_COMMON_FILLED_STATE:-1}"
DARCY_INITIAL_DEACTIVATE_BELOW_CHI="${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:--1}"
ALPHA="${ALPHA:-800000.0}"
ALPHA_MIN="${ALPHA_MIN:-0.0}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_BRINKMAN_FORCING_MODE="${DARCY_BRINKMAN_FORCING_MODE:-mean_outward_bath}"
DARCY_CHI_COLLISION_VP_ENABLE="${DARCY_CHI_COLLISION_VP_ENABLE:-true}"
DARCY_CHI_COLLISION_VP_MODE="${DARCY_CHI_COLLISION_VP_MODE:-interface_band}"
DARCY_CHI_COLLISION_VP_LAYERS="${DARCY_CHI_COLLISION_VP_LAYERS:-1}"
DARCY_CHI_COLLISION_VP_THRESHOLD="${DARCY_CHI_COLLISION_VP_THRESHOLD:-0.5}"
DARCY_CHI_COLLISION_VP_STRENGTH="${DARCY_CHI_COLLISION_VP_STRENGTH:-0.25}"

INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.25}"

SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-50}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-$SUMMARY_EVERY}"
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-$SUMMARY_EVERY}"

BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x7w_periodic_darcy_step_${NX}x${NY}_g${GAMMA}_u${U0}}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"

# First launch is deliberately SRC only. Override once the baseline is accepted.
RUN_MODES="${RUN_MODES:-${MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src}}}}"

# Keep progress, suppress visualization/filtered recording overhead by default.
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-Ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-10}"
LIVE_VIS_NX="${LIVE_VIS_NX:-512}"
LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
RECORD_ENABLE="${RECORD_ENABLE:-false}"

# No external flow controller in the discriminant run.
KEEP_MEAN_FLOW_ENABLE="${KEEP_MEAN_FLOW_ENABLE:-false}"
BODY_ACCELERATION_X="${BODY_ACCELERATION_X:-0.0}"
BODY_ACCELERATION_Y="${BODY_ACCELERATION_Y:-0.0}"

# -----------------------------------------------------------------------------
# 0493x7r qualified Q6 / Q6-g-f production profile
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
PROJECTION_MOMENTUM_CORRECTION_ENABLE="$RUN_OK_PROJECTION_MOMENTUM_CORRECTION_ENABLE"
Q6_STRICT="$RUN_OK_Q6_STRICT"

Q6_GF_DENSITY_RELAXATION_TIME="$RUN_OK_Q6_GF_DENSITY_RELAXATION_TIME"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="$RUN_OK_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="$RUN_OK_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="$RUN_OK_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES"
Q6_GF_DENSITY_TRACTION_GAIN="$RUN_OK_Q6_GF_DENSITY_TRACTION_GAIN"
Q6_GF_MIN_FILL_FRACTION="$RUN_OK_Q6_GF_MIN_FILL_FRACTION"
Q6_GF_SPECIES_DIAGNOSTICS_ENABLE=false
Q6_GF_EXTERNAL_SPECIES=0
Q6_GF_HAS_GAS_PHASE=0

run_ok_export_q6_cuda_profile_0493x7w() {
  local mode=$1
  local cells=$((NX * NY))

  if suite_path_has_q6_g_f_0493x7h "$mode"; then
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
    export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  elif suite_path_has_q6_0434 "$mode"; then
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

append_profile_audit_0493x7w() {
  local file=$1 mode=$2
  cat >> "$file" <<META
X7W_CASE=periodic_darcy_backward_step
X7W_MODE=${mode}
X7W_LX=${Lx}
X7W_LY=${Ly}
X7W_NX=${NX}
X7W_NY=${NY}
X7W_GAMMA=${GAMMA}
X7W_U0=${U0}
X7W_STEP_XMIN=${STEP_XMIN}
X7W_STEP_XMAX=${STEP_XMAX}
X7W_STEP_YMIN=${STEP_YMIN}
X7W_STEP_YMAX=${STEP_YMAX}
X7W_KEEP_MEAN_FLOW_ENABLE=${KEEP_MEAN_FLOW_ENABLE}
X7W_BODY_ACCELERATION_X=${BODY_ACCELERATION_X}
X7W_RUN_OK_DARCY_COMMON_FILLED_STATE=${RUN_OK_DARCY_COMMON_FILLED_STATE}
X7W_DARCY_INITIAL_DEACTIVATE_BELOW_CHI=${DARCY_INITIAL_DEACTIVATE_BELOW_CHI}
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
META
}

print_profile_0493x7w() {
  local mode=$1
  local cells=$((NX * NY))

  echo "[0493x7w] mode=$mode cells=$cells particles_nominal=$((cells * GAMMA)) steps=$STEPS"
  if suite_path_has_q6_g_f_0493x7h "$mode"; then
    echo "[0493x7w] Q6-g-f signed1: x7j=$MPCD_Q6_G_F_RESIDENT_CG_0493X7J tau=$Q6_GF_DENSITY_RELAXATION_TIME"
  elif suite_path_has_q6_0434 "$mode"; then
    echo "[0493x7w] legacy Q6: singleBlock0407=$MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407"
  fi
}

# -----------------------------------------------------------------------------
# Common derived defaults
# -----------------------------------------------------------------------------
suite_defaults_common_0434 || exit $?
suite_compute_derived_0434 || exit $?

CELLS=$((NX * NY))
NOMINAL_FLUID=$((CELLS * GAMMA))

# Protect the compact-Q6 intent against accidental oversized overrides.
if (( CELLS > 65536 )); then
  case " $RUN_MODES " in
    *" src-q6 "*|*" q6 "*)
      if ! suite_truthy_0434 "${ALLOW_SLOW_Q6:-0}"; then
        echo "[0493x7w] ERROR NX*NY=$CELLS > 65536 disables legacy-Q6 0407 fast path." >&2
        echo "[0493x7w] Set ALLOW_SLOW_Q6=1 only if that is intentional." >&2
        exit 2
      fi
      ;;
  esac
fi

echo "[0493x7w] compact periodic Darcy backward-step discriminator"
echo "[0493x7w] grid=${NX}x${NY} cells=$CELLS nominalFluid=$NOMINAL_FLUID gamma=$GAMMA"
echo "[0493x7w] domain=${Lx}x${Ly} step=x[${STEP_XMIN},${STEP_XMAX}] y[${STEP_YMIN},${STEP_YMAX}]"
echo "[0493x7w] periodic-x / wall-y; no inlet/outlet; keepMeanFlow=${KEEP_MEAN_FLOW_ENABLE}; ax=${BODY_ACCELERATION_X}"
echo "[0493x7w] Darcy alpha=$ALPHA q=$DARCY_Q mode=$DARCY_BRINKMAN_FORCING_MODE chiVP=$DARCY_CHI_COLLISION_VP_ENABLE filledState=$RUN_OK_DARCY_COMMON_FILLED_STATE"
echo "[0493x7w] modes=$RUN_MODES"

write_params_0493x7w() {
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
bcY = wall

openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0

bodyAccelerationX = $BODY_ACCELERATION_X
bodyAccelerationY = $BODY_ACCELERATION_Y
keepMeanFlowEnable = $KEEP_MEAN_FLOW_ENABLE

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $PARTICLE_MASS
wallKBT = -1.0
wallThermalNoise = 0.0
PARAMS

  suite_write_common_params_0434 "$mode" >> "$params" || return $?
  suite_write_darcy_params_0434 "$chi" "$mode" >> "$params" || return $?
  return 0
}

run_one_mode_0493x7w() {
  local mode=$1
  local run_root state chi params out log time_file rc

  suite_validate_path_0434 "$mode" || return $?

  run_root="$BASE_RUN_ROOT/$mode"
  suite_prepare_dirs_0434 "$run_root" || return $?

  state="$run_root/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
  chi="$run_root/chi/${CASE_LABEL}_${NX}x${NY}.f32"
  params="$run_root/params/${CASE_LABEL}.kv"
  out="$run_root/output"
  log="$run_root/logs/${CASE_LABEL}.log"
  time_file="$run_root/logs/${CASE_LABEL}.time"

  mkdir -p "$out" || return $?

  suite_generate_case_for_mode_0493x7h "$mode" "$state" "$chi" || return $?
  write_params_0493x7w "$mode" "$state" "$out" "$chi" "$params" || return $?

  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY" || return $?
  run_ok_export_q6_cuda_profile_0493x7w "$mode"

  suite_prepare_livevis_control_0434 "$run_root" "$mode" || return $?
  suite_export_livevis_0434 || return $?
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode" || return $?
  append_profile_audit_0493x7w "$run_root/logs/environment_0434.env" "$mode"

  print_profile_0493x7w "$mode"
  echo "[0493x7w] root=$run_root"

  suite_run_binary_0434 "$params" "$log" "$time_file" "$out"
  rc=$?
  if (( rc != 0 )); then
    echo "[0493x7w] ERROR mode=$mode rc=$rc" >&2
    return "$rc"
  fi

  echo "[0493x7w] PASS mode=$mode"
  return 0
}

overall_rc=0
while IFS= read -r mode; do
  [[ -n "$mode" ]] || continue
  run_one_mode_0493x7w "$mode"
  rc=$?
  if (( rc != 0 )); then
    overall_rc=$rc
    break
  fi
done < <(suite_mode_list_0434)

if (( overall_rc == 0 )); then
  echo "[0493x7w] COMPLETE"
else
  echo "[0493x7w] FAILED rc=$overall_rc" >&2
fi

exit "$overall_rc"

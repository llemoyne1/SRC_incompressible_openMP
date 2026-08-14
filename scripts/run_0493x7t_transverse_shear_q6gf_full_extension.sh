#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x7t: extend an existing 0493x7s transverse-shear campaign with the
# complete signed1 Q6-g-f path, without rerunning SRC / legacy-Q6 / q6-g-f-div0.
#
# Existing cases expected under RUN_ROOT:
#   seed_<seed>/00_src
#   seed_<seed>/01_q6_legacy
#   seed_<seed>/02_q6gf_div0
#
# This runner adds:
#   seed_<seed>/03_q6gf_signed1
#
# Then the four-way analyzer compares the coherent transverse/vortical response.

CASE_LABEL="transverse_shear_vorticity_0493x7t"
RUN_ROOT="${RUN_ROOT:-runs/0493x7s_transverse_shear_vorticity}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
TOPOLOGY="periodic"

NX="${NX:-64}"
NY="${NY:-64}"
Lx="${Lx:-0.128}"
Ly="${Ly:-0.128}"
GAMMA="${GAMMA:-6}"
DT="${DT:-0.0005}"
KBT="${KBT:-5.0}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.3962634015954636}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:--1.0}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

STEPS="${STEPS:-2000}"
DUMP_EVERY="${DUMP_EVERY:-50}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
WAVE_MODE="${WAVE_MODE:-1}"
WAVE_AMPLITUDE="${WAVE_AMPLITUDE:-0.6}"
SEEDS="${SEEDS:-493851 493852}"
EXPECTED_NU="${EXPECTED_NU:-0.0009422644557}"

THREADS="${THREADS:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
CLEAN_SIGNED1_CASE="${CLEAN_SIGNED1_CASE:-1}"

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"

# Complete production signed1 density-restoration profile.
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_EXTERNAL_SPECIES=0
Q6_GF_SPECIES_DIAGNOSTICS_ENABLE=false
Q6_GF_SINGLE_PHASE_TYPE=0
Q6_GF_SINGLE_PHASE_PARTICLE_MASS="$PARTICLE_MASS"

SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
INACTIVE_SLOTS=0
INACTIVE_SLOTS_CELL_FRACTION=0
DUMP_STATE_EVERY="$DUMP_EVERY"
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
LIVE_VIS_ENABLE=0
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}"
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false
PARTICLE_TYPE_FILTER=-1
BACKGROUND_TYPE=0
U0=0.0
UIN=0.0

export LIVE_PROGRESS OMP_NUM_THREADS="$THREADS"

truthy_0493x7t() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

validate_existing_0493x7s() {
  local seed case
  for seed in $SEEDS; do
    [[ -f "$RUN_ROOT/seed_${seed}/init/transverse_shear_0493x7s.smpcd" ]] || {
      echo "[0493x7t] ERROR missing x7s initial state for seed=$seed" >&2
      return 2
    }
    for case in 00_src 01_q6_legacy 02_q6gf_div0; do
      [[ -d "$RUN_ROOT/seed_${seed}/$case/output" ]] || {
        echo "[0493x7t] ERROR missing existing x7s output seed=$seed case=$case" >&2
        return 2
      }
    done
  done
  return 0
}

write_params_0493x7t() {
  local seed=$1 state=$2 out=$3 params=$4
  SEED="$seed"
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
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
keepMeanFlowEnable = false
PARAMS
  suite_write_common_params_0434 "src-q6-g-f" >> "$params" || return $?
  return 0
}

run_signed1_seed_0493x7t() {
  local seed=$1
  local state="$RUN_ROOT/seed_${seed}/init/transverse_shear_0493x7s.smpcd"
  local case_dir="$RUN_ROOT/seed_${seed}/03_q6gf_signed1"
  local params="$case_dir/params/params_0493x7t.kv"
  local out="$case_dir/output"
  local log="$case_dir/logs/run_0493x7t.log"
  local time_file="$case_dir/logs/run_0493x7t.time"

  if truthy_0493x7t "$CLEAN_SIGNED1_CASE"; then
    rm -rf "$case_dir"
  fi
  mkdir -p "$case_dir/init" "$case_dir/chi" "$case_dir/params" "$case_dir/logs" "$out" "$case_dir/analysis"

  write_params_0493x7t "$seed" "$state" "$out" "$params" || return $?
  suite_export_cuda_flags_0434 "src-q6-g-f" "$TOPOLOGY" || return $?
  export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
  export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  suite_export_livevis_0434
  suite_write_env_file_0434 "$case_dir/logs/environment_0434.env" "src-q6-g-f"
  cat >> "$case_dir/logs/environment_0434.env" <<META
X7T_LABEL=03_q6gf_signed1
X7T_SOURCE_CAMPAIGN=0493x7s
X7T_ROTATION_ANGLE=$ROTATION_ANGLE
Q6_GF_DENSITY_RELAXATION_TIME=$Q6_GF_DENSITY_RELAXATION_TIME
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=$Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=$Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=$Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES
Q6_GF_DENSITY_TRACTION_GAIN=$Q6_GF_DENSITY_TRACTION_GAIN
Q6_GF_MIN_FILL_FRACTION=$Q6_GF_MIN_FILL_FRACTION
MPCD_Q6_G_F_RESIDENT_CG_0493X7J=$MPCD_Q6_G_F_RESIDENT_CG_0493X7J
MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=$MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407
META

  echo "[0493x7t] seed=$seed mode=src-q6-g-f variant=signed1 tau=$Q6_GF_DENSITY_RELAXATION_TIME gate=$Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE tractionGain=$Q6_GF_DENSITY_TRACTION_GAIN x7j=$MPCD_Q6_G_F_RESIDENT_CG_0493X7J"
  suite_run_binary_0434 "$params" "$log" "$time_file" "$out"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "[0493x7t] ERROR signed1 run failed seed=$seed rc=$rc" >&2
    return $rc
  fi
  return 0
}

suite_defaults_common_0434
suite_compute_derived_0434
validate_existing_0493x7s || exit $?

if ! truthy_0493x7t "$ANALYZE_ONLY"; then
  overall_rc=0
  for seed in $SEEDS; do
    run_signed1_seed_0493x7t "$seed" || overall_rc=$?
  done
  if [[ $overall_rc -ne 0 ]]; then
    exit "$overall_rc"
  fi
  if truthy_0493x7t "$PREFLIGHT_ONLY"; then
    echo "[0493x7t] PASS preflight signed1; existing x7s cases untouched"
    exit 0
  fi
fi

python3 scripts/analyze_0493x7t_transverse_shear_fourway.py \
  --root "$RUN_ROOT" \
  --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --dt "$DT" --steps "$STEPS" --dump-every "$DUMP_EVERY" \
  --wave-mode "$WAVE_MODE" --requested-amplitude "$WAVE_AMPLITUDE" \
  --expected-nu "$EXPECTED_NU" --seeds $SEEDS
exit $?

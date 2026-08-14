#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x7s: cheap vortical-sector qualification for the VK-calibrated fluid.
# Default comparison:
#   00_src         : classic SRC
#   01_q6_legacy   : historical Q6 (0407 fast path on this small grid)
#   02_q6gf_div0   : modern Q6-g-f/x7j with density-restoration RHS disabled
#
# The physical state is a periodic transverse shear wave
#   ux(y)=A sin(2*pi*m*y/Ly), uy=0,
# which is divergence-free and has zero nonlinear self-advection.  Its coherent
# vorticity therefore decays only through viscous transport.

CASE_LABEL="transverse_shear_vorticity_0493x7s"
TOPOLOGY="periodic"
RUN_ROOT="${RUN_ROOT:-runs/0493x7s_transverse_shear_vorticity}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"

# Cell-equivalent to the current VK candidate: a=0.002, gamma=6, alpha=80 deg.
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
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

# Qualified projection tolerance; the small 64x64 legacy-Q6 grid is below the
# 0407 single-block threshold, while Q6-g-f uses the x7j resident path.
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"

# q6-g-f-div0: keep the modern operator/application path, but remove the x7d
# density-restoration source completely.  tractionGain must also be zero because
# the signed traction branch requires active density relaxation.
Q6_GF_DENSITY_RELAXATION_TIME=0.0
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=0
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0
Q6_GF_DENSITY_TRACTION_GAIN=0.0
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

fail_0493x7s() {
  echo "[0493x7s] ERROR $*" >&2
  return 2
}

validate_0493x7s() {
  if (( NX < 8 || NY < 8 || GAMMA < 4 || WAVE_MODE < 1 )); then
    fail_0493x7s "require NX,NY>=8, GAMMA>=4, WAVE_MODE>=1" || return $?
  fi
  if (( STEPS < DUMP_EVERY || DUMP_EVERY < 1 || STEPS % DUMP_EVERY != 0 )); then
    fail_0493x7s "require STEPS>=DUMP_EVERY>=1 and STEPS divisible by DUMP_EVERY" || return $?
  fi
  python3 - "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$DT" "$KBT" "$PARTICLE_MASS" "$WAVE_AMPLITUDE" <<'PY_VALIDATE'
import math, sys
Lx,Ly,Nx,Ny,gamma,dt,kbt,mass,amp = map(float, sys.argv[1:])
if not all(math.isfinite(v) for v in (Lx,Ly,dt,kbt,mass,amp)):
    raise SystemExit('[0493x7s] ERROR non-finite physical parameter')
if min(Lx,Ly,dt,kbt,mass,amp) <= 0:
    raise SystemExit('[0493x7s] ERROR positive Lx,Ly,dt,kBT,mass,amplitude required')
dx=Lx/Nx; dy=Ly/Ny
if abs(dx-dy) > 1e-12*max(dx,dy):
    raise SystemExit(f'[0493x7s] ERROR collision cells must be square: dx={dx:.17g} dy={dy:.17g}')
print(f'[0493x7s] geometry cell={dx:.9g} grid={int(Nx)}x{int(Ny)} particleCount={int(Nx*Ny*gamma)}')
PY_VALIDATE
  return $?
}

x7s_export_q6_profile() {
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

write_params_0493x7s() {
  local mode=$1 seed=$2 state=$3 out=$4 params=$5
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
  suite_write_common_params_0434 "$mode" >> "$params" || return $?
  return 0
}

run_mode_0493x7s() {
  local seed=$1 mode=$2 dirname=$3 state=$4
  local case_dir="$RUN_ROOT/seed_${seed}/$dirname"
  local params="$case_dir/params/params_0493x7s.kv"
  local out="$case_dir/output"
  local log="$case_dir/logs/run_0493x7s.log"
  local time_file="$case_dir/logs/run_0493x7s.time"

  suite_prepare_dirs_0434 "$case_dir"
  mkdir -p "$out"
  write_params_0493x7s "$mode" "$seed" "$state" "$out" "$params" || return $?
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY" || return $?
  x7s_export_q6_profile "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$case_dir/logs/environment_0434.env" "$mode"
  cat >> "$case_dir/logs/environment_0434.env" <<META
X7S_LABEL=$dirname
X7S_WAVE_MODE=$WAVE_MODE
X7S_WAVE_AMPLITUDE=$WAVE_AMPLITUDE
X7S_LX=$Lx
X7S_LY=$Ly
X7S_ROTATION_ANGLE=$ROTATION_ANGLE
X7S_Q6GF_DIV0=1
Q6_GF_DENSITY_RELAXATION_TIME=$Q6_GF_DENSITY_RELAXATION_TIME
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=$Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE
Q6_GF_DENSITY_TRACTION_GAIN=$Q6_GF_DENSITY_TRACTION_GAIN
MPCD_Q6_G_F_RESIDENT_CG_0493X7J=$MPCD_Q6_G_F_RESIDENT_CG_0493X7J
MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=$MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407
META

  echo "[0493x7s] seed=$seed mode=$mode label=$dirname cells=$((NX*NY)) steps=$STEPS"
  if [[ "$mode" == "src-q6" ]]; then
    echo "[0493x7s] legacy-Q6 singleBlock0407=$MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407"
  elif suite_path_has_q6_g_f_0493x7h "$mode"; then
    echo "[0493x7s] q6-g-f-div0 tau=$Q6_GF_DENSITY_RELAXATION_TIME tractionGain=$Q6_GF_DENSITY_TRACTION_GAIN x7j=$MPCD_Q6_G_F_RESIDENT_CG_0493X7J"
  fi

  suite_run_binary_0434 "$params" "$log" "$time_file" "$out"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "$seed,$dirname,FAIL,rc=$rc" >> "$RUN_ROOT/status_0493x7s.csv"
    return $rc
  fi
  echo "$seed,$dirname,PASS,ok" >> "$RUN_ROOT/status_0493x7s.csv"
  return 0
}

validate_0493x7s || exit $?
suite_defaults_common_0434
suite_compute_derived_0434

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
  mkdir -p "$RUN_ROOT"
  printf 'seed,case,status,reason\n' > "$RUN_ROOT/status_0493x7s.csv"

  overall_rc=0
  for seed in $SEEDS; do
    state="$RUN_ROOT/seed_${seed}/init/transverse_shear_0493x7s.smpcd"
    python3 scripts/generate_0493x7s_transverse_shear_state.py \
      --output "$state" --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" \
      --gamma "$GAMMA" --kBT "$KBT" --mass "$PARTICLE_MASS" --seed "$seed" \
      --wave-mode "$WAVE_MODE" --wave-amplitude "$WAVE_AMPLITUDE" --particle-type 0
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "[0493x7s] ERROR state generation failed seed=$seed rc=$rc" >&2
      exit $rc
    fi

    run_mode_0493x7s "$seed" src 00_src "$state" || overall_rc=$?
    run_mode_0493x7s "$seed" src-q6 01_q6_legacy "$state" || overall_rc=$?
    run_mode_0493x7s "$seed" src-q6-g-f 02_q6gf_div0 "$state" || overall_rc=$?
  done

  cat "$RUN_ROOT/status_0493x7s.csv"
  if [[ $overall_rc -ne 0 ]] || grep -q ',FAIL,' "$RUN_ROOT/status_0493x7s.csv"; then
    echo "[0493x7s] FAIL runner" >&2
    exit 2
  fi
  if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
    echo "[0493x7s] PASS preflight; no simulation launched"
    exit 0
  fi
fi

python3 scripts/analyze_0493x7s_transverse_shear_vorticity.py \
  --root "$RUN_ROOT" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --dt "$DT" --steps "$STEPS" --dump-every "$DUMP_EVERY" \
  --wave-mode "$WAVE_MODE" --requested-amplitude "$WAVE_AMPLITUDE" \
  --expected-nu "$EXPECTED_NU" --seeds $SEEDS
exit $?

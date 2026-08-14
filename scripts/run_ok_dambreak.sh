#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# -----------------------------------------------------------------------------
# 0493x7h public dam-break comparison runner.
# Same initial state and physical parameters for:
#   src          : SRC without Q6;
#   src-q6       : previous independent_masked Q6, legacy force ordering;
#   src-q6-g-f   : current Q6-g-f (Q6-G+x6f+x6g+x7d+A/B1).
# -----------------------------------------------------------------------------
CASE_LABEL="dambreak"
TOPOLOGY="closed_box"
Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"; NX="${NX:-300}"; NY="${NY:-150}"
GAMMA="${GAMMA:-10}"; STEPS="${STEPS:-5000}"; DT="${DT:-0.005}"; KBT="${KBT:-0.05}"
SEED="${SEED:-493953}"
GRAVITY_Y="${GRAVITY_Y:--0.5}"
LIQUID_COLUMN_WIDTH="${LIQUID_COLUMN_WIDTH:-0.5}"
LIQUID_COLUMN_HEIGHT="${LIQUID_COLUMN_HEIGHT:-0.8}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1000.0}"; GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"; GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_OCCUPANCY_FRACTION="${SPECIES_Q6_MIN_OCCUPANCY_FRACTION:-0.5}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/run_ok_dambreak_${NX}x${NY}_g${GAMMA}}"
RUN_MODES="${RUN_MODES:-${MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src src-q6 src-q6-g-f}}}}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.5}"
SUMMARY_EVERY="${SUMMARY_EVERY:-25}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"; LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:-$LIQUID_TYPE}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1600}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"

# This runner owns the two-phase registry.  Q6-g-f reuses it and enables the
# validated x6g gas-pressure Dirichlet condition; src/src-q6 do not.
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=1
PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"
INACTIVE_TYPE="$GAS_TYPE"
GEN_CASE="tg"; U0=0.0; VELOCITY_MODE="zero"; TG_HOLE_ENABLE=false

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

python3 - "$Lx" "$Ly" "$LIQUID_COLUMN_WIDTH" "$LIQUID_COLUMN_HEIGHT" \
  "$LIQUID_MASS" "$GAS_MASS" "$LIQUID_Q6_STRENGTH" "$GAS_Q6_STRENGTH" <<'PY_VALIDATE'
import math, sys
lx, ly, width, height, ml, mg, ql, qg = map(float, sys.argv[1:])
if not (0.0 < width < lx and 0.0 < height < ly):
    raise SystemExit("[run_ok_dambreak] liquid column must lie strictly inside the box")
if not (ml > 0.0 and mg > 0.0 and math.isfinite(ml) and math.isfinite(mg)):
    raise SystemExit("[run_ok_dambreak] particle masses must be finite and positive")
if not (ql > 0.0 and qg == 0.0):
    raise SystemExit("[run_ok_dambreak] require liquid Q6 strength>0 and gas Q6 strength=0")
PY_VALIDATE

write_params_dambreak_0493x7h() {
  local mode=$1 state=$2 out=$3 params=$4
  local species_q6_enable=false species_q6_mode=independent_masked
  local species_diagnostics_enable=true
  if suite_path_has_q6_0434 "$mode"; then species_q6_enable=true; fi
  # 0493x7l: production Q6-g-f no longer writes the generic per-species
  # telemetry CSV. Keep it for the historical SRC / previous-Q6 comparators.
  if suite_path_has_q6_g_f_0493x7h "$mode"; then species_diagnostics_enable=false; fi
  # src-q6 is intentionally the previous Q6 comparator. Q6-g-f overrides this
  # mode and the force ordering through the common helper below.
  local liquid_ref gas_ref
  liquid_ref="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
  gas_ref="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = specular
bcRight = specular
bcBottom = solid
bcTop = specular
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
q6ForceProjectionMode = legacy
keepMeanFlowEnable = false
wallVpEnable = false
wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $LIQUID_MASS
wallKBT = -1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $liquid_ref
species0ResamplingEnable = false
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $gas_ref
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = $species_diagnostics_enable
speciesDiagnosticsFilename = species_runtime_run_ok_dambreak.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = $species_q6_enable
speciesQ6Mode = $species_q6_mode
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_OCCUPANCY_FRACTION
PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
}

run_one_mode_dambreak_0493x7h() {
  local mode=$1
  suite_validate_path_0434 "$mode"
  local run_root="$BASE_RUN_ROOT/$mode"
  suite_prepare_dirs_0434 "$run_root"
  local state="$run_root/init/dambreak_${NX}x${NY}_g${GAMMA}.smpcd"
  local params="$run_root/params/dambreak.kv"
  local out="$run_root/output"
  local log="$run_root/logs/dambreak.log"
  local time_file="$run_root/logs/dambreak.time"
  mkdir -p "$out"

  python3 scripts/generate_0493x0_dam_break_state.py \
    --output "$state" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --column-width "$LIQUID_COLUMN_WIDTH" --column-height "$LIQUID_COLUMN_HEIGHT" \
    --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
    --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
    --kBT "$KBT" --seed "$SEED"

  write_params_dambreak_0493x7h "$mode" "$state" "$out" "$params"
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  run_ok_export_q6_cuda_profile_0493x7r "$mode"
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0493x7h.env" "$mode"
  run_ok_append_q6_profile_audit_0493x7r "$run_root/logs/environment_0493x7h.env" "$mode"
  run_ok_print_q6_profile_0493x7r "$mode"
  cat >> "$run_root/logs/environment_0493x7h.env" <<META
LIQUID_COLUMN_WIDTH=$LIQUID_COLUMN_WIDTH
LIQUID_COLUMN_HEIGHT=$LIQUID_COLUMN_HEIGHT
LIQUID_TYPE=$LIQUID_TYPE
GAS_TYPE=$GAS_TYPE
LIQUID_MASS=$LIQUID_MASS
GAS_MASS=$GAS_MASS
GRAVITY_Y=$GRAVITY_Y
META
  echo "[0493x7h] case=dambreak mode=$mode root=$run_root"
  if suite_path_has_q6_g_f_0493x7h "$mode"; then
    echo "[0493x7h] physics=Q6-g-f tau=$Q6_GF_DENSITY_RELAXATION_TIME minFill=$Q6_GF_MIN_FILL_FRACTION x6g=eos"
  elif suite_path_has_q6_0434 "$mode"; then
    echo "[0493x7h] physics=previous-Q6 speciesMode=independent_masked forceOrdering=legacy"
  else
    echo "[0493x7h] physics=SRC no-Q6"
  fi
  suite_run_binary_0434 "$params" "$log" "$time_file" "$out"
}

while IFS= read -r mode; do
  [[ -n "$mode" ]] || continue
  run_one_mode_dambreak_0493x7h "$mode"
done < <(suite_mode_list_0434)

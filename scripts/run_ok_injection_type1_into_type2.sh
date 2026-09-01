#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

# -----------------------------------------------------------------------------
# USER EDIT ZONE -- common layout in all 0434 scripts
# -----------------------------------------------------------------------------
CASE_LABEL="injection_type1_into_type2"
GEN_CASE="injection"
TOPOLOGY="${TOPOLOGY:-segmented}"
Lx="${Lx:-4.5}"; Ly="${Ly:-1.5}"; NX="${NX:-1152}"; NY="${NY:-384}"
GAMMA="${GAMMA:-8}"; STEPS="${STEPS:-2000}"; DT="${DT:-0.0063471328149122585}"; KBT="${KBT:-0.125}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
# 0493x14d: optional per-type thermostat targets. Disabled by default so the
# historical runner remains unchanged unless explicitly requested.
SPECIES_THERMOSTAT_ENABLE="${SPECIES_THERMOSTAT_ENABLE:-false}"
INJECT_THERMOSTAT_TARGET_KBT="${INJECT_THERMOSTAT_TARGET_KBT:--1.0}"
BACKGROUND_THERMOSTAT_TARGET_KBT="${BACKGROUND_THERMOSTAT_TARGET_KBT:--1.0}"
LIQUID_PARTICLE_MASS="${LIQUID_PARTICLE_MASS:-1.0}"
GAS_PARTICLE_MASS="${GAS_PARTICLE_MASS:-0.1}"
SEED="${SEED:-1628431}"; U0="${U0:-0.0}"; VELOCITY_MODE="${VELOCITY_MODE:-zero}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-5.0}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000000}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-$ROOT/livevis_control.kv}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"

# Full-domain liquid type-1 injection into active gas type-2.
# x9 capillarity + x6g gas pressure are enabled; the qualified x10u/x10v/x12a
# kinetic closure remains OFF because it is liquid/vacuum-only.
RUN_OK_LIQUID_SURFACE_ENABLE="${RUN_OK_LIQUID_SURFACE_ENABLE:-1}"
# Surface/free-surface physics -- visible runner parameters.
SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-500.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-0.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

# Baseline validation intentionally excludes resampling.  The public wrapper
# selects SRC / previous Q6 / Q6-g-f; direct use of this backend retains the
# historical SRC + SRC-Q6 default unless RUN_MODES is explicitly overridden.
# Resampling paths remain available explicitly.
if [[ -z "${RUN_MODES:-}" && -z "${MODES:-}" && -z "${INTEG_PATH:-}" && -z "${SRC_INTEG_PATH:-}" ]]; then
  if suite_truthy_0434 "$RUN_OK_LIQUID_SURFACE_ENABLE"; then
    RUN_MODES="src-q6-g-f"
  else
    RUN_MODES="src src-q6"
  fi
else
  RUN_MODES="${RUN_MODES:-${MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src src-q6}}}}"
fi
 
# Livevis + 0433a WYSIWYR filtered recording.
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"; LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-2}"
RECORD_FIELDS="${RECORD_FIELDS:-mass,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-100}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
# LiveVis may consume device snapshots, but must not request a resampling host mirror.
LIVE_VIS_RESAMPLING_HOST_MIRROR="${LIVE_VIS_RESAMPLING_HOST_MIRROR:-0}"
LIVE_VIS_FORCE_HOST_MIRROR="${LIVE_VIS_FORCE_HOST_MIRROR:-0}"
export LIVE_VIS_RESAMPLING_HOST_MIRROR LIVE_VIS_FORCE_HOST_MIRROR
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

# Gamma-relative resampling thresholds. Actual integer thresholds are derived in common.
RESAMPLING_NMIN_COEF="${RESAMPLING_NMIN_COEF:-0.40}"  # Nmin = ceil(gamma*(1-coef))
RESAMPLING_NMAX_COEF="${RESAMPLING_NMAX_COEF:-0.60}"  # Nmax = ceil(gamma*(1+coef))
GUARD_EVERY="${GUARD_EVERY:-5}"

# Particle type ids are independent of the physical phase family.
INJECT_TYPE="${INJECT_TYPE:-1}"
BACKGROUND_TYPE="${BACKGROUND_TYPE:-2}"
INJECT_PHASE="${INJECT_PHASE:-liquid}"
BACKGROUND_PHASE="${BACKGROUND_PHASE:-gas}"

phase_defaults_0493w4() {
  local phase=$1 role=$2
  case "$phase" in
    liquid)
      printf '%s %s %s\n' "${role}_liquid_incompressible" 1.0 1.0
      ;;
    gas)
      printf '%s %s %s\n' "${role}_gas_compressible" 0.0 0.0
      ;;
    *)
      echo "[0493w4] ERROR ${role} phase must be liquid or gas, got '$phase'" >&2
      return 2
      ;;
  esac
}

read -r INJECT_NAME_DEFAULT INJECT_Q6_DEFAULT INJECT_CLOSURE_DEFAULT   < <(phase_defaults_0493w4 "$INJECT_PHASE" injected)
read -r BACKGROUND_NAME_DEFAULT BACKGROUND_Q6_DEFAULT BACKGROUND_CLOSURE_DEFAULT   < <(phase_defaults_0493w4 "$BACKGROUND_PHASE" background)

INJECT_SPECIES_NAME="${INJECT_SPECIES_NAME:-$INJECT_NAME_DEFAULT}"
BACKGROUND_SPECIES_NAME="${BACKGROUND_SPECIES_NAME:-$BACKGROUND_NAME_DEFAULT}"
INJECT_Q6_STRENGTH="${INJECT_Q6_STRENGTH:-${LIQUID_Q6_STRENGTH:-$INJECT_Q6_DEFAULT}}"
BACKGROUND_Q6_STRENGTH="${BACKGROUND_Q6_STRENGTH:-${GAS_Q6_STRENGTH:-$BACKGROUND_Q6_DEFAULT}}"
INJECT_MASS_CLOSURE_STRENGTH="${INJECT_MASS_CLOSURE_STRENGTH:-${LIQUID_MASS_CLOSURE_STRENGTH:-$INJECT_CLOSURE_DEFAULT}}"
BACKGROUND_MASS_CLOSURE_STRENGTH="${BACKGROUND_MASS_CLOSURE_STRENGTH:-${GAS_MASS_CLOSURE_STRENGTH:-$BACKGROUND_CLOSURE_DEFAULT}}"

case "$INJECT_PHASE:$BACKGROUND_PHASE" in
  liquid:gas) DEFAULT_INJECT_TO_BACKGROUND_MASS_RATIO=10. ;; ##################
  gas:liquid) DEFAULT_INJECT_TO_BACKGROUND_MASS_RATIO=0.01 ;;
  *) DEFAULT_INJECT_TO_BACKGROUND_MASS_RATIO=10.0 ;;
esac
INJECT_TO_BACKGROUND_MASS_RATIO="${INJECT_TO_BACKGROUND_MASS_RATIO:-${LIQUID_TO_GAS_MASS_RATIO:-$DEFAULT_INJECT_TO_BACKGROUND_MASS_RATIO}}"
BACKGROUND_PARTICLE_MASS="${BACKGROUND_PARTICLE_MASS:-$GAS_PARTICLE_MASS}"
PARTICLE_MASS="$BACKGROUND_PARTICLE_MASS"
INJECT_MASS="${INJECT_MASS:-$LIQUID_PARTICLE_MASS}"

SPECIES_DIAGNOSTICS_ENABLE="${SPECIES_DIAGNOSTICS_ENABLE:-true}"
SPECIES_DIAGNOSTICS_FILENAME="${SPECIES_DIAGNOSTICS_FILENAME:-species_runtime_injection_0493w4.csv}"
SPECIES_CELL_DIAGNOSTICS_ENABLE="${SPECIES_CELL_DIAGNOSTICS_ENABLE:-false}"
SPECIES_CELL_DIAGNOSTICS_FILENAME="${SPECIES_CELL_DIAGNOSTICS_FILENAME:-species_cell_injection_0493w4.csv}"
SPECIES_Q6_ENABLE="${SPECIES_Q6_ENABLE:-true}"
SPECIES_Q6_MODE="${SPECIES_Q6_MODE:-independent_masked}" #weighted independent_masked}"
SPECIES_Q6_SENSITIVITY="${SPECIES_Q6_SENSITIVITY:-1.0}"
SPECIES_Q6_FALLBACK_MODE="${SPECIES_Q6_FALLBACK_MODE:-common}"
SPECIES_Q6_COMPARISON_TOLERANCE="${SPECIES_Q6_COMPARISON_TOLERANCE:-1.0e-11}"
SPECIES_Q6_MIN_OCCUPANCY_FRACTION="${SPECIES_Q6_MIN_OCCUPANCY_FRACTION:-0.5}"
# 0490p strict species-aware resident resampling. 0491h-fix1 established that
# generic 0296, thermal renormalization and the legacy mass guard must remain off.
SPECIES_RESAMPLING_ENABLE="${SPECIES_RESAMPLING_ENABLE:-false}"
# 0493b: mutation policy is per species and defaults to enabled.
SPECIES0_RESAMPLING_ENABLE="${SPECIES0_RESAMPLING_ENABLE:-true}"
SPECIES1_RESAMPLING_ENABLE="${SPECIES1_RESAMPLING_ENABLE:-true}"
# 0493a: one resident production path for every boundary family.
SPECIES_RESIDENT_MODE="${SPECIES_RESIDENT_MODE:-production}"
RESAMPLING_HOST_PATCHBACK_ENABLE="${RESAMPLING_HOST_PATCHBACK_ENABLE:-0}"
RESAMPLING_SPARSE_DEVICE_GATE_ENABLE="${RESAMPLING_SPARSE_DEVICE_GATE_ENABLE:-0}"
MASS_RECONDITION_ENABLE="${MASS_RECONDITION_ENABLE:-0}"
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE="${RESAMPLING_THERMAL_RENORMALIZATION_ENABLE:-false}"
RESAMPLING_MASS_GUARD_ENABLE="${RESAMPLING_MASS_GUARD_ENABLE:-false}"
RESAMPLING_PARTICLE_MASS_MAX="${RESAMPLING_PARTICLE_MASS_MAX:-20.0}"
UIN="${UIN:-0.75}"
INLET_FACE="${INLET_FACE:-left}"; INLET_CENTER_Y="${INLET_CENTER_Y:-0.75}"; INLET_HEIGHT_CELLS="${INLET_HEIGHT_CELLS:-17.0}"
INLET_SMIN="${INLET_SMIN:-$(awk -v cy="$INLET_CENTER_Y" -v h="$INLET_HEIGHT_CELLS" -v ly="$Ly" -v ny="$NY" 'BEGIN{dy=ly/ny; y=cy-0.5*h*dy; if(y<0)y=0; printf "%.17g", y/ly}')}"
INLET_SMAX="${INLET_SMAX:-$(awk -v cy="$INLET_CENTER_Y" -v h="$INLET_HEIGHT_CELLS" -v ly="$Ly" -v ny="$NY" 'BEGIN{dy=ly/ny; y=cy+0.5*h*dy; if(y>ly)y=ly; printf "%.17g", y/ly}')}"
OUTLET_SMIN="${OUTLET_SMIN:-0.0}"; OUTLET_SMAX="${OUTLET_SMAX:-1.0}"
OUTLET_MODE="${OUTLET_MODE:-hybrid}"; OUTLET_FEEDBACK_GAIN="${OUTLET_FEEDBACK_GAIN:-0.0}"

# This runner currently implements a left-inlet/right-outlet geometry with
# velocities aligned with x. Balance the prescribed volumetric boundary flux:
# Uin * inletWidth = Uout * outletWidth.
if [[ "$INLET_FACE" != "left" ]]; then
  echo "[0493w4] ERROR INLET_FACE=$INLET_FACE unsupported; this runner currently requires left" >&2
  exit 2
fi

INLET_WIDTH="$(awk \
  -v a="$INLET_SMIN" \
  -v b="$INLET_SMAX" \
  'BEGIN {
     w = b - a;
     if (!(w > 0.0)) exit 2;
     printf "%.17g", w;
   }')"

OUTLET_WIDTH="$(awk \
  -v a="$OUTLET_SMIN" \
  -v b="$OUTLET_SMAX" \
  'BEGIN {
     w = b - a;
     if (!(w > 0.0)) exit 2;
     printf "%.17g", w;
   }')"

if [[ -z "${UOUT+x}" ]]; then
  UOUT="$(awk \
    -v u="$UIN" \
    -v wi="$INLET_WIDTH" \
    -v wo="$OUTLET_WIDTH" \
    'BEGIN {
       printf "%.17g", u * wi / wo;
     }')"
fi

if ! awk \
  -v uin="$UIN" \
  -v uout="$UOUT" \
  -v wi="$INLET_WIDTH" \
  -v wo="$OUTLET_WIDTH" \
  'BEGIN { exit (wi > 0.0 && wo > 0.0 && uin >= 0.0 && uout >= 0.0) ? 0 : 1 }'
then
  echo "[0493w4] ERROR invalid inlet/outlet geometry or velocities" >&2
  exit 2
fi

INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-1.0}"; INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-2}"

# Initial state selector.
#   INITIAL_DOMAIN_MODE=empty : empty domain with a preallocated inactive slot pool.
#   INITIAL_DOMAIN_MODE=full  : domain initially filled with background type 2.
# The inlet injects type 1 in both cases. Phase families are selected
# independently through INJECT_PHASE and BACKGROUND_PHASE.
INITIAL_DOMAIN_MODE="${INITIAL_DOMAIN_MODE:-full}"
EMPTY_INITIAL_SLOTS="${EMPTY_INITIAL_SLOTS:-}"
EMPTY_INITIAL_TYPE="${EMPTY_INITIAL_TYPE:-$BACKGROUND_TYPE}"
EMPTY_INITIAL_MASS="${EMPTY_INITIAL_MASS:-$BACKGROUND_PARTICLE_MASS}"
SCENARIO_EXPECTATION="${SCENARIO_EXPECTATION:-two_species}"
POSTCHECK_SPECIES_ENABLE="${POSTCHECK_SPECIES_ENABLE:-true}"
REQUIRE_MIXED_CELL_AT_END="${REQUIRE_MIXED_CELL_AT_END:-false}"
PHYSICS_LABEL="${PHYSICS_LABEL:-${INJECT_PHASE}_type${INJECT_TYPE}_into_${INITIAL_DOMAIN_MODE}_${BACKGROUND_PHASE}_type${BACKGROUND_TYPE}}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493w4_${CASE_LABEL}_${PHYSICS_LABEL}_mr${INJECT_TO_BACKGROUND_MASS_RATIO}_${NX}x${NY}_g${GAMMA}}"
# -----------------------------------------------------------------------------

INLET_TARGET_FLUX="$(awk \
  -v u="$UIN" \
  -v w="$INLET_WIDTH" \
  'BEGIN { printf "%.17g", u * w }')"

OUTLET_TARGET_FLUX="$(awk \
  -v u="$UOUT" \
  -v w="$OUTLET_WIDTH" \
  'BEGIN { printf "%.17g", u * w }')"

printf \
  '[0493w4] open-boundary targets Uin=%s widthIn=%s Uout=%s widthOut=%s Qin=%s Qout=%s\n' \
  "$UIN" \
  "$INLET_WIDTH" \
  "$UOUT" \
  "$OUTLET_WIDTH" \
  "$INLET_TARGET_FLUX" \
  "$OUTLET_TARGET_FLUX"

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

if suite_truthy_0434 "$RUN_OK_LIQUID_SURFACE_ENABLE"; then
  THERMOSTAT_ENABLE=true
  THERMOSTAT_MODE=cell_relative_rescale
  THERMOSTAT_EVERY=1
  THERMOSTAT_TARGET_KBT="$KBT"
  SPECIES_RESAMPLING_ENABLE=false
  LIQUID_RESAMPLING_ENABLE=false
  GAS_RESAMPLING_ENABLE=false
  MASS_RECONDITION_ENABLE=0
  RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
  RESAMPLING_MASS_GUARD_ENABLE=false
  WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
  CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
  VIRIAL_DENSITY_KICK_ENABLE=false
fi
suite_defaults_common_0434
suite_compute_derived_0434

[[ "$INITIAL_DOMAIN_MODE" == full ]] || { echo "[run_ok_injection_type1_into_type2] ERROR this runner is full-domain; use run_ok_injection_type1_into_type2_empty.sh for vacuum" >&2; exit 2; }

case "$SCENARIO_EXPECTATION" in
  empty|two_species) ;;
  *) echo "[0493w4] ERROR unknown SCENARIO_EXPECTATION=$SCENARIO_EXPECTATION; expected empty or two_species" >&2; exit 2 ;;
esac

case "$INITIAL_DOMAIN_MODE:$SCENARIO_EXPECTATION" in
  empty:empty|empty_refill:empty|empty-refill:empty|full:two_species) ;;
  *)
    echo "[0493w4] ERROR inconsistent initial/scenario contract: INITIAL_DOMAIN_MODE=$INITIAL_DOMAIN_MODE SCENARIO_EXPECTATION=$SCENARIO_EXPECTATION" >&2
    exit 2
    ;;
esac

# Full liquid/gas interface.  Mechanical capillarity is active through x9 and
# gas pressure through x6g.  Kinetic reflection/one-for-one/x12a are disabled.
[[ "$INJECT_PHASE" == liquid && "$BACKGROUND_PHASE" == gas ]] || {
  echo "[run_ok_injection_type1_into_type2] ERROR default full surface case requires INJECT_PHASE=liquid BACKGROUND_PHASE=gas" >&2
  exit 2
}
RUN_OK_LIQUID_SURFACE_PHASE_A="type:$INJECT_TYPE"
RUN_OK_LIQUID_SURFACE_PHASE_B="type:$BACKGROUND_TYPE"
PHASE_INTERFACE_A_SELECTOR="$RUN_OK_LIQUID_SURFACE_PHASE_A"
PHASE_INTERFACE_B_SELECTOR="$RUN_OK_LIQUID_SURFACE_PHASE_B"

if suite_truthy_0434 "$POSTCHECK_SPECIES_ENABLE" && ! suite_truthy_0434 "$SPECIES_DIAGNOSTICS_ENABLE"; then
  echo "[0493w4] ERROR POSTCHECK_SPECIES_ENABLE=true requires SPECIES_DIAGNOSTICS_ENABLE=true" >&2
  exit 2
fi
if suite_truthy_0434 "$REQUIRE_MIXED_CELL_AT_END" && ! suite_truthy_0434 "$SPECIES_CELL_DIAGNOSTICS_ENABLE"; then
  echo "[0493w4] ERROR REQUIRE_MIXED_CELL_AT_END=true requires SPECIES_CELL_DIAGNOSTICS_ENABLE=true" >&2
  exit 2
fi

if [[ "$INJECT_TYPE" == "$BACKGROUND_TYPE" ]]; then
  echo "[0434-suite] ERROR INJECT_TYPE and BACKGROUND_TYPE must be distinct for two-species injection testing" >&2
  exit 2
fi

INJECT_REFERENCE_CELL_MASS="${INJECT_REFERENCE_CELL_MASS:-${LIQUID_REFERENCE_CELL_MASS:-$(awk -v g="$GAMMA" -v m="$INJECT_MASS" 'BEGIN{printf "%.17g", g*m}')}}"
BACKGROUND_REFERENCE_CELL_MASS="${BACKGROUND_REFERENCE_CELL_MASS:-${GAS_REFERENCE_CELL_MASS:-$(awk -v g="$GAMMA" -v m="$BACKGROUND_PARTICLE_MASS" 'BEGIN{printf "%.17g", g*m}')}}"
ACTUAL_INJECT_TO_BACKGROUND_MASS_RATIO="$(awk -v mi="$INJECT_MASS" -v mb="$BACKGROUND_PARTICLE_MASS" 'BEGIN{printf "%.17g", mi/mb}')"

# 0493x7h: when Q6-g-f is selected, keep this runner's explicit two-species
# registry and enable x6g only when one of those species is a gas phase.
if suite_mode_set_has_q6_g_f_0493x7h; then
  Q6_GF_EXTERNAL_SPECIES=1
  if [[ "$INJECT_PHASE" == gas || "$BACKGROUND_PHASE" == gas ]]; then
    Q6_GF_HAS_GAS_PHASE=1
  else
    Q6_GF_HAS_GAS_PHASE=0
  fi
  projected_liquid_count=0
  [[ "$INJECT_PHASE" == liquid ]] && awk -v a="$INJECT_Q6_STRENGTH" 'BEGIN{exit !(a>0)}' && projected_liquid_count=$((projected_liquid_count+1))
  [[ "$BACKGROUND_PHASE" == liquid ]] && awk -v a="$BACKGROUND_Q6_STRENGTH" 'BEGIN{exit !(a>0)}' && projected_liquid_count=$((projected_liquid_count+1))
  if [[ "$projected_liquid_count" != 1 ]]; then
    echo "[0493x7h] ERROR src-q6-g-f injection requires exactly one liquid species with q6Strength>0; got $projected_liquid_count" >&2
    exit 2
  fi
fi

write_params_0434() {
  local mode=$1 state=$2 out=$3 chi=$4 params=$5
  local species_q6_enable_for_mode=false
  if suite_path_has_q6_0434 "$mode" && suite_truthy_0434 "$SPECIES_Q6_ENABLE"; then
    species_q6_enable_for_mode=true
  fi
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = solid
bcY = solid
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 4
openBoundarySegment0 = ${INLET_FACE} inlet ${INLET_SMIN} ${INLET_SMAX} ${UIN} 0.0 ${INJECT_TYPE} ${INJECT_MASS}
openBoundarySegment1 = right outlet ${OUTLET_SMIN} ${OUTLET_SMAX} ${UOUT} 0.0 0 ${PARTICLE_MASS}
openBoundarySegment2 = ${INLET_FACE} inlet 0.01 ${INLET_SMIN} 0.01 0.0 2 0.1
openBoundarySegment3 = ${INLET_FACE} inlet ${INLET_SMAX} 0.99 0.01 0.0 2 0.1


inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.25
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = -0.00001
inletThermalNoise = ${INLET_THERMAL_NOISE}
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = ${INLET_RESERVOIR_CELLS}
inletTargetOccupancy = ${GAMMA}
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true
openBoundaryOutletMode = ${OUTLET_MODE}
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = ${OUTLET_FEEDBACK_GAIN}
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = ${PARTICLE_MASS}
wallKBT = -1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
species0 = ${INJECT_TYPE} ${INJECT_SPECIES_NAME} ${INJECT_PHASE} ${INJECT_Q6_STRENGTH} ${INJECT_MASS_CLOSURE_STRENGTH} ${INJECT_REFERENCE_CELL_MASS}
species0ResamplingEnable = ${SPECIES0_RESAMPLING_ENABLE}
species1 = ${BACKGROUND_TYPE} ${BACKGROUND_SPECIES_NAME} ${BACKGROUND_PHASE} ${BACKGROUND_Q6_STRENGTH} ${BACKGROUND_MASS_CLOSURE_STRENGTH} ${BACKGROUND_REFERENCE_CELL_MASS}
species1ResamplingEnable = ${SPECIES1_RESAMPLING_ENABLE}
speciesRequireRegisteredTypes = true
speciesThermostatEnable = ${SPECIES_THERMOSTAT_ENABLE}
species0ThermostatTargetKBT = ${INJECT_THERMOSTAT_TARGET_KBT}
species1ThermostatTargetKBT = ${BACKGROUND_THERMOSTAT_TARGET_KBT}
speciesDiagnosticsEnable = ${SPECIES_DIAGNOSTICS_ENABLE}
speciesDiagnosticsFilename = ${SPECIES_DIAGNOSTICS_FILENAME}
speciesCellDiagnosticsEnable = ${SPECIES_CELL_DIAGNOSTICS_ENABLE}
speciesCellDiagnosticsFilename = ${SPECIES_CELL_DIAGNOSTICS_FILENAME}
speciesQ6Enable = ${species_q6_enable_for_mode}
speciesQ6Sensitivity = ${SPECIES_Q6_SENSITIVITY}
speciesQ6FallbackMode = ${SPECIES_Q6_FALLBACK_MODE}
speciesQ6ComparisonTolerance = ${SPECIES_Q6_COMPARISON_TOLERANCE}
speciesQ6MinOccupancyFraction = ${SPECIES_Q6_MIN_OCCUPANCY_FRACTION}
PARAMS
  run_ok_surface_append_params_0493x13zi "$params" "$RUN_OK_LIQUID_SURFACE_PHASE_A" "$RUN_OK_LIQUID_SURFACE_PHASE_B"
  suite_write_common_params_0434 "$mode" >> "$params"
  :
}

generate_empty_initial_state_0434() {
  local state=$1
  local empty_slots="$EMPTY_INITIAL_SLOTS"
  local empty_type="$EMPTY_INITIAL_TYPE"
  local empty_mass="${EMPTY_INITIAL_MASS:-$PARTICLE_MASS}"

  if [[ -z "$empty_slots" ]]; then
    empty_slots="$(python3 - "$NX" "$NY" "$GAMMA" <<'PYSLOTS'
import sys
Nx, Ny, gamma = map(int, sys.argv[1:4])
print(Nx * Ny * gamma)
PYSLOTS
)"
  fi

  python3 - "$state" "$empty_slots" "$empty_type" "$empty_mass" <<'PYGEN'
import os
import struct
import sys

out, nslot, typ0, mass0 = sys.argv[1:]
nslot = int(nslot)
typ0 = int(typ0)
mass0 = float(mass0)
if nslot < 0:
    raise SystemExit(f"EMPTY_INITIAL_SLOTS must be non-negative, got {nslot}")
if mass0 <= 0.0:
    raise SystemExit(f"EMPTY_INITIAL_MASS/PARTICLE_MASS must be positive, got {mass0}")

x = [0.0] * nslot
y = [0.0] * nslot
vx = [0.0] * nslot
vy = [0.0] * nslot
typ = [typ0] * nslot
mass = [mass0] * nslot
role = [0] * nslot  # inactive

os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
magic = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
reserved = [0] * 8
reserved[0] = 1
reserved[1] = 1
n = len(x)
with open(out, "wb") as f:
    f.write(magic)
    f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
    f.write(struct.pack("<8Q", *reserved))
    for arr, fmt in [
        (x, "d"), (y, "d"), (vx, "d"), (vy, "d"),
        (typ, "I"), (mass, "d"), (role, "B"),
    ]:
        f.write(struct.pack("<%d%s" % (n, fmt), *arr))
print(f"[0434-generate-empty] state={out} fluid=0 inactive={nslot} total={nslot} type={typ0} mass={mass0}")
PYGEN
}

run_one_mode_0434() {
  local mode=$1
  suite_validate_path_0434 "$mode"
  if suite_truthy_0434 "$RUN_OK_LIQUID_SURFACE_ENABLE"; then
    [[ "$mode" == src-q6-g-f ]] || { echo "[run_ok_injection_type1_into_type2] ERROR surface profile requires src-q6-g-f" >&2; return 2; }
  fi
  local run_root="$BASE_RUN_ROOT/$mode"
  suite_prepare_dirs_0434 "$run_root"
  local state_suffix="${CASE_LABEL}_${NX}x${NY}_g${GAMMA}"
  local chi=""
  case "$INITIAL_DOMAIN_MODE" in
    full)
      ;;
    empty|empty_refill|empty-refill)
      state_suffix="${state_suffix}_empty"
      ;;
    *)
      echo "[0434-suite] unknown INITIAL_DOMAIN_MODE='$INITIAL_DOMAIN_MODE'. Expected full or empty." >&2
      return 2
      ;;
  esac

  local state="$run_root/init/${state_suffix}.smpcd"
  local params="$run_root/params/${CASE_LABEL}.kv"
  local out="$run_root/output"
  local log="$run_root/logs/${CASE_LABEL}.log"
  local time="$run_root/logs/${CASE_LABEL}.time"
  mkdir -p "$out"

  case "$INITIAL_DOMAIN_MODE" in
    full)
      RUN_OK_GENERATOR_PATH="$ROOT/${GENERATOR_0434}"
      export RUN_OK_GENERATOR_PATH
      suite_generate_case_0434 "$state" "$chi"
      ;;
    empty|empty_refill|empty-refill)
      RUN_OK_GENERATOR_PATH="embedded:generate_empty_initial_state_0434"
      export RUN_OK_GENERATOR_PATH
      generate_empty_initial_state_0434 "$state"
      ;;
  esac

  python3 scripts/check_injection_species_0492b.py state \
    --state "$state" \
    --scenario "$SCENARIO_EXPECTATION" \
    --inject-type "$INJECT_TYPE" \
    --background-type "$BACKGROUND_TYPE"

  write_params_0434 "$mode" "$state" "$out" "$chi" "$params"
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  run_ok_export_q6_cuda_profile_0493x7r "$mode"
  PHASE_INTERFACE_B_SELECTOR="$RUN_OK_LIQUID_SURFACE_PHASE_B"
  run_ok_surface_export_off_flags_0493x13zi
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode"
  run_ok_append_q6_profile_audit_0493x7r "$run_root/logs/environment_0434.env" "$mode"
  cat >> "$run_root/logs/environment_0434.env" <<META_SURFACE
RUN_OK_LIQUID_SURFACE_ENABLE=$RUN_OK_LIQUID_SURFACE_ENABLE
SURFACE_TENSION_SIGMA=$SURFACE_TENSION_SIGMA
SURFACE_TENSION_MIN_RADIUS_CELLS=$SURFACE_TENSION_MIN_RADIUS_CELLS
PHASE_INTERFACE_A_SELECTOR=$RUN_OK_LIQUID_SURFACE_PHASE_A
PHASE_INTERFACE_B_SELECTOR=$RUN_OK_LIQUID_SURFACE_PHASE_B
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION=$PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION
X12A_LOCAL_THERMAL_RADIUS_CELLS=$X12A_LOCAL_THERMAL_RADIUS_CELLS
META_SURFACE
  run_ok_print_q6_profile_0493x7r "$mode"
  PHASE_INTERFACE_A_SELECTOR="$RUN_OK_LIQUID_SURFACE_PHASE_A"
  PHASE_INTERFACE_B_SELECTOR="$RUN_OK_LIQUID_SURFACE_PHASE_B"
  run_ok_surface_print_0493x13zi "$(suite_truthy_0434 "$RUN_OK_LIQUID_SURFACE_ENABLE" && printf x9+x6g-liquid-gas-no-kinetic-closure || printf off)"
  cat >> "$run_root/logs/environment_0434.env" <<META_0493W4
INITIAL_DOMAIN_MODE=${INITIAL_DOMAIN_MODE}
SCENARIO_EXPECTATION=${SCENARIO_EXPECTATION}
POSTCHECK_SPECIES_ENABLE=${POSTCHECK_SPECIES_ENABLE}
REQUIRE_MIXED_CELL_AT_END=${REQUIRE_MIXED_CELL_AT_END}
SPECIES_DIAGNOSTICS_ENABLE=${SPECIES_DIAGNOSTICS_ENABLE}
SPECIES_CELL_DIAGNOSTICS_ENABLE=${SPECIES_CELL_DIAGNOSTICS_ENABLE}
INJECT_PHASE=${INJECT_PHASE}
BACKGROUND_PHASE=${BACKGROUND_PHASE}
INJECT_SPECIES_NAME=${INJECT_SPECIES_NAME}
BACKGROUND_SPECIES_NAME=${BACKGROUND_SPECIES_NAME}
INJECT_Q6_STRENGTH=${INJECT_Q6_STRENGTH}
BACKGROUND_Q6_STRENGTH=${BACKGROUND_Q6_STRENGTH}
INJECT_MASS_CLOSURE_STRENGTH=${INJECT_MASS_CLOSURE_STRENGTH}
BACKGROUND_MASS_CLOSURE_STRENGTH=${BACKGROUND_MASS_CLOSURE_STRENGTH}
INJECT_TO_BACKGROUND_MASS_RATIO=${ACTUAL_INJECT_TO_BACKGROUND_MASS_RATIO}
SPECIES_THERMOSTAT_ENABLE=${SPECIES_THERMOSTAT_ENABLE}
INJECT_THERMOSTAT_TARGET_KBT=${INJECT_THERMOSTAT_TARGET_KBT}
BACKGROUND_THERMOSTAT_TARGET_KBT=${BACKGROUND_THERMOSTAT_TARGET_KBT}
META_0493W4
  echo "[0434-suite] case=$CASE_LABEL mode=$mode root=$run_root"
  echo "[0434-suite] initialDomainMode=$INITIAL_DOMAIN_MODE state=$state"
  if [[ "$INITIAL_DOMAIN_MODE" == full ]]; then
    echo "[0434-suite] inject(type=$INJECT_TYPE,phase=$INJECT_PHASE,mass=$INJECT_MASS,q6Alpha=$INJECT_Q6_STRENGTH,closure=$INJECT_MASS_CLOSURE_STRENGTH) into background(type=$BACKGROUND_TYPE,phase=$BACKGROUND_PHASE,mass=$BACKGROUND_PARTICLE_MASS,q6Alpha=$BACKGROUND_Q6_STRENGTH,closure=$BACKGROUND_MASS_CLOSURE_STRENGTH) mass_ratio=$ACTUAL_INJECT_TO_BACKGROUND_MASS_RATIO"
    echo "[0493x14d] speciesThermostat=$SPECIES_THERMOSTAT_ENABLE injectKBT=$INJECT_THERMOSTAT_TARGET_KBT backgroundKBT=$BACKGROUND_THERMOSTAT_TARGET_KBT"
  else
    echo "[0434-suite] inject(type=$INJECT_TYPE,phase=$INJECT_PHASE,mass=$INJECT_MASS,q6Alpha=$INJECT_Q6_STRENGTH,closure=$INJECT_MASS_CLOSURE_STRENGTH) into empty domain; inactiveSlotType=$BACKGROUND_TYPE inactiveSlotPhase=$BACKGROUND_PHASE inactiveSlotMass=$BACKGROUND_PARTICLE_MASS"
  fi
  if suite_path_has_q6_0434 "$mode" && suite_truthy_0434 "$SPECIES_Q6_ENABLE"; then
    local effective_q6_mode="$SPECIES_Q6_MODE" effective_min_occ="$SPECIES_Q6_MIN_OCCUPANCY_FRACTION"
    if suite_path_has_q6_g_f_0493x7h "$mode"; then
      effective_q6_mode=free_surface_masked
      effective_min_occ="$Q6_GF_MIN_FILL_FRACTION"
    fi
    echo "[0434-suite] speciesQ6=on mode=$effective_q6_mode sensitivity=$SPECIES_Q6_SENSITIVITY fallback=$SPECIES_Q6_FALLBACK_MODE tolerance=$SPECIES_Q6_COMPARISON_TOLERANCE minOcc=$effective_min_occ"
  else
    echo "[0434-suite] speciesQ6=off for mode=$mode"
  fi
  local resident_mode
  resident_mode="$(suite_species_resident_mode_0492a "$mode" "$TOPOLOGY")"
  echo "[0434-suite] resampling thresholds: Nmin=$GUARD_NMIN Ntarget=$GUARD_NTARGET Nmax=$GUARD_NMAX from gamma=$GAMMA speciesResampling=$SPECIES_RESAMPLING_ENABLE speciesResident=$resident_mode massRecondition0296=$MASS_RECONDITION_ENABLE"
  suite_run_binary_0434 "$params" "$log" "$time" "$out"

  if ! suite_truthy_0434 "$PREFLIGHT_ONLY" && suite_truthy_0434 "$POSTCHECK_SPECIES_ENABLE"; then
    postcheck_args=(
      runtime
      --csv "$out/$SPECIES_DIAGNOSTICS_FILENAME"
      --scenario "$SCENARIO_EXPECTATION"
      --inject-type "$INJECT_TYPE"
      --background-type "$BACKGROUND_TYPE"
      --inject-phase "$INJECT_PHASE"
      --background-phase "$BACKGROUND_PHASE"
      --inject-q6 "$INJECT_Q6_STRENGTH"
      --background-q6 "$BACKGROUND_Q6_STRENGTH"
      --inject-closure "$INJECT_MASS_CLOSURE_STRENGTH"
      --background-closure "$BACKGROUND_MASS_CLOSURE_STRENGTH"
    )
    if suite_truthy_0434 "$REQUIRE_MIXED_CELL_AT_END"; then
      postcheck_args+=(
        --cell-csv "$out/$SPECIES_CELL_DIAGNOSTICS_FILENAME"
        --require-mixed-cell
      )
    fi
    python3 scripts/check_injection_species_0492b.py "${postcheck_args[@]}"
  fi
}

while IFS= read -r mode; do
  [[ -n "$mode" ]] || continue
  run_one_mode_0434 "$mode"
done < <(suite_mode_list_0434)

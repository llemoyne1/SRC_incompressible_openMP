#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# -----------------------------------------------------------------------------
# USER EDIT ZONE -- common layout in all 0434 scripts
# -----------------------------------------------------------------------------
CASE_LABEL="injection_type1_into_type2"
GEN_CASE="injection"
TOPOLOGY="${TOPOLOGY:-segmented}"
Lx="${Lx:-3.0}"; Ly="${Ly:-1.0}"; NX="${NX:-900}"; NY="${NY:-300}"
GAMMA="${GAMMA:-10}"; STEPS="${STEPS:-5000}"; DT="${DT:-0.01}"; KBT="${KBT:-0.005}"
SEED="${SEED:-1628431}"; U0="${U0:-0.0}"; VELOCITY_MODE="${VELOCITY_MODE:-zero}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-5.0}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000000}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-$ROOT/livevis_control.kv}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"

# Baseline validation intentionally excludes resampling so SRC and SRC+Q6 can
# be compared before any population mutation is introduced. Resampling paths
# remain available only through an explicit override such as:
#   RUN_MODES="src-resampling src-q6-resampling" SPECIES_RESAMPLING_ENABLE=true
RUN_MODES="${RUN_MODES:-${MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src src-q6}}}}" 
 
# Livevis + 0433a WYSIWYR filtered recording.
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"; LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-2}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"; RECORD_STRIDE="${RECORD_STRIDE:-1}"
FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-1}"
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
INJECT_PHASE="${INJECT_PHASE:-gas}"
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
  liquid:gas) DEFAULT_INJECT_TO_BACKGROUND_MASS_RATIO=1.5 ;; ##################
  gas:liquid) DEFAULT_INJECT_TO_BACKGROUND_MASS_RATIO=0.01 ;;
  *) DEFAULT_INJECT_TO_BACKGROUND_MASS_RATIO=10.0 ;;
esac
INJECT_TO_BACKGROUND_MASS_RATIO="${INJECT_TO_BACKGROUND_MASS_RATIO:-${LIQUID_TO_GAS_MASS_RATIO:-$DEFAULT_INJECT_TO_BACKGROUND_MASS_RATIO}}"
BACKGROUND_PARTICLE_MASS="${BACKGROUND_PARTICLE_MASS:-${GAS_PARTICLE_MASS:-${PARTICLE_MASS:-1.0}}}"
PARTICLE_MASS="$BACKGROUND_PARTICLE_MASS"
INJECT_MASS="${INJECT_MASS:-$(awk -v mb="$BACKGROUND_PARTICLE_MASS" -v r="$INJECT_TO_BACKGROUND_MASS_RATIO" 'BEGIN{printf "%.17g", mb*r}')}"

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
UIN="${UIN:-0.5}"
INLET_FACE="${INLET_FACE:-left}"; INLET_CENTER_Y="${INLET_CENTER_Y:-0.5}"; INLET_HEIGHT_CELLS="${INLET_HEIGHT_CELLS:-15.0}"
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
INITIAL_DOMAIN_MODE="${INITIAL_DOMAIN_MODE:-empty}"
EMPTY_INITIAL_SLOTS="${EMPTY_INITIAL_SLOTS:-}"
EMPTY_INITIAL_TYPE="${EMPTY_INITIAL_TYPE:-$BACKGROUND_TYPE}"
EMPTY_INITIAL_MASS="${EMPTY_INITIAL_MASS:-$BACKGROUND_PARTICLE_MASS}"
SCENARIO_EXPECTATION="${SCENARIO_EXPECTATION:-empty}"
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

suite_defaults_common_0434
suite_compute_derived_0434

case "$INITIAL_DOMAIN_MODE" in
  empty|empty_refill|empty-refill|full) ;;
  *) echo "[0434-suite] ERROR unknown INITIAL_DOMAIN_MODE=$INITIAL_DOMAIN_MODE; expected empty or full" >&2; exit 2 ;;
esac

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
openBoundarySegmentCount = 2
openBoundarySegment0 = ${INLET_FACE} inlet ${INLET_SMIN} ${INLET_SMAX} ${UIN} 0.0 ${INJECT_TYPE} ${INJECT_MASS}
openBoundarySegment1 = right outlet ${OUTLET_SMIN} ${OUTLET_SMAX} ${UOUT} 0.0 0 ${PARTICLE_MASS}
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
speciesDiagnosticsEnable = ${SPECIES_DIAGNOSTICS_ENABLE}
speciesDiagnosticsFilename = ${SPECIES_DIAGNOSTICS_FILENAME}
speciesCellDiagnosticsEnable = ${SPECIES_CELL_DIAGNOSTICS_ENABLE}
speciesCellDiagnosticsFilename = ${SPECIES_CELL_DIAGNOSTICS_FILENAME}
speciesQ6Enable = ${species_q6_enable_for_mode}
speciesQ6Mode = ${SPECIES_Q6_MODE}
speciesQ6Sensitivity = ${SPECIES_Q6_SENSITIVITY}
speciesQ6FallbackMode = ${SPECIES_Q6_FALLBACK_MODE}
speciesQ6ComparisonTolerance = ${SPECIES_Q6_COMPARISON_TOLERANCE}
speciesQ6MinOccupancyFraction = ${SPECIES_Q6_MIN_OCCUPANCY_FRACTION}
PARAMS
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
      suite_generate_case_0434 "$state" "$chi"
      ;;
    empty|empty_refill|empty-refill)
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
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode"
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
META_0493W4
  echo "[0434-suite] case=$CASE_LABEL mode=$mode root=$run_root"
  echo "[0434-suite] initialDomainMode=$INITIAL_DOMAIN_MODE state=$state"
  if [[ "$INITIAL_DOMAIN_MODE" == full ]]; then
    echo "[0434-suite] inject(type=$INJECT_TYPE,phase=$INJECT_PHASE,mass=$INJECT_MASS,q6Alpha=$INJECT_Q6_STRENGTH,closure=$INJECT_MASS_CLOSURE_STRENGTH) into background(type=$BACKGROUND_TYPE,phase=$BACKGROUND_PHASE,mass=$BACKGROUND_PARTICLE_MASS,q6Alpha=$BACKGROUND_Q6_STRENGTH,closure=$BACKGROUND_MASS_CLOSURE_STRENGTH) mass_ratio=$ACTUAL_INJECT_TO_BACKGROUND_MASS_RATIO"
  else
    echo "[0434-suite] inject(type=$INJECT_TYPE,phase=$INJECT_PHASE,mass=$INJECT_MASS,q6Alpha=$INJECT_Q6_STRENGTH,closure=$INJECT_MASS_CLOSURE_STRENGTH) into empty domain; inactiveSlotType=$BACKGROUND_TYPE inactiveSlotPhase=$BACKGROUND_PHASE inactiveSlotMass=$BACKGROUND_PARTICLE_MASS"
  fi
  if suite_path_has_q6_0434 "$mode" && suite_truthy_0434 "$SPECIES_Q6_ENABLE"; then
    echo "[0434-suite] speciesQ6=on mode=$SPECIES_Q6_MODE sensitivity=$SPECIES_Q6_SENSITIVITY fallback=$SPECIES_Q6_FALLBACK_MODE tolerance=$SPECIES_Q6_COMPARISON_TOLERANCE minOcc=$SPECIES_Q6_MIN_OCCUPANCY_FRACTION"
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

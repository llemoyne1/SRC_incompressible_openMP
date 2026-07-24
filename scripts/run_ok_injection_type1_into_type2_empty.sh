#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# -----------------------------------------------------------------------------
# USER EDIT ZONE -- common layout in all 0434 scripts
# -----------------------------------------------------------------------------
CASE_LABEL="injection_type1_into_type2"
PHYSICS_LABEL="${PHYSICS_LABEL:-liquid_type1_into_gas_type2}"
GEN_CASE="injection"
TOPOLOGY="segmented"
Lx="${Lx:-3.0}"; Ly="${Ly:-1.0}"; NX="${NX:-900}"; NY="${NY:-300}"
GAMMA="${GAMMA:-10}"; STEPS="${STEPS:-5000}"; DT="${DT:-0.01}"; KBT="${KBT:-0.005}"
SEED="${SEED:-1628431}"; U0="${U0:-0.0}"; VELOCITY_MODE="${VELOCITY_MODE:-zero}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-5.0}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000000}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"

# Path choice: set RUN_MODES/MODES="src" or INTEG_PATH=src-q6-resampling.
# Default runs one robust path selected below. To compare all paths, set:
#   RUN_MODES="src src-resampling src-q6 src-q6-resampling"
RUN_MODES="${RUN_MODES:-${MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src-q6}}}}"

# Livevis + 0433a WYSIWYR filtered recording.
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-1200}"; LIVE_VIS_NY="${LIVE_VIS_NY:-300}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-gray}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-2}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"; RECORD_STRIDE="${RECORD_STRIDE:-1}"
FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
LIVE_PROGRESS=${LIVE_PROGRESS:-1}
LIVE_VIS_HOLD_ON_EXIT=${LIVE_VIS_HOLD_ON_EXIT:-1}

# Gamma-relative resampling thresholds. Actual integer thresholds are derived in common.
RESAMPLING_NMIN_COEF="${RESAMPLING_NMIN_COEF:-0.40}"  # Nmin = ceil(gamma*(1-coef))
RESAMPLING_NMAX_COEF="${RESAMPLING_NMAX_COEF:-0.60}"  # Nmax = ceil(gamma*(1+coef))
GUARD_EVERY="${GUARD_EVERY:-5}"

BACKGROUND_TYPE="${BACKGROUND_TYPE:-2}"   # compressible gas
INJECT_TYPE="${INJECT_TYPE:-1}"           # incompressible liquid
LIQUID_TO_GAS_MASS_RATIO="${LIQUID_TO_GAS_MASS_RATIO:-10.0}"
GAS_PARTICLE_MASS="${GAS_PARTICLE_MASS:-${PARTICLE_MASS:-1.0}}"
PARTICLE_MASS="${PARTICLE_MASS:-$GAS_PARTICLE_MASS}"
INJECT_MASS="${INJECT_MASS:-$(awk -v mg="$PARTICLE_MASS" -v r="$LIQUID_TO_GAS_MASS_RATIO" 'BEGIN{printf "%.17g", mg*r}')}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0491_${CASE_LABEL}_${PHYSICS_LABEL}_mr${LIQUID_TO_GAS_MASS_RATIO}_${NX}x${NY}_g${GAMMA}}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
LIQUID_MASS_CLOSURE_STRENGTH="${LIQUID_MASS_CLOSURE_STRENGTH:-1.0}"
GAS_MASS_CLOSURE_STRENGTH="${GAS_MASS_CLOSURE_STRENGTH:-0.0}"
SPECIES_DIAGNOSTICS_ENABLE="${SPECIES_DIAGNOSTICS_ENABLE:-true}"
SPECIES_CELL_DIAGNOSTICS_ENABLE="${SPECIES_CELL_DIAGNOSTICS_ENABLE:-false}"
SPECIES_Q6_ENABLE="${SPECIES_Q6_ENABLE:-true}"
SPECIES_Q6_MODE="${SPECIES_Q6_MODE:-weighted}"
SPECIES_Q6_SENSITIVITY="${SPECIES_Q6_SENSITIVITY:-1.0}"
SPECIES_Q6_FALLBACK_MODE="${SPECIES_Q6_FALLBACK_MODE:-common}"
SPECIES_Q6_COMPARISON_TOLERANCE="${SPECIES_Q6_COMPARISON_TOLERANCE:-1.0e-11}"
RESAMPLING_PARTICLE_MASS_MAX="${RESAMPLING_PARTICLE_MASS_MAX:-20.0}"
UIN="${UIN:-0.5}"
INLET_FACE="${INLET_FACE:-left}"; INLET_CENTER_Y="${INLET_CENTER_Y:-0.5}"; INLET_HEIGHT_CELLS="${INLET_HEIGHT_CELLS:-15.0}"
INLET_SMIN="${INLET_SMIN:-$(awk -v cy="$INLET_CENTER_Y" -v h="$INLET_HEIGHT_CELLS" -v ly="$Ly" -v ny="$NY" 'BEGIN{dy=ly/ny; y=cy-0.5*h*dy; if(y<0)y=0; printf "%.17g", y/ly}')}"
INLET_SMAX="${INLET_SMAX:-$(awk -v cy="$INLET_CENTER_Y" -v h="$INLET_HEIGHT_CELLS" -v ly="$Ly" -v ny="$NY" 'BEGIN{dy=ly/ny; y=cy+0.5*h*dy; if(y>ly)y=ly; printf "%.17g", y/ly}')}"
OUTLET_SMIN="${OUTLET_SMIN:-0.0}"; OUTLET_SMAX="${OUTLET_SMAX:-1.0}"
OUTLET_MODE="${OUTLET_MODE:-hybrid}"; OUTLET_FEEDBACK_GAIN="${OUTLET_FEEDBACK_GAIN:-0.0}"
INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-1.0}"; INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-2}"

# Initial state selector.
#   INITIAL_DOMAIN_MODE=full  : current 0434 behavior, domain initially filled at gamma.
#   INITIAL_DOMAIN_MODE=empty : no initial fluid particles; inactive pool sized for refill.
#
# EMPTY_INITIAL_SLOTS defaults to one full-domain target occupancy GAMMA*Nx*Ny,
# so the same script can be used for empty-refill / advancing-front tests.
INITIAL_DOMAIN_MODE="${INITIAL_DOMAIN_MODE:-full}"
EMPTY_INITIAL_SLOTS="${EMPTY_INITIAL_SLOTS:-}"
EMPTY_INITIAL_TYPE="${EMPTY_INITIAL_TYPE:-$BACKGROUND_TYPE}"
EMPTY_INITIAL_MASS="${EMPTY_INITIAL_MASS:-$PARTICLE_MASS}"
# -----------------------------------------------------------------------------

suite_defaults_common_0434
suite_compute_derived_0434

if [[ "$INJECT_TYPE" == "$BACKGROUND_TYPE" ]]; then
  echo "[0434-suite] ERROR INJECT_TYPE and BACKGROUND_TYPE must be distinct for liquid-into-gas testing" >&2
  exit 2
fi

LIQUID_REFERENCE_CELL_MASS="${LIQUID_REFERENCE_CELL_MASS:-$(awk -v g="$GAMMA" -v m="$INJECT_MASS" 'BEGIN{printf "%.17g", g*m}')}"
GAS_REFERENCE_CELL_MASS="${GAS_REFERENCE_CELL_MASS:-$(awk -v g="$GAMMA" -v m="$PARTICLE_MASS" 'BEGIN{printf "%.17g", g*m}')}"
ACTUAL_LIQUID_TO_GAS_MASS_RATIO="$(awk -v ml="$INJECT_MASS" -v mg="$PARTICLE_MASS" 'BEGIN{printf "%.17g", ml/mg}')"

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
openBoundarySegment1 = right outlet ${OUTLET_SMIN} ${OUTLET_SMAX} ${UIN} 0.0 0 ${PARTICLE_MASS}
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
species0 = ${INJECT_TYPE} liquid_incompressible liquid ${LIQUID_Q6_STRENGTH} ${LIQUID_MASS_CLOSURE_STRENGTH} ${LIQUID_REFERENCE_CELL_MASS}
species1 = ${BACKGROUND_TYPE} gas_compressible gas ${GAS_Q6_STRENGTH} ${GAS_MASS_CLOSURE_STRENGTH} ${GAS_REFERENCE_CELL_MASS}
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = ${SPECIES_DIAGNOSTICS_ENABLE}
speciesDiagnosticsFilename = species_runtime_liquid_into_gas_0491.csv
speciesCellDiagnosticsEnable = ${SPECIES_CELL_DIAGNOSTICS_ENABLE}
speciesCellDiagnosticsFilename = species_cell_liquid_into_gas_0491.csv
speciesQ6Enable = ${species_q6_enable_for_mode}
speciesQ6Mode = ${SPECIES_Q6_MODE}
speciesQ6Sensitivity = ${SPECIES_Q6_SENSITIVITY}
speciesQ6FallbackMode = ${SPECIES_Q6_FALLBACK_MODE}
speciesQ6ComparisonTolerance = ${SPECIES_Q6_COMPARISON_TOLERANCE}
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

  write_params_0434 "$mode" "$state" "$out" "$chi" "$params"
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode"
  echo "[0434-suite] case=$CASE_LABEL mode=$mode root=$run_root"
  echo "[0434-suite] initialDomainMode=$INITIAL_DOMAIN_MODE state=$state"
  echo "[0434-suite] liquid(type=$INJECT_TYPE,mass=$INJECT_MASS,q6Alpha=$LIQUID_Q6_STRENGTH) into gas(type=$BACKGROUND_TYPE,mass=$PARTICLE_MASS,q6Alpha=$GAS_Q6_STRENGTH) mass_ratio=$ACTUAL_LIQUID_TO_GAS_MASS_RATIO"
  if suite_path_has_q6_0434 "$mode" && suite_truthy_0434 "$SPECIES_Q6_ENABLE"; then
    echo "[0434-suite] speciesQ6=on mode=$SPECIES_Q6_MODE sensitivity=$SPECIES_Q6_SENSITIVITY fallback=$SPECIES_Q6_FALLBACK_MODE tolerance=$SPECIES_Q6_COMPARISON_TOLERANCE"
  else
    echo "[0434-suite] speciesQ6=off for mode=$mode"
  fi
  echo "[0434-suite] resampling thresholds: Nmin=$GUARD_NMIN Ntarget=$GUARD_NTARGET Nmax=$GUARD_NMAX from gamma=$GAMMA"
  suite_run_binary_0434 "$params" "$log" "$time" "$out"
}

while IFS= read -r mode; do
  [[ -n "$mode" ]] || continue
  run_one_mode_0434 "$mode"
done < <(suite_mode_list_0434)

#!/usr/bin/env bash
set -euo pipefail
# 0414 — first CUDA-resident qualification of segmented open boundaries on x+y.
#
# One case is run at a time (CASE=...), in accordance with the development
# workflow.  The default is the historical right-pressure-outlet control.
#
# Cases:
#   right      left partial inlet -> right full pressure outlet
#              historical x8r/x8s orientation; non-regression anchor.
#   top        bottom partial inlet -> top full pressure outlet
#              exact 90-degree rotation of the boundary topology.
#   left       right partial inlet -> left full pressure outlet
#              exact x-reflection of the historical right case.
#   bottom     top partial inlet -> bottom full pressure outlet
#              exact y-reflection of the rotated top case.
#   left_top   left partial inlet -> top full pressure outlet
#              first genuinely multi-axis inlet/outlet topology.
#   right_top left partial inlet -> right + top full pressure outlets
#              multi-axis outlet corner + exact 2-D separable x8s deflation.
#   left_partial_top left partial inlet -> top partial pressure outlet
#              multi-axis partial x8r; exact x8s deflation must stay disabled.
#
# Physics contract retained from 0493x8q-x8t:
#   * outlet particles use the local kinetic half-space continuation x8q;
#   * predictor normal velocity has zero normal gradient;
#   * pressure correction imposes phi=0 on every Neumann outlet segment;
#   * final outlet flux is NOT prescribed by the nominal segment velocity;
#   * density-relaxation mean centering x8t follows the pressure outlet;
#   * x8s is exact for complete separable pressure faces.
#
# This runner never edits ./livevis_control.kv.  It uses that file as the
# default LiveVis/recording control, as required by the project conventions.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE="${CASE:-right}"
MODE="${MODE:-src-q6-g-f}"
[[ "$MODE" == "src-q6-g-f" ]] || {
  echo "[0414] ERROR first qualification is restricted to MODE=src-q6-g-f" >&2
  exit 2
}

CASE_LABEL="0414_segmented_xy_neumann_${CASE}"
GEN_CASE="io_box"
TOPOLOGY="segmented"

# Square box: right/top cases are direct x<->y rotations at the continuum and
# discrete operator levels.  The initial particle realization is statistically
# equivalent; field-level rotated comparisons belong to the analysis stage.
Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
NX="${NX:-128}"
NY="${NY:-128}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

U0="${U0:-0.0}"
VELOCITY_MODE="${VELOCITY_MODE:-zero}"
SEED="${SEED:-414001}"
UIN="${UIN:-0.12}"
# Metadata only for x8r Neumann outlets.  The projected final flux is determined
# by the interior solution and phi=0, never by this value.
UOUT_NOMINAL="${UOUT_NOMINAL:-0.0}"
INLET_SMIN="${INLET_SMIN:-0.20}"
INLET_SMAX="${INLET_SMAX:-0.80}"
INLET_PROFILE="${INLET_PROFILE:-poiseuille_y_max}"
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-4}"
INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-1.0}"
OUTLET_MODE="neumann"

THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-2500}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
# 0414d conditioning-only ablation.  true is the production/default path.
Q6_PRESSURE_OUTLET_DEFLATION_ENABLE="${Q6_PRESSURE_OUTLET_DEFLATION_ENABLE:-true}"
Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
Q6_GF_SPECIES_DIAGNOSTICS_ENABLE=false
Q6_GF_EXTERNAL_SPECIES=0
Q6_GF_HAS_GAS_PHASE=0

SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-1.0}"

STEPS="${STEPS:-1200}"
SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0414_segmented_xy_neumann}"
RUN_ROOT="$BASE_RUN_ROOT/$CASE"
RESTART_STATE="${RESTART_STATE:-}"
if [[ -n "$RESTART_STATE" ]]; then
  CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-0}"
else
  CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
fi
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
THREADS="${THREADS:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

# Project convention: LiveVis is on for development runs and the repository
# control file is authoritative.  Do not call suite_prepare_livevis_control_0434.
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-$ROOT/livevis_control.kv}"
OVERWRITE_LIVEVIS_CONTROL=0
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_SESSION_PREFIX="${RECORD_SESSION_PREFIX:-0414_segmented_xy_${CASE}}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-100}"
RECORD_STRIDE="${RECORD_STRIDE:-1}"

suite_defaults_common_0434
suite_compute_derived_0434

# Case-specific segment records.  x-face normal velocity is ux; y-face normal
# velocity is uy.  The local Poiseuille law is applied in the segment-local
# tangent coordinate for either orientation by the resident 0493x8k path.
SEGMENT_COUNT=0
SEGMENT_0=""
SEGMENT_1=""
SEGMENT_2=""
case "$CASE" in
  right)
    SEGMENT_COUNT=2
    SEGMENT_0="left inlet ${INLET_SMIN} ${INLET_SMAX} ${UIN} 0.0 0 ${PARTICLE_MASS}"
    SEGMENT_1="right outlet 0.0 1.0 ${UOUT_NOMINAL} 0.0 0 ${PARTICLE_MASS}"
    ;;
  top)
    SEGMENT_COUNT=2
    SEGMENT_0="bottom inlet ${INLET_SMIN} ${INLET_SMAX} 0.0 ${UIN} 0 ${PARTICLE_MASS}"
    SEGMENT_1="top outlet 0.0 1.0 0.0 ${UOUT_NOMINAL} 0 ${PARTICLE_MASS}"
    ;;
  left)
    SEGMENT_COUNT=2
    SEGMENT_0="right inlet ${INLET_SMIN} ${INLET_SMAX} -${UIN} 0.0 0 ${PARTICLE_MASS}"
    SEGMENT_1="left outlet 0.0 1.0 ${UOUT_NOMINAL} 0.0 0 ${PARTICLE_MASS}"
    ;;
  bottom)
    SEGMENT_COUNT=2
    SEGMENT_0="top inlet ${INLET_SMIN} ${INLET_SMAX} 0.0 -${UIN} 0 ${PARTICLE_MASS}"
    SEGMENT_1="bottom outlet 0.0 1.0 0.0 ${UOUT_NOMINAL} 0 ${PARTICLE_MASS}"
    ;;
  left_top)
    SEGMENT_COUNT=2
    SEGMENT_0="left inlet ${INLET_SMIN} ${INLET_SMAX} ${UIN} 0.0 0 ${PARTICLE_MASS}"
    SEGMENT_1="top outlet 0.0 1.0 0.0 ${UOUT_NOMINAL} 0 ${PARTICLE_MASS}"
    ;;
  right_top)
    SEGMENT_COUNT=3
    SEGMENT_0="left inlet ${INLET_SMIN} ${INLET_SMAX} ${UIN} 0.0 0 ${PARTICLE_MASS}"
    SEGMENT_1="right outlet 0.0 1.0 ${UOUT_NOMINAL} 0.0 0 ${PARTICLE_MASS}"
    SEGMENT_2="top outlet 0.0 1.0 0.0 ${UOUT_NOMINAL} 0 ${PARTICLE_MASS}"
    ;;
  left_partial_top)
    SEGMENT_COUNT=2
    SEGMENT_0="left inlet ${INLET_SMIN} ${INLET_SMAX} ${UIN} 0.0 0 ${PARTICLE_MASS}"
    SEGMENT_1="top outlet ${INLET_SMIN} ${INLET_SMAX} 0.0 ${UOUT_NOMINAL} 0 ${PARTICLE_MASS}"
    ;;
  *)
    echo "[0414] ERROR CASE must be right, top, left, bottom, left_top, right_top, or left_partial_top (got '$CASE')" >&2
    exit 2
    ;;
esac

# Keep the qualification geometry away from the newly forbidden hard-reservoir
# overlap class.  These first cases contain only one inlet reservoir.
python3 - "$CASE" "$INLET_SMIN" "$INLET_SMAX" "$INLET_RESERVOIR_CELLS" "$NX" "$NY" <<'PY'
import sys
case,s0,s1,nr,nx,ny=sys.argv[1:]
s0=float(s0); s1=float(s1); nr=int(nr); nx=int(nx); ny=int(ny)
if not (0.0 <= s0 < s1 <= 1.0):
    raise SystemExit("[0414-preflight] ERROR invalid inlet segment")
if nr <= 0:
    raise SystemExit("[0414-preflight] ERROR inletReservoirCells must be positive")
print("===== 0414 SEGMENTED X/Y NEUMANN PREFLIGHT =====")
print(f"case={case} grid={nx}x{ny} inlet=[{s0:g},{s1:g}] reservoirCells={nr}")
print("outlet=0493x8q kinetic continuation + x8r phi=0 pressure outlet")
if case == "right":
    print("x8s=historical exact 3-mode right/full-face anchor")
elif case == "top":
    print("x8s=exact 90-degree rotated 3-mode top/full-face")
elif case == "left":
    print("x8s=exact x-reflected 3-mode left/full-face")
elif case == "bottom":
    print("x8s=exact y-reflected 3-mode bottom/full-face")
elif case == "left_top":
    print("multiAxis=yes; x8s=exact top/full-face 3-mode; chronological crossing active")
elif case == "right_top":
    print("multiAxis=yes; outletCorner=right+top; x8s=exact separable 2-D low-mode deflation")
else:
    print("multiAxis=yes; partialOutlet=top; x8r=local phi=0 on open cells; x8s=disabled (nonseparable partial face)")
PY

write_params_0414() {
  local state=$1 out=$2 params=$3
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
openBoundarySegmentCount = $SEGMENT_COUNT
PARAMS
  local k name seg
  for ((k=0; k<SEGMENT_COUNT; ++k)); do
    name="SEGMENT_${k}"
    seg="${!name}"
    printf 'openBoundarySegment%d = %s\n' "$k" "$seg" >> "$params"
  done
  cat >> "$params" <<PARAMS

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.0
inletVelocityRampInitialFactor = 1.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = ${INLET_PROFILE}

inletKBT = ${KBT}
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
q6PressureOutletDeflationEnable = ${Q6_PRESSURE_OUTLET_DEFLATION_ENABLE}
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = ${PARTICLE_MASS}
wallKBT = -1.0
wallThermalNoise = 0.0
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = 0.0
wallUyTop = 0.0
PARAMS
  suite_write_common_params_0434 "$MODE" >> "$params"
}

suite_validate_path_0434 "$MODE"
suite_prepare_dirs_0434 "$RUN_ROOT"

STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
if [[ -n "$RESTART_STATE" ]]; then
  [[ -f "$RESTART_STATE" ]] || {
    echo "[0414] ERROR RESTART_STATE not found: $RESTART_STATE" >&2
    exit 2
  }
  STATE="$RESTART_STATE"
  echo "[0414] RESTART from $STATE"
else
  suite_generate_case_0434 "$STATE"
fi

PARAMS_FILE="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"
write_params_0414 "$STATE" "$OUT" "$PARAMS_FILE"

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"
export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
export MPCD_INTERNAL_PROFILES="${MPCD_INTERNAL_PROFILES:-0}"
export MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0

if suite_truthy_0434 "$LIVE_VIS_ENABLE"; then
  [[ -f "$LIVE_VIS_CONTROL_FILE" ]] || {
    echo "[0414] ERROR LiveVis control missing: $LIVE_VIS_CONTROL_FILE" >&2
    echo "[0414] The runner intentionally does not create or modify ./livevis_control.kv." >&2
    exit 2
  }
fi
# Keep the filtered-field recorder cadence explicit without touching the
# repository LiveVis control file.  The control file remains authoritative if
# it contains an explicit runtime override.
export SRC_FILTERED_FIELD_RECORD_EVERY="$RECORD_EVERY"
export MPCD_FILTERED_FIELD_RECORD_EVERY="$RECORD_EVERY"
export SRC_FILTERED_FIELD_RECORD_FIELDS="$RECORD_FIELDS"
export MPCD_FILTERED_FIELD_RECORD_FIELDS="$RECORD_FIELDS"

suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0414.env" "$MODE"
cat >> "$RUN_ROOT/logs/environment_0414.env" <<META
PATCH_0414_CASE=${CASE}
PATCH_0414_SEGMENT_COUNT=${SEGMENT_COUNT}
PATCH_0414_SEGMENT_0=${SEGMENT_0}
PATCH_0414_SEGMENT_1=${SEGMENT_1}
PATCH_0414_SEGMENT_2=${SEGMENT_2}
PATCH_0414_NEUMANN=x8q_kinetic+x8r_pressure_phi0+x8t_density_target_centering
PATCH_0414_X8S=exact_separable_low_modes
PATCH_0414_X8S_ENABLE=${Q6_PRESSURE_OUTLET_DEFLATION_ENABLE}
PATCH_0414_CROSSING=chronological_first_intersection_for_multi_axis
PATCH_0414_LIVEVIS_CONTROL=${LIVE_VIS_CONTROL_FILE}
PATCH_0414_RECORD_EVERY_REQUEST=${RECORD_EVERY}
META

echo
echo "===== 0414 RUN case=$CASE mode=$MODE ====="
echo "[0414] root=$RUN_ROOT steps=$STEPS dt=$DT seed=$SEED"
echo "[0414] segments:"
for ((k=0; k<SEGMENT_COUNT; ++k)); do
  name="SEGMENT_${k}"; echo "  $k: ${!name}"
done
echo "[0414] CUDA resident x7j required; host fallback forbidden for generalized outlet orientations"
echo "[0414] x8s pressure-outlet deflation enable=$Q6_PRESSURE_OUTLET_DEFLATION_ENABLE"
echo "[0414] LiveVis control=$LIVE_VIS_CONTROL_FILE (read-only by this runner)"
echo "[0414] dumpStateEvery=$DUMP_STATE_EVERY requestedRecordEvery=$RECORD_EVERY"

suite_run_binary_0434 "$PARAMS_FILE" "$LOG" "$TIME_FILE" "$OUT"

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo
  echo "===== 0414 COMPLETE case=$CASE ====="
  echo "output=$OUT"
  echo "log=$LOG"
  echo "time=$(cat "$TIME_FILE" 2>/dev/null || true)"
  echo "status=COMPLETE"
fi

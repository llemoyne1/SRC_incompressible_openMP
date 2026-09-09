#!/usr/bin/env bash
set -euo pipefail
# 0493x8k — segmented local-Poiseuille inlet qualification.
#
# First validation of 0493x8k:
#   * modes: SRC and Q6-G-F only;
#   * partial-height inlet [0.20,0.80] to prove that the Poiseuille coordinate
#     is LOCAL to the segment, not to the whole domain;
#   * poiseuille_y_max with UMAX=0.18 -> segment-mean normal velocity = 0.12;
#   * hard_cell_density remains uniform in population;
#   * right outlet remains the pre-x8k segmented outlet implementation.
#
# IMPORTANT:
#   UOUT=0.12 is only a temporary Q6-G-F flux-balance bridge:
#       Q_in = (2/3 UMAX) * segment_height
#       Q_out = UOUT        * segment_height
#   This is NOT the final Zovatto Neumann outlet.  That is the next patch.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="0493x8k_segmented_local_poiseuille"
GEN_CASE="io_box"
TOPOLOGY="segmented"
RUN_MODES="${RUN_MODES:-src src-q6-g-f}"

# Small but non-pathological qualification box.
Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
NX="${NX:-96}"
NY="${NY:-96}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

# Start from a filled, zero-mean box.  The inlet itself supplies the flow.
U0="${U0:-0.0}"
VELOCITY_MODE="${VELOCITY_MODE:-zero}"
SEED="${SEED:-493910}"

# Deliberately PARTIAL opening: local-profile semantics are observable here.
INLET_FACE="${INLET_FACE:-left}"
INLET_SMIN="${INLET_SMIN:-0.20}"
INLET_SMAX="${INLET_SMAX:-0.80}"
OUTLET_FACE="${OUTLET_FACE:-right}"
OUTLET_SMIN="${OUTLET_SMIN:-$INLET_SMIN}"
OUTLET_SMAX="${OUTLET_SMAX:-$INLET_SMAX}"

INLET_PROFILE="${INLET_PROFILE:-poiseuille_y_max}"
UIN="${UIN:-0.18}"

# Temporary bridge until the Zovatto Neumann patch.
UOUT="${UOUT:-0.12}"
OUTLET_MODE="${OUTLET_MODE:-neumann}"
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-4}"

THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1000}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
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

STEPS="${STEPS:-120}"
SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000000}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x8k_segmented_local_poiseuille}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
THREADS="${THREADS:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

# No heavy visual/recording diagnostics for this first qualification.
LIVE_VIS_ENABLE=0
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false

suite_defaults_common_0434
suite_compute_derived_0434

# Lightweight physical contract only.
python3 - \
  "$INLET_SMIN" "$INLET_SMAX" "$OUTLET_SMIN" "$OUTLET_SMAX" \
  "$UIN" "$UOUT" "$INLET_PROFILE" <<'PY'
import math
import sys

s0, s1, o0, o1, uin, uout, profile = sys.argv[1:]
s0=float(s0); s1=float(s1); o0=float(o0); o1=float(o1)
uin=float(uin); uout=float(uout)

if profile not in ("poiseuille_y_max", "poiseuille_y", "poiseuille_y_mean"):
    raise SystemExit(f"[0493x8k-preflight] ERROR unsupported profile={profile}")
if not (0.0 <= s0 < s1 <= 1.0):
    raise SystemExit("[0493x8k-preflight] ERROR invalid inlet segment")
if not (0.0 <= o0 < o1 <= 1.0):
    raise SystemExit("[0493x8k-preflight] ERROR invalid outlet segment")

if profile == "poiseuille_y_max":
    umean = (2.0/3.0)*uin
    umax = uin
else:
    umean = uin
    umax = 1.5*uin

qin = umean*(s1-s0)
qout = uout*(o1-o0)

print("===== 0493x8k SEGMENTED LOCAL-POISEUILLE PREFLIGHT =====")
print(f"inletSegment=[{s0:g},{s1:g}] profile={profile}")
print("xi=(s-sMin)/(sMax-sMin)")
print(f"Umax={umax:.12g} Umean={umean:.12g}")
print(f"Qin/Lface={qin:.12g}")
print(f"temporaryOutlet=[{o0:g},{o1:g}] Uout={uout:.12g} Qout/Lface={qout:.12g}")
print("outletSemantics=TEMPORARY_BALANCED_FLUX_BRIDGE_NOT_ZOVATTO_NEUMANN")

if not math.isclose(qin, qout, rel_tol=1e-12, abs_tol=1e-14):
    raise SystemExit(
        f"[0493x8k-preflight] ERROR temporary flux mismatch Qin={qin} Qout={qout}"
    )
PY

write_params_0493x8k() {
  local mode=$1 state=$2 out=$3 params=$4
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
openBoundarySegment0 = ${INLET_FACE} inlet ${INLET_SMIN} ${INLET_SMAX} ${UIN} 0.0 0 ${PARTICLE_MASS}
openBoundarySegment1 = ${OUTLET_FACE} outlet ${OUTLET_SMIN} ${OUTLET_SMAX} ${UOUT} 0.0 0 ${PARTICLE_MASS}

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.0
inletVelocityRampInitialFactor = 1.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = ${INLET_PROFILE}

inletKBT = ${KBT}
inletThermalNoise = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = ${INLET_RESERVOIR_CELLS}
inletTargetOccupancy = ${GAMMA}
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = false
inletReinjectBackflow = true

openBoundaryOutletMode = ${OUTLET_MODE}
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
  suite_write_common_params_0434 "$mode" >> "$params"
}

run_one_0493x8k() {
  local mode=$1
  suite_validate_path_0434 "$mode"

  local run_root="$BASE_RUN_ROOT/$mode"
  suite_prepare_dirs_0434 "$run_root"

  local state="$run_root/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
  local params="$run_root/params/${CASE_LABEL}.kv"
  local out="$run_root/output"
  local log="$run_root/logs/${CASE_LABEL}.log"
  local time_file="$run_root/logs/${CASE_LABEL}.time"
  mkdir -p "$out"

  suite_generate_case_0434 "$state"
  write_params_0493x8k "$mode" "$state" "$out" "$params"

  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"

  if suite_path_has_q6_g_f_0493x7h "$mode"; then
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
    export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  else
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=0
  fi

  export MPCD_INTERNAL_PROFILES="${MPCD_INTERNAL_PROFILES:-0}"
  export MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0

  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0493x8k.env" "$mode"

  cat >> "$run_root/logs/environment_0493x8k.env" <<META
X8K_PROFILE=${INLET_PROFILE}
X8K_INLET=${INLET_FACE}:${INLET_SMIN}:${INLET_SMAX}:${UIN}
X8K_OUTLET_TEMPORARY=${OUTLET_FACE}:${OUTLET_SMIN}:${OUTLET_SMAX}:${UOUT}:${OUTLET_MODE}
META

  echo
  echo "===== 0493x8k RUN mode=$mode ====="
  echo "[0493x8k] inlet=$INLET_FACE[$INLET_SMIN,$INLET_SMAX] profile=$INLET_PROFILE Uarg=$UIN"
  echo "[0493x8k] expected inlet segment mean U=0.12 for default poiseuille_y_max/UIN=0.18"
  echo "[0493x8k] temporary outlet=$OUTLET_FACE[$OUTLET_SMIN,$OUTLET_SMAX] U=$UOUT mode=$OUTLET_MODE"
  echo "[0493x8k] NOTE outlet is NOT yet Zovatto Neumann"

  suite_run_binary_0434 "$params" "$log" "$time_file" "$out"

  if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
    echo "[0493x8k] COMPLETE mode=$mode"
    echo "[0493x8k] log=$log"
    echo "[0493x8k] output=$out"
    echo "[0493x8k] time=$(cat "$time_file" 2>/dev/null || true)"
  fi
}

for mode in $RUN_MODES; do
  run_one_0493x8k "$mode"
done

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo
  echo "===== 0493x8k COMPLETE ====="
  echo "Expected default local profile:"
  echo "  xi=(s-0.20)/0.60"
  echo "  un=4*0.18*xi*(1-xi)"
  echo "  Umax=0.18 at segment midpoint"
  echo "  Umean=0.12 over the open segment"
  echo "Modes completed: $RUN_MODES"
  echo "Next step after validation: Zovatto-compatible segmented Neumann outlet."
fi

#!/usr/bin/env bash
set -euo pipefail
cd "${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"

# 0493x10x: isolate the effect of x10o thermal-envelope coefficient C.
# Physics is frozen to the qualified x10v support treatment.  x10w/pairwise is
# explicitly OFF so MPCD_X10O_THERMAL_SIGMAS changes only x10o wall thickness.
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0

# Freeze the physical case.  Only C varies.
export SIGMA_ACTIVE="${SIGMA_ACTIVE:-3000}"
export CONTACT_ANGLE_DEG="${CONTACT_ANGLE_DEG:--1}"
export KBT="${KBT:-0.125}"
export DT="${DT:-0.002}"
export LIQUID_MASS="${LIQUID_MASS:-1.0}"
export GAMMA="${GAMMA:-20}"
export NX="${NX:-800}"
export NY="${NY:-400}"
export Lx="${Lx:-3.125}"
export Ly="${Ly:-1.5625}"
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_MAX_CELLS="${MPCD_X10O_THERMAL_MAX_CELLS:-0.75}"
export SEED="${SEED:-493952}"
export STEPS="${STEPS:-1000}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-250}"

# Cost-oriented qualification settings: no GUI/recording.  The inherited x10o
# crossing CSV remains available for wall-thickness/intervention checks.
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE=0
export LIVE_VIS_EVERY=100
export LIVE_VIS_RECORD_ENABLE=0
export LIVE_VIS_RECORD_EVERY=100
export LIVE_VIS_RECORD_FIELDS=mass
export FILTER_SAMPLE_EVERY=100
export FILTERED_RECORDING_ENABLE=0
export LIVE_VIS_HOLD_ON_EXIT=0
export OVERWRITE_LIVEVIS_CONTROL=1

PHASE="${PHASE:-screen}"
SKIP_DONE="${SKIP_DONE:-1}"
SCREEN_C_VALUES="${SCREEN_C_VALUES:-0 0.5 1 2 3 4.2}"
CONTROL_C_VALUES="${CONTROL_C_VALUES:-0 1 2 3 4.2}"

case "$PHASE" in
  screen|control|full) ;;
  *) echo "[0493x10x] ERROR PHASE must be screen, control, or full" >&2; exit 2 ;;
esac

printf '[0493x10x] PHASE=%s steps=%s kBT=%s dt=%s m=%s sigma=%s maxCells=%s\n' \
  "$PHASE" "$STEPS" "$KBT" "$DT" "$LIQUID_MASS" "$SIGMA_ACTIVE" "$MPCD_X10O_THERMAL_MAX_CELLS"
python3 - "$DT" "$KBT" "$LIQUID_MASS" "$MPCD_X10O_THERMAL_MAX_CELLS" "$Lx" "$Ly" "$NX" "$NY" <<'PYI'
import math, sys
dt,kbt,m,maxc,Lx,Ly=map(float,sys.argv[1:7]); nx,ny=map(int,sys.argv[7:9])
h=min(Lx/nx,Ly/ny)
step=dt*math.sqrt(kbt/m)
ccap=maxc*h/step if step>0 else float('inf')
print(f'[0493x10x] thermalStep={step:.12g} h={h:.12g} Ccap={ccap:.9g}')
print('[0493x10x] expected delta/h before cap: C*thermalStep/h')
PYI

tag_float() {
  local x="$1"
  x="${x//-/m}"
  x="${x//./p}"
  printf '%s' "$x"
}

run_case() {
  local R="$1" C="$2" g="$3"
  local ctag gtag root final_state
  ctag="$(tag_float "$C")"
  gtag="$(tag_float "$g")"
  root="runs/0493x10x_C${ctag}_R${R}_g${gtag}"
  final_state=$(printf '%s/output/state_step_%08d.smpcd' "$root" "$STEPS")

  if [[ "$SKIP_DONE" == 1 && -f "$final_state" && -f "$root/output/summary_runtime.csv" ]]; then
    echo "[0493x10x] SKIP complete C=$C R=$R g=$g root=$root"
    return 0
  fi

  echo
  echo "===== 0493x10x C=$C R=$R g=$g ====="
  MPCD_X10O_THERMAL_SIGMAS="$C" \
  RUN_ROOT="$root" \
  DROP_RADIUS_CELLS="$R" \
  GRAVITY_Y="$g" \
  CLEAN_RUN_ROOT=1 \
  bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh
}

run_pair() {
  local R="$1" C="$2"
  run_case "$R" "$C" 0
  run_case "$R" "$C" -0.1
}

if [[ "$PHASE" == screen || "$PHASE" == full ]]; then
  echo "===== 0493x10x SCREEN: R8 ====="
  for C in $SCREEN_C_VALUES; do run_pair 8 "$C"; done
fi

if [[ "$PHASE" == control || "$PHASE" == full ]]; then
  echo "===== 0493x10x CONTROL: R40 ====="
  for C in $CONTROL_C_VALUES; do run_pair 40 "$C"; done
fi

echo
echo "===== 0493x10x SWEEP COMPLETE ====="
python3 scripts/analyze_0493x10x_thermal_sigmas_sweep.py || true

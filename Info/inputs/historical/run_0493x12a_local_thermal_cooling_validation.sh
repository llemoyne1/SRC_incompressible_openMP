#!/usr/bin/env bash
set -euo pipefail
cd "${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"

case_name="${1:-r8}"

# Qualified x10v baseline; x10w remains explicitly off.
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0

# x12a local thermal law.
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

# Visual review is part of the physical qualification. Recording remains off
# so LIVE_VIS_EVERY=1 does not also create a heavy disk-I/O path.
export LIVE_PROGRESS=1
export LIVE_VIS_ENABLE=1
export LIVE_VIS_EVERY=1
export LIVE_VIS_RECORD_ENABLE=0
export FILTERED_RECORDING_ENABLE=0
export LIVE_VIS_HOLD_ON_EXIT=1

case "$case_name" in
  r40-smoke)
    echo "===== 0493x12a R40 RESOLVED NO-COOLING SMOKE ====="
    echo "expected: Lloc~40h > Rc => effective thermostat target remains ~0.125"
    RUN_ROOT="runs/0493x12a_R40_resolved_smoke" \
    DROP_RADIUS_CELLS=40 \
    KBT=0.125 \
    GRAVITY_Y=0 \
    SIGMA_ACTIVE=4500 \
    SURFACE_TENSION_MIN_RADIUS_CELLS=3 \
    SEED=493952 \
    STEPS="${SMOKE_STEPS:-100}" \
    SUMMARY_EVERY=25 \
    DUMP_STATE_EVERY=100 \
    bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh
    ;;

  r8)
    echo "===== 0493x12a R8 HOT->LOCAL-COOLED QUALIFICATION ====="
    echo "expected: fT=(8/(8*sqrt(10)))^2=0.1 => kBT_eff~0.0125"
    RUN_ROOT="runs/0493x12a_R8_kBT0.125_localcool_g0" \
    DROP_RADIUS_CELLS=8 \
    KBT=0.125 \
    GRAVITY_Y=0 \
    SIGMA_ACTIVE=3000 \
    SURFACE_TENSION_MIN_RADIUS_CELLS=3 \
    SEED=493952 \
    STEPS="${R8_STEPS:-1000}" \
    SUMMARY_EVERY=100 \
    DUMP_STATE_EVERY=100 \
    bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh
    ;;

  dripping)
    echo "===== 0493x12a DRIPPING VISUAL QUALIFICATION ====="
    echo "goal: cool thin neck/filament progressively without any Drop role yet"
    RUN_ROOT="runs/0493x12a_dripping_s2500_g01_u01" \
    KBT=0.125 \
    DT=0.002 \
    SIGMA_ACTIVE=2500 \
    GRAVITY_Y=-0.1 \
    UIN=0.1 \
    SEED=493940 \
    CASES=capillary \
    STEPS="${DRIP_STEPS:-10000}" \
    SUMMARY_EVERY=100 \
    DUMP_STATE_EVERY=1000 \
    CLEAN_RUN_ROOT=1 \
    bash scripts/run_0493x10o_q6_thermal_interface_dripping.sh
    ;;

  *)
    echo "usage: $0 {r40-smoke|r8|dripping}" >&2
    exit 2
    ;;
esac

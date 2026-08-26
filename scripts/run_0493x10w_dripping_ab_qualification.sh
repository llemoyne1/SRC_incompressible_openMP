#!/usr/bin/env bash
set -euo pipefail
cd "${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"

export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
export MPCD_X10W_THERMAL_PHASE_CHI_ON=0.022
export MPCD_X10W_THERMAL_PHASE_CHI_FULL=0.028
export MPCD_X10W_THERMAL_PHASE_ETA_CAP=0.05724334

# Historical best-dripping physical parameters.
export KBT=0.125
export DT=0.002
export SIGMA_ACTIVE=2500
export GRAVITY_Y=-0.1
export UIN=0.1
export SEED=493940
export CASES=capillary
export STEPS="${DRIP_STEPS:-50000}"
export SUMMARY_EVERY=100
export DUMP_STATE_EVERY=1000
export CLEAN_RUN_ROOT=1
export LIVE_PROGRESS=1
export LIVE_VIS_ENABLE=1
export LIVE_VIS_EVERY=100
export LIVE_VIS_RECORD_ENABLE=1
export LIVE_VIS_RECORD_EVERY=100
export LIVE_VIS_RECORD_FIELDS=mass
export FILTER_SAMPLE_EVERY=100
export FILTERED_RECORDING_ENABLE=0
export LIVE_VIS_HOLD_ON_EXIT=1

run_drip() {
    local tag="$1" limiter="$2"
    echo
    echo "===== 0493x10w DRIPPING A/B $tag limiter=$limiter ====="
    MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER="$limiter" \
    RUN_ROOT="runs/0493x10w_dripping_${tag}_s2500_g01_u01" \
    bash scripts/run_0493x10o_q6_thermal_interface_dripping.sh
}

# Same x10v physics, only x10w toggled.
run_drip x10v_baseline 0
run_drip x10w_limiter 1

echo
echo "===== 0493x10w DRIPPING A/B COMPLETE ====="

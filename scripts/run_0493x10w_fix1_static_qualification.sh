#!/usr/bin/env bash
set -euo pipefail
cd "${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"

# 0493x10w-fix1 qualification: same x10w law, exact-neutral + shallow-overlap consistency.
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0

# Freeze the offline-qualified law for this campaign.
export MPCD_X10W_THERMAL_PHASE_CHI_ON=0.022
export MPCD_X10W_THERMAL_PHASE_CHI_FULL=0.028
export MPCD_X10W_THERMAL_PHASE_ETA_CAP=0.05724334

export SIGMA_ACTIVE=3000
export CONTACT_ANGLE_DEG=-1
export SEED=493952
export SUMMARY_EVERY=100
export DUMP_STATE_EVERY=250
export LIVE_PROGRESS=1
export LIVE_VIS_ENABLE=0
export LIVE_VIS_EVERY=100
export LIVE_VIS_RECORD_ENABLE=0
export LIVE_VIS_RECORD_EVERY=100
export LIVE_VIS_RECORD_FIELDS=mass
export FILTER_SAMPLE_EVERY=100
export FILTERED_RECORDING_ENABLE=0
export LIVE_VIS_HOLD_ON_EXIT=0

run_case() {
    local tag="$1" R="$2" kbt="$3" g="$4" steps="$5"
    echo
    echo "===== 0493x10w-fix1 QUALIFY $tag R=$R kBT=$kbt g=$g steps=$steps ====="
    RUN_ROOT="runs/0493x10w_fix1_${tag}_R${R}_kBT${kbt}_g${g//-/m}" \
    DROP_RADIUS_CELLS="$R" \
    KBT="$kbt" \
    GRAVITY_Y="$g" \
    STEPS="$steps" \
    bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh
}

# Compile/runtime smoke. Stops campaign immediately on failure.
run_case smoke 8 0.125 0 20

# Negative controls: eta <= etaCap, so x10w MUST be dynamically inactive,
# including R4 where chi is high. These compare to the existing cold baselines.
run_case cold_control 4 0.0125 -0.1 1000
run_case cold_control 8 0.0125 -0.1 1000

# Main hot qualification. Paired g=0/-0.1 permits clean subtraction of COM drift.
for R in 8 16 20 40; do
    run_case hot_sigma3000 "$R" 0.125 0 1000
    run_case hot_sigma3000 "$R" 0.125 -0.1 1000
done

echo
echo "===== 0493x10w-fix1 STATIC QUALIFICATION COMPLETE ====="

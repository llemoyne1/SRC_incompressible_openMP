#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
cd "$ROOT"

# 0493x12a — overnight paired impact/splash qualification of the capillary
# minimum-radius cutoff.  No source modification and no new diagnostics:
# four existing x9s splash runs, paired minRadiusCells=3 vs 4.
#
# Order deliberately completes the wall pair first, then the puddle pair:
#   wall rmin3 -> wall rmin4 -> puddle rmin3 -> puddle rmin4
#
# Existing x10v + x12a physics is kept identical across the four runs.

CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x12a_splash_minradius_night_s945_v035_fix1}"
NIGHT_STEPS="${NIGHT_STEPS:-20000}"
STATE_EVERY="${STATE_EVERY:-2000}"
CAMPAIGN_RECORD_EVERY="${CAMPAIGN_RECORD_EVERY:-100}"
CAMPAIGN_SUMMARY_EVERY="${CAMPAIGN_SUMMARY_EVERY:-100}"

mkdir -p "$CAMPAIGN_ROOT"
CAMPAIGN_LOG="$CAMPAIGN_ROOT/campaign.log"
STATUS_FILE="$CAMPAIGN_ROOT/status.tsv"

exec > >(tee -a "$CAMPAIGN_LOG") 2>&1

printf "case\ttarget\tminRadiusCells\tstatus\trc\tstart\tend\n" > "$STATUS_FILE"

echo "===== 0493x12a OVERNIGHT IMPACT/SPLASH MIN-RADIUS CAMPAIGN ====="
echo "root=$ROOT"
echo "campaignRoot=$CAMPAIGN_ROOT"
echo "stepsPerCase=$NIGHT_STEPS stateEvery=$STATE_EVERY recordEvery=$CAMPAIGN_RECORD_EVERY"
echo "matrix=wall{3,4},puddle{3,4}"
echo "physics: x10v CIC+Q2 one-for-one swap + x12a local cooling"
echo "impact: R/h=40, vy=-0.35, gravityY=-0.005, sigma=945, kBT=0.125"
echo "recording: mass,ux,uy; filterMode=none; liveEvery=1; holdOnExit=0"
echo "x10 contract: x10o=1 CIC=1 Q2=1 oneForOne=1 swap=1 x12a=1"
echo

# Qualified x10o/x10v kinetic-interface baseline.
# IMPORTANT: x10u/x10v are only active when the x10o Q6 thermal-interface
# primitive itself is active.  The first campaign omitted this activation,
# making quadraticInterface=false and therefore oneForOneRelocation=false.
export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0
export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
export MPCD_X10M_MOVING_INTERFACE_WALL=0
export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
export MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=1

export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0

# Final x12a local cooling law.
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

# Common splash physics: production-like x9t regime, intentionally identical
# between minRadiusCells=3 and 4.
export RUN_MODE=src-q6-g-f
export GAMMA=20
export DT=0.002
export KBT=0.125
export LIQUID_MASS=1.0
export PARTICLE_MASS=1.0

# Exact x10o thermal-envelope parameters used by the qualified static/drop
# runners.
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS=3.0
export MPCD_X10O_THERMAL_MAX_CELLS=0.75
export ROTATION_ANGLE=1.5707963267948966
export RANDOM_ROTATION_SIGN=true
export GRID_SHIFT_ENABLE=true
export THERMOSTAT_ENABLE=true
export THERMOSTAT_MODE=cell_relative_rescale
export THERMOSTAT_EVERY=1
export THERMOSTAT_TARGET_KBT=0.125
export THERMOSTAT_MIN_PARTICLES=3

export SIGMA_ACTIVE=945.0
export KINETIC_REFLECTION_FRACTION=1.0
export EVAPORATION_TARGET_TYPE=-1
export CONTACT_ANGLE_DEG=90.0

export DROP_RADIUS_CELLS=40
export DROP_CENTER_X=1.5625
export DROP_CENTER_Y=1.0
export DROP_VX=0.0
export DROP_VY=-0.35
export GRAVITY_Y=-0.005
export PUDDLE_DEPTH_CELLS=40
export SEED=493950

# Runtime / output cadence.
export STEPS="$NIGHT_STEPS"
export SUMMARY_EVERY="$CAMPAIGN_SUMMARY_EVERY"
export DUMP_STATE_EVERY="$STATE_EVERY"
export DUMP_ROLE_FILTER=fluid
export SUMMARY_ROLE_FILTER=fluid
export CLEAN_RUN_ROOT=1
export LIVE_PROGRESS=1

# Live view remains first-class, but must not hold between unattended cases.
export LIVE_VIS_ENABLE=1
export LIVE_VIS_FIELD=mass
export LIVE_VIS_EVERY=1
export LIVE_VIS_HOLD_ON_EXIT=0

# Keep both the current runtime-control names and the historical x9s recorder
# names coherent.  This is intentional: x9s exports the latter directly while
# src_mpcd_run_common_0434 writes the livevis control file from the former.
export FILTERED_RECORDING_ENABLE=1
export RECORD_ENABLE=true
export RECORD_FIELDS=mass,ux,uy
export RECORD_EVERY="$CAMPAIGN_RECORD_EVERY"
export RECORD_FORMAT=f32
export RECORD_STRIDE=1
export FILTER_MODE=none
export FILTER_TAU=0.0
export FILTER_SAMPLE_EVERY="$CAMPAIGN_RECORD_EVERY"

export FILTERED_RECORD_FIELDS=mass,ux,uy
export FILTERED_RECORD_EVERY="$CAMPAIGN_RECORD_EVERY"
export FILTERED_RECORD_SAMPLE_EVERY="$CAMPAIGN_RECORD_EVERY"

# Aliases used by the x12a validation wrappers / current local convention.
export LIVE_VIS_RECORD_ENABLE=1
export LIVE_VIS_RECORD_FIELDS=mass,ux,uy
export LIVE_VIS_RECORD_EVERY="$CAMPAIGN_RECORD_EVERY"

failures=0

run_case() {
    local target="$1"
    local rmin="$2"
    local label="${target}_rmin${rmin}"
    local start end rc
    local case_root="$CAMPAIGN_ROOT/$label"

    start="$(date -Is)"
    echo
    echo "================================================================"
    echo "START case=$label at $start"
    echo "RUN_ROOT=$case_root"
    echo "TARGET=$target SURFACE_TENSION_MIN_RADIUS_CELLS=$rmin"
    echo "================================================================"

    export TARGET="$target"
    export SURFACE_TENSION_MIN_RADIUS_CELLS="$rmin"
    export RUN_ROOT="$case_root"

    if bash scripts/run_0493x9s_splash.sh; then
        rc=0
        status=PASS
    else
        rc=$?
        status=FAIL
        failures=$((failures + 1))
    fi

    end="$(date -Is)"
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$label" "$target" "$rmin" "$status" "$rc" "$start" "$end" >> "$STATUS_FILE"

    echo "END case=$label status=$status rc=$rc at $end"
}

run_case wall 3
run_case wall 4
run_case puddle 3
run_case puddle 4

echo
echo "===== CAMPAIGN COMPLETE ====="
cat "$STATUS_FILE"
echo "campaignLog=$CAMPAIGN_LOG"
echo "statusFile=$STATUS_FILE"

if (( failures > 0 )); then
    echo "[0493x12a-night] completed with $failures failed case(s)" >&2
    exit 1
fi

echo "[0493x12a-night] 4/4 cases completed"

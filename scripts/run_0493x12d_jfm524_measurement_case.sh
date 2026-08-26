#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
cd "$ROOT"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x12d — JFM 524 measurement case, D=320h, compact-Y production using the existing Darcy/chi
# Brinkman path.  No source modification and no new diagnostics.
#
# Geometry is a 2-D "tape step": a chi=0 solid layer attached to the bottom
# wall and extending from a vertical leading edge to the right boundary.
# Default dimensionless geometry:
#   drop D = 320 h
#   defaults reproduce the 0.07 mm tape and d_obs=2.0 mm article condition:
#     tape height H = 6 h = 0.01875 D (target 0.07/3.7 = 0.018919)
#     obstacle distance d = 173 h = 0.540625 D (target 2.0/3.7 = 0.540541)
#
# This runner matches JFM 524 (2005) geometry/We/Fr as closely as the current
# qualified SRC fluid permits.  Reynolds remains the current-fluid value (~649),
# not the experimental Re=12200; that mismatch is explicit in the campaign manifest.
#
# IMPORTANT compatibility choice:
#   darcyChiCollisionVpEnable=false
# The current x9m contact-angle closure explicitly rejects simultaneous
# domain-wall + chi-wall geometry.  The present run therefore tests the
# Darcy/chi Brinkman obstacle + Q6-G-F + x10v + x12a path, while retaining the
# qualified x9m contact angle on the physical bottom wall.  It does NOT yet
# claim chi-obstacle wetting/contact-angle equivalence.

CASE_LABEL="0493x12d_jfm524_measurement_case"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"
TOPOLOGY=closed_box

CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x12d_jfm524_measurement_case}"
CASES="${CASES:-rmin4}"

NX="${NX:-3200}"
NY="${NY:-1024}"
Lx="${Lx:-12.5}"
Ly="${Ly:-4.0}"
# Keep h=1/256 exactly while removing unused vertical vacuum.
# Quantitative JFM measurements need the ejected sheet/filament arc, not only
# the near-wall footprint.  The 3200x1600 reference shows that arc above y=2;
# Ly=4 preserves the useful trajectory while still reducing the old vertical grid.
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
PARTICLE_MASS="$LIQUID_MASS"

# Keep the common Q6-G-F single-phase registry on the same physical type as
# the splash state.  suite_write_common_params_0434 appends its own species0
# declaration when Q6_GF_EXTERNAL_SPECIES=0, using BACKGROUND_TYPE.
BACKGROUND_TYPE="$LIQUID_TYPE"
INACTIVE_TYPE="$LIQUID_TYPE"

SIGMA_ACTIVE="${SIGMA_ACTIVE:-392.149185}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
CONTACT_ANGLE_DEG="${CONTACT_ANGLE_DEG:-90.0}"
KINETIC_REFLECTION_FRACTION="${KINETIC_REFLECTION_FRACTION:-1.0}"
EVAPORATION_TARGET_TYPE=-1

DROP_RADIUS_CELLS="${DROP_RADIUS_CELLS:-160}"
DROP_CENTER_X="${DROP_CENTER_X:-6.25}"
DROP_CENTER_Y="${DROP_CENTER_Y:-0.703125}"
# 20h initial bottom clearance; DROP_VY is chosen so |Vy| ~= 0.35 at first wall contact under GRAVITY_Y.
DROP_VX="${DROP_VX:-0.0}"
DROP_VY="${DROP_VY:--0.3499190531394368}"
GRAVITY_Y="${GRAVITY_Y:--0.0003626}"
SEED="${SEED:-493950}"

# Tape-step geometry in grid cells.
OBSTACLE_HEIGHT_CELLS="${OBSTACLE_HEIGHT_CELLS:-6}"
OBSTACLE_DISTANCE_CELLS="${OBSTACLE_DISTANCE_CELLS:-173}"

# Darcy/chi "solid" obstacle.  alpha*dt is intentionally deep in the stiff
# lambda->1 regime; mean_outward_bath is the existing wall-like Darcy mode.
ALPHA="${ALPHA:-800000.0}"
ALPHA_MIN="${ALPHA_MIN:-0.0}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_USOLID_X=0.0
DARCY_USOLID_Y=0.0
DARCY_BRINKMAN_FORCING_MODE="${DARCY_BRINKMAN_FORCING_MODE:-mean_outward_bath}"
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=-1
DARCY_CHI_COLLISION_VP_ENABLE=false
DARCY_CHI_COLLISION_VP_MODE=interface_band
DARCY_CHI_COLLISION_VP_GAMMA="$GAMMA"
DARCY_CHI_COLLISION_VP_MASS="$LIQUID_MASS"
DARCY_CHI_COLLISION_VP_LAYERS=1
DARCY_CHI_COLLISION_VP_THRESHOLD=0.5
DARCY_CHI_COLLISION_VP_STRENGTH=0.0
DARCY_THREADS_PER_BLOCK=256
DARCY_COST_EVERY="${DARCY_COST_EVERY:-100}"

TOPO_BENCHMARK_ENABLE=true
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-100}"
TOPO_BENCHMARK_FILENAME=topo_benchmark_0348.csv
TOPO_BENCHMARK_FORCE_ENABLE=true
TOPO_BENCHMARK_DRAG_LIFT_ENABLE=true
TOPO_BENCHMARK_FLOW_DIR_X=1.0
TOPO_BENCHMARK_FLOW_DIR_Y=0.0
TOPO_BENCHMARK_LIFT_DIR_X=0.0
TOPO_BENCHMARK_LIFT_DIR_Y=1.0

STEPS="${STEPS:-3000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-500}"
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
LIVE_PROGRESS=1
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

# Compact live view + high-cadence recording for the JFM measurements.
# 800x256 is an exact 4x downsample of the 3200x1024 physical grid.
LIVE_VIS_ENABLE=1
LIVE_VIS_FIELD=mass
LIVE_VIS_EVERY=1
LIVE_VIS_COLORMAP=blue_red
LIVE_VIS_CLIP=-1
LIVE_VIS_GAIN=1.0
LIVE_VIS_SMOOTH_PASSES=0
LIVE_VIS_NX="${LIVE_VIS_NX:-800}"
LIVE_VIS_NY="${LIVE_VIS_NY:-256}"
LIVE_VIS_HOLD_ON_EXIT=0
PARTICLE_TYPE_FILTER="$LIQUID_TYPE"

FILTERED_RECORDING_ENABLE=1
RECORD_ENABLE=true
RECORD_FIELDS=mass,ux,uy
RECORD_FORMAT=f32
RECORD_STRIDE=1
RECORD_EVERY="${RECORD_EVERY:-50}"
FILTER_MODE=none
FILTER_TAU=0.0
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-50}"

# Historical recorder names still consumed directly by x9-era code paths.
FILTERED_RECORD_FIELDS=mass,ux,uy
FILTERED_RECORD_EVERY="$RECORD_EVERY"
FILTERED_RECORD_SAMPLE_EVERY="$FILTER_SAMPLE_EVERY"

# Qualified fluid/Q6 settings, matching the smooth-wall splash campaign.
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"
THERMOSTAT_MIN_PARTICLES=3
ROTATION_ANGLE=1.5707963267948966
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=true

PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=2000
PROJECTION_TOLERANCE=1.0e-5
Q6_PROJECTION_STRENGTH=1.0
Q6_STRICT=1
SPECIES_Q6_MIN_FILL_FRACTION=0.10
Q6_GF_EXTERNAL_SPECIES=0
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_DENSITY_RELAXATION_TIME=0.25
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0
Q6_GF_DENSITY_TRACTION_GAIN=1.0

SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false

# x10v + x12a chain.
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
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS=3.0
export MPCD_X10O_THERMAL_MAX_CELLS=0.75
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

suite_defaults_common_0434
suite_compute_derived_0434

mkdir -p "$CAMPAIGN_ROOT"
CAMPAIGN_LOG="$CAMPAIGN_ROOT/campaign.log"
STATUS_FILE="$CAMPAIGN_ROOT/status.tsv"
exec > >(tee -a "$CAMPAIGN_LOG") 2>&1
printf "case\tminRadiusCells\tstatus\trc\tstart\tend\n" > "$STATUS_FILE"

# Compute h, physical obstacle geometry, and initial-drop radius.
read -r H DROP_RADIUS OBS_H OBS_D OBS_EDGE OBS_EDGE_CELL <<<"$(python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$DROP_RADIUS_CELLS" \
  "$OBSTACLE_HEIGHT_CELLS" "$OBSTACLE_DISTANCE_CELLS" "$DROP_CENTER_X" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2])
nx,ny=int(sys.argv[3]),int(sys.argv[4])
rc=float(sys.argv[5]); hc=int(sys.argv[6]); dc=int(sys.argv[7]); cx=float(sys.argv[8])
dx=lx/nx; dy=ly/ny
if abs(dx-dy) > 1e-12*max(1.0,abs(dx),abs(dy)):
    raise SystemExit("[0493x12a-obstacle] ERROR square cells required")
r=rc*dx
oh=hc*dy
od=dc*dx
edge=cx+od
edge_cell=round(edge/dx)
if hc < 1 or hc >= ny:
    raise SystemExit("[0493x12a-obstacle] ERROR invalid obstacle height")
if not (cx+r+2*dx < edge < lx-2*dx):
    raise SystemExit(
        f"[0493x12a-obstacle] ERROR obstacle edge x={edge:g} must clear initial drop and right boundary")
print(f"{dx:.17g} {r:.17g} {oh:.17g} {od:.17g} {edge:.17g} {edge_cell:d}")
PY
)"

python3 - "$H" "$DROP_RADIUS" "$OBS_H" "$OBS_D" "$ALPHA" "$DT" \
  "$SIGMA_ACTIVE" "$DROP_VY" "$GRAVITY_Y" <<'PY'
import math,sys
h,r,Hobs,d,alpha,dt,sigma,vy,g=map(float,sys.argv[1:])
D=2*r
lam=1-math.exp(-alpha*dt)
print("===== 0493x12a OBSTACLE SPLASH PREFLIGHT =====")
print(f"drop D/h={D/h:.3f} R/h={r/h:.3f}")
print(f"tape-step H/h={Hobs/h:.3f} H/D={Hobs/D:.6f}")
print(f"edge distance d/h={d/h:.3f} d/D={d/D:.6f}")
print(f"Darcy alpha={alpha:.9g} alpha*dt={alpha*dt:.9g} lambdaSolid={lam:.12g}")
print(f"impact sigma={sigma:g} vy0={vy:g} gravityY={g:g}")
print("JFM target: D=3.7mm U=3.3m/s Re=12200 We=514 gD/U^2=0.0037")
print("SRC target: D/h=320 Uimpact=0.35 We=514 Re~648.8; h=1/256")
print("chi convention: 1=fluid, 0=solid; step extends from leading edge to right boundary")
print("compatibility: chiCollisionVP=OFF; physical-bottom x9m contact angle retained")
PY

failures=0

run_case() {
    local label="$1"
    local rmin="$2"
    local case_root="$CAMPAIGN_ROOT/$label"
    local state="$case_root/init/${CASE_LABEL}.smpcd"
    local chi="$case_root/chi/${CASE_LABEL}_chi.f32"
    local params="$case_root/params/${CASE_LABEL}.kv"
    local out="$case_root/output"
    local log="$case_root/logs/${CASE_LABEL}.log"
    local time_file="$case_root/logs/${CASE_LABEL}.time"
    local start end rc status

    start="$(date -Is)"
    echo
    echo "================================================================"
    echo "START case=$label minRadiusCells=$rmin at $start"
    echo "================================================================"

    if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then
        rm -rf "$case_root"
    fi
    mkdir -p "$case_root/init" "$case_root/chi" "$case_root/params" "$out" "$case_root/logs"

    python3 scripts/generate_0493x9s_splash_state.py \
      --output "$state" --target wall --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
      --gamma "$GAMMA" --drop-center-x "$DROP_CENTER_X" --drop-center-y "$DROP_CENTER_Y" \
      --drop-radius "$DROP_RADIUS" --drop-vx "$DROP_VX" --drop-vy "$DROP_VY" \
      --puddle-depth 0 --liquid-type "$LIQUID_TYPE" --liquid-mass "$LIQUID_MASS" \
      --kBT "$KBT" --seed "$SEED"

    # Binary chi step: bottom-attached solid layer for x >= leading edge.
    python3 - "$chi" "$NX" "$NY" "$OBSTACLE_HEIGHT_CELLS" "$OBS_EDGE_CELL" <<'PY_CHI'
import struct,sys
path=sys.argv[1]
nx,ny,hc,edge=int(sys.argv[2]),int(sys.argv[3]),int(sys.argv[4]),int(sys.argv[5])
vals=[1.0]*(nx*ny)
solid=0
for j in range(hc):
    for i in range(max(0,edge),nx):
        vals[j*nx+i]=0.0
        solid += 1
with open(path,"wb") as f:
    f.write(struct.pack(f"<{len(vals)}f",*vals))
print(f"[0493x12a-obstacle-chi] file={path} grid={nx}x{ny} edgeCell={edge} heightCells={hc} solidCells={solid}")
PY_CHI

    local refmass
    refmass="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"

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
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $SIGMA_ACTIVE
surfaceTensionMinRadiusCells = $rmin
phaseInterfaceKineticReflectionFraction = $KINETIC_REFLECTION_FRACTION
phaseInterfaceEvaporationTargetType = $EVAPORATION_TARGET_TYPE
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = vacuum
phaseInterfaceContactAngleDegrees = $CONTACT_ANGLE_DEG
speciesRegistryEnable = true
speciesCount = 1
species0 = $LIQUID_TYPE incompressible_liquid liquid 1.0 1.0 $refmass
species0ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x12a_obstacle.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_FILL_FRACTION
PARAMS

    suite_write_common_params_0434 "$RUN_MODE" >> "$params"
    suite_write_darcy_params_0434 "$chi" "$RUN_MODE" >> "$params"

    suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
    export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
    export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
    export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
    export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
    export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
    export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=1
    export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=0
    export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0

    export SRC_FILTERED_FIELD_RECORD_FIELDS="$FILTERED_RECORD_FIELDS"
    export MPCD_FILTERED_FIELD_RECORD_FIELDS="$FILTERED_RECORD_FIELDS"
    export SRC_FILTERED_FIELD_RECORD_EVERY="$FILTERED_RECORD_EVERY"
    export MPCD_FILTERED_FIELD_RECORD_EVERY="$FILTERED_RECORD_EVERY"
    export SRC_FILTERED_FIELD_SAMPLE_EVERY="$FILTERED_RECORD_SAMPLE_EVERY"
    export MPCD_FILTERED_FIELD_SAMPLE_EVERY="$FILTERED_RECORD_SAMPLE_EVERY"

    BASE_RUN_ROOT="$case_root"
    LIVE_VIS_CONTROL_FILE="$case_root/livevis_control_0493x12a_obstacle.kv"
    RECORD_SESSION_PREFIX="${label}_0493x12a_obstacle"
    suite_prepare_livevis_control_0434 "$case_root" "$RUN_MODE"
    suite_export_livevis_0434
    suite_write_env_file_0434 "$case_root/logs/environment_0493x12a_obstacle.env" "$RUN_MODE"

    echo "[0493x12a-obstacle] run=$label minRadiusCells=$rmin sigma=$SIGMA_ACTIVE"
    echo "[0493x12a-obstacle] chi=$chi edgeX=$OBS_EDGE edgeCell=$OBS_EDGE_CELL H=$OBS_H"
    echo "[0493x12a-obstacle] Darcy alpha=$ALPHA mode=$DARCY_BRINKMAN_FORCING_MODE chiVP=$DARCY_CHI_COLLISION_VP_ENABLE"
    echo "[0493x12a-obstacle] recording every=$FILTERED_RECORD_EVERY fields=$FILTERED_RECORD_FIELDS dumpsEvery=$DUMP_STATE_EVERY"

    if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
        echo "[0493x12a-obstacle] PREFLIGHT_ONLY=1; params and chi generated, simulation skipped"
        rc=0
        status=PREFLIGHT
    else
        if suite_run_binary_0434 "$params" "$log" "$time_file" "$out"; then
            rc=0
            status=PASS
        else
            rc=$?
            status=FAIL
            failures=$((failures+1))
        fi
    fi

    end="$(date -Is)"
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$label" "$rmin" "$status" "$rc" "$start" "$end" >> "$STATUS_FILE"
    echo "END case=$label status=$status rc=$rc at $end"
}

for c in $CASES; do
    case "$c" in
        rmin3) run_case obstacle_rmin3 3 ;;
        rmin4) run_case obstacle_rmin4 4 ;;
        *) echo "[0493x12a-obstacle] ERROR unknown case=$c" >&2; exit 2 ;;
    esac
done

echo
echo "===== 0493x12a OBSTACLE SPLASH COMPLETE ====="
cat "$STATUS_FILE"
echo "campaignLog=$CAMPAIGN_LOG"
echo "statusFile=$STATUS_FILE"

if (( failures > 0 )); then
    echo "[0493x12a-obstacle] completed with $failures failed case(s)" >&2
    exit 1
fi

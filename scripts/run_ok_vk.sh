#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

# run_ok_vk -- compact Zovatto/Pedrizzetti centered-cylinder demonstrator.
# Same transverse geometry and D/h=80 as the qualified benchmark, reduced axial
# extent 4D upstream + 11D downstream so the run_ok stays workstation-sized.
CASE_LABEL="vk_zovatto_re280_reduced"
GEN_CASE="vk"
TOPOLOGY="segmented"
RUN_MODES="${RUN_MODES:-src-q6-g-f}"

# G08-0.72 reference fluid.
Lx="${Lx:-4.6875}"; Ly="${Ly:-1.5625}"; NX="${NX:-1200}"; NY="${NY:-400}"
GAMMA="${GAMMA:-8}"; DT="${DT:-0.0063471328149122585}"; KBT="${KBT:-0.125}"; STEPS="${STEPS:-12000}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
REFERENCE_NU="${REFERENCE_NU:-0.00056029}"
REFERENCE_CS="${REFERENCE_CS:-0.35512}"
TARGET_RE_H="${TARGET_RE_H:-280.0}"

D="${D:-0.3125}"; CYLINDER_R="${CYLINDER_R:-0.15625}"
CYLINDER_CX="${CYLINDER_CX:-1.25}"; CYLINDER_CY="${CYLINDER_CY:-0.78125}"
UMEAN="${UMEAN:-$(python3 - "$TARGET_RE_H" "$REFERENCE_NU" "$Ly" <<'PY_U'
import sys
re,nu,h=map(float,sys.argv[1:]); print(f"{re*nu/h:.17g}")
PY_U
)}"
UMAX="${UMAX:-$(python3 - "$UMEAN" <<'PY_U'
import sys; print(f"{1.5*float(sys.argv[1]):.17g}")
PY_U
)}"
U0="$UMAX"; UIN="$UMAX"; UOUT_NOMINAL="$UMEAN"; VELOCITY_MODE="poiseuille_x"
SEED="${SEED:-493920}"
INLET_FACE=left; INLET_SMIN=0.0; INLET_SMAX=1.0
OUTLET_FACE=right; OUTLET_SMIN=0.0; OUTLET_SMAX=1.0
INLET_PROFILE=poiseuille_y_max; OUTLET_MODE=neumann; INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-6}"

RUN_OK_DARCY_COMMON_FILLED_STATE=1
SKIP_SOLID_CELLS=false; SKIP_SOLID_PARTICLES=false
ALPHA="${ALPHA:-4000.0}"; ALPHA_MIN="${ALPHA_MIN:-0.0}"; DARCY_Q="${DARCY_Q:-0.1}"
DARCY_INITIAL_DEACTIVATE_BELOW_CHI="${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:--1}"
DARCY_BRINKMAN_FORCING_MODE="${DARCY_BRINKMAN_FORCING_MODE:-mean}"
DARCY_CHI_COLLISION_VP_ENABLE="${DARCY_CHI_COLLISION_VP_ENABLE:-false}"

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"; PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-2500}"; PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_STRICT="${Q6_STRICT:-1}"; Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1; Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6; Q6_GF_DENSITY_TRACTION_GAIN=1.0; Q6_GF_MIN_FILL_FRACTION=0.10
Q6_GF_HAS_GAS_PHASE=0; Q6_GF_EXTERNAL_SPECIES=0
SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-1.0}"

SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2000}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/run_ok_vk_zovatto_re280_reduced_${NX}x${NY}_g${GAMMA}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-speed}"; LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"; LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"; RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-mass,ux,uy}"; RECORD_EVERY="${RECORD_EVERY:-100}"
FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

suite_defaults_common_0434
suite_compute_derived_0434

write_params_vk() {
  local mode=$1 state=$2 out=$3 chi=$4 params=$5
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
openBoundarySegment0 = left inlet 0.0 1.0 ${UIN} 0.0 0 ${PARTICLE_MASS}
openBoundarySegment1 = right outlet 0.0 1.0 ${UOUT_NOMINAL} 0.0 0 ${PARTICLE_MASS}
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
inletRandomizeTangential = true
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
PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
  suite_write_darcy_params_0434 "$chi" "$mode" >> "$params"
}

generate_vk() {
  local state=$1 chi=$2
  RUN_OK_GENERATOR_PATH="$GENERATOR_0434"
  python3 "$GENERATOR_0434" --case "$GEN_CASE" --state "$state" --chi "$chi" \
    --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --kBT "$KBT" --mass "$PARTICLE_MASS" \
    --seed "$SEED" --u0 "$U0" --velocity-mode "$VELOCITY_MODE" --background-type 0 --inactive-type 0 \
    --inactive-slots "$INACTIVE_SLOTS" --skip-solid-cells false --skip-solid-particles false --remove-mean-drift false \
    --cylinder-cx "$CYLINDER_CX" --cylinder-cy "$CYLINDER_CY" --cylinder-r "$CYLINDER_R"
}

mode=src-q6-g-f
run_root="$BASE_RUN_ROOT/$mode"; suite_prepare_dirs_0434 "$run_root"
state="$run_root/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
chi="$run_root/chi/${CASE_LABEL}_${NX}x${NY}.f32"
params="$run_root/params/${CASE_LABEL}.kv"; out="$run_root/output"; log="$run_root/logs/${CASE_LABEL}.log"; time_file="$run_root/logs/${CASE_LABEL}.time"
mkdir -p "$out"
generate_vk "$state" "$chi"
write_params_vk "$mode" "$state" "$out" "$chi" "$params"
suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
echo "[run_ok_vk] Q6-g-f projection=$PROJECTION_OPERATOR tol=$PROJECTION_TOLERANCE maxIt=$PROJECTION_MAX_ITERATIONS x7j=1"
echo "[run_ok_vk] Zovatto reduced H/D=5 upstream=4D downstream=11D D/h=80 Re_H=$TARGET_RE_H Umean=$UMEAN Umax=$UMAX"
suite_run_binary_0434 "$params" "$log" "$time_file" "$out"

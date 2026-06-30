#!/usr/bin/env bash
set -euo pipefail

# 0431 -- segmented injection of particles of type 1 into a homogeneous
# type-2 medium, equal mass m=1.
#
# Geometry:
#   - initial active homogeneous medium: type BACKGROUND_TYPE=2, mass=1;
#   - left segmented inlet injects INJECT_TYPE=1, mass=1;
#   - right boundary is by default a full-height segmented outlet, which keeps
#     the resident segmented IO path coherent.
#
# Integration path:
#   INTEG_PATH=src | src-resampling | src-q6 | src-q6-resampling
#
# The script is autonomous and generates its own .smpcd state.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bool_true_0431() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

INTEG_PATH=${INTEG_PATH:-${SRC_INTEG_PATH:-src}}
case "$INTEG_PATH" in
  src|classic) CASE_LABEL=src; SRC_CLASSIC_CUDA_MODE_ENABLE=true; PROJECTION_ENABLE=false; RESAMPLING_ENABLE=false ;;
  src-resampling|resampling) CASE_LABEL=src-resampling; SRC_CLASSIC_CUDA_MODE_ENABLE=true; PROJECTION_ENABLE=false; RESAMPLING_ENABLE=true ;;
  src-q6|q6) CASE_LABEL=src-q6; SRC_CLASSIC_CUDA_MODE_ENABLE=false; PROJECTION_ENABLE=true; RESAMPLING_ENABLE=false ;;
  src-q6-resampling|q6-resampling) CASE_LABEL=src-q6-resampling; SRC_CLASSIC_CUDA_MODE_ENABLE=false; PROJECTION_ENABLE=true; RESAMPLING_ENABLE=true ;;
  *) echo "[0431-type-injection] ERROR unsupported INTEG_PATH=$INTEG_PATH" >&2; exit 2 ;;
esac

path_has_q6_0431() { [[ "$CASE_LABEL" == "src-q6" || "$CASE_LABEL" == "src-q6-resampling" ]]; }
path_has_resampling_0431() { [[ "$CASE_LABEL" == "src-resampling" || "$CASE_LABEL" == "src-q6-resampling" ]]; }

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0400_livevis}"
AUTO_BUILD="${AUTO_BUILD:-1}"
BUILD_HELPER="${BUILD_HELPER:-scripts/build_src_mpcd_cuda_q6_resident_0400.sh}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

Lx=${Lx:-${LX:-4.0}}
Ly=${Ly:-${LY:-1.0}}
NX=${NX:-1200}
NY=${NY:-300}
GAMMA=${GAMMA:-6}
STEPS=${STEPS:-5000}
DT=${DT:-0.005}
KBT=${KBT:-0.5}
SEED=${SEED:-431173}
STATE_SEED=${STATE_SEED:-$((SEED + 13))}
THREADS=${THREADS:-8}
SUMMARY_EVERY=${SUMMARY_EVERY:-25}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-500}
PARTICLE_MASS=${PARTICLE_MASS:-400.0}

UIN=${UIN:-1.0}
UINIT=${UINIT:-0.0}
BACKGROUND_TYPE=${BACKGROUND_TYPE:-2}
INJECT_TYPE=${INJECT_TYPE:-1}
INJECT_MASS=${INJECT_MASS:-1.0}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-$((GAMMA * NX * NY))}

# Left segmented inlet.
INLET_FACE=${INLET_FACE:-left}
INLET_CENTER_Y=${INLET_CENTER_Y:-0.5}
INLET_HEIGHT_CELLS=${INLET_HEIGHT_CELLS:-5.0}
INLET_SMIN=${INLET_SMIN:-$(awk -v cy="$INLET_CENTER_Y" -v h="$INLET_HEIGHT_CELLS" -v ly="$Ly" -v ny="$NY" 'BEGIN{dy=ly/ny; y=cy-0.5*h*dy; if(y<0)y=0; printf "%.17g", y/ly}')}
INLET_SMAX=${INLET_SMAX:-$(awk -v cy="$INLET_CENTER_Y" -v h="$INLET_HEIGHT_CELLS" -v ly="$Ly" -v ny="$NY" 'BEGIN{dy=ly/ny; y=cy+0.5*h*dy; if(y>ly)y=ly; printf "%.17g", y/ly}')}
INLET_RESERVOIR_CELLS=${INLET_RESERVOIR_CELLS:-2}
INLET_THERMAL_NOISE=${INLET_THERMAL_NOISE:-1.0}

# Right outlet choice.
# segmented: right full-height outlet segment, recommended resident path.
# fullface: experimental mixed mode, uses bcRight=outlet plus left segmented inlet.
RIGHT_OUTLET_STYLE=${RIGHT_OUTLET_STYLE:-segmented}
OUTLET_MODE=${OUTLET_MODE:-hybrid}
OUTLET_SMIN=${OUTLET_SMIN:-0.0}
OUTLET_SMAX=${OUTLET_SMAX:-1.0}
OUTLET_HYBRID_BLEND=${OUTLET_HYBRID_BLEND:-0.5}
OUTLET_FEEDBACK_GAIN=${OUTLET_FEEDBACK_GAIN:-0.0}

PROJECTION_BACKEND=${PROJECTION_BACKEND:-cuda}
PROJECTION_OPERATOR=${PROJECTION_OPERATOR:-auto_fv_cg}
PROJECTION_MAX_ITERATIONS=${PROJECTION_MAX_ITERATIONS:-800}
PROJECTION_TOLERANCE=${PROJECTION_TOLERANCE:-1e-10}
PROJECTION_MOMENTUM_CORRECTION_ENABLE=${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}
Q6_PROJECTION_STRENGTH=${Q6_PROJECTION_STRENGTH:-1.0}
Q6_STRICT=${Q6_STRICT:-1}

THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE:-true}
THERMOSTAT_MODE=${THERMOSTAT_MODE:-cell_relative_rescale}
THERMOSTAT_EVERY=${THERMOSTAT_EVERY:-1}
THERMOSTAT_TARGET_KBT=${THERMOSTAT_TARGET_KBT:--1.0}
THERMOSTAT_MIN_PARTICLES=${THERMOSTAT_MIN_PARTICLES:-3}

RESAMP_N_MIN=${RESAMP_N_MIN:-14}
RESAMP_N_TARGET=${RESAMP_N_TARGET:-20}
RESAMP_N_MAX=${RESAMP_N_MAX:-26}
GUARD_EVERY=${GUARD_EVERY:-5}

SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER:-fluid}
DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER:-fluid}

FORCE_BUILD=${FORCE_BUILD:-0}
BUILD_IF_STALE=${BUILD_IF_STALE:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-1}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-${SRC_LIVE_VIS_ENABLE:-1}}
LIVE_VIS_FIELD=${LIVE_VIS_FIELD:-density}
LIVE_VIS_EVERY=${LIVE_VIS_EVERY:-1}
LIVE_VIS_NX=${LIVE_VIS_NX:-1200}
LIVE_VIS_NY=${LIVE_VIS_NY:-300}
LIVE_VIS_CLIP=${LIVE_VIS_CLIP:--1}
LIVE_VIS_GAIN=${LIVE_VIS_GAIN:-1.0}
LIVE_VIS_SMOOTH_PASSES=${LIVE_VIS_SMOOTH_PASSES:-2}
LIVE_VIS_COLORMAP=${LIVE_VIS_COLORMAP:-gray}
LIVE_VIS_WINDOW_SCALE=${LIVE_VIS_WINDOW_SCALE:-1}
LIVE_VIS_VSYNC=${LIVE_VIS_VSYNC:-0}
LIVE_VIS_CUDA_FIELD=${LIVE_VIS_CUDA_FIELD:-1}
LIVE_VIS_CUDA_SNAPSHOT=${LIVE_VIS_CUDA_SNAPSHOT:-0}
LIVE_VIS_LOG_SOURCE=${LIVE_VIS_LOG_SOURCE:-0}
LIVE_VIS_CONTROL_FILE=${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}
LIVE_VIS_CONTROL_EVERY=${LIVE_VIS_CONTROL_EVERY:-1}
LIVE_VIS_CONTROL_LOG=${LIVE_VIS_CONTROL_LOG:-0}
LIVE_VIS_HOLD_ON_EXIT=${LIVE_VIS_HOLD_ON_EXIT:-1}

TAG=${TAG:-type${INJECT_TYPE}_into_type${BACKGROUND_TYPE}_${CASE_LABEL}_${NX}x${NY}_u${UIN}}
RUN_ROOT=${RUN_ROOT:-runs/injection_type1_into_type2_0431_${TAG}}
STATE=${STATE:-$RUN_ROOT/init/homogeneous_type${BACKGROUND_TYPE}_${NX}x${NY}_g${GAMMA}.smpcd}
PARAMS=${PARAMS:-$RUN_ROOT/params/injection_type1_into_type2.kv}
OUT_DIR=${OUT_DIR:-$RUN_ROOT/output}
TIME_FILE=${TIME_FILE:-$RUN_ROOT/logs/injection_type1_into_type2.time}
ENV_FILE=${ENV_FILE:-$RUN_ROOT/logs/environment_0431.env}

build_solver_0431() {
  if [[ -x "$BIN" && "$FORCE_REBUILD" != "1" && "$FORCE_REBUILD" != "true" && "$FORCE_REBUILD" != "TRUE" ]]; then
    return 0
  fi
  if ! bool_true_0431 "$AUTO_BUILD"; then echo "[0431-type-injection] missing binary: $BIN" >&2; exit 127; fi
  if [[ ! -f "$BUILD_HELPER" ]]; then echo "[0431-type-injection] missing build helper: $BUILD_HELPER" >&2; exit 127; fi
  MPCD_ENABLE_LIVE_VIS="${MPCD_ENABLE_LIVE_VIS:-1}" OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash "$BUILD_HELPER"
}

generate_type2_medium_state_0431() {
  local out=$1
  mkdir -p "$(dirname "$out")"
  python3 - "$out" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$PARTICLE_MASS" "$STATE_SEED" "$UINIT" "$BACKGROUND_TYPE" "$INACTIVE_SLOTS" <<'PYGEN'
import math, os, random, struct, sys
out,Lx,Ly,Nx,Ny,gamma,kBT,mass0,seed,uinit,bgtype,inactive = sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny); gamma=int(gamma)
kBT=float(kBT); mass0=float(mass0); seed=int(seed); uinit=float(uinit)
bgtype=int(bgtype); inactive=int(inactive)
rng=random.Random(seed); dx=Lx/Nx; dy=Ly/Ny
sigma=math.sqrt(kBT/mass0) if kBT > 0 else 0.0
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
for j in range(Ny):
    for i in range(Nx):
        x0=i*dx; y0=j*dy
        for _ in range(gamma):
            xp=x0+dx*rng.random(); yp=y0+dy*rng.random()
            ux=uinit + (sigma*rng.gauss(0.0,1.0) if sigma else 0.0)
            uy=(sigma*rng.gauss(0.0,1.0) if sigma else 0.0)
            x.append(xp); y.append(yp); vx.append(ux); vy.append(uy)
            typ.append(bgtype); mass.append(mass0); role.append(1)
fluid_mass=sum(mass[i] for i,r in enumerate(role) if r==1)
if fluid_mass:
    mvx=sum(mass[i]*vx[i] for i,r in enumerate(role) if r==1)/fluid_mass
    mvy=sum(mass[i]*vy[i] for i,r in enumerate(role) if r==1)/fluid_mass
    for i,r in enumerate(role):
        if r==1:
            vx[i]=vx[i]-mvx+uinit
            vy[i]=vy[i]-mvy
for _ in range(inactive):
    x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
    typ.append(1); mass.append(mass0); role.append(0)
n=len(x)
magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE'))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
with open(out,'wb') as f:
    f.write(magic)
    f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4))
    f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in [(x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')]:
        f.write(struct.pack('<%d%s'%(n,fmt),*arr))
print(f"[0431-state] output={out} activeType={bgtype} fluid={Nx*Ny*gamma} inactive={inactive} total={n}")
PYGEN
}

write_params_0431() {
  local bc_right="solid" seg_count=2
  if [[ "$RIGHT_OUTLET_STYLE" == "fullface" ]]; then
    bc_right="outlet"
    seg_count=1
  elif [[ "$RIGHT_OUTLET_STYLE" != "segmented" ]]; then
    echo "[0431-type-injection] ERROR RIGHT_OUTLET_STYLE must be segmented or fullface" >&2
    exit 2
  fi
  cat > "$PARAMS" <<PARAMS
inputState = $STATE
outputDir = $OUT_DIR
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY

dt = $DT
nSteps = $STEPS

bcLeft = solid
bcRight = $bc_right
bcBottom = solid
bcTop = solid
bcX = solid
bcY = solid

openBoundarySegmentsEnable = true
openBoundarySegmentCount = $seg_count
openBoundarySegment0 = $INLET_FACE inlet $INLET_SMIN $INLET_SMAX $UIN 0.0 $INJECT_TYPE $INJECT_MASS
PARAMS
  if [[ "$RIGHT_OUTLET_STYLE" == "segmented" ]]; then
    cat >> "$PARAMS" <<PARAMS
openBoundarySegment1 = right outlet $OUTLET_SMIN $OUTLET_SMAX $UIN 0.0 0 1.0
PARAMS
  fi
  cat >> "$PARAMS" <<PARAMS

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.25
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = -0.00001
inletThermalNoise = $INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $INLET_RESERVOIR_CELLS
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = $OUTLET_MODE
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = $OUTLET_FEEDBACK_GAIN

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

srcClassicCudaModeEnable = $SRC_CLASSIC_CUDA_MODE_ENABLE
projectionEnable = $PROJECTION_ENABLE
projectionBackend = $PROJECTION_BACKEND
projectionOperator = $PROJECTION_OPERATOR
projectionMaxIterations = $PROJECTION_MAX_ITERATIONS
projectionTolerance = $PROJECTION_TOLERANCE
projectionMomentumCorrectionEnable = $PROJECTION_MOMENTUM_CORRECTION_ENABLE
q6ProjectionStrength = $Q6_PROJECTION_STRENGTH

resamplingEnable = $RESAMPLING_ENABLE
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $SEED

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $PARTICLE_MASS
wallKBT = -1.0
wallThermalNoise = 0.0

thermostatEnable = $THERMOSTAT_ENABLE
thermostatMode = $THERMOSTAT_MODE
thermostatEvery = $THERMOSTAT_EVERY
thermostatTargetKBT = $THERMOSTAT_TARGET_KBT
thermostatMinParticles = $THERMOSTAT_MIN_PARTICLES
kBT = $KBT
PARAMS
  if [[ "$RESAMPLING_ENABLE" == "true" ]]; then
    cat >> "$PARAMS" <<PARAMS

resamplingPopulationNMin = $RESAMP_N_MIN
resamplingPopulationNTarget = $RESAMP_N_TARGET
resamplingPopulationNMax = $RESAMP_N_MAX
resamplingTargetCellMass = $GAMMA
resamplingWetMaskMode = occupied
resamplingWetCellMassThreshold = 0.0
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = 0.5
resamplingParticleMassMax = 2.0
resamplingLatentActivationEnable = false
PARAMS
  fi
  cat >> "$PARAMS" <<PARAMS

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_STATE_EVERY
summaryRoleFilter = $SUMMARY_ROLE_FILTER
dumpRoleFilter = $DUMP_ROLE_FILTER
initialInactiveSlots = $INACTIVE_SLOTS
numThreads = $THREADS
PARAMS
}

cuda_env_clear_0431() {
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=0
  export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0
  export MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=0
  export MPCD_CUDA_Q6_RESIDENT_0400=0
  export MPCD_CUDA_Q6_RESIDENT_STRICT_0400=0
  export MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=0
  export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
  export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE=0
  export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=0
}

apply_fastflags_0431() {
  case "${MPCD_INJECTION_FASTFLAGS_ENABLE:-1}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) ;;
    *) return 0 ;;
  esac
  export MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM="${MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM:-1}"
  export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE="${MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE:-1}"
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE="${MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE:-1}"
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE="${MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319:-1}"
}

apply_env_0431() {
  cuda_env_clear_0431
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
  export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  if path_has_q6_0431; then
    export MPCD_CUDA_Q6_RESIDENT_0400=1
    export MPCD_CUDA_Q6_RESIDENT_STRICT_0400="$Q6_STRICT"
    export MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  else
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  fi
  if path_has_resampling_0431; then
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=1
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY="$GUARD_EVERY"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH=1.0
    export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=1
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE=1
    export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1
    export MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1
  fi
  apply_fastflags_0431
}

livevis_prepare_0431() {
  if [[ ! -f "$LIVE_VIS_CONTROL_FILE" ]]; then
    cat > "$LIVE_VIS_CONTROL_FILE" <<CONTROL
field = ${LIVE_VIS_FIELD}
clip = ${LIVE_VIS_CLIP}
gain = ${LIVE_VIS_GAIN}
smoothPasses = ${LIVE_VIS_SMOOTH_PASSES}
colormap = ${LIVE_VIS_COLORMAP}
CONTROL
  fi
  export SRC_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
  export MPCD_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
  export SRC_LIVE_VIS_FIELD="$LIVE_VIS_FIELD"
  export SRC_LIVE_VIS_EVERY="$LIVE_VIS_EVERY"
  export SRC_LIVE_VIS_NX="$LIVE_VIS_NX"
  export SRC_LIVE_VIS_NY="$LIVE_VIS_NY"
  export SRC_LIVE_VIS_CLIP="$LIVE_VIS_CLIP"
  export SRC_LIVE_VIS_GAIN="$LIVE_VIS_GAIN"
  export SRC_LIVE_VIS_SMOOTH_PASSES="$LIVE_VIS_SMOOTH_PASSES"
  export SRC_LIVE_VIS_COLORMAP="$LIVE_VIS_COLORMAP"
  export SRC_LIVE_VIS_WINDOW_SCALE="$LIVE_VIS_WINDOW_SCALE"
  export SRC_LIVE_VIS_VSYNC="$LIVE_VIS_VSYNC"
  export SRC_LIVE_VIS_CUDA_FIELD="$LIVE_VIS_CUDA_FIELD"
  export SRC_LIVE_VIS_CUDA_SNAPSHOT="$LIVE_VIS_CUDA_SNAPSHOT"
  export SRC_LIVE_VIS_LOG_SOURCE="$LIVE_VIS_LOG_SOURCE"
  export SRC_LIVE_VIS_CONTROL_FILE="$LIVE_VIS_CONTROL_FILE"
  export SRC_LIVE_VIS_CONTROL_EVERY="$LIVE_VIS_CONTROL_EVERY"
  export SRC_LIVE_VIS_CONTROL_LOG="$LIVE_VIS_CONTROL_LOG"
  export SRC_LIVE_VIS_HOLD_ON_EXIT="$LIVE_VIS_HOLD_ON_EXIT"
}

build_solver_0431
if [[ ! -x "$BIN" ]]; then echo "[0431-type-injection] missing binary: $BIN" >&2; exit 127; fi

mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/params" "$RUN_ROOT/logs" "$OUT_DIR"
generate_type2_medium_state_0431 "$STATE"
write_params_0431
apply_env_0431
livevis_prepare_0431

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

env | grep -E '^(MPCD_INJECTION_FASTFLAGS_ENABLE=|MPCD_CUDA_|SRC_LIVE_VIS_|MPCD_LIVE_VIS_ENABLE=|OMP_|BIN=|INTEG_PATH=|SRC_INTEG_PATH=|NX=|NY=|GAMMA=|UIN=|BACKGROUND_TYPE=|INJECT_TYPE=|RIGHT_OUTLET_STYLE=|KBT=|DT=)' | sort > "$ENV_FILE"

echo "[0431-type-injection] binary=$BIN"
echo "[0431-type-injection] params=$PARAMS"
echo "[0431-type-injection] output=$OUT_DIR"
echo "[0431-type-injection] path=$CASE_LABEL type${INJECT_TYPE}->type${BACKGROUND_TYPE} right=$RIGHT_OUTLET_STYLE inlet=[$INLET_SMIN,$INLET_SMAX] UIN=$UIN"

/usr/bin/time -o "$TIME_FILE" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$PARAMS"

echo "[0431-type-injection] time=$(cat "$TIME_FILE")"
echo "[0431-type-injection] dumps/root=$RUN_ROOT"

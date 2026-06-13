#!/usr/bin/env bash
set -euo pipefail

# 0335a: full-periodic VK live visualization driver for SRC_GPU-VIZ.
# This script runs only the SRC binary, without monolithic benchmark or dumps.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bool_true_0335() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac
}

Lx="${Lx:-1.5}"
Ly="${Ly:-0.4}"
NX="${NX:-360}"
NY="${NY:-19}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-20000}"
DT="${DT:-0.0005}"
KBT="${KBT:-5}"
U0="${U0:-0.051}"
SEED="${SEED:-1628505}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-1}"
KEEP_MEAN_FLOW_ENABLE="${KEEP_MEAN_FLOW_ENABLE:-false}"
CX="${CX:-0.25}"
CY="${CY:-0.205}"
RC="${RC:-0.04}"
THREADS="${THREADS:-8}"
MODE="${MODE:-classic}"   # classic or resampling
INACTIVE_SLOTS="${INACTIVE_SLOTS:-0}"
if [[ "$MODE" == "resampling" && "${INACTIVE_SLOTS}" == "0" ]]; then
  INACTIVE_SLOTS="${INACTIVE_SLOTS_RESAMPLING:-750000}"
fi

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

SRC_BIN="${SRC_BIN:-build/src_mpcd_base_cuda_livevis_0335a}"
AUTO_BUILD_SRC="${AUTO_BUILD_SRC:-1}"
FORCE_REBUILD_SRC="${FORCE_REBUILD_SRC:-0}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}"
TAG="${TAG:-vk_full_periodic_livevis_0335a_${MODE}}"
RUN_ROOT="${RUN_ROOT:-runs/${TAG}}"

export SRC_LIVE_VIS_ENABLE="${SRC_LIVE_VIS_ENABLE:-1}"
export SRC_LIVE_VIS_FIELD="${SRC_LIVE_VIS_FIELD:-ux}"
export SRC_LIVE_VIS_EVERY="${SRC_LIVE_VIS_EVERY:-10}"
export SRC_LIVE_VIS_NX="${SRC_LIVE_VIS_NX:-300}"
export SRC_LIVE_VIS_NY="${SRC_LIVE_VIS_NY:-80}"
export SRC_LIVE_VIS_ALPHA="${SRC_LIVE_VIS_ALPHA:-0.08}"
export SRC_LIVE_VIS_CLIP="${SRC_LIVE_VIS_CLIP:--1}"
export SRC_LIVE_VIS_QUANTILE="${SRC_LIVE_VIS_QUANTILE:-0.995}"
export SRC_LIVE_VIS_GAIN="${SRC_LIVE_VIS_GAIN:-1.0}"
export SRC_LIVE_VIS_SMOOTH_PASSES="${SRC_LIVE_VIS_SMOOTH_PASSES:-1}"
export SRC_LIVE_VIS_WINDOW_SCALE="${SRC_LIVE_VIS_WINDOW_SCALE:-1}"
export SRC_LIVE_VIS_VSYNC="${SRC_LIVE_VIS_VSYNC:-0}"
if [[ "$MODE" == "resampling" ]]; then
  export SRC_LIVE_VIS_FORCE_HOST_MIRROR="${SRC_LIVE_VIS_FORCE_HOST_MIRROR:-1}"
  # 0335d: visual-inspection mode.  The CUDA resampling path may invalidate the
  # shared 0251 mirror, so the live renderer otherwise falls back to a frozen
  # host copy.  This slower mode forces host-visible updates for visualization.
  export SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR="${SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR:-1}"
else
  export SRC_LIVE_VIS_FORCE_HOST_MIRROR="${SRC_LIVE_VIS_FORCE_HOST_MIRROR:-0}"
  export SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR="${SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR:-0}"
fi

build_src_if_needed_0335() {
  if [[ -x "$SRC_BIN" && ! "$FORCE_REBUILD_SRC" =~ ^(1|true|TRUE)$ ]]; then return 0; fi
  if ! bool_true_0335 "$AUTO_BUILD_SRC"; then
    echo "[0335a] missing SRC binary: $SRC_BIN" >&2
    exit 127
  fi
  echo "[0335a] building $SRC_BIN with live visualization enabled"
  MPCD_ENABLE_LIVE_VIS=1 OUT="$SRC_BIN" CUDA_ARCH_FLAGS="$CUDA_ARCH_FLAGS" \
    bash scripts/build_src_mpcd_cuda_0315b.sh
}

generate_state_0335() {
  local output=$1 inactive_slots=$2
  python3 - "$output" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" "$U0" "$CX" "$CY" "$RC" "$inactive_slots" <<'PYGEN'
import math, os, random, struct, sys
(out,Lx,Ly,Nx,Ny,gamma,kBT,seed,U0,cx,cy,rc,inactive_slots)=sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny); gamma=float(gamma); kBT=float(kBT); seed=int(seed); U0=float(U0)
cx=float(cx); cy=float(cy); rc=float(rc); inactive_slots=int(inactive_slots)
n_active=int(round(gamma*Nx*Ny))
rng=random.Random(seed)
sigma=math.sqrt(kBT) if kBT>0 else 0.0
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
rejected=0
for _ in range(n_active):
    for attempt in range(100000):
        xp=Lx*rng.random(); yp=Ly*rng.random()
        if (xp-cx)*(xp-cx)+(yp-cy)*(yp-cy) >= rc*rc:
            break
        rejected += 1
    else:
        raise SystemExit('too many cylinder rejection attempts')
    x.append(xp); y.append(yp)
    vx.append(U0 + sigma*rng.gauss(0.0,1.0)); vy.append(sigma*rng.gauss(0.0,1.0))
    typ.append(0); mass.append(1.0); role.append(1)
mx=sum(vx)/len(vx); my=sum(vy)/len(vy)
for i in range(len(vx)):
    vx[i]=vx[i]-mx+U0
    vy[i]=vy[i]-my
for _ in range(inactive_slots):
    x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0); typ.append(0); mass.append(1.0); role.append(0)
os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE'))
n=len(x); reserved=[0]*8; reserved[0]=1; reserved[1]=1
with open(out,'wb') as f:
    f.write(magic)
    f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4))
    f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in [(x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')]:
        f.write(struct.pack('<%d%s'%(n,fmt),*arr))
print(f'[0335a-state] output={out} fluid={n_active} inactive={inactive_slots} total={n} rejectedCylinder={rejected}')
PYGEN
}

write_params_0335() {
  local params=$1 state=$2 out=$3 mode=$4
  local resampling_enable="false"
  [[ "$mode" == "resampling" ]] && resampling_enable="true"
  cat > "$params" <<PARAMS
inputState = ${state}
outputDir = ${out}
Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
keepMeanFlowEnable = ${KEEP_MEAN_FLOW_ENABLE}
immersedSolidEnable = true
immersedSolidShape = circle
immersedSolidCx = ${CX}
immersedSolidCy = ${CY}
immersedSolidR = ${RC}
immersedSolidFractionSamples = 4
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

nSteps = ${STEPS}
dt = ${DT}
rotationAngle = ${ROTATION_ANGLE}
randomRotationSign = true
gridShiftEnable = true
rngSeed = ${SEED}

srcClassicCudaModeEnable = true
projectionEnable = false
resamplingEnable = ${resampling_enable}
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false

thermostatEnable = $(if bool_true_0335 "$THERMOSTAT_ENABLE"; then echo true; else echo false; fi)
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = ${KBT}

summaryEvery = ${STEPS}
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
numThreads = ${THREADS}
PARAMS
}

cuda_env_0335() {
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
  export MPCD_CUDA_IMMERSED_CIRCLE_0284=1
  export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
  export MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330="${MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=1
  if bool_true_0335 "$SRC_LIVE_VIS_FORCE_HOST_MIRROR"; then
    # Slower but useful for live visual inspection of paths that invalidate the shared CUDA mirror.
    export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=0
  fi
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
  export MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318_UNSAFE_ENABLE=0
  if bool_true_0335 "$THERMOSTAT_ENABLE"; then
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
  fi
  if [[ "$MODE" == "resampling" ]]; then
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296="${MASS_RECONDITION_ENABLE:-1}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY="${MASS_RECONDITION_EVERY:-5}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="${GUARD_EVERY:-5}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="${GUARD_NMIN:-12}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="${GUARD_NTARGET:-20}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="${GUARD_NMAX:-32}"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="${RESTORE_ENABLE:-1}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="${BOUNDARY_AWARE:-1}"
    export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307="${MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307:-1}"
    if bool_true_0335 "$SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR"; then
      # Visualization-only fallback: keep the authoritative host mirror moving.
      # This intentionally gives up the fastest fully-resident path, but avoids
      # a frozen live window when the CUDA resampling edits invalidate the 0251
      # compact fluid download used by the renderer.
      export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
      export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
      export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
      export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=0
      export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=0
      export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=0
      export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=0
      export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=1
      export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=1
    fi
  else
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298=0
  fi
}

build_src_if_needed_0335
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/params" "$RUN_ROOT/output" "$RUN_ROOT/logs"
STATE="$RUN_ROOT/init/vk_full_periodic_livevis_0335a_${NX}x${NY}_g${GAMMA}_inactive${INACTIVE_SLOTS}.smpcd"
PARAMS="$RUN_ROOT/params/vk_full_periodic_livevis_0335a.kv"
generate_state_0335 "$STATE" "$INACTIVE_SLOTS"
write_params_0335 "$PARAMS" "$STATE" "$RUN_ROOT/output" "$MODE"
cuda_env_0335
env | grep -E '^(MPCD_CUDA_|SRC_GPU_|SRC_LIVE_VIS_|OMP_)' | sort > "$RUN_ROOT/logs/environment_0335a.env"

echo "[0335a] binary=$SRC_BIN"
echo "[0335a] params=$PARAMS"
echo "[0335a] run_root=$RUN_ROOT"
"$SRC_BIN" "$PARAMS"

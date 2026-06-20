#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_darcy_resamp_0360}"
TAG="${TAG:-vk_resamp_1200x640_u0p9_5000_0360}"
RUN_ROOT="${RUN_ROOT:-runs/${TAG}}"

export Lx="${Lx:-1.5}"
export Ly="${Ly:-0.4}"
export NX="${NX:-1200}"
export NY="${NY:-640}"
export GAMMA="${GAMMA:-6}"
export STEPS="${STEPS:-5000}"
export DT="${DT:-0.0005}"
export KBT="${KBT:-5}"
export U0="${U0:-0.9}"
export SEED="${SEED:-1628505}"
export CYLINDER_CX="${CYLINDER_CX:-0.25}"
export CYLINDER_CY="${CYLINDER_CY:-0.205}"
export CYLINDER_R="${CYLINDER_R:-0.04}"
export THREADS="${THREADS:-12}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

export SRC_LIVE_VIS_ENABLE="${SRC_LIVE_VIS_ENABLE:-1}"
export SRC_LIVE_VIS_FIELD="${SRC_LIVE_VIS_FIELD:-vorticity}"
export SRC_LIVE_VIS_EVERY="${SRC_LIVE_VIS_EVERY:-5}"
export SRC_LIVE_VIS_NX="${SRC_LIVE_VIS_NX:-1200}"
export SRC_LIVE_VIS_NY="${SRC_LIVE_VIS_NY:-640}"
export SRC_LIVE_VIS_CLIP="${SRC_LIVE_VIS_CLIP:--20}"
export SRC_LIVE_VIS_GAIN="${SRC_LIVE_VIS_GAIN:-1.0}"
export SRC_LIVE_VIS_SMOOTH_PASSES="${SRC_LIVE_VIS_SMOOTH_PASSES:-3}"
export SRC_LIVE_VIS_COLORMAP="${SRC_LIVE_VIS_COLORMAP:-thermal}"
export SRC_LIVE_VIS_WINDOW_SCALE="${SRC_LIVE_VIS_WINDOW_SCALE:-1}"
export SRC_LIVE_VIS_VSYNC="${SRC_LIVE_VIS_VSYNC:-0}"
export SRC_LIVE_VIS_CUDA_FIELD="${SRC_LIVE_VIS_CUDA_FIELD:-1}"
export SRC_LIVE_VIS_CUDA_SNAPSHOT="${SRC_LIVE_VIS_CUDA_SNAPSHOT:-0}"
export SRC_LIVE_VIS_FORCE_HOST_MIRROR="${SRC_LIVE_VIS_FORCE_HOST_MIRROR:-0}"
export SRC_LIVE_VIS_CONTROL_FILE="${SRC_LIVE_VIS_CONTROL_FILE:-$ROOT/livevis_control.kv}"
export SRC_LIVE_VIS_CONTROL_EVERY="${SRC_LIVE_VIS_CONTROL_EVERY:-1}"
export SRC_LIVE_VIS_CONTROL_LOG="${SRC_LIVE_VIS_CONTROL_LOG:-1}"

if [[ ! -x "$BIN" ]]; then
  echo "[0360-vk] ERROR missing binary: $BIN" >&2
  exit 127
fi
if [[ ! -f "$SRC_LIVE_VIS_CONTROL_FILE" ]]; then
  cat > "$SRC_LIVE_VIS_CONTROL_FILE" <<CONTROL
field = ${SRC_LIVE_VIS_FIELD}
clip = ${SRC_LIVE_VIS_CLIP}
gain = ${SRC_LIVE_VIS_GAIN}
smoothPasses = ${SRC_LIVE_VIS_SMOOTH_PASSES}
colormap = ${SRC_LIVE_VIS_COLORMAP}
CONTROL
fi

if [[ "$CLEAN_RUN_ROOT" == "1" ]]; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/params" "$RUN_ROOT/output" "$RUN_ROOT/logs"
STATE="$RUN_ROOT/init/vk_resamp_1200x640_u0p9_0360.smpcd"
PARAMS="$RUN_ROOT/params/vk_resamp_1200x640_u0p9_0360.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/vk_resamp_1200x640_u0p9_0360.log"
TIMELOG="$RUN_ROOT/logs/vk_resamp_1200x640_u0p9_0360.time"
ENVLOG="$RUN_ROOT/logs/environment_0360.env"

echo "[0360-vk] root=$ROOT"
echo "[0360-vk] bin=$BIN"
echo "[0360-vk] runRoot=$RUN_ROOT"
echo "[0360-vk] livevisControl=$SRC_LIVE_VIS_CONTROL_FILE"
echo "[0360-vk] case: ${NX}x${NY}, L=${Lx}x${Ly}, gamma=${GAMMA}, U0=${U0}, kBT=${KBT}, alpha=pi/2, steps=${STEPS}"
echo "[0360-vk] cylinder: cx=${CYLINDER_CX} cy=${CYLINDER_CY} r=${CYLINDER_R}"

python3 - "$STATE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" "$U0" "$CYLINDER_CX" "$CYLINDER_CY" "$CYLINDER_R" <<'PYGEN'
import os, struct, sys
import numpy as np
(out,Lx,Ly,Nx,Ny,gamma,kBT,seed,u0,cx,cy,r)=sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny); gamma=int(gamma)
kBT=float(kBT); seed=int(seed); u0=float(u0); cx=float(cx); cy=float(cy); r=float(r)
rng=np.random.default_rng(seed); dx=Lx/Nx; dy=Ly/Ny
ii,jj=np.meshgrid(np.arange(Nx,dtype=np.int32), np.arange(Ny,dtype=np.int32), indexing='xy')
xc=(ii.ravel()+0.5)*dx; yc=(jj.ravel()+0.5)*dy
active=((xc-cx)**2+(yc-cy)**2)>r*r
ai=ii.ravel()[active]; aj=jj.ravel()[active]
pi=np.repeat(ai,gamma).astype(np.float64,copy=False); pj=np.repeat(aj,gamma).astype(np.float64,copy=False)
n0=int(pi.size); x=(pi+rng.random(n0))*dx; y=(pj+rng.random(n0))*dy
outside=((x-cx)**2+(y-cy)**2)>r*r; rejected=n0-int(np.count_nonzero(outside))
x=x[outside].astype('<f8',copy=False); y=y[outside].astype('<f8',copy=False); n=int(x.size)
sigma=np.sqrt(kBT); vx=(u0+sigma*rng.standard_normal(n)).astype('<f8',copy=False); vy=(sigma*rng.standard_normal(n)).astype('<f8',copy=False)
vx += u0-float(vx.mean()); vy -= float(vy.mean())
typ=np.zeros(n,dtype='<u4'); mass=np.ones(n,dtype='<f8'); role=np.ones(n,dtype=np.uint8)
os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE')); reserved=[0]*8; reserved[0]=1; reserved[1]=1
with open(out,'wb') as f:
    f.write(magic); f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4)); f.write(struct.pack('<8Q',*reserved))
    x.tofile(f); y.tofile(f); vx.tofile(f); vy.tofile(f); typ.tofile(f); mass.tofile(f); role.tofile(f)
print(f'[0360-state] output={out} grid={Nx}x{Ny} gamma={gamma} fluid={n} activeCells={int(ai.size)} skippedCells={int(Nx*Ny-ai.size)} rejected={rejected}')
PYGEN

cat > "$PARAMS" <<PARAMS
inputState = ${STATE}
outputDir = ${OUT}
Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}

bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
keepMeanFlowEnable = false

immersedSolidEnable = true
immersedSolidShape = circle
immersedSolidCx = ${CYLINDER_CX}
immersedSolidCy = ${CYLINDER_CY}
immersedSolidR = ${CYLINDER_R}
immersedSolidFractionSamples = 4
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

darcyBrinkmanEnable = false
cudaResamplingChiFilterEnable = true
cudaResamplingChiMin = 0.5
cudaResamplingEmptyRefillEnable = false
cudaResamplingEmptyRefillReference = gamma

wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0

nSteps = ${STEPS}
dt = ${DT}
rotationAngle = 1.5707963267948966
randomRotationSign = true
gridShiftEnable = true
rngSeed = ${SEED}

srcClassicCudaModeEnable = true
projectionEnable = false
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = ${KBT}

summaryEvery = ${SUMMARY_EVERY}
dumpStateEvery = ${DUMP_STATE_EVERY}
summaryRoleFilter = fluid
dumpRoleFilter = fluid
numThreads = ${THREADS}
PARAMS

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}" OMP_PROC_BIND="${OMP_PROC_BIND:-close}" OMP_PLACES="${OMP_PLACES:-cores}" OMP_DYNAMIC="${OMP_DYNAMIC:-false}"
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0 MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0 MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0 MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0 MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1 MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0
export MPCD_CUDA_IMMERSED_CIRCLE_0284=1 MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0 MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330=1
export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1 MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1 MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1 MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319=1 MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM=1 MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSE_WALL_FINALIZE_ROTATION_0325=0 MPCD_CUDA_PERSISTENT_SRC_COLLISION_ROTATION_TABLE_CACHE_0329=0 MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1
{
  echo "TAG=${TAG}"; echo "BIN=${BIN}"; sha256sum "$BIN" | awk '{print "BIN_SHA256="$1}'
  echo "RUN_ROOT=${RUN_ROOT}"; echo "STATE=${STATE}"; echo "PARAMS=${PARAMS}"; echo "LIVEVIS_CONTROL=${SRC_LIVE_VIS_CONTROL_FILE}"
  env | grep -E '^(MPCD_CUDA_|SRC_LIVE_VIS_|OMP_)' | sort
} > "$ENVLOG"

echo "[0360-vk] params=$PARAMS"
echo "[0360-vk] output=$OUT"
/usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$PARAMS" > "$LOG" 2> "$TIMELOG"

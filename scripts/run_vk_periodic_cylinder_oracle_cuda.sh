#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN="${BIN:?Usage: BIN=build/src_mpcd_base_cuda_XXXX TAG=XXXX bash scripts/run_vk_periodic_cylinder_oracle_cuda.sh}"
TAG="${TAG:-$(basename "$BIN")}"
RUN_ROOT="${RUN_ROOT:-runs/vk_oracle_${TAG}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

NX="${NX:-300}"
NY="${NY:-160}"
GAMMA="${GAMMA:-6}"
STEPS="${STEPS:-1200}"
DT="${DT:-0.0005}"
KBT="${KBT:-5}"
UIN="${UIN:-0.9}"
SEED="${SEED:-1628505}"
THREADS="${THREADS:-8}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1200}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-750000}"

Lx="${Lx:-2.0}"
Ly="${Ly:-1.0}"
CYLINDER_CX="${CYLINDER_CX:-0.35}"
CYLINDER_CY="${CYLINDER_CY:-0.475}"
CYLINDER_R="${CYLINDER_R:-0.125}"

WALL_CIRCLE_0318="${WALL_CIRCLE_0318:-1}"
MEANVX_MAX="${MEANVX_MAX:-0.80}"

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

if [[ ! -x "$BIN" ]]; then
  echo "ORACLE_ERROR missing_or_not_executable_bin=$BIN" >&2
  exit 127
fi

if [[ "$CLEAN_RUN_ROOT" == "1" ]]; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/params" "$RUN_ROOT/output" "$RUN_ROOT/logs"

STATE="$RUN_ROOT/init/vk_oracle_${TAG}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/vk_oracle_${TAG}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/vk_oracle_${TAG}.log"
TIMELOG="$RUN_ROOT/logs/vk_oracle_${TAG}.time"
ENVLOG="$RUN_ROOT/logs/environment_oracle.env"
MATRIX="runs/vk_oracle_matrix.tsv"

python3 - "$STATE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" "$UIN" "$INACTIVE_SLOTS" "$CYLINDER_CX" "$CYLINDER_CY" "$CYLINDER_R" <<'PYGEN'
import math, os, random, struct, sys

(out,Lx,Ly,Nx,Ny,gamma,kBT,seed,Uin,inactive_slots,cx,cy,r)=sys.argv[1:]
Lx=float(Lx); Ly=float(Ly)
Nx=int(Nx); Ny=int(Ny); gamma=int(gamma)
kBT=float(kBT); seed=int(seed); Uin=float(Uin)
inactive_slots=int(inactive_slots)
cx=float(cx); cy=float(cy); r=float(r)

rng=random.Random(seed)
dx=Lx/Nx
dy=Ly/Ny
mass0=1.0
sigma=math.sqrt(kBT/mass0) if kBT > 0 else 0.0

x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]

def in_circle(xp, yp):
    return (xp-cx)*(xp-cx) + (yp-cy)*(yp-cy) <= r*r

active_cells=0
skipped_cells=0
rejected=0

for j in range(Ny):
    yc=(j+0.5)*dy
    for i in range(Nx):
        xc=(i+0.5)*dx
        if in_circle(xc, yc):
            skipped_cells += 1
            continue
        active_cells += 1
        x0=i*dx
        y0=j*dy
        for _ in range(gamma):
            ok=False
            for _try in range(1000):
                xp=x0+dx*rng.random()
                yp=y0+dy*rng.random()
                if in_circle(xp, yp):
                    rejected += 1
                    continue
                ok=True
                break
            if not ok:
                continue
            ux=Uin
            uy=0.0
            if sigma > 0:
                ux += sigma*rng.gauss(0.0, 1.0)
                uy += sigma*rng.gauss(0.0, 1.0)
            x.append(xp); y.append(yp); vx.append(ux); vy.append(uy)
            typ.append(0); mass.append(mass0); role.append(1)

fluid_mass=sum(m for m,r0 in zip(mass,role) if r0 == 1)
if fluid_mass > 0:
    mvx=sum(m*u for m,u,r0 in zip(mass,vx,role) if r0 == 1)/fluid_mass
    mvy=sum(m*v for m,v,r0 in zip(mass,vy,role) if r0 == 1)/fluid_mass
    for k,r0 in enumerate(role):
        if r0 == 1:
            vx[k]=vx[k]-mvx+Uin
            vy[k]=vy[k]-mvy

for _ in range(inactive_slots):
    x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
    typ.append(0); mass.append(mass0); role.append(0)

os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
magic=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE"))
reserved=[0]*8
reserved[0]=1
reserved[1]=1
n=len(x)

with open(out, "wb") as f:
    f.write(magic)
    f.write(struct.pack("<IIIIQIIII",2,0x01020304,2,1,n,1,1,8,4))
    f.write(struct.pack("<8Q", *reserved))
    for arr,fmt in [(x,"d"),(y,"d"),(vx,"d"),(vy,"d"),(typ,"I"),(mass,"d"),(role,"B")]:
        f.write(struct.pack("<%d%s"%(n,fmt), *arr))

print(f"state={out} Nx={Nx} Ny={Ny} gamma={gamma} fluid={sum(1 for rr in role if rr==1)} inactive={sum(1 for rr in role if rr==0)} activeCells={active_cells} skippedCells={skipped_cells} rejected={rejected}")
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

wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0

nSteps = ${STEPS}
dt = ${DT}
rotationAngle = 1.5
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

# CUDA flags: explicit periodic-x / wall-y / immersed-circle oracle.
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0
export MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0
export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0
export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0

export MPCD_CUDA_STREAMING_PERIODIC_0245=0
export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0

export MPCD_CUDA_IMMERSED_RECTANGLE_0247=0
export MPCD_CUDA_IMMERSED_CIRCLE_0284=1
export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0

export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"

export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1

export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1

export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272="${SRC_GPU_DEVICE_ROTATION_0322:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273="${SRC_GPU_LAZY_KERNEL_CHECK_0322:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273="${SRC_GPU_SKIP_SETUP_SYNC_0322:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1

export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319="${SRC_GPU_SKIP_WALL_VP_DIAG_0319:-1}"
export MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM="${SRC_GPU_ASYNC_STREAM_0320:-1}"
export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS="${SRC_GPU_WALL_FAST_DIAG_0320:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321="${SRC_GPU_FAST_THERMOSTAT_DIAG_0321:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327="${SRC_GPU_SKIP_HOST_CELLID_FILL_0327:-1}"
export MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330="${SRC_GPU_IMMERSED_CIRCLE_FAST_DIAG_0330:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSE_WALL_FINALIZE_ROTATION_0325=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ROTATION_TABLE_CACHE_0329=0

export MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318="${WALL_CIRCLE_0318}"

{
  echo "TAG=${TAG}"
  echo "BIN=${BIN}"
  sha256sum "$BIN" | awk '{print "BIN_SHA256="$1}'
  echo "RUN_ROOT=${RUN_ROOT}"
  echo "WALL_CIRCLE_0318=${WALL_CIRCLE_0318}"
  echo "NX=${NX}"
  echo "NY=${NY}"
  echo "GAMMA=${GAMMA}"
  echo "STEPS=${STEPS}"
  env | grep -E '^(MPCD_CUDA_|SRC_GPU_|OMP_)' | sort
} > "$ENVLOG"

echo "[vk-oracle] TAG=$TAG BIN=$BIN RUN_ROOT=$RUN_ROOT WALL_CIRCLE_0318=$WALL_CIRCLE_0318"

/usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$PARAMS" > "$LOG" 2> "$TIMELOG"

python3 - "$TAG" "$BIN" "$RUN_ROOT" "$WALL_CIRCLE_0318" "$MEANVX_MAX" "$MATRIX" <<'PYPARSE'
import csv, hashlib, os, sys

tag, bin_path, run_root, wall0318, meanvx_max, matrix = sys.argv[1:]
meanvx_max = float(meanvx_max)
summary = os.path.join(run_root, "output", "summary_runtime.csv")

with open(summary, newline="", errors="replace") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

if not rows:
    print(f"ORACLE_FAIL tag={tag} reason=no_summary_rows run_root={run_root}")
    sys.exit(2)

r = rows[-1]

def f(name, default="nan"):
    return r.get(name, default)

def ff(name):
    try:
        return float(f(name))
    except Exception:
        return float("nan")

def ii(name):
    try:
        return int(float(f(name)))
    except Exception:
        return -999999

step = ii("step")
time = ff("time")
meanVx = ff("meanVx")
meanVy = ff("meanVy")
hitsBottom = ii("hitsBottom")
hitsTop = ii("hitsTop")
maxY = ii("maxYWallReflectionsPerParticle")
hitsImmersed = ii("hitsImmersed")

reasons = []
if hitsBottom <= 0:
    reasons.append("hitsBottom<=0")
if hitsTop <= 0:
    reasons.append("hitsTop<=0")
if hitsImmersed <= 0:
    reasons.append("hitsImmersed<=0")
if not (meanVx < meanvx_max):
    reasons.append(f"meanVx>={meanvx_max}")

verdict = "PASS" if not reasons else "FAIL"

sha = ""
try:
    h = hashlib.sha256()
    with open(bin_path, "rb") as bf:
        for chunk in iter(lambda: bf.read(1024 * 1024), b""):
            h.update(chunk)
    sha = h.hexdigest()
except Exception:
    sha = "NA"

fields = [
    "tag","verdict","step","time","meanVx","meanVy",
    "hitsBottom","hitsTop","maxYWallReflectionsPerParticle","hitsImmersed",
    "wallCircle0318","bin","bin_sha256","run_root","reasons"
]
values = [
    tag, verdict, str(step), repr(time), repr(meanVx), repr(meanVy),
    str(hitsBottom), str(hitsTop), str(maxY), str(hitsImmersed),
    wall0318, bin_path, sha, run_root, ";".join(reasons)
]

new_file = not os.path.exists(matrix)
os.makedirs(os.path.dirname(matrix) or ".", exist_ok=True)
with open(matrix, "a", newline="") as mf:
    w = csv.writer(mf, delimiter="\t")
    if new_file:
        w.writerow(fields)
    w.writerow(values)

print("\t".join(fields))
print("\t".join(values))
PYPARSE

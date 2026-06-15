#!/usr/bin/env bash
set -euo pipefail

# Portable CUDA SRC/MPCD + split-safe post-SRC resampling demo (updated 0337 live-visualization checkpoint).
# This script is self-contained: it does not source any repository demo helper.
# It generates its own initial .smpcd state, writes its own .kv parameters, sets
# CUDA/resampling environment flags explicitly, and launches the selected binary.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_livevis_0337d}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
AUTO_BUILD="${AUTO_BUILD:-1}"
THREADS="${THREADS:-12}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
RUN_MODES="${RUN_MODES:-classic resampling}"   # set to "classic resampling" to compare to resampling

# Compact output defaults: fluid-only dumps are lighter and suitable for most
# visual post-processing.  Set DUMP_ROLE_FILTER=all for restart-compatible dumps
# or to inspect inactive slots explicitly.
DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"
SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"


# 0337 live visualization defaults. These are explicit so the demo scripts are
# self-documenting and can be overridden from the environment.
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-vorticity}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-1200}"
LIVE_VIS_NY="${LIVE_VIS_NY:-320}"
LIVE_VIS_ALPHA="${LIVE_VIS_ALPHA:-0.08}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--20}"
LIVE_VIS_QUANTILE="${LIVE_VIS_QUANTILE:-0.995}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-0.5}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-10}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_VSYNC="${LIVE_VIS_VSYNC:-0}"
LIVE_VIS_LOG_SOURCE="${LIVE_VIS_LOG_SOURCE:-1}"
LIVE_VIS_CUDA_FIELD="${LIVE_VIS_CUDA_FIELD:-1}"
LIVE_VIS_CUDA_SNAPSHOT="${LIVE_VIS_CUDA_SNAPSHOT:-0}"
LIVE_VIS_RESAMPLING_HOST_MIRROR="${LIVE_VIS_RESAMPLING_HOST_MIRROR:-0}"
LIVE_VIS_FORCE_HOST_MIRROR="${LIVE_VIS_FORCE_HOST_MIRROR:-0}"

portable_bool_true_0315() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

portable_thermostat_kv_0315() {
  if portable_bool_true_0315 "${THERMOSTAT_ENABLE:-1}"; then printf 'true'; else printf 'false'; fi
}

portable_livevis_env_0337() {
  local mode=${1:-resampling}
  export SRC_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
  export SRC_LIVE_VIS_FIELD="$LIVE_VIS_FIELD"
  export SRC_LIVE_VIS_EVERY="$LIVE_VIS_EVERY"
  export SRC_LIVE_VIS_NX="$LIVE_VIS_NX"
  export SRC_LIVE_VIS_NY="$LIVE_VIS_NY"
  export SRC_LIVE_VIS_ALPHA="$LIVE_VIS_ALPHA"
  export SRC_LIVE_VIS_CLIP="$LIVE_VIS_CLIP"
  export SRC_LIVE_VIS_QUANTILE="$LIVE_VIS_QUANTILE"
  export SRC_LIVE_VIS_GAIN="$LIVE_VIS_GAIN"
  export SRC_LIVE_VIS_SMOOTH_PASSES="$LIVE_VIS_SMOOTH_PASSES"
  export SRC_LIVE_VIS_WINDOW_SCALE="$LIVE_VIS_WINDOW_SCALE"
  export SRC_LIVE_VIS_VSYNC="$LIVE_VIS_VSYNC"
  export SRC_LIVE_VIS_LOG_SOURCE="$LIVE_VIS_LOG_SOURCE"
  export SRC_LIVE_VIS_CUDA_FIELD="$LIVE_VIS_CUDA_FIELD"
  export SRC_LIVE_VIS_CUDA_SNAPSHOT="$LIVE_VIS_CUDA_SNAPSHOT"
  export SRC_LIVE_VIS_FORCE_HOST_MIRROR="$LIVE_VIS_FORCE_HOST_MIRROR"
  if [[ "$mode" == "resampling" ]]; then
    export SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR="$LIVE_VIS_RESAMPLING_HOST_MIRROR"
  else
    export SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=0
  fi
}


portable_ensure_binary_0315() {
  if [[ -x "$BIN" && "$FORCE_REBUILD" != "1" && "$FORCE_REBUILD" != "true" && "$FORCE_REBUILD" != "TRUE" ]]; then
    return 0
  fi
  if ! portable_bool_true_0315 "$AUTO_BUILD"; then
    echo "[0315-portable] missing binary: $BIN" >&2
    exit 127
  fi
  local helper=""
  for h in scripts/build_src_mpcd_cuda_0315b.sh scripts/build_src_mpcd_cuda_0314.sh scripts/build_src_mpcd_cuda_0308.sh scripts/build_src_mpcd_cuda_0313.sh scripts/build_src_mpcd_cuda_0307.sh scripts/build_src_mpcd_cuda_0306.sh scripts/build_src_mpcd_cuda_0305.sh scripts/build_src_mpcd_cuda_0303.sh; do
    if [[ -f "$h" ]]; then helper="$h"; break; fi
  done
  if [[ -z "$helper" ]]; then
    echo "[0315-portable] no CUDA build helper found" >&2
    exit 127
  fi
  echo "[0315-portable] building $BIN with $helper"
  MPCD_ENABLE_LIVE_VIS="${MPCD_ENABLE_LIVE_VIS:-1}" OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash "$helper"
  [[ -x "$BIN" ]] || { echo "[0315-portable] build did not create $BIN" >&2; exit 127; }
}

portable_prepare_dirs_0315() {
  local run_root=$1
  if portable_bool_true_0315 "$CLEAN_RUN_ROOT"; then rm -rf "$run_root"; fi
  mkdir -p "$run_root/init" "$run_root/params" "$run_root/logs" "$run_root/output" "$run_root/analysis"
}

portable_generate_state_0315() {
  local output=$1 Lx=$2 Ly=$3 Nx=$4 Ny=$5 gamma=$6 kBT=$7 seed=$8 mode=$9 mean_ux=${10} mean_uy=${11} amp=${12} active_x_min=${13} active_x_max=${14} active_y_min=${15} active_y_max=${16} inactive_slots=${17} hole_spec=${18}
  shift 18
  python3 - "$output" "$Lx" "$Ly" "$Nx" "$Ny" "$gamma" "$kBT" "$seed" "$mode" "$mean_ux" "$mean_uy" "$amp" "$active_x_min" "$active_x_max" "$active_y_min" "$active_y_max" "$inactive_slots" "$hole_spec" "$@" <<'PYGEN'
import math, os, random, struct, sys
(out,Lx,Ly,Nx,Ny,gamma,kBT,seed,mode,mean_ux,mean_uy,amp,ax0,ax1,ay0,ay1,inactive_slots,hole_spec,*solid_specs)=sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny); gamma=int(gamma); kBT=float(kBT); seed=int(seed)
mean_ux=float(mean_ux); mean_uy=float(mean_uy); amp=float(amp)
ax0=float(ax0); ax1=float(ax1); ay0=float(ay0); ay1=float(ay1); inactive_slots=int(inactive_slots)
if ax1 < 0.0: ax1=Lx
if ay1 < 0.0: ay1=Ly
hole=None
if hole_spec and hole_spec != 'none':
    kind,payload=(hole_spec.split(':',1) if ':' in hole_spec else ('rect',hole_spec))
    vals=[float(v) for v in payload.replace(',', ' ').split()]
    if kind.lower() not in ('rect','rectangle') or len(vals)!=4:
        raise SystemExit(f'invalid hole spec: {hole_spec}')
    hole=tuple(vals)
rects=[]; circles=[]
for spec in solid_specs:
    if not spec or spec == 'none':
        continue
    kind,payload=(spec.split(':',1) if ':' in spec else ('rect',spec))
    vals=[float(v) for v in payload.replace(',', ' ').split()]
    kind=kind.strip().lower()
    if kind in ('rect','rectangle','box','step'):
        if len(vals)!=4: raise SystemExit(f'invalid rectangle spec: {spec}')
        xmin,xmax,ymin,ymax=vals
        if not (xmax>xmin and ymax>ymin): raise SystemExit(f'invalid rectangle bounds: {spec}')
        rects.append((xmin,xmax,ymin,ymax))
    elif kind in ('circle','disk','disc','cylinder'):
        if len(vals)!=3: raise SystemExit(f'invalid circle spec: {spec}')
        cx,cy,r=vals
        if r<=0.0: raise SystemExit(f'invalid circle radius: {spec}')
        circles.append((cx,cy,r))
    else:
        raise SystemExit(f'unsupported solid spec: {spec}')

def in_solid(x,y):
    for xmin,xmax,ymin,ymax in rects:
        if xmin <= x <= xmax and ymin <= y <= ymax: return True
    for cx,cy,r in circles:
        if (x-cx)*(x-cx)+(y-cy)*(y-cy) <= r*r: return True
    return False

def in_hole(x,y):
    if hole is None: return False
    x0,x1,y0,y1=hole
    return x0 <= x <= x1 and y0 <= y <= y1

def base_velocity(x,y):
    if mode == 'zero': return 0.0,0.0
    if mode == 'uniform': return mean_ux,mean_uy
    if mode == 'taylor_green':
        ux=amp*math.sin(2*math.pi*x/Lx)*math.cos(2*math.pi*y/Ly)
        uy=-amp*math.cos(2*math.pi*x/Lx)*math.sin(2*math.pi*y/Ly)
        return ux+mean_ux,uy+mean_uy
    if mode == 'poiseuille_x':
        yc=0.5*(ay0+ay1); half=max(1e-15,0.5*(ay1-ay0)); eta=(y-yc)/half
        return mean_ux*max(0.0,1.0-eta*eta),mean_uy
    raise SystemExit(f'unsupported flow mode: {mode}')

rng=random.Random(seed)
dx=Lx/Nx; dy=Ly/Ny; mass0=1.0; sigma=math.sqrt(kBT/mass0) if kBT>0 else 0.0
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
active_cells=0; skipped_cells=0; rejected=0; deactivated=0
for j in range(Ny):
    cy=(j+0.5)*dy
    for i in range(Nx):
        cx=(i+0.5)*dx
        if cx < ax0 or cx > ax1 or cy < ay0 or cy > ay1 or in_solid(cx,cy):
            skipped_cells += 1; continue
        active_cells += 1
        x0=i*dx; y0=j*dy
        for _ in range(gamma):
            ok=False
            for _try in range(1000):
                xp=x0+dx*rng.random(); yp=y0+dy*rng.random()
                if xp < ax0 or xp > ax1 or yp < ay0 or yp > ay1 or in_solid(xp,yp):
                    rejected += 1; continue
                ok=True; break
            if not ok: continue
            ux,uy=base_velocity(xp,yp)
            if sigma>0:
                ux += sigma*rng.gauss(0.0,1.0); uy += sigma*rng.gauss(0.0,1.0)
            r=1
            if in_hole(xp,yp):
                r=0; deactivated += 1
            x.append(xp); y.append(yp); vx.append(ux); vy.append(uy); typ.append(0); mass.append(mass0); role.append(r)
# Remove net drift among active fluid particles only.
fluid_mass=sum(m for m,r in zip(mass,role) if r==1)
if fluid_mass>0:
    mvx=sum(m*u for m,u,r in zip(mass,vx,role) if r==1)/fluid_mass
    mvy=sum(m*v for m,v,r in zip(mass,vy,role) if r==1)/fluid_mass
    tvx=mean_ux if mode in ('uniform','poiseuille_x') else 0.0
    tvy=mean_uy if mode in ('uniform','poiseuille_x') else 0.0
    for i,r in enumerate(role):
        if r==1:
            vx[i]=vx[i]-mvx+tvx; vy[i]=vy[i]-mvy+tvy
# Append reservoir inactive slots at a harmless point; they are slots, not fluid.
slot_x=max(0.0,min(Lx,ax0)); slot_y=max(0.0,min(Ly,ay0))
for _ in range(inactive_slots):
    x.append(slot_x); y.append(slot_y); vx.append(0.0); vy.append(0.0); typ.append(0); mass.append(mass0); role.append(0)
os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE'))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
n=len(x)
with open(out,'wb') as f:
    f.write(magic)
    f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4))
    f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in [(x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')]:
        f.write(struct.pack('<%d%s'%(n,fmt),*arr))
fluid=sum(1 for r in role if r==1); inactive=sum(1 for r in role if r==0)
print(f'[0315-state] output={out} grid={Nx}x{Ny} activeCells={active_cells} skippedCells={skipped_cells} fluid={fluid} inactive={inactive} holeInactive={deactivated} rejected={rejected}')
PYGEN
}

portable_write_common_params_0315() {
  local steps=$1 dt=$2 kbt=$3 seed=$4 summary_every=$5 dump_every=$6 threads=$7 rotation_angle=${8:-1.5}
  cat <<PARAMS
nSteps = ${steps}
dt = ${dt}
rotationAngle = ${rotation_angle}
randomRotationSign = true
gridShiftEnable = true
rngSeed = ${seed}

srcClassicCudaModeEnable = true
projectionEnable = false
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false

thermostatEnable = $(portable_thermostat_kv_0315)
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = ${kbt}

summaryEvery = ${summary_every}
dumpStateEvery = ${dump_every}
summaryRoleFilter = ${SUMMARY_ROLE_FILTER}
dumpRoleFilter = ${DUMP_ROLE_FILTER}
numThreads = ${threads}
PARAMS
}

portable_cuda_clear_0315() {
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0
  export MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=0
  export MPCD_CUDA_STREAMING_PERIODIC_0245=0
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247=0
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=0
  export MPCD_CUDA_IMMERSED_CIRCLE_0284=0
  export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
  export MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0
  export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
  export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"
  # 0318b/0319/0320/0321/0327b/0330b fast-path flags are opt-in per mode.
  # Keep 0325 and 0329 disabled: both were measured as regressions and rolled back.
  export MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=0
  export MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=0
  export MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSE_WALL_FINALIZE_ROTATION_0325=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ROTATION_TABLE_CACHE_0329=0
  export MPCD_CUDA_INACTIVE_TAIL_POOL_0313="${MPCD_CUDA_INACTIVE_TAIL_POOL_0313:-1}"
}

portable_cuda_enable_thermostat_0315() {
  local shared=${1:-0}
  if portable_bool_true_0315 "${THERMOSTAT_ENABLE:-1}"; then
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="$shared"
  else
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  fi
}

portable_cuda_classic_fast_flags_0330b() {
  # Validated checkpoint for SRC classic CUDA resident performance:
  #   keep 0318b/0319/0320/0321/0322/0327b/0330b;
  #   keep 0324 optional but off by default;
  #   keep rejected 0325/0329 disabled.
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319="${SRC_GPU_SKIP_WALL_VP_DIAG_0319:-1}"
  export MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM="${SRC_GPU_ASYNC_STREAM_0320:-1}"
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS="${SRC_GPU_WALL_FAST_DIAG_0320:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321="${SRC_GPU_FAST_THERMOSTAT_DIAG_0321:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272="${SRC_GPU_DEVICE_ROTATION_0322:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273="${SRC_GPU_LAZY_KERNEL_CHECK_0322:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273="${SRC_GPU_SKIP_SETUP_SYNC_0322:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327="${SRC_GPU_SKIP_HOST_CELLID_FILL_0327:-1}"
  export MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330="${SRC_GPU_IMMERSED_CIRCLE_FAST_DIAG_0330:-1}"

  # Explicitly disable rejected experiments unless the user deliberately overrides
  # the low-level MPCD_CUDA_* variables after this helper.
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSE_WALL_FINALIZE_ROTATION_0325=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ROTATION_TABLE_CACHE_0329=0
}


portable_cuda_periodic_0315() {
  portable_cuda_clear_0315
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
  portable_cuda_enable_thermostat_0315 1
  portable_cuda_classic_fast_flags_0330b
}

portable_cuda_wall_0315() {
  portable_cuda_clear_0315
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  portable_cuda_enable_thermostat_0315 0
  portable_cuda_classic_fast_flags_0330b
}

portable_cuda_io_fullface_rect_0315() {
  portable_cuda_clear_0315
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=1
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247=1
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=1
  portable_cuda_enable_thermostat_0315 1
  portable_cuda_classic_fast_flags_0330b
}

portable_cuda_io_segmented_0315() {
  portable_cuda_clear_0315
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  portable_cuda_enable_thermostat_0315 1
  portable_cuda_classic_fast_flags_0330b
}

portable_cuda_io_fullface_circle_0315() {
  portable_cuda_clear_0315
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=1
  export MPCD_CUDA_IMMERSED_CIRCLE_0284=1
  export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1
  portable_cuda_enable_thermostat_0315 1
  portable_cuda_classic_fast_flags_0330b
}

portable_cuda_periodic_circle_0315() {
  portable_cuda_clear_0315
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0
  export MPCD_CUDA_IMMERSED_CIRCLE_0284=1
  export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1
  portable_cuda_enable_thermostat_0315 0
  portable_cuda_classic_fast_flags_0330b
  export MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318="${SRC_GPU_WALL_CIRCLE_RESIDENT_0318:-1}"
}

portable_resampling_env_0315() {
  local mode=$1
  local survey="${RESAMPLING_SURVEY_ENABLE:-1}"
  export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295="$survey"
  export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="${RESAMPLING_SURVEY_EVERY:-${SUMMARY_EVERY:-100}}"
  export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE="${MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE:-full}"
  export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304:-1}"
  export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY:-${FLAG_EVERY:-50}}"
  export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN:-6}"
  export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY:-1}"
  export MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U="${MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U:-1.0}"
  export MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD="${MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD:-1.0}"

  if [[ "$mode" == "resampling" ]]; then
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296="${MASS_RECONDITION_ENABLE:-1}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY="${MASS_RECONDITION_EVERY:-${GUARD_EVERY:-5}}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH="${MASS_RECONDITION_STRENGTH:-1.0}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="${GUARD_EVERY:-5}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="${GUARD_NMIN:-3}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="${GUARD_NTARGET:-6}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="${GUARD_NMAX:-9}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION="${GUARD_SPLIT_FRACTION:-0.5}"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="${RESTORE_ENABLE:-1}"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE="${RESTORE_MAX_SCALE:-4.0}"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_ABS_TOL="${RESTORE_ABS_TOL:-1e-14}"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_REL_TOL="${RESTORE_REL_TOL:-1e-12}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="${BOUNDARY_AWARE:-1}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS="${OPEN_BOUNDARY_HALO_CELLS:-1}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS="${BOUNDARY_HALO_CELLS:-0}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS="${SOLID_HALO_CELLS:-0}"
    export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307="${MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307:-1}"
    export MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307="${MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307:-1}"
    export MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307="${MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307:-0.5}"
    export MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307="${MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307:-0.25}"
    export MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307="${MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307:-0}"
  else
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298=0
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE=0
    export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=0
  fi
}

portable_write_env_file_0315() {
  local file=$1 mode=$2
  mkdir -p "$(dirname "$file")"
  env | grep -E '^(MPCD_CUDA_|SRC_GPU_|SRC_LIVE_VIS_|MPCD_ENABLE_LIVE_VIS=|OMP_|BIN=|THREADS=|RUN_MODES=|DUMP_ROLE_FILTER=|SUMMARY_ROLE_FILTER=|LIVE_VIS_)' | sort > "$file"
  cat >> "$file" <<META
mode=${mode}
GUARD_EVERY=${GUARD_EVERY:-5}
GUARD_NMIN=${GUARD_NMIN:-12}
GUARD_NTARGET=${GUARD_NTARGET:-20}
GUARD_NMAX=${GUARD_NMAX:-32}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-unset}
META
}

portable_run_binary_0315() {
  local params=$1 log=$2 time=$3 out_dir=$4
  portable_ensure_binary_0315
  echo "[0315-portable] binary : $BIN"
  echo "[0337-portable] checkpoint: 0334a resident classic + 0337 CUDA live field renderer"
  echo "[0315-portable] params : $params"
  echo "[0315-portable] output : $out_dir"
  local rc=0
  if portable_bool_true_0315 "$LIVE_PROGRESS"; then
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" 2> "$time" | tee "$log" || rc=$?
  else
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" > "$log" 2> "$time" || rc=$?
  fi
  if [[ "$rc" != "0" ]]; then
    echo "[0315-portable] ERROR: binary failed rc=$rc" >&2
    tail -80 "$time" >&2 || true
    tail -80 "$log" >&2 || true
    return "$rc"
  fi
  echo "[0315-portable] completed"
}

portable_mode_root_0315() {
  local base=$1 mode=$2
  if [[ "$mode" == "classic" ]]; then printf '%s/classic' "$base"; else printf '%s/resampling_split_safe' "$base"; fi
}

CASE_NAME="von_karman_cylinder_0315"
VK_MODE="${VK_MODE:-io}"   # io | periodic
Lx="${Lx:-0.8}"; Ly="${Ly:-0.4}"; NX="${NX:-640}"; NY="${NY:-640}"
GAMMA="${GAMMA:-6}"; STEPS="${STEPS:-500}"; DT="${DT:-0.0005}"; KBT="${KBT:-0.5}"
SEED="${SEED:-1628505}"; SUMMARY_EVERY="${SUMMARY_EVERY:-1000}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
UIN="${UIN:-0.45}"; UINIT="${UINIT:-0.45}"; THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-1}"
CYLINDER_CX="${CYLINDER_CX:-0.1}"; CYLINDER_CY="${CYLINDER_CY:-0.205}"; CYLINDER_R="${CYLINDER_R:-0.04}"
OUTLET_MODE="${OUTLET_MODE:-equilibrium_flux}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-00}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/VK_classic_small_time}"
run_mode_0315() {
  local mode=$1 run_root; run_root=$(portable_mode_root_0315 "$BASE_RUN_ROOT/${VK_MODE}" "$mode")
  portable_prepare_dirs_0315 "$run_root"
  local state="$run_root/init/${CASE_NAME}_${VK_MODE}_${NX}x${NY}_g${GAMMA}.smpcd" params="$run_root/params/${CASE_NAME}_${VK_MODE}.kv" out="$run_root/output" log="$run_root/logs/${CASE_NAME}_${VK_MODE}.log" time="$run_root/logs/${CASE_NAME}_${VK_MODE}.time"
  local flow_u="$UINIT"
  if [[ "$VK_MODE" == "periodic" ]]; then flow_u="$UIN"; fi
  portable_generate_state_0315 "$state" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" uniform "$flow_u" 0.0 0.0 0.0 -1.0 0.0 -1.0 "$INACTIVE_SLOTS" none "circle:${CYLINDER_CX},${CYLINDER_CY},${CYLINDER_R}"
  if [[ "$VK_MODE" == "periodic" ]]; then
    cat > "$params" <<PARAMS
inputState = ${state}
outputDir = ${out}
Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}
bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid
bodyAccelerationX = 0.000005
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
$(portable_write_common_params_0315 "$STEPS" "$DT" "$KBT" "$SEED" "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$THREADS" 1.5)
PARAMS
    portable_cuda_periodic_circle_0315
  else
    cat > "$params" <<PARAMS
inputState = ${state}
outputDir = ${out}
Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}
bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
keepMeanFlowEnable = false
inletUxLeft = ${UIN}
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.05
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = flat_taper_y
inletVelocityWallTaperCells = 2.0
inletKBT = -1.0
inletThermalNoise = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 3
inletTargetOccupancy = ${GAMMA}
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true
openBoundaryOutletMode = ${OUTLET_MODE}
openBoundaryOutletForcedMassFlux = 0.0
openBoundaryOutletForcedMassPerStep = 0.0
openBoundaryOutletForcedParticleFlux = 0.0
openBoundaryOutletForcedParticlesPerStep = 0
openBoundaryOutletForcedLayerCells = 3
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
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
$(portable_write_common_params_0315 "$STEPS" "$DT" "$KBT" "$SEED" "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$THREADS" 1.5)
PARAMS
    portable_cuda_io_fullface_circle_0315
  fi
  portable_resampling_env_0315 "$mode"
  portable_livevis_env_0337 "$mode"
  portable_write_env_file_0315 "$run_root/logs/environment_0315.env" "$mode"
  portable_run_binary_0315 "$params" "$log" "$time" "$out"
}
#for mode in $RUN_MODES; do run_mode_0315 "$mode"; done
run_mode_0315 $RUN_MODES
#cat > "$BASE_RUN_ROOT/visualize_von_karman_0315.m" <<'MATLAB'
# root = 'runs/VK_classic';
# mode = 'io'; % change to 'periodic' if VK_MODE=periodic was used
# resamp = fullfile(root, mode, 'resampling_split_safe', 'output');
# play_smpcd_dumps(resamp, 'field', 'speed', 'frameStride', 2, 'pauseTime', 0.03, ...
#     'showParticles', true, 'particleRoleFilter', 'fluid', 'particleColorMode', 'masslog', ...
#     'particleMassMax', 0.5, 'particleSpeedMin', 1.0, 'particleThresholdLogic', 'or', ...
#     'particleLabelMode', 'mass_speed', 'particleLabelMax', 30, 'particleMarkerSize', 12);
# MATLAB
# echo "[0315-portable] MATLAB helper: $BASE_RUN_ROOT/visualize_von_karman_0315.m"

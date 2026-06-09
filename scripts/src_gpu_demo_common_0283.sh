#!/usr/bin/env bash
# Common helpers for SRC_GPU demo scripts 0283.
# These helpers deliberately run SRC classic only:
#   advection/streaming + random grid shift + SRC rotation/collision + thermostat.
# Q6, resampling, Q9 and virial/capacity closure are explicitly disabled.

set -euo pipefail

src_gpu_demo_root() {
  local src_dir="${BASH_SOURCE[0]}"
  while [[ -L "$src_dir" ]]; do
    src_dir="$(readlink "$src_dir")"
  done
  cd "$(dirname "$src_dir")/.." && pwd
}

ROOT_DIR="${ROOT_DIR:-$(src_gpu_demo_root)}"
cd "$ROOT_DIR"

BIN="${BIN:-build/src_mpcd_base_cuda_0291b}"
THREADS="${THREADS:-8}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

AUTO_BUILD="${AUTO_BUILD:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
# 0291b: one physical switch controls the thermostat in both CPU and CUDA
# paths.  CUDA environment flags may only select the implementation backend.
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-1}"

ensure_src_gpu_demo_binary_0283() {
  if [[ -x "$BIN" ]]; then
    return 0
  fi
  if [[ "$AUTO_BUILD" != "1" && "$AUTO_BUILD" != "true" && "$AUTO_BUILD" != "TRUE" ]]; then
    echo "[0283-demo] missing binary: $BIN" >&2
    exit 127
  fi
  if [[ -f scripts/build_src_mpcd_cuda_0291b.sh ]]; then
    echo "[0283-demo] building $BIN with build_src_mpcd_cuda_0291b.sh"
    OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0291b.sh
  elif [[ -f scripts/build_src_mpcd_cuda_0291.sh ]]; then
    echo "[0283-demo] building $BIN with build_src_mpcd_cuda_0291.sh"
    OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0291.sh
  elif [[ -f scripts/build_src_mpcd_cuda_0288.sh ]]; then
    echo "[0283-demo] building $BIN with build_src_mpcd_cuda_0288.sh"
    OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0288.sh
  elif [[ -f scripts/build_src_mpcd_cuda_0286.sh ]]; then
    echo "[0283-demo] building $BIN with build_src_mpcd_cuda_0286.sh"
    OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0286.sh
  elif [[ -f scripts/build_src_mpcd_cuda_0281.sh ]]; then
    echo "[0283-demo] building $BIN with build_src_mpcd_cuda_0281.sh"
    OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0281.sh
  elif [[ -f scripts/build_src_mpcd_cuda_0275.sh ]]; then
    echo "[0283-demo] building $BIN with build_src_mpcd_cuda_0275.sh"
    OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0275.sh
  elif [[ -f scripts/build_src_mpcd_base.sh ]]; then
    echo "[0283-demo] CUDA build helper unavailable; building CPU binary through build_src_mpcd_base.sh" >&2
    BIN="${BIN:-build/src_mpcd_base}"
    bash scripts/build_src_mpcd_base.sh
  else
    echo "[0283-demo] no known build script found" >&2
    exit 127
  fi
  if [[ ! -x "$BIN" ]]; then
    echo "[0283-demo] build did not create executable: $BIN" >&2
    exit 127
  fi
}

prepare_demo_dirs_0283() {
  local run_root=$1
  if [[ "$CLEAN_RUN_ROOT" == "1" || "$CLEAN_RUN_ROOT" == "true" || "$CLEAN_RUN_ROOT" == "TRUE" ]]; then
    rm -rf "$run_root"
  fi
  mkdir -p "$run_root/init" "$run_root/params" "$run_root/logs" "$run_root/output"
}

generate_demo_state_0283() {
  local output=$1 Lx=$2 Ly=$3 Nx=$4 Ny=$5 gamma=$6 kBT=$7 seed=$8 mode=$9 mean_ux=${10} mean_uy=${11} amp=${12} active_x_min=${13} active_x_max=${14} active_y_min=${15} active_y_max=${16} inactive_slots=${17}
  shift 17
  python3 - "$output" "$Lx" "$Ly" "$Nx" "$Ny" "$gamma" "$kBT" "$seed" "$mode" "$mean_ux" "$mean_uy" "$amp" "$active_x_min" "$active_x_max" "$active_y_min" "$active_y_max" "$inactive_slots" "$@" <<'PY'
import math, os, random, struct, sys
(out,Lx,Ly,Nx,Ny,gamma,kBT,seed,mode,mean_ux,mean_uy,amp,ax0,ax1,ay0,ay1,inactive_slots,*solid_specs)=sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny); gamma=int(gamma); kBT=float(kBT); seed=int(seed)
mean_ux=float(mean_ux); mean_uy=float(mean_uy); amp=float(amp)
ax0=float(ax0); ax1=float(ax1); ay0=float(ay0); ay1=float(ay1); inactive_slots=int(inactive_slots)
if ax1 < 0.0: ax1=Lx
if ay1 < 0.0: ay1=Ly
rects=[]; circles=[]
for spec in solid_specs:
    if not spec or spec == 'none':
        continue
    kind, payload = (spec.split(':',1) if ':' in spec else ('rect', spec))
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
        if xmin <= x <= xmax and ymin <= y <= ymax:
            return True
    for cx,cy,r in circles:
        if (x-cx)*(x-cx)+(y-cy)*(y-cy) <= r*r:
            return True
    return False

def base_velocity(x,y):
    if mode == 'zero': return 0.0, 0.0
    if mode == 'uniform': return mean_ux, mean_uy
    if mode == 'taylor_green':
        ux=amp*math.sin(2*math.pi*x/Lx)*math.cos(2*math.pi*y/Ly)
        uy=-amp*math.cos(2*math.pi*x/Lx)*math.sin(2*math.pi*y/Ly)
        return ux+mean_ux, uy+mean_uy
    if mode == 'poiseuille_x':
        yc=0.5*(ay0+ay1); half=max(1e-15,0.5*(ay1-ay0)); eta=(y-yc)/half
        return mean_ux*max(0.0,1.0-eta*eta), mean_uy
    raise SystemExit(f'unsupported flow mode: {mode}')

rng=random.Random(seed)
dx=Lx/Nx; dy=Ly/Ny; mass0=1.0; sigma=math.sqrt(kBT/mass0) if kBT>0 else 0.0
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
active_cells=0; skipped_cells=0; rejected=0
for j in range(Ny):
    cy=(j+0.5)*dy
    for i in range(Nx):
        cx=(i+0.5)*dx
        if cx < ax0 or cx > ax1 or cy < ay0 or cy > ay1 or in_solid(cx,cy):
            skipped_cells += 1
            continue
        active_cells += 1
        x0=i*dx; y0=j*dy
        for _ in range(gamma):
            ok=False
            for _try in range(1000):
                xp=x0+dx*rng.random(); yp=y0+dy*rng.random()
                if xp < ax0 or xp > ax1 or yp < ay0 or yp > ay1 or in_solid(xp,yp):
                    rejected += 1
                    continue
                ok=True; break
            if not ok:
                continue
            ux,uy=base_velocity(xp,yp)
            if sigma>0:
                ux += sigma*rng.gauss(0.0,1.0); uy += sigma*rng.gauss(0.0,1.0)
            x.append(xp); y.append(yp); vx.append(ux); vy.append(uy); typ.append(0); mass.append(mass0); role.append(1)
if not x:
    raise SystemExit('generated zero particles')
mt=sum(mass); mvx=sum(m*u for m,u in zip(mass,vx))/mt; mvy=sum(m*u for m,u in zip(mass,vy))/mt
tvx=mean_ux if mode in ('uniform','poiseuille_x') else 0.0; tvy=mean_uy if mode in ('uniform','poiseuille_x') else 0.0
vx=[u-mvx+tvx for u in vx]; vy=[v-mvy+tvy for v in vy]
for _ in range(inactive_slots):
    x.append(ax0); y.append(ay0); vx.append(0.0); vy.append(0.0); typ.append(0); mass.append(mass0); role.append(0)
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
print(f'[state] output={out} grid={Nx}x{Ny} activeCells={active_cells} skippedCells={skipped_cells} fluid={n-inactive_slots} inactive={inactive_slots} rejected={rejected}')
PY
}


src_gpu_bool_is_true_0283() {
  local v
  v="$(printf '%s' "${1:-0}" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    1|true|yes|on|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

src_gpu_thermostat_enable_kv_0291b() {
  if src_gpu_bool_is_true_0283 "$THERMOSTAT_ENABLE"; then
    printf 'true'
  else
    printf 'false'
  fi
}

write_src_classic_common_params_0283() {
  local steps=$1 dt=$2 kbt=$3 seed=$4 summary_every=$5 dump_every=$6 threads=$7 rotation_angle=${8:-2.0943951023931953}
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

thermostatEnable = $(src_gpu_thermostat_enable_kv_0291b)
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = ${kbt}

summaryEvery = ${summary_every}
dumpStateEvery = ${dump_every}
dumpRoleFilter = ${DUMP_ROLE_FILTER:-all}
summaryRoleFilter = ${SUMMARY_ROLE_FILTER:-all}
numThreads = ${threads}
PARAMS
}

run_demo_case_0283() {
  local params_file=$1 log_file=$2 time_file=$3 out_dir=$4
  ensure_src_gpu_demo_binary_0283
  echo "[0283-demo] binary : $BIN"
  echo "[0283-demo] params : $params_file"
  echo "[0283-demo] output : $out_dir"
  local rc=0
  if [[ "$LIVE_PROGRESS" == "1" || "$LIVE_PROGRESS" == "true" || "$LIVE_PROGRESS" == "TRUE" ]]; then
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params_file" 2> "$time_file" | tee "$log_file" || rc=$?
  else
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params_file" > "$log_file" 2> "$time_file" || rc=$?
  fi
  if [[ -s "$time_file" ]]; then
    cat "$time_file"
  fi
  if [[ "$rc" != "0" ]]; then
    echo "[0283-demo] ERROR: run failed with exit code $rc" >&2
    echo "[0283-demo] stderr/time tail: $time_file" >&2
    tail -80 "$time_file" >&2 || true
    echo "[0283-demo] stdout/log tail: $log_file" >&2
    tail -80 "$log_file" >&2 || true
    echo "[0283-demo] params head: $params_file" >&2
    sed -n '1,120p' "$params_file" >&2 || true
    exit "$rc"
  fi
  if [[ ! -s "$out_dir/summary_runtime.csv" ]]; then
    echo "[0283-demo] ERROR: missing runtime summary after successful process: $out_dir/summary_runtime.csv" >&2
    echo "[0283-demo] stdout/log tail: $log_file" >&2
    tail -80 "$log_file" >&2 || true
    exit 2
  fi
  local dump_count=0
  dump_count=$(find "$out_dir" -maxdepth 1 -name 'state_step_*.smpcd' -type f | wc -l | tr -d ' ')
  if [[ "$dump_count" == "0" ]]; then
    echo "[0283-demo] ERROR: no animation dumps found in $out_dir" >&2
    echo "[0283-demo] check dumpStateEvery in $params_file" >&2
    exit 3
  fi
  echo "[0283-demo] summary: $out_dir/summary_runtime.csv"
  echo "[0283-demo] dumps  : $out_dir/state_step_*.smpcd ($dump_count files)"
}

src_gpu_cuda_env_clear_0283() {
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0
  export MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=0
  export MPCD_CUDA_STREAMING_PERIODIC_0245=0
  export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=1
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=1
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247=0
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=1
  export MPCD_CUDA_STREAMING_PISTON_0247B=0
  export MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0
  export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0
  export MPCD_CUDA_CELL_MOMENTS_USE=0
  export MPCD_CUDA_THERMOSTAT_USE=0
  export MPCD_CUDA_THERMOSTAT_PERSISTENT_0258=0
  export MPCD_CUDA_SRC_COLLISION_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=0
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=0
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=0
  export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"
  export MPCD_CUDA_RESAMPLING_EXTRACTION_USE=0
  export MPCD_CUDA_RESAMPLING_INSERTION_USE=0
  export MPCD_CUDA_RESAMPLING_PERSISTENT_0240=0
}


src_gpu_cuda_env_enable_src_thermostat_0291b() {
  # Argument: 1 means the caller wants the shared 0251->0260 fused consumer;
  # 0 means a post-boundary persistent thermostat backend without shared fused
  # consumption.  In both cases, THERMOSTAT_ENABLE=false disables the backend.
  local shared_requested="${1:-0}"
  if src_gpu_bool_is_true_0283 "$THERMOSTAT_ENABLE"; then
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
    if [[ "$shared_requested" == "1" ]]; then
      export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
    else
      export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
    fi
  else
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  fi
}

src_gpu_cuda_env_periodic_resident_thermostat_0283() {
  src_gpu_cuda_env_clear_0283
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
  src_gpu_cuda_env_enable_src_thermostat_0291b 1
}

src_gpu_cuda_env_wall_resident_thermostat_0283() {
  src_gpu_cuda_env_clear_0283
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  src_gpu_cuda_env_enable_src_thermostat_0291b 0
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
}

src_gpu_cuda_env_io_fullface_resident_thermostat_0283() {
  src_gpu_cuda_env_clear_0283
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=1
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247=1
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=1
  src_gpu_cuda_env_enable_src_thermostat_0291b 1
}

src_gpu_cuda_env_io_segmented_resident_thermostat_0283() {
  src_gpu_cuda_env_clear_0283
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  src_gpu_cuda_env_enable_src_thermostat_0291b 1
}

src_gpu_cuda_env_circle_boundary_cpu_collision_cuda_0283() {
  # The current CUDA immersed-solid fast path is rectangle-specific.  This mode
  # leaves circular immersed-solid reflection on the validated CPU path, then
  # applies persistent CUDA SRC collision and CUDA thermostat.
  src_gpu_cuda_env_clear_0283
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=0
  src_gpu_cuda_env_enable_src_thermostat_0291b 0
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
}

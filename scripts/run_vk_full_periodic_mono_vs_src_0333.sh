#!/usr/bin/env bash
set -euo pipefail

# 0333: monolithic VK/KH CUDA code vs SRC_GPU full-periodic VK benchmark.
# Goal: compare pure-step time at matched geometry, particle count, thermostat,
# rotation angle, and disabled heavy outputs.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bool_true_0333() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac
}

ART_DIR="${ART_DIR:-dev_history/artifacts/vk_mono_vs_src_0333_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$ART_DIR"

# Shared physics/geometry. Defaults mirror the attached mpcd_vkkh_play.cu VK defaults.
Lx="${Lx:-1.5}"
Ly="${Ly:-0.4}"
NX="${NX:-360}"
NY="${NY:-19}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-5000}"
DT="${DT:-0.0005}"
KBT="${KBT:-5}"
U0="${U0:-0.051}"
SEED="${SEED:-1628505}"
ALPHA_DEG="${ALPHA_DEG:-90}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-1}"
KEEP_MEAN_FLOW_ENABLE="${KEEP_MEAN_FLOW_ENABLE:-false}"
CX="${CX:-0.25}"
CY="${CY:-0.205}"
RC="${RC:-0.04}"
THREADS="${THREADS:-8}"
REPS="${REPS:-3}"
INACTIVE_SLOTS_RESAMPLING="${INACTIVE_SLOTS_RESAMPLING:-750000}"
INCLUDE_CLASSIC_INACTIVE="${INCLUDE_CLASSIC_INACTIVE:-1}"
RUN_MONO_SOLID_DEFAULT="${RUN_MONO_SOLID_DEFAULT:-0}"

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

SRC_BIN="${SRC_BIN:-build/src_mpcd_base_cuda_vkbench_0333}"
MONO_SRC="${MONO_SRC:-external_benchmarks/mpcd_vkkh_play_timed_0333.cu}"
MONO_BIN="${MONO_BIN:-build/mpcd_vkkh_play_timed_0333}"
AUTO_BUILD_SRC="${AUTO_BUILD_SRC:-0}"
AUTO_BUILD_MONO="${AUTO_BUILD_MONO:-1}"
FORCE_REBUILD_SRC="${FORCE_REBUILD_SRC:-0}"
FORCE_REBUILD_MONO="${FORCE_REBUILD_MONO:-0}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}"

write_manifest_0333() {
  {
    echo "branch=$(git branch --show-current 2>/dev/null || echo unknown)"
    echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "src_bin=$SRC_BIN"
    if [[ -x "$SRC_BIN" ]]; then sha256sum "$SRC_BIN" | sed 's/^/src_bin_sha256=/' ; else echo "src_bin_sha256=MISSING"; fi
    echo "mono_src=$MONO_SRC"
    echo "mono_bin=$MONO_BIN"
    if [[ -x "$MONO_BIN" ]]; then sha256sum "$MONO_BIN" | sed 's/^/mono_bin_sha256=/' ; else echo "mono_bin_sha256=MISSING"; fi
    echo "Lx=$Lx"
    echo "Ly=$Ly"
    echo "NX=$NX"
    echo "NY=$NY"
    echo "GAMMA=$GAMMA"
    echo "STEPS=$STEPS"
    echo "DT=$DT"
    echo "KBT=$KBT"
    echo "U0=$U0"
    echo "SEED=$SEED"
    echo "ALPHA_DEG=$ALPHA_DEG"
    echo "ROTATION_ANGLE=$ROTATION_ANGLE"
    echo "THERMOSTAT_ENABLE=$THERMOSTAT_ENABLE"
    echo "KEEP_MEAN_FLOW_ENABLE=$KEEP_MEAN_FLOW_ENABLE"
    echo "CX=$CX"
    echo "CY=$CY"
    echo "RC=$RC"
    echo "REPS=$REPS"
    echo "INACTIVE_SLOTS_RESAMPLING=$INACTIVE_SLOTS_RESAMPLING"
    echo "date=$(date --iso-8601=seconds)"
  } > "$ART_DIR/manifest.txt"
}

build_src_if_needed_0333() {
  if [[ -x "$SRC_BIN" && ! "$FORCE_REBUILD_SRC" =~ ^(1|true|TRUE)$ ]]; then return 0; fi
  if ! bool_true_0333 "$AUTO_BUILD_SRC"; then
    echo "[0333] missing SRC binary: $SRC_BIN" >&2
    echo "[0333] build it first, or set AUTO_BUILD_SRC=1" >&2
    exit 127
  fi
  local helper=""
  for h in scripts/build_src_mpcd_cuda_0315b.sh scripts/build_src_mpcd_cuda_0314.sh scripts/build_src_mpcd_cuda_0308.sh scripts/build_src_mpcd_cuda_0307.sh; do
    if [[ -f "$h" ]]; then helper="$h"; break; fi
  done
  [[ -n "$helper" ]] || { echo "[0333] no SRC CUDA build helper found" >&2; exit 127; }
  echo "[0333] building SRC binary $SRC_BIN with $helper"
  OUT="$SRC_BIN" CUDA_ARCH_FLAGS="$CUDA_ARCH_FLAGS" bash "$helper"
}

build_mono_if_needed_0333() {
  if [[ -x "$MONO_BIN" && ! "$FORCE_REBUILD_MONO" =~ ^(1|true|TRUE)$ ]]; then return 0; fi
  if ! bool_true_0333 "$AUTO_BUILD_MONO"; then
    echo "[0333] missing monolithic binary: $MONO_BIN" >&2
    exit 127
  fi
  [[ -f "$MONO_SRC" ]] || { echo "[0333] missing monolithic source: $MONO_SRC" >&2; exit 127; }
  mkdir -p "$(dirname "$MONO_BIN")"
  echo "[0333] building monolithic $MONO_BIN"
  nvcc -O3 -std=c++17 ${CUDA_ARCH_FLAGS} -Xcompiler -fopenmp "$MONO_SRC" -o "$MONO_BIN"
}

src_generate_state_0333() {
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
# Match monolithic initialization: remove drift and impose target mean U0,0.
mx=sum(vx)/len(vx); my=sum(vy)/len(vy)
for i in range(len(vx)):
    vx[i]=vx[i]-mx+U0
    vy[i]=vy[i]-my
# Inactive reservoir slots are storage only.
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
print(f'[0333-state] output={out} fluid={n_active} inactive={inactive_slots} total={n} rejectedCylinder={rejected}')
PYGEN
}

src_write_params_0333() {
  local params=$1 state=$2 out=$3 mode=$4
  local resampling_enable="false"
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

thermostatEnable = $(if bool_true_0333 "$THERMOSTAT_ENABLE"; then echo true; else echo false; fi)
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

src_cuda_clear_0333() {
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0
  export MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
  export MPCD_CUDA_STREAMING_PERIODIC_0245=0
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
  export MPCD_CUDA_IMMERSED_CIRCLE_0284=0
  export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
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
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
  export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"
  export MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318_UNSAFE_ENABLE=0
  export SRC_GPU_WALL_CIRCLE_RESIDENT_0318=0
  export MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM="${SRC_GPU_ASYNC_STREAM_0320:-1}"
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
  export MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSE_WALL_FINALIZE_ROTATION_0325=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ROTATION_TABLE_CACHE_0329=0
}

src_cuda_enable_classic_periodic_circle_0333() {
  src_cuda_clear_0333
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
  export MPCD_CUDA_IMMERSED_CIRCLE_0284=1
  export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1
  if bool_true_0333 "$THERMOSTAT_ENABLE"; then
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
  fi
}

src_resampling_env_0333() {
  local mode=$1
  export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=0
  export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=0
  if [[ "$mode" == "resampling" ]]; then
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296="${MASS_RECONDITION_ENABLE:-1}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY="${MASS_RECONDITION_EVERY:-5}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH="${MASS_RECONDITION_STRENGTH:-1.0}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="${GUARD_EVERY:-5}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="${GUARD_NMIN:-12}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="${GUARD_NTARGET:-20}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="${GUARD_NMAX:-32}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION="${GUARD_SPLIT_FRACTION:-0.5}"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="${RESTORE_ENABLE:-1}"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE="${RESTORE_MAX_SCALE:-4.0}"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_ABS_TOL="${RESTORE_ABS_TOL:-1e-14}"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_REL_TOL="${RESTORE_REL_TOL:-1e-12}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="${BOUNDARY_AWARE:-1}"
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

run_monolithic_case_0333() {
  local case=$1 solid=$2 bbet=$3
  echo -e "case\trep\tstatus\tstdout\ttimefile" > "$ART_DIR/${case}_mono_runs_0333.tsv"
  for rep in $(seq 1 "$REPS"); do
    local out="$ART_DIR/stdout_${case}_rep${rep}.txt"
    local tim="$ART_DIR/time_${case}_rep${rep}.txt"
    local odir="$ART_DIR/${case}_out_rep${rep}"
    echo "[0333] monolithic case=$case rep=$rep"
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' -o "$tim" \
      "$MONO_BIN" \
        --mode vk --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" \
        --dt "$DT" --steps "$STEPS" --alphaDeg "$ALPHA_DEG" --U0 "$U0" --kBT "$KBT" \
        --thermostat "$THERMOSTAT_ENABLE" --keepMeanFlow $(bool_true_0333 "$KEEP_MEAN_FLOW_ENABLE" && echo 1 || echo 0) \
        --xInletInject 0 --solid "$solid" --bbEn 1 --bbEt "$bbet" \
        --xc "$CX" --yc "$CY" --Rc "$RC" --seed "$SEED" \
        --vis 0 --writeCSV 0 --dumpStride 0 --logStride 0 --outDir "$odir" \
      > "$out" 2>&1
    local status=$?
    echo -e "${case}\t${rep}\t${status}\t${out}\t${tim}" >> "$ART_DIR/${case}_mono_runs_0333.tsv"
  done
}

run_src_case_0333() {
  local case=$1 mode=$2 inactive=$3
  local runbase="$ART_DIR/${case}"
  for rep in $(seq 1 "$REPS"); do
    local run_root="runs/vk_full_periodic_0333/${case}_rep${rep}"
    rm -rf "$run_root"
    mkdir -p "$run_root/init" "$run_root/params" "$run_root/output" "$run_root/logs"
    local state="$run_root/init/vk_full_periodic_0333_${NX}x${NY}_g${GAMMA}_inactive${inactive}.smpcd"
    local params="$run_root/params/vk_full_periodic_0333.kv"
    local out="$ART_DIR/stdout_${case}_rep${rep}.txt"
    local tim="$ART_DIR/time_${case}_rep${rep}.txt"
    echo "[0333] SRC case=$case mode=$mode inactive=$inactive rep=$rep"
    src_generate_state_0333 "$state" "$inactive" | tee "$ART_DIR/state_${case}_rep${rep}.txt"
    src_write_params_0333 "$params" "$state" "$run_root/output" "$mode"
    src_cuda_enable_classic_periodic_circle_0333
    src_resampling_env_0333 "$mode"
    env | grep -E '^(MPCD_CUDA_|SRC_GPU_|OMP_)' | sort > "$run_root/logs/environment_0333.env"
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' -o "$tim" "$SRC_BIN" "$params" > "$out" 2>&1
    local status=$?
    echo -e "${case}\t${mode}\t${inactive}\t${rep}\t${status}\t${run_root}\t${out}\t${tim}" >> "$ART_DIR/src_runs_0333.tsv"
  done
}

build_mono_if_needed_0333
build_src_if_needed_0333
write_manifest_0333

: > "$ART_DIR/mono_runs_0333.tsv"
run_monolithic_case_0333 "MONO_ANALYTIC_SPECULAR" 0 1
if bool_true_0333 "$RUN_MONO_SOLID_DEFAULT"; then
  run_monolithic_case_0333 "MONO_SOLID_DEFAULT" 1 -1
fi
# Merge mono case files into one table.
{
  echo -e "case\trep\tstatus\tstdout\ttimefile"
  for f in "$ART_DIR"/*_mono_runs_0333.tsv; do tail -n +2 "$f"; done
} > "$ART_DIR/mono_runs_0333.tsv.tmp"
mv "$ART_DIR/mono_runs_0333.tsv.tmp" "$ART_DIR/mono_runs_0333.tsv"

echo -e "case\tmode\tinactive\trep\tstatus\trun_root\tstdout\ttimefile" > "$ART_DIR/src_runs_0333.tsv"
run_src_case_0333 "SRC_CLASSIC_NINACT0" "classic" 0
if bool_true_0333 "$INCLUDE_CLASSIC_INACTIVE"; then
  run_src_case_0333 "SRC_CLASSIC_NINACT${INACTIVE_SLOTS_RESAMPLING}" "classic" "$INACTIVE_SLOTS_RESAMPLING"
fi
run_src_case_0333 "SRC_RESAMPLING_NINACT${INACTIVE_SLOTS_RESAMPLING}" "resampling" "$INACTIVE_SLOTS_RESAMPLING"

python3 scripts/analyze_vk_full_periodic_mono_vs_src_0333.py "$ART_DIR" | tee "$ART_DIR/analyze_vk_full_periodic_mono_vs_src_0333.stdout.txt"

echo "[0333] artifacts: $ART_DIR"
find "$ART_DIR" -maxdepth 1 -type f | sort

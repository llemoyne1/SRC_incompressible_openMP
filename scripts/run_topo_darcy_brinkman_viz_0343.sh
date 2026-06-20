#!/usr/bin/env bash
set -euo pipefail

# 0343/topo: CUDA-VIZ SRC classic + pure Brinkman/Darcy penalization.
# Darcy-only remains the default.  Set TOPO_RESAMPLING_ENABLE=1 to activate the
# CUDA-resident 0295/0296/0297/refill path with chi-filtered Darcy compatibility.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bool_true_0343() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac
}

Lx="${Lx:-1.5}"
Ly="${Ly:-0.4}"
NX="${NX:-360}"
NY="${NY:-96}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-2000}"
DT="${DT:-0.0005}"
KBT="${KBT:-5}"
U0="${U0:-0.05}"
AX="${AX:-0.0}"
AY="${AY:-0.0}"
SEED="${SEED:-1628505}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-1}"
THREADS="${THREADS:-12}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-50000}"

# Darcy/topology defaults: chi=1 fluid, chi=0 solid/porous.
DARCY_ENABLE="${DARCY_ENABLE:-1}"
DARCY_CHI_MODE="${DARCY_CHI_MODE:-circle}"
DARCY_CHI_FILE="${DARCY_CHI_FILE:-}"
DARCY_CHI_FILE_FORMAT="${DARCY_CHI_FILE_FORMAT:-float32}"
DARCY_ALPHA_MIN="${DARCY_ALPHA_MIN:-0.0}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-80.0}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_USOLID_X="${DARCY_USOLID_X:-0.0}"
DARCY_USOLID_Y="${DARCY_USOLID_Y:-0.0}"
DARCY_CX="${DARCY_CX:-0.45}"
DARCY_CY="${DARCY_CY:-0.20}"
DARCY_R="${DARCY_R:-0.055}"
DARCY_INTERFACE_WIDTH="${DARCY_INTERFACE_WIDTH:-0.01}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}"

# CUDA-resident resampling/refill defaults.  Top-level weighted resampling stays
# off by default; this path keeps particles/cells resident on the GPU.
TOP_LEVEL_RESAMPLING_ENABLE="${TOP_LEVEL_RESAMPLING_ENABLE:-0}"
TOPO_RESAMPLING_ENABLE="${TOPO_RESAMPLING_ENABLE:-0}"
RESAMPLING_SURVEY_ENABLE="${RESAMPLING_SURVEY_ENABLE:-$TOPO_RESAMPLING_ENABLE}"
RESAMPLING_SURVEY_EVERY="${RESAMPLING_SURVEY_EVERY:-$DARCY_COST_EVERY}"
FLAG_EVERY="${FLAG_EVERY:-50}"
MASS_RECONDITION_ENABLE="${MASS_RECONDITION_ENABLE:-$TOPO_RESAMPLING_ENABLE}"
MASS_RECONDITION_EVERY="${MASS_RECONDITION_EVERY:-5}"
MASS_RECONDITION_STRENGTH="${MASS_RECONDITION_STRENGTH:-1.0}"
GUARD_EVERY="${GUARD_EVERY:-5}"
GUARD_NMIN="${GUARD_NMIN:-12}"
GUARD_NTARGET="${GUARD_NTARGET:-${GAMMA}}"
GUARD_NMAX="${GUARD_NMAX:-32}"
GUARD_SPLIT_FRACTION="${GUARD_SPLIT_FRACTION:-0.5}"
RESTORE_ENABLE="${RESTORE_ENABLE:-1}"
RESTORE_MAX_SCALE="${RESTORE_MAX_SCALE:-4.0}"
RESTORE_ABS_TOL="${RESTORE_ABS_TOL:-1e-14}"
RESTORE_REL_TOL="${RESTORE_REL_TOL:-1e-12}"
BOUNDARY_AWARE="${BOUNDARY_AWARE:-1}"
BOUNDARY_HALO_CELLS="${BOUNDARY_HALO_CELLS:-0}"
OPEN_BOUNDARY_HALO_CELLS="${OPEN_BOUNDARY_HALO_CELLS:-1}"
SOLID_HALO_CELLS="${SOLID_HALO_CELLS:-0}"
EMPTY_REFILL_ENABLE="${EMPTY_REFILL_ENABLE:-$TOPO_RESAMPLING_ENABLE}"
EMPTY_REFILL_TARGET_FRACTION="${EMPTY_REFILL_TARGET_FRACTION:-0.5}"
EMPTY_REFILL_REFERENCE="${EMPTY_REFILL_REFERENCE:-nTarget}"
EMPTY_REFILL_GAMMA="${EMPTY_REFILL_GAMMA:-${GAMMA}}"
EMPTY_REFILL_MEMORY_MAX_AGE="${EMPTY_REFILL_MEMORY_MAX_AGE:-1000}"
RESAMPLING_CHI_FILTER_ENABLE="${RESAMPLING_CHI_FILTER_ENABLE:-1}"
RESAMPLING_CHI_MIN="${RESAMPLING_CHI_MIN:-0.5}"

# 0353b: optional state dumps for high-resolution NACA/topology diagnostics.
# Default remains zero to preserve the historical lightweight benchmark path.
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-500}"
DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"
SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"

# 0348a/topo benchmark observables: disabled by default to preserve the
# historical CUDA-VIZ path.  When enabled, the first implementation only adds
# cell-based Darcy force/drag/lift reductions at topoBenchmarkEvery cadence.
TOPO_BENCHMARK_ENABLE="${TOPO_BENCHMARK_ENABLE:-0}"
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-$DARCY_COST_EVERY}"
TOPO_BENCHMARK_FILENAME="${TOPO_BENCHMARK_FILENAME:-topo_benchmark_0348.csv}"
TOPO_BENCHMARK_FORCE_ENABLE="${TOPO_BENCHMARK_FORCE_ENABLE:-1}"
TOPO_BENCHMARK_DRAG_LIFT_ENABLE="${TOPO_BENCHMARK_DRAG_LIFT_ENABLE:-1}"
TOPO_BENCHMARK_FLOW_DIR_X="${TOPO_BENCHMARK_FLOW_DIR_X:-1.0}"
TOPO_BENCHMARK_FLOW_DIR_Y="${TOPO_BENCHMARK_FLOW_DIR_Y:-0.0}"
TOPO_BENCHMARK_LIFT_DIR_X="${TOPO_BENCHMARK_LIFT_DIR_X:-0.0}"
TOPO_BENCHMARK_LIFT_DIR_Y="${TOPO_BENCHMARK_LIFT_DIR_Y:-1.0}"

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

BIN="${BIN:-build/src_mpcd_base_cuda_topo_0343}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
AUTO_BUILD="${AUTO_BUILD:-1}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}"
TAG="${TAG:-topo_darcy_brinkman_viz_0343}"
RUN_ROOT="${RUN_ROOT:-runs/${TAG}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-chi}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
LIVE_VIS_NX="${LIVE_VIS_NX:-600}"
LIVE_VIS_NY="${LIVE_VIS_NY:-320}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:-1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_VSYNC="${LIVE_VIS_VSYNC:-0}"
LIVE_VIS_CONTROL_ENABLE="${LIVE_VIS_CONTROL_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-livevis_control.kv}"
LIVE_VIS_CONTROL_RESET="${LIVE_VIS_CONTROL_RESET:-0}"

build_if_needed_0343() {
  if [[ -x "$BIN" && "$FORCE_REBUILD" != "1" && "$FORCE_REBUILD" != "true" && "$FORCE_REBUILD" != "TRUE" ]]; then
    return 0
  fi
  if ! bool_true_0343 "$AUTO_BUILD"; then
    echo "[0343-topo] missing binary: $BIN" >&2
    exit 127
  fi
  echo "[0343-topo] building $BIN"
  MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" CUDA_ARCH_FLAGS="$CUDA_ARCH_FLAGS" \
    bash scripts/build_src_mpcd_cuda_topo_0343.sh
}

generate_state_0343() {
  local output=$1
  python3 - "$output" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" "$U0" "$INACTIVE_SLOTS" <<'PYGEN'
import math, os, random, struct, sys
out,Lx,Ly,Nx,Ny,gamma,kBT,seed,U0,inactive_slots=sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny); gamma=float(gamma); kBT=float(kBT); seed=int(seed); U0=float(U0); inactive_slots=int(inactive_slots)
n=int(round(gamma*Nx*Ny))
rng=random.Random(seed)
sigma=math.sqrt(kBT) if kBT>0 else 0.0
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
for _ in range(n):
    x.append(Lx*rng.random()); y.append(Ly*rng.random())
    vx.append(U0 + sigma*rng.gauss(0.0,1.0)); vy.append(sigma*rng.gauss(0.0,1.0))
    typ.append(0); mass.append(1.0); role.append(1)
mx=sum(vx)/len(vx); my=sum(vy)/len(vy)
for i in range(len(vx)):
    vx[i]=vx[i]-mx+U0
    vy[i]=vy[i]-my
# Append inactive reservoir slots at the tail. They are ignored by fluid
# dynamics and consumed by CUDA resampling/refill when cells need particles.
slot_x = 0.0
slot_y = 0.0
for _ in range(max(0, inactive_slots)):
    x.append(slot_x); y.append(slot_y)
    vx.append(0.0); vy.append(0.0)
    typ.append(0); mass.append(1.0); role.append(0)
total_n = len(x)
os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE'))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
with open(out,'wb') as f:
    f.write(magic)
    f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,total_n,1,1,8,4))
    f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in [(x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')]:
        f.write(struct.pack('<%d%s'%(total_n,fmt),*arr))
fluid=sum(1 for r in role if r==1); inactive=sum(1 for r in role if r==0)
print(f'[0343-state] output={out} fluid={fluid} inactive={inactive} total={total_n} gamma={gamma} kBT={kBT} U0={U0}')
PYGEN
}

write_params_0343() {
  local params=$1 state=$2 out=$3
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
bodyAccelerationX = ${AX}
bodyAccelerationY = ${AY}
taylorGreenForcingEnable = false
keepMeanFlowEnable = false

nSteps = ${STEPS}
dt = ${DT}
rotationAngle = ${ROTATION_ANGLE}
randomRotationSign = true
gridShiftEnable = true
rngSeed = ${SEED}

srcClassicCudaModeEnable = true
projectionEnable = false
resamplingEnable = $(if bool_true_0343 "$TOP_LEVEL_RESAMPLING_ENABLE"; then echo true; else echo false; fi)
resamplingTargetCellMass = ${GAMMA}
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false
cudaResamplingEmptyRefillEnable = $(if bool_true_0343 "$EMPTY_REFILL_ENABLE"; then echo true; else echo false; fi)
cudaResamplingEmptyRefillTargetFraction = ${EMPTY_REFILL_TARGET_FRACTION}
cudaResamplingEmptyRefillReference = ${EMPTY_REFILL_REFERENCE}
cudaResamplingEmptyRefillGamma = ${EMPTY_REFILL_GAMMA}
cudaResamplingEmptyRefillMemoryMaxAge = ${EMPTY_REFILL_MEMORY_MAX_AGE}
cudaResamplingChiFilterEnable = $(if bool_true_0343 "$RESAMPLING_CHI_FILTER_ENABLE"; then echo true; else echo false; fi)
cudaResamplingChiMin = ${RESAMPLING_CHI_MIN}

thermostatEnable = $(if bool_true_0343 "$THERMOSTAT_ENABLE"; then echo true; else echo false; fi)
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = ${KBT}

darcyBrinkmanEnable = $(if bool_true_0343 "$DARCY_ENABLE"; then echo true; else echo false; fi)
darcyChiMode = ${DARCY_CHI_MODE}
darcyAlphaMin = ${DARCY_ALPHA_MIN}
darcyAlphaMax = ${DARCY_ALPHA_MAX}
darcyQ = ${DARCY_Q}
darcyUSolidX = ${DARCY_USOLID_X}
darcyUSolidY = ${DARCY_USOLID_Y}
darcyCircleCx = ${DARCY_CX}
darcyCircleCy = ${DARCY_CY}
darcyCircleR = ${DARCY_R}
darcyInterfaceWidth = ${DARCY_INTERFACE_WIDTH}
darcyCostEvery = ${DARCY_COST_EVERY}
darcyCostFilename = darcy_cost_0343.csv

topoBenchmarkEnable = $(if bool_true_0343 "$TOPO_BENCHMARK_ENABLE"; then echo true; else echo false; fi)
topoBenchmarkEvery = ${TOPO_BENCHMARK_EVERY}
topoBenchmarkFilename = ${TOPO_BENCHMARK_FILENAME}
topoBenchmarkForceEnable = $(if bool_true_0343 "$TOPO_BENCHMARK_FORCE_ENABLE"; then echo true; else echo false; fi)
topoBenchmarkDragLiftEnable = $(if bool_true_0343 "$TOPO_BENCHMARK_DRAG_LIFT_ENABLE"; then echo true; else echo false; fi)
topoBenchmarkFlowDirX = ${TOPO_BENCHMARK_FLOW_DIR_X}
topoBenchmarkFlowDirY = ${TOPO_BENCHMARK_FLOW_DIR_Y}
topoBenchmarkLiftDirX = ${TOPO_BENCHMARK_LIFT_DIR_X}
topoBenchmarkLiftDirY = ${TOPO_BENCHMARK_LIFT_DIR_Y}

summaryEvery = ${DARCY_COST_EVERY}
dumpStateEvery = ${DUMP_STATE_EVERY}
summaryRoleFilter = ${SUMMARY_ROLE_FILTER}
dumpRoleFilter = ${DUMP_ROLE_FILTER}
numThreads = ${THREADS}
PARAMS
  if [[ "${DARCY_CHI_MODE}" == "file" ]]; then
    if [[ -z "${DARCY_CHI_FILE}" ]]; then
      echo "[0345-topo] ERROR: DARCY_CHI_MODE=file requires DARCY_CHI_FILE" >&2
      exit 2
    fi
    cat >> "$params" <<PARAMS

darcyChiFile = ${DARCY_CHI_FILE}
darcyChiNx = ${NX}
darcyChiNy = ${NY}
darcyChiFileFormat = ${DARCY_CHI_FILE_FORMAT}
PARAMS
  fi
}

cuda_env_0343() {
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
  if bool_true_0343 "$THERMOSTAT_ENABLE"; then
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
  else
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  fi
  export SRC_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
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
  export SRC_LIVE_VIS_CUDA_FIELD=1
  export SRC_LIVE_VIS_CUDA_SNAPSHOT=0
  export SRC_LIVE_VIS_FORCE_HOST_MIRROR=0
  export SRC_LIVE_VIS_CONTROL_FILE="$LIVE_VIS_CONTROL_FILE"
  export SRC_LIVE_VIS_CONTROL_EVERY=1
  export SRC_LIVE_VIS_CONTROL_LOG=1
  export MPCD_CUDA_DARCY_BRINKMAN_LOG_0343="${MPCD_CUDA_DARCY_BRINKMAN_LOG_0343:-0}"
  export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295="$RESAMPLING_SURVEY_ENABLE"
  export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="$RESAMPLING_SURVEY_EVERY"
  export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE="${MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE:-full}"
  export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304:-$TOPO_RESAMPLING_ENABLE}"
  export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY:-$FLAG_EVERY}"
  export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN:-6}"
  export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY:-1}"
  if bool_true_0343 "$TOPO_RESAMPLING_ENABLE"; then
    export MPCD_CUDA_INACTIVE_TAIL_POOL_0313="${MPCD_CUDA_INACTIVE_TAIL_POOL_0313:-1}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296="$MASS_RECONDITION_ENABLE"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY="$MASS_RECONDITION_EVERY"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH="$MASS_RECONDITION_STRENGTH"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="$GUARD_EVERY"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="$GUARD_NMIN"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="$GUARD_NTARGET"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="$GUARD_NMAX"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION="$GUARD_SPLIT_FRACTION"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="$RESTORE_ENABLE"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE="$RESTORE_MAX_SCALE"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_ABS_TOL="$RESTORE_ABS_TOL"
    export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_REL_TOL="$RESTORE_REL_TOL"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="$BOUNDARY_AWARE"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS="$OPEN_BOUNDARY_HALO_CELLS"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS="$BOUNDARY_HALO_CELLS"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS="$SOLID_HALO_CELLS"
    export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307="${RESAMPLING_SPLIT_SAFETY_0307:-1}"
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

build_if_needed_0343
if bool_true_0343 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/params" "$RUN_ROOT/output" "$RUN_ROOT/logs"
STATE="$RUN_ROOT/init/topo_darcy_0343_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/topo_darcy_0343.kv"
generate_state_0343 "$STATE"
write_params_0343 "$PARAMS" "$STATE" "$RUN_ROOT/output"
control_dir="$(dirname "$LIVE_VIS_CONTROL_FILE")"
if [[ "$control_dir" != "." ]]; then
  mkdir -p "$control_dir"
fi
if [[ ! -f "$LIVE_VIS_CONTROL_FILE" || "$LIVE_VIS_CONTROL_RESET" == "1" || "$LIVE_VIS_CONTROL_RESET" == "true" || "$LIVE_VIS_CONTROL_RESET" == "TRUE" ]]; then
  cat > "$LIVE_VIS_CONTROL_FILE" <<CONTROL
# 0344/topo persistent live visualization controls.
# Default location is repository root: livevis_control.kv.
# Edit this file while running; the runner no longer overwrites it unless
# LIVE_VIS_CONTROL_RESET=1 or the file does not exist.
# Supported topo fields: chi, alpha, darcy_power, ux, uy, speed, vorticity, mass.
field = ${LIVE_VIS_FIELD}
clip = ${LIVE_VIS_CLIP}
gain = ${LIVE_VIS_GAIN}
smoothPasses = ${LIVE_VIS_SMOOTH_PASSES}
colormap = ${LIVE_VIS_COLORMAP}
CONTROL
  echo "[0344-topo] wrote live control=$LIVE_VIS_CONTROL_FILE"
else
  echo "[0344-topo] reusing live control=$LIVE_VIS_CONTROL_FILE"
fi
cuda_env_0343
env | grep -E '^(MPCD_CUDA_|SRC_LIVE_VIS_|OMP_)' | sort > "$RUN_ROOT/logs/environment_0343.env"

echo "[0343-topo] binary=$BIN"
echo "[0343-topo] params=$PARAMS"
echo "[0343-topo] run_root=$RUN_ROOT"
echo "[0343-topo] live control=$LIVE_VIS_CONTROL_FILE"
"$BIN" "$PARAMS" 2>&1 | tee "$RUN_ROOT/logs/run_0343.log"


#!/usr/bin/env bash
set -euo pipefail

# 0410 -- autonomous backward-step comparison from the portable 0315 geometry.
# Runs SRC CUDA classic and SRC+Q6 CPU by default. The hard backward-step uses
# immersedSolidEnable=true, which the current resident Q6 CUDA guards do not
# support; set RUN_UNSUPPORTED_Q6_CUDA=1 to attempt the experimental CUDA-Q6 run.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

truthy_0410() { case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac; }
USER_BIN_SET=0
if [[ -n "${BIN+x}" ]]; then USER_BIN_SET=1; fi

Lx=${Lx:-${LX:-2.0}}
Ly=${Ly:-${LY:-1.0}}
NX=${NX:-960}
NY=${NY:-480}
GAMMA=${GAMMA:-7}
STEPS=${STEPS:-5000}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-${DUMPS_EVERY:-100}}
THREADS=${THREADS:-8}
SEED=${SEED:-1628310}
STATE_SEED=${STATE_SEED:-$SEED}
DT=${DT:-0.001}
KBT=${KBT:-0.05}
PARTICLE_MASS=${PARTICLE_MASS:-1.0}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-4200000}

UIN=${UIN:-0.25}
UINIT=${UINIT:-0.25}
STEP_XMIN=${STEP_XMIN:-0.0}
STEP_XMAX=${STEP_XMAX:-1.0}
STEP_YMIN=${STEP_YMIN:-0.0}
STEP_YMAX=${STEP_YMAX:-0.52}
OUTLET_MODE=${OUTLET_MODE:-hybrid}

ROTATION_ANGLE=${ROTATION_ANGLE:-1.5}
RANDOM_ROTATION_SIGN=${RANDOM_ROTATION_SIGN:-true}
GRID_SHIFT_ENABLE=${GRID_SHIFT_ENABLE:-true}
PROJECTION_OPERATOR=${PROJECTION_OPERATOR:-elliptic_fv_cg}
PROJECTION_MAX_ITERATIONS=${PROJECTION_MAX_ITERATIONS:-800}
PROJECTION_TOLERANCE=${PROJECTION_TOLERANCE:-1.0e-10}
PROJECTION_MOMENTUM_CORRECTION_ENABLE=${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}
Q6_PROJECTION_STRENGTH=${Q6_PROJECTION_STRENGTH:-1.0}
THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE:-true}
THERMOSTAT_MODE=${THERMOSTAT_MODE:-cell_relative_rescale}
THERMOSTAT_EVERY=${THERMOSTAT_EVERY:-1}
THERMOSTAT_TARGET_KBT=${THERMOSTAT_TARGET_KBT:--1.0}
THERMOSTAT_MIN_PARTICLES=${THERMOSTAT_MIN_PARTICLES:-3}
DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER:-fluid}
SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER:-fluid}

FORCE_BUILD=${FORCE_BUILD:-0}
BUILD_IF_STALE=${BUILD_IF_STALE:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-1}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-${SRC_LIVE_VIS_ENABLE:-1}}
LIVE_VIS_RUN=${LIVE_VIS_RUN:-all}
RUN_UNSUPPORTED_Q6_CUDA=${RUN_UNSUPPORTED_Q6_CUDA:-0}
PARAM_OVERRIDES_FILE=${PARAM_OVERRIDES_FILE:-}
PARAM_OVERRIDES_TEXT=${PARAM_OVERRIDES_TEXT:-}

if truthy_0410 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "0" ]]; then
  BIN=build/src_mpcd_base_cuda_q6_resident_0400_livevis
else
  BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}
fi
needs_build=0
if truthy_0410 "$FORCE_BUILD" || [[ ! -x "$BIN" ]]; then
  needs_build=1
elif truthy_0410 "$BUILD_IF_STALE"; then
  if find src include scripts/build_src_mpcd_cuda_q6_resident_0400.sh -type f -newer "$BIN" -print -quit | grep -q .; then needs_build=1; fi
fi
if [[ "$needs_build" == "1" ]]; then
  if truthy_0410 "$LIVE_VIS_ENABLE"; then MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh; else OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh; fi
fi
if [[ ! -x "$BIN" ]]; then echo "[0410-backward-step] ERROR missing binary: $BIN" >&2; exit 127; fi

TAG="${NX}x${NY}_${STEPS}_uin${UIN}_step${STEP_XMAX}x${STEP_YMAX}"
RUN_ROOT=${RUN_ROOT:-runs/q6_resident_0410_backward_step_autonomous_${TAG}}
ART_DIR=${ART_DIR:-dev_history/artifacts/q6_resident_0410_backward_step_autonomous_${TAG}}
STATE="$RUN_ROOT/init/backward_step.smpcd"
mkdir -p "$RUN_ROOT/init" "$ART_DIR"

python3 - "$STATE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$STATE_SEED" "$UINIT" "$INACTIVE_SLOTS" "$STEP_XMIN" "$STEP_XMAX" "$STEP_YMIN" "$STEP_YMAX" <<'PYGEN'
import math, os, random, struct, sys
(out,Lx,Ly,Nx,Ny,gamma,kBT,seed,uinit,inactive_slots,sxmin,sxmax,symin,symax)=sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny); gamma=int(gamma); kBT=float(kBT); seed=int(seed)
uinit=float(uinit); inactive_slots=int(inactive_slots)
sxmin=float(sxmin); sxmax=float(sxmax); symin=float(symin); symax=float(symax)
rng=random.Random(seed); dx=Lx/Nx; dy=Ly/Ny; mass0=1.0; sigma=math.sqrt(kBT/mass0) if kBT>0 else 0.0
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]; skipped=0; rejected=0
def solid(xp,yp): return sxmin <= xp <= sxmax and symin <= yp <= symax
for j in range(Ny):
    for i in range(Nx):
        cx=(i+0.5)*dx; cy=(j+0.5)*dy
        if solid(cx,cy): skipped += 1; continue
        for _ in range(gamma):
            ok=False
            for _try in range(1000):
                xp=i*dx+dx*rng.random(); yp=j*dy+dy*rng.random()
                if solid(xp,yp): rejected += 1; continue
                ok=True; break
            if not ok: continue
            ux=uinit + (sigma*rng.gauss(0.0,1.0) if sigma>0 else 0.0)
            uy=(sigma*rng.gauss(0.0,1.0) if sigma>0 else 0.0)
            x.append(xp); y.append(yp); vx.append(ux); vy.append(uy); typ.append(0); mass.append(mass0); role.append(1)
fluid_mass=sum(mass)
if fluid_mass>0:
    mvx=sum(m*u for m,u in zip(mass,vx))/fluid_mass; mvy=sum(m*v for m,v in zip(mass,vy))/fluid_mass
    vx=[u-mvx+uinit for u in vx]; vy=[v-mvy for v in vy]
for _ in range(inactive_slots):
    x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0); typ.append(0); mass.append(mass0); role.append(0)
os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE')); reserved=[0]*8; reserved[0]=1; reserved[1]=1; n=len(x)
with open(out,'wb') as f:
    f.write(magic); f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4)); f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in [(x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')]: f.write(struct.pack('<%d%s'%(n,fmt),*arr))
print(f'[0410-state] output={out} grid={Nx}x{Ny} fluid={sum(1 for r in role if r==1)} inactive={sum(1 for r in role if r==0)} skippedCells={skipped} rejected={rejected}')
PYGEN

append_param_overrides_0410() {
  local params=$1
  if [[ -n "$PARAM_OVERRIDES_FILE" ]]; then { printf '\n# PARAM_OVERRIDES_FILE: %s\n' "$PARAM_OVERRIDES_FILE"; cat "$PARAM_OVERRIDES_FILE"; printf '\n'; } >> "$params"; fi
  if [[ -n "$PARAM_OVERRIDES_TEXT" ]]; then { printf '\n# PARAM_OVERRIDES_TEXT\n'; printf '%s\n' "$PARAM_OVERRIDES_TEXT"; } >> "$params"; fi
}

write_params_0410() {
  local out_dir=$1 params=$2 projection_enable=$3 projection_backend=$4 classic_cuda=$5
  cat > "$params" <<PARAMS
inputState = $STATE
outputDir = $out_dir
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY

dt = $DT
nSteps = $STEPS

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false

inletUxLeft = $UIN
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.25
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
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = $OUTLET_MODE
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0

immersedSolidEnable = true
immersedSolidShape = rectangle
immersedSolidXMin = $STEP_XMIN
immersedSolidXMax = $STEP_XMAX
immersedSolidYMin = $STEP_YMIN
immersedSolidYMax = $STEP_YMAX
immersedSolidFractionSamples = 4
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $PARTICLE_MASS
wallKBT = -1.0
wallThermalNoise = 0.0

projectionEnable = $projection_enable
projectionBackend = $projection_backend
projectionOperator = $PROJECTION_OPERATOR
projectionMaxIterations = $PROJECTION_MAX_ITERATIONS
projectionTolerance = $PROJECTION_TOLERANCE
projectionMomentumCorrectionEnable = $PROJECTION_MOMENTUM_CORRECTION_ENABLE
q6ProjectionStrength = $Q6_PROJECTION_STRENGTH
projectionImmersedSolidMaskEnable = true

srcClassicCudaModeEnable = $classic_cuda
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false

rotationAngle = $ROTATION_ANGLE
randomRotationSign = $RANDOM_ROTATION_SIGN
gridShiftEnable = $GRID_SHIFT_ENABLE
rngSeed = $SEED

thermostatEnable = $THERMOSTAT_ENABLE
thermostatMode = $THERMOSTAT_MODE
thermostatEvery = $THERMOSTAT_EVERY
thermostatTargetKBT = $THERMOSTAT_TARGET_KBT
thermostatMinParticles = $THERMOSTAT_MIN_PARTICLES
kBT = $KBT

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_STATE_EVERY
summaryRoleFilter = $SUMMARY_ROLE_FILTER
dumpRoleFilter = $DUMP_ROLE_FILTER
numThreads = $THREADS
PARAMS
  append_param_overrides_0410 "$params"
}

livevis_off_env=(SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0)
livevis_on_env=("${livevis_off_env[@]}")
if truthy_0410 "$LIVE_VIS_ENABLE"; then
  SRC_LIVE_VIS_FIELD=${SRC_LIVE_VIS_FIELD:-${LIVE_VIS_FIELD:-speed}}
  SRC_LIVE_VIS_EVERY=${SRC_LIVE_VIS_EVERY:-${LIVE_VIS_EVERY:-25}}
  SRC_LIVE_VIS_NX=${SRC_LIVE_VIS_NX:-${LIVE_VIS_NX:-600}}
  SRC_LIVE_VIS_NY=${SRC_LIVE_VIS_NY:-${LIVE_VIS_NY:-300}}
  SRC_LIVE_VIS_CLIP=${SRC_LIVE_VIS_CLIP:-${LIVE_VIS_CLIP:--1}}
  SRC_LIVE_VIS_GAIN=${SRC_LIVE_VIS_GAIN:-${LIVE_VIS_GAIN:-1.0}}
  SRC_LIVE_VIS_SMOOTH_PASSES=${SRC_LIVE_VIS_SMOOTH_PASSES:-${LIVE_VIS_SMOOTH_PASSES:-1}}
  SRC_LIVE_VIS_COLORMAP=${SRC_LIVE_VIS_COLORMAP:-${LIVE_VIS_COLORMAP:-thermal}}
  SRC_LIVE_VIS_WINDOW_SCALE=${SRC_LIVE_VIS_WINDOW_SCALE:-${LIVE_VIS_WINDOW_SCALE:-1}}
  SRC_LIVE_VIS_VSYNC=${SRC_LIVE_VIS_VSYNC:-${LIVE_VIS_VSYNC:-0}}
  SRC_LIVE_VIS_CUDA_FIELD=${SRC_LIVE_VIS_CUDA_FIELD:-${LIVE_VIS_CUDA_FIELD:-1}}
  SRC_LIVE_VIS_CUDA_SNAPSHOT=${SRC_LIVE_VIS_CUDA_SNAPSHOT:-${LIVE_VIS_CUDA_SNAPSHOT:-1}}
  SRC_LIVE_VIS_LOG_SOURCE=${SRC_LIVE_VIS_LOG_SOURCE:-${LIVE_VIS_LOG_SOURCE:-0}}
  SRC_LIVE_VIS_CONTROL_FILE=${SRC_LIVE_VIS_CONTROL_FILE:-${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}}
  SRC_LIVE_VIS_CONTROL_EVERY=${SRC_LIVE_VIS_CONTROL_EVERY:-${LIVE_VIS_CONTROL_EVERY:-1}}
  SRC_LIVE_VIS_CONTROL_LOG=${SRC_LIVE_VIS_CONTROL_LOG:-0}
  if [[ ! -f "$SRC_LIVE_VIS_CONTROL_FILE" ]]; then
    cat > "$SRC_LIVE_VIS_CONTROL_FILE" <<CONTROL
field = ${SRC_LIVE_VIS_FIELD}
clip = ${SRC_LIVE_VIS_CLIP}
gain = ${SRC_LIVE_VIS_GAIN}
smoothPasses = ${SRC_LIVE_VIS_SMOOTH_PASSES}
colormap = ${SRC_LIVE_VIS_COLORMAP}
quiverScale = ${SRC_LIVE_VIS_QUIVER_SCALE:--1}
CONTROL
  fi
  livevis_on_env=(SRC_LIVE_VIS_ENABLE=1 MPCD_LIVE_VIS_ENABLE=1 SRC_LIVE_VIS_FIELD="$SRC_LIVE_VIS_FIELD" SRC_LIVE_VIS_EVERY="$SRC_LIVE_VIS_EVERY" SRC_LIVE_VIS_NX="$SRC_LIVE_VIS_NX" SRC_LIVE_VIS_NY="$SRC_LIVE_VIS_NY" SRC_LIVE_VIS_CLIP="$SRC_LIVE_VIS_CLIP" SRC_LIVE_VIS_GAIN="$SRC_LIVE_VIS_GAIN" SRC_LIVE_VIS_SMOOTH_PASSES="$SRC_LIVE_VIS_SMOOTH_PASSES" SRC_LIVE_VIS_COLORMAP="$SRC_LIVE_VIS_COLORMAP" SRC_LIVE_VIS_WINDOW_SCALE="$SRC_LIVE_VIS_WINDOW_SCALE" SRC_LIVE_VIS_VSYNC="$SRC_LIVE_VIS_VSYNC" SRC_LIVE_VIS_CUDA_FIELD="$SRC_LIVE_VIS_CUDA_FIELD" SRC_LIVE_VIS_CUDA_SNAPSHOT="$SRC_LIVE_VIS_CUDA_SNAPSHOT" SRC_LIVE_VIS_LOG_SOURCE="$SRC_LIVE_VIS_LOG_SOURCE" SRC_LIVE_VIS_CONTROL_FILE="$SRC_LIVE_VIS_CONTROL_FILE" SRC_LIVE_VIS_CONTROL_EVERY="$SRC_LIVE_VIS_CONTROL_EVERY" SRC_LIVE_VIS_CONTROL_LOG="$SRC_LIVE_VIS_CONTROL_LOG")
  echo "[0410-backward-step] livevis run=$LIVE_VIS_RUN control=$SRC_LIVE_VIS_CONTROL_FILE field=$SRC_LIVE_VIS_FIELD size=${SRC_LIVE_VIS_NX}x${SRC_LIVE_VIS_NY}"
fi

write_validation_summary_0410() {
  local out_dir=$1 name=$2
  python3 - "$out_dir/summary_runtime.csv" "$RUN_ROOT/${name}.time" "$out_dir/validation_summary_0162.csv" "$name" <<'SUMMARYPY'
import csv, os, re, sys
summary_path, time_path, out_path, run_tag = sys.argv[1:5]
with open(summary_path, newline="") as f: rows = list(csv.DictReader(f))
if not rows: raise SystemExit(f"empty summary_runtime: {summary_path}")
last = rows[-1]; text = open(time_path).read() if os.path.exists(time_path) else ""; m = re.search(r"elapsed=([^\s]+) user=([^\s]+) sys=([^\s]+)", text)
elapsed, user, sy = m.groups() if m else ("", "", "")
fieldnames = ["runTag", "case", "elapsed_s", "user_s", "sys_s"] + list(last.keys())
out = {"runTag": run_tag, "case": "backward_step", "elapsed_s": elapsed, "user_s": user, "sys_s": sy}; out.update(last)
with open(out_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fieldnames); w.writeheader(); w.writerow(out)
SUMMARYPY
}

run_case_0410() {
  local name=$1 projection_enable=$2 projection_backend=$3 classic_cuda=$4 livevis_key=$5
  if [[ "$name" == "src_q6_cuda" ]] && ! truthy_0410 "$RUN_UNSUPPORTED_Q6_CUDA"; then
    echo "[0410-backward-step] skipping src_q6_cuda: current resident Q6 CUDA does not support immersedSolid rectangle. Set RUN_UNSUPPORTED_Q6_CUDA=1 to attempt anyway."
    return 0
  fi
  local out_dir="$RUN_ROOT/$name" params="$RUN_ROOT/params_${name}.kv"
  mkdir -p "$out_dir"; write_params_0410 "$out_dir" "$params" "$projection_enable" "$projection_backend" "$classic_cuda"
  local livevis_env=("${livevis_off_env[@]}")
  if truthy_0410 "$LIVE_VIS_ENABLE"; then case "$LIVE_VIS_RUN" in "$livevis_key"|all) livevis_env=("${livevis_on_env[@]}") ;; none|off|0) ;; esac; fi
  local resident_io=0 resident_q6=0 classic_thermostat=0
  if [[ "$classic_cuda" == "true" ]]; then resident_io=1; classic_thermostat=1; fi
  if [[ "$projection_backend" == "cuda" ]]; then resident_io=1; resident_q6=1; fi
  echo "[0410-backward-step] running $name params=$params step=[$STEP_XMIN,$STEP_XMAX]x[$STEP_YMIN,$STEP_YMAX]"
  set +e
  env OMP_NUM_THREADS="$THREADS" OMP_PROC_BIND=close OMP_PLACES=cores OMP_DYNAMIC=false \
    MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263="$resident_io" \
    MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT="$resident_io" \
    MPCD_CUDA_IMMERSED_RECTANGLE_0247="$resident_io" \
    MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=0 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE="$resident_io" \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251="$resident_io" \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253="$resident_io" \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254="$resident_io" \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE="$classic_thermostat" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="$classic_thermostat" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1 \
    MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404="$resident_q6" \
    MPCD_CUDA_Q6_RESIDENT_0400="$resident_q6" \
    MPCD_CUDA_Q6_RESIDENT_STRICT_0400="$resident_q6" \
    MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400="$resident_q6" \
    "${livevis_env[@]}" /usr/bin/time -o "$RUN_ROOT/${name}.time" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params"
  local rc=$?
  set -e
  if [[ "$rc" != "0" ]]; then
    echo "[0410-backward-step] $name failed rc=$rc" >&2
    return "$rc"
  fi
  write_validation_summary_0410 "$out_dir" "$name"
}

run_case_0410 src_cuda_classic false cpu true src_cuda_classic
run_case_0410 src_q6_cpu true cpu false src_q6_cpu
run_case_0410 src_q6_cuda true cuda false src_q6_cuda

if [[ -f "$RUN_ROOT/src_q6_cpu/summary_runtime.csv" && -f "$RUN_ROOT/src_q6_cuda/summary_runtime.csv" ]]; then
  set +e
  python3 scripts/compare_validation_mono_config_0162.py --origin "$RUN_ROOT/src_q6_cpu" --optimized "$RUN_ROOT/src_q6_cuda" --out "$ART_DIR/src_q6_cpu_vs_src_q6_cuda.csv" --summary-out "$ART_DIR/src_q6_cpu_vs_src_q6_cuda_summary.csv"
  cpu_cmp_rc=$?
  set -e
  echo "[0410-backward-step] SRC+Q6 CPU vs SRC+Q6 CUDA summary: $ART_DIR/src_q6_cpu_vs_src_q6_cuda_summary.csv (rc=$cpu_cmp_rc)"
fi

echo "[0410-backward-step] dumps/root: $RUN_ROOT"

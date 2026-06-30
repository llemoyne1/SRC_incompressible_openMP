#!/usr/bin/env bash
set -euo pipefail

# 0425 -- autonomous SRC classic CUDA + Darcy/Brinkman/chiVP backward-step demo.
#
# This script is self-contained:
#   - it generates its own backward-step chi file;
#   - it generates its own initial .smpcd state outside the step solid;
#   - it writes its own .kv parameters;
#   - it launches the selected CUDA livevis binary.
#
# Geometry follows the portable solid backward-step script:
#   Lx=2.0, Ly=1.0, Nx=128, Ny=96, gamma=20
#   solid step rectangle: x in [0,1.05], y in [0,0.42]
#
# Boundary convention for Darcy/chi:
#   - top/bottom are solid walls;
#   - left/right are solid by default with two open segments:
#       inlet  on left,  s in [STEP_YMAX/Ly, 1]
#       outlet on right, s in [0, 1]
#   This avoids injecting particles directly into the chi-solid step region.
#
# Default retained Darcy model:
#   darcyBrinkmanForcingMode = mean_outward_bath
#   darcyChiCollisionVpEnable = true
#   darcyChiCollisionVpStrength = 0.25
#   darcyInitialDeactivateBelowChi = 0.05

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

truthy_0425() { case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac; }

INTEG_PATH=${INTEG_PATH:-${SRC_INTEG_PATH:-src}}
case "$INTEG_PATH" in
  src|classic) SRC_CLASSIC_CUDA_MODE_ENABLE=true; PROJECTION_ENABLE=false; RESAMPLING_ENABLE=false ;;
  src-resampling|resampling) SRC_CLASSIC_CUDA_MODE_ENABLE=true; PROJECTION_ENABLE=false; RESAMPLING_ENABLE=true ;;
  src-q6|q6) SRC_CLASSIC_CUDA_MODE_ENABLE=false; PROJECTION_ENABLE=true; RESAMPLING_ENABLE=false ;;
  src-q6-resampling|q6-resampling) SRC_CLASSIC_CUDA_MODE_ENABLE=false; PROJECTION_ENABLE=true; RESAMPLING_ENABLE=true ;;
  *) echo "[integ-path] ERROR unsupported INTEG_PATH=$INTEG_PATH (use src|src-resampling|src-q6|src-q6-resampling)" >&2; exit 2 ;;
esac
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cuda}
PROJECTION_OPERATOR=${PROJECTION_OPERATOR:-auto_fv_cg}
PROJECTION_MAX_ITERATIONS=${PROJECTION_MAX_ITERATIONS:-200}
PROJECTION_TOLERANCE=${PROJECTION_TOLERANCE:-1e-10}
Q6_PROJECTION_STRENGTH=${Q6_PROJECTION_STRENGTH:-1.0}
Q6_STRICT=${Q6_STRICT:-1}
CUDA_RESAMPLING_CHI_FILTER_ENABLE=${CUDA_RESAMPLING_CHI_FILTER_ENABLE:-true}
CUDA_RESAMPLING_CHI_MIN=${CUDA_RESAMPLING_CHI_MIN:-0.05}
if [[ "$RESAMPLING_ENABLE" == "true" ]]; then
  CUDA_RESAMPLING_EMPTY_REFILL_ENABLE=true
else
  CUDA_RESAMPLING_EMPTY_REFILL_ENABLE=false
fi
CUDA_RESAMPLING_EMPTY_REFILL_REFERENCE=${CUDA_RESAMPLING_EMPTY_REFILL_REFERENCE:-gamma}
CUDA_RESAMPLING_EMPTY_REFILL_GAMMA=${CUDA_RESAMPLING_EMPTY_REFILL_GAMMA:-}
CUDA_RESAMPLING_EMPTY_REFILL_TARGET_FRACTION=${CUDA_RESAMPLING_EMPTY_REFILL_TARGET_FRACTION:-0.1}
CUDA_RESAMPLING_EMPTY_REFILL_MEMORY_MAX_AGE=${CUDA_RESAMPLING_EMPTY_REFILL_MEMORY_MAX_AGE:-1000}

auto_bool_0431() { if truthy_0411 "${1:-0}" 2>/dev/null || truthy_0425 "${1:-0}" 2>/dev/null; then printf true; else printf false; fi; }
integ_path_has_q6_0431() { case "$INTEG_PATH" in src-q6|q6|src-q6-resampling|q6-resampling) return 0 ;; *) return 1 ;; esac; }
integ_path_has_resampling_0431() { case "$INTEG_PATH" in src-resampling|resampling|src-q6-resampling|q6-resampling) return 0 ;; *) return 1 ;; esac; }
integ_apply_path_env_0431() {
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE="${MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE:-1}"
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE="${MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE:-1}"
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE="${MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1
  if integ_path_has_q6_0431; then
    export MPCD_CUDA_Q6_RESIDENT_0400=1
    export MPCD_CUDA_Q6_RESIDENT_STRICT_0400="$Q6_STRICT"
    export MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=1
  else
    export MPCD_CUDA_Q6_RESIDENT_0400=0
    export MPCD_CUDA_Q6_RESIDENT_STRICT_0400=0
    export MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=0
  fi
  if integ_path_has_q6_0431; then
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=0
  fi
  case "segmented" in
    wall)
      export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
      export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=1
      export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
      if integ_path_has_q6_0431; then export MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=1; else export MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=0; fi
      ;;
    segmented)
      export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
      export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
      export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=1
      if integ_path_has_q6_0431; then export MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=1; else export MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=0; fi
      ;;
    periodic)
      export MPCD_CUDA_STREAMING_PERIODIC_0245=1
      export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
      if integ_path_has_q6_0431; then export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1; else export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=0; fi
      ;;
  esac
  if integ_path_has_resampling_0431; then
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296="${MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296:-1}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY="${MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY:-${MASS_RECONDITION_EVERY:-${GUARD_EVERY:-5}}}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH="${MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH:-1.0}"
    export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=1
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297="${MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297:-1}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="${MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE:-1}"
    export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1
    export MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1
  else
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
    export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
    export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=0
  fi
}


Lx=${Lx:-${LX:-2.0}}
Ly=${Ly:-${LY:-1.0}}
NX=${NX:-960}
NY=${NY:-480}
GAMMA=${GAMMA:-7}
CUDA_RESAMPLING_EMPTY_REFILL_GAMMA=${CUDA_RESAMPLING_EMPTY_REFILL_GAMMA:-$GAMMA}
STEPS=${STEPS:-500}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-1000}
THREADS=${THREADS:-8}
SEED=${SEED:-1628304}
DT=${DT:-0.0005}
KBT=${KBT:-0.05}
PARTICLE_MASS=${PARTICLE_MASS:-1.0}
UIN=${UIN:-0.25}
U0=${U0:-$UIN}
UINIT=${UINIT:-0.25}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-120000}

STEP_XMIN=${STEP_XMIN:-0.0}
STEP_XMAX=${STEP_XMAX:-1.0}
STEP_YMIN=${STEP_YMIN:-0.0}
STEP_YMAX=${STEP_YMAX:-0.52}

# Segmented inlet/outlet definition.
# For vertical faces, s is relative y/Ly.
INLET_FACE=${INLET_FACE:-left}
INLET_SMIN=${INLET_SMIN:-$(python3 - <<PY
print(float("$STEP_YMAX")/float("$Ly"))
PY
)}
INLET_SMAX=${INLET_SMAX:-1.0}
OUTLET_FACE=${OUTLET_FACE:-right}
OUTLET_SMIN=${OUTLET_SMIN:-0.0}
OUTLET_SMAX=${OUTLET_SMAX:-1.0}
OUTLET_MODE=${OUTLET_MODE:-hybrid}

CHI_FILE_FORMAT=${CHI_FILE_FORMAT:-float32}
ALPHA=${ALPHA:-${DARCY_ALPHA_MAX:-800000.0}}
ALPHA_MIN=${ALPHA_MIN:-${DARCY_ALPHA_MIN:-0.0}}
DARCY_Q=${DARCY_Q:-0.1}
DARCY_USOLID_X=${DARCY_USOLID_X:-0.0}
DARCY_USOLID_Y=${DARCY_USOLID_Y:-0.0}
DARCY_COST_EVERY=${DARCY_COST_EVERY:-$SUMMARY_EVERY}
DARCY_THREADS_PER_BLOCK=${DARCY_THREADS_PER_BLOCK:-256}

DARCY_INITIAL_DEACTIVATE_BELOW_CHI=${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:-0.05}
DARCY_BRINKMAN_FORCING_MODE=${DARCY_BRINKMAN_FORCING_MODE:-mean_outward_bath}
DARCY_CHI_COLLISION_VP_ENABLE=${DARCY_CHI_COLLISION_VP_ENABLE:-true}
DARCY_CHI_COLLISION_VP_MODE=${DARCY_CHI_COLLISION_VP_MODE:-interface_band}
DARCY_CHI_COLLISION_VP_GAMMA=${DARCY_CHI_COLLISION_VP_GAMMA:--1}
DARCY_CHI_COLLISION_VP_MASS=${DARCY_CHI_COLLISION_VP_MASS:-1.0}
DARCY_CHI_COLLISION_VP_LAYERS=${DARCY_CHI_COLLISION_VP_LAYERS:-1}
DARCY_CHI_COLLISION_VP_THRESHOLD=${DARCY_CHI_COLLISION_VP_THRESHOLD:-0.5}
DARCY_CHI_COLLISION_VP_STRENGTH=${DARCY_CHI_COLLISION_VP_STRENGTH:-0.25}
WALL_KBT=${WALL_KBT:--1.0}

DARCY_INITIAL_DEACTIVATE_BELOW_CHI=${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:-0.05}
DARCY_BRINKMAN_FORCING_MODE=${DARCY_BRINKMAN_FORCING_MODE:-mean_outward_bath}
DARCY_CHI_COLLISION_VP_ENABLE=${DARCY_CHI_COLLISION_VP_ENABLE:-true}
DARCY_CHI_COLLISION_VP_STRENGTH=${DARCY_CHI_COLLISION_VP_STRENGTH:-0.25}
DARCY_COST_EVERY=${DARCY_COST_EVERY:-1000000}
TOPO_BENCHMARK_ENABLE=${TOPO_BENCHMARK_ENABLE:-false}
ALPHA=${ALPHA:-800000.0}


TOPO_BENCHMARK_ENABLE=${TOPO_BENCHMARK_ENABLE:-true}
TOPO_BENCHMARK_EVERY=${TOPO_BENCHMARK_EVERY:-$DARCY_COST_EVERY}
TOPO_BENCHMARK_FILENAME=${TOPO_BENCHMARK_FILENAME:-topo_benchmark_0348.csv}
TOPO_BENCHMARK_FORCE_ENABLE=${TOPO_BENCHMARK_FORCE_ENABLE:-true}
TOPO_BENCHMARK_DRAG_LIFT_ENABLE=${TOPO_BENCHMARK_DRAG_LIFT_ENABLE:-true}
TOPO_BENCHMARK_FLOW_DIR_X=${TOPO_BENCHMARK_FLOW_DIR_X:-1.0}
TOPO_BENCHMARK_FLOW_DIR_Y=${TOPO_BENCHMARK_FLOW_DIR_Y:-0.0}
TOPO_BENCHMARK_LIFT_DIR_X=${TOPO_BENCHMARK_LIFT_DIR_X:-0.0}
TOPO_BENCHMARK_LIFT_DIR_Y=${TOPO_BENCHMARK_LIFT_DIR_Y:-1.0}

ROTATION_ANGLE=${ROTATION_ANGLE:-1.5}
RANDOM_ROTATION_SIGN=${RANDOM_ROTATION_SIGN:-true}
GRID_SHIFT_ENABLE=${GRID_SHIFT_ENABLE:-true}
THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE:-true}
THERMOSTAT_MODE=${THERMOSTAT_MODE:-cell_relative_rescale}
THERMOSTAT_EVERY=${THERMOSTAT_EVERY:-1}
THERMOSTAT_TARGET_KBT=${THERMOSTAT_TARGET_KBT:--1.0}
THERMOSTAT_MIN_PARTICLES=${THERMOSTAT_MIN_PARTICLES:-3}
DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER:-fluid}
SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER:-fluid}

FORCE_BUILD=${FORCE_BUILD:-0}
BUILD_IF_STALE=${BUILD_IF_STALE:-1}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-${SRC_LIVE_VIS_ENABLE:-1}}
LIVE_VIS_FIELD=${LIVE_VIS_FIELD:-Ux}
LIVE_VIS_EVERY=${LIVE_VIS_EVERY:-25}
LIVE_VIS_NX=${LIVE_VIS_NX:-600}
LIVE_VIS_NY=${LIVE_VIS_NY:-300}
LIVE_VIS_CLIP=${LIVE_VIS_CLIP:--1}
LIVE_VIS_GAIN=${LIVE_VIS_GAIN:-1.0}
LIVE_VIS_SMOOTH_PASSES=${LIVE_VIS_SMOOTH_PASSES:-50}
LIVE_VIS_COLORMAP=${LIVE_VIS_COLORMAP:-blue_red}
LIVE_VIS_WINDOW_SCALE=${LIVE_VIS_WINDOW_SCALE:-1}
LIVE_VIS_VSYNC=${LIVE_VIS_VSYNC:-0}
LIVE_VIS_CUDA_FIELD=${LIVE_VIS_CUDA_FIELD:-1}
LIVE_VIS_CUDA_SNAPSHOT=${LIVE_VIS_CUDA_SNAPSHOT:-1}
LIVE_VIS_LOG_SOURCE=${LIVE_VIS_LOG_SOURCE:-0}
LIVE_VIS_CONTROL_FILE=${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}
LIVE_VIS_CONTROL_EVERY=${LIVE_VIS_CONTROL_EVERY:-1}
LIVE_VIS_CONTROL_LOG=${LIVE_VIS_CONTROL_LOG:-0}
LIVE_VIS_HOLD_ON_EXIT=${LIVE_VIS_HOLD_ON_EXIT:-1}
export SRC_LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"

REQUIRE_VALIDATED_SEGMENTED_RESIDENT=${REQUIRE_VALIDATED_SEGMENTED_RESIDENT:-1}

TAG=${TAG:-step_darcy_mean_outward_chiVP_0425_${NX}x${NY}_u${UIN}_alpha${ALPHA}}
RUN_ROOT=${RUN_ROOT:-runs/${TAG}}
STATE=${STATE:-$RUN_ROOT/init/backward_step_darcy_${NX}x${NY}_g${GAMMA}.smpcd}
CHI_FILE=${CHI_FILE:-$RUN_ROOT/chi/chi_backward_step_${NX}x${NY}_x${STEP_XMAX}_y${STEP_YMAX}_f32.f32}
PARAMS=${PARAMS:-$RUN_ROOT/params/src_classic_darcy_step.kv}
OUT_DIR=${OUT_DIR:-$RUN_ROOT/output}
TIME_FILE=${TIME_FILE:-$RUN_ROOT/logs/src_classic_darcy_step.time}
ENV_FILE=${ENV_FILE:-$RUN_ROOT/logs/environment_0425.env}

USER_BIN_SET=0
if [[ -n "${BIN+x}" ]]; then USER_BIN_SET=1; fi
if truthy_0425 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "0" ]]; then
  BIN=build/src_mpcd_base_cuda_q6_resident_0400_livevis
else
  BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}
fi

needs_build=0
if truthy_0425 "$FORCE_BUILD" || [[ ! -x "$BIN" ]]; then
  needs_build=1
elif truthy_0425 "$BUILD_IF_STALE"; then
  if find src include scripts/build_src_mpcd_cuda_q6_resident_0400.sh -type f -newer "$BIN" -print -quit | grep -q .; then
    needs_build=1
  fi
fi
if [[ "$needs_build" == "1" ]]; then
  if truthy_0425 "$LIVE_VIS_ENABLE"; then
    MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
  else
    OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
  fi
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0425-step-darcy] ERROR missing binary: $BIN" >&2
  exit 127
fi

mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/chi" "$RUN_ROOT/params" "$RUN_ROOT/logs" "$OUT_DIR"

python3 - "$CHI_FILE" "$STATE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" "$UINIT" "$INACTIVE_SLOTS" "$STEP_XMIN" "$STEP_XMAX" "$STEP_YMIN" "$STEP_YMAX" <<'PYGEN'
import math, os, random, struct, sys
(chi_file,state_file,Lx,Ly,Nx,Ny,gamma,kBT,seed,uinit,inactive_slots,
 sxmin,sxmax,symin,symax) = sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny)
gamma=int(gamma); kBT=float(kBT); seed=int(seed); uinit=float(uinit); inactive_slots=int(inactive_slots)
sxmin=float(sxmin); sxmax=float(sxmax); symin=float(symin); symax=float(symax)
rng=random.Random(seed)
dx=Lx/Nx; dy=Ly/Ny; mass0=1.0; sigma=math.sqrt(kBT/mass0) if kBT>0 else 0.0

def in_step(x,y):
    return (sxmin <= x <= sxmax) and (symin <= y <= symax)

# Chi field at cell centers: 0 in step solid, 1 in fluid.
chi=[]
solid_cells=0
for j in range(Ny):
    yc=(j+0.5)*dy
    for i in range(Nx):
        xc=(i+0.5)*dx
        val=0.0 if in_step(xc,yc) else 1.0
        if val == 0.0: solid_cells += 1
        chi.append(val)
os.makedirs(os.path.dirname(chi_file) or '.', exist_ok=True)
with open(chi_file, 'wb') as f:
    f.write(struct.pack('<%df' % len(chi), *chi))

x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
active_cells=0; skipped_cells=0; rejected=0
for j in range(Ny):
    for i in range(Nx):
        xc=(i+0.5)*dx; yc=(j+0.5)*dy
        if in_step(xc,yc):
            skipped_cells += 1
            continue
        active_cells += 1
        x0=i*dx; y0=j*dy
        for _ in range(gamma):
            ok=False
            for _try in range(1000):
                xp=x0+dx*rng.random(); yp=y0+dy*rng.random()
                if in_step(xp,yp):
                    rejected += 1
                    continue
                ok=True
                break
            if not ok:
                continue
            ux=uinit + (sigma*rng.gauss(0.0,1.0) if sigma>0 else 0.0)
            uy=(sigma*rng.gauss(0.0,1.0) if sigma>0 else 0.0)
            x.append(xp); y.append(yp); vx.append(ux); vy.append(uy); typ.append(0); mass.append(mass0); role.append(1)

fluid_mass=sum(m for m,r in zip(mass,role) if r==1)
if fluid_mass>0:
    mvx=sum(m*u for m,u,r in zip(mass,vx,role) if r==1)/fluid_mass
    mvy=sum(m*v for m,v,r in zip(mass,vy,role) if r==1)/fluid_mass
    for idx,r in enumerate(role):
        if r==1:
            vx[idx]=vx[idx]-mvx+uinit
            vy[idx]=vy[idx]-mvy

for _ in range(inactive_slots):
    x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0); typ.append(0); mass.append(mass0); role.append(0)

os.makedirs(os.path.dirname(state_file) or '.', exist_ok=True)
magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE'))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
n=len(x)
with open(state_file,'wb') as f:
    f.write(magic)
    f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4))
    f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in [(x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')]:
        f.write(struct.pack('<%d%s'%(n,fmt),*arr))

print(f'[0425-step-chi] output={chi_file} grid={Nx}x{Ny} solidCells={solid_cells}')
print(f'[0425-step-state] output={state_file} grid={Nx}x{Ny} activeCells={active_cells} skippedCells={skipped_cells} fluid={sum(1 for r in role if r==1)} inactive={sum(1 for r in role if r==0)} rejected={rejected}')
PYGEN

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
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = solid
bcY = solid

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = $INLET_FACE inlet $INLET_SMIN $INLET_SMAX $UIN 0.0 0 $PARTICLE_MASS
openBoundarySegment1 = $OUTLET_FACE outlet $OUTLET_SMIN $OUTLET_SMAX $UIN 0.0 0 $PARTICLE_MASS

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.25
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
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

immersedSolidEnable = false

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $PARTICLE_MASS
wallKBT = $WALL_KBT
wallThermalNoise = 0.0

srcClassicCudaModeEnable = $SRC_CLASSIC_CUDA_MODE_ENABLE
projectionEnable = $PROJECTION_ENABLE
projectionBackend = $PROJECTION_BACKEND
projectionOperator = $PROJECTION_OPERATOR
projectionMaxIterations = $PROJECTION_MAX_ITERATIONS
projectionTolerance = $PROJECTION_TOLERANCE
q6ProjectionStrength = $Q6_PROJECTION_STRENGTH
resamplingEnable = $RESAMPLING_ENABLE
cudaResamplingChiFilterEnable = $CUDA_RESAMPLING_CHI_FILTER_ENABLE
cudaResamplingChiMin = $CUDA_RESAMPLING_CHI_MIN
cudaResamplingEmptyRefillEnable = $CUDA_RESAMPLING_EMPTY_REFILL_ENABLE
cudaResamplingEmptyRefillReference = $CUDA_RESAMPLING_EMPTY_REFILL_REFERENCE
cudaResamplingEmptyRefillGamma = $CUDA_RESAMPLING_EMPTY_REFILL_GAMMA
cudaResamplingEmptyRefillTargetFraction = $CUDA_RESAMPLING_EMPTY_REFILL_TARGET_FRACTION
cudaResamplingEmptyRefillMemoryMaxAge = $CUDA_RESAMPLING_EMPTY_REFILL_MEMORY_MAX_AGE
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

darcyBrinkmanEnable = true
darcyChiMode = file
darcyChiFile = $CHI_FILE
darcyChiNx = $NX
darcyChiNy = $NY
darcyChiFileFormat = $CHI_FILE_FORMAT
darcyAlphaMin = $ALPHA_MIN
darcyAlphaMax = $ALPHA
darcyQ = $DARCY_Q
darcyUSolidX = $DARCY_USOLID_X
darcyUSolidY = $DARCY_USOLID_Y
darcyCostEvery = $DARCY_COST_EVERY
darcyCostFilename = darcy_cost_0343.csv
darcyThreadsPerBlock = $DARCY_THREADS_PER_BLOCK
darcyInitialDeactivateBelowChi = $DARCY_INITIAL_DEACTIVATE_BELOW_CHI
darcyBrinkmanForcingMode = $DARCY_BRINKMAN_FORCING_MODE

darcyChiCollisionVpEnable = $DARCY_CHI_COLLISION_VP_ENABLE
darcyChiCollisionVpMode = $DARCY_CHI_COLLISION_VP_MODE
darcyChiCollisionVpGamma = $DARCY_CHI_COLLISION_VP_GAMMA
darcyChiCollisionVpMass = $DARCY_CHI_COLLISION_VP_MASS
darcyChiCollisionVpLayers = $DARCY_CHI_COLLISION_VP_LAYERS
darcyChiCollisionVpThreshold = $DARCY_CHI_COLLISION_VP_THRESHOLD
darcyChiCollisionVpStrength = $DARCY_CHI_COLLISION_VP_STRENGTH

topoBenchmarkEnable = $TOPO_BENCHMARK_ENABLE
topoBenchmarkEvery = $TOPO_BENCHMARK_EVERY
topoBenchmarkFilename = $TOPO_BENCHMARK_FILENAME
topoBenchmarkForceEnable = $TOPO_BENCHMARK_FORCE_ENABLE
topoBenchmarkDragLiftEnable = $TOPO_BENCHMARK_DRAG_LIFT_ENABLE
topoBenchmarkFlowDirX = $TOPO_BENCHMARK_FLOW_DIR_X
topoBenchmarkFlowDirY = $TOPO_BENCHMARK_FLOW_DIR_Y
topoBenchmarkLiftDirX = $TOPO_BENCHMARK_LIFT_DIR_X
topoBenchmarkLiftDirY = $TOPO_BENCHMARK_LIFT_DIR_Y

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_STATE_EVERY
summaryRoleFilter = $SUMMARY_ROLE_FILTER
dumpRoleFilter = $DUMP_ROLE_FILTER
numThreads = $THREADS
PARAMS

if truthy_0425 "$LIVE_VIS_ENABLE"; then
  if [[ ! -f "$LIVE_VIS_CONTROL_FILE" ]]; then
    cat > "$LIVE_VIS_CONTROL_FILE" <<CONTROL
field = ${LIVE_VIS_FIELD}
clip = ${LIVE_VIS_CLIP}
gain = ${LIVE_VIS_GAIN}
smoothPasses = ${LIVE_VIS_SMOOTH_PASSES}
colormap = ${LIVE_VIS_COLORMAP}
quiverScale = ${SRC_LIVE_VIS_QUIVER_SCALE:--1}
CONTROL
  fi
fi

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

# 0426 fast resident CUDA collision/thermostat controls.
# These defaults reproduce the optimized resident SRC path observed in the
# solid/full-face validation and avoid the slow generic collision/thermostat
# path in Darcy/chi demo scripts. Set MPCD_DARCY_FASTFLAGS_ENABLE=0 to disable.
export_src_cuda_resident_fastflags_0426() {
  case "${MPCD_DARCY_FASTFLAGS_ENABLE:-1}" in
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


# CUDA classic SRC / segmented boundary / persistent collision controls.
export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
if truthy_0425 "$REQUIRE_VALIDATED_SEGMENTED_RESIDENT"; then
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
else
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=0
fi
export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=1
export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0
export MPCD_CUDA_IMMERSED_RECTANGLE_0247=0
export MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1


export_src_cuda_resident_fastflags_0426
integ_apply_path_env_0431

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

env | grep -E '^(MPCD_DARCY_FASTFLAGS_ENABLE=|MPCD_CUDA_|SRC_LIVE_VIS_|MPCD_LIVE_VIS_ENABLE=|OMP_|BIN=|CHI_FILE=|DARCY_|TOPO_BENCHMARK_|ALPHA=|U0=|UIN=|DT=|KBT=|NX=|NY=|STEP_)' | sort > "$ENV_FILE"

echo "[0425-step-darcy] binary=$BIN"
echo "[0425-step-darcy] params=$PARAMS"
echo "[0425-step-darcy] output=$OUT_DIR"
echo "[0425-step-darcy] chi=$CHI_FILE format=$CHI_FILE_FORMAT alpha=$ALPHA"
echo "[0425-step-darcy] stepRect=[$STEP_XMIN,$STEP_XMAX]x[$STEP_YMIN,$STEP_YMAX]"
echo "[0425-step-darcy] segments: ${INLET_FACE}:in[$INLET_SMIN,$INLET_SMAX] -> ${OUTLET_FACE}:out[$OUTLET_SMIN,$OUTLET_SMAX]"
echo "[0425-step-darcy] model: forcing=$DARCY_BRINKMAN_FORCING_MODE chiVP=$DARCY_CHI_COLLISION_VP_ENABLE strength=$DARCY_CHI_COLLISION_VP_STRENGTH initialDeactivateBelowChi=$DARCY_INITIAL_DEACTIVATE_BELOW_CHI"
echo "[0425-step-darcy] livevis=$LIVE_VIS_ENABLE hold=$LIVE_VIS_HOLD_ON_EXIT field=$LIVE_VIS_FIELD"

/usr/bin/time -o "$TIME_FILE" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$PARAMS"

echo "[0425-step-darcy] time=$(cat "$TIME_FILE")"
echo "[0425-step-darcy] darcy csv=$OUT_DIR/darcy_cost_0343.csv"
if [[ "$TOPO_BENCHMARK_ENABLE" == "true" || "$TOPO_BENCHMARK_ENABLE" == "1" || "$TOPO_BENCHMARK_ENABLE" == "TRUE" ]]; then
  echo "[0425-step-darcy] topo benchmark csv=$OUT_DIR/$TOPO_BENCHMARK_FILENAME"
fi
echo "[0425-step-darcy] dumps/root=$RUN_ROOT"

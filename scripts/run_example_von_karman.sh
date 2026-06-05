#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BIN="${BIN:-build/src_mpcd_base}"
AUTO_BUILD="${AUTO_BUILD:-0}"
BUILD_PROFILE="${BUILD_PROFILE:-native}"
CXX="${CXX:-g++}"
THREADS="${THREADS:-8}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-false}"
if [[ -n "${OMP_PLACES:-}" ]]; then export OMP_PLACES; fi
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

build_solver() {
  mkdir -p "$(dirname "$BIN")"
  local common_flags="-std=c++17 -Wall -Wextra -fopenmp"
  local opt_flags
  case "$BUILD_PROFILE" in
    safe) opt_flags="-O2" ;;
    release) opt_flags="-O3 -DNDEBUG" ;;
    native) opt_flags="-O3 -DNDEBUG -march=native -mtune=native" ;;
    lto-native) opt_flags="-O3 -DNDEBUG -march=native -mtune=native -flto" ;;
    *) echo "Unknown BUILD_PROFILE='$BUILD_PROFILE'. Expected: safe, release, native, lto-native" >&2; exit 2 ;;
  esac
  local flags="${CXXFLAGS:-$common_flags $opt_flags}"
  echo "[build] CXX=$CXX"
  echo "[build] BUILD_PROFILE=$BUILD_PROFILE"
  echo "[build] BIN=$BIN"
  $CXX $flags -Iinclude \
    src/main_src_mpcd_base.cpp \
    src/params_io_base.cpp \
    src/cell_grid.cpp \
    src/boundary_base.cpp \
    src/fluid_domain.cpp \
    src/immersed_solid.cpp \
    src/src_collision.cpp \
    src/thermostat.cpp \
    src/elliptic_projection.cpp \
    src/q6_projection_adapter.cpp \
    src/closed_capacity_response.cpp \
    src/src_mpcd_base.cpp \
    src/runtime_summary.cpp \
    src/particle_state.cpp \
    src/state_smpcd_io.cpp \
    src/weighted_resampling.cpp \
    -o "$BIN"
}

if [[ "$AUTO_BUILD" == "1" || ! -x "$BIN" ]]; then
  build_solver
fi
if [[ ! -x "$BIN" ]]; then
  echo "Missing executable '$BIN'." >&2
  exit 127
fi

generate_state() {
  local output="$1" Lx="$2" Ly="$3" Nx="$4" Ny="$5" gamma="$6" kBT="$7" seed="$8" mode="$9" mean_ux="${10}" mean_uy="${11}" amp="${12}" axmax="${13}" solid_rect="${14:-none}"
  python3 - "$output" "$Lx" "$Ly" "$Nx" "$Ny" "$gamma" "$kBT" "$seed" "$mode" "$mean_ux" "$mean_uy" "$amp" "$axmax" "$solid_rect" <<'PY'
import math, os, random, struct, sys
out,Lx,Ly,Nx,Ny,gamma,kBT,seed,mode,mean_ux,mean_uy,amp,axmax,solid = sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny); gamma=int(gamma); kBT=float(kBT)
seed=int(seed); mean_ux=float(mean_ux); mean_uy=float(mean_uy); amp=float(amp); axmax=float(axmax)
solids=[]
if solid != 'none':
    raw = solid.strip()
    kind = 'rect'
    payload = raw
    if ':' in raw:
        kind, payload = raw.split(':', 1)
        kind = kind.strip().lower()
    p=[float(v) for v in payload.replace(',', ' ').split()]
    if kind in ('rect','rectangle','box','step'):
        if len(p)!=4: raise SystemExit('solid rect must be xmin,xmax,ymin,ymax')
        solids.append(('rect', tuple(p)))
    elif kind in ('circle','disk','disc','cylinder'):
        if len(p)!=3: raise SystemExit('solid circle must be cx,cy,r')
        if p[2] <= 0.0: raise SystemExit('solid circle radius must be > 0')
        solids.append(('circle', tuple(p)))
    else:
        raise SystemExit(f'unsupported solid spec kind: {kind}')
active_x_max = Lx if axmax < 0.0 else axmax
rng=random.Random(seed)
dx=Lx/Nx; dy=Ly/Ny; mass0=1.0; sigma=math.sqrt(kBT/mass0) if kBT > 0 else 0.0
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
def in_rect(xp,yp,r):
    xmin,xmax,ymin,ymax=r
    return xmin <= xp <= xmax and ymin <= yp <= ymax
def in_circle(xp,yp,c):
    cx,cy,rr=c
    return (xp-cx)*(xp-cx) + (yp-cy)*(yp-cy) <= rr*rr
def in_solid(xp,yp):
    for kind, geom in solids:
        if kind == 'rect' and in_rect(xp,yp,geom): return True
        if kind == 'circle' and in_circle(xp,yp,geom): return True
    return False
def base_velocity(xp,yp):
    if mode == 'zero': return 0.0, 0.0
    if mode == 'uniform': return mean_ux, mean_uy
    if mode == 'taylor_green':
        ux=amp*math.sin(2*math.pi*xp/Lx)*math.cos(2*math.pi*yp/Ly)
        uy=-amp*math.cos(2*math.pi*xp/Lx)*math.sin(2*math.pi*yp/Ly)
        return ux+mean_ux, uy+mean_uy
    if mode == 'poiseuille_x':
        eta=(yp-0.5*Ly)/(0.5*Ly)
        return mean_ux*max(0.0,1.0-eta*eta), mean_uy
    raise SystemExit(f'unsupported mode: {mode}')
for j in range(Ny):
    cy=(j+0.5)*dy
    for i in range(Nx):
        cx=(i+0.5)*dx
        if cx > active_x_max or in_solid(cx, cy):
            continue
        x0=i*dx; y0=j*dy
        for _ in range(gamma):
            ok=False
            for _try in range(1000):
                xp=x0+dx*rng.random(); yp=y0+dy*rng.random()
                if xp <= active_x_max and not in_solid(xp, yp):
                    ok=True; break
            if not ok: continue
            ux,uy=base_velocity(xp,yp)
            if sigma>0:
                ux += sigma*rng.gauss(0,1); uy += sigma*rng.gauss(0,1)
            x.append(xp); y.append(yp); vx.append(ux); vy.append(uy); typ.append(0); mass.append(mass0); role.append(1)
if not x: raise SystemExit('generated zero particles')
mt=sum(mass); mvx=sum(m*u for m,u in zip(mass,vx))/mt; mvy=sum(m*u for m,u in zip(mass,vy))/mt
tvx=mean_ux if mode in ('uniform','poiseuille_x') else 0.0; tvy=mean_uy if mode in ('uniform','poiseuille_x') else 0.0
vx=[u-mvx+tvx for u in vx]; vy=[v-mvy+tvy for v in vy]
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
print(f'[state] wrote {out} with {n} particles')
PY
}

write_common_runtime_block() {
  cat <<PARAMS
rotationAngle = 1.5
randomRotationSign = true
gridShiftEnable = true
rngSeed = ${SEED}

projectionEnable = true
projectionMaxIterations = ${PROJECTION_MAX_ITERATIONS}
projectionTolerance = ${PROJECTION_TOLERANCE}
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = ${Q6_PROJECTION_STRENGTH}

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = ${KBT}

summaryEvery = ${SUMMARY_EVERY}
dumpStateEvery = ${DUMP_STATE_EVERY}
numThreads = ${THREADS}
PARAMS
}

write_resampling_block() {
  cat <<PARAMS
resamplingEnable = true
resamplingPopulationNMin = ${RESAMP_N_MIN}
resamplingPopulationNTarget = ${RESAMP_N_TARGET}
resamplingPopulationNMax = ${RESAMP_N_MAX}
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP}
resamplingTargetCellMass = ${GAMMA}
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = ${RESAMP_POOR_FRACTION}
resamplingRichCellMassFraction = ${RESAMP_RICH_FRACTION}
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = ${RESAMP_MASS_RENORM_PERIOD}
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = ${RESAMP_MASS_MIN}
resamplingParticleMassMax = ${RESAMP_MASS_MAX}
resamplingLatentActivationEnable = false
PARAMS
}


restart_slug_from_state() {
  local base_name
  base_name="$(basename "$1")"
  base_name="${base_name%.smpcd}"
  printf '%s' "$base_name" | tr -c 'A-Za-z0-9._-' '_'
}

default_run_root_for_case() {
  local case_dir="$1"
  if [[ -n "${RESTART_STATE:-}" ]]; then
    printf 'runs/%s_restart/%s' "$case_dir" "$(restart_slug_from_state "$RESTART_STATE")"
  else
    printf 'runs/%s' "$case_dir"
  fi
}

absolute_path_for_guard() {
  local path_value="$1"
  if [[ "$path_value" == /* ]]; then
    printf '%s\n' "$path_value"
  else
    printf '%s/%s\n' "$ROOT_DIR" "$path_value"
  fi
}
prepare_run_root() {
  if [[ "${CLEAN_RUN_ROOT}" == "1" ]]; then
    if [[ -n "${RESTART_STATE:-}" ]]; then
      local restart_abs run_abs
      restart_abs="$(absolute_path_for_guard "$RESTART_STATE")"
      run_abs="$(absolute_path_for_guard "$RUN_ROOT")"
      case "$restart_abs" in
        "$run_abs"|"$run_abs"/*)
          echo "ERROR: RESTART_STATE is inside RUN_ROOT while CLEAN_RUN_ROOT=1." >&2
          echo "       RESTART_STATE=$RESTART_STATE" >&2
          echo "       RUN_ROOT=$RUN_ROOT" >&2
          echo "       Use a different RUN_ROOT or set CLEAN_RUN_ROOT=0." >&2
          exit 2
          ;;
      esac
    fi
    rm -rf "$RUN_ROOT"
  fi
  mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/params" "$RUN_ROOT/logs"
}

prepare_initial_state_or_restart() {
  local generated_state="$1"
  shift
  if [[ -n "${RESTART_STATE:-}" ]]; then
    if [[ ! -f "$RESTART_STATE" ]]; then
      echo "ERROR: RESTART_STATE does not exist: $RESTART_STATE" >&2
      exit 2
    fi
    STATE_FILE="$RESTART_STATE"
    echo "[restart] using dump as inputState: $STATE_FILE"
    echo "[restart] writing new run to: $RUN_ROOT"
  else
    STATE_FILE="$generated_state"
    generate_state "$STATE_FILE" "$@"
  fi
}

run_case() {
  echo "[run] binary : $BIN"
  echo "[run] params : $PARAMS_FILE"
  echo "[run] output : $OUT_DIR"
  if [[ "${LIVE_PROGRESS}" == "1" || "${LIVE_PROGRESS}" == "true" || "${LIVE_PROGRESS}" == "TRUE" || "${LIVE_PROGRESS}" == "on" || "${LIVE_PROGRESS}" == "ON" ]]; then
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$PARAMS_FILE" 2> "$TIME_FILE" | tee "$LOG_FILE"
  else
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$PARAMS_FILE" > "$LOG_FILE" 2> "$TIME_FILE"
  fi
  cat "$TIME_FILE"
  echo "[run] summary: $OUT_DIR/summary_runtime.csv"
}


NX="${NX:-128}"
NY="${NY:-48}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-10000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
DT="${DT:-0.0005}"
KBT="${KBT:-0.001}"
SEED="${SEED:-1620162}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-3}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-3}"
RESAMP_N_MIN="${RESAMP_N_MIN:-1}"
RESAMP_N_TARGET="${RESAMP_N_TARGET:-20}"
RESAMP_N_MAX="${RESAMP_N_MAX:-202}"
RESAMP_POP_MAX_SPLITS_PER_CELL="${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}"
RESAMP_POP_MAX_SPLITS_PER_STEP="${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}"
RESAMP_POP_MAX_EXTRACT_PER_CELL="${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}"
RESAMP_POP_MAX_EXTRACT_PER_STEP="${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}"
RESAMP_POOR_FRACTION="${RESAMP_POOR_FRACTION:-0.90}"
RESAMP_RICH_FRACTION="${RESAMP_RICH_FRACTION:-1.10}"
RESAMP_MASS_RENORM_PERIOD="${RESAMP_MASS_RENORM_PERIOD:-10000}"
RESAMP_MASS_MIN="${RESAMP_MASS_MIN:-0.5}"
RESAMP_MASS_MAX="${RESAMP_MASS_MAX:-2.0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
RESTART_STATE="${RESTART_STATE:-}"

CASE_NAME="von_karman"
Lx="${Lx:-3}"
Ly="${Ly:-1.}"
NX="${NX:-128}"
NY="${NY:-48}"
UIN="${UIN:-10}"
CYLINDER_CX="${CYLINDER_CX:-0.40}"
CYLINDER_R="${CYLINDER_R:-0.16}"
CYLINDER_Y_OFFSET="${CYLINDER_Y_OFFSET:-0.02}"
CYLINDER_CY="${CYLINDER_CY:-$(python3 - <<PY
Ly = float('${Ly}')
off = float('${CYLINDER_Y_OFFSET}')
print(f'{0.5*Ly + off:.17g}')
PY
)}"
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-1}"
INLET_RAMP_END_TIME="${INLET_RAMP_END_TIME:-0.25}"
OUTLET_MODE="${OUTLET_MODE:-hybrid}"
OUTLET_HYBRID_BLEND="${OUTLET_HYBRID_BLEND:-0.0}"
OUTLET_FEEDBACK_GAIN="${OUTLET_FEEDBACK_GAIN:-0.0}"
KEEP_MEAN_FLOW_ENABLE="${KEEP_MEAN_FLOW_ENABLE:-false}"
RUN_ROOT="${RUN_ROOT:-$(default_run_root_for_case example_von_karman)}"
prepare_run_root
GENERATED_STATE_FILE="$RUN_ROOT/init/von_karman_${NX}x${NY}_g${GAMMA}_seed${SEED}.smpcd"
STATE_FILE="$GENERATED_STATE_FILE"
PARAMS_FILE="$RUN_ROOT/params/von_karman.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/von_karman.log"
TIME_FILE="$RUN_ROOT/logs/von_karman.time"
SOLID_CIRCLE="circle:${CYLINDER_CX},${CYLINDER_CY},${CYLINDER_R}"

prepare_initial_state_or_restart "$GENERATED_STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" $((SEED+44)) uniform "$UIN" 0.0 0.0 -1.0 "$SOLID_CIRCLE"
mkdir -p "$OUT_DIR"
cat > "$PARAMS_FILE" <<PARAMS
inputState = ${STATE_FILE}
outputDir = ${OUT_DIR}

Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}

dt = ${DT}
nSteps = ${STEPS}

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = ${KEEP_MEAN_FLOW_ENABLE}
targetMeanUx = ${UIN}
targetMeanUy = 0.0

bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
rotationAngle = 1.5

inletUxLeft = ${UIN}
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = ${INLET_RAMP_END_TIME}
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = flat_taper_y
inletVelocityWallTaperCells = 2.0
inletKBT = -1.0
inletThermalNoise = 1.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = ${INLET_RESERVOIR_CELLS}
inletTargetOccupancy = ${GAMMA}
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet   0.0 1.0 ${UIN} 0.0 0 1.0
openBoundarySegment1 = right outlet 0.0 1.0 0.0 0.0 0 1.0
openBoundaryOutletMode = ${OUTLET_MODE}
openBoundaryOutletHybridBlend = ${OUTLET_HYBRID_BLEND}
openBoundaryOutletFeedbackGain = ${OUTLET_FEEDBACK_GAIN}

projectionOperator = elliptic_fv_cg
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidCloseCutFaces = true
projectionImmersedSolidFluidFractionThreshold = 0.5
projectionAllowUnmaskedImmersedSolid = false

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
wallThermalNoise = 1.0

$(write_common_runtime_block)
$(write_resampling_block)
PARAMS

echo "[case] von Karman cylinder"
echo "[case] Lx=${Lx} Ly=${Ly} Nx=${NX} Ny=${NY} UIN=${UIN}"
echo "[case] cylinder: cx=${CYLINDER_CX} cy=${CYLINDER_CY} r=${CYLINDER_R} y_offset=${CYLINDER_Y_OFFSET}"
echo "[case] keepMeanFlowEnable=${KEEP_MEAN_FLOW_ENABLE} outletMode=${OUTLET_MODE}"
run_case

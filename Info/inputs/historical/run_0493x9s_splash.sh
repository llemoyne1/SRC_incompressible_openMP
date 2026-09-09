#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x9s — liquid/vacuum splash potential test using the qualified x9r
# capillary limiter.  TARGET=wall impacts the solid bottom wall directly;
# TARGET=puddle adds a flat, initially quiescent liquid layer.
CASE_LABEL="splash_0493x9s"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"
TOPOLOGY=closed_box
TARGET="${TARGET:-wall}"
case "$TARGET" in wall|puddle) ;; *) echo "[0493x9s] ERROR TARGET must be wall or puddle" >&2; exit 2;; esac
RUN_ROOT="${RUN_ROOT:-runs/0493x9s_splash_${TARGET}_V085}"

# Geometry: retain h=1/256 and the 400-cell vertical extent used by the
# well-characterized VK/x9 campaigns.  800 cells in x gives 10 drop diameters
# for the default R/h=40 drop, leaving generous lateral splash clearance.
NX="${NX:-800}"; NY="${NY:-400}"
Lx="${Lx:-3.125}"; Ly="${Ly:-1.5625}"

# Default microscopic/capillary profile follows the clean recent x9r runs.
# It intentionally does NOT claim the old VK nu/D calibration because KBT,
# particle mass and dt differ; only h, gamma, collision angle and grid-shift
# geometry are inherited here.
LIQUID_TYPE="${LIQUID_TYPE:-1}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
SIGMA_ACTIVE="${SIGMA_ACTIVE:-940.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"
CONTACT_ANGLE_DEG="${CONTACT_ANGLE_DEG:-90.0}"
KINETIC_REFLECTION_FRACTION="${KINETIC_REFLECTION_FRACTION:-0.0}"
EVAPORATION_TARGET_TYPE="${EVAPORATION_TARGET_TYPE:--1}"

GAMMA="${GAMMA:-20}"                       # déjà bon
DT="${DT:-0.002}"                          # au lieu de 0.001
KBT="${KBT:-0.00125}"                        # au lieu de 1.25e-6
LIQUID_MASS="${LIQUID_MASS:-1.0}"          # au lieu de 10
PARTICLE_MASS="${PARTICLE_MASS:-$LIQUID_MASS}"
WALL_VP_MASS="${WALL_VP_MASS:-$LIQUID_MASS}"

# Initial drop and impact control.  Gravity is deliberately modest: the
# initial downward velocity controls Weber number while the drop remains
# capillary-coherent during the fall.
DROP_RADIUS_CELLS="${DROP_RADIUS_CELLS:-40}"
DROP_CENTER_X="${DROP_CENTER_X:-1.5625}"
DROP_CENTER_Y="${DROP_CENTER_Y:-1.}"
DROP_VX="${DROP_VX:-0.0}"
DROP_VY="${DROP_VY:--0.35}"
GRAVITY_Y="${GRAVITY_Y:--0.005}"
PUDDLE_DEPTH_CELLS="${PUDDLE_DEPTH_CELLS:-40}"
SEED="${SEED:-493950}"

STEPS="${STEPS:-20000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-20}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-5000}"
DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"
SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
THREADS="${THREADS:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"
LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
FILTERED_RECORD_FIELDS="${FILTERED_RECORD_FIELDS:-mass,ux,uy}"
FILTERED_RECORD_EVERY="${FILTERED_RECORD_EVERY:-50}"

# Avec filterMode=none, inutile d'échantillonner à chaque step :
# on ne calcule les champs du recorder qu'aux steps réellement enregistrés.
FILTERED_RECORD_SAMPLE_EVERY="${FILTERED_RECORD_SAMPLE_EVERY:-50}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-2000}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_EXTERNAL_SPECIES=0
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"

SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false

GEN_CASE=tg
U0=0.0
VELOCITY_MODE=zero
PARTICLE_MASS="$LIQUID_MASS"
BACKGROUND_TYPE="$LIQUID_TYPE"
INACTIVE_TYPE="$LIQUID_TYPE"
TG_HOLE_ENABLE=false

suite_defaults_common_0434
suite_compute_derived_0434

read -r H DROP_RADIUS PUDDLE_DEPTH <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" "$DROP_RADIUS_CELLS" "$PUDDLE_DEPTH_CELLS" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
rc,pc=float(sys.argv[5]),float(sys.argv[6])
dx,dy=lx/nx,ly/ny
if abs(dx-dy)>1e-12*max(1.0,abs(dx),abs(dy)):
    raise SystemExit('[0493x9s] ERROR square cells required')
print(f'{dx:.17g} {rc*dx:.17g} {pc*dy:.17g}')
PY
)"

# Physical/preflight summary.  The 2-D density proxy is exactly the one used
# by the x9 Laplace term: rho_ref=(gamma*m)/h^2.
python3 - "$TARGET" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_MASS" "$DT" "$KBT" \
  "$DROP_RADIUS" "$DROP_CENTER_X" "$DROP_CENTER_Y" "$DROP_VX" "$DROP_VY" \
  "$PUDDLE_DEPTH" "$GRAVITY_Y" "$SIGMA_ACTIVE" "$SURFACE_TENSION_MIN_RADIUS_CELLS" "$STEPS" <<'PY'
import math,sys
(target,lx,ly,nx,ny,gamma,mass,dt,kbt,r,cx,cy,vx,vy,pdepth,g,sigma,rmin,steps)=sys.argv[1:]
lx=float(lx); ly=float(ly); nx=int(nx); ny=int(ny); gamma=float(gamma); mass=float(mass)
dt=float(dt); kbt=float(kbt); r=float(r); cx=float(cx); cy=float(cy); vx=float(vx); vy=float(vy)
pdepth=float(pdepth); g=float(g); sigma=float(sigma); rmin=float(rmin); steps=int(steps)
h=lx/nx
# 0493x11c-fix4-sigma0-nondim-safe: sigma=0 is valid; We/Bo diagnostics are NaN when their capillary denominator vanishes.
# 0493x11c-fix3-allow-zero-sigma:
# sigma=0 is the exact no-capillarity control needed by the paired
# Young-Laplace baseline; all geometric/time/mass scales remain >0.
if min(gamma,mass,dt,r,rmin)>0 and sigma>=0: pass
else: raise SystemExit('[0493x9s] ERROR gamma,mass,dt,R,minRadiusCells must be positive and sigma must be non-negative')
if not (0<cx-r and cx+r<lx and 0<cy-r and cy+r<ly):
    raise SystemExit('[0493x9s] ERROR initial drop intersects an external wall')
surface=0.0 if target=='wall' else pdepth
if target=='puddle' and not (0<pdepth<cy-r-2*h):
    raise SystemExit('[0493x9s] ERROR puddle must be positive and separated from drop by >=2h')
fall=max(0.0,cy-r-surface)
# Downward speed magnitude at impact for downward/zero gravity only.
v0=max(0.0,-vy)
if g<=0:
    vimp=math.sqrt(max(0.0,v0*v0+2*(-g)*fall))
else:
    vimp=v0
rho=gamma*mass/(h*h)
D=2*r
we0=((rho*v0*v0*D/sigma) if sigma > 0 else math.nan)
wei=((rho*vimp*vimp*D/sigma) if sigma > 0 else math.nan)
bo=((rho*abs(g)*D*D/sigma) if sigma > 0 else math.nan)
kmax=1.0/(rmin*h)
print('===== 0493x9s SPLASH PREFLIGHT =====')
print(f'target={target} grid={nx}x{ny} L=({lx:.8g},{ly:.8g}) h={h:.10g} gamma={gamma:g}')
print(f'fluid dt={dt:g} kBT={kbt:g} particleMass={mass:g} transportCalibration=NOT_REUSED')
print(f'drop R={r:.8g} R/h={r/h:.3f} D={D:.8g} center=({cx:.8g},{cy:.8g}) v0=({vx:.6g},{vy:.6g})')
print(f'targetSurfaceY={surface:.8g} fallClearance={fall:.8g} gravityY={g:.8g} impactSpeedProxy={vimp:.8g}')
print(f'capillary sigma={sigma:.8g} minRadiusCells={rmin:g} kappaLimit={kmax:.8g}')
print(f'nondimProxy We0={we0:.6g} WeImpact={wei:.6g} Bo={bo:.6g}')
print(f'timing steps={steps} tEnd={steps*dt:.8g} dumpsEvery={sys.argv[-1] if False else "configured-in-runner"}')
if target=='puddle': print(f'puddleDepth={pdepth:.8g} puddleDepth/h={pdepth/h:.3f}')
PY

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${TARGET}.smpcd"
OUT="$RUN_ROOT/output"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}_${TARGET}.kv"
LOG="$RUN_ROOT/logs/${CASE_LABEL}_${TARGET}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_LABEL}_${TARGET}.time"
mkdir -p "$OUT"

python3 scripts/generate_0493x9s_splash_state.py \
  --output "$STATE" --target "$TARGET" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
  --gamma "$GAMMA" --drop-center-x "$DROP_CENTER_X" --drop-center-y "$DROP_CENTER_Y" \
  --drop-radius "$DROP_RADIUS" --drop-vx "$DROP_VX" --drop-vy "$DROP_VY" \
  --puddle-depth "$PUDDLE_DEPTH" --liquid-type "$LIQUID_TYPE" --liquid-mass "$LIQUID_MASS" \
  --kBT "$KBT" --seed "$SEED"
sha256sum "$STATE" | sed 's/^/[0493x9s-init] sha256=/'

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
X9T_SPECIES_COUNT=1
X9T_VAPOR_SPECIES_LINE=""
X9T_VAPOR_RESAMPLING_LINE=""
if [[ "$EVAPORATION_TARGET_TYPE" =~ ^[0-9]+$ ]]; then
  if [[ "$EVAPORATION_TARGET_TYPE" == "$LIQUID_TYPE" ]]; then
    echo "[0493x9t] ERROR evaporation target must differ from liquid type" >&2; exit 2
  fi
  X9T_SPECIES_COUNT=2
  X9T_VAPOR_SPECIES_LINE="species1 = $EVAPORATION_TARGET_TYPE kinetic_vapor gas 0.0 1.0 $LIQUID_REFERENCE_CELL_MASS"
  X9T_VAPOR_RESAMPLING_LINE="species1ResamplingEnable = false"
elif [[ "$EVAPORATION_TARGET_TYPE" != "-1" ]]; then
  echo "[0493x9t] ERROR EVAPORATION_TARGET_TYPE must be -1 or a non-negative integer" >&2; exit 2
fi
cat > "$PARAMS" <<PARAMS_EOF
inputState = $STATE
outputDir = $OUT
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
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $SIGMA_ACTIVE
surfaceTensionMinRadiusCells = $SURFACE_TENSION_MIN_RADIUS_CELLS
phaseInterfaceKineticReflectionFraction = $KINETIC_REFLECTION_FRACTION
phaseInterfaceEvaporationTargetType = $EVAPORATION_TARGET_TYPE
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = vacuum
phaseInterfaceContactAngleDegrees = $CONTACT_ANGLE_DEG
speciesRegistryEnable = true
speciesCount = $X9T_SPECIES_COUNT
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
$X9T_VAPOR_SPECIES_LINE
$X9T_VAPOR_RESAMPLING_LINE
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x9s.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_FILL_FRACTION
PARAMS_EOF
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=1
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
export SRC_FILTERED_FIELD_RECORD_FIELDS="$FILTERED_RECORD_FIELDS"
export MPCD_FILTERED_FIELD_RECORD_FIELDS="$FILTERED_RECORD_FIELDS"

export SRC_FILTERED_FIELD_RECORD_EVERY="$FILTERED_RECORD_EVERY"
export MPCD_FILTERED_FIELD_RECORD_EVERY="$FILTERED_RECORD_EVERY"

export SRC_FILTERED_FIELD_SAMPLE_EVERY="$FILTERED_RECORD_SAMPLE_EVERY"
export MPCD_FILTERED_FIELD_SAMPLE_EVERY="$FILTERED_RECORD_SAMPLE_EVERY"

BASE_RUN_ROOT="$RUN_ROOT"
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/livevis_control_0493x9s.kv"
suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x9s.env" "$RUN_MODE"

printf '%s\n' \
  "[0493x9s-suite] target=$TARGET sigma=$SIGMA_ACTIVE minRadiusCells=$SURFACE_TENSION_MIN_RADIUS_CELLS contactAngle=$CONTACT_ANGLE_DEG" \
  "[0493x9t-suite] kineticReflectionFraction=$KINETIC_REFLECTION_FRACTION evaporationTargetType=$EVAPORATION_TARGET_TYPE" \
  "[0493x9s-suite] drop R/h=$DROP_RADIUS_CELLS center=($DROP_CENTER_X,$DROP_CENTER_Y) v=($DROP_VX,$DROP_VY) gravityY=$GRAVITY_Y" \
  "[0493x9s-suite] vacuum=1 puddleDepthCells=$([[ $TARGET == puddle ]] && echo "$PUDDLE_DEPTH_CELLS" || echo 0) dumpsEvery=$DUMP_STATE_EVERY steps=$STEPS dt=$DT" \
  "[0493x9s-suite] objective=qualitative impact/sheet/rim/splash; wall and liquid-puddle targets use identical bulk/capillary settings"

# 0493x11c-fix5-force-x9e-sigma0:
# x11c paired Young-Laplace baselines need the solved-Q6 x9e pressure gauge
# even when surfaceTensionSigma=0. Keep this opt-in so ordinary x9s runs
# preserve their historical diagnostic policy.
if suite_truthy_0434 "${MPCD_X11C_FORCE_X9E_SIGMA0:-0}"; then
  export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
  echo "[0493x11c-a] forcing x9e solved-pressure diagnostics for sigma=0 paired baseline"
fi
suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

echo "[0493x9s-suite] completed target=$TARGET output=$OUT"
echo "[0493x9s-suite] state dumps requested every $DUMP_STATE_EVERY steps"

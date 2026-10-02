#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 0493x23f — ARTICLE SEMI-COUETTE S|L|G|S
#
# Geometry:
#   y=0          : solid stationary wall, ux=0
#   0<y<hL      : liquid
#   y=hL        : single planar L/G interface
#   hL<y<Ly     : gas
#   y=Ly        : solid moving wall, ux=+Uw
#   x            : periodic
#
# Purpose:
#   Minimal single-interface tangential-transfer benchmark for the article.
#   Keep the locally characterized x23e transport point unchanged:
#     h=1/256, gamma=20, dt=0.002, alphaSRC=90 deg,
#     mL=1, kBTL=0.02, q6L=1,
#     mG=0.1, kBTG=0.08, q6G=0.
#
# Default grid 64x64, L=0.25x0.25:
#   32 liquid cells + 32 gas cells.
#
# The initial mean velocity can be the expected two-layer Couette solution
# (INIT_PROFILE=theory, default) to shorten spin-up.  INIT_PROFILE=zero is
# available as a control.
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

CASE_LABEL="${CASE_LABEL:-0493x23f_article_semi_couette_S_L_G_S}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="wall"

# -----------------------------------------------------------------------------
# Geometry chosen to preserve h=1/256 while reducing cost.
# -----------------------------------------------------------------------------
Lx="${Lx:-0.25}"
Ly="${Ly:-0.25}"
NX="${NX:-64}"
NY="${NY:-64}"
LIQUID_CELLS="${LIQUID_CELLS:-32}"

GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
STEPS="${STEPS:-8000}"
SEED="${SEED:-593171}"

WALL_SPEED="${WALL_SPEED:-0.075}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"
GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"
GAS_KBT="${GAS_KBT:-0.08}"

# x6g reads params.kBT; keep it aligned with the gas target as in x14/x23.
KBT="${KBT:-$GAS_KBT}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$GAS_KBT}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"

Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"

# Planar benchmark: no capillary forcing is needed.
SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2560.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"
PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"

# Initial mean profile.  The value 0.13309 is only a spin-up aid, not a
# measurement assumption; the article analysis must use measured rho and
# independently calibrated nu.
INIT_PROFILE="${INIT_PROFILE:-theory}"
INIT_MU_RATIO="${INIT_MU_RATIO:-0.13309}"

# -----------------------------------------------------------------------------
# Output / diagnostics.
# -----------------------------------------------------------------------------
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-velocity}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-20}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"
LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-2}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"

# Article metrology: native 64x64 rho/ux/uy every 20 steps, no smoothing.
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-20}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-20}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
RUN_ROOT="${RUN_ROOT:-runs/0493x23f_article_semi_couette_64x64_Uw0075_seed${SEED}}"

# Keep the production x14/x23 path: no species resampling/reconditioning.
GEN_CASE="tg"
U0=0.0
VELOCITY_MODE="zero"
PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"
INACTIVE_TYPE="$GAS_TYPE"
TG_HOLE_ENABLE=false
SPECIES_RESAMPLING_ENABLE=false
SPECIES_RESIDENT_MODE=off
RESAMPLING_HOST_PATCHBACK_ENABLE=0
MASS_RECONDITION_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=1
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"
RUN_OK_GENERATOR_PATH="$ROOT/scripts/$(basename "${BASH_SOURCE[0]}")"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH

suite_defaults_common_0434
suite_compute_derived_0434

# -----------------------------------------------------------------------------
# Strict geometry / transport-point checks.
# -----------------------------------------------------------------------------
read -r H HL HG P_REF NPART <<<"$(python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$LIQUID_CELLS" "$GAMMA" "$GAS_KBT" \
  "$DT" "$ROTATION_ANGLE" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2])
nx,ny=int(sys.argv[3]),int(sys.argv[4])
nl=int(sys.argv[5]); gamma=int(sys.argv[6]); tg=float(sys.argv[7])
dt=float(sys.argv[8]); ang=float(sys.argv[9])
hx=lx/nx; hy=ly/ny
if nx <= 0 or ny <= 0 or not (0 < nl < ny):
    raise SystemExit('[0493x23f] invalid grid or LIQUID_CELLS')
if abs(hx-hy) > 1e-13:
    raise SystemExit(f'[0493x23f] square cells required: hx={hx:.17g} hy={hy:.17g}')
if abs(hx-1/256) > 1e-13:
    raise SystemExit(f'[0493x23f] must preserve characterized h=1/256; got {hx:.17g}')
if abs(dt-0.002) > 1e-14:
    raise SystemExit(f'[0493x23f] must preserve dt=0.002; got {dt:.17g}')
if abs(ang-math.pi/2) > 1e-13:
    raise SystemExit(f'[0493x23f] must preserve alphaSRC=pi/2; got {ang:.17g}')
hl=nl*hy; hg=ly-hl
area=hx*hy
pref=gamma*tg/area
npart=nx*ny*gamma
print(f'{hx:.17g} {hl:.17g} {hg:.17g} {pref:.17g} {npart}')
PY
)"

if [[ "$LIQUID_CELLS" -ne $((NY/2)) ]]; then
  echo "[0493x23f] WARNING default article geometry expects equal liquid/gas thicknesses." >&2
fi

# -----------------------------------------------------------------------------
# Run layout.
# -----------------------------------------------------------------------------
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then
  rm -rf "$RUN_ROOT"
fi
suite_prepare_dirs_0434 "$RUN_ROOT"
mkdir -p "$RUN_ROOT/analysis"

STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TF="$RUN_ROOT/logs/${CASE_LABEL}.time"

# -----------------------------------------------------------------------------
# Exact two-temperature S|L|G|S state generator.
#
# Each cell contains exactly gamma particles.  Lower LIQUID_CELLS rows are
# type 1 liquid, upper rows type 2 gas.  Thermal fluctuations use the correct
# species mass and target kBT from the first frame.
#
# For INIT_PROFILE=theory:
#   aL/aG = INIT_MU_RATIO
#   u(0)=0, u(Ly)=Uw, continuity at y=HL.
# This only reduces spin-up and is NOT used as the measured reference.
# -----------------------------------------------------------------------------
python3 - "$STATE" "$RUN_ROOT/init/${CASE_LABEL}.json" \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_CELLS" \
  "$LIQUID_TYPE" "$GAS_TYPE" "$LIQUID_MASS" "$GAS_MASS" \
  "$LIQUID_KBT" "$GAS_KBT" "$SEED" "$WALL_SPEED" \
  "$INIT_PROFILE" "$INIT_MU_RATIO" <<'PYGEN'
import json, math, os, random, struct, sys

(out, meta, Lx, Ly, Nx, Ny, gamma, nliq,
 lt, gt, mL, mG, tL, tG, seed, Uw, init_mode, rmu) = sys.argv[1:]

Lx=float(Lx); Ly=float(Ly)
Nx=int(Nx); Ny=int(Ny); gamma=int(gamma); nliq=int(nliq)
lt=int(lt); gt=int(gt)
mL=float(mL); mG=float(mG)
tL=float(tL); tG=float(tG)
seed=int(seed); Uw=float(Uw); rmu=float(rmu)

if init_mode not in ('theory','zero'):
    raise SystemExit('[0493x23f-generate] INIT_PROFILE must be theory or zero')
if lt == gt:
    raise SystemExit('[0493x23f-generate] liquid/gas types must differ')
if min(mL,mG,tL,tG) <= 0:
    raise SystemExit('[0493x23f-generate] masses/kBT must be positive')

dx=Lx/Nx; dy=Ly/Ny
hL=nliq*dy; hG=Ly-hL

if init_mode == 'theory':
    aG=Uw/(hG+rmu*hL)
    aL=rmu*aG
    uI=aL*hL
else:
    aG=aL=uI=0.0

def base_u(y):
    if init_mode == 'zero':
        return 0.0
    if y < hL:
        return aL*y
    return uI + aG*(y-hL)

rng=random.Random(seed)
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]

def paired_thermal_velocities(count, pmass, pkbt):
    vals=[]
    for _ in range(count//2):
        gx=rng.gauss(0.0,1.0)
        gy=rng.gauss(0.0,1.0)
        vals.append((gx,gy))
        vals.append((-gx,-gy))
    if count % 2:
        vals.append((0.0,0.0))
    s2=sum(tx*tx+ty*ty for tx,ty in vals)
    if not s2 > 0.0:
        raise RuntimeError('degenerate thermal draw')
    scale=math.sqrt((2.0*count*pkbt)/(pmass*s2))
    return [(scale*tx,scale*ty) for tx,ty in vals]

for j in range(Ny):
    is_liquid = j < nliq
    ptype = lt if is_liquid else gt
    pmass = mL if is_liquid else mG
    pkbt = tL if is_liquid else tG
    for i in range(Nx):
        x0=i*dx; y0=j*dy
        thermal=paired_thermal_velocities(gamma,pmass,pkbt)
        for tx,ty in thermal:
            xp=x0+dx*rng.random()
            yp=y0+dy*rng.random()
            x.append(xp); y.append(yp)
            vx.append(base_u(yp)+tx); vy.append(ty)
            typ.append(ptype); mass.append(pmass); role.append(1)

# Thermal peculiar velocity has exactly zero mean in every initial cell.
# Therefore the cell-scale mean shear is the prescribed theory profile
# rather than a noisy realization whose random cell drift can exceed Uw.

os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE'))
reserved=[0]*8
reserved[0]=1
reserved[1]=1
n=len(x)

with open(out,'wb') as f:
    f.write(magic)
    f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4))
    f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in [
        (x,'d'),(y,'d'),(vx,'d'),(vy,'d'),
        (typ,'I'),(mass,'d'),(role,'B')]:
        f.write(struct.pack('<%d%s'%(n,fmt),*arr))

d={
    'case':'0493x23f_article_semi_couette_S_L_G_S',
    'Lx':Lx,'Ly':Ly,'Nx':Nx,'Ny':Ny,'h':dx,'gamma':gamma,
    'liquidCells':nliq,'liquidThickness':hL,'gasThickness':hG,
    'liquidType':lt,'gasType':gt,'liquidMass':mL,'gasMass':mG,
    'liquidKBT':tL,'gasKBT':tG,'seed':seed,'wallSpeedTop':Uw,
    'wallSpeedBottom':0.0,'initProfile':init_mode,'initMuRatio':rmu,
    'init_aL':aL,'init_aG':aG,'init_uInterface':uI,
    'particleCount':n
}
with open(meta,'w',encoding='utf-8') as f:
    json.dump(d,f,indent=2,sort_keys=True)

print(f'[0493x23f-generate] state={out}')
print(f'[0493x23f-generate] grid={Nx}x{Ny} h={dx:.12g} gamma={gamma} N={n}')
print(f'[0493x23f-generate] S|L({nliq}h)|G({Ny-nliq}h)|S, yGamma={hL:.12g}')
print(f'[0493x23f-generate] mL={mL:g} TL={tL:g} mG={mG:g} TG={tG:g}')
print(f'[0493x23f-generate] init={init_mode} aL={aL:.9g} aG={aG:.9g} uI={uI:.9g}')
PYGEN

LREF="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GREF="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

# -----------------------------------------------------------------------------
# Parameters: same local fluid point as x23e, but periodic-x / wall-y and only
# one L/G interface.  The lower wall is stationary, the upper wall moves +Uw.
# -----------------------------------------------------------------------------
cat > "$PARAMS" <<PARAMS_EOF
inputState = $STATE
outputDir = $OUT
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS

bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid
bcX = periodic
bcY = wall

openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false

wallVpEnable = false
wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $GAS_MASS
wallKBT = $GAS_KBT
wallThermalNoise = 0.0
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = $WALL_SPEED
wallUyTop = 0.0

speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LREF
species0ResamplingEnable = false
species0ThermostatTargetKBT = $LIQUID_KBT
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GREF
species1ResamplingEnable = false
species1ThermostatTargetKBT = $GAS_KBT
speciesRequireRegisteredTypes = true
speciesThermostatEnable = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x23f.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_FILL_FRACTION
PARAMS_EOF

suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"
run_ok_surface_append_params_0493x13zi \
  "$PARAMS" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
cat >> "$PARAMS" <<'PARAMS_EOF'
phaseInterfaceKineticBilateralRelocation = true
PARAMS_EOF

# -----------------------------------------------------------------------------
# CUDA/physics routing: same liquid/gas production chain used by x14/x23.
# -----------------------------------------------------------------------------
suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
run_ok_surface_export_off_flags_0493x13zi

export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$P_REF"
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1

export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
export MPCD_X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X14L_GAS_SPECULAR_REFLECTION=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="$X12A_LOCAL_THERMAL_RADIUS_CELLS"

export MPCD_X14V_GAS_KINETIC_EXCESS_KICK="${MPCD_X14V_GAS_KINETIC_EXCESS_KICK:-1}"
export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION="${MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION:-1}"
export MPCD_X14V_X6G_FACE_THERMO_TRACTION="${MPCD_X14V_X6G_FACE_THERMO_TRACTION:-0}"
export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION="${MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION:-0}"
export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION="${MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION:-0}"
export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION="${MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION:-0}"
export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC="${MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC:-0}"
export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE="${MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE:-0}"

# IMPORTANT: liquid touches the lower domain wall, so do not enable any
# closed-component/global-resultant closure intended only for isolated liquid.
export X14_DEVICE_Q6_RESULTANT_CLOSURE=0
export MPCD_X14AI_DEVICE_Q6_RESULTANT_CLOSURE=0

export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=0
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1

# Local LiveVis/recording control.
suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434

suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x23f.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_0493x23f.env" <<META
BENCHMARK=0493x23f_article_semi_couette_S_L_G_S
GEOMETRY=S|L|G|S
H=$H
LIQUID_CELLS=$LIQUID_CELLS
LIQUID_THICKNESS=$HL
GAS_THICKNESS=$HG
WALL_UX_BOTTOM=0.0
WALL_UX_TOP=$WALL_SPEED
INIT_PROFILE=$INIT_PROFILE
INIT_MU_RATIO=$INIT_MU_RATIO
GAMMA=$GAMMA
DT=$DT
ROTATION_ANGLE=$ROTATION_ANGLE
LIQUID_MASS=$LIQUID_MASS
GAS_MASS=$GAS_MASS
LIQUID_KBT=$LIQUID_KBT
GAS_KBT=$GAS_KBT
LIQUID_Q6_STRENGTH=$LIQUID_Q6_STRENGTH
GAS_Q6_STRENGTH=$GAS_Q6_STRENGTH
GAS_PRESSURE_REFERENCE=$P_REF
SURFACE_TENSION_SIGMA=$SURFACE_TENSION_SIGMA
MPCD_X14L_GAS_SPECULAR_REFLECTION=1
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=$MPCD_X14V_GAS_KINETIC_EXCESS_KICK
MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=$MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION
ARTICLE_NU_L=0.00061588
ARTICLE_NU_G=0.000729393
META

# Preflight with exact generated params and active routing.
suite_preflight_run_ok_0492 "$PARAMS"

echo
echo "===== 0493x23f ARTICLE SEMI-COUETTE S|L|G|S ====="
echo "runRoot=$RUN_ROOT"
echo "grid=${NX}x${NY} L=${Lx}x${Ly} h=$H particles=$NPART"
echo "layout: wall ux=0 | liquid ${LIQUID_CELLS}h | gas $((NY-LIQUID_CELLS))h | wall ux=+$WALL_SPEED"
echo "fluid point: gamma=$GAMMA dt=$DT alpha=$ROTATION_ANGLE"
echo "liquid: m=$LIQUID_MASS kBT=$LIQUID_KBT q6=$LIQUID_Q6_STRENGTH"
echo "gas:    m=$GAS_MASS kBT=$GAS_KBT q6=$GAS_Q6_STRENGTH"
echo "record: rho,ux,uy every $RECORD_EVERY steps; smooth=0"
echo "init: $INIT_PROFILE, muRatioSeed=$INIT_MU_RATIO"
echo "independent viscosity references: nuL=6.15880e-4 nuG=7.29393e-4"
echo "run: steps=$STEPS dt=$DT tEnd=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{printf "%.9g",n*d}')"
echo "=================================================="

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo "[0493x23f] PREFLIGHT PASS; no simulation launched"
  exit 0
fi

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"

echo
echo "[0493x23f] DONE"
echo "[0493x23f] run=$RUN_ROOT"
echo "[0493x23f] params=$PARAMS"
echo "[0493x23f] recording=$OUT/recordings"

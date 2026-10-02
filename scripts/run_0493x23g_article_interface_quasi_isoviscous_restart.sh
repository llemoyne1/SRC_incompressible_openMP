#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 0493x23g-r — RESTART L/G INTERFACE-CENTERED QUASI-ISOVISCOUS COUETTE
#
# Geometry:
#   y=0          : solid wall, ux=-Uw
#   0<y<hL      : projected liquid (Q6-g-f)
#   y=hL        : single planar liquid/gas interface
#   hL<y<Ly     : compressible SRC gas
#   y=Ly        : solid wall, ux=+Uw
#   x            : periodic
#
# Purpose:
#   Qualify the LIQUID/GAS tangential interaction locally at a single planar
#   interface, while minimizing dependence on remote wall slip and on an
#   uncertain large viscosity contrast.
#
#   The microscopic point is the low-ell article transport-map case L036_G08_A120:
#     h=1/256, gamma=8, alphaSRC=120 deg,
#     dt=0.0031735664074561293, kBT=0.125, m=1 on BOTH sides.
#
#   The closures remain physically different:
#     liquid : SRC + particle/field Q6-g-f closure
#     gas    : compressible SRC gas, q6Strength=0
#
#   Independent article TG references (6 seeds, both PASS/QUALIFIED):
#     nu_L(Q6-g-f) = 7.18535122550e-4
#     nu_G(SRC)    = 6.774787066662e-4
#   With equal nominal densities, mu_G/mu_L = nu_G/nu_L ~= 0.942861.
#   Thus the expected interfacial slope jump is only about 6%, rather than the
#   O(8x) contrast of x23f.  The viscosity ratio is used only as a local
#   constitutive reference and for the optional spin-up profile.
#
#   Default 128x128, L=0.5x0.5 -> 64h liquid + 64h gas.  The liquid thickness
#   exceeds 2*Rc (Rc/h ~= 25.3), so x12a is not globally triggered by a thin
#   liquid layer.  Equal m and kBT also make the single wall-VP parameter set
#   consistent with BOTH physical walls.
#
#   Keep the production surface-tension setting sigma=2560.  The interface is
#   planar, so capillarity is not used as an acceptance observable here, but the
#   production liquid/gas chain (x10/x12/x14 + capillary closure) is retained.
#
#   Recording includes rho1/rho2 and y1/y2 so the later analysis can locate the
#   interface from composition and fit one-sided velocity gradients as a
#   function of distance from alpha~0.5, instead of inferring the interface law
#   from remote no-slip conditions.
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

CASE_LABEL="${CASE_LABEL:-0493x23g_article_interface_quasi_isoviscous_L036_G08_A120}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="wall"

# -----------------------------------------------------------------------------
# Geometry chosen to preserve h=1/256 while reducing cost.
# -----------------------------------------------------------------------------
Lx="${Lx:-0.5}"
Ly="${Ly:-0.5}"  
NX="${NX:-128}"
NY="${NY:-128}"
LIQUID_CELLS="${LIQUID_CELLS:-64}"

GAMMA="${GAMMA:-8}"
DT="${DT:-0.0031735664074561293}"
STEPS="${STEPS:-}"
SEED="${SEED:-593172}"

# Restart controls.  By default continue the qualified 0->8000 run to global
# step 40000.  RESTART_STATE may point to any compatible x23g dump.
SOURCE_RUN_ROOT="${SOURCE_RUN_ROOT:-runs/0493x23g_interface_quasi_isoviscous_128x128_cold_Uw0.04_seed593172}"
RESTART_STATE="${RESTART_STATE:-}"
RESTART_FROM_STEP="${RESTART_FROM_STEP:-}"
TARGET_GLOBAL_STEP="${TARGET_GLOBAL_STEP:-20000}"


WALL_SPEED_MAG="${WALL_SPEED_MAG:-0.04}"
WALL_UX_BOTTOM="$(awk -v u="$WALL_SPEED_MAG" 'BEGIN{printf "%.17g",-u}')"
WALL_UX_TOP="$(awk -v u="$WALL_SPEED_MAG" 'BEGIN{printf "%.17g",u}')"

LIQUID_TYPE="${LIQUID_TYPE:-1}"
GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_KBT="${LIQUID_KBT:-0.0125}"
GAS_KBT="${GAS_KBT:-0.0125}"

# x6g reads params.kBT; keep it aligned with the gas target as in x14/x23.
KBT="${KBT:-$GAS_KBT}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$GAS_KBT}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931954923}"
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

# Keep the production capillary interface active, as in the qualified x23g run.
SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2560.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"
PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"

# Article low-ell transport references.  They are documentary/analysis values;
# they do not alter the solver.  Because mL=mG and the initial occupancies are
# equal, the nominal dynamic-viscosity ratio equals nuG/nuL.
ARTICLE_NU_L="${ARTICLE_NU_L:-0.00071853512255}"
ARTICLE_NU_G="${ARTICLE_NU_G:-0.0006774787066662}"
ARTICLE_NU_L_STD="${ARTICLE_NU_L_STD:-0.00007148437368744265}"
ARTICLE_NU_G_STD="${ARTICLE_NU_G_STD:-0.0000665780874244649}"
ARTICLE_TRANSPORT_CASE="L036_G08_A120"

# Initial mean profile: expected two-layer Couette using the central article
# viscosity ratio only to reduce spin-up.  It is NOT an acceptance assumption.
INIT_PROFILE="${INIT_PROFILE:-theory}"
INIT_MU_RATIO="${INIT_MU_RATIO:-$(awk -v ng="$ARTICLE_NU_G" -v nl="$ARTICLE_NU_L" 'BEGIN{printf "%.17g",ng/nl}')}"

# -----------------------------------------------------------------------------
# Output / diagnostics.
# -----------------------------------------------------------------------------
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-500}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
# LIVE_VIS_CONTROL_FILE is set after RUN_ROOT so this benchmark never shares
# the repository-global livevis_control.kv with another run.
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

# Interface-centered metrology: native solver grid, conservative composition
# fields plus velocity every 20 steps, no spatial smoothing.
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,rho1,rho2,y1,y2,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-20}"
RECORD_FORMAT="${RECORD_FORMAT:-f32}"
RECORD_STRIDE="${RECORD_STRIDE:-1}"
RECORD_SESSION_PREFIX="${RECORD_SESSION_PREFIX:-0493x23g_interface}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_TAU="${FILTER_TAU:-0}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-20}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
LIVE_VIS_CONTROL_EVERY="${LIVE_VIS_CONTROL_EVERY:-1}"
LIVE_VIS_CONTROL_LOG="${LIVE_VIS_CONTROL_LOG:-1}"

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"

x23g_abs_path() {
  python3 - "$ROOT" "$1" <<'PYABS'
from pathlib import Path
import sys
root=Path(sys.argv[1]).resolve()
p=Path(sys.argv[2])
print((p if p.is_absolute() else root/p).resolve())
PYABS
}

# Resolve the checkpoint BEFORE creating/cleaning the continuation root.
if [[ -z "$RESTART_STATE" ]]; then
  SOURCE_RUN_ROOT_ABS="$(x23g_abs_path "$SOURCE_RUN_ROOT")"
  [[ -d "$SOURCE_RUN_ROOT_ABS/output" ]] || {
    echo "[0493x23g-r] ERROR source output missing: $SOURCE_RUN_ROOT_ABS/output" >&2
    exit 2
  }
  RESTART_STATE="$(find "$SOURCE_RUN_ROOT_ABS/output" -maxdepth 1 -type f -name 'state_step_*.smpcd' -print | sort -V | tail -n 1)"
else
  RESTART_STATE="$(x23g_abs_path "$RESTART_STATE")"
fi
[[ -n "$RESTART_STATE" && -f "$RESTART_STATE" ]] || {
  echo "[0493x23g-r] ERROR no restart state found. Set RESTART_STATE explicitly." >&2
  exit 2
}

SOURCE_RUN_ROOT_RESOLVED="$(cd "$(dirname "$RESTART_STATE")/.." && pwd)"
SOURCE_PARAMS="${SOURCE_PARAMS:-$(dirname "$RESTART_STATE")/params_used.kv}"

if [[ -z "$RESTART_FROM_STEP" ]]; then
  bn="$(basename "$RESTART_STATE")"
  if [[ "$bn" =~ ^state_step_([0-9]+)\.smpcd$ ]]; then
    RESTART_FROM_STEP="$((10#${BASH_REMATCH[1]}))"
  else
    echo "[0493x23g-r] ERROR cannot infer restart step from $bn; set RESTART_FROM_STEP." >&2
    exit 2
  fi
fi

if [[ -z "$STEPS" ]]; then
  STEPS="$((TARGET_GLOBAL_STEP - RESTART_FROM_STEP))"
fi
if (( STEPS <= 0 )); then
  echo "[0493x23g-r] ERROR STEPS must be > 0 (from=$RESTART_FROM_STEP target=$TARGET_GLOBAL_STEP)." >&2
  exit 2
fi
TARGET_GLOBAL_STEP_EFFECTIVE="$((RESTART_FROM_STEP + STEPS))"

RUN_ROOT="${RUN_ROOT:-runs/0493x23g_interface_quasi_isoviscous_restart_${RESTART_FROM_STEP}_to_${TARGET_GLOBAL_STEP_EFFECTIVE}_seed${SEED}}"
if [[ "$RUN_ROOT" = /* ]]; then
  RUN_ROOT_ABS="$RUN_ROOT"
else
  RUN_ROOT_ABS="$ROOT/$RUN_ROOT"
fi
RUN_ROOT_ABS="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$RUN_ROOT_ABS")"
if [[ "$RUN_ROOT_ABS" == "$SOURCE_RUN_ROOT_RESOLVED" ]]; then
  echo "[0493x23g-r] ERROR RUN_ROOT must differ from source run root (CLEAN_RUN_ROOT would destroy the checkpoint)." >&2
  exit 2
fi

# Strict compatibility check against the source run parameters when available.
if [[ -f "$SOURCE_PARAMS" ]]; then
  python3 - "$SOURCE_PARAMS" "$RESTART_STATE" "$Lx" "$Ly" "$NX" "$NY" "$DT" \
    "$WALL_UX_BOTTOM" "$WALL_UX_TOP" "$SURFACE_TENSION_SIGMA" "$GAMMA" <<'PYCHK'
from pathlib import Path
import math, re, struct, sys
params,state=sys.argv[1],sys.argv[2]
Lx,Ly=float(sys.argv[3]),float(sys.argv[4])
Nx,Ny=int(sys.argv[5]),int(sys.argv[6])
dt=float(sys.argv[7]); ub=float(sys.argv[8]); ut=float(sys.argv[9]); sigma=float(sys.argv[10]); gamma=int(sys.argv[11])
kv={}
for raw in Path(params).read_text(errors='replace').splitlines():
    line=raw.split('#',1)[0].strip()
    if '=' not in line: continue
    k,v=line.split('=',1); kv[k.strip()]=v.strip()
def num(key):
    return float(kv[key]) if key in kv else None
def chk(key, want, atol=1e-12):
    got=num(key)
    if got is not None and not math.isclose(got,want,rel_tol=1e-12,abs_tol=atol):
        raise SystemExit(f'[0493x23g-r] incompatible source params: {key}={got:.17g}, expected {want:.17g}')
for k,w in [('Lx',Lx),('Ly',Ly),('Nx',Nx),('Ny',Ny),('dt',dt),('wallUxBottom',ub),('wallUxTop',ut),('surfaceTensionSigma',sigma)]:
    chk(k,w)
with open(state,'rb') as f:
    magic=f.read(16)
    if not magic.startswith(b'SRCMPCD_STATE'):
        raise SystemExit('[0493x23g-r] restart file is not an SRCMPCD_STATE')
    hdr=f.read(struct.calcsize('<IIIIQIIII'))
    if len(hdr) != struct.calcsize('<IIIIQIIII'):
        raise SystemExit('[0493x23g-r] truncated restart header')
    version,endian,dim,scalar,npart,*rest=struct.unpack('<IIIIQIIII',hdr)
expected=Nx*Ny*gamma
if npart != expected:
    raise SystemExit(f'[0493x23g-r] restart particle count {npart} != expected {expected}')
print(f'[0493x23g-r] source compatibility PASS: {params}')
PYCHK
else
  echo "[0493x23g-r] WARNING source params_used.kv not found: $SOURCE_PARAMS" >&2
fi

# Restart does not regenerate the initial condition.
INIT_PROFILE="restart"

# Use an ABSOLUTE, run-local control path.  The repository-root control file is never used.
LIVE_VIS_CONTROL_FILE="$RUN_ROOT_ABS/livevis_control_0493x23g.kv"
LIVE_VIS_CONTROL_FILE_EFFECTIVE="$LIVE_VIS_CONTROL_FILE"
OVERWRITE_LIVEVIS_CONTROL=1
export LIVE_VIS_CONTROL_FILE LIVE_VIS_CONTROL_FILE_EFFECTIVE

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
  "$DT" "$ROTATION_ANGLE" "$X12A_LOCAL_THERMAL_RADIUS_CELLS" \
  "$LIQUID_MASS" "$GAS_MASS" "$LIQUID_KBT" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2])
nx,ny=int(sys.argv[3]),int(sys.argv[4])
nl=int(sys.argv[5]); gamma=int(sys.argv[6]); tg=float(sys.argv[7])
dt=float(sys.argv[8]); ang=float(sys.argv[9]); rc=float(sys.argv[10])
mL=float(sys.argv[11]); mG=float(sys.argv[12]); tL=float(sys.argv[13])
hx=lx/nx; hy=ly/ny
if nx <= 0 or ny <= 0 or not (0 < nl < ny):
    raise SystemExit('[0493x23g] invalid grid or LIQUID_CELLS')
if abs(hx-hy) > 1e-13:
    raise SystemExit(f'[0493x23g] square cells required: hx={hx:.17g} hy={hy:.17g}')
if abs(hx-1/256) > 1e-13:
    raise SystemExit(f'[0493x23g] must preserve characterized h=1/256; got {hx:.17g}')
if abs(dt-0.0031735664074561293) > 1e-14:
    raise SystemExit(f'[0493x23g] must preserve article low-ell dt; got {dt:.17g}')
if abs(ang-2.0*math.pi/3.0) > 1e-13:
    raise SystemExit(f'[0493x23g] must preserve alphaSRC=120deg; got {ang:.17g}')
if gamma != 8:
    raise SystemExit(f'[0493x23g] must preserve article low-ell gamma=8; got {gamma}')
if abs(mL-1.0)>1e-14 or abs(mG-1.0)>1e-14:
    raise SystemExit(f'[0493x23g] quasi-isoviscous control requires mL=mG=1; got {mL}, {mG}')
if abs(tL-0.125)>1e-14 or abs(tg-0.125)>1e-14:
    raise SystemExit(f'[0493x23g] quasi-isoviscous control requires kBTL=kBTG=0.125; got {tL}, {tg}')
if nl <= 2.0*rc:
    raise SystemExit(f'[0493x23g] liquid thickness must exceed 2*Rc: cells={nl}, 2Rc={2*rc:.6g}')
hl=nl*hy; hg=ly-hl
area=hx*hy
pref=gamma*tg/area
npart=nx*ny*gamma
print(f'{hx:.17g} {hl:.17g} {hg:.17g} {pref:.17g} {npart}')
PY
)"

if [[ "$LIQUID_CELLS" -ne $((NY/2)) ]]; then
  echo "[0493x23g] WARNING default interface benchmark expects equal liquid/gas thicknesses." >&2
fi

# -----------------------------------------------------------------------------
# Run layout.
# -----------------------------------------------------------------------------
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then
  rm -rf "$RUN_ROOT"
fi
suite_prepare_dirs_0434 "$RUN_ROOT"
mkdir -p "$RUN_ROOT/analysis"

STATE="$RESTART_STATE"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TF="$RUN_ROOT/logs/${CASE_LABEL}.time"

# -----------------------------------------------------------------------------
# Restart state: use the existing particle dump directly.  The executable
# restarts its local step counter and RNG stream at zero; global step metadata
# below preserves the physical continuation origin for post-processing.
# -----------------------------------------------------------------------------
echo "[0493x23g-r] restart state = $STATE"
echo "[0493x23g-r] global step   = $RESTART_FROM_STEP -> $TARGET_GLOBAL_STEP_EFFECTIVE ($STEPS additional)"
echo "[0493x23g-r] source root   = $SOURCE_RUN_ROOT_RESOLVED"


LREF="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GREF="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

# -----------------------------------------------------------------------------
# Parameters: article low-ell quasi-isoviscous liquid/gas point, periodic-x /
# wall-y, one L/G interface.  Symmetric walls suppress common-mode translation.
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
wallUxBottom = $WALL_UX_BOTTOM
wallUyBottom = 0.0
wallUxTop = $WALL_UX_TOP
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
speciesDiagnosticsFilename = species_runtime_0493x23g.csv
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

# -----------------------------------------------------------------------------
# Strict run-local LiveVis/recorder control.
#
# Do NOT call suite_prepare_livevis_control_0434 here: this benchmark writes the
# complete control file itself, after CLEAN_RUN_ROOT, and exports BOTH SRC_* and
# MPCD_* control-path aliases.  The repository-root livevis_control.kv is never
# consulted by this runner.
# -----------------------------------------------------------------------------
mkdir -p "$(dirname "$LIVE_VIS_CONTROL_FILE")"
cat > "$LIVE_VIS_CONTROL_FILE" <<CONTROL
# 0493x23g interface-centered LiveVis/filtered-recorder control.
# Generated by the runner; edits affect this run only.
field = ${LIVE_VIS_FIELD}
colormap = ${LIVE_VIS_COLORMAP}
clip = ${LIVE_VIS_CLIP}
gain = ${LIVE_VIS_GAIN}
smoothPasses = ${LIVE_VIS_SMOOTH_PASSES}
liveGridNx = ${LIVE_VIS_NX}
liveGridNy = ${LIVE_VIS_NY}
liveEvery = ${LIVE_VIS_EVERY}
particleTypeFilter = ${PARTICLE_TYPE_FILTER}
filterMode = ${FILTER_MODE}
filterTau = ${FILTER_TAU}
filterSampleEvery = ${FILTER_SAMPLE_EVERY}
recordEnable = ${RECORD_ENABLE}
recordSession = ${RECORD_SESSION_PREFIX}_${RUN_MODE}
recordFields = ${RECORD_FIELDS}
recordFormat = ${RECORD_FORMAT}
recordStride = ${RECORD_STRIDE}
recordEvery = ${RECORD_EVERY}
CONTROL

# Export normal LiveVis variables, then force both recognized control-file aliases
# to the absolute run-local path.
suite_export_livevis_0434
export SRC_LIVE_VIS_CONTROL_FILE="$LIVE_VIS_CONTROL_FILE"
export MPCD_LIVE_VIS_CONTROL_FILE="$LIVE_VIS_CONTROL_FILE"
export LIVE_VIS_CONTROL_FILE_EFFECTIVE="$LIVE_VIS_CONTROL_FILE"
export SRC_LIVE_VIS_CONTROL_EVERY="$LIVE_VIS_CONTROL_EVERY"
export MPCD_LIVE_VIS_CONTROL_EVERY="$LIVE_VIS_CONTROL_EVERY"
export SRC_LIVE_VIS_CONTROL_LOG="$LIVE_VIS_CONTROL_LOG"
export MPCD_LIVE_VIS_CONTROL_LOG="$LIVE_VIS_CONTROL_LOG"

# Recorder startup fallbacks mirror the control file.  Runtime control remains
# authoritative, but even before its first reload the requested composition
# fields/cadence are explicit.
export SRC_FILTERED_FIELD_RECORD_FIELDS="$RECORD_FIELDS"
export MPCD_FILTERED_FIELD_RECORD_FIELDS="$RECORD_FIELDS"
export SRC_FILTERED_FIELD_RECORD_EVERY="$RECORD_EVERY"
export MPCD_FILTERED_FIELD_RECORD_EVERY="$RECORD_EVERY"

echo "[0493x23g-livevis] control=$LIVE_VIS_CONTROL_FILE"
echo "[0493x23g-livevis] grid=${LIVE_VIS_NX}x${LIVE_VIS_NY} every=$LIVE_VIS_EVERY"
echo "[0493x23g-livevis] recordFields=$RECORD_FIELDS recordEvery=$RECORD_EVERY"

suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x23g.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_0493x23g.env" <<META
BENCHMARK=0493x23g_article_interface_quasi_isoviscous_L036_G08_A120
GEOMETRY=S|L|G|S
LIVE_VIS_CONTROL_FILE=$LIVE_VIS_CONTROL_FILE
LIVE_VIS_NX=$LIVE_VIS_NX
LIVE_VIS_NY=$LIVE_VIS_NY
RECORD_FIELDS=$RECORD_FIELDS
RECORD_EVERY=$RECORD_EVERY
H=$H
LIQUID_CELLS=$LIQUID_CELLS
LIQUID_THICKNESS=$HL
GAS_THICKNESS=$HG
WALL_UX_BOTTOM=$WALL_UX_BOTTOM
WALL_UX_TOP=$WALL_UX_TOP
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
ARTICLE_TRANSPORT_CASE=$ARTICLE_TRANSPORT_CASE
ARTICLE_NU_L=$ARTICLE_NU_L
ARTICLE_NU_G=$ARTICLE_NU_G
ARTICLE_NU_L_STD=$ARTICLE_NU_L_STD
ARTICLE_NU_G_STD=$ARTICLE_NU_G_STD
ARTICLE_MU_G_OVER_MU_L_NOMINAL=$INIT_MU_RATIO
RESTART=1
RESTART_STATE=$RESTART_STATE
RESTART_SOURCE_ROOT=$SOURCE_RUN_ROOT_RESOLVED
RESTART_FROM_GLOBAL_STEP=$RESTART_FROM_STEP
RESTART_LOCAL_STEPS=$STEPS
RESTART_TARGET_GLOBAL_STEP=$TARGET_GLOBAL_STEP_EFFECTIVE
RESTART_SEMANTICS=hydrodynamic_not_bitwise_rng_continuous
META

# Preflight with exact generated params and active routing.
suite_preflight_run_ok_0492 "$PARAMS"

echo
echo "===== 0493x23g-r RESTART L/G INTERFACE QUASI-ISOVISCOUS COUETTE ====="
echo "runRoot=$RUN_ROOT"
echo "grid=${NX}x${NY} L=${Lx}x${Ly} h=$H particles=$NPART"
echo "layout: wall ux=$WALL_UX_BOTTOM | liquid ${LIQUID_CELLS}h | gas $((NY-LIQUID_CELLS))h | wall ux=$WALL_UX_TOP"
echo "fluid point: gamma=$GAMMA dt=$DT alpha=$ROTATION_ANGLE"
echo "liquid: m=$LIQUID_MASS kBT=$LIQUID_KBT q6=$LIQUID_Q6_STRENGTH"
echo "gas:    m=$GAS_MASS kBT=$GAS_KBT q6=$GAS_Q6_STRENGTH"
echo "record: $RECORD_FIELDS every $RECORD_EVERY steps; smooth=0"
echo "livevis control (run-local only): $LIVE_VIS_CONTROL_FILE"
echo "restart: global $RESTART_FROM_STEP -> $TARGET_GLOBAL_STEP_EFFECTIVE ; state=$RESTART_STATE"
echo "article transport case: $ARTICLE_TRANSPORT_CASE"
echo "independent viscosity references: nuL=$ARTICLE_NU_L (PASS) nuG=$ARTICLE_NU_G (PASS) muG/muL~$INIT_MU_RATIO"
echo "run: localSteps=$STEPS dt=$DT localDuration=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{printf "%.9g",n*d}')"
echo "restart semantics: hydrodynamic continuation; local step/RNG counter restarts at 0"
echo "=================================================="

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo "[0493x23g-r] PREFLIGHT PASS; no simulation launched"
  exit 0
fi

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"

echo
echo "[0493x23g-r] DONE"
echo "[0493x23g-r] run=$RUN_ROOT"
echo "[0493x23g-r] params=$PARAMS"
echo "[0493x23g-r] recording=$OUT/recordings"

echo "[0493x23g-r] global end step=$TARGET_GLOBAL_STEP_EFFECTIVE (local end step=$STEPS)"

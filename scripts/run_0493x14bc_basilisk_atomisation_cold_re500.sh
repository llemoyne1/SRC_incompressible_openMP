#!/usr/bin/env bash
# Deliberately no `set -euo pipefail`: key dependent operations are guarded explicitly.

# 0493x14bc — cold-liquid Re500 Basilisk atomisation benchmark.
#
# Final Stage-A fluid selected after the interface-roughness study:
#   gamma=8, alpha=90 deg, h=1/256, dt=0.00635
#   liquid: m=1, kBT=0.0078125, nu=2.122268985e-4 (TG128, 8 seeds, PASS, CV=2.2%)
#   gas:    m=0.03591954022988506, kBT=0.00575, nu=3.536191886e-4 (TG64, REVIEW)
#
# Similarity target: Re_L=500, We_G=200, rho_L/rho_G=27.84, D/h=96,
# 18D x 18D domain.  With the calibrated cold liquid this gives
# U=0.282969198 and sigma=2.827354642 (computed from the references below).
#
# 0493x14ba global inlet oscillation is supported and ON by default here:
#   U(t)=Umean*[1+0.05*sin(2*pi*(t+offset-t0)/T + phase)]
# with St=5/3.  Set BASILISK_PULSE_RUNTIME_ENABLE=0 for the steady control.
#
# The x14 liquid/gas physics is unchanged: Q6-g-f liquid + x6g/x9/x10/x12
# + x14l/x14v, no resampling, no virial kick. x14ax/x14az alpha_x6c
# recording/display are supported by the canonical binary.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SEED="${SEED:-493215}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

GAMMA="${GAMMA:-8}"
if [[ "$GAMMA" != "8" ]]; then
  echo "[0493x14bc] ERROR this calibrated runner is fixed to GAMMA=8 (got $GAMMA)" >&2
  exit 2
fi
CASE_LABEL="${CASE_LABEL:-0493x14bc_basilisk2d_Re500_WeG200_D96_cold}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="segmented"
NEUMANN_PROFILE="${NEUMANN_PROFILE:-x9e}"

# -----------------------------------------------------------------------------
# Target similarity and resolved local fluid
# -----------------------------------------------------------------------------
TARGET_RE_L="${TARGET_RE_L:-500}"
TARGET_WE_G="${TARGET_WE_G:-200}"
TARGET_DENSITY_RATIO="${TARGET_DENSITY_RATIO:-27.84}"
TARGET_ST="${TARGET_ST:-1.6666666666666667}"
BASILISK_PULSE_REL_AMPLITUDE="${BASILISK_PULSE_REL_AMPLITUDE:-0.05}"
BASILISK_PULSE_RUNTIME_ENABLE="${BASILISK_PULSE_RUNTIME_ENABLE:-1}"
INLET_OSCILLATION_PHASE="${INLET_OSCILLATION_PHASE:-0.0}"
INLET_OSCILLATION_START_TIME="${INLET_OSCILLATION_START_TIME:-0.0}"
# Empty means auto: zero for a fresh run, or step*dt when a direct state_step_N
# restart is used.  Set explicitly for chained restart segments.
INLET_OSCILLATION_TIME_OFFSET="${INLET_OSCILLATION_TIME_OFFSET:-}"

# Fixed calibrated cold liquid and retained gas reference.
H_TARGET="${H_TARGET:-0.00390625}"              # 1/256
DT="${DT:-0.00635}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"
GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
LIQUID_KBT="${LIQUID_KBT:-0.0078125}"
GAS_MASS="${GAS_MASS:-0.03591954022988506}"
GAS_KBT="${GAS_KBT:-0.00575}"
KBT="$GAS_KBT"
PARTICLE_MASS="$GAS_MASS"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"

# Measured transport coefficients.
LIQUID_NU_REFERENCE="${LIQUID_NU_REFERENCE:-0.0002122268985}"
GAS_NU_REFERENCE="${GAS_NU_REFERENCE:-0.0003536191886}"
LIQUID_NU_REFERENCE_STATUS="TG128_PASS_8seeds_CV2.2"
GAS_NU_REFERENCE_STATUS="TG64_REVIEW_CV13.22"

# -----------------------------------------------------------------------------
# Geometry: 2-D slit analogue of the cylindrical Basilisk jet
# D/h=96 and 18D x 18D => 1728^2 cells, close to the current 2400x1200 cost.
# No solid nozzle body: the liquid is injected directly through a centered
# segment of the left boundary, as in Basilisk's f0 inlet mask.
# -----------------------------------------------------------------------------
JET_DIAMETER_CELLS="${JET_DIAMETER_CELLS:-96}"
DOMAIN_DIAMETERS_X="${DOMAIN_DIAMETERS_X:-18}"
DOMAIN_DIAMETERS_Y="${DOMAIN_DIAMETERS_Y:-18}"
INITIAL_JET_LENGTH_OVER_D="${INITIAL_JET_LENGTH_OVER_D:-0.15}"

read -r NX NY Lx Ly JET_D JET_CENTER_Y LIQUID_SPEED SURFACE_TENSION_SIGMA \
  LIQ_SMIN LIQ_SMAX GAS_RHO LIQUID_RHO RE_L_DESIGN WE_G_DESIGN WE_L_DESIGN \
  PULSE_PERIOD PULSE_PERIOD_STEPS CTH_G CTH_L ADV_L FLIGHT_L LAMBDA_G_OVER_H LAMBDA_L_OVER_H \
  U_OVER_GAS_THERMAL BASILISK_T_EQ_END NOMINAL_PARTICLES <<<"$(python3 - \
  "$H_TARGET" "$JET_DIAMETER_CELLS" "$DOMAIN_DIAMETERS_X" "$DOMAIN_DIAMETERS_Y" \
  "$TARGET_RE_L" "$TARGET_WE_G" "$TARGET_DENSITY_RATIO" "$TARGET_ST" \
  "$GAMMA" "$LIQUID_MASS" "$GAS_MASS" "$LIQUID_KBT" "$GAS_KBT" "$DT" \
  "$LIQUID_NU_REFERENCE" "${STEPS:-4758}" <<'PY'
import math,sys
(h,dc,ndx,ndy,re,wegr,rr,st,gam,ml,mg,kl,kg,dt,nul,steps)=map(float,sys.argv[1:])
dc=int(round(dc)); ndx=int(round(ndx)); ndy=int(round(ndy)); steps=int(round(steps))
nx=dc*ndx; ny=dc*ndy
D=dc*h; Lx=nx*h; Ly=ny*h; cy=.5*Ly
U=re*nul/D
rhoL=gam*ml/(h*h); rhoG=gam*mg/(h*h)
sigma=rhoG*U*U*D/wegr
recheck=U*D/nul; weg=rhoG*U*U*D/sigma; wel=rhoL*U*U*D/sigma
s0=(cy-.5*D)/Ly; s1=(cy+.5*D)/Ly
T=D/(st*U)
cthg=math.sqrt(kg/mg)*dt/h; cthl=math.sqrt(kl/ml)*dt/h
adv=abs(U)*dt/h
flight=cthl+adv
lamg=math.sqrt(math.pi*kg/(2*mg))*dt/h
laml=math.sqrt(math.pi*kl/(2*ml))*dt/h
thermal_ratio=U/math.sqrt(kg/mg)
# Basilisk dimensionless time t_B uses U_B=1,D_B=1/6; t* = 6 t_B.
tsrc=steps*dt; tstar=tsrc*U/D; tb=tstar/6.0
np=nx*ny*int(round(gam))
print(nx,ny,Lx,Ly,D,cy,U,sigma,s0,s1,rhoG,rhoL,recheck,weg,wel,T,T/dt,cthg,cthl,adv,flight,lamg,laml,thermal_ratio,tb,np)
PY
)"

# 4758 steps gives Basilisk-equivalent t ~= 3.80 with the calibrated cold liquid.
STEPS="${STEPS:-4758}"
GRAVITY_Y="${GRAVITY_Y:-0.0}"
RE_G_DESIGN="$(awk -v U="$LIQUID_SPEED" -v D="$JET_D" -v nu="$GAS_NU_REFERENCE" 'BEGIN{printf "%.9g",U*D/nu}')"
NU_G_OVER_NU_L="$(awk -v ng="$GAS_NU_REFERENCE" -v nl="$LIQUID_NU_REFERENCE" 'BEGIN{printf "%.9g",ng/nl}')"
MU_L_OVER_MU_G="$(awk -v rr="$TARGET_DENSITY_RATIO" -v nl="$LIQUID_NU_REFERENCE" -v ng="$GAS_NU_REFERENCE" 'BEGIN{printf "%.9g",rr*nl/ng}')"

THERMOSTAT_ENABLE=true
THERMOSTAT_MODE="cell_relative_rescale"
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$GAS_KBT"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"
PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"

# No startup ramp; optional x14ba sine starts at the mean value for phase=0.
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-2}"
INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-0.0}"
INLET_HARD_CELL_THERMAL_RESCALE="${INLET_HARD_CELL_THERMAL_RESCALE:-false}"
OUTLET_MODE="${OUTLET_MODE:-neumann}"
OUTLET_FEEDBACK_GAIN="${OUTLET_FEEDBACK_GAIN:-0.0}"
NEUMANN_VIRTUAL_LAYERS="${NEUMANN_VIRTUAL_LAYERS:-2}"
NEUMANN_COARSE_LAYERS="${NEUMANN_COARSE_LAYERS:-8}"
NEUMANN_TARGET_OCCUPANCY="${NEUMANN_TARGET_OCCUPANCY:-}"

# Q6-g-f production profile.
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1600}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-$(awk -v g="$GAMMA" 'BEGIN{printf "%.17g",3.0*g/8.0}')}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-$(awk -v g="$GAMMA" 'BEGIN{printf "%.17g",6.0*g/8.0}')}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-$SPECIES_Q6_MIN_FILL_FRACTION}"
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=1
SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
VIRIAL_DENSITY_KICK_ENABLE=false

SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
# Large 1728^2 states are intentional for restart/diagnostics in this benchmark.
ALLOW_LARGE_DUMPS="${ALLOW_LARGE_DUMPS:-1}"
export ALLOW_LARGE_DUMPS
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-5.0}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
DESIGN_ONLY="${DESIGN_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
THREADS="${THREADS:-8}"
ANALYZE_ENABLE="${ANALYZE_ENABLE:-1}"
RESTART="${RESTART:-0}"
RESTART_STATE="${RESTART_STATE:-}"
RESTART_TAG="${RESTART_TAG:-segment}"
FLIGHT_WARN_CELLS="${FLIGHT_WARN_CELLS:-0.80}"
STRICT_FLIGHT_GUARD="${STRICT_FLIGHT_GUARD:-0}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-alpha_x6c}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-400}"
LIVE_VIS_NY="${LIVE_VIS_NY:-400}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:-1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_EVERY="${RECORD_EVERY:-100}"
RECORD_FIELDS="${RECORD_FIELDS:-rho1,alpha_x6c,ux,uy}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"

BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x14bc_basilisk_atomisation_Re500_cold_seed${SEED}}"
if [[ "$RESTART" == "1" ]]; then
  if [[ -z "$RESTART_STATE" || ! -s "$RESTART_STATE" ]]; then
    echo "[0493x14bc] ERROR RESTART=1 requires RESTART_STATE=/path/state_step_N.smpcd" >&2
    exit 2
  fi
  RUN_ROOT="$BASE_RUN_ROOT/restart_${RESTART_TAG}"
else
  RUN_ROOT="$BASE_RUN_ROOT"
fi

case "$BASILISK_PULSE_RUNTIME_ENABLE" in
  0|1) ;;
  *) echo "[0493x14bc] ERROR BASILISK_PULSE_RUNTIME_ENABLE must be 0 or 1" >&2; exit 2 ;;
esac
if [[ -z "$INLET_OSCILLATION_TIME_OFFSET" ]]; then
  INLET_OSCILLATION_TIME_OFFSET=0.0
  if [[ "$RESTART" == "1" && "$BASILISK_PULSE_RUNTIME_ENABLE" == "1" ]]; then
    restart_base="$(basename "$RESTART_STATE")"
    if [[ "$restart_base" =~ ^state_step_0*([0-9]+)\.smpcd$ ]]; then
      restart_step="${BASH_REMATCH[1]}"
      [[ -n "$restart_step" ]] || restart_step=0
      INLET_OSCILLATION_TIME_OFFSET="$(awk -v n="$restart_step" -v dt="$DT" 'BEGIN{printf "%.17g",n*dt}')"
      echo "[0493x14bc] oscillation restart phase offset auto=$INLET_OSCILLATION_TIME_OFFSET from step=$restart_step"
    else
      echo "[0493x14bc] ERROR oscillating restart requires INLET_OSCILLATION_TIME_OFFSET" >&2
      echo "[0493x14bc]       when RESTART_STATE is not named state_step_N.smpcd" >&2
      exit 2
    fi
  fi
fi

# Common helper assumptions.
GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero
BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
export RUN_OK_REFERENCE_PARTICLE_MASS
suite_defaults_common_0434
suite_compute_derived_0434

printf '%s\n' \
  "===== 0493x14bc BASILISK ATOMISATION — COLD Re500 =====" \
  "reference=https://basilisk.fr/src/examples/atomisation.c" \
  "stage=2D cold-liquid calibrated benchmark with x14ba global inlet oscillation" \
  "domain=${Lx}x${Ly} grid=${NX}x${NY} h=${H_TARGET} = ${DOMAIN_DIAMETERS_X}D x ${DOMAIN_DIAMETERS_Y}D" \
  "jet: D/h=${JET_DIAMETER_CELLS} D=${JET_D} centerY=${JET_CENTER_Y} initialLength/D=${INITIAL_JET_LENGTH_OVER_D}" \
  "fluid: gamma=${GAMMA} alpha=90deg dt=${DT} kBT_L=${LIQUID_KBT} m_L=${LIQUID_MASS} kBT_G=${GAS_KBT} m_G=${GAS_MASS}" \
  "transport: nuL=${LIQUID_NU_REFERENCE} [${LIQUID_NU_REFERENCE_STATUS}] nuG=${GAS_NU_REFERENCE} [${GAS_NU_REFERENCE_STATUS}] muL/muG=${MU_L_OVER_MU_G}" \
  "density: rhoL=${LIQUID_RHO} rhoG=${GAS_RHO} rhoL/rhoG=${TARGET_DENSITY_RATIO}" \
  "targets: ReL=${RE_L_DESIGN} ReG=${RE_G_DESIGN} nuG/nuL=${NU_G_OVER_NU_L} WeG=${WE_G_DESIGN} WeL=${WE_L_DESIGN} U=${LIQUID_SPEED} sigma=${SURFACE_TENSION_SIGMA}" \
  "pulse: runtime=${BASILISK_PULSE_RUNTIME_ENABLE} A/U=${BASILISK_PULSE_REL_AMPLITUDE} St=${TARGET_ST} period=${PULSE_PERIOD} = ${PULSE_PERIOD_STEPS} steps phase=${INLET_OSCILLATION_PHASE} offset=${INLET_OSCILLATION_TIME_OFFSET}" \
  "resolution: lambdaL/h=${LAMBDA_L_OVER_H} lambdaG/h=${LAMBDA_G_OVER_H}; thermalFlightL=${CTH_L} thermalFlightG=${CTH_G}; advectiveFlightL=${ADV_L}; totalFlightL=${FLIGHT_L} cells/step" \
  "gas kinetic ratio: U/sqrt(kBT_G/m_G)=${U_OVER_GAS_THERMAL}" \
  "duration: steps=${STEPS} equivalent Basilisk t~${BASILISK_T_EQ_END}" \
  "nominal particles=${NOMINAL_PARTICLES} (current 2400x1200,gamma8 reference = 23040000)" \
    "======================================================"

if awk -v x="$FLIGHT_L" -v w="$FLIGHT_WARN_CELLS" 'BEGIN{exit !(x>w)}'; then
  echo "[0493x14bc] WARNING liquid thermal+advective flight=${FLIGHT_L} cells/step > ${FLIGHT_WARN_CELLS}" >&2
  if suite_truthy_0434 "$STRICT_FLIGHT_GUARD"; then
    echo '[0493x14bc] ERROR STRICT_FLIGHT_GUARD=1' >&2; exit 2
  fi
fi

if suite_truthy_0434 "$DESIGN_ONLY"; then
  echo '[0493x14bc] DESIGN_ONLY=1: no state generation and no solver launch'
  exit 0
fi

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
mkdir -p "$RUN_ROOT/analysis"
STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
OUT="$RUN_ROOT/output"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TF="$RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"

# -----------------------------------------------------------------------------
# Initial state: liquid slug x < 0.15D inside the inlet slit, stagnant gas elsewhere.
# RESTART=1 uses the supplied dump directly: no multi-GB copy and no regeneration.
# This is a hydrodynamic restart; the executable RNG stream restarts locally.
# -----------------------------------------------------------------------------
if [[ "$RESTART" == "1" ]]; then
  STATE="$RESTART_STATE"
  echo "[0493x14bc] RESTART inputState=$STATE"
else
python3 - "$STATE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_TYPE" "$GAS_TYPE" \
  "$LIQUID_MASS" "$GAS_MASS" "$LIQUID_KBT" "$GAS_KBT" "$SEED" "$JET_D" \
  "$JET_CENTER_Y" "$INITIAL_JET_LENGTH_OVER_D" "$LIQUID_SPEED" <<'PYGEN'
from __future__ import annotations
import json,math,random,struct,sys
from array import array
from pathlib import Path

(path,Lx,Ly,NX,NY,gamma,lt,gt,lm,gm,lk,gk,seed,D,cy,L0D,U)=sys.argv[1:]
path=Path(path); Lx=float(Lx); Ly=float(Ly); NX=int(NX); NY=int(NY); gamma=int(gamma)
lt=int(lt); gt=int(gt); lm=float(lm); gm=float(gm); lk=float(lk); gk=float(gk)
seed=int(seed); D=float(D); cy=float(cy); L0D=float(L0D); U=float(U)
h=Lx/NX
if abs(h-Ly/NY)>1e-12: raise SystemExit('square cells required')
y0,y1=cy-D/2,cy+D/2; L0=L0D*D
MAGIC=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE"))

def paired(rng,n,m,kbt,ux,uy):
    if n<=0: return []
    q=[]
    for _ in range(n//2):
        a,b=rng.gauss(0,1),rng.gauss(0,1); q.extend(((a,b),(-a,-b)))
    if n%2: q.append((0.,0.))
    s=sum(a*a+b*b for a,b in q)
    c=math.sqrt(2*n*kbt/(m*s)) if s else 0.
    return [(ux+c*a,uy+c*b) for a,b in q]

def positions(i,j,n):
    # deterministic coprime lattice inside each cell
    ax,ay=3,7
    while math.gcd(ax,n)!=1: ax+=2
    while math.gcd(ay,n)!=1 or ay==ax: ay+=2
    return [((i+(((ax*k)%n)+.5)/n)*h,(j+(((ay*k)%n)+.5)/n)*h) for k in range(n)]

rl=random.Random(seed^0x14A901); rg=random.Random(seed^0x14A902)
X=array('d');Y=array('d');VX=array('d');VY=array('d');T=array('I');M=array('d');R=bytearray()
nl=ng=0
for j in range(NY):
    yc=(j+.5)*h
    for i in range(NX):
        xc=(i+.5)*h
        liquid=(xc<L0 and y0<=yc<y1)
        if liquid:
            typ,m,kbt,ux,rng=lt,lm,lk,U,rl; nl+=gamma
        else:
            typ,m,kbt,ux,rng=gt,gm,gk,0.,rg; ng+=gamma
        vel=paired(rng,gamma,m,kbt,ux,0.)
        for (px,py),(vx,vy) in zip(positions(i,j,gamma),vel):
            X.append(px);Y.append(py);VX.append(vx);VY.append(vy);T.append(typ);M.append(m);R.append(1)
path.parent.mkdir(parents=True,exist_ok=True)
reserved=[0]*8; reserved[0]=1; reserved[1]=1
with path.open('wb') as f:
    f.write(MAGIC); f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,len(X),1,1,8,4)); f.write(struct.pack('<8Q',*reserved))
    for a in (X,Y,VX,VY,T,M): a.tofile(f)
    f.write(R)
meta={
 'profile':'0493x14bc_basilisk_atomisation_cold_re500_2d',
 'grid':{'Lx':Lx,'Ly':Ly,'Nx':NX,'Ny':NY,'h':h},
 'jet':{'diameter':D,'diameterCells':D/h,'centerY':cy,'initialLengthOverD':L0D,'initialLength':L0,'meanSpeed':U},
 'initialState':{'particles':len(X),'liquidParticles':nl,'gasParticles':ng},
 'note':'Cold-liquid Re500 benchmark; inlet sinusoid is controlled at runtime by x14ba parameters.'}
path.with_suffix(path.suffix+'.json').write_text(json.dumps(meta,indent=2)+'\n')
print(f'[0493x14bc-generate] grid={NX}x{NY} h={h:.9g} N={len(X)} liquid={nl} gas={ng}')
print(f'[0493x14bc-generate] D={D:.9g} L0={L0:.9g} U={U:.9g}')
PYGEN
rc=$?
if [[ $rc -ne 0 ]]; then echo "[0493x14bc] ERROR initial-state generation failed rc=$rc" >&2; exit $rc; fi
fi

LREF="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GREF="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"
GAS_P_REF="$(awk -v g="$GAMMA" -v k="$GAS_KBT" -v h="$H_TARGET" 'BEGIN{printf "%.17g",g*k/(h*h)}')"
SEG0="left inlet $LIQ_SMIN $LIQ_SMAX $LIQUID_SPEED 0.0 $LIQUID_TYPE $LIQUID_MASS"
SEG1="right outlet 0.0 1.0 0.0 0.0 0 $GAS_MASS"

cat > "$PARAMS" <<PARAMS
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

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = $SEG0
openBoundarySegment1 = $SEG1

# Startup ramp and periodic oscillation are independent and multiplicative.
inletVelocityRampEnable = false
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.0
inletVelocityRampInitialFactor = 1.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocityOscillationEnable = $BASILISK_PULSE_RUNTIME_ENABLE
inletVelocityOscillationAmplitude = $BASILISK_PULSE_REL_AMPLITUDE
inletVelocityOscillationPeriod = $PULSE_PERIOD
inletVelocityOscillationPhase = $INLET_OSCILLATION_PHASE
inletVelocityOscillationStartTime = $INLET_OSCILLATION_START_TIME
inletVelocityOscillationTimeOffset = $INLET_OSCILLATION_TIME_OFFSET
inletVelocitySpatialProfile = uniform
inletKBT = $GAS_KBT
inletThermalNoise = $INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $INLET_RESERVOIR_CELLS
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = $INLET_HARD_CELL_THERMAL_RESCALE
inletRandomizeTangential = false
inletReinjectBackflow = true

openBoundaryOutletMode = $OUTLET_MODE
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = $OUTLET_FEEDBACK_GAIN

bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
taylorGreenForcingEnable = false
wallVpEnable = false
wallAccommodation = 0.0
wallVpGamma = $GAMMA
wallVpMass = $LIQUID_MASS
wallKBT = -1.0
wallThermalNoise = 0.0

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
speciesDiagnosticsFilename = species_runtime_0493x14bc.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
PARAMS

suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"
run_ok_surface_append_params_0493x13zi "$PARAMS" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
cat >> "$PARAMS" <<'PARAMS'
phaseInterfaceKineticBilateralRelocation = true
PARAMS

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
run_ok_surface_export_off_flags_0493x13zi
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$GAS_P_REF"
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1

export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS="$X10O_THERMAL_SIGMAS"
export MPCD_X10O_THERMAL_MAX_CELLS="$X10O_THERMAL_MAX_CELLS"
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="$X12A_LOCAL_THERMAL_RADIUS_CELLS"

export MPCD_X14L_GAS_SPECULAR_REFLECTION=1
export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1
export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0
export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0
export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0
export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=0
export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1

# Qualified multiphase Neumann outlet, same x9c physics as the atomizer runner.
unset MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_KINETIC_0493X8Q_DISABLE || true
unset MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_REPLICA_0493X8V || true
unset MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_CELLS_0493X8W || true
unset MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_RESERVOIR_0493X8X || true
unset MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RESIDENT_OPT_0493X9D || true
unset MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RESIDENT_OPT_0493X9D_FIX1 || true
unset MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_POOL_0493X9E || true
unset MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_PRESSURE_RESERVOIR_0493X8Y_TARGET_OCCUPANCY || true
export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_PRESSURE_RESERVOIR_0493X8Y=1
export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_NO_BACKFLOW_0493X8Z=1
export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_ZERO_DRIFT_ON_BACKFLOW_0493X9A=1
export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_LIQUID_STRICT_OUTFLOW_0493X9B=1
export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_LIQUID_TYPE_0493X9B="$LIQUID_TYPE"
export MPCD_Q6_PHASE_OUTLET_GHOST_CONTINUATION_0493X9C_OUTLET=1
export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_SPECIES_0493X8R_DISABLE=1
export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_RESERVOIR_0493X8X_LAYERS="$NEUMANN_VIRTUAL_LAYERS"
export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_RESERVOIR_0493X8X_COARSE_LAYERS="$NEUMANN_COARSE_LAYERS"
if [[ -n "$NEUMANN_TARGET_OCCUPANCY" ]]; then
  export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_PRESSURE_RESERVOIR_0493X8Y_TARGET_OCCUPANCY="$NEUMANN_TARGET_OCCUPANCY"
fi
case "$NEUMANN_PROFILE" in
  x9c) ;;
  x9d-fix1) export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RESIDENT_OPT_0493X9D_FIX1=1 ;;
  x9e)
    export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RESIDENT_OPT_0493X9D_FIX1=1
    export MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_POOL_0493X9E=1
    ;;
  *) echo "[0493x14bc] ERROR bad NEUMANN_PROFILE=$NEUMANN_PROFILE" >&2; exit 2 ;;
esac

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_${CASE_LABEL}.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_${CASE_LABEL}.env" <<META
BENCHMARK=basilisk_atomisation_2d_stageA_cold_re500
REFERENCE_URL=https://basilisk.fr/src/examples/atomisation.c
TARGET_RE_L=$TARGET_RE_L
GAMMA=$GAMMA
LIQUID_MASS=$LIQUID_MASS
LIQUID_KBT=$LIQUID_KBT
GAS_MASS=$GAS_MASS
GAS_KBT=$GAS_KBT
TARGET_WE_G=$TARGET_WE_G
TARGET_DENSITY_RATIO=$TARGET_DENSITY_RATIO
TARGET_ST=$TARGET_ST
BASILISK_PULSE_REL_AMPLITUDE=$BASILISK_PULSE_REL_AMPLITUDE
BASILISK_PULSE_RUNTIME_ENABLE=$BASILISK_PULSE_RUNTIME_ENABLE
INLET_OSCILLATION_PERIOD=$PULSE_PERIOD
INLET_OSCILLATION_PHASE=$INLET_OSCILLATION_PHASE
INLET_OSCILLATION_START_TIME=$INLET_OSCILLATION_START_TIME
INLET_OSCILLATION_TIME_OFFSET=$INLET_OSCILLATION_TIME_OFFSET
JET_DIAMETER_CELLS=$JET_DIAMETER_CELLS
JET_DIAMETER=$JET_D
LIQUID_SPEED=$LIQUID_SPEED
SURFACE_TENSION_SIGMA=$SURFACE_TENSION_SIGMA
LIQUID_NU_REFERENCE=$LIQUID_NU_REFERENCE
LIQUID_NU_REFERENCE_STATUS=$LIQUID_NU_REFERENCE_STATUS
GAS_NU_REFERENCE=$GAS_NU_REFERENCE
GAS_NU_REFERENCE_STATUS=$GAS_NU_REFERENCE_STATUS
ALLOW_LARGE_DUMPS=$ALLOW_LARGE_DUMPS
LAMBDA_L_OVER_H=$LAMBDA_L_OVER_H
LAMBDA_G_OVER_H=$LAMBDA_G_OVER_H
THERMAL_FLIGHT_L=$CTH_L
THERMAL_FLIGHT_G=$CTH_G
ADVECTIVE_FLIGHT_L=$ADV_L
TOTAL_FLIGHT_L=$FLIGHT_L
RE_G_DESIGN=$RE_G_DESIGN
NU_G_OVER_NU_L=$NU_G_OVER_NU_L
MU_L_OVER_MU_G=$MU_L_OVER_MU_G
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=$Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=$Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES
RESTART=$RESTART
RESTART_STATE=${RESTART_STATE:-none}
META

run_ok_surface_print_0493x13zi "Basilisk 2-D cold-liquid Re500 jet; x14ba global inlet oscillation"
echo "[0493x14bc] PARAMS=$PARAMS"
echo "[0493x14bc] STATE=$STATE"
echo "[0493x14bc] RUN_ROOT=$RUN_ROOT"

# Contract guards.
grep -Fqx "openBoundarySegmentCount = 2" "$PARAMS" || { echo '[0493x14bc] ERROR segment count contract' >&2; exit 2; }
grep -Fq "openBoundarySegment0 = left inlet" "$PARAMS" || { echo '[0493x14bc] ERROR liquid inlet contract' >&2; exit 2; }
grep -Fq "openBoundarySegment1 = right outlet" "$PARAMS" || { echo '[0493x14bc] ERROR outlet contract' >&2; exit 2; }
if grep -Eq '^darcyBrinkmanEnable[[:space:]]*=[[:space:]]*true' "$PARAMS"; then
  echo '[0493x14bc] ERROR this benchmark must not contain chi/Darcy nozzle geometry' >&2
  exit 2
fi

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
rc=$?
if [[ $rc -ne 0 ]]; then echo "[0493x14bc] ERROR solver failed rc=$rc" >&2; exit $rc; fi
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo '[0493x14bc] PREFLIGHT_ONLY complete'
  exit 0
fi

# Diagnostic component statistics from periodic full-state dumps.
if suite_truthy_0434 "$ANALYZE_ENABLE"; then
python3 - "$RUN_ROOT" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_TYPE" "$JET_D" "$LIQUID_SPEED" "$DT" <<'PYANA'
from __future__ import annotations
import csv,math,re,struct,sys
from collections import deque
from pathlib import Path
import numpy as np
root=Path(sys.argv[1]); Lx=float(sys.argv[2]); Ly=float(sys.argv[3]); nx=int(sys.argv[4]); ny=int(sys.argv[5]); gamma=float(sys.argv[6]); ltype=int(sys.argv[7]); D=float(sys.argv[8]); U=float(sys.argv[9]); dt=float(sys.argv[10])
h=Lx/nx; magic=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE")); rr=re.compile(r'state_step_(\d+)\.smpcd$')
def read(path):
  with path.open('rb') as f:
    if f.read(16)!=magic: raise RuntimeError('bad state magic')
    version,endian,dim,layout,n,has_type,_,real_bytes,type_bytes=struct.unpack('<IIIIQIIII',f.read(40)); reserved=struct.unpack('<8Q',f.read(64))
    x=np.fromfile(f,'<f8',n); y=np.fromfile(f,'<f8',n); vx=np.fromfile(f,'<f8',n); vy=np.fromfile(f,'<f8',n); typ=np.fromfile(f,'<u4',n)
    mass=np.fromfile(f,'<f8',n) if reserved[0] else np.ones(n); role=np.fromfile(f,np.uint8,n) if reserved[1] else np.ones(n,dtype=np.uint8)
  return x,y,vx,vy,typ,mass,role
def comps(occ,thr):
  wet=occ>=thr; seen=np.zeros_like(wet,dtype=np.uint8); out=[]
  for j in range(ny):
    for i in range(nx):
      if not wet[j,i] or seen[j,i]: continue
      q=deque([(j,i)]); seen[j,i]=1; cells=parts=0; left=False; xmax=-1; ymin=ny; ymax=-1
      while q:
        a,b=q.popleft(); cells+=1; parts+=int(occ[a,b]); left|=(b==0); xmax=max(xmax,b); ymin=min(ymin,a); ymax=max(ymax,a)
        for da,db in ((-1,0),(1,0),(0,-1),(0,1)):
          aa,bb=a+da,b+db
          if 0<=aa<ny and 0<=bb<nx and wet[aa,bb] and not seen[aa,bb]: seen[aa,bb]=1; q.append((aa,bb))
      out.append((cells,parts,left,xmax,ymin,ymax))
  return out
rows=[]; thr=max(1,int(round(.25*gamma)))
for p in sorted((root/'output').glob('state_step_*.smpcd')):
  m=rr.search(p.name)
  if not m: continue
  step=int(m.group(1)); x,y,vx,vy,typ,mass,role=read(p); mask=(role==1)&(typ==ltype); xl=x[mask]; yl=y[mask]
  if not xl.size: continue
  ix=np.clip((xl/h).astype(np.int64),0,nx-1); iy=np.clip((yl/h).astype(np.int64),0,ny-1); occ=np.zeros((ny,nx),dtype=np.int32); np.add.at(occ,(iy,ix),1)
  cc=comps(occ,thr); core=[c for c in cc if c[2]]; det=[c for c in cc if (not c[2]) and c[0]>=2]
  core_x=max((c[3]+1)*h for c in core) if core else math.nan
  t=step*dt; tstar=t*U/D; tb=tstar/6.
  rows.append(dict(step=step,time=t,tOverDU=tstar,basiliskEquivalentTime=tb,liquidParticles=int(xl.size),x99=float(np.quantile(xl,.99)),xMax=float(xl.max()),coreXMax=core_x,detachedComponents=len(det),largestDetachedCells=max([c[0] for c in det],default=0),sprayY10=float(np.quantile(yl,.10)),sprayY90=float(np.quantile(yl,.90))))
out=root/'analysis'/'basilisk_stageA_metrics.csv'; out.parent.mkdir(exist_ok=True)
if rows:
  with out.open('w',newline='') as f: w=csv.DictWriter(f,fieldnames=rows[0]); w.writeheader(); w.writerows(rows)
  print('[0493x14bc-analysis] wrote',out)
else: print('[0493x14bc-analysis] no state dumps found')
PYANA
fi

echo "[0493x14bc] COMPLETE root=$RUN_ROOT"
echo "[0493x14bc] pulseRuntime=$BASILISK_PULSE_RUNTIME_ENABLE period=$PULSE_PERIOD stepsPerPeriod=$PULSE_PERIOD_STEPS"

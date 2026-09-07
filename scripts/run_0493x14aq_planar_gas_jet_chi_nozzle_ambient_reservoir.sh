#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# The current shared helper reads SEED while being sourced under set -u.
SEED="${SEED:-493205}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

GENERATOR="$ROOT/scripts/generate_gas_jet_liquid_bath_2d.py"
ANALYZER="$ROOT/scripts/analyze_gas_jet_liquid_bath_2d.py"
SRC_Q6="$ROOT/src/cuda_q6_resident_0400.cu"
SRC_BASE="$ROOT/src/src_mpcd_base.cpp"
SRC_PARAMS="$ROOT/src/params_io_base.cpp"
for f in "$GENERATOR" "$ANALYZER" "$SRC_Q6" "$SRC_BASE" "$SRC_PARAMS"; do
  [[ -f "$f" ]] || { echo "[gas-jet-chi-nozzle-ambient] ERROR missing $f" >&2; exit 2; }
done
grep -q '0493x14ad — local-x6g-face gauge sampling' "$SRC_Q6" || {
  echo '[gas-jet-chi-nozzle-ambient] ERROR current local gas-traction projection source marker not found' >&2; exit 2;
}
grep -q '0493x7g Q6-g-f prestream Darcy/chi was requested but not handled' "$SRC_BASE" || {
  echo '[gas-jet-chi-nozzle-ambient] ERROR Q6-g-f + resident Darcy/chi integration (0493x7g) not found' >&2; exit 2;
}
grep -q '0493x7g Q6-g-f Darcy requires darcyInitialDeactivateBelowChi<0' "$SRC_PARAMS" || {
  echo '[gas-jet-chi-nozzle-ambient] ERROR Q6-g-f Darcy/chi parameter contract (0493x7g) not found' >&2; exit 2;
}
grep -q -- '--incident-height-over-jet' "$ANALYZER" || {
  echo '[gas-jet-chi-nozzle-ambient] ERROR local jet analyzer with --incident-height-over-jet is required' >&2; exit 2;
}

# =============================================================================
# 0493x14aq — DARCY/CHI NOZZLE + LATERAL AMBIENT GAS RESERVOIRS (2-D)
#
# Purpose: retain the x14ap similarity point and the same chi-Darcy nozzle, while
# changing ONLY the top gas-boundary segmentation so the far lateral gas is
# connected to zero-mean hard-density reservoirs. These rebuild gas at the same
# top barometric target occupancy and kBT as the jet reservoir, but with u=(0,0).
# The existing passive hybrid outlet strips are retained between those reservoirs
# and the nozzle, so returned jet gas can still leave the domain.
#
# Geometry:
#   - a central top segmented inlet feeds the nozzle throat;
#   - two chi=0 vertical wall strips extend downward from the top boundary;
#   - the free jet exits at y = Ly - NOZZLE_LENGTH_CELLS*h;
#   - top outlets begin outside the OUTER nozzle walls;
#   - the liquid bath remains below the nozzle in chi=1 fluid.
#
# chi convention: chi=1 free fluid, chi=0 penalized nozzle wall.
# Particles are NOT deactivated in chi=0: darcyInitialDeactivateBelowChi=-1,
# as required by the qualified Q6-g-f/free_surface_masked Darcy path.
#
# Coupling under test, with meanings written explicitly:
#   x6g   : thermodynamic gas pressure in the liquid pressure boundary condition;
#   x9    : Laplace surface-tension pressure jump sigma*kappa;
#   x10o + CIC + Q2 + x10u/x10v + x12a:
#           qualified liquid-side kinetic support/relocalization closure;
#   x14l  : specular NORMAL reflection of gas particles at the moving interface;
#   x14v  : transfer to liquid of gas normal kinetic impulse in excess of the
#           thermodynamic pressure already represented by x6g;
#   x14ad : local mapping of x6g gauge traction to the interface segments.
#
# x14ai (global Q6-resultant closure) is FORCED OFF: this bath touches walls and
# the domain has external inlet/outlet segments, outside x14ai's valid scope.
#
# No C++/CUDA change.  ./livevis_control.kv remains user-owned/read-only.
# =============================================================================
CASE_LABEL="${CASE_LABEL:-0493x14aq_planar_gas_jet_chi_nozzle_ambient_reservoir}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="segmented"

# ---- Physical/numerical parameters: visible by design ------------------------
Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"; NX="${NX:-512}"; NY="${NY:-256}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
STEPS="${STEPS:-3000}"
BATH_HEIGHT="${BATH_HEIGHT:-0.75}"
GRAVITY_Y="${GRAVITY_Y:--0.5}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"; GAS_KBT="${GAS_KBT:-0.08}"
KBT="$GAS_KBT"                     # x6g gas EOS reads the global kBT.
PARTICLE_MASS="$GAS_MASS"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}" # 90 deg, same resolved liquid/gas fluid as multi-radius qualification
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE="cell_relative_rescale"
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$GAS_KBT"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-1880.0}"
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

# ---- Parameterizable chi-Darcy nozzle ---------------------------------------
# Rectangular slit nozzle. Cell-count parameters keep the chi walls aligned
# exactly with cell faces on the default Cartesian grid.
#
# Experimental-similarity defaults:
#   d = 8*h = 0.03125
#   sigma = 1880
#   => nozzle-scale liquid Bond number Bo_d ~= 0.3404
#      for the present rho_L and |g|, matching the ~0.34 air/water scale
#      associated with a 1.59 mm planar slot.
# The nozzle standoff remains independently parameterizable through
# NOZZLE_LENGTH_CELLS; the present default gives H0/d = 6.
NOZZLE_CENTER_X="${NOZZLE_CENTER_X:-1.0}"
NOZZLE_INNER_WIDTH_CELLS="${NOZZLE_INNER_WIDTH_CELLS:-8}"
NOZZLE_WALL_THICKNESS_CELLS="${NOZZLE_WALL_THICKNESS_CELLS:-4}"
NOZZLE_LENGTH_CELLS="${NOZZLE_LENGTH_CELLS:-16}"

# The segmented inlet is exactly the nozzle throat.
JET_CENTER_X="$NOZZLE_CENTER_X"
JET_WIDTH_CELLS="$NOZZLE_INNER_WIDTH_CELLS"
JET_SPEED="${JET_SPEED:-0.5}"
JET_RAMP_START_TIME="${JET_RAMP_START_TIME:-0.0}"
JET_RAMP_END_TIME="${JET_RAMP_END_TIME:-0.20}"
JET_RAMP_INITIAL_FACTOR="${JET_RAMP_INITIAL_FACTOR:-0.0}"
JET_RAMP_FINAL_FACTOR="${JET_RAMP_FINAL_FACTOR:-1.0}"

# Qualified Q6-g-f + Darcy/chi deterministic mean-Brinkman family.
# With dt=0.002 and alphaMax=2500, lambda=1-exp(-alpha*dt)=0.9933 per step
# in chi=0 cells: wall-cell mean velocity is strongly damped without deleting
# particle support.
DARCY_ALPHA_MIN="${DARCY_ALPHA_MIN:-0.0}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-2500.0}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_USOLID_X="${DARCY_USOLID_X:-0.0}"
DARCY_USOLID_Y="${DARCY_USOLID_Y:-0.0}"
DARCY_FORCING_MODE="${DARCY_FORCING_MODE:-mean}"
DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"

# OFF by default: this first nozzle test adds only the deterministic chi-Darcy
# mean relaxation. The optional chi collision-VP wall mechanism is exposed for
# later A/B tests, but is not silently enabled.
DARCY_CHI_COLLISION_VP_ENABLE="${DARCY_CHI_COLLISION_VP_ENABLE:-false}"
DARCY_CHI_COLLISION_VP_MODE="${DARCY_CHI_COLLISION_VP_MODE:-interface_band}"
DARCY_CHI_COLLISION_VP_GAMMA="${DARCY_CHI_COLLISION_VP_GAMMA:-$GAMMA}"
DARCY_CHI_COLLISION_VP_MASS="${DARCY_CHI_COLLISION_VP_MASS:-$GAS_MASS}"
DARCY_CHI_COLLISION_VP_LAYERS="${DARCY_CHI_COLLISION_VP_LAYERS:-1}"
DARCY_CHI_COLLISION_VP_THRESHOLD="${DARCY_CHI_COLLISION_VP_THRESHOLD:-0.5}"
DARCY_CHI_COLLISION_VP_STRENGTH="${DARCY_CHI_COLLISION_VP_STRENGTH:-0.25}"

case "$DARCY_FORCING_MODE" in
  mean|classic|cell_mean|mean_outward_bath|mean_oriented_bath|brinkman_outward_bath) ;;
  *) echo "[gas-jet-chi-nozzle-ambient] ERROR unsupported Q6-g-f Darcy forcing mode: $DARCY_FORCING_MODE" >&2; exit 2 ;;
esac
# The current top same-face segmented resident path is exercised with HYBRID
# outlets in the existing Q6-g-f/dripping runners.  Keep this first benchmark
# on that already-exercised topology instead of using the right-outlet-specific
# Neumann qualification.
OUTLET_MODE="${OUTLET_MODE:-hybrid}"
OUTLET_FEEDBACK_GAIN="${OUTLET_FEEDBACK_GAIN:-0.0}"
if [[ "$OUTLET_MODE" != "hybrid" ]]; then
  echo "[gas-jet-chi-nozzle-ambient] ERROR first top-same-face qualification requires OUTLET_MODE=hybrid; got $OUTLET_MODE" >&2
  exit 2
fi
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-2}"
# Width of each zero-mean lateral atmospheric reservoir on the top face.
# This is an aperture width along x, not the inward reservoir depth
# (which remains INLET_RESERVOIR_CELLS). 64 cells = 0.25 physical length
# on the default 512x256, Lx=2 grid.
AMBIENT_RESERVOIR_WIDTH_CELLS="${AMBIENT_RESERVOIR_WIDTH_CELLS:-64}"
TOP_OPEN_MARGIN="${TOP_OPEN_MARGIN:-0.01}"
# The CUDA resident segmented 0264 path requires inletThermalNoise==0.
# Gas temperature is maintained by the species thermostat after injection.
INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-0.0}"
if ! awk -v x="$INLET_THERMAL_NOISE" 'BEGIN{exit !(x==0)}'; then
  echo "[gas-jet-chi-nozzle-ambient] ERROR resident segmented inlet requires INLET_THERMAL_NOISE=0" >&2
  exit 2
fi
# Four solid faces are structurally required by the resident segmented collision
# subset.  Zero accommodation makes their collision coupling slip/specular-like,
# avoiding an arbitrary single virtual-particle mass for a two-species box.
WALL_ACCOMMODATION="${WALL_ACCOMMODATION:-0.0}"
if ! awk -v x="$WALL_ACCOMMODATION" 'BEGIN{exit !(x==0)}'; then
  echo "[gas-jet-chi-nozzle-ambient] ERROR first gas/liquid jet qualification fixes WALL_ACCOMMODATION=0" >&2
  exit 2
fi

# Q6-g-f projected liquid: standard signed density restoration profile.
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1600}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=1

SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
VIRIAL_DENSITY_KICK_ENABLE=false

SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-$SUMMARY_EVERY}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"   # 0.2 time-unit sampling at dt=0.002; compact archive excludes .smpcd files
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-1.0}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14aq_planar_gas_jet_chi_nozzle_ambient_reservoir_s${SURFACE_TENSION_SIGMA}_seed${SEED}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
THREADS="${THREADS:-8}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-25}"
LIVE_VIS_NX="${LIVE_VIS_NX:-256}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"; LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"; LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"

GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
RUN_OK_GENERATOR_PATH="$GENERATOR"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH
suite_defaults_common_0434
suite_compute_derived_0434

# ---- Derived physical controls and rejection of obviously unresolved cases ---
read -r H CELL_AREA JET_WIDTH JET_SMIN JET_SMAX GAS_P_REF GAS_RHO LIQUID_RHO CTH CJET CCOMB HBAR BARO_RATIO WE_G BO_W FR_W INLET_OCC <<<"$(python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$JET_CENTER_X" "$JET_WIDTH_CELLS" "$JET_SPEED" "$DT" \
  "$GAS_MASS" "$GAS_KBT" "$LIQUID_MASS" "$SURFACE_TENSION_SIGMA" "$GRAVITY_Y" "$BATH_HEIGHT" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4]); gam=float(sys.argv[5])
xc=float(sys.argv[6]); wc=float(sys.argv[7]); uj=float(sys.argv[8]); dt=float(sys.argv[9]); mg=float(sys.argv[10]); kg=float(sys.argv[11]); ml=float(sys.argv[12]); sig=float(sys.argv[13]); gy=float(sys.argv[14]); bh=float(sys.argv[15])
hx=lx/nx; hy=ly/ny
if abs(hx-hy)>1e-12*max(1,abs(hx),abs(hy)): raise SystemExit('[gas-jet-chi-nozzle-ambient] square cells required')
if abs(hx-1/256)>1e-12: raise SystemExit(f'[gas-jet-chi-nozzle-ambient] first qualification keeps h=1/256, got {hx:.17g}')
if abs(bh/hy-round(bh/hy))>1e-10: raise SystemExit('[gas-jet-chi-nozzle-ambient] BATH_HEIGHT must lie on a cell boundary')
W=wc*hx; smin=(xc-.5*W)/lx; smax=(xc+.5*W)/lx
if not (0.02<smin<smax<0.98): raise SystemExit('[gas-jet-chi-nozzle-ambient] jet segment too close to top corners')
A=hx*hy; pref=gam*kg/A; rhoG=gam*mg/A; rhoL=gam*ml/A
cth=math.sqrt(kg/mg)*dt/hx; cjet=abs(uj)*dt/hx; ccomb=cth+cjet
if ccomb>0.80: raise SystemExit(f'[gas-jet-chi-nozzle-ambient] unresolved gas flight: Cthermal+Cjet={ccomb:.6g} > 0.80 cell/step')
gabs=abs(gy)
if gy>1e-15: raise SystemExit('[gas-jet-chi-nozzle-ambient] default geometry expects GRAVITY_Y <= 0')
if gabs>0:
    H=kg/(mg*gabs); gh=ly-bh; ratio=math.exp(-gh/H)
    mf=(H/gh)*(1-math.exp(-gh/H)); n0=gam/mf; ntop=n0*math.exp(-(gh-.5*hy)/H)
else:
    H=float('inf'); ratio=1.0; ntop=gam
We=rhoG*uj*uj*W/sig
Bo=rhoL*gabs*W*W/sig if sig>0 else float('inf')
Fr=abs(uj)/math.sqrt(gabs*W) if gabs>0 else float('inf')
print(hx,A,W,smin,smax,pref,rhoG,rhoL,cth,cjet,ccomb,H,ratio,We,Bo,Fr,max(2,int(round(ntop))))
PY
)"

# Resolve nozzle geometry on cell faces and derive the outlet segments.
read -r NOZZLE_INNER_XMIN NOZZLE_INNER_XMAX NOZZLE_OUTER_XMIN NOZZLE_OUTER_XMAX \
        NOZZLE_EXIT_Y NOZZLE_WALL_THICKNESS NOZZLE_LENGTH \
        NOZZLE_STANDOFF NOZZLE_STANDOFF_OVER_WIDTH \
        LEFT_WALL_SMIN LEFT_WALL_SMAX RIGHT_WALL_SMIN RIGHT_WALL_SMAX \
        DARCY_LAMBDA <<<"$(python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$NOZZLE_CENTER_X" "$NOZZLE_INNER_WIDTH_CELLS" \
  "$NOZZLE_WALL_THICKNESS_CELLS" "$NOZZLE_LENGTH_CELLS" "$BATH_HEIGHT" \
  "$DARCY_ALPHA_MAX" "$DT" <<'PY'
import math, sys
lx,ly=float(sys.argv[1]),float(sys.argv[2])
nx,ny=int(sys.argv[3]),int(sys.argv[4])
xc=float(sys.argv[5])
wcell=int(sys.argv[6]); tcell=int(sys.argv[7]); lcell=int(sys.argv[8])
bath=float(sys.argv[9]); alpha=float(sys.argv[10]); dt=float(sys.argv[11])
hx,hy=lx/nx,ly/ny
if abs(hx-hy) > 1e-12*max(1.0,abs(hx),abs(hy)):
    raise SystemExit("[gas-jet-chi-nozzle-ambient] square cells required")
if wcell < 2 or tcell < 1 or lcell < 1:
    raise SystemExit("[gas-jet-chi-nozzle-ambient] require innerWidthCells>=2, wallThicknessCells>=1, lengthCells>=1")
inner0=xc-0.5*wcell*hx
inner1=xc+0.5*wcell*hx
outer0=inner0-tcell*hx
outer1=inner1+tcell*hx
exit_y=ly-lcell*hy
for name,v in (("inner0",inner0),("inner1",inner1),("outer0",outer0),("outer1",outer1)):
    if not (0.0 < v < lx):
        raise SystemExit(f"[gas-jet-chi-nozzle-ambient] {name}={v} outside domain")
if not (outer0 < inner0 < inner1 < outer1):
    raise SystemExit("[gas-jet-chi-nozzle-ambient] invalid nozzle x ordering")
if exit_y <= bath + 4*hy:
    raise SystemExit(
        f"[gas-jet-chi-nozzle-ambient] nozzle exit y={exit_y:.9g} too close to bath={bath:.9g}; "
        "keep at least 4 cells of free-jet gap"
    )
# Require all nozzle edges to lie on cell faces so the binary chi field is exact.
for name,v in (("inner0",inner0),("inner1",inner1),("outer0",outer0),("outer1",outer1),("exit_y",exit_y)):
    q=(v/hx) if name != "exit_y" else (v/hy)
    if abs(q-round(q)) > 1e-9:
        raise SystemExit(f"[gas-jet-chi-nozzle-ambient] {name}={v:.17g} is not aligned with a cell face")
W=inner1-inner0
stand=exit_y-bath
lam=1.0-math.exp(-alpha*dt)
print(inner0,inner1,outer0,outer1,exit_y,tcell*hx,lcell*hy,stand,stand/W,
      outer0/lx,inner0/lx,inner1/lx,outer1/lx,lam)
PY
)"

# Top face:
# ambient hard-density inlet | passive outlet | chi wall | jet inlet |
# chi wall | passive outlet | ambient hard-density inlet.
#
# All inlet segments share inletTargetOccupancy=INLET_OCC and inletKBT=GAS_KBT.
# The lateral reservoirs prescribe exactly zero cell-mean velocity, whereas the
# central throat retains the ramped downward JET_SPEED.
read -r LEFT_AMBIENT_SMIN LEFT_AMBIENT_SMAX LEFT_OUTLET_SMIN LEFT_OUTLET_SMAX \
        RIGHT_OUTLET_SMIN RIGHT_OUTLET_SMAX RIGHT_AMBIENT_SMIN RIGHT_AMBIENT_SMAX \
  <<<"$(python3 - \
    "$NX" "$TOP_OPEN_MARGIN" "$AMBIENT_RESERVOIR_WIDTH_CELLS" \
    "$LEFT_WALL_SMIN" "$RIGHT_WALL_SMAX" <<'PY'
import sys
nx=int(sys.argv[1])
margin=float(sys.argv[2])
nres=int(sys.argv[3])
left_wall=float(sys.argv[4])
right_wall=float(sys.argv[5])
if not (0 <= margin < 0.25):
    raise SystemExit("[gas-jet-chi-nozzle-ambient] TOP_OPEN_MARGIN must lie in [0,0.25)")
if nres < 1:
    raise SystemExit("[gas-jet-chi-nozzle-ambient] AMBIENT_RESERVOIR_WIDTH_CELLS must be >=1")
w=nres/nx
la0=margin
la1=la0+w
lo0=la1
lo1=left_wall
ro0=right_wall
ra1=1.0-margin
ra0=ra1-w
ro1=ra0
if not (0 <= la0 < la1 < lo1 < right_wall < ro1 < ra0 < ra1 <= 1):
    raise SystemExit(
        "[gas-jet-chi-nozzle-ambient] lateral reservoir width leaves insufficient passive outlet aperture"
    )
print(la0,la1,lo0,lo1,ro0,ro1,ra0,ra1)
PY
)"

ANALYSIS_INCIDENT_HEIGHT_OVER_JET="${ANALYSIS_INCIDENT_HEIGHT_OVER_JET:-$(awk -v s="$NOZZLE_STANDOFF_OVER_WIDTH" 'BEGIN{printf "%.17g",0.5*s}')}"

python3 - \
  "$LEFT_AMBIENT_SMIN" "$LEFT_AMBIENT_SMAX" \
  "$LEFT_OUTLET_SMIN" "$LEFT_OUTLET_SMAX" \
  "$LEFT_WALL_SMIN" "$LEFT_WALL_SMAX" \
  "$JET_SMIN" "$JET_SMAX" \
  "$RIGHT_WALL_SMIN" "$RIGHT_WALL_SMAX" \
  "$RIGHT_OUTLET_SMIN" "$RIGHT_OUTLET_SMAX" \
  "$RIGHT_AMBIENT_SMIN" "$RIGHT_AMBIENT_SMAX" <<'PY'
import sys
a=list(map(float,sys.argv[1:]))
(la0,la1,lo0,lo1,lw0,lw1,ji0,ji1,rw0,rw1,ro0,ro1,ra0,ra1)=a
if not (0 <= la0 < la1 <= lo0 < lo1 <= lw0 < lw1 <= ji0 < ji1 <= rw0 < rw1 <= ro0 < ro1 <= ra0 < ra1 <= 1):
    raise SystemExit(
        "[gas-jet-chi-nozzle-ambient] invalid top segmentation; expected "
        "ambient | outlet | left chi wall | jet | right chi wall | outlet | ambient"
    )
PY

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$CAMPAIGN_ROOT"; fi
suite_prepare_dirs_0434 "$CAMPAIGN_ROOT"
mkdir -p "$CAMPAIGN_ROOT/chi"
STATE="$CAMPAIGN_ROOT/init/${CASE_LABEL}.smpcd"
OUT="$CAMPAIGN_ROOT/output"
PARAMS="$CAMPAIGN_ROOT/params/${CASE_LABEL}.kv"
LOG="$CAMPAIGN_ROOT/logs/${CASE_LABEL}.log"
TF="$CAMPAIGN_ROOT/logs/${CASE_LABEL}.time"
ANALYSIS_DIR="$CAMPAIGN_ROOT/analysis"
mkdir -p "$OUT" "$ANALYSIS_DIR"

python3 "$GENERATOR" \
  --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --bath-height "$BATH_HEIGHT" --gravity-y "$GRAVITY_Y" \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
  --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED"

CHI_FILE="$CAMPAIGN_ROOT/chi/${CASE_LABEL}_${NX}x${NY}.f32"
CHI_META="$CHI_FILE.json"
python3 - "$CHI_FILE" "$CHI_META" "$Lx" "$Ly" "$NX" "$NY" \
  "$NOZZLE_INNER_XMIN" "$NOZZLE_INNER_XMAX" "$NOZZLE_OUTER_XMIN" "$NOZZLE_OUTER_XMAX" \
  "$NOZZLE_EXIT_Y" "$NOZZLE_CENTER_X" "$NOZZLE_INNER_WIDTH_CELLS" \
  "$NOZZLE_WALL_THICKNESS_CELLS" "$NOZZLE_LENGTH_CELLS" <<'PY'
import json, struct, sys
from pathlib import Path

out=Path(sys.argv[1]); meta=Path(sys.argv[2])
lx,ly=float(sys.argv[3]),float(sys.argv[4])
nx,ny=int(sys.argv[5]),int(sys.argv[6])
inner0,inner1,outer0,outer1,exit_y=map(float,sys.argv[7:12])
xc=float(sys.argv[12]); wcell=int(sys.argv[13]); tcell=int(sys.argv[14]); lcell=int(sys.argv[15])
hx,hy=lx/nx,ly/ny

vals=[]
solid=0
left_solid=0
right_solid=0
for j in range(ny):
    y=(j+0.5)*hy
    in_y=(y >= exit_y)
    for i in range(nx):
        x=(i+0.5)*hx
        left=in_y and (outer0 <= x < inner0)
        right=in_y and (inner1 <= x < outer1)
        is_solid=left or right
        vals.append(0.0 if is_solid else 1.0)
        solid += int(is_solid)
        left_solid += int(left)
        right_solid += int(right)

expected=2*tcell*lcell
if solid != expected or left_solid != tcell*lcell or right_solid != tcell*lcell:
    raise SystemExit(
        f"[gas-jet-chi-nozzle-ambient] chi cell-count mismatch solid={solid} expected={expected} "
        f"left={left_solid} right={right_solid}"
    )

out.parent.mkdir(parents=True,exist_ok=True)
out.write_bytes(struct.pack(f"<{len(vals)}f",*vals))
meta.write_text(json.dumps({
    "format":"float32 little-endian row-major",
    "convention":{"fluid":1.0,"penalized_nozzle_wall":0.0},
    "grid":{"Lx":lx,"Ly":ly,"Nx":nx,"Ny":ny,"hx":hx,"hy":hy},
    "nozzle":{
        "centerX":xc,
        "innerXMin":inner0,"innerXMax":inner1,
        "outerXMin":outer0,"outerXMax":outer1,
        "exitY":exit_y,
        "innerWidthCells":wcell,
        "wallThicknessCells":tcell,
        "lengthCells":lcell,
        "solidCells":solid
    }
},indent=2)+"\n")
print(
    f"[gas-jet-chi-nozzle-ambient] chi={out} solidCells={solid} "
    f"inner=[{inner0:.9g},{inner1:.9g}] outer=[{outer0:.9g},{outer1:.9g}] "
    f"exitY={exit_y:.9g}"
)
PY

LREF="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GREF="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"
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
openBoundarySegmentCount = 5
# Central driven jet reservoir: same density target, ramped downward velocity.
openBoundarySegment0 = top inlet $JET_SMIN $JET_SMAX 0.0 -$JET_SPEED $GAS_TYPE $GAS_MASS
# Far lateral atmospheric reservoirs: same density/kBT target, zero mean velocity.
openBoundarySegment1 = top inlet $LEFT_AMBIENT_SMIN $LEFT_AMBIENT_SMAX 0.0 0.0 $GAS_TYPE $GAS_MASS
openBoundarySegment2 = top outlet $LEFT_OUTLET_SMIN $LEFT_OUTLET_SMAX 0.0 0.0 0 $GAS_MASS
openBoundarySegment3 = top outlet $RIGHT_OUTLET_SMIN $RIGHT_OUTLET_SMAX 0.0 0.0 0 $GAS_MASS
openBoundarySegment4 = top inlet $RIGHT_AMBIENT_SMIN $RIGHT_AMBIENT_SMAX 0.0 0.0 $GAS_TYPE $GAS_MASS
inletVelocityRampEnable = true
inletVelocityRampStartTime = $JET_RAMP_START_TIME
inletVelocityRampEndTime = $JET_RAMP_END_TIME
inletVelocityRampInitialFactor = $JET_RAMP_INITIAL_FACTOR
inletVelocityRampFinalFactor = $JET_RAMP_FINAL_FACTOR
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = $GAS_KBT
inletThermalNoise = $INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $INLET_RESERVOIR_CELLS
inletTargetOccupancy = $INLET_OCC
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true
openBoundaryOutletMode = $OUTLET_MODE
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = $OUTLET_FEEDBACK_GAIN
bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
taylorGreenForcingEnable = false
wallVpEnable = false
wallAccommodation = $WALL_ACCOMMODATION
wallVpGamma = $GAMMA
wallVpMass = $LIQUID_MASS
wallKBT = -1.0
wallThermalNoise = 0.0
darcyBrinkmanEnable = true
darcyChiMode = file
darcyChiFile = $CHI_FILE
darcyChiNx = $NX
darcyChiNy = $NY
darcyChiFileFormat = float32
darcyAlphaMin = $DARCY_ALPHA_MIN
darcyAlphaMax = $DARCY_ALPHA_MAX
darcyQ = $DARCY_Q
darcyUSolidX = $DARCY_USOLID_X
darcyUSolidY = $DARCY_USOLID_Y
darcyCostEvery = $DARCY_COST_EVERY
darcyCostFilename = darcy_cost_0343.csv
darcyThreadsPerBlock = $DARCY_THREADS_PER_BLOCK
darcyInitialDeactivateBelowChi = -1.0
darcyBrinkmanForcingMode = $DARCY_FORCING_MODE
darcyChiCollisionVpEnable = $DARCY_CHI_COLLISION_VP_ENABLE
darcyChiCollisionVpMode = $DARCY_CHI_COLLISION_VP_MODE
darcyChiCollisionVpGamma = $DARCY_CHI_COLLISION_VP_GAMMA
darcyChiCollisionVpMass = $DARCY_CHI_COLLISION_VP_MASS
darcyChiCollisionVpLayers = $DARCY_CHI_COLLISION_VP_LAYERS
darcyChiCollisionVpThreshold = $DARCY_CHI_COLLISION_VP_THRESHOLD
darcyChiCollisionVpStrength = $DARCY_CHI_COLLISION_VP_STRENGTH
topoBenchmarkEnable = false
topoBenchmarkForceEnable = false
topoBenchmarkDragLiftEnable = false
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
speciesDiagnosticsFilename = species_runtime_0493x14aq.csv
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
# Current Q6-g-f cooperative resident CG.
export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0

# Start from all optional surface-kinetic branches OFF, then enable exactly the
# integrated liquid/gas coupling under test.
run_ok_surface_export_off_flags_0493x13zi
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$GAS_P_REF"
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1

# Liquid-side kinetic support/relocalization closure.
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

# Gas-liquid interaction closure.
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
# Global Q6-resultant closure deliberately OFF: wall/open-boundary-connected bath.
export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=0

export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1

suite_prepare_livevis_control_0434 "$CAMPAIGN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$CAMPAIGN_ROOT/logs/environment_${CASE_LABEL}.env" "$RUN_MODE"
cat >> "$CAMPAIGN_ROOT/logs/environment_${CASE_LABEL}.env" <<META
BENCHMARK=planar_gas_jet_normal_to_liquid_bath_2d
GAS_THERMAL_FLIGHT_CELLS=$CTH
GAS_DIRECTED_JET_FLIGHT_CELLS=$CJET
GAS_THERMAL_PLUS_DIRECTED_FLIGHT_CELLS=$CCOMB
GAS_BAROMETRIC_SCALE_HEIGHT=$HBAR
GAS_TOP_TO_BATH_DENSITY_RATIO=$BARO_RATIO
GAS_INLET_TARGET_OCCUPANCY=$INLET_OCC
AMBIENT_RESERVOIR_WIDTH_CELLS=$AMBIENT_RESERVOIR_WIDTH_CELLS
AMBIENT_RESERVOIR_TARGET_OCCUPANCY=$INLET_OCC
AMBIENT_RESERVOIR_MEAN_UX=0
AMBIENT_RESERVOIR_MEAN_UY=0
LEFT_AMBIENT_SMIN=$LEFT_AMBIENT_SMIN
LEFT_AMBIENT_SMAX=$LEFT_AMBIENT_SMAX
LEFT_OUTLET_SMIN=$LEFT_OUTLET_SMIN
LEFT_OUTLET_SMAX=$LEFT_OUTLET_SMAX
RIGHT_OUTLET_SMIN=$RIGHT_OUTLET_SMIN
RIGHT_OUTLET_SMAX=$RIGHT_OUTLET_SMAX
RIGHT_AMBIENT_SMIN=$RIGHT_AMBIENT_SMIN
RIGHT_AMBIENT_SMAX=$RIGHT_AMBIENT_SMAX
JET_WIDTH=$JET_WIDTH
JET_SPEED=$JET_SPEED
NOZZLE_CHI_FILE=$CHI_FILE
NOZZLE_CENTER_X=$NOZZLE_CENTER_X
NOZZLE_INNER_WIDTH_CELLS=$NOZZLE_INNER_WIDTH_CELLS
NOZZLE_WALL_THICKNESS_CELLS=$NOZZLE_WALL_THICKNESS_CELLS
NOZZLE_LENGTH_CELLS=$NOZZLE_LENGTH_CELLS
NOZZLE_EXIT_Y=$NOZZLE_EXIT_Y
NOZZLE_STANDOFF=$NOZZLE_STANDOFF
NOZZLE_STANDOFF_OVER_WIDTH=$NOZZLE_STANDOFF_OVER_WIDTH
DOMAIN_WIDTH_OVER_JET_WIDTH=$(awk -v L="$Lx" -v W="$JET_WIDTH" 'BEGIN{printf "%.17g",L/W}')
LIQUID_DEPTH_OVER_JET_WIDTH=$(awk -v H="$BATH_HEIGHT" -v W="$JET_WIDTH" 'BEGIN{printf "%.17g",H/W}')
DARCY_ALPHA_MIN=$DARCY_ALPHA_MIN
DARCY_ALPHA_MAX=$DARCY_ALPHA_MAX
DARCY_LAMBDA_PER_STEP=$DARCY_LAMBDA
DARCY_Q=$DARCY_Q
DARCY_FORCING_MODE=$DARCY_FORCING_MODE
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=-1
DARCY_CHI_COLLISION_VP_ENABLE=$DARCY_CHI_COLLISION_VP_ENABLE
ANALYSIS_INCIDENT_HEIGHT_OVER_JET=$ANALYSIS_INCIDENT_HEIGHT_OVER_JET
GAS_WEBER_JET_WIDTH=$WE_G
LIQUID_BOND_JET_WIDTH=$BO_W
JET_FROUDE_JET_WIDTH=$FR_W
MPCD_X14L_GAS_SPECULAR_REFLECTION=1
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=0
META

run_ok_surface_print_0493x13zi "gas pressure + Laplace tension + liquid kinetic support + gas specular reflection + gas excess normal impulse + local gas traction"
echo "===== PLANAR GAS JET -> LIQUID BATH, 2-D ====="
echo "PATHS: runner=$ROOT/scripts/run_0493x14aq_planar_gas_jet_chi_nozzle_ambient_reservoir.sh"
echo "       generator=$GENERATOR analyzer=$ANALYZER binary=$BIN"
echo "       state=$STATE params=$PARAMS output=$OUT"
echo "DOMAIN: L=${Lx}x${Ly} grid=${NX}x${NY} h=$H bathHeight=$BATH_HEIGHT gravityY=$GRAVITY_Y"
echo "PHASE: liquid(type=$LIQUID_TYPE,m=$LIQUID_MASS,kBT=$LIQUID_KBT,rhoNom=$LIQUID_RHO)"
echo "       gas(type=$GAS_TYPE,m=$GAS_MASS,kBT=$GAS_KBT,rhoNom=$GAS_RHO) baroH=$HBAR nTop/nBath=$BARO_RATIO"
echo "JET:   top inlet, centerX=$JET_CENTER_X throatWidthCells=$JET_WIDTH_CELLS throatWidth=$JET_WIDTH U=$JET_SPEED inletN=$INLET_OCC"
echo "       ramp t=[$JET_RAMP_START_TIME,$JET_RAMP_END_TIME] factor=[$JET_RAMP_INITIAL_FACTOR,$JET_RAMP_FINAL_FACTOR]"
echo "NOZZLE chi-Darcy: innerX=[$NOZZLE_INNER_XMIN,$NOZZLE_INNER_XMAX] outerX=[$NOZZLE_OUTER_XMIN,$NOZZLE_OUTER_XMAX]"
echo "       wallThicknessCells=$NOZZLE_WALL_THICKNESS_CELLS lengthCells=$NOZZLE_LENGTH_CELLS exitY=$NOZZLE_EXIT_Y"
echo "       initialStandoff=$NOZZLE_STANDOFF  H0/d=$NOZZLE_STANDOFF_OVER_WIDTH"
echo "SIMILARITY: Lx/d=$(awk -v L="$Lx" -v W="$JET_WIDTH" 'BEGIN{printf "%.9g",L/W}')  Hliquid/d=$(awk -v H="$BATH_HEIGHT" -v W="$JET_WIDTH" 'BEGIN{printf "%.9g",H/W}')"
echo "DARCY: alpha=[$DARCY_ALPHA_MIN,$DARCY_ALPHA_MAX] q=$DARCY_Q lambdaSolidPerStep=$DARCY_LAMBDA mode=$DARCY_FORCING_MODE"
echo "       initialDeactivate=-1 chiCollisionVP=$DARCY_CHI_COLLISION_VP_ENABLE"
echo "ANALYSIS: incident probe follows etaFar at +$ANALYSIS_INCIDENT_HEIGHT_OVER_JET jet widths (half initial nozzle standoff by default)"
echo "RESOLUTION: gas thermal flight=$CTH h/step; directed jet flight=$CJET h/step; sum=$CCOMB h/step"
echo "DIMENSIONLESS: We_g(W)=$WE_G  Bo_l(W)=$BO_W  Fr(W)=$FR_W"
echo "BOUNDARIES: solid base faces; top = ambient reservoir | outlet | chi wall | jet throat | chi wall | outlet | ambient reservoir"
echo "       ambient widths=${AMBIENT_RESERVOIR_WIDTH_CELLS} cells/side, Ntarget=$INLET_OCC, meanU=(0,0), outlets mode=$OUTLET_MODE"
echo "       left ambient=[$LEFT_AMBIENT_SMIN,$LEFT_AMBIENT_SMAX] left outlet=[$LEFT_OUTLET_SMIN,$LEFT_OUTLET_SMAX]"
echo "       right outlet=[$RIGHT_OUTLET_SMIN,$RIGHT_OUTLET_SMAX] right ambient=[$RIGHT_AMBIENT_SMIN,$RIGHT_AMBIENT_SMAX]"
echo "WALL COLLISION: accommodation=$WALL_ACCOMMODATION (0 = slip/specular-like; no virtual-wall momentum coupling)"
echo "INLET: thermalNoise=$INLET_THERMAL_NOISE; species thermostat restores gas target kBT=$GAS_KBT"
echo "COUPLING: chi-Darcy nozzle shaping + thermodynamic gas pressure + surface tension + gas specular reflection + gas excess normal impulse + local traction projection"
echo "GLOBAL RESULTANT CLOSURE: OFF (required: bath is wall/open-boundary connected)"
echo "RUN: steps=$STEPS dt=$DT tEnd=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{printf "%.9g",n*d}') summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY"
echo "NOTE: ./livevis_control.kv is user-owned/read-only and is not modified"
echo "================================================"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo '[gas-jet-chi-nozzle-ambient] PREFLIGHT_ONLY complete'
  exit 0
fi

python3 "$ANALYZER" \
  --run-root "$CAMPAIGN_ROOT" --nx "$NX" --ny "$NY" --Lx "$Lx" --Ly "$Ly" \
  --gamma "$GAMMA" --liquid-type "$LIQUID_TYPE" --liquid-mass "$LIQUID_MASS" \
  --gas-type "$GAS_TYPE" --gas-kbt "$GAS_KBT" \
  --jet-center-x "$JET_CENTER_X" --jet-width "$JET_WIDTH" --dt "$DT" \
  --jet-ramp-end-time "$JET_RAMP_END_TIME" \
  --incident-height-over-jet "$ANALYSIS_INCIDENT_HEIGHT_OVER_JET"

OUT_TAR="$CAMPAIGN_ROOT/0493x14aq_planar_gas_jet_chi_nozzle_ambient_reservoir_compact.tar.gz"
FILES=(
  analysis
  "chi/${CASE_LABEL}_${NX}x${NY}.f32"
  "chi/${CASE_LABEL}_${NX}x${NY}.f32.json"
  "output/darcy_cost_0343.csv"
  "output/summary_runtime.csv"
  "output/species_runtime_0493x14aq.csv"
  "output/cuda_phase_interface_pressure_0493x6g.csv"
  "output/cuda_phase_interface_stencil_0493x6f.csv"
  "output/cuda_species_q6_independent_masked_0493w5.csv"
  "logs/${CASE_LABEL}.log"
  "logs/${CASE_LABEL}.time"
  "logs/environment_${CASE_LABEL}.env"
  "params/${CASE_LABEL}.kv"
  "init/${CASE_LABEL}.smpcd.json"
)
PRESENT=(); for f in "${FILES[@]}"; do [[ -e "$CAMPAIGN_ROOT/$f" ]] && PRESENT+=("$f"); done
tar -czf "$OUT_TAR" -C "$CAMPAIGN_ROOT" "${PRESENT[@]}"
echo "[gas-jet-chi-nozzle-ambient] COMPLETE"
echo "[gas-jet-chi-nozzle-ambient] compact=$OUT_TAR"

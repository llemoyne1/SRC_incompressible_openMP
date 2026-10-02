#!/usr/bin/env bash

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SEED="${SEED:-493205}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

GENERATOR="$ROOT/scripts/generate_gas_jet_liquid_bath_2d.py"
STABILITY_MATLAB="analyze_0493x24e_sato_airwater_bath_stabilization"
SRC_Q6="$ROOT/src/cuda_q6_resident_0400.cu"
SRC_BASE="$ROOT/src/src_mpcd_base.cpp"
SRC_PARAMS="$ROOT/src/params_io_base.cpp"
for f in "$GENERATOR" "$SRC_Q6" "$SRC_BASE" "$SRC_PARAMS"; do
  [[ -f "$f" ]] || { echo "[0493x24e] ERROR missing $f" >&2; exit 2; }
done
grep -q '0493x14ad — local-x6g-face gauge sampling' "$SRC_Q6" || {
  echo '[0493x24e] ERROR current local gas-traction projection source marker not found' >&2; exit 2;
}
grep -q '0493x7g Q6-g-f prestream Darcy/chi was requested but not handled' "$SRC_BASE" || {
  echo '[0493x24e] ERROR Q6-g-f + resident Darcy/chi integration (0493x7g) not found' >&2; exit 2;
}
grep -q '0493x7g Q6-g-f Darcy requires darcyInitialDeactivateBelowChi<0' "$SRC_PARAMS" || {
  echo '[0493x24e] ERROR Q6-g-f Darcy/chi parameter contract (0493x7g) not found' >&2; exit 2;
}

# -----------------------------------------------------------------------------
# 0493x24e — SATO WATER/AIR-DENSITY BATH PRE-STABILIZATION
#
# Goal: build an unforced, statistically stationary gas/liquid bath that can be
# used as a common physical RESTART state for later Sato forcing cases.
#
# The central top segment remains a hard-density gas reservoir with ZERO mean
# velocity.  Thus there is gas exchange needed by the open-boundary atmosphere,
# but no directed gas injection and no jet momentum.  The nozzle, outlets, bath,
# water/air density ratio, kBT, dt, gravity, sigma and Brinkman walls are already
# those intended for the subsequent x24 water/air-similarity campaign.
#
# Default duration: 15000 steps (t=6 at dt=4e-4).
# Late stationarity window: 10000:15000.
# Dumps: every 1000 steps for later RESTART selection.
# LiveVis: enabled; ./livevis_control.kv remains user-owned and authoritative.
# No C++/CUDA source change.
# -----------------------------------------------------------------------------

# =============================================================================
# Unforced equilibrium case. Geometry matches the Sato ratios in the 2-D planar
# analogue: vessel width/nozzle width=20, liquid depth/nozzle width=10, H/D=0.8.
# The same nozzle and atmospheric top segmentation will be reused by the forced
# campaign after a late stationary dump has been selected.
# =============================================================================
CASE_LABEL="${CASE_LABEL:-0493x24h_sato_short_nozzle_relax}"
TARGET_BO_SATO="${TARGET_BO_SATO:-13.584125}"
TARGET_FRM_SATO="${TARGET_FRM_SATO:-0.0}"
TARGET_H_OVER_D="${TARGET_H_OVER_D:-0.8}"
SATO_STAGE_A_SLOPE="${SATO_STAGE_A_SLOPE:-1.30}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="segmented"

# ---- Physical/numerical parameters: x24h short-nozzle geometry ---------------
#
# x24h keeps EXACTLY the stabilized x24e computational box:
#   Lx = 1.5625, Nx = 400
#   Ly = 1.0,    Ny = 256
#   h  = 1/256
#
# The stabilized liquid surface is near y ~= 0.815.  Instead of increasing Ly
# to restore H/D ~= 0.8, shorten the nozzle from 40 to 31 cells while keeping
# its inlet attached to the original top boundary y=1.
#
# With 31 cells:
#   nozzle exit = 1 - 31/256 = 0.87890625
#
# Use the nearest cell-aligned geometric reference surface
#   BATH_HEIGHT = 209/256 = 0.81640625
# so that
#   (0.87890625 - 0.81640625) / (20/256) = 0.8 exactly.
#
# IMPORTANT: in RESTART mode this BATH_HEIGHT does NOT move or regenerate the
# liquid.  The actual particle state remains the stabilized x24e state.

Lx=1.5625
NX=400
Ly=1.0
NY=256

NOZZLE_INNER_WIDTH_CELLS=20
NOZZLE_LENGTH_CELLS=31
BATH_HEIGHT=0.81640625

python3 - "$Lx" "$Ly" "$NX" "$NY" "$NOZZLE_INNER_WIDTH_CELLS"   "$NOZZLE_LENGTH_CELLS" "$BATH_HEIGHT" "$TARGET_H_OVER_D" <<'PYX24H_DOMAIN'
import sys

lx=float(sys.argv[1]); ly=float(sys.argv[2])
nx=int(sys.argv[3]); ny=int(sys.argv[4])
dc=int(sys.argv[5]); lc=int(sys.argv[6])
bath=float(sys.argv[7]); hd=float(sys.argv[8])

hx=lx/nx
hy=ly/ny

if abs(hx-hy) > 1e-14:
    raise SystemExit(
        f"[0493x24h] ERROR non-square cells hx={hx:.17g} hy={hy:.17g}"
    )

D=dc*hx
exit_y=ly-lc*hy
actual_hd=(exit_y-bath)/D

if abs(actual_hd-hd) > 1e-12:
    raise SystemExit(
        f"[0493x24h] ERROR geometry mismatch: "
        f"target H/D={hd:.12g}, geometric H/D={actual_hd:.12g}"
    )

print(
    f"[0493x24h] fixed-domain geometry PASS "
    f"grid={nx}x{ny} Ly={ly:.12g} "
    f"nozzleLengthCells={lc} exitY={exit_y:.12g} "
    f"referenceBathY={bath:.12g} H/D={actual_hd:.12g}"
)
PYX24H_DOMAIN
GAMMA="${GAMMA:-20}"
DT="${DT:-0.0004}"
STEPS="${STEPS:-15000}"
GRAVITY_Y="${GRAVITY_Y:--0.5}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.0011735205616850552}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"; GAS_KBT="${GAS_KBT:-0.0009388164493480442}"
KBT="$GAS_KBT"                     # x6g gas EOS reads the global kBT.
PARTICLE_MASS="$GAS_MASS"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"
# Water/air density-ratio contract and thermal-velocity-preserving gas scaling.
AIR_WATER_DENSITY_RATIO_REF="${AIR_WATER_DENSITY_RATIO_REF:-0.0011735205616850552}"
GAS_KBT_OVER_MASS_REF="${GAS_KBT_OVER_MASS_REF:-0.8}"
python3 - "$GAS_MASS" "$LIQUID_MASS" "$AIR_WATER_DENSITY_RATIO_REF" "$GAS_KBT" "$GAS_KBT_OVER_MASS_REF" <<'PYX24D_RHO'
import sys
mg,ml,rr,kg,kr=map(float,sys.argv[1:])
r=mg/ml
if abs(r-rr)>1e-10*max(1.0,abs(rr)):
    raise SystemExit(f'[0493x24e] density-ratio mismatch gas/liquid={r:.17g} ref={rr:.17g}')
km=kg/mg
if abs(km-kr)>1e-10*max(1.0,abs(kr)):
    raise SystemExit(f'[0493x24e] gas kBT/m mismatch={km:.17g} ref={kr:.17g}')
print(f'[0493x24e] water/air density-ratio contract PASS rhoG/rhoL={r:.12g} gas_kBT/m={km:.12g}')
PYX24D_RHO

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}" # 90 deg, same resolved liquid/gas fluid as multi-radius qualification
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE="cell_relative_rescale"
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$GAS_KBT"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# Chosen so that Bo_D matches the Sato water/air value for the default D=20h.
SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-294.461365748622}"
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
#   D = 20*h = 0.078125
#   sigma = 294.461365748622
#   => nozzle-scale liquid Bond number Bo_D ~= 13.5841
#      for the present rho_L and |g|, matching the 10 mm water/air Sato reference Bond number.
# Corrected geometry: same nozzle for every H/D; only its rigid vertical
# position relative to the bath changes.  NOZZLE_LENGTH_CELLS is defined above
# because it also determines Ly/NY.
NOZZLE_CENTER_X="${NOZZLE_CENTER_X:-0.78125}"
NOZZLE_WALL_THICKNESS_CELLS="${NOZZLE_WALL_THICKNESS_CELLS:-4}"

# The segmented inlet is exactly the nozzle throat.
JET_CENTER_X="$NOZZLE_CENTER_X"
JET_WIDTH_CELLS="$NOZZLE_INNER_WIDTH_CELLS"
# Stabilization run: no directed gas injection.  The central top segment is
# retained as a zero-mean hard-density gas reservoir so that the atmospheric
# topology, nozzle, outlets and gas inventory are identical to the later
# forced campaign.  JET_SPEED=0 is therefore an equilibrium reservoir, not a jet.
JET_SPEED="${JET_SPEED:-0.0}"
JET_RAMP_START_TIME="${JET_RAMP_START_TIME:-0.0}"
JET_RAMP_END_TIME="${JET_RAMP_END_TIME:-0.0}"
JET_RAMP_INITIAL_FACTOR="${JET_RAMP_INITIAL_FACTOR:-0.0}"
JET_RAMP_FINAL_FACTOR="${JET_RAMP_FINAL_FACTOR:-0.0}"

# Qualified Q6-g-f + Darcy/chi deterministic mean-Brinkman family.
# With the default dt=0.001 and alphaMax=800000, the mean-Brinkman relaxation is effectively solid
# in chi=0 cells: wall-cell mean velocity is strongly damped without deleting
# particle support.
DARCY_ALPHA_MIN="${DARCY_ALPHA_MIN:-0.0}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-800000.0}"
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
  *) echo "[0493x24e] ERROR unsupported Q6-g-f Darcy forcing mode: $DARCY_FORCING_MODE" >&2; exit 2 ;;
esac
# The current top same-face segmented resident path is exercised with HYBRID
# outlets in the existing Q6-g-f/dripping runners.  Keep this first benchmark
# on that already-exercised topology instead of using the right-outlet-specific
# Neumann qualification.
OUTLET_MODE="${OUTLET_MODE:-hybrid}"
OUTLET_FEEDBACK_GAIN="${OUTLET_FEEDBACK_GAIN:-0.0}"
if [[ "$OUTLET_MODE" != "hybrid" ]]; then
  echo "[0493x24e] ERROR first top-same-face qualification requires OUTLET_MODE=hybrid; got $OUTLET_MODE" >&2
  exit 2
fi
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-2}"
# The CUDA resident segmented 0264 path requires inletThermalNoise==0.
# Gas temperature is maintained by the species thermostat after injection.
INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-0.0}"
if ! awk -v x="$INLET_THERMAL_NOISE" 'BEGIN{exit !(x==0)}'; then
  echo "[0493x24e] ERROR resident segmented inlet requires INLET_THERMAL_NOISE=0" >&2
  exit 2
fi
# Four solid faces are structurally required by the resident segmented collision
# subset.  Zero accommodation makes their collision coupling slip/specular-like,
# avoiding an arbitrary single virtual-particle mass for a two-species box.
WALL_ACCOMMODATION="${WALL_ACCOMMODATION:-0.0}"
if ! awk -v x="$WALL_ACCOMMODATION" 'BEGIN{exit !(x==0)}'; then
  echo "[0493x24e] ERROR first gas/liquid jet qualification fixes WALL_ACCOMMODATION=0" >&2
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
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"    # stabilization checkpoints for later campaign RESTART
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-1.0}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x24e_sato_airwater_bath_stabilization_seed${SEED}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
THREADS="${THREADS:-8}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-200}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"; LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"; LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
# Dense observation stream. ./livevis_control.kv remains authoritative.
# In the present campaign it selects particleTypeFilter=1 and rho,ux,uy, i.e.
# dense liquid fields. The x14at analyzer therefore reconstructs h(t) from rho
# and aligns gas-core covariates from the sparse state analyzer.
PARTICLE_TYPE_FILTER=-1
FILTERED_RECORDING_ENABLE=1
RECORD_ENABLE=true
RECORD_FIELDS="rho,ux,uy"
RECORD_EVERY="${RECORD_EVERY:-20}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-20}"

# Restart is a physical continuation from a state dump.  The binary local step
# counter/RNG stream restarts; the origin is recorded explicitly for audit.
RESTART="${RESTART:-0}"
RESTART_STATE="${RESTART_STATE:-}"
RESTART_FROM_STEP="${RESTART_FROM_STEP:-}"
RESTART_TAG="${RESTART_TAG:-segment}"
POSTPROCESS_ONLY="${POSTPROCESS_ONLY:-0}"
ANALYSIS_START_STEP="${ANALYSIS_START_STEP:-10000}"
ANALYSIS_END_STEP="${ANALYSIS_END_STEP:-15000}"
if [[ "$ANALYSIS_END_STEP" -gt "$STEPS" ]]; then
  echo "[0493x24e] ERROR ANALYSIS_END_STEP=$ANALYSIS_END_STEP > STEPS=$STEPS" >&2; exit 2
fi

echo "[0493x24e] water/air bath stabilization, zero directed injection: fixed D_cells=$NOZZLE_INNER_WIDTH_CELLS fixed nozzleLengthCells=$NOZZLE_LENGTH_CELLS targetH/D=$TARGET_H_OVER_D grid=${NX}x${NY} Ly=$Ly alphaMax=$DARCY_ALPHA_MAX"
GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
RUN_OK_GENERATOR_PATH="$GENERATOR"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH
suite_defaults_common_0434
suite_compute_derived_0434

# ---- Derived physical controls and rejection of obviously unresolved cases ---
read -r H CELL_AREA JET_WIDTH JET_SMIN JET_SMAX GAS_P_REF GAS_RHO LIQUID_RHO CTH CJET CCOMB HBAR BARO_RATIO WE_G BO_W FR_W INLET_OCC FRM_SATO_NOMINAL <<<"$(python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$JET_CENTER_X" "$JET_WIDTH_CELLS" "$JET_SPEED" "$DT" \
  "$GAS_MASS" "$GAS_KBT" "$LIQUID_MASS" "$SURFACE_TENSION_SIGMA" "$GRAVITY_Y" "$BATH_HEIGHT" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4]); gam=float(sys.argv[5])
xc=float(sys.argv[6]); wc=float(sys.argv[7]); uj=float(sys.argv[8]); dt=float(sys.argv[9]); mg=float(sys.argv[10]); kg=float(sys.argv[11]); ml=float(sys.argv[12]); sig=float(sys.argv[13]); gy=float(sys.argv[14]); bh=float(sys.argv[15])
hx=lx/nx; hy=ly/ny
if abs(hx-hy)>1e-12*max(1,abs(hx),abs(hy)): raise SystemExit('[0493x24e] square cells required')
if abs(hx-1/256)>1e-12: raise SystemExit(f'[0493x24e] first qualification keeps h=1/256, got {hx:.17g}')
if abs(bh/hy-round(bh/hy))>1e-10: raise SystemExit('[0493x24e] BATH_HEIGHT must lie on a cell boundary')
W=wc*hx; smin=(xc-.5*W)/lx; smax=(xc+.5*W)/lx
if not (0.02<smin<smax<0.98): raise SystemExit('[0493x24e] jet segment too close to top corners')
A=hx*hy; pref=gam*kg/A; rhoG=gam*mg/A; rhoL=gam*ml/A
cth=math.sqrt(kg/mg)*dt/hx; cjet=abs(uj)*dt/hx; ccomb=cth+cjet
if ccomb>0.80: raise SystemExit(f'[0493x24e] unresolved gas flight: Cthermal+Cjet={ccomb:.6g} > 0.80 cell/step')
gabs=abs(gy)
if gy>1e-15: raise SystemExit('[0493x24e] default geometry expects GRAVITY_Y <= 0')
if gabs>0:
    H=kg/(mg*gabs); gh=ly-bh; ratio=math.exp(-gh/H)
    mf=(H/gh)*(1-math.exp(-gh/H)); n0=gam/mf; ntop=n0*math.exp(-(gh-.5*hy)/H)
else:
    H=float('inf'); ratio=1.0; ntop=gam
We=rhoG*uj*uj*W/sig
Bo=rhoL*gabs*W*W/sig if sig>0 else float('inf')
Fr=abs(uj)/math.sqrt(gabs*W) if gabs>0 else float('inf')
frm=((math.pi/4.0)**2)*rhoG*uj*uj/(rhoL*gabs*W) if gabs>0 else float('inf')
print(hx,A,W,smin,smax,pref,rhoG,rhoL,cth,cjet,ccomb,H,ratio,We,Bo,Fr,max(2,int(round(ntop))),frm)
PY
)"

python3 - "$TARGET_FRM_SATO" "$FRM_SATO_NOMINAL" "$TARGET_BO_SATO" "$BO_W" <<'PYX14AT_SIM'
import sys
tf,ff,tb,bb=map(float,sys.argv[1:])
if abs(ff-tf)>5e-10*max(1.0,abs(tf)):
    raise SystemExit(f'[0493x24e] nominal Sato Fr mismatch target={tf:.12g} actual={ff:.12g}')
if abs(bb-tb)>2e-3*max(1.0,abs(tb)):
    raise SystemExit(f'[0493x24e] Bond mismatch target={tb:.12g} actual={bb:.12g}; override sigma only deliberately')
PYX14AT_SIM

python3 - "$JET_SPEED" "$TARGET_FRM_SATO" <<'PYX24E_ZERO'
import sys
u,f=map(float,sys.argv[1:])
if abs(u)>1e-15 or abs(f)>1e-15:
    raise SystemExit(f'[0493x24e] stabilization requires zero directed injection: JET_SPEED={u}, targetFr={f}')
print('[0493x24e] zero-directed-injection contract PASS')
PYX24E_ZERO

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
    raise SystemExit("[0493x24e] square cells required")
if wcell < 2 or tcell < 1 or lcell < 1:
    raise SystemExit("[0493x24e] require innerWidthCells>=2, wallThicknessCells>=1, lengthCells>=1")
inner0=xc-0.5*wcell*hx
inner1=xc+0.5*wcell*hx
outer0=inner0-tcell*hx
outer1=inner1+tcell*hx
exit_y=ly-lcell*hy
for name,v in (("inner0",inner0),("inner1",inner1),("outer0",outer0),("outer1",outer1)):
    if not (0.0 < v < lx):
        raise SystemExit(f"[0493x24e] {name}={v} outside domain")
if not (outer0 < inner0 < inner1 < outer1):
    raise SystemExit("[0493x24e] invalid nozzle x ordering")
if exit_y <= bath + 4*hy:
    raise SystemExit(
        f"[0493x24e] nozzle exit y={exit_y:.9g} too close to bath={bath:.9g}; "
        "keep at least 4 cells of free-jet gap"
    )
# Require all nozzle edges to lie on cell faces so the binary chi field is exact.
for name,v in (("inner0",inner0),("inner1",inner1),("outer0",outer0),("outer1",outer1),("exit_y",exit_y)):
    q=(v/hx) if name != "exit_y" else (v/hy)
    if abs(q-round(q)) > 1e-9:
        raise SystemExit(f"[0493x24e] {name}={v:.17g} is not aligned with a cell face")
W=inner1-inner0
stand=exit_y-bath
lam=1.0-math.exp(-alpha*dt)
print(inner0,inner1,outer0,outer1,exit_y,tcell*hx,lcell*hy,stand,stand/W,
      outer0/lx,inner0/lx,inner1/lx,outer1/lx,lam)
PY
)"

python3 - "$TARGET_H_OVER_D" "$NOZZLE_STANDOFF_OVER_WIDTH" <<'PYX14AT_HD'
import sys
a,b=map(float,sys.argv[1:])
if abs(a-b)>1e-12*max(1.0,abs(a)):
    raise SystemExit(f'[0493x24e] H/D mismatch target={a:.12g} actual={b:.12g}')
PYX14AT_HD

# Top face: WIDE outlet -- chi wall -- inlet/nozzle throat -- chi wall -- WIDE outlet.
# These are intentionally the largest symmetric outlets compatible with the
# 1% corner margins and the finite chi nozzle walls. There is no atmospheric
# reservoir-width parameter to tune.
OUTLET_EDGE_MARGIN="${OUTLET_EDGE_MARGIN:-0.01}"
LEFT_OUTLET_SMIN="${LEFT_OUTLET_SMIN:-$OUTLET_EDGE_MARGIN}"
LEFT_OUTLET_SMAX="${LEFT_OUTLET_SMAX:-$LEFT_WALL_SMIN}"
RIGHT_OUTLET_SMIN="${RIGHT_OUTLET_SMIN:-$RIGHT_WALL_SMAX}"
RIGHT_OUTLET_SMAX="${RIGHT_OUTLET_SMAX:-$(awk -v m="$OUTLET_EDGE_MARGIN" 'BEGIN{printf "%.17g",1.0-m}')}"
ANALYSIS_INCIDENT_HEIGHT_OVER_JET="${ANALYSIS_INCIDENT_HEIGHT_OVER_JET:-$(awk -v s="$NOZZLE_STANDOFF_OVER_WIDTH" 'BEGIN{printf "%.17g",0.5*s}')}"

python3 - "$LEFT_OUTLET_SMIN" "$LEFT_OUTLET_SMAX" "$JET_SMIN" "$JET_SMAX" \
  "$RIGHT_OUTLET_SMIN" "$RIGHT_OUTLET_SMAX" "$LEFT_WALL_SMIN" "$LEFT_WALL_SMAX" \
  "$RIGHT_WALL_SMIN" "$RIGHT_WALL_SMAX" <<'PY'
import sys
lo0,lo1,ji0,ji1,ro0,ro1,lw0,lw1,rw0,rw1=map(float,sys.argv[1:])
if not (0 <= lo0 < lo1 <= lw0 < lw1 <= ji0 < ji1 <= rw0 < rw1 <= ro0 < ro1 <= 1):
    raise SystemExit(
        "[0493x24e] invalid top segmentation; expected "
        "left outlet | left chi wall | inlet | right chi wall | right outlet"
    )
PY

RUN_ROOT="$CAMPAIGN_ROOT"
if [[ "$RESTART" == "1" ]]; then
  [[ -n "$RESTART_STATE" && -s "$RESTART_STATE" ]] || { echo '[0493x24e] ERROR RESTART=1 requires RESTART_STATE=/path/state_step_N.smpcd' >&2; exit 2; }
  if [[ -z "$RESTART_FROM_STEP" ]]; then
    b="$(basename "$RESTART_STATE")"
    [[ "$b" =~ ^state_step_([0-9]+)\.smpcd$ ]] || { echo '[0493x24e] ERROR cannot infer RESTART_FROM_STEP from dump name' >&2; exit 2; }
    RESTART_FROM_STEP=$((10#${BASH_REMATCH[1]}))
  fi
  [[ "$RESTART_FROM_STEP" =~ ^[0-9]+$ ]] || { echo '[0493x24e] ERROR RESTART_FROM_STEP must be an integer' >&2; exit 2; }
  RUN_ROOT="${CAMPAIGN_ROOT}/restart_${RESTART_TAG}"
  # Do not re-ramp the inlet on a continuation.
  JET_RAMP_START_TIME=0.0; JET_RAMP_END_TIME=0.0; JET_RAMP_INITIAL_FACTOR=0.0; JET_RAMP_FINAL_FACTOR=0.0
  INLET_RAMP_ENABLE=false
else
  RESTART_FROM_STEP=0
  INLET_RAMP_ENABLE=true
fi
if suite_truthy_0434 "$POSTPROCESS_ONLY"; then
  [[ "$RESTART" == "0" ]] || { echo '[0493x24e] ERROR POSTPROCESS_ONLY is for the original case root, not a restart segment' >&2; exit 2; }
  echo "[0493x24e] POSTPROCESS_ONLY: simulation skipped. Run MATLAB analyzer from ./matlab:"
  echo "             $STABILITY_MATLAB"
  exit 0
fi

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
mkdir -p "$RUN_ROOT/chi"
STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
OUT="$RUN_ROOT/output"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TF="$RUN_ROOT/logs/${CASE_LABEL}.time"
ANALYSIS_DIR="$RUN_ROOT/analysis"
mkdir -p "$OUT" "$ANALYSIS_DIR"

if [[ "$RESTART" == "1" ]]; then
  cp -f "$RESTART_STATE" "$STATE"
else
  python3 "$GENERATOR" \
    --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --bath-height "$BATH_HEIGHT" --gravity-y "$GRAVITY_Y" \
    --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
    --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
    --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED"
fi

CHI_FILE="$RUN_ROOT/chi/${CASE_LABEL}_${NX}x${NY}.f32"
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
        f"[0493x24e] chi cell-count mismatch solid={solid} expected={expected} "
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
    f"[0493x24e] chi={out} solidCells={solid} "
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
openBoundarySegmentCount = 3
openBoundarySegment0 = top inlet $JET_SMIN $JET_SMAX 0.0 -$JET_SPEED $GAS_TYPE $GAS_MASS
openBoundarySegment1 = top outlet $LEFT_OUTLET_SMIN $LEFT_OUTLET_SMAX 0.0 0.0 0 $GAS_MASS
openBoundarySegment2 = top outlet $RIGHT_OUTLET_SMIN $RIGHT_OUTLET_SMAX 0.0 0.0 0 $GAS_MASS
inletVelocityRampEnable = $INLET_RAMP_ENABLE
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
speciesDiagnosticsFilename = species_runtime_0493x14at.csv
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

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_${CASE_LABEL}.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_${CASE_LABEL}.env" <<META
BENCHMARK=sato_airwater_bath_equilibration_no_directed_jet
CAMPAIGN=0493x24e_sato_airwater_bath_stabilization
TARGET_FRM_SATO=$TARGET_FRM_SATO
FRM_SATO_NOMINAL=$FRM_SATO_NOMINAL
TARGET_H_OVER_D=$TARGET_H_OVER_D
TARGET_BO_SATO=$TARGET_BO_SATO
SATO_STAGE_A_SLOPE=$SATO_STAGE_A_SLOPE
RESTART=$RESTART
RESTART_STATE=$RESTART_STATE
RESTART_FROM_STEP=$RESTART_FROM_STEP
GAS_THERMAL_FLIGHT_CELLS=$CTH
GAS_DIRECTED_JET_FLIGHT_CELLS=$CJET
GAS_THERMAL_PLUS_DIRECTED_FLIGHT_CELLS=$CCOMB
GAS_BAROMETRIC_SCALE_HEIGHT=$HBAR
GAS_TOP_TO_BATH_DENSITY_RATIO=$BARO_RATIO
GAS_INLET_TARGET_OCCUPANCY=$INLET_OCC
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
OUTLET_TOPOLOGY=wide_symmetric_no_lateral_reservoir
OUTLET_EDGE_MARGIN=$OUTLET_EDGE_MARGIN
LEFT_OUTLET_SMIN=$LEFT_OUTLET_SMIN
LEFT_OUTLET_SMAX=$LEFT_OUTLET_SMAX
RIGHT_OUTLET_SMIN=$RIGHT_OUTLET_SMIN
RIGHT_OUTLET_SMAX=$RIGHT_OUTLET_SMAX
GAS_PRESSURE_TREATMENT=measured_generating_covariate_not_qualification_target
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
LIQUID_RHO=$LIQUID_RHO
GAS_RHO_NOMINAL=$GAS_RHO
GRAVITY_ABS=$(awk -v g="$GRAVITY_Y" 'BEGIN{if(g<0)g=-g; printf "%.17g",g}')
SURFACE_TENSION_SIGMA=$SURFACE_TENSION_SIGMA
DT=$DT
STEPS=$STEPS
ANALYSIS_START_STEP=$ANALYSIS_START_STEP
ANALYSIS_END_STEP=$ANALYSIS_END_STEP
Lx=$Lx
Ly=$Ly
NX=$NX
NY=$NY
RECORD_FIELDS=$RECORD_FIELDS
RECORD_EVERY=$RECORD_EVERY
LIVE_VIS_EVERY=$LIVE_VIS_EVERY
MPCD_X14L_GAS_SPECULAR_REFLECTION=1
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=0
META

run_ok_surface_print_0493x13zi "gas pressure + Laplace tension + liquid kinetic support + gas specular reflection + gas excess normal impulse + local gas traction"
echo "===== SATO WATER/AIR BATH STABILIZATION, 2-D, ZERO DIRECTED INJECTION ====="
echo "PATHS: runner=$ROOT/scripts/run_0493x24e_sato_airwater_bath_stabilization.sh"
echo "       generator=$GENERATOR binary=$BIN"
echo "       state=$STATE params=$PARAMS output=$OUT"
echo "DOMAIN: L=${Lx}x${Ly} grid=${NX}x${NY} h=$H bathHeight=$BATH_HEIGHT gravityY=$GRAVITY_Y"
echo "PHASE: liquid(type=$LIQUID_TYPE,m=$LIQUID_MASS,kBT=$LIQUID_KBT,rhoNom=$LIQUID_RHO)"
echo "       gas(type=$GAS_TYPE,m=$GAS_MASS,kBT=$GAS_KBT,rhoNom=$GAS_RHO) baroH=$HBAR nTop/nBath=$BARO_RATIO"
echo "GAS RESERVOIR: top central segment, centerX=$JET_CENTER_X widthCells=$JET_WIDTH_CELLS width=$JET_WIDTH meanUy=-$JET_SPEED targetN=$INLET_OCC"
echo "               zero-directed-flow contract; ramp=off"
echo "NOZZLE chi-Darcy: innerX=[$NOZZLE_INNER_XMIN,$NOZZLE_INNER_XMAX] outerX=[$NOZZLE_OUTER_XMIN,$NOZZLE_OUTER_XMAX]"
echo "       wallThicknessCells=$NOZZLE_WALL_THICKNESS_CELLS lengthCells=$NOZZLE_LENGTH_CELLS exitY=$NOZZLE_EXIT_Y"
echo "       initialStandoff=$NOZZLE_STANDOFF  H0/d=$NOZZLE_STANDOFF_OVER_WIDTH"
echo "SIMILARITY: Lx/d=$(awk -v L="$Lx" -v W="$JET_WIDTH" 'BEGIN{printf "%.9g",L/W}')  Hliquid/d=$(awk -v H="$BATH_HEIGHT" -v W="$JET_WIDTH" 'BEGIN{printf "%.9g",H/W}')"
echo "DARCY: alpha=[$DARCY_ALPHA_MIN,$DARCY_ALPHA_MAX] q=$DARCY_Q lambdaSolidPerStep=$DARCY_LAMBDA mode=$DARCY_FORCING_MODE"
echo "       initialDeactivate=-1 chiCollisionVP=$DARCY_CHI_COLLISION_VP_ENABLE"
echo "ANALYSIS: offline MATLAB stationarity of etaMean, etaFar, surface range and occupancy integral"
echo "RESOLUTION: gas thermal flight=$CTH h/step; directed jet flight=$CJET h/step; sum=$CCOMB h/step"
echo "DIMENSIONLESS: zero directed Fr_m=$FRM_SATO_NOMINAL  We_g(D)=$WE_G  Bo_l(D)=$BO_W targetBo=$TARGET_BO_SATO"
echo "STABILIZATION GAS: rhoG/rhoL=$(awk -v a="$GAS_MASS" -v b="$LIQUID_MASS" 'BEGIN{printf "%.12g",a/b}') gasKBT/m=$(awk -v a="$GAS_KBT" -v b="$GAS_MASS" 'BEGIN{printf "%.12g",a/b}') dt=$DT"
echo "SATO GEOM: Lx/D=$(awk -v L="$Lx" -v W="$JET_WIDTH" 'BEGIN{printf "%.9g",L/W}') liquidDepth/D=$(awk -v H="$BATH_HEIGHT" -v W="$JET_WIDTH" 'BEGIN{printf "%.9g",H/W}') H/D=$NOZZLE_STANDOFF_OVER_WIDTH"
echo "RESTART: active=$RESTART fromStep=$RESTART_FROM_STEP state=${RESTART_STATE:-none}"
echo "BOUNDARIES: solid base faces; top = WIDE outlet | chi wall | zero-mean gas reservoir | chi wall | WIDE outlet (mode=$OUTLET_MODE)"
echo "       left outlet=[$LEFT_OUTLET_SMIN,$LEFT_OUTLET_SMAX] right outlet=[$RIGHT_OUTLET_SMIN,$RIGHT_OUTLET_SMAX]"
echo "GAS PRESSURE: measured generating covariate; NOT a pass/fail atmospheric target"
echo "PRESSURE COVARIATE: rhoL=$LIQUID_RHO gAbs=$(awk -v g="$GRAVITY_Y" 'BEGIN{if(g<0)g=-g; printf "%.17g",g}') sigma=$SURFACE_TENSION_SIGMA d=$JET_WIDTH"
echo "WALL COLLISION: accommodation=$WALL_ACCOMMODATION (0 = slip/specular-like; no virtual-wall momentum coupling)"
echo "INLET: thermalNoise=$INLET_THERMAL_NOISE; species thermostat restores gas target kBT=$GAS_KBT"
echo "COUPLING: chi-Darcy nozzle shaping + thermodynamic gas pressure + surface tension + gas specular reflection + gas excess normal impulse + local traction projection"
echo "GLOBAL RESULTANT CLOSURE: OFF (required: bath is wall/open-boundary connected)"
echo "RUN: steps=$STEPS dt=$DT tEnd=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{printf "%.9g",n*d}') summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY analysisWindow=${ANALYSIS_START_STEP}:${ANALYSIS_END_STEP}"
echo "NOTE: ./livevis_control.kv is user-owned/read-only and is not modified"
echo "================================================"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo '[0493x24e] PREFLIGHT_ONLY complete'
  exit 0
fi

echo "[0493x24e] simulation complete."
echo "[0493x24e] stationarity analysis is offline MATLAB (no physics change):"
echo "            cd matlab && matlab -batch \"$STABILITY_MATLAB\""
echo "[0493x24e] candidate campaign restart state should be selected only after the stationarity report;"
echo "            dumps are written every $DUMP_STATE_EVERY steps."

OUT_TAR="$RUN_ROOT/0493x24e_sato_airwater_bath_stabilization_compact.tar.gz"
FILES=(
  analysis
  output/recordings
  "chi/${CASE_LABEL}_${NX}x${NY}.f32"
  "chi/${CASE_LABEL}_${NX}x${NY}.f32.json"
  "output/darcy_cost_0343.csv"
  "output/species_runtime_0493x14at.csv"
  "output/cuda_phase_interface_pressure_0493x6g.csv"
  "output/cuda_phase_interface_stencil_0493x6f.csv"
  "output/cuda_species_q6_independent_masked_0493w5.csv"
  "logs/${CASE_LABEL}.log"
  "logs/${CASE_LABEL}.time"
  "logs/environment_${CASE_LABEL}.env"
  "params/${CASE_LABEL}.kv"
  "init/${CASE_LABEL}.smpcd.json"
)
PRESENT=(); for f in "${FILES[@]}"; do [[ -e "$RUN_ROOT/$f" ]] && PRESENT+=("$f"); done
tar -czf "$OUT_TAR" -C "$RUN_ROOT" "${PRESENT[@]}"
echo "[0493x24e] STABILIZATION RUN COMPLETE"
echo "[0493x24e] compact=$OUT_TAR"

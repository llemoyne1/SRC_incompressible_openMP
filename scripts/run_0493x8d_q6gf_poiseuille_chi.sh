#!/usr/bin/env bash
set -euo pipefail

# 0493x8d-b — Q6-g-f-only periodic planar Brinkman/chi Poiseuille qualification.
#
# No physical wall is present: x and y are periodic.  A binary chi=0 slab,
# 16 cells thick, is the only "wall".  Darcy uses deterministic mean mode and
# chi-collision virtual particles are OFF, so the test isolates the continuum
# Brinkman operator + Q6-g-f projection.
#
# Same calibrated 0493w1 fluid as x8d-a:
#   a=1/256, gamma=20, dt=.002, kBT=.125, m=1, rotation=90 deg.
#
# The default alpha is deliberately RESOLVED, not the historical stiff/saturated
# alpha: ell_B=sqrt(nu_ref/alpha)=4 cells.  This is a qualification of the
# Brinkman PDE before any stiff-wall limit is attempted.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="0493x8d_q6gf_poiseuille_chi"
GEN_CASE="uniform"
TOPOLOGY="periodic"
MODE="src-q6-g-f"

Lx="${Lx:-0.5}"
Ly="${Ly:-0.3125}"
NX="${NX:-128}"
NY="${NY:-80}"
WALL_CELLS="${WALL_CELLS:-16}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-30000}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
SEED="${SEED:-493202}"
U0=0.0
VELOCITY_MODE=zero
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

REFERENCE_NU="${REFERENCE_NU:-0.00059751}"
REFERENCE_CS="${REFERENCE_CS:-0.35459}"
REFERENCE_DSELF="${REFERENCE_DSELF:-0.00016588}"
REFERENCE_UCHAR="${REFERENCE_UCHAR:-0.1064}"
REFERENCE_L="${REFERENCE_L:-0.24}"

ALPHA="${ALPHA:-2.44740096}"
ALPHA_MIN=0.0
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_USOLID_X=0.0
DARCY_USOLID_Y=0.0
DARCY_BRINKMAN_FORCING_MODE=mean
DARCY_CHI_COLLISION_VP_ENABLE=false
RUN_OK_DARCY_COMMON_FILLED_STATE=1
BODY_AX="${BODY_AX:-0.006305394872053156}"

SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-1000}"
TOPO_BENCHMARK_ENABLE=false
TOPO_BENCHMARK_FORCE_ENABLE=false
TOPO_BENCHMARK_DRAG_LIFT_ENABLE=false
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-1000}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x8d_q6gf_poiseuille_qualification/chi}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_HOLD_ON_EXIT=0
FILTERED_RECORDING_ENABLE=0
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.03}"

PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_EXTERNAL_SPECIES=0
MPCD_Q6_G_F_RESIDENT_CG_0493X7J="${MPCD_Q6_G_F_RESIDENT_CG_0493X7J:-1}"
MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407="${MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407:-0}"

SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false


# Preserve the calibrated microscopic state and a resolved Brinkman layer.
python3 - "$Lx" "$Ly" "$NX" "$NY" "$WALL_CELLS" "$DT" "$KBT" "$GAMMA" \
  "$REFERENCE_NU" "$REFERENCE_CS" "$REFERENCE_UCHAR" "$REFERENCE_L" \
  "$ALPHA" "$BODY_AX" "$STEPS" <<'PY_X8D_CHI'
import math, sys
lx,ly,nx,ny,wc,dt,kbt,gamma,nu,cs,U,L,alpha,ax,steps=sys.argv[1:]
lx=float(lx); ly=float(ly); nx=int(nx); ny=int(ny); wc=int(wc)
dt=float(dt); kbt=float(kbt); gamma=int(gamma)
nu=float(nu); cs=float(cs); U=float(U); L=float(L)
alpha=float(alpha); ax=float(ax); steps=int(steps)
dx=lx/nx; dy=ly/ny
if abs(dx-dy) > 1e-12*max(dx,dy):
    raise SystemExit(f"[0493x8d-chi] ERROR non-square cells dx={dx} dy={dy}")
if abs(dx-1/256) > 1e-12:
    raise SystemExit(f"[0493x8d-chi] ERROR a={dx:.12g}; calibrated fluid requires 1/256")
if not (0 < wc < ny):
    raise SystemExit("[0493x8d-chi] ERROR WALL_CELLS must be in (0,Ny)")
S=wc*dy; H=ly-S
ell=math.sqrt(nu/alpha)
kap=1/ell
coth=lambda x: math.cosh(x)/math.sinh(x)
uI=ax/alpha + ax*H/(2*nu*kap)*coth(kap*S/2)
Uc=ax*H*H/(8*nu)+uI
Umean=ax*H*H/(12*nu)+uI
print(f"[0493x8d-chi] fluid=a256_dt002_k125 gamma={gamma} kBT={kbt} dt={dt}")
print(f"[0493x8d-chi] a={dx:.9g} fluidH={H:.9g} ({H/dy:.0f} cells) slabS={S:.9g} ({wc} cells)")
print(f"[0493x8d-chi] alpha={alpha:.12g} alpha*dt={alpha*dt:.6g} ellB/a={ell/dy:.6g}")
print(f"[0493x8d-chi] analytic-ref Uinterface={uI:.9g} Umean={Umean:.9g} Ucenter={Uc:.9g}")
print(f"[0493x8d-chi] Re_center_ref={Uc*L/nu:.5f} Ma_center_ref={Uc/cs:.5f} tEnd={steps*dt:.6g}")
PY_X8D_CHI

suite_defaults_common_0434
suite_compute_derived_0434
suite_validate_path_0434 "$MODE"

RUN_ROOT="$BASE_RUN_ROOT/$MODE"
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
CHI="$RUN_ROOT/chi/${CASE_LABEL}_chi_f32.f32"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIME="$RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"

# Full periodic state; chi is written separately so the generator does not
# interpret the slab as a particle-deactivation geometry.
suite_generate_case_0434 "$STATE" ""

python3 - "$CHI" "$NX" "$NY" "$WALL_CELLS" <<'PY_X8D_CHI_FILE'
import struct, sys
path,nx,ny,wc=sys.argv[1],int(sys.argv[2]),int(sys.argv[3]),int(sys.argv[4])
vals=[]
for j in range(ny):
    chi=0.0 if j < wc else 1.0
    vals.extend([chi]*nx)
with open(path,"wb") as f:
    f.write(struct.pack(f"<{len(vals)}f",*vals))
print(f"[0493x8d-chi] wrote binary chi={path} penalizedRows={wc}/{ny}")
PY_X8D_CHI_FILE

cat > "$PARAMS" <<PARAMS
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
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = $BODY_AX
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
wallAccommodation = 0.0
wallVpEnable = false
PARAMS
suite_write_common_params_0434 "$MODE" >> "$PARAMS"
suite_write_darcy_params_0434 "$CHI" "$MODE" >> "$PARAMS"

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"
suite_prepare_livevis_control_0434 "$RUN_ROOT" "$MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x8d.env" "$MODE"

echo "[0493x8d-chi] case=$CASE_LABEL mode=$MODE root=$RUN_ROOT"
suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME" "$OUT"

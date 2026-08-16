#!/usr/bin/env bash
set -euo pipefail

# 0493x8f — Q6-g-f Von Karman qualification candidate, Re ~= 65.
#
# Design principles:
#   * keep the viscosity-qualified microscopic fluid unchanged:
#       a=1/256, gamma=20, dt=.002, kBT=.125, m=1, rotation=pi/2,
#       random sign, grid shift, cell-relative thermostat every step;
#   * Q6-g-f production signed-density path only, resampling off;
#   * replace historical periodic-x/body-force VK by controlled left inlet /
#     passive right Neumann outlet;
#   * physical no-slip top/bottom walls as qualified by x8d Poiseuille;
#   * filled Brinkman cylinder, alpha=4000, forcing=mean, chi-VP off;
#   * preserve LIVE_VIS_ENABLE=1.
#
# Macroscopic design:
#   Uinf=.14, D=.3125=80a, Re=64.8795 using nuTG=6.743265812e-4
#   H=5D, Lx=10D, cylinder at x=3D, y=H/2.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="0493x8f_q6gf_vk_re65"
GEN_CASE="vk"
TOPOLOGY="segmented"
RUN_MODES="src-q6-g-f"

# ---------------------------------------------------------------------------
# Qualified microscopic fluid: do not change in the reference x8f run.
# ---------------------------------------------------------------------------
Lx="${Lx:-4.6875}" #3.125}"
Ly="${Ly:-1.5625}"
NX="${NX:-1200}"
NY="${NY:-400}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

REFERENCE_NU="${REFERENCE_NU:-0.00067432658123431854}"
REFERENCE_CS="${REFERENCE_CS:-0.35459}"

# ---------------------------------------------------------------------------
# VK macroscopic design.
# ---------------------------------------------------------------------------
U0="${U0:-0.14}"
UIN="${UIN:-$U0}"
VELOCITY_MODE="${VELOCITY_MODE:-uniform_x}"
SEED="${SEED:-493903}"

CYLINDER_R="${CYLINDER_R:-0.15625}"
CYLINDER_CX="${CYLINDER_CX:-0.9375}"
CYLINDER_CY="${CYLINDER_CY:-0.78125}"

# Full-height left inlet and full-height right outlet, represented by the
# already-qualified segmented IO machinery because top/bottom remain solid.
INLET_FACE="${INLET_FACE:-left}"
INLET_SMIN="${INLET_SMIN:-0.0}"
INLET_SMAX="${INLET_SMAX:-1.0}"
OUTLET_FACE="${OUTLET_FACE:-right}"
OUTLET_SMIN="${OUTLET_SMIN:-0.0}"
OUTLET_SMAX="${OUTLET_SMAX:-1.0}"
OUTLET_MODE="${OUTLET_MODE:-neumann}"
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-6}"

# Filled fictitious Brinkman cylinder; x8d/x8e-qualified interaction settings.
RUN_OK_DARCY_COMMON_FILLED_STATE=1
SKIP_SOLID_CELLS=false
SKIP_SOLID_PARTICLES=false
ALPHA="${ALPHA:-4000.0}"
ALPHA_MIN="${ALPHA_MIN:-0.0}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_INITIAL_DEACTIVATE_BELOW_CHI="${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:--1}"
DARCY_BRINKMAN_FORCING_MODE="${DARCY_BRINKMAN_FORCING_MODE:-mean}"
DARCY_CHI_COLLISION_VP_ENABLE="${DARCY_CHI_COLLISION_VP_ENABLE:-false}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-50}"
TOPO_BENCHMARK_ENABLE="${TOPO_BENCHMARK_ENABLE:-true}"
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-20}"
TOPO_BENCHMARK_FORCE_ENABLE="${TOPO_BENCHMARK_FORCE_ENABLE:-true}"
TOPO_BENCHMARK_DRAG_LIFT_ENABLE="${TOPO_BENCHMARK_DRAG_LIFT_ENABLE:-true}"

# ---------------------------------------------------------------------------
# Qualified Q6-g-f production profile.
# 1600 is only a safety cap for the larger 800x400 solve; tolerance is the
# qualified 1e-5 target.
# ---------------------------------------------------------------------------
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-2000}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
Q6_GF_SPECIES_DIAGNOSTICS_ENABLE=false
Q6_GF_EXTERNAL_SPECIES=0
Q6_GF_HAS_GAS_PHASE=0

# Explicitly keep all resampling / refill mutation paths off.
SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-1.0}"

# ---------------------------------------------------------------------------
# Run length and I/O.
# ---------------------------------------------------------------------------
STEPS="${STEPS:-20000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10000}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x8f_q6gf_vk_re65}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
THREADS="${THREADS:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

# User requirement: LiveVis is deliberately forced ON for x8f.
LIVE_VIS_ENABLE=1
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-speed}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-20}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"
LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
OVERWRITE_LIVEVIS_CONTROL="${OVERWRITE_LIVEVIS_CONTROL:-0}"

# Keep enough field history for wake / St analysis without dumping particles
# every few hundred steps.  stride=2 -> 400x200 recorded grid by default.
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_SESSION_PREFIX="${RECORD_SESSION_PREFIX:-0493x8f_q6gf_vk_re65}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-100}"
RECORD_STRIDE="${RECORD_STRIDE:-2}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-1}"

suite_defaults_common_0434
suite_compute_derived_0434

# ---------------------------------------------------------------------------
# Preflight physical contract.
# ---------------------------------------------------------------------------
python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$DT" "$KBT" "$U0" \
  "$CYLINDER_CX" "$CYLINDER_CY" "$CYLINDER_R" \
  "$REFERENCE_NU" "$REFERENCE_CS" "$ALPHA" "$STEPS" <<'PY'
import math, sys
(lx,ly,nx,ny,gamma,dt,kbt,u,xc,yc,r,nu,cs,alpha,steps)=sys.argv[1:]
lx=float(lx); ly=float(ly); nx=int(nx); ny=int(ny); gamma=float(gamma)
dt=float(dt); kbt=float(kbt); u=float(u); xc=float(xc); yc=float(yc)
r=float(r); nu=float(nu); cs=float(cs); alpha=float(alpha); steps=int(steps)
dx=lx/nx; dy=ly/ny; D=2*r
if abs(dx-dy)>1e-14:
    raise SystemExit(f"[0493x8f-preflight] ERROR non-square cells dx={dx} dy={dy}")
if abs(dx-1/256)>1e-14:
    raise SystemExit(f"[0493x8f-preflight] ERROR calibrated cell size lost: a={dx}")
if not (0 < xc-r and xc+r < lx and 0 < yc-r and yc+r < ly):
    raise SystemExit("[0493x8f-preflight] ERROR cylinder intersects external boundary")
Re=u*D/nu
Ma=u/cs
alpha_dt=alpha*dt
up=xc/D
down=(lx-xc)/D
block=D/ly
flow_time=lx/u
conv_D=D/u
st_guess=0.15
shed_period=D/(st_guess*u)
shed_steps=shed_period/dt
n_periods=steps/shed_steps
active=nx*ny*gamma
print("===== 0493x8f VK PREFLIGHT =====")
print(f"grid={nx}x{ny} L=({lx:.8g},{ly:.8g}) a={dx:.10g} gamma={gamma:g} active~{active:.0f}")
print(f"thermal dt={dt:g} kBT={kbt:g} nuTG={nu:.10g} csRef={cs:.8g}")
print(f"flow Uinf={u:.8g} D={D:.8g} D/a={D/dx:.3f} Re={Re:.5f} MaProxy={Ma:.5f}")
print(f"geometry H/D={ly/D:.3f} Lx/D={lx/D:.3f} blockage={block:.4f} upstream={up:.3f}D downstream={down:.3f}D")
print(f"Darcy alpha={alpha:.8g} alphaDt={alpha_dt:.8g} chiVP=off forcing=mean")
print(f"timing tEnd={steps*dt:.8g} flowThroughSteps={flow_time/dt:.1f} D/Usteps={conv_D/dt:.1f}")
print(f"StDesign={st_guess:g} expectedPeriod={shed_period:.6g} expectedPeriodSteps={shed_steps:.1f} runPeriods~{n_periods:.3f}")
print("livevisEnable=1 field=speed")
PY

write_params_0493x8f() {
  local mode=$1 state=$2 out=$3 chi=$4 params=$5
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
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
openBoundarySegment0 = ${INLET_FACE} inlet ${INLET_SMIN} ${INLET_SMAX} ${UIN} 0.0 0 ${PARTICLE_MASS}
openBoundarySegment1 = ${OUTLET_FACE} outlet ${OUTLET_SMIN} ${OUTLET_SMAX} ${UIN} 0.0 0 ${PARTICLE_MASS}

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.25
inletVelocityRampInitialFactor = 1.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = ${KBT}
inletThermalNoise = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = ${INLET_RESERVOIR_CELLS}
inletTargetOccupancy = ${GAMMA}
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = ${OUTLET_MODE}
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = ${PARTICLE_MASS}
wallKBT = -1.0
wallThermalNoise = 0.0
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = 0.0
wallUyTop = 0.0
PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
  suite_write_darcy_params_0434 "$chi" "$mode" >> "$params"
}

run_one_0493x8f() {
  local mode="src-q6-g-f"
  suite_validate_path_0434 "$mode"

  local run_root="$BASE_RUN_ROOT/$mode"
  suite_prepare_dirs_0434 "$run_root"
  local state="$run_root/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
  local chi="$run_root/chi/${CASE_LABEL}_circle_xc${CYLINDER_CX}_yc${CYLINDER_CY}_r${CYLINDER_R}_${NX}x${NY}.f32"
  local params="$run_root/params/${CASE_LABEL}.kv"
  local out="$run_root/output"
  local log="$run_root/logs/${CASE_LABEL}.log"
  local time="$run_root/logs/${CASE_LABEL}.time"
  mkdir -p "$out"

  suite_generate_case_for_mode_0493x7h "$mode" "$state" "$chi"
  write_params_0493x8f "$mode" "$state" "$out" "$chi" "$params"

  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
  export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0

  # Keep expensive historic debug/profiling paths off.
  export MPCD_INTERNAL_PROFILES="${MPCD_INTERNAL_PROFILES:-0}"
  export MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0

  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0493x8f.env" "$mode"
  cat >> "$run_root/logs/environment_0493x8f.env" <<META
X8F_REFERENCE_NU=${REFERENCE_NU}
X8F_REFERENCE_CS=${REFERENCE_CS}
X8F_CYLINDER_D=$(awk -v r="$CYLINDER_R" 'BEGIN{printf "%.17g",2*r}')
X8F_CYLINDER_CX=${CYLINDER_CX}
X8F_CYLINDER_CY=${CYLINDER_CY}
X8F_INLET=${INLET_FACE}:${INLET_SMIN}:${INLET_SMAX}
X8F_OUTLET=${OUTLET_FACE}:${OUTLET_SMIN}:${OUTLET_SMAX}:${OUTLET_MODE}
X8F_LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE}
X8F_RECORD_EVERY=${RECORD_EVERY}
X8F_RECORD_STRIDE=${RECORD_STRIDE}
META

  echo "[0493x8f] mode=$mode topology=$TOPOLOGY root=$run_root"
  echo "[0493x8f] inlet=$INLET_FACE[$INLET_SMIN,$INLET_SMAX] U=$UIN -> outlet=$OUTLET_FACE[$OUTLET_SMIN,$OUTLET_SMAX] mode=$OUTLET_MODE"
  echo "[0493x8f] cylinder=($CYLINDER_CX,$CYLINDER_CY,r=$CYLINDER_R) alpha=$ALPHA forcing=$DARCY_BRINKMAN_FORCING_MODE chiVP=$DARCY_CHI_COLLISION_VP_ENABLE"
  echo "[0493x8f] livevis=$LIVE_VIS_ENABLE field=$LIVE_VIS_FIELD every=$LIVE_VIS_EVERY control=$LIVE_VIS_CONTROL_FILE"
  echo "[0493x8f] recording=$RECORD_ENABLE fields=$RECORD_FIELDS every=$RECORD_EVERY stride=$RECORD_STRIDE"
  echo "[0493x8f] Q6GF tau=$Q6_GF_DENSITY_RELAXATION_TIME tol=$PROJECTION_TOLERANCE maxIt=$PROJECTION_MAX_ITERATIONS x7j=1 resampling=off"

  suite_run_binary_0434 "$params" "$log" "$time" "$out"

  if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
    echo
    echo "===== 0493x8f RUN COMPLETE ====="
    echo "root=$run_root"
    echo "log=$log"
    echo "time=$(cat "$time" 2>/dev/null || true)"
    echo "topo=$out/$TOPO_BENCHMARK_FILENAME"
    echo "darcy=$out/darcy_cost_0343.csv"
    echo "status=COMPLETE"
  fi
}

run_one_0493x8f

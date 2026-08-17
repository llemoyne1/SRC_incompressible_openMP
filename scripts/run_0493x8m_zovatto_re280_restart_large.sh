#!/usr/bin/env bash
set -euo pipefail
# 0493x8m — Zovatto & Pedrizzetti (JFM 440, 2001) centered-cylinder benchmark.
#
# Literature configuration reproduced:
#   blockage d=D/H=0.2; centered cylinder -> gamma_gap=2
#   Re_H = Umean*H/nu = 280
#   inlet: fully developed plane Poiseuille
#   outlet: passive segmented Neumann kinetic-pressure closure from 0493x8q-x8t
#   no-slip upper/lower walls
#   Zovatto paper domain: upstream=15D, downstream=40D.
#   Present 1200x400 benchmark keeps the exact H/D and Re_H physics but uses
#   a reduced axial domain: upstream=4D, downstream=11D, total=15D.
#   Production is restartable in numbered 25000-step segments.
#
# Qualified microscopic fluid is unchanged:
#   a=1/256, gamma=20, dt=.002, kBT=.125, mass=1, rotation=pi/2.
#
# IMPORTANT:
#   The case generator's generic poiseuille_x + remove_mean_drift=true shifts
#   the parabola to the wrong mean.  This runner invokes the existing generator
#   directly with --remove-mean-drift false, so U0 is genuinely Umax and
#   Umean=(2/3)Umax from the initial state onward.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="0493x8m_zovatto_re280_large"
GEN_CASE="vk"
TOPOLOGY="segmented"
RUN_MODES="${RUN_MODES:-src-q6-g-f}"

# ---------------------------------------------------------------------------
# Segmented production / restart controls.
# ---------------------------------------------------------------------------
SEGMENT_INDEX="${SEGMENT_INDEX:-0}"
RESTART_STATE="${RESTART_STATE:-}"
GLOBAL_STEP_OFFSET="${GLOBAL_STEP_OFFSET:-}"
BASE_SEED="${BASE_SEED:-493920}"
printf -v SEGMENT_TAG "%03d" "$SEGMENT_INDEX"

# ---------------------------------------------------------------------------
# Microscopic fluid: viscosity-qualified x8d/x8f state.
# ---------------------------------------------------------------------------
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
# Zovatto geometry, in the same physical scale as x8f.
# D=80a=.3125, H=5D=1.5625.
# Reduced-domain benchmark at the qualified 1200x400 resolution:
#   Lx=15D=3H, cylinder at x=4D -> upstream=4D, downstream=11D.
# The Zovatto 15D/40D domain is NOT claimed here; axial-domain sensitivity
# will be checked separately if the literature observables require it.
# ---------------------------------------------------------------------------
CYLINDER_R="${CYLINDER_R:-0.15625}"
D="${D:-0.3125}"
Ly="${Ly:-1.5625}"
CYLINDER_CY="${CYLINDER_CY:-0.78125}"
CYLINDER_CX="${CYLINDER_CX:-4.6875}"
Lx="${Lx:-17.1875}"

# Preserve a=1/256 exactly.
NX="${NX:-4400}"
NY="${NY:-400}"

# Exact target Re_H=280 based on the measured/qualified nu.
TARGET_RE_H="${TARGET_RE_H:-280.0}"
UMEAN="${UMEAN:-$(python3 - "$TARGET_RE_H" "$REFERENCE_NU" "$Ly" <<'PY'
import sys
re,nu,h=map(float,sys.argv[1:])
print(f"{re*nu/h:.17g}")
PY
)}"
UMAX="${UMAX:-$(python3 - "$UMEAN" <<'PY'
import sys
print(f"{1.5*float(sys.argv[1]):.17g}")
PY
)}"

# U0 is Umax because generator poiseuille_x is 4*U0*y/H*(1-y/H).
U0="$UMAX"
UIN="$UMAX"
UOUT_NOMINAL="$UMEAN"
VELOCITY_MODE="poiseuille_x"

INLET_FACE="left"
INLET_SMIN="0.0"
INLET_SMAX="1.0"
OUTLET_FACE="right"
OUTLET_SMIN="0.0"
OUTLET_SMAX="1.0"
INLET_PROFILE="poiseuille_y_max"
OUTLET_MODE="neumann"
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-6}"
INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-1.0}"

# Filled Brinkman cylinder, as already qualified for Q6-G-F.
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

# Q6-G-F production.
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-3500}"
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

SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-1.0}"

# ---------------------------------------------------------------------------
# Production duration and diagnostics.
#
# Production is split into restartable 25000-step segments by default.
# Dumps are written every 2000 steps AND at the final step, so each segment
# always ends with an exact restart state (state_step_00025000.smpcd by default).
# Six default segments reach 150000 global steps (~23.2 H/U).
# ---------------------------------------------------------------------------
STEPS="${STEPS:-25000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2000}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x8m_zovatto_re280_large}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
THREADS="${THREADS:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"


if [[ -z "$GLOBAL_STEP_OFFSET" ]]; then
  GLOBAL_STEP_OFFSET=$((SEGMENT_INDEX * STEPS))
fi
GLOBAL_STEP_END=$((GLOBAL_STEP_OFFSET + STEPS))
SEED="${SEED:-$((BASE_SEED + SEGMENT_INDEX))}"

GLOBAL_TIME_OFFSET="$(python3 - "$GLOBAL_STEP_OFFSET" "$DT" <<'PY'
import sys
print(f"{int(sys.argv[1]) * float(sys.argv[2]):.17g}")
PY
)"
GLOBAL_TIME_END="$(python3 - "$GLOBAL_STEP_END" "$DT" <<'PY'
import sys
print(f"{int(sys.argv[1]) * float(sys.argv[2]):.17g}")
PY
)"

# Live view: enough to follow onset without dominating runtime.
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-$BASE_RUN_ROOT/livevis_control_0493x8m.kv}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-speed}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-50}"
LIVE_VIS_NX="${LIVE_VIS_NX:-600}"
LIVE_VIS_NY="${LIVE_VIS_NY:-200}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
OVERWRITE_LIVEVIS_CONTROL="${OVERWRITE_LIVEVIS_CONTROL:-1}"

# Dense enough for St, profiles, phase averaging and mean fields.
# 600x200 gives a 2x2 spatial reduction of the 1200x400 solver grid and keeps
# approximately square physical recording cells. RECORD_EVERY=100 gives
# ~54 frames per expected literature period.
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_SESSION_PREFIX="${RECORD_SESSION_PREFIX:-0493x8m_zovatto_re280_seg${SEGMENT_TAG}}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-100}"
RECORD_STRIDE="${RECORD_STRIDE:-1}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-0}"

suite_defaults_common_0434
suite_compute_derived_0434

# ---------------------------------------------------------------------------
# Physical preflight, informational rather than restrictive.
# ---------------------------------------------------------------------------
python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$DT" "$UMAX" "$UMEAN" \
  "$CYLINDER_CX" "$CYLINDER_R" "$REFERENCE_NU" "$REFERENCE_CS" "$STEPS" <<'PY'
import sys
lx,ly,nx,ny,gamma,dt,umax,umean,xc,r,nu,cs,steps=sys.argv[1:]
lx=float(lx); ly=float(ly); nx=int(nx); ny=int(ny); gamma=float(gamma)
dt=float(dt); umax=float(umax); umean=float(umean); xc=float(xc)
r=float(r); nu=float(nu); cs=float(cs); steps=int(steps)
D=2*r
a=lx/nx
ReH=umean*ly/nu
ReDmax=umax*D/nu
Ma=umax/cs
up=xc/D
down=(lx-xc)/D
H_over_D=ly/D
Tlit=0.83
period_phys=Tlit*ly/umean
period_steps=period_phys/dt
tauH_end=(steps*dt)*umean/ly
nperiod=steps/period_steps
active=nx*ny*gamma
print("===== 0493x8m ZOVATTO Re_H=280 PREFLIGHT =====")
print(f"grid={nx}x{ny} cells={nx*ny} activeParticles~{active:.0f} a={a:.10g}")
print(f"geometry D={D:.8g} H/D={H_over_D:.3f} upstream={up:.3f}D downstream={down:.3f}D Lx/D={lx/D:.3f}")
print(f"flow Umean={umean:.12g} Umax={umax:.12g} Umax/Umean={umax/umean:.6f}")
print(f"Re_H={ReH:.8g} Re_D(Umax)={ReDmax:.8g} MaMaxProxy={Ma:.6g}")
print(f"literature centered gammaGap=2 target: Re_H=280, T*=T*Umean/H=0.83")
print(f"literature expected physical period={period_phys:.8g}, periodSteps={period_steps:.1f}")
print(f"run steps={steps} tEnd={steps*dt:.8g} tauH=t*Umean/H={tauH_end:.5f} expectedPeriods~{nperiod:.3f}")
print("BC inlet=local Poiseuille full-height; outlet=0493x8q-x8t passive kinetic-pressure Neumann")
print("initialState=Poiseuille (generator remove_mean_drift=false)")
PY

write_params_0493x8m() {
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
# x8q-x8t ignores this nominal outlet velocity as a physical final target when
# OUTLET_MODE=neumann; keep Umean only for legacy metadata/diagnostic balance.
openBoundarySegment1 = ${OUTLET_FACE} outlet ${OUTLET_SMIN} ${OUTLET_SMAX} ${UOUT_NOMINAL} 0.0 0 ${PARTICLE_MASS}

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.0
inletVelocityRampInitialFactor = 1.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = ${INLET_PROFILE}

inletKBT = ${KBT}
inletThermalNoise = ${INLET_THERMAL_NOISE}
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

# Generate the exact Poiseuille initial field for segment 0.
generate_initial_0493x8m() {
  local state=$1 chi=$2
  python3 "$GENERATOR_0434" \
    --case "$GEN_CASE" --state "$state" --chi "$chi" \
    --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" \
    --kBT "$KBT" --mass "$PARTICLE_MASS" --seed "$SEED" --u0 "$U0" \
    --velocity-mode "$VELOCITY_MODE" --background-type "$BACKGROUND_TYPE" \
    --inactive-type "$INACTIVE_TYPE" --inactive-slots "$INACTIVE_SLOTS" \
    --skip-solid-cells false --skip-solid-particles false \
    --remove-mean-drift false \
    --cylinder-cx "$CYLINDER_CX" --cylinder-cy "$CYLINDER_CY" --cylinder-r "$CYLINDER_R"
}

# A restart still needs the same Darcy chi field, but it does not need another
# 10-million-particle initial-state generation.  Create only the small f32
# circle mask if the shared chi is absent.
ensure_chi_0493x8m() {
  local chi=$1
  [[ -f "$chi" ]] && return 0
  mkdir -p "$(dirname "$chi")"
  python3 - "$chi" "$Lx" "$Ly" "$NX" "$NY" \
    "$CYLINDER_CX" "$CYLINDER_CY" "$CYLINDER_R" <<'PY'
import math
import struct
import sys

path,Lx,Ly,Nx,Ny,cx,cy,r=sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny)
cx=float(cx); cy=float(cy); r=float(r)
dx=Lx/Nx; dy=Ly/Ny; r2=r*r
with open(path, "wb") as f:
    for j in range(Ny):
        y=(j+0.5)*dy
        row=[]
        for i in range(Nx):
            x=(i+0.5)*dx
            inside=(x-cx)*(x-cx)+(y-cy)*(y-cy) <= r2
            row.append(0.0 if inside else 1.0)
        f.write(struct.pack("<%df" % Nx, *row))
print(f"[0493x8m] generated shared chi only: {path}")
PY
}

resolve_restart_0493x8m() {
  local mode=$1
  if [[ -n "$RESTART_STATE" ]]; then
    printf '%s\n' "$RESTART_STATE"
    return 0
  fi
  if (( SEGMENT_INDEX == 0 )); then
    printf '\n'
    return 0
  fi

  local prev_index=$((SEGMENT_INDEX - 1))
  local prev_tag
  printf -v prev_tag "%03d" "$prev_index"
  local prev_out="$BASE_RUN_ROOT/segment_${prev_tag}/$mode/output"
  local latest=""
  if [[ -d "$prev_out" ]]; then
    latest="$(find "$prev_out" -maxdepth 1 -type f -name 'state_step_*.smpcd' \
      -print | sort | tail -n 1)"
  fi
  if [[ -z "$latest" ]]; then
    echo "[0493x8m] ERROR no restart state found in previous segment: $prev_out" >&2
    echo "[0493x8m] set RESTART_STATE=/path/to/state_step_XXXXXXXX.smpcd to override" >&2
    return 2
  fi
  printf '%s\n' "$latest"
}

run_one_0493x8m() {
  local mode="${RUN_MODES:-src-q6-g-f}"
  suite_validate_path_0434 "$mode"

  local run_root="$BASE_RUN_ROOT/segment_${SEGMENT_TAG}/$mode"
  local restart_state
  restart_state="$(resolve_restart_0493x8m "$mode")"

  suite_prepare_dirs_0434 "$run_root"

  local generated_state="$run_root/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
  local chi="$BASE_RUN_ROOT/shared/${CASE_LABEL}_circle_xc${CYLINDER_CX}_yc${CYLINDER_CY}_r${CYLINDER_R}_${NX}x${NY}.f32"
  local params="$run_root/params/${CASE_LABEL}_seg${SEGMENT_TAG}.kv"
  local out="$run_root/output"
  local log="$run_root/logs/${CASE_LABEL}_seg${SEGMENT_TAG}.log"
  local time_file="$run_root/logs/${CASE_LABEL}_seg${SEGMENT_TAG}.time"
  mkdir -p "$out" "$BASE_RUN_ROOT/shared"

  local state=""
  if [[ -n "$restart_state" ]]; then
    if [[ ! -f "$restart_state" ]]; then
      echo "[0493x8m] ERROR restart state not found: $restart_state" >&2
      exit 2
    fi
    state="$restart_state"
    ensure_chi_0493x8m "$chi"
    echo "[0493x8m] RESTART segment=$SEGMENT_INDEX from $state"
  else
    state="$generated_state"
    echo "[0493x8m] INITIAL segment=0: generating filled Poiseuille state..."
    generate_initial_0493x8m "$state" "$chi"
  fi

  write_params_0493x8m "$mode" "$state" "$out" "$chi" "$params"

  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
  export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  export MPCD_INTERNAL_PROFILES="${MPCD_INTERNAL_PROFILES:-0}"
  export MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0

  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0493x8m.env" "$mode"
  cat >> "$run_root/logs/environment_0493x8m.env" <<META
X8M_REFERENCE=Zovatto_Pedrizzetti_JFM_440_2001
X8M_TARGET_RE_H=${TARGET_RE_H}
X8M_REFERENCE_NU=${REFERENCE_NU}
X8M_U_MEAN=${UMEAN}
X8M_U_MAX=${UMAX}
X8M_LITERATURE_T_STAR=0.83
X8M_CYLINDER_D=${D}
X8M_CYLINDER_CX=${CYLINDER_CX}
X8M_CYLINDER_CY=${CYLINDER_CY}
X8M_UPSTREAM_D=4
X8M_DOWNSTREAM_D=11
X8M_ZOVATTO_PAPER_UPSTREAM_D=15
X8M_ZOVATTO_PAPER_DOWNSTREAM_D=40
X8M_DOMAIN_STATUS=reduced_axial_domain
X8M_INLET_PROFILE=${INLET_PROFILE}
X8M_INLET_THERMAL_NOISE=${INLET_THERMAL_NOISE}
X8M_OUTLET=${OUTLET_FACE}:${OUTLET_SMIN}:${OUTLET_SMAX}:${OUTLET_MODE}:kinetic_pressure_x8t
X8M_RECORD_EVERY=${RECORD_EVERY}
X8M_RECORD_STRIDE=${RECORD_STRIDE}
X8M_SEGMENT_INDEX=${SEGMENT_INDEX}
X8M_SEGMENT_TAG=${SEGMENT_TAG}
X8M_LOCAL_STEPS=${STEPS}
X8M_GLOBAL_STEP_OFFSET=${GLOBAL_STEP_OFFSET}
X8M_GLOBAL_STEP_END=${GLOBAL_STEP_END}
X8M_GLOBAL_TIME_OFFSET=${GLOBAL_TIME_OFFSET}
X8M_GLOBAL_TIME_END=${GLOBAL_TIME_END}
X8M_RESTART_STATE=${restart_state:-INITIAL_POISEUILLE}
X8M_SEED=${SEED}
META

  echo
  echo "===== 0493x8m ZOVATTO RUN ====="
  echo "[0493x8m] mode=$mode segment=$SEGMENT_INDEX globalSteps=${GLOBAL_STEP_OFFSET}->${GLOBAL_STEP_END} root=$run_root"
  echo "[0493x8m] inputState=$state seed=$SEED"
  echo "[0493x8m] inlet Poiseuille Umax=$UMAX Umean=$UMEAN thermalNoise=$INLET_THERMAL_NOISE -> passive kinetic-pressure Neumann"
  echo "[0493x8m] geometry H/D=5 upstream=4D downstream=11D (reduced axial domain; Zovatto paper=15D/40D)"
  echo "[0493x8m] recording fields=$RECORD_FIELDS every=$RECORD_EVERY stride=$RECORD_STRIDE"
  echo "[0493x8m] forces every=$TOPO_BENCHMARK_EVERY Darcy cost every=$DARCY_COST_EVERY"
  echo "[0493x8m] restart dumps every=$DUMP_STATE_EVERY"
  echo "[0493x8m] Q6GF tol=$PROJECTION_TOLERANCE maxIt=$PROJECTION_MAX_ITERATIONS"

  suite_run_binary_0434 "$params" "$log" "$time_file" "$out"

  if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
    echo
    echo "===== 0493x8m COMPLETE ====="
    echo "root=$run_root"
    echo "segment=$SEGMENT_INDEX globalSteps=${GLOBAL_STEP_OFFSET}->${GLOBAL_STEP_END}"
    echo "finalRestart=$out/state_step_$(printf '%08d' "$STEPS").smpcd"
    echo "log=$log"
    echo "time=$(cat "$time_file" 2>/dev/null || true)"
    echo "topo=$out/$TOPO_BENCHMARK_FILENAME"
    echo "darcy=$out/darcy_cost_0343.csv"
    echo "filtered-recording session=${RECORD_SESSION_PREFIX}"
    echo "literature target: Re_H=280, T*=0.83"
    echo "status=COMPLETE"
  fi
}

run_one_0493x8m

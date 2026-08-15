#!/usr/bin/env bash
# 0493x8h generated semantically from the CURRENT local x8f runner.
# x8f remains untouched; restart support is runner-only (no C++/CUDA change).
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

CASE_LABEL="${CASE_LABEL:-0493x8h_q6gf_vk_restart}"
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

# ---------------------------------------------------------------------------
# 0493x8h restart controls.
#
# RESTART_STATE points to a state_step_*.smpcd dump. The source run's
# params_used.kv and Darcy chi are auto-discovered when possible.
#
# This is a hydrodynamic restart, not a bitwise-continuous restart: the C++
# step counter/RNG sequence restarts at local step 0. RESTART_FROM_STEP is
# recorded as metadata so post-processing can reconstruct global time.
# ---------------------------------------------------------------------------
RESTART_STATE="${RESTART_STATE:-}"
RESTART_PARAMS="${RESTART_PARAMS:-}"
RESTART_CHI="${RESTART_CHI:-}"
RESTART_FROM_STEP="${RESTART_FROM_STEP:-}"
RESTART_STRICT="${RESTART_STRICT:-1}"
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


# ---------------------------------------------------------------------------
# 0493x8h restart helpers.
# ---------------------------------------------------------------------------
x8h_truthy() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac
}

x8h_abs_path() {
  python3 - "$ROOT" "$1" <<'PYX8H'
from pathlib import Path
import sys
root = Path(sys.argv[1]).resolve()
p = Path(sys.argv[2])
print((p if p.is_absolute() else root / p).resolve())
PYX8H
}

x8h_kv_get() {
  local file=$1 key=$2
  awk -F= -v wanted="$key" '
    {
      k=$1
      gsub(/^[ \t]+|[ \t]+$/, "", k)
      if (k == wanted) {
        v=substr($0,index($0,"=")+1)
        sub(/[ \t]*#.*/, "", v)
        gsub(/^[ \t]+|[ \t]+$/, "", v)
        print v
        exit
      }
    }' "$file"
}

x8h_resolve_restart_sources() {
  [[ -n "$RESTART_STATE" ]] || return 0

  RESTART_STATE="$(x8h_abs_path "$RESTART_STATE")"
  [[ -f "$RESTART_STATE" ]] || {
    echo "[0493x8h] ERROR restart state not found: $RESTART_STATE" >&2
    exit 2
  }

  if [[ -z "$RESTART_PARAMS" ]]; then
    local candidate
    candidate="$(dirname "$RESTART_STATE")/params_used.kv"
    [[ -f "$candidate" ]] || {
      echo "[0493x8h] ERROR cannot auto-find params_used.kv beside restart dump." >&2
      echo "[0493x8h] Set RESTART_PARAMS=/path/to/params_used.kv" >&2
      exit 2
    }
    RESTART_PARAMS="$candidate"
  else
    RESTART_PARAMS="$(x8h_abs_path "$RESTART_PARAMS")"
  fi
  [[ -f "$RESTART_PARAMS" ]] || {
    echo "[0493x8h] ERROR restart params not found: $RESTART_PARAMS" >&2
    exit 2
  }

  if [[ -z "$RESTART_CHI" ]]; then
    local chi_from_params
    chi_from_params="$(x8h_kv_get "$RESTART_PARAMS" darcyChiFile)"
    [[ -n "$chi_from_params" ]] || {
      echo "[0493x8h] ERROR darcyChiFile missing in $RESTART_PARAMS" >&2
      echo "[0493x8h] Set RESTART_CHI=/path/to/chi.f32" >&2
      exit 2
    }
    RESTART_CHI="$(x8h_abs_path "$chi_from_params")"
  else
    RESTART_CHI="$(x8h_abs_path "$RESTART_CHI")"
  fi
  [[ -f "$RESTART_CHI" ]] || {
    echo "[0493x8h] ERROR restart chi not found: $RESTART_CHI" >&2
    exit 2
  }

  if [[ -z "$RESTART_FROM_STEP" ]]; then
    local base local_step source_run source_env source_origin source_active
    base="$(basename "$RESTART_STATE")"
    if [[ "$base" =~ state_step_0*([0-9]+)\.smpcd$ ]]; then
      local_step="${BASH_REMATCH[1]}"
    else
      echo "[0493x8h] ERROR cannot infer source step from: $base" >&2
      echo "[0493x8h] Set RESTART_FROM_STEP explicitly." >&2
      exit 2
    fi

    # If the source itself is an x8h continuation, recover its global origin
    # automatically, so chained restarts do not fall back to local dump steps.
    source_run="$(dirname "$(dirname "$RESTART_STATE")")"
    source_env="$source_run/logs/environment_0493x8f.env"
    if [[ -f "$source_env" ]]; then
      source_active="$(x8h_kv_get "$source_env" X8H_RESTART_ACTIVE)"
      source_origin="$(x8h_kv_get "$source_env" X8H_RESTART_FROM_STEP)"
    else
      source_active=""
      source_origin=""
    fi
    if [[ "$source_active" == 1 && "$source_origin" =~ ^[0-9]+$ ]]; then
      RESTART_FROM_STEP=$((source_origin + local_step))
      echo "[0493x8h] chained restart origin=$source_origin localDumpStep=$local_step globalSourceStep=$RESTART_FROM_STEP"
    else
      RESTART_FROM_STEP="$local_step"
    fi
  fi
  [[ "$RESTART_FROM_STEP" =~ ^[0-9]+$ ]] || {
    echo "[0493x8h] ERROR RESTART_FROM_STEP must be an integer" >&2
    exit 2
  }

  export RESTART_STATE RESTART_PARAMS RESTART_CHI RESTART_FROM_STEP
}

x8h_validate_restart_contract() {
  [[ -n "$RESTART_STATE" ]] || return 0
  x8h_truthy "$RESTART_STRICT" || return 0

  python3 - \
    "$RESTART_STATE" "$RESTART_PARAMS" "$RESTART_CHI" \
    "$Lx" "$Ly" "$NX" "$NY" "$DT" \
    "$CYLINDER_CX" "$CYLINDER_CY" "$CYLINDER_R" <<'PYX8H'
from array import array
from pathlib import Path
import math, struct, sys

(state_s, params_s, chi_s,
 lx_s, ly_s, nx_s, ny_s, dt_s,
 cx_s, cy_s, r_s) = sys.argv[1:]

state = Path(state_s)
params = Path(params_s)
chi = Path(chi_s)
lx, ly = float(lx_s), float(ly_s)
nx, ny = int(nx_s), int(ny_s)
dt = float(dt_s)
cx, cy, rr = float(cx_s), float(cy_s), float(r_s)

def parse_kv(path):
    d = {}
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.split("#",1)[0].strip()
        if not line or "=" not in line:
            continue
        k,v = line.split("=",1)
        d[k.strip()] = v.strip()
    return d

kv = parse_kv(params)

def require_float(key, expected, rtol=2e-12, atol=2e-14):
    if key not in kv:
        raise SystemExit(f"[0493x8h] ERROR restart params missing {key}")
    got = float(kv[key])
    if not math.isclose(got, expected, rel_tol=rtol, abs_tol=atol):
        raise SystemExit(
            f"[0493x8h] ERROR restart mismatch {key}: source={got:.17g} current={expected:.17g}"
        )

def require_int(key, expected):
    if key not in kv:
        raise SystemExit(f"[0493x8h] ERROR restart params missing {key}")
    got = int(float(kv[key]))
    if got != expected:
        raise SystemExit(
            f"[0493x8h] ERROR restart mismatch {key}: source={got} current={expected}"
        )

require_float("Lx", lx)
require_float("Ly", ly)
require_int("Nx", nx)
require_int("Ny", ny)
require_float("dt", dt)

# Cheap state-header validation only: do not scan a multi-GB dump.
with state.open("rb") as f:
    magic = f.read(16)
    hdr = f.read(struct.calcsize("<IIIIQIIII"))
if not magic.startswith(b"SRCMPCD_STATE"):
    raise SystemExit(f"[0493x8h] ERROR invalid .smpcd magic in {state}")
if len(hdr) != struct.calcsize("<IIIIQIIII"):
    raise SystemExit(f"[0493x8h] ERROR truncated .smpcd header in {state}")
version, endian, dim, _, n, *_ = struct.unpack("<IIIIQIIII", hdr)
if version != 2 or endian != 0x01020304 or dim != 2 or n <= 0:
    raise SystemExit(
        f"[0493x8h] ERROR incompatible .smpcd header version={version} endian={endian:#x} dim={dim} N={n}"
    )

# Strict chi/grid/geometry validation. This is only 4*Nx*Ny bytes (~MB).
expected_bytes = 4 * nx * ny
if chi.stat().st_size != expected_bytes:
    raise SystemExit(
        f"[0493x8h] ERROR chi size mismatch: got={chi.stat().st_size} expected={expected_bytes}"
    )
vals = array("f")
with chi.open("rb") as f:
    vals.fromfile(f, nx*ny)
if sys.byteorder != "little":
    vals.byteswap()

dx, dy = lx/nx, ly/ny
bad = 0
first = None
solid_cells = 0
for j in range(ny):
    y = (j + 0.5) * dy
    row = j*nx
    for i in range(nx):
        x = (i + 0.5) * dx
        expected = 0.0 if (x-cx)*(x-cx) + (y-cy)*(y-cy) <= rr*rr else 1.0
        if expected == 0.0:
            solid_cells += 1
        got = vals[row+i]
        if abs(got-expected) > 1e-6:
            bad += 1
            if first is None:
                first = (i,j,x,y,got,expected)

if bad:
    i,j,x,y,got,expected = first
    raise SystemExit(
        "[0493x8h] ERROR restart chi does not match current VK geometry: "
        f"badCells={bad}, first=({i},{j}) x={x:.8g} y={y:.8g} got={got:.8g} expected={expected:.1f}"
    )

print(
    f"[0493x8h] restart contract PASS stateN={n} "
    f"grid={nx}x{ny} L=({lx:.8g},{ly:.8g}) dt={dt:.8g} "
    f"cylinder=({cx:.8g},{cy:.8g},r={rr:.8g}) solidCells={solid_cells}"
)
PYX8H
}

x8h_prepare_state_and_chi() {
  local mode=$1 generated_state=$2 local_chi=$3
  if [[ -z "$RESTART_STATE" ]]; then
    suite_generate_case_for_mode_0493x7h "$mode" "$generated_state" "$local_chi"
    X8H_INPUT_STATE="$generated_state"
    X8H_RESTART_ACTIVE=0
    return 0
  fi

  x8h_validate_restart_contract

  # Copy only the small chi field; do not duplicate the large particle dump.
  cp -f "$RESTART_CHI" "$local_chi"
  X8H_INPUT_STATE="$RESTART_STATE"
  X8H_RESTART_ACTIVE=1

  echo "[0493x8h] restartState=$RESTART_STATE"
  echo "[0493x8h] restartParams=$RESTART_PARAMS"
  echo "[0493x8h] restartChi=$RESTART_CHI -> $local_chi"
  echo "[0493x8h] restartFromStep=$RESTART_FROM_STEP localSteps=$STEPS"
}

run_one_0493x8f() {
  local mode="src-q6-g-f"
  suite_validate_path_0434 "$mode"

  local run_root="$BASE_RUN_ROOT/$mode"
  x8h_resolve_restart_sources
  if [[ -n "$RESTART_STATE" ]] && x8h_truthy "$CLEAN_RUN_ROOT"; then
    case "$RESTART_STATE" in "$ROOT/$run_root/"*)
      echo "[0493x8h] ERROR restart dump is inside run_root that CLEAN_RUN_ROOT=1 would delete" >&2
      exit 2 ;;
    esac
  fi
  suite_prepare_dirs_0434 "$run_root"
  local state="$run_root/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
  local chi="$run_root/chi/${CASE_LABEL}_circle_xc${CYLINDER_CX}_yc${CYLINDER_CY}_r${CYLINDER_R}_${NX}x${NY}.f32"
  local params="$run_root/params/${CASE_LABEL}.kv"
  local out="$run_root/output"
  local log="$run_root/logs/${CASE_LABEL}.log"
  local time="$run_root/logs/${CASE_LABEL}.time"
  mkdir -p "$out"

  x8h_prepare_state_and_chi "$mode" "$state" "$chi"
  state="$X8H_INPUT_STATE"
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


if [[ -n "$RESTART_STATE" ]]; then
  RESTART_FROM_TIME="$(python3 - "$RESTART_FROM_STEP" "$DT" <<'PYX8H'
import sys
print(f"{int(sys.argv[1])*float(sys.argv[2]):.17g}")
PYX8H
)"
  cat >> "$run_root/logs/environment_0493x8f.env" <<META_RESTART
X8H_RESTART_ACTIVE=1
X8H_RESTART_STATE=${RESTART_STATE}
X8H_RESTART_PARAMS=${RESTART_PARAMS}
X8H_RESTART_CHI=${RESTART_CHI}
X8H_RESTART_FROM_STEP=${RESTART_FROM_STEP}
X8H_RESTART_FROM_TIME=${RESTART_FROM_TIME}
X8H_LOCAL_STEPS=${STEPS}
X8H_GLOBAL_END_STEP=$((RESTART_FROM_STEP + STEPS))
META_RESTART
  cp -f "$RESTART_PARAMS" "$run_root/logs/restart_source_params_used.kv"
else
  cat >> "$run_root/logs/environment_0493x8f.env" <<META_RESTART
X8H_RESTART_ACTIVE=0
META_RESTART
fi
  if [[ -n "$RESTART_STATE" ]]; then
    echo "[0493x8h] continuation globalSteps=${RESTART_FROM_STEP}..$((RESTART_FROM_STEP + STEPS)) (local counter restarts at 0)"
  fi
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

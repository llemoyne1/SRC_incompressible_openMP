#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

ANALYZER_N2="$ROOT/scripts/analyze_0493x13k_oscillating_drop_2d.py"
ANALYZER_N3="$ROOT/scripts/analyze_0493x13l_oscillating_drop_n3_state.py"
ANALYZER_N4="$ROOT/scripts/analyze_0493x13m_oscillating_drop_n4_state.py"
SRC14V="$ROOT/src/cuda_q6_resident_0400.cu"
for f in "$ANALYZER_N2" "$ANALYZER_N3" "$ANALYZER_N4" "$SRC14V"; do
  [[ -f "$f" ]] || { echo "[0493x14x] ERROR missing $f" >&2; exit 2; }
done
grep -q '0493x14v-gas-kinetic-excess' "$SRC14V" || {
  echo "[0493x14x] ERROR x14v source marker not found; apply x14v first" >&2
  exit 2
}

# =============================================================================
# 0493x14x -- oscillating-drop validation with explicit liquid/gas coupling.
#
# This is a runner-only extension of the existing x13k/l/m modal-drop
# validation.  It keeps the x14w liquid/gas physics chain:
#   liquid: Q6-projected incompressible phase, x10o/CIC/Q2/x10p/q/x10u/x10v,
#           x12a local thermal cooling, species thermostat at LIQUID_KBT;
#   gas:    non-projected compressible species, x14l specular response,
#           x6g accessible-volume pressure, x14v normal kinetic excess kick,
#           species thermostat at GAS_KBT.
#
# No C++/CUDA source file and no existing script is modified by this runner.
# =============================================================================

CASE_LABEL_BASE="${CASE_LABEL_BASE:-0493x14x_oscillating_drop_liquid_gas}"
CASE_LABEL="${CASE_LABEL:-$CASE_LABEL_BASE}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="closed_box"

Lx="${Lx:-1.5625}"
Ly="${Ly:-1.5625}"
NX="${NX:-400}"
NY="${NY:-400}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
SEED="${SEED:-493180}"
MODES="${MODES:-2}"

RADIUS_CELLS="${RADIUS_CELLS:-40}"
EPSILON="${EPSILON:-auto}"
PHASE="${PHASE:-0.0}"
CENTER_X="${CENTER_X:-0.78125}"
CENTER_Y="${CENTER_Y:-0.78125}"
SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2560.0}"
SIGMA_DECLARED="${SIGMA_DECLARED:-$SURFACE_TENSION_SIGMA}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
NU_REF="${NU_REF:-0.00051}"
FIT_PERIODS="${FIT_PERIODS:-2.5}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"
GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"
GAS_KBT="${GAS_KBT:-0.08}"

# x6g currently consumes global kBT in its gas EOS. Keep it aligned with gas.
KBT="${KBT:-$GAS_KBT}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$GAS_KBT}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"
PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"

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
PROJECTION_MOMENTUM_CORRECTION_ENABLE="${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-false}"

STEPS="${STEPS:-auto}"
SUMMARY_EVERY="${SUMMARY_EVERY:-auto}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-auto}"
SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"
DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}"
LIVE_VIS_NX="${LIVE_VIS_NX:-200}"
LIVE_VIS_NY="${LIVE_VIS_NY:-200}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-mass}"
RECORD_EVERY="${RECORD_EVERY:-100}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x14x_oscillating_drop_liquid_gas_${NX}x${NY}_g${GAMMA}_rc${RADIUS_CELLS}_TL${LIQUID_KBT}_TG${GAS_KBT}_s${SURFACE_TENSION_SIGMA}}"

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
RUN_OK_GENERATOR_PATH="$ROOT/scripts/run_ok_0493x14x_oscillating_drop_liquid_gas.sh"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH

suite_defaults_common_0434
suite_compute_derived_0434

generate_modal_two_phase_state() {
  local state=$1 mode=$2 eps=$3 radius=$4 h=$5
  python3 - "$state" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$CENTER_X" "$CENTER_Y" \
    "$radius" "$mode" "$eps" "$PHASE" "$LIQUID_TYPE" "$GAS_TYPE" \
    "$LIQUID_MASS" "$GAS_MASS" "$LIQUID_KBT" "$GAS_KBT" "$SEED" <<'PY'
import json, math, random, struct, sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))

def coprime_multiplier(modulus, start, avoid=-1):
    for off in range(modulus):
        c = 1 + ((start + off - 1) % modulus)
        if c != avoid and math.gcd(c, modulus) == 1:
            return c
    return 1

def paired_velocities(rng, count, mass, kbt):
    if count <= 0:
        return []
    if kbt == 0.0 or count == 1:
        return [(0.0, 0.0)] * count
    vals = []
    for _ in range(count // 2):
        gx, gy = rng.gauss(0.0, 1.0), rng.gauss(0.0, 1.0)
        vals.extend(((gx, gy), (-gx, -gy)))
    if count % 2:
        vals.append((0.0, 0.0))
    s2 = sum(x*x + y*y for x, y in vals)
    scale = math.sqrt((2.0 * count * kbt) / (mass * s2)) if s2 > 0.0 else 0.0
    return [(scale*x, scale*y) for x, y in vals]

def write_state(path, x, y, vx, vy, typ, mass, role):
    n = len(x)
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    path.parent.mkdir(parents=True, exist_ok=True)
    if sys.byteorder == "big":
        for a in (x, y, vx, vy, typ, mass):
            a.byteswap()
    try:
        with path.open("wb") as f:
            f.write(MAGIC)
            f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
            f.write(struct.pack("<8Q", *reserved))
            for a in (x, y, vx, vy, typ, mass):
                a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder == "big":
            for a in (x, y, vx, vy, typ, mass):
                a.byteswap()

out = Path(sys.argv[1])
Lx, Ly = float(sys.argv[2]), float(sys.argv[3])
nx, ny, gamma = int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
cx, cy = float(sys.argv[7]), float(sys.argv[8])
R, mode, eps, phase = float(sys.argv[9]), int(sys.argv[10]), float(sys.argv[11]), float(sys.argv[12])
lt, gt = int(sys.argv[13]), int(sys.argv[14])
lm, gm = float(sys.argv[15]), float(sys.argv[16])
lkbt, gkbt, seed = float(sys.argv[17]), float(sys.argv[18]), int(sys.argv[19])
if gamma < 2:
    raise SystemExit("[0493x14x-generate] gamma must be >=2")
if lt == gt:
    raise SystemExit("[0493x14x-generate] liquid and gas types must differ")
dx, dy = Lx / nx, Ly / ny
if abs(dx - dy) > 1e-12 * max(1.0, abs(dx), abs(dy)):
    raise SystemExit("[0493x14x-generate] square cells required")
c0 = math.sqrt(max(0.0, 1.0 - 0.5 * eps * eps))
if R * (c0 + abs(eps)) >= min(cx, Lx - cx, cy, Ly - cy):
    raise SystemExit("[0493x14x-generate] modal drop touches/overlaps a wall")
ax = coprime_multiplier(gamma, 3)
ay = coprime_multiplier(gamma, 7, avoid=ax)
rng_l = random.Random(seed ^ 0x14D11 ^ (mode << 8))
rng_g = random.Random(seed ^ 0x14D22 ^ (mode << 8))
x = array("d"); y = array("d"); vx = array("d"); vy = array("d")
typ = array("I"); mass = array("d"); role = bytearray()
liquid_particles = gas_particles = mixed_cells = liquid_cells = gas_cells = 0
for iy in range(ny):
    for ix in range(nx):
        positions = []
        types = []
        for k in range(gamma):
            fx = ((ax * k) % gamma + 0.5) / gamma
            fy = ((ay * k) % gamma + 0.5) / gamma
            px, py = (ix + fx) * dx, (iy + fy) * dy
            theta = math.atan2(py - cy, px - cx)
            rb = R * (c0 + eps * math.cos(mode * theta + phase))
            inside = math.hypot(px - cx, py - cy) <= rb
            positions.append((px, py))
            types.append(lt if inside else gt)
        nl = sum(t == lt for t in types)
        ng = gamma - nl
        if nl == gamma:
            liquid_cells += 1
        elif ng == gamma:
            gas_cells += 1
        else:
            mixed_cells += 1
        liquid_particles += nl
        gas_particles += ng
        vl = paired_velocities(rng_l, nl, lm, lkbt)
        vg = paired_velocities(rng_g, ng, gm, gkbt)
        il = ig = 0
        for (px, py), t in zip(positions, types):
            if t == lt:
                ux, uy = vl[il]; il += 1; m = lm
            else:
                ux, uy = vg[ig]; ig += 1; m = gm
            x.append(px); y.append(py); vx.append(ux); vy.append(uy)
            typ.append(t); mass.append(m); role.append(1)
write_state(out, x, y, vx, vy, typ, mass, role)
meta = {
    "profile": "modal_drop_two_temperature_liquid_gas_0493x14x",
    "Lx": Lx, "Ly": Ly, "nx": nx, "ny": ny, "dx": dx, "dy": dy,
    "gamma": gamma, "centerX": cx, "centerY": cy, "radius": R,
    "radiusCells": R / dx, "mode": mode, "epsilon": eps, "phase": phase,
    "liquidType": lt, "gasType": gt, "liquidMass": lm, "gasMass": gm,
    "liquidKBT": lkbt, "gasKBT": gkbt, "seed": seed,
    "particles": len(x), "liquidParticles": liquid_particles,
    "gasParticles": gas_particles, "liquidCells": liquid_cells,
    "gasCells": gas_cells, "mixedCells": mixed_cells,
}
out.with_suffix(out.suffix + ".json").write_text(json.dumps(meta, indent=2) + "\n")
print(f"[0493x14x-generate] mode={mode} grid={nx}x{ny} gamma={gamma} N={len(x)} R/h={R/dx:.6g} eps={eps:.6g}")
print(f"[0493x14x-generate] liquid={liquid_particles} gas={gas_particles} mixedCells={mixed_cells}")
print(f"[0493x14x-generate] state={out}")
PY
}

filter_liquid_state_dumps() {
  local source_out=$1 filtered_root=$2 liquid_type=$3
  python3 - "$source_out" "$filtered_root/output" "$liquid_type" <<'PY'
import re, shutil, struct, sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
STEP_RE = re.compile(r"state_step_(\d+)\.smpcd$")

def read_array(f, code, n):
    a = array(code)
    a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state array")
    return a

def write_state(path, x, y, vx, vy, typ, mass, role):
    n = len(x)
    path.parent.mkdir(parents=True, exist_ok=True)
    if sys.byteorder == "big":
        for a in (x, y, vx, vy, typ, mass):
            a.byteswap()
    try:
        with path.open("wb") as f:
            f.write(MAGIC)
            f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 0, 4))
            for a in (x, y, vx, vy, typ, mass):
                a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder == "big":
            for a in (x, y, vx, vy, typ, mass):
                a.byteswap()

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
lt = int(sys.argv[3])
if dst.exists():
    shutil.rmtree(dst)
dst.mkdir(parents=True, exist_ok=True)
written = 0
for p in sorted(src.glob("state_step_*.smpcd")):
    if not STEP_RE.search(p.name):
        continue
    with p.open("rb") as f:
        if f.read(16) != MAGIC:
            raise RuntimeError(f"{p}: bad state magic")
        version, endian, dim, layout, n, has_type, has_mass, reserved_count, type_bytes = struct.unpack("<IIIIQIIII", f.read(40))
        if version != 2 or endian != 0x01020304 or dim != 2 or layout != 1 or not has_type or not has_mass or type_bytes != 4:
            raise RuntimeError(f"{p}: unsupported state header")
        if reserved_count:
            f.read(8 * reserved_count)
        x0 = read_array(f, "d", n); y0 = read_array(f, "d", n)
        vx0 = read_array(f, "d", n); vy0 = read_array(f, "d", n)
        t0 = read_array(f, "I", n); m0 = read_array(f, "d", n)
        r0 = read_array(f, "B", n)
    keep = [i for i, t in enumerate(t0) if int(t) == lt and r0[i] == 1]
    x = array("d", (x0[i] for i in keep)); y = array("d", (y0[i] for i in keep))
    vx = array("d", (vx0[i] for i in keep)); vy = array("d", (vy0[i] for i in keep))
    typ = array("I", (t0[i] for i in keep)); mass = array("d", (m0[i] for i in keep))
    role = bytearray([1] * len(keep))
    write_state(dst / p.name, x, y, vx, vy, typ, mass, role)
    written += 1
print(f"[0493x14x-filter] liquid dumps={written} source={src} filteredRoot={dst.parent}")
PY
}

run_one_mode() {
  local mode=$1
  CASE_LABEL="${CASE_LABEL_BASE}_n${mode}"
  local eps="$EPSILON"
  local steps="$STEPS"
  local summary_every="$SUMMARY_EVERY"
  local dump_every="$DUMP_STATE_EVERY"
  case "$mode" in
    2)
      [[ "$eps" == auto ]] && eps=0.02
      [[ "$steps" == auto ]] && steps=600
      [[ "$summary_every" == auto ]] && summary_every=2
      [[ "$dump_every" == auto ]] && dump_every=0
      ;;
    3)
      [[ "$eps" == auto ]] && eps=0.04
      [[ "$steps" == auto ]] && steps=300
      [[ "$summary_every" == auto ]] && summary_every=5
      [[ "$dump_every" == auto ]] && dump_every=10
      ;;
    4)
      [[ "$eps" == auto ]] && eps=0.04
      [[ "$steps" == auto ]] && steps=200
      [[ "$summary_every" == auto ]] && summary_every=5
      [[ "$dump_every" == auto ]] && dump_every=5
      ;;
    *)
      echo "[0493x14x] ERROR unsupported MODE=$mode; expected 2, 3 or 4" >&2
      exit 2
      ;;
  esac

  local label="$CASE_LABEL"
  local run_root="$BASE_RUN_ROOT/n${mode}_eps${eps}_seed${SEED}"
  if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$run_root"; fi
  suite_prepare_dirs_0434 "$run_root"
  local state="$run_root/init/${label}.smpcd"
  local out="$run_root/output"
  local params="$run_root/params/${label}.kv"
  local log="$run_root/logs/${label}.log"
  local time_file="$run_root/logs/${label}.time"
  local analysis_dir="$run_root/analysis"
  mkdir -p "$out" "$analysis_dir"

  local derived
  derived="$(python3 - "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_MASS" "$GAS_MASS" \
    "$GAS_KBT" "$RADIUS_CELLS" "$mode" "$eps" "$SIGMA_DECLARED" "$NU_REF" "$DT" \
    "$ROTATION_ANGLE" "$SURFACE_TENSION_MIN_RADIUS_CELLS" "$CENTER_X" "$CENTER_Y" <<'PY'
import math, sys
lx, ly = float(sys.argv[1]), float(sys.argv[2])
nx, ny = int(sys.argv[3]), int(sys.argv[4])
gamma = float(sys.argv[5])
ml, mg, tg = float(sys.argv[6]), float(sys.argv[7]), float(sys.argv[8])
rc, mode, eps = float(sys.argv[9]), int(sys.argv[10]), float(sys.argv[11])
sigma, nu, dt = float(sys.argv[12]), float(sys.argv[13]), float(sys.argv[14])
angle, rmin = float(sys.argv[15]), float(sys.argv[16])
cx, cy = float(sys.argv[17]), float(sys.argv[18])
hx, hy = lx / nx, ly / ny
if abs(hx - hy) > 1e-12 * max(1.0, abs(hx), abs(hy)):
    raise SystemExit("[0493x14x] ERROR square cells required")
if mode not in (2, 3, 4):
    raise SystemExit("[0493x14x] ERROR mode must be 2, 3 or 4")
if not (0.0 < eps <= 0.05):
    raise SystemExit(f"[0493x14x] ERROR small-amplitude validation requires 0<epsilon<=0.05, got {eps}")
for name, value in (("sigma", sigma), ("R", rc), ("nu", nu), ("dt", dt), ("gamma", gamma), ("mL", ml), ("mG", mg)):
    if not (math.isfinite(value) and value > 0.0):
        raise SystemExit(f"[0493x14x] ERROR {name} must be finite >0")
if rmin != 4:
    raise SystemExit(f"[0493x14x] ERROR current x12 dynamic drop uses minRadiusCells=4 here, got {rmin}")
if abs(angle - 1.5707963267948966) > 1e-12:
    raise SystemExit(f"[0493x14x] ERROR x14 liquid/gas chain keeps rotationAngle=pi/2, got {angle}")
h = hx
R = rc * h
c0 = math.sqrt(max(0.0, 1.0 - 0.5 * eps * eps))
if R * (c0 + abs(eps)) >= min(cx, lx - cx, cy, ly - cy):
    raise SystemExit("[0493x14x] ERROR drop touches/overlaps a wall")
rho_l = gamma * ml / (h * h)
omega0 = math.sqrt(mode * (mode * mode - 1.0) * sigma / (rho_l * R ** 3))
period0 = 2.0 * math.pi / omega0
beta = 2.0 * mode * (mode - 1.0) * nu / (R * R)
omegad = math.sqrt(max(0.0, omega0 * omega0 - beta * beta))
periodd = 2.0 * math.pi / omegad if omegad > 0.0 else math.inf
area = h * h
p_ref = gamma * tg / area
g_ref = gamma * mg
l_ref = gamma * ml
lap = sigma / R
Rc = 25.298221281347036 * h
print(f"{h:.17g} {R:.17g} {rho_l:.17g} {omega0:.17g} {period0:.17g} {beta:.17g} {omegad:.17g} {periodd:.17g} {area:.17g} {p_ref:.17g} {l_ref:.17g} {g_ref:.17g} {lap:.17g} {R/Rc:.17g}")
PY
)"
  read -r H RADIUS RHO_L OMEGA0 PERIOD0 BETA_LAMB OMEGA_LAMB PERIOD_LAMB CELL_AREA P_REF LREF GREF LAPLACE_PRESSURE RCUT_RATIO <<<"$derived"

  generate_modal_two_phase_state "$state" "$mode" "$eps" "$RADIUS" "$H"

  cat > "$params" <<PARAMS_EOF
inputState = $state
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $steps
bcLeft = specular
bcRight = specular
bcBottom = specular
bcTop = specular
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
wallVpEnable = false
wallAccommodation = 1.0
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
speciesDiagnosticsFilename = species_runtime_0493x14x_n${mode}.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
PARAMS_EOF

  STEPS="$steps" SUMMARY_EVERY="$summary_every" DUMP_STATE_EVERY="$dump_every" \
    suite_write_common_params_0434 "$RUN_MODE" >> "$params"
  run_ok_surface_append_params_0493x13zi "$params" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
  cat >> "$params" <<'PARAMS_EOF'
phaseInterfaceKineticBilateralRelocation = true
PARAMS_EOF

  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
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
  export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
  export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
  if [[ "$mode" == 2 ]]; then
    export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=1
  else
    export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
  fi
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0

  suite_prepare_livevis_control_0434 "$run_root" "$RUN_MODE"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0493x14x_n${mode}.env" "$RUN_MODE"
  cat >> "$run_root/logs/environment_0493x14x_n${mode}.env" <<META
CASE_LABEL=$label
MODE=$mode
EPSILON=$eps
RADIUS_CELLS=$RADIUS_CELLS
RADIUS=$RADIUS
CENTER_X=$CENTER_X
CENTER_Y=$CENTER_Y
LIQUID_TYPE=$LIQUID_TYPE
GAS_TYPE=$GAS_TYPE
LIQUID_MASS=$LIQUID_MASS
GAS_MASS=$GAS_MASS
LIQUID_KBT=$LIQUID_KBT
GAS_KBT=$GAS_KBT
GLOBAL_KBT_X6G=$KBT
SURFACE_TENSION_SIGMA=$SURFACE_TENSION_SIGMA
LIQUID_VACUUM_REFERENCE_OMEGA0=$OMEGA0
LIQUID_VACUUM_REFERENCE_PERIOD0=$PERIOD0
LIQUID_VACUUM_REFERENCE_BETA_LAMB=$BETA_LAMB
LIQUID_VACUUM_REFERENCE_OMEGA_LAMB=$OMEGA_LAMB
LIQUID_VACUUM_REFERENCE_PERIOD_LAMB=$PERIOD_LAMB
GAS_THERMAL_PRESSURE=$P_REF
LAPLACE_PRESSURE=$LAPLACE_PRESSURE
MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
MPCD_X14L_GAS_SPECULAR_REFLECTION=1
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
X14X_NOTE=frequency_reference_is_liquid_vacuum_proxy_for_regression_not_a_liquid_gas_theory_claim
META

  echo
  echo "===== 0493x14x OSCILLATING DROP LIQUID/GAS n=$mode ====="
  echo "PATHS: runner=$ROOT/scripts/run_ok_0493x14x_oscillating_drop_liquid_gas.sh"
  echo "       state=$state params=$params output=$out analysis=$analysis_dir"
  echo "DROP:  grid=${NX}x${NY} h=$H gamma=$GAMMA R/h=$RADIUS_CELLS eps=$eps center=($CENTER_X,$CENTER_Y)"
  echo "PHASE: liquid(type=$LIQUID_TYPE,m=$LIQUID_MASS,kBT=$LIQUID_KBT,q6=$LIQUID_Q6_STRENGTH)"
  echo "       gas(type=$GAS_TYPE,m=$GAS_MASS,kBT=$GAS_KBT,q6=$GAS_Q6_STRENGTH)"
  echo "CHAIN: x6g accessible-volume + x14l gas specular + x14v kinetic-excess"
  echo "CAP:   sigma=$SURFACE_TENSION_SIGMA dP_Laplace=$LAPLACE_PRESSURE pGasRef=$P_REF"
  echo "REF:   liquid/vacuum proxy omega0=$OMEGA0 period0=$PERIOD0 LambBeta=$BETA_LAMB"
  echo "RUN:   steps=$steps dt=$DT summaryEvery=$summary_every dumpEvery=$dump_every preflight=$PREFLIGHT_ONLY"
  echo "==============================================="

  STEPS="$steps" SUMMARY_EVERY="$summary_every" DUMP_STATE_EVERY="$dump_every" \
    suite_run_binary_0434 "$params" "$log" "$time_file" "$out"

  if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
    echo "[0493x14x] PREFLIGHT_ONLY complete for n=$mode"
    return 0
  fi

  case "$mode" in
    2)
      local shape="$out/cuda_ellipse_shape_0493x9f.csv"
      [[ -s "$shape" ]] || { echo "[0493x14x] ERROR missing x9f shape CSV: $shape" >&2; exit 2; }
      python3 "$ANALYZER_N2" \
        --run-root "$run_root" --radius-cells "$RADIUS_CELLS" --sigma "$SIGMA_DECLARED" \
        --gamma "$GAMMA" --mass "$LIQUID_MASS" --h "$H" --nu "$NU_REF" \
        --mode "$mode" --fit-periods "$FIT_PERIODS"
      ;;
    3)
      local filtered_root="$analysis_dir/liquid_only_modal_view"
      filter_liquid_state_dumps "$out" "$filtered_root" "$LIQUID_TYPE"
      python3 "$ANALYZER_N3" \
        --run-root "$filtered_root" --radius-cells "$RADIUS_CELLS" --sigma "$SIGMA_DECLARED" \
        --gamma "$GAMMA" --mass "$LIQUID_MASS" --h "$H" --nu "$NU_REF" \
        --dt "$DT" --mode "$mode" --phase "$PHASE" --fit-periods "$FIT_PERIODS"
      ;;
    4)
      local filtered_root="$analysis_dir/liquid_only_modal_view"
      filter_liquid_state_dumps "$out" "$filtered_root" "$LIQUID_TYPE"
      python3 "$ANALYZER_N4" \
        --run-root "$filtered_root" --radius-cells "$RADIUS_CELLS" --sigma "$SIGMA_DECLARED" \
        --gamma "$GAMMA" --mass "$LIQUID_MASS" --h "$H" --nu "$NU_REF" \
        --dt "$DT" --mode "$mode" --phase "$PHASE" --fit-periods "$FIT_PERIODS"
      ;;
  esac
  echo "[0493x14x] COMPLETE n=$mode run=$run_root"
}

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$BASE_RUN_ROOT"; fi
mkdir -p "$BASE_RUN_ROOT"
for mode in $MODES; do
  run_one_mode "$mode"
done

echo
echo "[0493x14x] DONE modes=$MODES root=$BASE_RUN_ROOT"

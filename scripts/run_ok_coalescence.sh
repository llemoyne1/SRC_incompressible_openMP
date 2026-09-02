#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

# run_ok_coalescence: stand-alone liquid/vacuum two-drop collision
# demonstration.  It follows run_ok_splash.sh execution settings and embeds the
# two-drop state generator so this runner adds no script dependency.
CASE_LABEL="coalescence"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
TOPOLOGY=closed_box

# Geometry: same h=1/256, vertical extent and lateral clearance policy as the
# current splash runner.
NX="${NX:-800}"; NY="${NY:-400}"
Lx="${Lx:-3.125}"; Ly="${Ly:-1.5625}"

# Default microscopic/capillary profile follows run_ok_splash.sh.
LIQUID_TYPE="${LIQUID_TYPE:-1}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
SIGMA_ACTIVE="${SIGMA_ACTIVE:-9945.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
CONTACT_ANGLE_DEG="${CONTACT_ANGLE_DEG:-90.0}"
KINETIC_REFLECTION_FRACTION="${KINETIC_REFLECTION_FRACTION:-1.0}"
EVAPORATION_TARGET_TYPE="${EVAPORATION_TARGET_TYPE:--1}"
SURFACE_TENSION_SIGMA="$SIGMA_ACTIVE"
PHASE_INTERFACE_A_SELECTOR="type:$LIQUID_TYPE"
PHASE_INTERFACE_B_SELECTOR="vacuum"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="$KINETIC_REFLECTION_FRACTION"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="$EVAPORATION_TARGET_TYPE"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="$CONTACT_ANGLE_DEG"
X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

GAMMA="${GAMMA:-8}"
DT="${DT:-0.0063471328149122585}"
KBT="${KBT:-0.125}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
RUN_ROOT="${RUN_ROOT:-runs/run_ok_coalescence_V35_${NX}x${NY}_g${GAMMA}_s${SIGMA_ACTIVE}}"
PARTICLE_MASS="${PARTICLE_MASS:-$LIQUID_MASS}"
WALL_VP_MASS="${WALL_VP_MASS:-$LIQUID_MASS}"

# Two-drop initial condition.  The default centers are symmetric about
# PAIR_CENTER_* and separated by CENTER_OFFSET_*; velocities default to a
# head-on approach along that offset vector.  Direct DROP*_CENTER_* and
# DROP*_V* overrides take precedence.
DROP1_DIAMETER_CELLS="${DROP1_DIAMETER_CELLS:-80}"
DROP2_DIAMETER_CELLS="${DROP2_DIAMETER_CELLS:-80}"
CENTER_OFFSET_X_CELLS="${CENTER_OFFSET_X_CELLS:-320}"
CENTER_OFFSET_Y_CELLS="${CENTER_OFFSET_Y_CELLS:-60}"
CENTER_OFFSET_X="${CENTER_OFFSET_X:-}"
CENTER_OFFSET_Y="${CENTER_OFFSET_Y:-}"
PAIR_CENTER_X="${PAIR_CENTER_X:-}"
PAIR_CENTER_Y="${PAIR_CENTER_Y:-}"
APPROACH_SPEED="${APPROACH_SPEED:-0.35}"
DROP1_CENTER_X="${DROP1_CENTER_X:-}"
DROP1_CENTER_Y="${DROP1_CENTER_Y:-}"
DROP2_CENTER_X="${DROP2_CENTER_X:-}"
DROP2_CENTER_Y="${DROP2_CENTER_Y:-}"
DROP1_VX="${DROP1_VX:-0.25}"
DROP1_VY="${DROP1_VY:-0}"
DROP2_VX="${DROP2_VX:--0.25}"
DROP2_VY="${DROP2_VY:-0}"
GRAVITY_Y="${GRAVITY_Y:-0.0}"
SEED="${SEED:-493960}"

STEPS="${STEPS:-1500}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"
SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
THREADS="${THREADS:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"
LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
FILTERED_RECORD_FIELDS="${FILTERED_RECORD_FIELDS:-mass,ux,uy}"
FILTERED_RECORD_EVERY="${FILTERED_RECORD_EVERY:-100}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
FILTERED_RECORD_SAMPLE_EVERY="${FILTERED_RECORD_SAMPLE_EVERY:-100}"

THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-2000}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_EXTERNAL_SPECIES=0
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"

SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false

GEN_CASE=tg
U0=0.0
VELOCITY_MODE=zero
PARTICLE_MASS="$LIQUID_MASS"
BACKGROUND_TYPE="$LIQUID_TYPE"
INACTIVE_TYPE="$LIQUID_TYPE"
TG_HOLE_ENABLE=false

suite_defaults_common_0434
suite_compute_derived_0434

read -r H DROP1_DIAMETER DROP2_DIAMETER DROP1_RADIUS DROP2_RADIUS \
  CENTER_OFFSET_X_RESOLVED CENTER_OFFSET_Y_RESOLVED \
  DROP1_CENTER_X_DEFAULT DROP1_CENTER_Y_DEFAULT \
  DROP2_CENTER_X_DEFAULT DROP2_CENTER_Y_DEFAULT \
  DROP1_VX_DEFAULT DROP1_VY_DEFAULT DROP2_VX_DEFAULT DROP2_VY_DEFAULT <<<"$(python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$DROP1_DIAMETER_CELLS" "$DROP2_DIAMETER_CELLS" \
  "$CENTER_OFFSET_X_CELLS" "$CENTER_OFFSET_Y_CELLS" "$CENTER_OFFSET_X" "$CENTER_OFFSET_Y" \
  "$PAIR_CENTER_X" "$PAIR_CENTER_Y" "$APPROACH_SPEED" <<'PY'
import math, sys
lx, ly = float(sys.argv[1]), float(sys.argv[2])
nx, ny = int(sys.argv[3]), int(sys.argv[4])
d1c, d2c = float(sys.argv[5]), float(sys.argv[6])
oxc, oyc = float(sys.argv[7]), float(sys.argv[8])
ox_arg, oy_arg = sys.argv[9], sys.argv[10]
pcx_arg, pcy_arg = sys.argv[11], sys.argv[12]
speed = float(sys.argv[13])
dx, dy = lx / nx, ly / ny
if abs(dx - dy) > 1e-12 * max(1.0, abs(dx), abs(dy)):
    raise SystemExit('[run_ok_coalescence] ERROR square cells required')
if min(d1c, d2c) <= 0.0:
    raise SystemExit('[run_ok_coalescence] ERROR drop diameters must be positive')
if not math.isfinite(speed) or speed <= 0.0:
    raise SystemExit('[run_ok_coalescence] ERROR APPROACH_SPEED must be positive')
ox = float(ox_arg) if ox_arg else oxc * dx
oy = float(oy_arg) if oy_arg else oyc * dy
pcx = float(pcx_arg) if pcx_arg else 0.5 * lx
pcy = float(pcy_arg) if pcy_arg else 0.5 * ly
sep = math.hypot(ox, oy)
if sep <= 0.0:
    raise SystemExit('[run_ok_coalescence] ERROR center offset must be non-zero')
d1, d2 = d1c * dx, d2c * dx
r1, r2 = 0.5 * d1, 0.5 * d2
ux, uy = ox / sep, oy / sep
c1x, c1y = pcx - 0.5 * ox, pcy - 0.5 * oy
c2x, c2y = pcx + 0.5 * ox, pcy + 0.5 * oy
v1x, v1y = speed * ux, speed * uy
v2x, v2y = -speed * ux, -speed * uy
print(' '.join(f'{v:.17g}' for v in (
    dx, d1, d2, r1, r2, ox, oy, c1x, c1y, c2x, c2y, v1x, v1y, v2x, v2y
)))
PY
)"

DROP1_CENTER_X="${DROP1_CENTER_X:-$DROP1_CENTER_X_DEFAULT}"
DROP1_CENTER_Y="${DROP1_CENTER_Y:-$DROP1_CENTER_Y_DEFAULT}"
DROP2_CENTER_X="${DROP2_CENTER_X:-$DROP2_CENTER_X_DEFAULT}"
DROP2_CENTER_Y="${DROP2_CENTER_Y:-$DROP2_CENTER_Y_DEFAULT}"
DROP1_VX="${DROP1_VX:-$DROP1_VX_DEFAULT}"
DROP1_VY="${DROP1_VY:-$DROP1_VY_DEFAULT}"
DROP2_VX="${DROP2_VX:-$DROP2_VX_DEFAULT}"
DROP2_VY="${DROP2_VY:-$DROP2_VY_DEFAULT}"

python3 - "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_MASS" "$DT" "$KBT" \
  "$DROP1_RADIUS" "$DROP2_RADIUS" "$DROP1_CENTER_X" "$DROP1_CENTER_Y" \
  "$DROP2_CENTER_X" "$DROP2_CENTER_Y" "$DROP1_VX" "$DROP1_VY" \
  "$DROP2_VX" "$DROP2_VY" "$GRAVITY_Y" "$SIGMA_ACTIVE" \
  "$SURFACE_TENSION_MIN_RADIUS_CELLS" "$STEPS" <<'PY'
import math, sys
(lx, ly, nx, ny, gamma, mass, dt, kbt, r1, r2, c1x, c1y, c2x, c2y,
 v1x, v1y, v2x, v2y, gy, sigma, rmin, steps) = sys.argv[1:]
lx=float(lx); ly=float(ly); nx=int(nx); ny=int(ny); gamma=float(gamma); mass=float(mass)
dt=float(dt); kbt=float(kbt); r1=float(r1); r2=float(r2)
c1x=float(c1x); c1y=float(c1y); c2x=float(c2x); c2y=float(c2y)
v1x=float(v1x); v1y=float(v1y); v2x=float(v2x); v2y=float(v2y)
gy=float(gy); sigma=float(sigma); rmin=float(rmin); steps=int(steps)
h = lx / nx
if min(gamma, mass, dt, r1, r2, rmin) <= 0.0 or sigma < 0.0:
    raise SystemExit('[run_ok_coalescence] ERROR gamma,mass,dt,R,minRadiusCells must be positive and sigma must be non-negative')
for label, cx, cy, r in (('drop1', c1x, c1y, r1), ('drop2', c2x, c2y, r2)):
    if not (0.0 < cx - r and cx + r < lx and 0.0 < cy - r and cy + r < ly):
        raise SystemExit(f'[run_ok_coalescence] ERROR {label} intersects an external wall')
dx12, dy12 = c2x - c1x, c2y - c1y
sep = math.hypot(dx12, dy12)
if sep <= r1 + r2:
    raise SystemExit('[run_ok_coalescence] ERROR initial drops overlap or touch')
ux, uy = dx12 / sep, dy12 / sep
approach = (v1x - v2x) * ux + (v1y - v2y) * uy
if approach <= 0.0:
    raise SystemExit('[run_ok_coalescence] ERROR relative velocity is not approaching along the center offset')
gap = sep - r1 - r2
rho = gamma * mass / (h * h)
dmean = r1 + r2
we_rel = (rho * approach * approach * dmean / sigma) if sigma > 0.0 else math.nan
tc = gap / approach
kmax = 1.0 / (rmin * h)
print('===== run_ok_coalescence PREFLIGHT =====')
print(f'grid={nx}x{ny} L=({lx:.8g},{ly:.8g}) h={h:.10g} gamma={gamma:g}')
print(f'fluid dt={dt:g} kBT={kbt:g} particleMass={mass:g} transportCalibration=NOT_REUSED')
print(f'drop1 D={2*r1:.8g} D/h={2*r1/h:.3f} center=({c1x:.8g},{c1y:.8g}) v=({v1x:.6g},{v1y:.6g})')
print(f'drop2 D={2*r2:.8g} D/h={2*r2/h:.3f} center=({c2x:.8g},{c2y:.8g}) v=({v2x:.6g},{v2y:.6g})')
print(f'centerOffset=({dx12:.8g},{dy12:.8g}) separation={sep:.8g} gap={gap:.8g} approachSpeed={approach:.8g} contactTimeProxy={tc:.8g}')
print(f'gravityY={gy:.8g} capillary sigma={sigma:.8g} minRadiusCells={rmin:g} kappaLimit={kmax:.8g}')
print(f'nondimProxy WeRelative={we_rel:.6g}')
print(f'timing steps={steps} tEnd={steps*dt:.8g} dumpsEvery=configured-in-runner')
PY

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
OUT="$RUN_ROOT/output"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"

RUN_OK_GENERATOR_PATH="$ROOT/scripts/run_ok_coalescence.sh:inline-two-drop-state"
export RUN_OK_GENERATOR_PATH
python3 - "$STATE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" \
  "$DROP1_CENTER_X" "$DROP1_CENTER_Y" "$DROP1_RADIUS" "$DROP1_VX" "$DROP1_VY" \
  "$DROP2_CENTER_X" "$DROP2_CENTER_Y" "$DROP2_RADIUS" "$DROP2_VX" "$DROP2_VY" \
  "$LIQUID_TYPE" "$LIQUID_MASS" "$KBT" "$SEED" <<'PY'
from __future__ import annotations

import json
import math
import random
import struct
import sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def coprime_multiplier(modulus: int, start: int, avoid: int = -1) -> int:
    for off in range(modulus):
        c = 1 + ((start + off - 1) % modulus)
        if c != avoid and math.gcd(c, modulus) == 1:
            return c
    return 1


def paired_fluctuations(rng: random.Random, count: int, mass: float, kbt: float):
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
    s2 = sum(a * a + b * b for a, b in vals)
    scale = math.sqrt((2.0 * count * kbt) / (mass * s2)) if s2 > 0.0 else 0.0
    return [(scale * a, scale * b) for a, b in vals]


def write_state(path: Path, x, y, vx, vy, typ, mass, role: bytearray) -> None:
    n = len(x)
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    path.parent.mkdir(parents=True, exist_ok=True)
    arrays = (x, y, vx, vy, typ, mass)
    if sys.byteorder == "big":
        for a in arrays:
            a.byteswap()
    try:
        with path.open("wb") as f:
            f.write(MAGIC)
            f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
            f.write(struct.pack("<8Q", *reserved))
            for a in arrays:
                a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder == "big":
            for a in arrays:
                a.byteswap()


def main() -> int:
    (state, lx, ly, nx, ny, gamma, c1x, c1y, r1, v1x, v1y,
     c2x, c2y, r2, v2x, v2y, liquid_type, liquid_mass, kbt, seed) = sys.argv[1:]
    state = Path(state)
    lx, ly = float(lx), float(ly)
    nx, ny, gamma = int(nx), int(ny), int(gamma)
    c1x, c1y, r1 = float(c1x), float(c1y), float(r1)
    v1x, v1y = float(v1x), float(v1y)
    c2x, c2y, r2 = float(c2x), float(c2y), float(r2)
    v2x, v2y = float(v2x), float(v2y)
    liquid_type, liquid_mass, kbt, seed = int(liquid_type), float(liquid_mass), float(kbt), int(seed)
    if gamma < 2:
        raise SystemExit("[run_ok_coalescence-generate] ERROR gamma must be >=2")
    dx, dy = lx / nx, ly / ny
    if abs(dx - dy) > 1e-12 * max(1.0, abs(dx), abs(dy)):
        raise SystemExit("[run_ok_coalescence-generate] ERROR square cells required")
    if math.hypot(c2x - c1x, c2y - c1y) <= r1 + r2:
        raise SystemExit("[run_ok_coalescence-generate] ERROR initial drops overlap or touch")

    ax = coprime_multiplier(gamma, 3)
    ay = coprime_multiplier(gamma, 7, avoid=ax)
    rng = random.Random(seed)
    drops = (
        ("drop1", c1x, c1y, r1, v1x, v1y),
        ("drop2", c2x, c2y, r2, v2x, v2y),
    )
    cells = set()
    for _, cx, cy, r, _, _ in drops:
        ix0 = max(0, int(math.floor((cx - r) / dx)) - 1)
        ix1 = min(nx - 1, int(math.floor((cx + r) / dx)) + 1)
        iy0 = max(0, int(math.floor((cy - r) / dy)) - 1)
        iy1 = min(ny - 1, int(math.floor((cy + r) / dy)) + 1)
        for iy in range(iy0, iy1 + 1):
            for ix in range(ix0, ix1 + 1):
                cells.add((iy, ix))

    x = array("d")
    y = array("d")
    vx = array("d")
    vy = array("d")
    typ = array("I")
    mass = array("d")
    role = bytearray()
    counts = {"drop1": 0, "drop2": 0}
    occupied_cells = 0
    partial_fill_cells = 0

    for iy, ix in sorted(cells):
        particles = []
        for k in range(gamma):
            fx = ((ax * k) % gamma + 0.5) / gamma
            fy = ((ay * k) % gamma + 0.5) / gamma
            px, py = (ix + fx) * dx, (iy + fy) * dy
            hits = []
            for label, cx, cy, r, ux, uy in drops:
                if (px - cx) ** 2 + (py - cy) ** 2 <= r * r:
                    hits.append((label, ux, uy))
            if len(hits) > 1:
                raise SystemExit("[run_ok_coalescence-generate] ERROR sampled particle is inside both drops")
            if hits:
                label, ux, uy = hits[0]
                particles.append((px, py, label, ux, uy))
        if not particles:
            continue
        occupied_cells += 1
        if len(particles) != gamma:
            partial_fill_cells += 1
        fluc = paired_fluctuations(rng, len(particles), liquid_mass, kbt)
        for (px, py, label, ux, uy), (du, dv) in zip(particles, fluc):
            x.append(px); y.append(py)
            vx.append(ux + du); vy.append(uy + dv)
            typ.append(liquid_type); mass.append(liquid_mass); role.append(1)
            counts[label] += 1

    if counts["drop1"] == 0 or counts["drop2"] == 0:
        raise SystemExit("[run_ok_coalescence-generate] ERROR a drop contains no particles")

    write_state(state, x, y, vx, vy, typ, mass, role)
    meta = {
        "profile": "liquid_vacuum_coalescence_run_ok",
        "Lx": lx, "Ly": ly, "nx": nx, "ny": ny, "dx": dx, "dy": dy, "gamma": gamma,
        "drop1CenterX": c1x, "drop1CenterY": c1y, "drop1Radius": r1,
        "drop1DiameterCells": 2.0 * r1 / dx, "drop1Vx": v1x, "drop1Vy": v1y,
        "drop2CenterX": c2x, "drop2CenterY": c2y, "drop2Radius": r2,
        "drop2DiameterCells": 2.0 * r2 / dx, "drop2Vx": v2x, "drop2Vy": v2y,
        "centerOffsetX": c2x - c1x, "centerOffsetY": c2y - c1y,
        "liquidType": liquid_type, "liquidMass": liquid_mass, "kBT": kbt, "seed": seed,
        "particles": len(x), "drop1Particles": counts["drop1"], "drop2Particles": counts["drop2"],
        "occupiedCells": occupied_cells, "partialFillCells": partial_fill_cells,
    }
    meta_path = state.with_suffix(state.suffix + ".json")
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")
    print(
        f"[run_ok_coalescence-generate] grid={nx}x{ny} h={dx:.10g} gamma={gamma} "
        f"N={len(x)} drop1={counts['drop1']} drop2={counts['drop2']}"
    )
    print(
        f"[run_ok_coalescence-generate] drop1 D/h={2*r1/dx:.6g} center=({c1x:.8g},{c1y:.8g}) "
        f"v=({v1x:.8g},{v1y:.8g})"
    )
    print(
        f"[run_ok_coalescence-generate] drop2 D/h={2*r2/dx:.6g} center=({c2x:.8g},{c2y:.8g}) "
        f"v=({v2x:.8g},{v2y:.8g})"
    )
    print(f"[run_ok_coalescence-generate] state={state} metadata={meta_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
sha256sum "$STATE" | sed 's/^/[run_ok_coalescence-init] sha256=/'

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
X9T_SPECIES_COUNT=1
X9T_VAPOR_SPECIES_LINE=""
X9T_VAPOR_RESAMPLING_LINE=""
if [[ "$EVAPORATION_TARGET_TYPE" =~ ^[0-9]+$ ]]; then
  if [[ "$EVAPORATION_TARGET_TYPE" == "$LIQUID_TYPE" ]]; then
    echo "[run_ok_coalescence] ERROR evaporation target must differ from liquid type" >&2; exit 2
  fi
  X9T_SPECIES_COUNT=2
  X9T_VAPOR_SPECIES_LINE="species1 = $EVAPORATION_TARGET_TYPE kinetic_vapor gas 0.0 1.0 $LIQUID_REFERENCE_CELL_MASS"
  X9T_VAPOR_RESAMPLING_LINE="species1ResamplingEnable = false"
elif [[ "$EVAPORATION_TARGET_TYPE" != "-1" ]]; then
  echo "[run_ok_coalescence] ERROR EVAPORATION_TARGET_TYPE must be -1 or a non-negative integer" >&2; exit 2
fi

cat > "$PARAMS" <<PARAMS_EOF
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
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $SIGMA_ACTIVE
surfaceTensionMinRadiusCells = $SURFACE_TENSION_MIN_RADIUS_CELLS
phaseInterfaceKineticReflectionFraction = $KINETIC_REFLECTION_FRACTION
phaseInterfaceEvaporationTargetType = $EVAPORATION_TARGET_TYPE
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = vacuum
phaseInterfaceContactAngleDegrees = $CONTACT_ANGLE_DEG
speciesRegistryEnable = true
speciesCount = $X9T_SPECIES_COUNT
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
$X9T_VAPOR_SPECIES_LINE
$X9T_VAPOR_RESAMPLING_LINE
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_coalescence.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_FILL_FRACTION
PARAMS_EOF
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
run_ok_surface_export_qualified_liquid_vacuum_flags_0493x13zi "$LIQUID_MASS"
run_ok_surface_print_0493x13zi "qualified-liquid-vacuum"
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=1
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
export SRC_FILTERED_FIELD_RECORD_FIELDS="$FILTERED_RECORD_FIELDS"
export MPCD_FILTERED_FIELD_RECORD_FIELDS="$FILTERED_RECORD_FIELDS"
export SRC_FILTERED_FIELD_RECORD_EVERY="$FILTERED_RECORD_EVERY"
export MPCD_FILTERED_FIELD_RECORD_EVERY="$FILTERED_RECORD_EVERY"
export SRC_FILTERED_FIELD_SAMPLE_EVERY="$FILTERED_RECORD_SAMPLE_EVERY"
export MPCD_FILTERED_FIELD_SAMPLE_EVERY="$FILTERED_RECORD_SAMPLE_EVERY"

BASE_RUN_ROOT="$RUN_ROOT"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_coalescence.env" "$RUN_MODE"

printf '%s\n' \
  "[run_ok_coalescence] sigma=$SIGMA_ACTIVE minRadiusCells=$SURFACE_TENSION_MIN_RADIUS_CELLS contactAngle=$CONTACT_ANGLE_DEG" \
  "[run_ok_coalescence] kineticReflectionFraction=$KINETIC_REFLECTION_FRACTION evaporationTargetType=$EVAPORATION_TARGET_TYPE" \
  "[run_ok_coalescence] drop1 D/h=$DROP1_DIAMETER_CELLS center=($DROP1_CENTER_X,$DROP1_CENTER_Y) v=($DROP1_VX,$DROP1_VY)" \
  "[run_ok_coalescence] drop2 D/h=$DROP2_DIAMETER_CELLS center=($DROP2_CENTER_X,$DROP2_CENTER_Y) v=($DROP2_VX,$DROP2_VY)" \
  "[run_ok_coalescence] centerOffset=($CENTER_OFFSET_X_RESOLVED,$CENTER_OFFSET_Y_RESOLVED) gravityY=$GRAVITY_Y dumpsEvery=$DUMP_STATE_EVERY steps=$STEPS dt=$DT" \
  "[run_ok_coalescence] objective=qualitative binary-drop collision/coalescence in liquid/vacuum settings"

if suite_truthy_0434 "${MPCD_X11C_FORCE_X9E_SIGMA0:-0}"; then
  export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
  echo "[run_ok_coalescence] forcing x9e solved-pressure diagnostics for sigma=0 paired baseline"
fi
suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

echo "[run_ok_coalescence] completed output=$OUT"
echo "[run_ok_coalescence] state dumps requested every $DUMP_STATE_EVERY steps"

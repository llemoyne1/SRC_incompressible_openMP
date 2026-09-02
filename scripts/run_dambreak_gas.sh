#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

# run_dambreak_gas: gas-filled variant of run_ok_dambreak.sh.
# The liquid column geometry follows run_ok_dambreak.sh, but cells outside the
# column are initialized as a uniform gas rather than left empty.  The per-type
# thermostat keeps liquid and gas at independent kinetic temperatures.
RUN_OK_ENTRYPOINT="$ROOT/scripts/run_dambreak_gas.sh"
CASE_LABEL="${CASE_LABEL:-dambreak_gas}"
TOPOLOGY="closed_box"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"
if [[ "$RUN_MODE" != "src-q6-g-f" ]]; then
  echo "[run_dambreak_gas] ERROR this gas/free-surface profile requires RUN_MODE=src-q6-g-f" >&2
  exit 2
fi

Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"; NX="${NX:-512}"; NY="${NY:-256}"
GAMMA="${GAMMA:-8}"
STEPS="${STEPS:-5000}"
DT="${DT:-0.0063471328149122585}"
SEED="${SEED:-493963}"

LIQUID_COLUMN_WIDTH="${LIQUID_COLUMN_WIDTH:-0.5}"
LIQUID_COLUMN_HEIGHT="${LIQUID_COLUMN_HEIGHT:-0.8}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"
GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
GAS_MASS="${GAS_MASS:-0.01}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"
GAS_KBT="${GAS_KBT:-0.99}"

# x6g currently consumes the global kBT as its gas EOS reference, so keep it
# aligned with the gas thermostat target.  The liquid target is supplied through
# species0ThermostatTargetKBT below.
KBT="${KBT:-$GAS_KBT}"
PARTICLE_MASS="$GAS_MASS"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"

ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$GAS_KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2940.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_A_SELECTOR="type:$LIQUID_TYPE"
PHASE_INTERFACE_B_SELECTOR="type:$GAS_TYPE"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-0.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
GRAVITY_Y="${GRAVITY_Y:--0.5}"

LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_OCCUPANCY_FRACTION="${SPECIES_Q6_MIN_OCCUPANCY_FRACTION:-0.5}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=1
Q6_GF_SPECIES_DIAGNOSTICS_ENABLE=false

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1600}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"

BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/run_dambreak_gas_${NX}x${NY}_g${GAMMA}_TL${LIQUID_KBT}_TG${GAS_KBT}}"
RUN_ROOT="${RUN_ROOT:-$BASE_RUN_ROOT}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.0}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-0}"
SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"
SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
THREADS="${THREADS:-8}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"
LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
MASS_RECONDITION_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
VIRIAL_DENSITY_KICK_ENABLE=false

BACKGROUND_TYPE="$GAS_TYPE"
INACTIVE_TYPE="$GAS_TYPE"
GEN_CASE="tg"
U0=0.0
VELOCITY_MODE="zero"
TG_HOLE_ENABLE=false

RUN_OK_GENERATOR_PATH="$ROOT/scripts/run_dambreak_gas.sh:inline-liquid-gas-dambreak-state"
export RUN_OK_ENTRYPOINT RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH

suite_defaults_common_0434
suite_compute_derived_0434

python3 - "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_COLUMN_WIDTH" "$LIQUID_COLUMN_HEIGHT" \
  "$LIQUID_TYPE" "$GAS_TYPE" "$LIQUID_MASS" "$GAS_MASS" "$LIQUID_KBT" "$GAS_KBT" "$DT" \
  "$SURFACE_TENSION_SIGMA" "$SURFACE_TENSION_MIN_RADIUS_CELLS" <<'PY_VALIDATE'
import math, sys
(lx, ly, nx, ny, gamma, width, height, lt, gt, ml, mg, tl, tg, dt, sigma, rmin) = sys.argv[1:]
lx=float(lx); ly=float(ly); nx=int(nx); ny=int(ny); gamma=int(gamma)
width=float(width); height=float(height); lt=int(lt); gt=int(gt)
ml=float(ml); mg=float(mg); tl=float(tl); tg=float(tg); dt=float(dt)
sigma=float(sigma); rmin=float(rmin)
if nx <= 0 or ny <= 0 or gamma < 2:
    raise SystemExit("[run_dambreak_gas] grid dimensions must be positive and GAMMA >= 2")
if not (0.0 < width < lx and 0.0 < height < ly):
    raise SystemExit("[run_dambreak_gas] liquid column must lie strictly inside the box")
if lt == gt:
    raise SystemExit("[run_dambreak_gas] liquid and gas particle types must differ")
for name, value in (("LIQUID_MASS", ml), ("GAS_MASS", mg), ("LIQUID_KBT", tl), ("GAS_KBT", tg), ("DT", dt)):
    if not (math.isfinite(value) and value > 0.0):
        raise SystemExit(f"[run_dambreak_gas] {name} must be finite and >0")
if not (math.isfinite(sigma) and sigma >= 0.0):
    raise SystemExit("[run_dambreak_gas] SURFACE_TENSION_SIGMA must be finite and >=0")
if not (math.isfinite(rmin) and rmin >= 0.0):
    raise SystemExit("[run_dambreak_gas] SURFACE_TENSION_MIN_RADIUS_CELLS must be finite and >=0")
PY_VALIDATE

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"

python3 - "$STATE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_COLUMN_WIDTH" "$LIQUID_COLUMN_HEIGHT" \
  "$LIQUID_TYPE" "$GAS_TYPE" "$LIQUID_MASS" "$GAS_MASS" "$LIQUID_KBT" "$GAS_KBT" "$SEED" <<'PY_STATE'
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
    for offset in range(modulus):
        candidate = 1 + ((start + offset - 1) % modulus)
        if candidate != avoid and math.gcd(candidate, modulus) == 1:
            return candidate
    return 1


def paired_thermal_velocities(rng: random.Random, count: int, mass: float, kbt: float):
    values = []
    for _ in range(count // 2):
        gx, gy = rng.gauss(0.0, 1.0), rng.gauss(0.0, 1.0)
        values.append((gx, gy))
        values.append((-gx, -gy))
    if count % 2:
        values.append((0.0, 0.0))
    s2 = sum(vx * vx + vy * vy for vx, vy in values)
    if not s2 > 0.0:
        values[0] = (1.0, 0.0)
        if count > 1:
            values[1] = (-1.0, 0.0)
        s2 = sum(vx * vx + vy * vy for vx, vy in values)
    scale = math.sqrt((2.0 * count * kbt) / (mass * s2))
    return [(scale * vx, scale * vy) for vx, vy in values]


def write_state(path: Path, x, y, vx, vy, typ, mass, role: bytearray) -> None:
    n = len(x)
    if not (len(y) == len(vx) == len(vy) == len(typ) == len(mass) == len(role) == n):
        raise RuntimeError("state arrays have inconsistent lengths")
    path.parent.mkdir(parents=True, exist_ok=True)
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    arrays = (x, y, vx, vy, typ, mass)
    if sys.byteorder == "big":
        for values in arrays:
            values.byteswap()
    try:
        with path.open("wb") as stream:
            stream.write(MAGIC)
            stream.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
            stream.write(struct.pack("<8Q", *reserved))
            for values in arrays:
                values.tofile(stream)
            stream.write(role)
    finally:
        if sys.byteorder == "big":
            for values in arrays:
                values.byteswap()


def main() -> int:
    (state, lx, ly, nx, ny, gamma, width, height, lt, gt, ml, mg, tl, tg, seed) = sys.argv[1:]
    state = Path(state)
    lx, ly = float(lx), float(ly)
    nx, ny, gamma = int(nx), int(ny), int(gamma)
    width, height = float(width), float(height)
    lt, gt = int(lt), int(gt)
    ml, mg = float(ml), float(mg)
    tl, tg = float(tl), float(tg)
    seed = int(seed)
    dx, dy = lx / nx, ly / ny

    ax = coprime_multiplier(gamma, 3)
    ay = coprime_multiplier(gamma, 7, avoid=ax)
    rng = random.Random(seed)

    x = array("d")
    y = array("d")
    vx = array("d")
    vy = array("d")
    typ = array("I")
    mass = array("d")
    role = bytearray()
    liquid_cells = gas_cells = liquid_particles = gas_particles = 0
    total_px = total_py = 0.0

    for iy in range(ny):
        yc = (iy + 0.5) * dy
        for ix in range(nx):
            xc = (ix + 0.5) * dx
            is_liquid = xc < width and yc < height
            particle_type = lt if is_liquid else gt
            particle_mass = ml if is_liquid else mg
            particle_kbt = tl if is_liquid else tg
            thermal = paired_thermal_velocities(rng, gamma, particle_mass, particle_kbt)
            if is_liquid:
                liquid_cells += 1
                liquid_particles += gamma
            else:
                gas_cells += 1
                gas_particles += gamma
            for k, (ux, uy) in enumerate(thermal):
                fx = ((ax * k) % gamma + 0.5) / gamma
                fy = ((ay * k) % gamma + 0.5) / gamma
                x.append((ix + fx) * dx)
                y.append((iy + fy) * dy)
                vx.append(ux)
                vy.append(uy)
                typ.append(particle_type)
                mass.append(particle_mass)
                role.append(1)
                total_px += particle_mass * ux
                total_py += particle_mass * uy

    expected = nx * ny * gamma
    if len(x) != expected:
        raise RuntimeError(f"generated {len(x)} particles, expected {expected}")
    write_state(state, x, y, vx, vy, typ, mass, role)
    meta = {
        "profile": "dambreak_gas_two_temperature",
        "Lx": lx, "Ly": ly, "nx": nx, "ny": ny, "gamma": gamma,
        "column_width": width, "column_height": height,
        "liquid_type": lt, "gas_type": gt,
        "liquid_mass": ml, "gas_mass": mg,
        "liquid_kBT": tl, "gas_kBT": tg,
        "liquid_cells": liquid_cells, "gas_cells": gas_cells, "empty_cells": 0,
        "liquid_particles": liquid_particles, "gas_particles": gas_particles,
        "fluid_particles": expected,
        "total_mass": liquid_particles * ml + gas_particles * mg,
        "total_momentum_x": total_px,
        "total_momentum_y": total_py,
        "position_multiplier_x": ax,
        "position_multiplier_y": ay,
        "seed": seed,
    }
    meta_path = state.with_suffix(state.suffix + ".json")
    meta_path.write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n")
    print(
        f"[run_dambreak_gas-state] state={state} grid={nx}x{ny} gamma={gamma} "
        f"fluid={expected} liquid={liquid_particles} gas={gas_particles} emptyCells=0"
    )
    print(
        f"[run_dambreak_gas-state] kBT(liquid/gas)=({tl:.8g},{tg:.8g}) "
        f"mass(liquid/gas)=({ml:.8g},{mg:.8g}) P=({total_px:.3e},{total_py:.3e})"
    )
    print(f"[run_dambreak_gas-state] metadata={meta_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY_STATE

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GAS_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

cat > "$PARAMS" <<PARAMS_EOF
inputState = $STATE
outputDir = $OUT
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = specular
bcRight = specular
bcBottom = solid
bcTop = specular
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
q6ForceProjectionMode = legacy
keepMeanFlowEnable = false
wallVpEnable = false
wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $LIQUID_MASS
wallKBT = -1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species0ThermostatTargetKBT = $LIQUID_KBT
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
species1ThermostatTargetKBT = $GAS_KBT
speciesRequireRegisteredTypes = true
speciesThermostatEnable = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_run_dambreak_gas.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = independent_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_OCCUPANCY_FRACTION
PARAMS_EOF
run_ok_surface_append_params_0493x13zi "$PARAMS" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"

export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
run_ok_surface_export_off_flags_0493x13zi

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_dambreak_gas.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_dambreak_gas.env" <<META
CASE_LABEL=$CASE_LABEL
LIQUID_COLUMN_WIDTH=$LIQUID_COLUMN_WIDTH
LIQUID_COLUMN_HEIGHT=$LIQUID_COLUMN_HEIGHT
LIQUID_TYPE=$LIQUID_TYPE
GAS_TYPE=$GAS_TYPE
LIQUID_MASS=$LIQUID_MASS
GAS_MASS=$GAS_MASS
LIQUID_KBT=$LIQUID_KBT
GAS_KBT=$GAS_KBT
GLOBAL_KBT_X6G=$KBT
GRAVITY_Y=$GRAVITY_Y
SURFACE_TENSION_SIGMA=$SURFACE_TENSION_SIGMA
SURFACE_TENSION_MIN_RADIUS_CELLS=$SURFACE_TENSION_MIN_RADIUS_CELLS
PHASE_INTERFACE_A_SELECTOR=$PHASE_INTERFACE_A_SELECTOR
PHASE_INTERFACE_B_SELECTOR=$PHASE_INTERFACE_B_SELECTOR
SPECIES_THERMOSTAT_ENABLE=true
MPCD_Q6_G_F_RESIDENT_CG_0493X7J=$MPCD_Q6_G_F_RESIDENT_CG_0493X7J
MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=$MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=$MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272
META

run_ok_surface_print_0493x13zi "x9+x6g-liquid-gas-species-thermostat"
echo "===== run_dambreak_gas ====="
echo "PATHS: runner=$RUN_OK_ENTRYPOINT"
echo "       generator=$RUN_OK_GENERATOR_PATH binary=$BIN"
echo "       state=$STATE params=$PARAMS output=$OUT"
echo "GRID:  L=${Lx}x${Ly} N=${NX}x${NY} gamma=$GAMMA dt=$DT steps=$STEPS"
echo "DAM:   column=(${LIQUID_COLUMN_WIDTH} x ${LIQUID_COLUMN_HEIGHT}) gravityY=$GRAVITY_Y"
echo "PHASE: liquid(type=$LIQUID_TYPE,m=$LIQUID_MASS,kBT=$LIQUID_KBT,q6=$LIQUID_Q6_STRENGTH)"
echo "       gas(type=$GAS_TYPE,m=$GAS_MASS,kBT=$GAS_KBT,q6=$GAS_Q6_STRENGTH) uniform outside liquid column"
echo "THERM: speciesThermostat=true mode=$THERMOSTAT_MODE every=$THERMOSTAT_EVERY minParticles=$THERMOSTAT_MIN_PARTICLES"
echo "PATH:  src-q6-g-f + x6g gas pressure; x10/x12 kinetic liquid-vacuum closure disabled"
echo "NOTE:  ./livevis_control.kv is user-owned and not modified"
echo "============================"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

echo "[run_dambreak_gas] completed output=$OUT"

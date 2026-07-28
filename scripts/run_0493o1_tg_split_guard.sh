#!/usr/bin/env bash
# 0493o2-fix1: TG mono/dual species runner
set -euo pipefail

# 0493o1 -- SRC-only periodic Taylor--Green baseline.
# Physical-reference bench for the future asymmetric resampling development.
# No Q6, no mutating resampling operation. Passive support diagnostics remain on.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="0493o1_src_baseline_tg"
GEN_CASE="tg"
TOPOLOGY="periodic"
MODE="src"

Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
NX="${NX:-64}"
NY="${NY:-64}"
GAMMA="${GAMMA:-20}"

# 0493o2-fix1: the mono path remains the strict default.  The dual path
# changes particle type labels only; positions, velocities, masses and roles
# are inherited unchanged from the same Taylor--Green generator.
TG_SPECIES_MODE="${TG_SPECIES_MODE:-mono}"
TG_SPECIES0_TYPE="${TG_SPECIES0_TYPE:-1}"
TG_SPECIES1_TYPE="${TG_SPECIES1_TYPE:-2}"
SPECIES0_RESAMPLING_ENABLE="${SPECIES0_RESAMPLING_ENABLE:-true}"
SPECIES1_RESAMPLING_ENABLE="${SPECIES1_RESAMPLING_ENABLE:-true}"

case "$TG_SPECIES_MODE" in
  mono|dual) ;;
  *)
    echo "[0493o2-tg] ERROR TG_SPECIES_MODE='$TG_SPECIES_MODE'; expected mono or dual" >&2
    exit 2
    ;;
esac
if [[ "$TG_SPECIES_MODE" == dual ]]; then
  [[ "$TG_SPECIES0_TYPE" =~ ^[0-9]+$ ]] || {
    echo "[0493o2-tg] ERROR TG_SPECIES0_TYPE must be an unsigned integer" >&2
    exit 2
  }
  [[ "$TG_SPECIES1_TYPE" =~ ^[0-9]+$ ]] || {
    echo "[0493o2-tg] ERROR TG_SPECIES1_TYPE must be an unsigned integer" >&2
    exit 2
  }
  if [[ "$TG_SPECIES0_TYPE" == "$TG_SPECIES1_TYPE" ]]; then
    echo "[0493o2-tg] ERROR dual species types must differ" >&2
    exit 2
  fi
  if (( GAMMA % 2 != 0 )); then
    echo "[0493o2-tg] ERROR dual 50/50 initialization requires even GAMMA, got $GAMMA" >&2
    exit 2
  fi
fi

STEPS="${STEPS:-2000}"
DT="${DT:-0.001}"
KBT="${KBT:-0.01}"
U0="${U0:-0.08}"
SEED="${SEED:-493001}"
VELOCITY_MODE="${VELOCITY_MODE:-taylor_green}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:--1.0}"

SUMMARY_EVERY="${SUMMARY_EVERY:-20}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-50}"
THREADS="${THREADS:-8}"
INACTIVE_SLOTS_PER_CELL="${INACTIVE_SLOTS_PER_CELL:-8}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((NX * NY * INACTIVE_SLOTS_PER_CELL))}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493o1_src_baseline_dual_bench/tg}"
RUN_ROOT="${RUN_ROOT:-$BASE_RUN_ROOT}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

# User-facing execution controls.  The control file is deliberately hard-wired
# to the repository root; runners must never create a case-local control file.
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-10}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"
LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
OVERWRITE_LIVEVIS_CONTROL="${OVERWRITE_LIVEVIS_CONTROL:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_SESSION_PREFIX="${RECORD_SESSION_PREFIX:-0493o1_src_baseline}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-$DUMP_STATE_EVERY}"
RECORD_STRIDE="${RECORD_STRIDE:-1}"

RESAMPLING_SURVEY_EVERY="${RESAMPLING_SURVEY_EVERY:-$SUMMARY_EVERY}"
FLAG_EVERY="${FLAG_EVERY:-$SUMMARY_EVERY}"
SUPPORT_TRIGGER_NMIN="${SUPPORT_TRIGGER_NMIN:-$(( (3 * GAMMA + 4) / 5 ))}"
OUTLIER_U_THRESHOLD="${OUTLIER_U_THRESHOLD:-1.0}"


# Emit only the registry payload; the surrounding common species controls stay
# in the runner's original parameter block.
species_registry_params_0493o2() {
  case "$TG_SPECIES_MODE" in
    mono)
      cat <<PARAMS
speciesCount = 1
species0 = ${BACKGROUND_TYPE} tg_mono unspecified 1.0 1.0 ${TARGET_CELL_MASS}
species0ResamplingEnable = ${SPECIES0_RESAMPLING_ENABLE}
PARAMS
      ;;
    dual)
      cat <<PARAMS
speciesCount = 2
species0 = ${TG_SPECIES0_TYPE} tg_species_A unspecified 1.0 1.0 ${SPECIES_TARGET_CELL_MASS}
species0ResamplingEnable = ${SPECIES0_RESAMPLING_ENABLE}
species1 = ${TG_SPECIES1_TYPE} tg_species_B unspecified 1.0 1.0 ${SPECIES_TARGET_CELL_MASS}
species1ResamplingEnable = ${SPECIES1_RESAMPLING_ENABLE}
PARAMS
      ;;
  esac
}

# Convert the generated homogeneous TG state to a locally balanced binary
# mixture.  Only the uint32 type array is rewritten.  Active particles are
# alternated in the original per-cell order; inactive/latent slots are assigned
# species 0 so every stored type is registered.
rewrite_tg_species_types_0493o2() {
  local state=$1
  [[ "$TG_SPECIES_MODE" == dual ]] || return 0

  python3 - "$state" "$NX" "$NY" "$Lx" "$Ly" \
    "$TG_SPECIES0_TYPE" "$TG_SPECIES1_TYPE" <<'PY0493O2'
from __future__ import annotations

import math
import os
import struct
import sys
from collections import defaultdict
from pathlib import Path

state, nx, ny, lx, ly, type_a, type_b = sys.argv[1:]
path = Path(state)
nx, ny = int(nx), int(ny)
lx, ly = float(lx), float(ly)
type_a, type_b = int(type_a), int(type_b)

if nx <= 0 or ny <= 0 or lx <= 0.0 or ly <= 0.0:
    raise SystemExit("[0493o2-state] invalid grid or domain")
if not (0 <= type_a <= 0xFFFFFFFF and 0 <= type_b <= 0xFFFFFFFF):
    raise SystemExit("[0493o2-state] species type outside uint32 range")
if type_a == type_b:
    raise SystemExit("[0493o2-state] species types must differ")

raw = bytearray(path.read_bytes())
header_size = 16 + struct.calcsize("<IIIIQIIII") + 8 * 8
if len(raw) < header_size:
    raise SystemExit(f"[0493o2-state] truncated state: {path}")
if bytes(raw[:16]).rstrip(b"\0") != b"SRCMPCD_STATE":
    raise SystemExit(f"[0493o2-state] bad magic in {path}")
version, endian, dim, layout, n, has_type, has_mass, real_size, type_size = \
    struct.unpack_from("<IIIIQIIII", raw, 16)
if version not in (1, 2) or endian != 0x01020304 or dim != 2 or layout != 1:
    raise SystemExit("[0493o2-state] unsupported state header")
if has_type != 1 or has_mass != 1 or real_size != 8 or type_size != 4:
    raise SystemExit("[0493o2-state] unsupported scalar layout")

x_off = header_size
y_off = x_off + 8 * n
vx_off = y_off + 8 * n
vy_off = vx_off + 8 * n
type_off = vy_off + 8 * n
mass_off = type_off + 4 * n
role_off = mass_off + 8 * n
expected_size = role_off + (n if version >= 2 else 0)
if len(raw) != expected_size:
    raise SystemExit(
        f"[0493o2-state] unexpected file size: got={len(raw)} expected={expected_size}"
    )

xs = struct.unpack_from(f"<{n}d", raw, x_off)
ys = struct.unpack_from(f"<{n}d", raw, y_off)
roles = raw[role_off:role_off + n] if version >= 2 else bytes([1]) * n

cells: dict[int, list[int]] = defaultdict(list)
fluid = 0
for p in range(n):
    if roles[p] != 1:
        struct.pack_into("<I", raw, type_off + 4 * p, type_a)
        continue
    x = xs[p] % lx
    y = ys[p] % ly
    ix = min(nx - 1, max(0, int(math.floor(x * nx / lx))))
    iy = min(ny - 1, max(0, int(math.floor(y * ny / ly))))
    cells[ix + nx * iy].append(p)
    fluid += 1

if len(cells) != nx * ny:
    raise SystemExit(
        f"[0493o2-state] expected {nx * ny} occupied cells, found {len(cells)}"
    )

count_a = 0
count_b = 0
min_cell = None
max_cell = 0
for cell in range(nx * ny):
    ids = cells[cell]
    min_cell = len(ids) if min_cell is None else min(min_cell, len(ids))
    max_cell = max(max_cell, len(ids))
    if len(ids) % 2 != 0:
        raise SystemExit(
            f"[0493o2-state] cell {cell} has odd fluid count {len(ids)}; "
            "dual 50/50 initialization requires even occupancy"
        )
    for local, p in enumerate(ids):
        typ = type_a if local % 2 == 0 else type_b
        struct.pack_into("<I", raw, type_off + 4 * p, typ)
        if typ == type_a:
            count_a += 1
        else:
            count_b += 1

if count_a + count_b != fluid or count_a != count_b:
    raise SystemExit(
        f"[0493o2-state] bad composition A={count_a} B={count_b} fluid={fluid}"
    )

tmp = path.with_suffix(path.suffix + ".0493o2.tmp")
tmp.write_bytes(raw)
os.replace(tmp, path)
print(
    f"[0493o2-state] mode=dual state={path} fluid={fluid} "
    f"type{type_a}={count_a} type{type_b}={count_b} "
    f"cells={len(cells)} cellN=[{min_cell},{max_cell}]"
)
PY0493O2
}

suite_defaults_common_0434
suite_compute_derived_0434

TARGET_CELL_MASS="$(python3 - "$GAMMA" "$PARTICLE_MASS" <<'PY_MASS'
import sys
gamma = float(sys.argv[1])
particle_mass = float(sys.argv[2])
print(gamma * particle_mass)
PY_MASS
)"
SPECIES_TARGET_CELL_MASS="$(python3 - "$TARGET_CELL_MASS" <<'PY_SPECIES_MASS'
import sys
print(0.5 * float(sys.argv[1]))
PY_SPECIES_MASS
)"
suite_prepare_dirs_0434 "$RUN_ROOT"

TG_CASE_SUFFIX=""
if [[ "$TG_SPECIES_MODE" == dual ]]; then
  TG_CASE_SUFFIX="_dual_t${TG_SPECIES0_TYPE}_t${TG_SPECIES1_TYPE}"
fi
STATE="$RUN_ROOT/init/${CASE_LABEL}${TG_CASE_SUFFIX}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}${TG_CASE_SUFFIX}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}${TG_CASE_SUFFIX}.log"
TIME="$RUN_ROOT/logs/${CASE_LABEL}${TG_CASE_SUFFIX}.time"
mkdir -p "$OUT"

suite_generate_case_0434 "$STATE"
rewrite_tg_species_types_0493o2 "$STATE"

cat > "$PARAMS" <<PARAMS
inputState = ${STATE}
outputDir = ${OUT}
Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}
dt = ${DT}
nSteps = ${STEPS}
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
openBoundarySegmentsEnable = false
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

# 0493o1 uses a strict cell/species deposit, including mono-species cases.
speciesRegistryEnable = true
$(species_registry_params_0493o2)
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false

$(suite_write_common_params_0434 "$MODE")
PARAMS

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"

# Passive population/support observability on a strictly SRC-only run.
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=1
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="$RESAMPLING_SURVEY_EVERY"
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE=full
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=1
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY="$FLAG_EVERY"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN="$SUPPORT_TRIGGER_NMIN"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY=1
export MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U="$OUTLIER_U_THRESHOLD"
export MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD="$OUTLIER_U_THRESHOLD"
export MPCD_INTERNAL_PROFILES="${MPCD_INTERNAL_PROFILES:-1}"
export MPCD_CUDA_RESIDENT_PROFILE_0266="${MPCD_CUDA_RESIDENT_PROFILE_0266:-1}"

# Hard assertion: no mutating resampling brick may be enabled in this baseline.
export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
export MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$MODE"
[[ "$LIVE_VIS_CONTROL_FILE" == "$ROOT/livevis_control.kv" ]] || {
  echo "[0493o1-tg] ERROR livevis control escaped repository root: $LIVE_VIS_CONTROL_FILE" >&2
  exit 2
}
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493o1.env" "$MODE"
cat >> "$RUN_ROOT/logs/environment_0493o1.env" <<META
MPCD_INTERNAL_PROFILES=${MPCD_INTERNAL_PROFILES}
MPCD_CUDA_RESIDENT_PROFILE_0266=${MPCD_CUDA_RESIDENT_PROFILE_0266}
RESAMPLING_SURVEY_EVERY=${RESAMPLING_SURVEY_EVERY}
FLAG_EVERY=${FLAG_EVERY}
SUPPORT_TRIGGER_NMIN=${SUPPORT_TRIGGER_NMIN}
TG_SPECIES_MODE=${TG_SPECIES_MODE}
TG_SPECIES0_TYPE=${TG_SPECIES0_TYPE}
TG_SPECIES1_TYPE=${TG_SPECIES1_TYPE}
SPECIES0_RESAMPLING_ENABLE=${SPECIES0_RESAMPLING_ENABLE}
SPECIES1_RESAMPLING_ENABLE=${SPECIES1_RESAMPLING_ENABLE}
SPECIES_TARGET_CELL_MASS=${SPECIES_TARGET_CELL_MASS}
META

printf '[0493o1-tg] SRC-only periodic Taylor--Green\n'
printf '[0493o2-tg] speciesMode=%s type0=%s type1=%s resample0=%s resample1=%s speciesTargetMass=%s\n' \
  "$TG_SPECIES_MODE" "$TG_SPECIES0_TYPE" "$TG_SPECIES1_TYPE" \
  "$SPECIES0_RESAMPLING_ENABLE" "$SPECIES1_RESAMPLING_ENABLE" \
  "$SPECIES_TARGET_CELL_MASS"
printf '[0493o1-tg] grid=%sx%s gamma=%s active~%s inactive=%s steps=%s dt=%s\n' \
  "$NX" "$NY" "$GAMMA" "$((NX * NY * GAMMA))" "$INACTIVE_SLOTS" "$STEPS" "$DT"
printf '[0493o1-tg] live_progress=%s livevis=%s control=%s every=%s\n' \
  "$LIVE_PROGRESS" "$LIVE_VIS_ENABLE" "$LIVE_VIS_CONTROL_FILE" "$LIVE_VIS_EVERY"
printf '[0493o1-tg] summaryEvery=%s dumpEvery=%s surveyEvery=%s flagEvery=%s\n' \
  "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$RESAMPLING_SURVEY_EVERY" "$FLAG_EVERY"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME" "$OUT"

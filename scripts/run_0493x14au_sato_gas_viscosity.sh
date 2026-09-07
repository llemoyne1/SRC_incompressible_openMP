#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

CAL="$ROOT/scripts/calibrate_fluid_0493w1_standalone.sh"
[[ -x "$CAL" || -f "$CAL" ]] || { echo "[0493x14au-G] ERROR missing $CAL" >&2; exit 2; }
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
[[ -x "$BIN" ]] || { echo "[0493x14au-G] ERROR BIN not executable: $BIN" >&2; exit 2; }

MODE="run"
case "${1:-}" in
  '') ;;
  --preflight) MODE="preflight" ;;
  --analyze-only) MODE="analyze" ;;
  --check) MODE="check" ;;
  -h|--help)
    cat <<'USAGE'
0493x14au — x14at gas transverse-viscosity qualification

Uses the authoritative standalone 0493w1 Taylor-Green calibrator on the
unprojected SRC path, with the exact x14at gas microscopic fluid:
  gamma=20, alpha=90deg, h=1/256, dt=0.001, kBT=0.08, m=0.1.

Two wavelengths are measured with the same 64x64 grid and same seed ensemble:
  primary:     mode=(1,1), wavelength=64 h, TG_TIME=4
  application: mode=(3,3), wavelength=64/3 h = 21.333 h, TG_TIME=4/9
The second wavelength is close to the Sato campaign nozzle width D=20 h.

Usage:
  bash scripts/run_0493x14au_sato_gas_viscosity.sh
  bash scripts/run_0493x14au_sato_gas_viscosity.sh --preflight
  RESTART=1 bash scripts/run_0493x14au_sato_gas_viscosity.sh
  bash scripts/run_0493x14au_sato_gas_viscosity.sh --analyze-only

RESTART=1 is ensemble-level restart: completed seeds are skipped and an
incomplete seed is recomputed from its Taylor-Green initial state. These small
periodic calibration grids deliberately do not use LiveVis/recording.
USAGE
    exit 0
    ;;
  *) echo "[0493x14au-G] ERROR unknown argument: ${1:-}" >&2; exit 2 ;;
esac

BASE_ROOT="${BASE_ROOT:-runs/0493x14au_sato_viscosity}"
PRIMARY_SEEDS="${PRIMARY_SEEDS:-4932101,4932102,4932103,4932104,4932105,4932106,4932107,4932108}"
SCALE_SEEDS="${SCALE_SEEDS:-4932101,4932102,4932103,4932104}"
RESTART="${RESTART:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

# Exact x14at gas microscopic point. The gas has q6Strength=0 in x14at, so its
# bulk transverse viscosity is calibrated on the unprojected SRC path.
CELL_SIZE="${CELL_SIZE:-0.00390625}"
GAMMA="${GAMMA:-20}"
DT_OVERRIDE="${DT_OVERRIDE:-0.001}"
KBT="${KBT:-0.08}"
PARTICLE_MASS="${PARTICLE_MASS:-0.1}"
ROTATION_ANGLE_DEG="${ROTATION_ANGLE_DEG:-90}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
NX="${NX:-64}"; NY="${NY:-64}"
TG_DUMP_COUNT="${TG_DUMP_COUNT:-80}"
SCALE_TG_DUMP_COUNT="${SCALE_TG_DUMP_COUNT:-40}"

if [[ "$RESTART" == "1" ]]; then
  CLEAN=0
else
  CLEAN=1
fi
SKIP_EXISTING=1

mkdir -p "$BASE_ROOT"
MANIFEST="$BASE_ROOT/gas_manifest.txt"
{
  echo "qualification=0493x14au-gas"
  echo "timestamp=$(date -Is)"
  echo "head=$(git rev-parse HEAD 2>/dev/null || echo unavailable)"
  echo "binary=$BIN"
  echo "binary_sha256=$(sha256sum "$BIN" | awk '{print $1}')"
  echo "calibrator=$CAL"
  echo "calibrator_sha256=$(sha256sum "$CAL" | awk '{print $1}')"
  echo "path=src"
  echo "gamma=$GAMMA"
  echo "alphaDeg=$ROTATION_ANGLE_DEG"
  echo "h=$CELL_SIZE"
  echo "dt=$DT_OVERRIDE"
  echo "kBT=$KBT"
  echo "mass=$PARTICLE_MASS"
  echo "primarySeeds=$PRIMARY_SEEDS"
  echo "scaleSeeds=$SCALE_SEEDS"
  python3 - "$CELL_SIZE" "$DT_OVERRIDE" "$KBT" "$PARTICLE_MASS" <<'PY'
import math,sys
h,dt,kbt,m=map(float,sys.argv[1:])
vmean=math.sqrt(math.pi*kbt/(2*m))
print(f"lambdaMeanOverH={vmean*dt/h:.17g}")
print("tgPrimaryWavelengthOverH=64")
print(f"tgApplicationWavelengthOverH={64/3:.17g}")
print(f"tgApplicationWavelengthOverD={(64/3)/20:.17g}")
PY
} > "$MANIFEST"
cat "$MANIFEST"

run_scale() {
  local label="$1" mode_xy="$2" t_phys="$3" seeds="$4" dump_count="$5"
  local rr="$BASE_ROOT/gas_${label}"
  local arg=()
  case "$MODE" in
    preflight) arg=(--preflight) ;;
    analyze) arg=(--analyze-only) ;;
    check) arg=(--check) ;;
    run) arg=() ;;
  esac
  echo "[0493x14au-G] scale=$label mode=($mode_xy,$mode_xy) TG_TIME=$t_phys root=$rr"
  CALIBRATION_PATH=src \
  CALIBRATION_EXPERIMENTS=tg \
  RUN_ROOT="$rr" BIN="$BIN" \
  CELL_SIZE="$CELL_SIZE" NX="$NX" NY="$NY" GAMMA="$GAMMA" \
  DT_OVERRIDE="$DT_OVERRIDE" KBT="$KBT" PARTICLE_MASS="$PARTICLE_MASS" \
  ROTATION_ANGLE_DEG="$ROTATION_ANGLE_DEG" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true \
  THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" THERMOSTAT_MODE="$THERMOSTAT_MODE" \
  THERMOSTAT_EVERY="$THERMOSTAT_EVERY" THERMOSTAT_TARGET_KBT="$THERMOSTAT_TARGET_KBT" \
  THERMOSTAT_MIN_PARTICLES="$THERMOSTAT_MIN_PARTICLES" \
  TG_MODE_X="$mode_xy" TG_MODE_Y="$mode_xy" TG_TIME="$t_phys" TG_DUMP_COUNT="$dump_count" \
  SEEDS="$seeds" \
  LIVE_PROGRESS="$LIVE_PROGRESS" THREADS="$THREADS" \
  CLEAN_RUN_ROOT="$CLEAN" SKIP_EXISTING="$SKIP_EXISTING" \
  bash "$CAL" "${arg[@]}"
}

if [[ "$MODE" == "check" ]]; then
  run_scale lambda64h 1 4.0 "$PRIMARY_SEEDS" "$TG_DUMP_COUNT"
  exit 0
fi

run_scale lambda64h 1 4.0 "$PRIMARY_SEEDS" "$TG_DUMP_COUNT"
run_scale lambda21p333h 3 0.4444444444444444 "$SCALE_SEEDS" "$SCALE_TG_DUMP_COUNT"

echo "[0493x14au-G] COMPLETE mode=$MODE root=$BASE_ROOT"

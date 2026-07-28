#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
SWEEP_ROOT="${SWEEP_ROOT:-runs/0493w1_src_fluid_presweep}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_SWEEP_ROOT="${CLEAN_SWEEP_ROOT:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PROFILE="${PROFILE:-physical6}"
CHARACTERISTIC_U="${CHARACTERISTIC_U:-0.15}"
CHARACTERISTIC_L="${CHARACTERISTIC_L:-0.24}"
SOUND_REPLICATES="${SOUND_REPLICATES:-4}"
SOUND_DENSITY_AMPLITUDE="${SOUND_DENSITY_AMPLITUDE:-0.08}"
TG_STEPS="${TG_STEPS:-1500}"
TG_DUMP_COUNT="${TG_DUMP_COUNT:-60}"
SOUND_STEPS="${SOUND_STEPS:-1200}"
SOUND_DUMP_COUNT="${SOUND_DUMP_COUNT:-120}"
MSD_STEPS="${MSD_STEPS:-2500}"
MSD_DUMP_COUNT="${MSD_DUMP_COUNT:-50}"

case "$PROFILE" in
  smoke2)
    CASES=(
      "a256_dt002_k030|0.00390625|0.002|0.03"
      "a256_dt002_k125|0.00390625|0.002|0.125"
    )
    ;;
  physical6)
    CASES=(
      "a192_dt002_k030|0.005208333333333333|0.002|0.03"
      "a192_dt002_k125|0.005208333333333333|0.002|0.125"
      "a256_dt002_k030|0.00390625|0.002|0.03"
      "a256_dt002_k125|0.00390625|0.002|0.125"
      "a256_dt004_k125|0.00390625|0.004|0.125"
      "a384_dt002_k125|0.002604166666666667|0.002|0.125"
    )
    ;;
  *) echo "[0493w1-presweep] unknown PROFILE=$PROFILE" >&2; exit 2 ;;
esac

if [[ "$PREFLIGHT_ONLY" != 1 && "$CLEAN_SWEEP_ROOT" == 1 ]]; then rm -rf "$SWEEP_ROOT"; fi
mkdir -p "$SWEEP_ROOT"
manifest="$SWEEP_ROOT/manifest_0493w1.csv"
printf 'case,cell,dt,kBT,Nx,Ny,Lx,Ly,lambdaMeanOverCellProxy\n' > "$manifest"

for item in "${CASES[@]}"; do
  IFS='|' read -r label cell dt kbt <<< "$item"
  lx=$(python3 -c "print(64*float('$cell'))")
  lam=$(python3 -c "import math; print(math.sqrt(math.pi*float('$kbt')/2)*float('$dt')/float('$cell'))")
  printf '%s,%s,%s,%s,64,64,%s,%s,%s\n' "$label" "$cell" "$dt" "$kbt" "$lx" "$lx" "$lam" >> "$manifest"
  case_sound_dump_count="$SOUND_DUMP_COUNT"
  if [[ "$label" == "a384_dt002_k125" ]]; then
    case_sound_dump_count=240
  else
    python3 - "$dt" <<'PY_DT' >/dev/null || case_sound_dump_count=240
import sys
raise SystemExit(0 if float(sys.argv[1]) < 0.004 else 1)
PY_DT
  fi
  echo "===== 0493w1 PRESWEEP case=$label cell=$cell dt=$dt kBT=$kbt lambda/a~$lam soundDumps=$case_sound_dump_count ====="
  env \
    RUN_ROOT="$SWEEP_ROOT/$label" CLEAN_RUN_ROOT=1 PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
    LIVE_PROGRESS="$LIVE_PROGRESS" Lx="$lx" Ly="$lx" NX=64 NY=64 GAMMA=20 \
    DT="$dt" KBT="$kbt" PARTICLE_MASS=1 \
    ROTATION_ANGLE=1.5707963267948966 RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true \
    THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 \
    THERMOSTAT_TARGET_KBT="$kbt" THERMOSTAT_MIN_PARTICLES=3 \
    TG_STEPS="$TG_STEPS" TG_DUMP_COUNT="$TG_DUMP_COUNT" \
    SOUND_MODE_X=2 SOUND_STEPS="$SOUND_STEPS" SOUND_DUMP_COUNT="$case_sound_dump_count" \
    SOUND_REPLICATES="$SOUND_REPLICATES" SOUND_DENSITY_AMPLITUDE="$SOUND_DENSITY_AMPLITUDE" \
    MSD_STEPS="$MSD_STEPS" MSD_DUMP_COUNT="$MSD_DUMP_COUNT" \
    CHARACTERISTIC_U="$CHARACTERISTIC_U" CHARACTERISTIC_L="$CHARACTERISTIC_L" \
    bash scripts/run_0493w1_src_fluid_calibrator.sh
 done

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[0493w1-presweep] PREFLIGHT_ONLY=1 cases=${#CASES[@]} manifest=$manifest"
  exit 0
fi
python3 scripts/analyze_0493w1_src_fluid_presweep.py --root "$SWEEP_ROOT"

#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

PARENT="scripts/run_0493x10o_q6_thermal_interface_static_drop.sh"
[[ -x "$PARENT" || -f "$PARENT" ]] || { echo "[0493x11a] ERROR missing $PARENT" >&2; exit 2; }
grep -q '0493x10q-wide-overlap-recovery' src/cuda_q6_resident_0400.cu || {
  echo "[0493x11a] ERROR current source does not contain x10q" >&2; exit 2; }

BASE="${BASE_RUN_ROOT:-runs/0493x11a_young_laplace}"
STEPS="${STEPS:-1000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
SEEDS="${SEEDS:-4931101 4931102 4931103}"
NX="${NX:-256}"; NY="${NY:-256}"; Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-20}"; DT="${DT:-0.002}"; KBT="${KBT:-0.125}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"
CLEAN_BASE="${CLEAN_BASE:-1}"
TAIL_START="${TAIL_START:-0.5}"

if [[ "$CLEAN_BASE" == 1 ]]; then rm -rf "$BASE"; fi
mkdir -p "$BASE" "$BASE/logs"
MANIFEST="$BASE/manifest.csv"
echo 'case,sigma,r_cells,seed,run_dir,h,steps' > "$MANIFEST"

read -r H CX CY <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
dx,dy=lx/nx,ly/ny
if abs(dx-dy)>1e-12*max(1,abs(dx),abs(dy)): raise SystemExit("square cells required")
print(f"{dx:.17g} {0.5*lx:.17g} {0.5*ly:.17g}")
PY
)"

# Compact 7-case design:
#   radius sweep: sigma=1500, R/h = 8,12,20,40
#   sigma sweep : R/h=20, sigma = 500,1500,3000,4500
# The (1500,20) point is shared.
CASES='500:20 1500:8 1500:12 1500:20 1500:40 3000:20 4500:20'

echo '===== 0493x11a YOUNG-LAPLACE QUANTITATIVE CAMPAIGN ====='
echo "[0493x11a] domain=${NX}x${NY} L=(${Lx},${Ly}) h=$H gamma=$GAMMA dt=$DT kBT=$KBT"
echo "[0493x11a] steps=$STEPS summaryEvery=$SUMMARY_EVERY seeds=[$SEEDS]"
echo "[0493x11a] radius sweep sigma=1500 R/h={8,12,20,40}; sigma sweep R/h=20 sigma={500,1500,3000,4500}"
echo '[0493x11a] pressure source=cuda_static_drop_pressure_0493x9e.csv (solved Q6 pressure gauge)'

for seed in $SEEDS; do
  for spec in $CASES; do
    sigma="${spec%%:*}"
    rc="${spec##*:}"
    tag="s${sigma}_r${rc}_seed${seed}"
    run="$BASE/$tag"
    echo
    echo "===== $tag ====="
    RUN_ROOT="$run" \
    NX="$NX" NY="$NY" Lx="$Lx" Ly="$Ly" \
    GAMMA="$GAMMA" DT="$DT" KBT="$KBT" LIQUID_MASS="$LIQUID_MASS" \
    SIGMA_ACTIVE="$sigma" SURFACE_TENSION_MIN_RADIUS_CELLS="$MIN_RADIUS_CELLS" \
    DROP_RADIUS_CELLS="$rc" DROP_CENTER_X="$CX" DROP_CENTER_Y="$CY" \
    CONTACT_ANGLE_DEG=-1 \
    SEED="$seed" STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" \
    DUMP_STATE_EVERY=0 INACTIVE_SLOTS=0 CLEAN_RUN_ROOT=1 \
    LIVE_PROGRESS=1 LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 \
    LIVE_VIS_RECORD_ENABLE=0 FILTERED_RECORDING_ENABLE=0 \
    OVERWRITE_LIVEVIS_CONTROL=1 \
    bash "$PARENT" 2>&1 | tee "$BASE/logs/${tag}.log"

    [[ -s "$run/output/cuda_static_drop_pressure_0493x9e.csv" ]] || {
      echo "[0493x11a] ERROR missing x9e pressure CSV for $tag" >&2; exit 2; }
    echo "$tag,$sigma,$rc,$seed,$run,$H,$STEPS" >> "$MANIFEST"
  done
done

python3 scripts/analyze_0493x11a_young_laplace.py \
  --manifest "$MANIFEST" --output-dir "$BASE/analysis" --tail-start "$TAIL_START"

echo "[0493x11a] COMPLETE analysis=$BASE/analysis"

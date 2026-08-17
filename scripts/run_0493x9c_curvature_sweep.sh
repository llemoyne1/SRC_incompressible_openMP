#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
GAMMAS="${GAMMAS:-10 20 40}"
R_CELLS_LIST="${R_CELLS_LIST:-8 12 16 24 40 80}"
NX="${NX:-400}"; NY="${NY:-400}"; Lx="${Lx:-1.5625}"; Ly="${Ly:-1.5625}"
SWEEP_ROOT="${SWEEP_ROOT:-runs/0493x9c_curvature_sweep_${NX}x${NY}}"
KEEP_STATES="${KEEP_STATES:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
mkdir -p "$SWEEP_ROOT"

echo "[0493x9c-sweep] gammas=$GAMMAS radiiCells=$R_CELLS_LIST grid=${NX}x${NY} root=$SWEEP_ROOT"
for g in $GAMMAS; do
  for rc in $R_CELLS_LIST; do
    case_root="$SWEEP_ROOT/g${g}_rc${rc}"
    echo "[0493x9c-sweep] RUN gamma=$g Rcells=$rc"
    GAMMA="$g" R_CELLS="$rc" NX="$NX" NY="$NY" Lx="$Lx" Ly="$Ly" \
      BASE_RUN_ROOT="$case_root" CLEAN_RUN_ROOT=1 STEPS=1 SUMMARY_EVERY=1 \
      DUMP_STATE_EVERY=0 LIVE_VIS_ENABLE=0 FILTERED_RECORDING_ENABLE=0 \
      LIVE_PROGRESS="$LIVE_PROGRESS" \
      bash scripts/run_0493x9c_ellipse_curvature.sh
    if [[ "$KEEP_STATES" != "1" ]]; then
      rm -f "$case_root"/init/*.smpcd "$case_root"/output/*.smpcd 2>/dev/null || true
    fi
  done
done
python3 scripts/summarize_0493x9c_curvature_sweep.py \
  --root "$SWEEP_ROOT" --csv "$SWEEP_ROOT/curvature_sweep_0493x9c.csv"
echo "[0493x9c-sweep] DONE summary=$SWEEP_ROOT/curvature_sweep_0493x9c.csv"

#!/usr/bin/env bash
# 0493x22h — phase-cost decomposition across grid size at constant gamma.
# Diagnostic-only. Reuses x22g's exact production-path parameterization,
# changing only internal profile collection and shortening to one run per variant/grid.
set -euo pipefail
ROOT="${ROOT:-$PWD}"; ROOT="$(cd "$ROOT" && pwd)"; cd "$ROOT"
BASE="${BASE:-scripts/run_0493x22g_grid_cost_scaling.sh}"
ANALYZER="${ANALYZER:-scripts/analyze_0493x22h_grid_phase_profile.py}"
ROOTOUT="${ROOTOUT:-runs/0493x22h_grid_phase_profile}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
GRID_SIZES="${GRID_SIZES:-64 96 128 192 256}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-400}"
WARMUP_STEPS="${WARMUP_STEPS:-50}"

fail(){ echo "[0493x22h] ERROR: $*" >&2; exit 2; }
[[ -f "$BASE" ]] || fail "missing prerequisite $BASE (apply x22g first)"
[[ -f "$ANALYZER" ]] || fail "missing analyzer $ANALYZER"
mkdir -p "$ROOTOUT"/analysis
TMP="$ROOTOUT/run_x22g_profiled.tmp.sh"
cp "$BASE" "$TMP"
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
old='export MPCD_INTERNAL_PROFILES=0 MPCD_CUDA_RESIDENT_PROFILE_0266=0'
new='export MPCD_INTERNAL_PROFILES=1 MPCD_CUDA_RESIDENT_PROFILE_0266=0'
if s.count(old)!=1:
    raise SystemExit(f'expected exactly one profile export, found {s.count(old)}')
s=s.replace(old,new)
p.write_text(s)
PY
chmod +x "$TMP"

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  ROOTOUT="$ROOTOUT" GRID_SIZES="$GRID_SIZES" GAMMA="$GAMMA" STEPS="$STEPS" WARMUP_STEPS="$WARMUP_STEPS" REPS=1 PREFLIGHT_ONLY=1 bash "$TMP"
  echo "[0493x22h] PREFLIGHT PASS gamma=$GAMMA grids=[$GRID_SIZES] profiles=ON source=x22g-exact-production-paths"
  exit 0
fi

ROOTOUT="$ROOTOUT" GRID_SIZES="$GRID_SIZES" GAMMA="$GAMMA" STEPS="$STEPS" WARMUP_STEPS="$WARMUP_STEPS" REPS=1 PREFLIGHT_ONLY=0 bash "$TMP"
python3 "$ANALYZER" "$ROOTOUT" "$GRID_SIZES" "$GAMMA"
echo "[0493x22h] DONE summary=$ROOTOUT/analysis/grid_phase_profile_summary.txt"

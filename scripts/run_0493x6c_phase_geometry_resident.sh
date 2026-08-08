#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

NX="${NX:-300}"
NY="${NY:-150}"
GAMMA="${GAMMA:-10}"
STEPS="${STEPS:-20}"
LIQUID_COLUMN_WIDTH="${LIQUID_COLUMN_WIDTH:-0.5}"
LIQUID_COLUMN_HEIGHT="${LIQUID_COLUMN_HEIGHT:-0.8}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x6c_phase_geometry_resident_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export NX NY GAMMA STEPS LIQUID_COLUMN_WIDTH LIQUID_COLUMN_HEIGHT BASE_RUN_ROOT PREFLIGHT_ONLY
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10}"

# x6c is the first geometry scaffold whose two O(Ncells) construction passes
# execute at every Q6 solve.  It remains diagnostic-only: the projection never
# reads either resident field in this patch.
export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
# x6a/x6b are independently qualified and would add diagnostic passes.  Keep
# them off so the wall time isolates the cost of the resident x6c preparation.
export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A="${MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A:-0}"
export MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B="${MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B:-0}"

printf '%s\n' \
  "[0493x6c] resident phase-geometry infrastructure" \
  "[0493x6c] Q6 physics unchanged: resident geometry is built but not consumed" \
  "[0493x6c] pass1 rawFill=sum(liquid cell mass)/sum(liquid reference cell mass)" \
  "[0493x6c] pass2 conservative five-point filter lambda=0.125; no-flux on non-periodic domain boundaries" \
  "[0493x6c] cost contract: two O(Ncells) CUDA passes per Q6 solve; audit only at step 1 and SUMMARY_EVERY=$SUMMARY_EVERY"

bash scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh

if [[ "$PREFLIGHT_ONLY" != "1" ]]; then
  AUDIT="$BASE_RUN_ROOT/output/cuda_phase_geometry_resident_0493x6c.csv"
  REPORT="$BASE_RUN_ROOT/phase_geometry_resident_0493x6c.json"
  python3 scripts/analyze_0493x6c_phase_geometry_resident.py \
    --audit "$AUDIT" \
    --json "$REPORT"
  echo "[0493x6c] geometryAudit=$AUDIT"
  echo "[0493x6c] geometryReport=$REPORT"
fi

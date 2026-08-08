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
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x6b_phase_geometry_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export NX NY GAMMA STEPS LIQUID_COLUMN_WIDTH LIQUID_COLUMN_HEIGHT BASE_RUN_ROOT PREFLIGHT_ONLY
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
# Reuse the existing summary cadence for geometry diagnostics: no new runtime
# cadence parameter and no full-grid diagnostic pass on every time step.
export SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10}"
export MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=1
# x6a has already been qualified independently. Keep it off by default here so
# the x6b timing measures only the new geometry scaffold unless explicitly asked.
export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A="${MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A:-0}"

printf '%s\n' \
  "[0493x6b] diagnostic-only phase geometry scaffold" \
  "[0493x6b] Q6 physics unchanged: no geometry quantity is consumed by the projection" \
  "[0493x6b] phaseFill=sum(liquid cell mass)/sum(liquid reference cell mass)" \
  "[0493x6b] cost control: one O(Ncells) CUDA diagnostic pass only at step 1 and SUMMARY_EVERY=$SUMMARY_EVERY; no particle pass and no geometry field buffer"

bash scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh

if [[ "$PREFLIGHT_ONLY" != "1" ]]; then
  AUDIT="$BASE_RUN_ROOT/output/cuda_phase_interface_geometry_0493x6b.csv"
  REPORT="$BASE_RUN_ROOT/phase_interface_geometry_0493x6b.json"
  python3 scripts/analyze_0493x6b_phase_geometry.py \
    --audit "$AUDIT" \
    --json "$REPORT"
  echo "[0493x6b] geometryAudit=$AUDIT"
  echo "[0493x6b] geometryReport=$REPORT"
fi

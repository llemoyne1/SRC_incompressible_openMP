#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

NX="${NX:-300}"
NY="${NY:-150}"
GAMMA="${GAMMA:-10}"
STEPS="${STEPS:-200}"
LIQUID_COLUMN_WIDTH="${LIQUID_COLUMN_WIDTH:-0.5}"
LIQUID_COLUMN_HEIGHT="${LIQUID_COLUMN_HEIGHT:-0.8}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x6a_phase_pressure_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export NX NY GAMMA STEPS LIQUID_COLUMN_WIDTH LIQUID_COLUMN_HEIGHT BASE_RUN_ROOT PREFLIGHT_ONLY
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10}"
export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=1

printf '%s\n' \
  "[0493x6a] diagnostic-only phase pressure scaffold" \
  "[0493x6a] Q6 physics unchanged: free_surface_masked still uses zero-gauge interface pressure" \
  "[0493x6a] measured field: ideal-gas p_g=N_g*kBT/A and phi_g=dt*p_g/rho_liquid_ref"

bash scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh

if [[ "$PREFLIGHT_ONLY" != "1" ]]; then
  AUDIT="$BASE_RUN_ROOT/output/cuda_phase_interface_pressure_0493x6a.csv"
  REPORT="$BASE_RUN_ROOT/phase_interface_pressure_0493x6a.json"
  python3 scripts/analyze_0493x6a_phase_pressure.py \
    --audit "$AUDIT" \
    --json "$REPORT"
  echo "[0493x6a] pressureAudit=$AUDIT"
  echo "[0493x6a] pressureReport=$REPORT"
fi

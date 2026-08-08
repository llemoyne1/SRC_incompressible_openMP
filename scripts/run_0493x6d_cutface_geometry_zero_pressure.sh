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
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x6d_cutface_zero_pressure_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export NX NY GAMMA STEPS LIQUID_COLUMN_WIDTH LIQUID_COLUMN_HEIGHT BASE_RUN_ROOT PREFLIGHT_ONLY
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10}"

# x6d consumes the x6c resident filtered alpha field in the masked free-surface
# pressure operator and in the matching face correction.  Gas pressure remains
# disabled: this isolates geometry at p_Gamma=0.
export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
export MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=1
export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A="${MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A:-0}"
export MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B="${MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B:-0}"

printf '%s\n' \
  "[0493x6d] guarded resident cut-face geometry, zero-gauge interface pressure" \
  "[0493x6d] alpha=0.5 distance used only on carrier/exterior faces that bracket the interface" \
  "[0493x6d] theta guard=0.10; smaller/non-bracketed faces retain legacy half-cell factor 2" \
  "[0493x6d] operator coefficient=1/(theta*h^2); face correction gradient=Delta(phi)/(theta*h)" \
  "[0493x6d] no gas-pressure coupling, no surface tension, no support-mask change, no extra production pass"

bash scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh

if [[ "$PREFLIGHT_ONLY" != "1" ]]; then
  AUDIT="$BASE_RUN_ROOT/output/cuda_phase_geometry_resident_0493x6c.csv"
  REPORT6C="$BASE_RUN_ROOT/phase_geometry_resident_0493x6c.json"
  REPORT6D="$BASE_RUN_ROOT/cutface_geometry_zero_pressure_0493x6d.json"
  python3 scripts/analyze_0493x6c_phase_geometry_resident.py \
    --audit "$AUDIT" --json "$REPORT6C"
  python3 scripts/analyze_0493x6d_cutface_geometry.py \
    --audit "$AUDIT" --json "$REPORT6D"
  echo "[0493x6d] geometryAudit=$AUDIT"
  echo "[0493x6d] geometryReport=$REPORT6D"
fi

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
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x6e_phase_interface_topology_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export NX NY GAMMA STEPS LIQUID_COLUMN_WIDTH LIQUID_COLUMN_HEIGHT BASE_RUN_ROOT PREFLIGHT_ONLY
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10}"

# x6e is diagnostic only.  It reuses the x6d physical path, while the new
# topology accounting is fused into the sparse x6c audit kernel.
export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
export MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=1
export MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1
export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A="${MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A:-0}"
export MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B="${MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B:-0}"

printf '%s\n' \
  "[0493x6e] diagnostic-only physical alpha=0.5 interface topology" \
  "[0493x6e] scans every unique grid face crossing alpha=0.5, independent of Q6 carrier boundary" \
  "[0493x6e] classes=active-active, active-inactive, inactive-inactive; x6d physics unchanged" \
  "[0493x6e] cost control: fused into sparse x6c audit kernel; no new production pass or resident field"

bash scripts/run_0493x6d_cutface_geometry_zero_pressure.sh

if [[ "$PREFLIGHT_ONLY" != "1" ]]; then
  AUDIT="$BASE_RUN_ROOT/output/cuda_phase_geometry_resident_0493x6c.csv"
  REPORT="$BASE_RUN_ROOT/phase_interface_topology_0493x6e.json"
  python3 scripts/analyze_0493x6e_phase_interface_topology.py \
    --audit "$AUDIT" --json "$REPORT"
  echo "[0493x6e] geometryAudit=$AUDIT"
  echo "[0493x6e] topologyReport=$REPORT"
fi

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
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x6f_phase_interface_stencil_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export NX NY GAMMA STEPS LIQUID_COLUMN_WIDTH LIQUID_COLUMN_HEIGHT BASE_RUN_ROOT PREFLIGHT_ONLY
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10}"

# x6f is the new active p_Gamma=0 pressure-domain path.  x6d must be disabled:
# its carrier-boundary cut-face operator is retained only as a comparison path.
export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
export MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0
export MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1
export MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
# Preserve x6f semantics even if a parent shell previously enabled x6g.
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0
export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A="${MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A:-0}"
export MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B="${MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B:-0}"

printf '%s\n' \
  "[0493x6f] resident alpha=0.5 phase-interface pressure stencil, pGamma=0" \
  "[0493x6f2] geometry source=clamp(raw liquid mass fill,0,1) before lambda=0.125 filtering; raw fill retained unbounded" \
  "[0493x6f] pressure domain=carrier AND alpha>=0.5; carrier remains particle-correction band" \
  "[0493x6f] east/north face coefficients prepared once per solve and reused by every CG iteration" \
  "[0493x6f] physical crossing: factor=1/theta; theta<0.10 keeps factor=2 stabilization" \
  "[0493x6f] same-phase carrier loss is NOT converted into an artificial p=0 interface" \
  "[0493x6f] no gas-pressure coupling and no surface tension; external domain BC path unchanged"

bash scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh

if [[ "$PREFLIGHT_ONLY" != "1" ]]; then
  GEOMETRY_AUDIT="$BASE_RUN_ROOT/output/cuda_phase_geometry_resident_0493x6c.csv"
  STENCIL_AUDIT="$BASE_RUN_ROOT/output/cuda_phase_interface_stencil_0493x6f.csv"
  REPORT6C="$BASE_RUN_ROOT/phase_geometry_resident_0493x6c.json"
  REPORT6F="$BASE_RUN_ROOT/phase_interface_stencil_0493x6f.json"
  python3 scripts/analyze_0493x6c_phase_geometry_resident.py \
    --audit "$GEOMETRY_AUDIT" --json "$REPORT6C"
  python3 scripts/analyze_0493x6f_phase_interface_stencil.py \
    --stencil "$STENCIL_AUDIT" --geometry "$GEOMETRY_AUDIT" --json "$REPORT6F"
  echo "[0493x6f] geometryAudit=$GEOMETRY_AUDIT"
  echo "[0493x6f] stencilAudit=$STENCIL_AUDIT"
  echo "[0493x6f] stencilReport=$REPORT6F"
fi

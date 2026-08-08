#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

NX="${NX:-300}"; NY="${NY:-150}"; GAMMA="${GAMMA:-10}"; STEPS="${STEPS:-20}"
Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"; KBT="${KBT:-0.05}"; DT="${DT:-0.005}"
LIQUID_COLUMN_WIDTH="${LIQUID_COLUMN_WIDTH:-0.5}"
LIQUID_COLUMN_HEIGHT="${LIQUID_COLUMN_HEIGHT:-0.8}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x6g_phase_gas_pressure_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
GAS_PRESSURE_MODE="${GAS_PRESSURE_MODE:-eos}"
GAS_PRESSURE_SCALE="${GAS_PRESSURE_SCALE:-1.0}"
CELL_AREA="$(awk -v lx="$Lx" -v ly="$Ly" -v nx="$NX" -v ny="$NY" 'BEGIN{printf "%.17g",(lx/nx)*(ly/ny)}')"
AMBIENT_EOS_PRESSURE="$(awk -v g="$GAMMA" -v t="$KBT" -v a="$CELL_AREA" 'BEGIN{printf "%.17g",g*t/a}')"
GAS_PRESSURE_REFERENCE="${GAS_PRESSURE_REFERENCE:-$AMBIENT_EOS_PRESSURE}"
GAS_PRESSURE_CONSTANT="${GAS_PRESSURE_CONSTANT:-$GAS_PRESSURE_REFERENCE}"

export NX NY GAMMA STEPS Lx Ly KBT DT LIQUID_COLUMN_WIDTH LIQUID_COLUMN_HEIGHT
export BASE_RUN_ROOT PREFLIGHT_ONLY
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10}"

export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
export MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0
export MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1
export MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G="$GAS_PRESSURE_MODE"
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$GAS_PRESSURE_REFERENCE"
export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G="$GAS_PRESSURE_CONSTANT"
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G="$GAS_PRESSURE_SCALE"
# Keep old diagnostics off: x6g audits the physical alpha=0.5 interface itself.
export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=0
export MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=0

printf '%s\n' \
  "[0493x6g] gas-pressure Dirichlet condition on resident alpha=0.5 interface" \
  "[0493x6g] p_l|Gamma=p_g; phiGamma=dt*(p_g-p_ref)/rho_l_ref; matrix unchanged from x6f" \
  "[0493x6g] source=$GAS_PRESSURE_MODE scale=$GAS_PRESSURE_SCALE pRef=$GAS_PRESSURE_REFERENCE pConst=$GAS_PRESSURE_CONSTANT" \
  "[0493x6g] EOS trace uses the alpha<0.5 gas-side cell; no liquid-side dilution" \
  "[0493x6g] future capillary path reuses the same face value for p_g + sigma*kappa"

bash scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh

if [[ "$PREFLIGHT_ONLY" != "1" ]]; then
  GEOMETRY="$BASE_RUN_ROOT/output/cuda_phase_geometry_resident_0493x6c.csv"
  STENCIL="$BASE_RUN_ROOT/output/cuda_phase_interface_stencil_0493x6f.csv"
  PRESSURE="$BASE_RUN_ROOT/output/cuda_phase_interface_pressure_0493x6g.csv"
  python3 scripts/analyze_0493x6c_phase_geometry_resident.py \
    --audit "$GEOMETRY" --json "$BASE_RUN_ROOT/phase_geometry_resident_0493x6c.json"
  python3 scripts/analyze_0493x6f_phase_interface_stencil.py \
    --stencil "$STENCIL" --geometry "$GEOMETRY" \
    --json "$BASE_RUN_ROOT/phase_interface_stencil_0493x6f.json"
  python3 scripts/analyze_0493x6g_phase_gas_pressure.py \
    --pressure "$PRESSURE" --stencil "$STENCIL" \
    --json "$BASE_RUN_ROOT/phase_interface_gas_pressure_0493x6g.json"
  echo "[0493x6g] pressureAudit=$PRESSURE"
  echo "[0493x6g] pressureReport=$BASE_RUN_ROOT/phase_interface_gas_pressure_0493x6g.json"
fi

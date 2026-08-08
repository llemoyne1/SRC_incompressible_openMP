#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"

NX="${NX:-300}"; NY="${NY:-150}"; GAMMA="${GAMMA:-10}"; STEPS="${STEPS:-1000}"
Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"; KBT="${KBT:-0.05}"
FINAL_ROOT="${FINAL_ROOT:-runs/0493x6g_final_dam_break_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
RUN_ZERO_REFERENCE="${RUN_ZERO_REFERENCE:-1}"
SUMMARY_EVERY="${SUMMARY_EVERY:-25}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-50}"
CELL_AREA="$(awk -v lx="$Lx" -v ly="$Ly" -v nx="$NX" -v ny="$NY" 'BEGIN{printf "%.17g",(lx/nx)*(ly/ny)}')"
P0="$(awk -v g="$GAMMA" -v t="$KBT" -v a="$CELL_AREA" 'BEGIN{printf "%.17g",g*t/a}')"
rm -rf "$FINAL_ROOT"
mkdir -p "$FINAL_ROOT"

common=(NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" Lx="$Lx" Ly="$Ly" KBT="$KBT"
        SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY"
        LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" LIVE_VIS_HOLD_ON_EXIT="$LIVE_VIS_HOLD_ON_EXIT"
        CLEAN_RUN_ROOT=1)

if [[ "$RUN_ZERO_REFERENCE" == "1" ]]; then
  echo "[0493x6g-final] matched zero-pGamma reference"
  env "${common[@]}" BASE_RUN_ROOT="$FINAL_ROOT/zero_pressure" \
    MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0 \
    bash scripts/run_0493x6f_phase_interface_stencil.sh
fi

echo "[0493x6g-final] EOS p_g interface run; ambient gauge pRef=$P0"
env "${common[@]}" BASE_RUN_ROOT="$FINAL_ROOT/eos_pressure" \
  GAS_PRESSURE_MODE=eos GAS_PRESSURE_SCALE=1 GAS_PRESSURE_REFERENCE="$P0" \
  bash scripts/run_0493x6g_phase_gas_pressure.sh

if [[ "$RUN_ZERO_REFERENCE" == "1" ]]; then
  python3 scripts/compare_0493x6g_dam_break.py \
    --zero "$FINAL_ROOT/zero_pressure" --eos "$FINAL_ROOT/eos_pressure" \
    --json "$FINAL_ROOT/dam_break_pg_vs_zero_0493x6g.json"
fi

echo "[0493x6g-final] PASS-like root=$FINAL_ROOT"

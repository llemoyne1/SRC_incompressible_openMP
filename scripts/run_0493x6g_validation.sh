#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

NX="${NX:-120}"; NY="${NY:-60}"; GAMMA="${GAMMA:-10}"
VALIDATION_STEPS="${VALIDATION_STEPS:-5}"
Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"; KBT="${KBT:-0.05}"
ROOT_RUN="${ROOT_RUN:-runs/0493x6g_validation_${NX}x${NY}_g${GAMMA}_s${VALIDATION_STEPS}}"
CELL_AREA="$(awk -v lx="$Lx" -v ly="$Ly" -v nx="$NX" -v ny="$NY" 'BEGIN{printf "%.17g",(lx/nx)*(ly/ny)}')"
P0="$(awk -v g="$GAMMA" -v t="$KBT" -v a="$CELL_AREA" 'BEGIN{printf "%.17g",g*t/a}')"
P2="$(awk -v p="$P0" 'BEGIN{printf "%.17g",2*p}')"
rm -rf "$ROOT_RUN"
mkdir -p "$ROOT_RUN"

common=(NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$VALIDATION_STEPS" Lx="$Lx" Ly="$Ly" KBT="$KBT"
        SUMMARY_EVERY="$VALIDATION_STEPS" DUMP_STATE_EVERY="$VALIDATION_STEPS"
        LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 CLEAN_RUN_ROOT=1)

echo "[0493x6g-validation] case 1/3: x6f zero-pressure reference"
env "${common[@]}" \
  BASE_RUN_ROOT="$ROOT_RUN/zero_reference" \
  MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0 \
  bash scripts/run_0493x6f_phase_interface_stencil.sh

echo "[0493x6g-validation] case 2/3: x6g enabled with EOS scale=0 (strict null path)"
env "${common[@]}" \
  BASE_RUN_ROOT="$ROOT_RUN/zero_scale" \
  GAS_PRESSURE_MODE=eos GAS_PRESSURE_SCALE=0 \
  GAS_PRESSURE_REFERENCE="$P0" \
  bash scripts/run_0493x6g_phase_gas_pressure.sh

echo "[0493x6g-validation] case 3/3: spatially constant nonzero pressure shift"
env "${common[@]}" \
  BASE_RUN_ROOT="$ROOT_RUN/constant_shift" \
  GAS_PRESSURE_MODE=constant GAS_PRESSURE_SCALE=1 \
  GAS_PRESSURE_REFERENCE="$P0" GAS_PRESSURE_CONSTANT="$P2" \
  bash scripts/run_0493x6g_phase_gas_pressure.sh

STEP_TAG="$(printf '%08d' "$VALIDATION_STEPS")"
REF="$ROOT_RUN/zero_reference/output/state_step_${STEP_TAG}.smpcd"
ZERO="$ROOT_RUN/zero_scale/output/state_step_${STEP_TAG}.smpcd"
CONST="$ROOT_RUN/constant_shift/output/state_step_${STEP_TAG}.smpcd"

python3 scripts/compare_0493x6g_states.py \
  --reference "$REF" --candidate "$ZERO" \
  --max-position "${ZERO_POSITION_TOL:-1e-13}" \
  --max-velocity "${ZERO_VELOCITY_TOL:-1e-13}" \
  --json "$ROOT_RUN/zero_scale_equivalence.json"
python3 scripts/compare_0493x6g_states.py \
  --reference "$REF" --candidate "$CONST" \
  --max-position "${GAUGE_POSITION_TOL:-5e-6}" \
  --max-velocity "${GAUGE_VELOCITY_TOL:-5e-5}" \
  --json "$ROOT_RUN/constant_pressure_gauge_invariance.json"

echo "[0493x6g-validation] PASS root=$ROOT_RUN p0=$P0"

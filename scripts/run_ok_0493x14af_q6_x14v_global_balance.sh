#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="$ROOT/scripts/run_ok_0493x14x_two_phase_oscillating_drop_n2.sh"
ANALYZER="$ROOT/scripts/analyze_0493x14af_q6_x14v_global_balance.py"
[[ -f "$BASE" ]] || { echo "[0493x14af] missing $BASE" >&2; exit 2; }
[[ -f "$ANALYZER" ]] || { echo "[0493x14af] missing $ANALYZER" >&2; exit 2; }

grep -q '0493x14af' "$ROOT/src/cuda_q6_resident_0400.cu" || {
  echo '[0493x14af] source diagnostic marker missing; apply patch first' >&2; exit 2;
}

# Short, synchronized balance test.  Physical parameters remain those of x14ae/x14ad.
export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1
export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0
export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0
export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=1
export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0

export CASE_LABEL="${CASE_LABEL:-0493x14af_q6_x14v_global_balance}"
export CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14af_q6_x14v_global_balance_seed493180}"
export SEED="${SEED:-493180}"
export MODE=2
export EPSILON=0.04
export RADIUS_CELLS=40
export SURFACE_TENSION_SIGMA=2560
export STEPS="${STEPS:-200}"
export SUMMARY_EVERY=1
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-200}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export RECORD_ENABLE=false
export FILTERED_RECORDING_ENABLE=0

printf '%s\n' \
  '===== 0493x14af Q6/X14V GLOBAL BALANCE =====' \
  "runner=$0" \
  "baseRunner=$BASE" \
  "runRoot=$CAMPAIGN_ROOT" \
  "steps=$STEPS summaryEvery=$SUMMARY_EVERY" \
  'x14ad=1 x14afBalanceDiag=1 scatterLossDiag=0 livevis=0 recording=0' \
  'goal: compare dPtot(step) with Jq6_applied(step)-Jthermo_x14ad(step)'

bash "$BASE"

python3 "$ANALYZER" --run-root "$CAMPAIGN_ROOT" --liquid-type 1

OUT_TAR="$CAMPAIGN_ROOT/0493x14af_q6_x14v_global_balance_compact.tar.gz"
FILES=(
  analysis
  output/cuda_x14v_global_balance_0493x14af.csv
  output/cuda_species_q6_independent_masked_0493w5.csv
  output/species_runtime_0493x14x.csv
  output/cuda_phase_interface_pressure_0493x6g.csv
  output/cuda_phase_interface_stencil_0493x6f.csv
  logs/${CASE_LABEL}.log
  logs/${CASE_LABEL}.time
  logs/environment_0493x14x.env
  params/${CASE_LABEL}.kv
)
PRESENT=(); for f in "${FILES[@]}"; do [[ -e "$CAMPAIGN_ROOT/$f" ]] && PRESENT+=("$f"); done
tar -czf "$OUT_TAR" -C "$CAMPAIGN_ROOT" "${PRESENT[@]}"
echo "[0493x14af] return: $OUT_TAR"

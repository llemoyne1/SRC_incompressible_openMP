#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="$ROOT/scripts/run_0493x14ah_drop_gas_transient_poiseuille_drag.sh"
SRC="$ROOT/src/cuda_q6_resident_0400.cu"
[[ -f "$BASE" ]] || { echo "[0493x14ai-drag] missing $BASE" >&2; exit 2; }
grep -q '0493x14ai — production-candidate device-side Q6 resultant closure' "$SRC" || { echo '[0493x14ai-drag] x14ai source marker missing' >&2; exit 2; }
export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1
export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC="${MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC:-0}"
CASE_LABEL="${CASE_LABEL:-0493x14ai_drop_gas_transient_poiseuille_drag}"
SEED="${SEED:-493191}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14ai_drop_gas_transient_poiseuille_drag_seed${SEED}}"
export CASE_LABEL SEED CAMPAIGN_ROOT

echo "===== 0493x14ai DYNAMIC DRAG WITH DEVICE CLOSURE ====="
echo "PATHS: runner=$ROOT/scripts/run_0493x14ai_drag_device_closure.sh base=$BASE"
echo "CHAIN: x14ah carrier + x14ad local distribution + x14ai exact B1 resultant"
echo "EXPECT: downstream drag retained; artificial n=1 transverse/global drift reduced"
echo "======================================================="
bash "$BASE"

#!/usr/bin/env bash
# =============================================================================
# 0493x24x — SHORT higher-load Sato probe
#
# Purpose
#   Explore one slightly more strongly forced case to see whether the oscillatory
#   cavity observed around Fr'_m=0.66 gives way to a different, possibly less
#   oscillatory regime before spending on any long campaign.
#
# Design choice
#   Keep dt = 4e-4 (short/cheap), but lower kBT_g/m_g from 3.2 to 2.0 so that
#   Fr'_m = 0.75 remains just inside the existing flight-resolution guard.
#
#   This is an EXPLORATORY regime probe, not a clean one-parameter continuation
#   of the M033 branch, because gas thermal/compressibility conditions change.
#
# Derived values:
#   Fr'_m,target = 0.75
#   Ujet         = 6.361732677881713
#   kBT_g/m_g    = 2.0
#   gas kBT      = 0.0023470411233701104
#   Ma_T proxy   = 4.4984
#   Cthermal     = 0.14482 cell/step
#   Cjet         = 0.65144 cell/step
#   Ctotal       = 0.79626 cell/step  (< 0.80, deliberately close)
#
# Procedure:
#   1) cheap zero-jet thermal relaxation: T=0.4 (1000 steps)
#   2) forced probe: T=2.0 (5000 steps)
#
# No C++/CUDA modification.
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SEED="${SEED:-493205}"

RELAX_RUNNER="scripts/run_0493x24h_sato_short_nozzle_relax.sh"
FORCED_RUNNER="scripts/run_0493x24i_sato_short_nozzle_forced.sh"

BASE_STATE="${BASE_STATE:-runs/0493x24h_sato_short_nozzle_relax_seed${SEED}/restart_short_nozzle_relax/output/state_step_00002000.smpcd}"
BASE_ROOT="${BASE_ROOT:-runs/0493x24x_sato_Fr075_KM2_short_seed${SEED}}"

DT="${DT:-0.0004}"
KM="${KM:-2.0}"
GAS_MASS="${GAS_MASS:-0.0011735205616850552}"
GAS_KBT="${GAS_KBT:-0.0023470411233701104}"

TARGET_H_OVER_D="${TARGET_H_OVER_D:-0.8}"
TARGET_FRM_SATO="${TARGET_FRM_SATO:-0.75}"
JET_SPEED="${JET_SPEED:-6.361732677881713}"

DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-800000}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-24.0}"

RELAX_STEPS="${RELAX_STEPS:-1000}"
FORCED_STEPS="${FORCED_STEPS:-5000}"
ANALYSIS_START_STEP="${ANALYSIS_START_STEP:-2500}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
RECORD_EVERY="${RECORD_EVERY:-20}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2500}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

for p in "$RELAX_RUNNER" "$FORCED_RUNNER" "$BASE_STATE"; do
  [[ -e "$p" ]] || { echo "[0493x24x] ERROR missing: $p" >&2; exit 2; }
done

python3 - "$DT" "$KM" "$JET_SPEED" "$TARGET_FRM_SATO" <<'PY'
import math,sys
dt,km,u,fr=map(float,sys.argv[1:])
h=1/256
cth=math.sqrt(km)*dt/h
cjet=u*dt/h
ctot=cth+cjet
mach=u/math.sqrt(km)
print(f"[0493x24x] Fr={fr:.12g} U={u:.12g} Ma_proxy={mach:.6g} "
      f"Cthermal={cth:.6g} Cjet={cjet:.6g} Ctotal={ctot:.6g}")
if ctot > 0.80:
    raise SystemExit(f"[0493x24x] unresolved gas flight: {ctot:.8g} > 0.80")
PY

mkdir -p "$BASE_ROOT" || exit 2
PLAN="$BASE_ROOT/campaign_plan.tsv"
STATUS="$BASE_ROOT/campaign_status.tsv"

printf "targetFr\tjetSpeed\tdt\tkBT_over_m\tgasKBT\trelaxSteps\tforcedSteps\tanalysisStart\tanalysisEnd\tbaseState\n" > "$PLAN"
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
  "$TARGET_FRM_SATO" "$JET_SPEED" "$DT" "$KM" "$GAS_KBT" \
  "$RELAX_STEPS" "$FORCED_STEPS" "$ANALYSIS_START_STEP" "$FORCED_STEPS" "$BASE_STATE" >> "$PLAN"
printf "stage\tstatus\tpath\n" > "$STATUS"

RELAX_ROOT="$BASE_ROOT/relax"
RELAX_LABEL="0493x24x_Fr075_KM2_relax"

echo "================================================================"
echo "[0493x24x] HIGHER-LOAD SHORT PROBE"
echo "[0493x24x] targetFr=$TARGET_FRM_SATO U=$JET_SPEED"
echo "[0493x24x] dt=$DT kBT/m=$KM gasKBT=$GAS_KBT"
echo "[0493x24x] relax=$RELAX_STEPS steps; forced=$FORCED_STEPS steps"
echo "================================================================"

# ---- A. Relax at the new gas thermal state -----------------------------------
RESTART=1 \
RESTART_STATE="$BASE_STATE" \
RESTART_FROM_STEP=2000 \
RESTART_TAG="relax_KM2" \
CAMPAIGN_ROOT="$RELAX_ROOT" \
CASE_LABEL="$RELAX_LABEL" \
TARGET_H_OVER_D="$TARGET_H_OVER_D" \
GAS_KBT="$GAS_KBT" \
GAS_KBT_OVER_MASS_REF="$KM" \
DT="$DT" \
DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
STEPS="$RELAX_STEPS" \
ANALYSIS_START_STEP="$((RELAX_STEPS/2))" \
ANALYSIS_END_STEP="$RELAX_STEPS" \
DUMP_STATE_EVERY="$RELAX_STEPS" \
DUMP_ROLE_FILTER=all \
SUMMARY_EVERY="$SUMMARY_EVERY" \
PREFLIGHT_ONLY=1 \
LIVE_PROGRESS="$LIVE_PROGRESS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
bash "$RELAX_RUNNER" || exit $?

RESTART=1 \
RESTART_STATE="$BASE_STATE" \
RESTART_FROM_STEP=2000 \
RESTART_TAG="relax_KM2" \
CAMPAIGN_ROOT="$RELAX_ROOT" \
CASE_LABEL="$RELAX_LABEL" \
TARGET_H_OVER_D="$TARGET_H_OVER_D" \
GAS_KBT="$GAS_KBT" \
GAS_KBT_OVER_MASS_REF="$KM" \
DT="$DT" \
DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
STEPS="$RELAX_STEPS" \
ANALYSIS_START_STEP="$((RELAX_STEPS/2))" \
ANALYSIS_END_STEP="$RELAX_STEPS" \
DUMP_STATE_EVERY="$RELAX_STEPS" \
DUMP_ROLE_FILTER=all \
SUMMARY_EVERY="$SUMMARY_EVERY" \
PREFLIGHT_ONLY=0 \
LIVE_PROGRESS="$LIVE_PROGRESS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
bash "$RELAX_RUNNER" || exit $?

RELAX_STATE="$RELAX_ROOT/restart_relax_KM2/output/state_step_00001000.smpcd"
[[ -s "$RELAX_STATE" ]] || {
  echo "[0493x24x] ERROR missing relaxed state: $RELAX_STATE" >&2
  exit 2
}
printf "relax\tPASS\t%s\n" "$RELAX_STATE" >> "$STATUS"

# ---- B. Forced short probe ---------------------------------------------------
FORCED_ROOT="$BASE_ROOT/forced"
FORCED_LABEL="0493x24x_Fr075_KM2_forced"

RESTART=1 \
RESTART_STATE="$RELAX_STATE" \
RESTART_FROM_STEP="$RELAX_STEPS" \
RESTART_TAG="forced_Fr075" \
CAMPAIGN_ROOT="$FORCED_ROOT" \
CASE_LABEL="$FORCED_LABEL" \
TARGET_H_OVER_D="$TARGET_H_OVER_D" \
TARGET_FRM_SATO="$TARGET_FRM_SATO" \
JET_SPEED="$JET_SPEED" \
GAS_KBT="$GAS_KBT" \
GAS_KBT_OVER_MASS_REF="$KM" \
DT="$DT" \
DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
JET_RAMP_START_TIME=0.0 \
JET_RAMP_END_TIME=0.20 \
JET_RAMP_INITIAL_FACTOR=0.0 \
JET_RAMP_FINAL_FACTOR=1.0 \
INACTIVE_SLOTS_CELL_FRACTION="$INACTIVE_SLOTS_CELL_FRACTION" \
STEPS="$FORCED_STEPS" \
ANALYSIS_START_STEP="$ANALYSIS_START_STEP" \
ANALYSIS_END_STEP="$FORCED_STEPS" \
DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
DUMP_ROLE_FILTER=all \
SUMMARY_EVERY="$SUMMARY_EVERY" \
RECORD_EVERY="$RECORD_EVERY" \
PREFLIGHT_ONLY=1 \
LIVE_PROGRESS="$LIVE_PROGRESS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
bash "$FORCED_RUNNER" || exit $?

RESTART=1 \
RESTART_STATE="$RELAX_STATE" \
RESTART_FROM_STEP="$RELAX_STEPS" \
RESTART_TAG="forced_Fr075" \
CAMPAIGN_ROOT="$FORCED_ROOT" \
CASE_LABEL="$FORCED_LABEL" \
TARGET_H_OVER_D="$TARGET_H_OVER_D" \
TARGET_FRM_SATO="$TARGET_FRM_SATO" \
JET_SPEED="$JET_SPEED" \
GAS_KBT="$GAS_KBT" \
GAS_KBT_OVER_MASS_REF="$KM" \
DT="$DT" \
DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
JET_RAMP_START_TIME=0.0 \
JET_RAMP_END_TIME=0.20 \
JET_RAMP_INITIAL_FACTOR=0.0 \
JET_RAMP_FINAL_FACTOR=1.0 \
INACTIVE_SLOTS_CELL_FRACTION="$INACTIVE_SLOTS_CELL_FRACTION" \
STEPS="$FORCED_STEPS" \
ANALYSIS_START_STEP="$ANALYSIS_START_STEP" \
ANALYSIS_END_STEP="$FORCED_STEPS" \
DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
DUMP_ROLE_FILTER=all \
SUMMARY_EVERY="$SUMMARY_EVERY" \
RECORD_EVERY="$RECORD_EVERY" \
PREFLIGHT_ONLY=0 \
LIVE_PROGRESS="$LIVE_PROGRESS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
bash "$FORCED_RUNNER" || exit $?

printf "forced\tPASS\t%s\n" "$FORCED_ROOT/restart_forced_Fr075" >> "$STATUS"

echo
echo "================================================================"
echo "[0493x24x] COMPLETE"
echo "[0493x24x] forced root:"
echo "  $FORCED_ROOT/restart_forced_Fr075"
echo "[0493x24x] This is an exploratory higher-load point: Fr changed AND kBT/m changed."
echo "================================================================"

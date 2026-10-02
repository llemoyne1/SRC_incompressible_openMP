#!/usr/bin/env bash
# =============================================================================
# 0493x24w — continue ONLY the high-load x24v endpoint (Fr'_m=0.6603645)
#
# Purpose
#   The low-Fr endpoint is already close to stationary, while the high-Fr case
#   still shows substantial late-time drift at global t~4.  Extend only the
#   high-load branch to test whether h/D approaches a plateau.
#
# Continuation:
#   source = x24v high-Fr checkpoint at local step 5000
#   global history = x24u t=0..2 + x24v t=2..4
#   this segment    = t=4..6 by default
#
# Fixed branch:
#   dt = 4e-4
#   kBT_g/m_g = 3.2 (M033)
#   H/D = 0.8
#   same density ratio / gravity / sigma / closure chain
#
# No re-ramp on restart (handled by parent x24i/x14at restart path).
# No C++/CUDA modification.
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SEED="${SEED:-493205}"

FORCED_RUNNER="scripts/run_0493x24i_sato_short_nozzle_forced.sh"

SRC_ROOT="${SRC_ROOT:-runs/0493x24v_sato_stageA_two_endpoints_extend_seed${SEED}/Fr0p660364520158346}"
SRC_STATE="${SRC_STATE:-$SRC_ROOT/restart_extend_t2_to_t4/output/state_step_00005000.smpcd}"

OUT_ROOT="${OUT_ROOT:-runs/0493x24w_sato_stageA_Fr0p660_extend_t4_to_t6_seed${SEED}}"

DT="${DT:-0.0004}"
KM="${KM:-3.2}"
GAS_KBT="${GAS_KBT:-0.003755265797392177}"

TARGET_H_OVER_D="${TARGET_H_OVER_D:-0.8}"
TARGET_FRM_SATO="${TARGET_FRM_SATO:-0.660364520158346}"
JET_SPEED="${JET_SPEED:-5.9694820421182504}"

DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-800000}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-24.0}"

FROM_GLOBAL_STEP="${FROM_GLOBAL_STEP:-10000}"
SEGMENT_T="${SEGMENT_T:-2.0}"

SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
RECORD_EVERY="${RECORD_EVERY:-20}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2500}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

[[ -f "$FORCED_RUNNER" ]] || {
  echo "[0493x24w] ERROR missing runner: $FORCED_RUNNER" >&2
  exit 2
}

[[ -s "$SRC_STATE" ]] || {
  echo "[0493x24w] ERROR missing high-Fr x24v checkpoint:" >&2
  echo "  $SRC_STATE" >&2
  echo "[0493x24w] Refusing to guess another checkpoint." >&2
  exit 2
}

read -r SEGMENT_STEPS ANALYSIS_START <<<"$(python3 - "$DT" "$SEGMENT_T" <<'PY'
import sys
dt=float(sys.argv[1]); T=float(sys.argv[2])
n=round(T/dt)
if abs(n*dt-T)>1e-12:
    raise SystemExit("SEGMENT_T is not an integer number of steps")
# Analyze the second half of this continuation.
print(int(n), int(round(0.50*n)))
PY
)" || exit 2

GLOBAL_END_STEP=$((FROM_GLOBAL_STEP + SEGMENT_STEPS))

mkdir -p "$OUT_ROOT" || exit 2

PLAN="$OUT_ROOT/campaign_plan.tsv"
STATUS="$OUT_ROOT/campaign_status.tsv"

printf "targetFr\tjetSpeed\tdt\tkBT_over_m\tfromGlobalStep\tsegmentSteps\tglobalEndStep\tsegmentT\tglobalTStart\tglobalTEnd\tsourceState\n" > "$PLAN"
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
  "$TARGET_FRM_SATO" "$JET_SPEED" "$DT" "$KM" \
  "$FROM_GLOBAL_STEP" "$SEGMENT_STEPS" "$GLOBAL_END_STEP" "$SEGMENT_T" \
  "$(awk -v n="$FROM_GLOBAL_STEP" -v d="$DT" 'BEGIN{printf "%.9g",n*d}')" \
  "$(awk -v n="$GLOBAL_END_STEP" -v d="$DT" 'BEGIN{printf "%.9g",n*d}')" \
  "$SRC_STATE" >> "$PLAN"

printf "stage\tstatus\troot\n" > "$STATUS"

CASE_LABEL="0493x24w_M033_Fr0p660_extend_t4_to_t6"

echo "================================================================"
echo " 0493x24w — HIGH-FR CONTINUATION ONLY"
echo "================================================================"
echo "[0493x24w] source=$SRC_STATE"
echo "[0493x24w] targetFr=$TARGET_FRM_SATO Ujet=$JET_SPEED"
echo "[0493x24w] dt=$DT kBT/m=$KM"
echo "[0493x24w] local segment steps=$SEGMENT_STEPS"
echo "[0493x24w] global step $FROM_GLOBAL_STEP -> $GLOBAL_END_STEP"
echo "[0493x24w] physical time $(awk -v n="$FROM_GLOBAL_STEP" -v d="$DT" 'BEGIN{printf "%.6g",n*d}') -> $(awk -v n="$GLOBAL_END_STEP" -v d="$DT" 'BEGIN{printf "%.6g",n*d}')"
echo "[0493x24w] analysis local ${ANALYSIS_START}:${SEGMENT_STEPS}"
echo "================================================================"

# Preflight
RESTART=1 \
RESTART_STATE="$SRC_STATE" \
RESTART_FROM_STEP="$FROM_GLOBAL_STEP" \
RESTART_TAG="extend_t4_to_t6" \
CAMPAIGN_ROOT="$OUT_ROOT" \
CASE_LABEL="$CASE_LABEL" \
TARGET_H_OVER_D="$TARGET_H_OVER_D" \
TARGET_FRM_SATO="$TARGET_FRM_SATO" \
JET_SPEED="$JET_SPEED" \
GAS_KBT="$GAS_KBT" \
GAS_KBT_OVER_MASS_REF="$KM" \
DT="$DT" \
DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
INACTIVE_SLOTS_CELL_FRACTION="$INACTIVE_SLOTS_CELL_FRACTION" \
STEPS="$SEGMENT_STEPS" \
ANALYSIS_START_STEP="$ANALYSIS_START" \
ANALYSIS_END_STEP="$SEGMENT_STEPS" \
DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
DUMP_ROLE_FILTER=all \
SUMMARY_EVERY="$SUMMARY_EVERY" \
RECORD_EVERY="$RECORD_EVERY" \
PREFLIGHT_ONLY=1 \
LIVE_PROGRESS="$LIVE_PROGRESS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
CLEAN_RUN_ROOT=1 \
bash "$FORCED_RUNNER"

rc=$?
if [[ "$rc" != "0" ]]; then
  printf "preflight\tFAIL\t%s\n" "$OUT_ROOT" >> "$STATUS"
  exit "$rc"
fi
printf "preflight\tPASS\t%s\n" "$OUT_ROOT" >> "$STATUS"

# Production
RESTART=1 \
RESTART_STATE="$SRC_STATE" \
RESTART_FROM_STEP="$FROM_GLOBAL_STEP" \
RESTART_TAG="extend_t4_to_t6" \
CAMPAIGN_ROOT="$OUT_ROOT" \
CASE_LABEL="$CASE_LABEL" \
TARGET_H_OVER_D="$TARGET_H_OVER_D" \
TARGET_FRM_SATO="$TARGET_FRM_SATO" \
JET_SPEED="$JET_SPEED" \
GAS_KBT="$GAS_KBT" \
GAS_KBT_OVER_MASS_REF="$KM" \
DT="$DT" \
DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
INACTIVE_SLOTS_CELL_FRACTION="$INACTIVE_SLOTS_CELL_FRACTION" \
STEPS="$SEGMENT_STEPS" \
ANALYSIS_START_STEP="$ANALYSIS_START" \
ANALYSIS_END_STEP="$SEGMENT_STEPS" \
DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
DUMP_ROLE_FILTER=all \
SUMMARY_EVERY="$SUMMARY_EVERY" \
RECORD_EVERY="$RECORD_EVERY" \
PREFLIGHT_ONLY=0 \
LIVE_PROGRESS="$LIVE_PROGRESS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
CLEAN_RUN_ROOT=1 \
bash "$FORCED_RUNNER"

rc=$?
if [[ "$rc" != "0" ]]; then
  printf "production\tFAIL\t%s\n" "$OUT_ROOT" >> "$STATUS"
  exit "$rc"
fi

printf "production\tPASS\t%s\n" "$OUT_ROOT" >> "$STATUS"

echo
echo "================================================================"
echo "[0493x24w] COMPLETE"
echo "[0493x24w] root=$OUT_ROOT"
echo "[0493x24w] Inspect late h/D drift over local ${ANALYSIS_START}:${SEGMENT_STEPS}"
echo "[0493x24w] If drift remains large at global t~6, do not assume stationarity."
echo "================================================================"

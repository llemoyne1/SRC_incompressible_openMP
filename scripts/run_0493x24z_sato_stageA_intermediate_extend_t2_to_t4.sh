#!/usr/bin/env bash
# =============================================================================
# 0493x24z — extend the TWO INTERMEDIATE Sato cases from forced t=2 to t=4
#
# Purpose
#   The v3 dense-time analysis showed that Fr'=0.40 and 0.55 were available
#   only over forced time 0..2, whereas Fr'=0.25 reaches t=4 and Fr'=0.660
#   reaches t=6. Extend only the intermediate cases to forced t=4 so the
#   h/D-vs-Fr comparison uses more comparable post-transient windows.
#
# Cases:
#   Fr'_m,target = 0.40
#   Fr'_m,target = 0.55
#
# Exact continuation of x24u:
#   dt        = 4e-4
#   kBT_g/m_g = 3.2 (M033 branch)
#   H/D       = 0.8
#   same density ratio / gravity / sigma / closure chain
#   restart from x24u state_step_00005000.smpcd
#
# Segment:
#   forced time 2 -> 4
#   5000 additional steps/case
#
# The parent x24i/x14at restart path disables inlet re-ramping automatically.
# No C++/CUDA modification.
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SEED="${SEED:-493205}"

FORCED_RUNNER="scripts/run_0493x24i_sato_short_nozzle_forced.sh"

SRC_BASE="${SRC_BASE:-runs/0493x24u_sato_stageA_short_M033_seed${SEED}}"
OUT_BASE="${OUT_BASE:-runs/0493x24z_sato_stageA_intermediate_extend_seed${SEED}}"

DT="${DT:-0.0004}"
KM="${KM:-3.2}"
GAS_KBT="${GAS_KBT:-0.003755265797392177}"

TARGET_H_OVER_D="${TARGET_H_OVER_D:-0.8}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-800000}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-24.0}"

FROM_STEP="${FROM_STEP:-5000}"
SEGMENT_T="${SEGMENT_T:-2.0}"

SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
RECORD_EVERY="${RECORD_EVERY:-20}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2500}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

REF_FR="0.660364520158346"
REF_U="5.9694820421182504"

CASES=(
  "0.40"
  "0.55"
)

[[ -f "$FORCED_RUNNER" ]] || {
  echo "[0493x24z] ERROR missing forced runner: $FORCED_RUNNER" >&2
  exit 2
}

read -r SEGMENT_STEPS ANALYSIS_START <<<"$(python3 - "$DT" "$SEGMENT_T" <<'PY'
import sys
dt=float(sys.argv[1]); T=float(sys.argv[2])
n=round(T/dt)
if abs(n*dt-T)>1e-12:
    raise SystemExit("SEGMENT_T is not an integer number of steps")
# Analyze the second half of continuation: forced t=3..4 by default.
print(int(n), int(round(0.50*n)))
PY
)" || exit 2

mkdir -p "$OUT_BASE" || exit 2
PLAN="$OUT_BASE/campaign_plan.tsv"
STATUS="$OUT_BASE/campaign_status.tsv"

printf "case\ttargetFr\tjetSpeed\tdt\tkBT_over_m\tfromStep\tsegmentSteps\tforcedTStart\tforcedTEnd\tsourceState\n" > "$PLAN"
printf "case\tstage\tstatus\troot\n" > "$STATUS"

echo "================================================================"
echo " 0493x24z — INTERMEDIATE SATO CONTINUATIONS"
echo "================================================================"
echo "[0493x24z] x24u source = $SRC_BASE"
echo "[0493x24z] dt=$DT kBT/m=$KM"
echo "[0493x24z] local segment steps=$SEGMENT_STEPS"
echo "[0493x24z] forced time 2 -> 4"
echo "[0493x24z] local analysis window=${ANALYSIS_START}:${SEGMENT_STEPS}"
echo "[0493x24z] cases: ${CASES[*]}"
echo "================================================================"

for FR in "${CASES[@]}"; do

  SAFE_FR="${FR//./p}"
  TAG="Fr${SAFE_FR}"

  U="$(python3 - "$FR" "$REF_FR" "$REF_U" <<'PY'
import math,sys
fr,fr0,u0=map(float,sys.argv[1:])
print(f"{u0*math.sqrt(fr/fr0):.17g}")
PY
)" || exit 2

  SRC_STATE="$SRC_BASE/$TAG/restart_short_stageA_screen/output/state_step_00005000.smpcd"

  if [[ ! -s "$SRC_STATE" ]]; then
    echo "[0493x24z] ERROR missing x24u checkpoint for $TAG:" >&2
    echo "  $SRC_STATE" >&2
    echo "[0493x24z] Refusing to guess another checkpoint." >&2
    exit 2
  fi

  CASE_ROOT="$OUT_BASE/$TAG"
  CASE_LABEL="0493x24z_M033_${TAG}_extend_t2_to_t4"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t2.0\t4.0\t%s\n" \
    "$TAG" "$FR" "$U" "$DT" "$KM" "$FROM_STEP" "$SEGMENT_STEPS" "$SRC_STATE" >> "$PLAN"

  echo
  echo "----------------------------------------------------------------"
  echo "[0493x24z] CASE=$TAG targetFr=$FR Ujet=$U"
  echo "[0493x24z] source=$SRC_STATE"
  echo "[0493x24z] output=$CASE_ROOT"
  echo "----------------------------------------------------------------"

  # Exact preflight.
  RESTART=1 \
  RESTART_STATE="$SRC_STATE" \
  RESTART_FROM_STEP="$FROM_STEP" \
  RESTART_TAG="extend_t2_to_t4" \
  CAMPAIGN_ROOT="$CASE_ROOT" \
  CASE_LABEL="$CASE_LABEL" \
  TARGET_H_OVER_D="$TARGET_H_OVER_D" \
  TARGET_FRM_SATO="$FR" \
  JET_SPEED="$U" \
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
    printf "%s\tpreflight\tFAIL\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"
    exit "$rc"
  fi
  printf "%s\tpreflight\tPASS\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"

  # Production.
  RESTART=1 \
  RESTART_STATE="$SRC_STATE" \
  RESTART_FROM_STEP="$FROM_STEP" \
  RESTART_TAG="extend_t2_to_t4" \
  CAMPAIGN_ROOT="$CASE_ROOT" \
  CASE_LABEL="$CASE_LABEL" \
  TARGET_H_OVER_D="$TARGET_H_OVER_D" \
  TARGET_FRM_SATO="$FR" \
  JET_SPEED="$U" \
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
    printf "%s\tproduction\tFAIL\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"
    exit "$rc"
  fi

  printf "%s\tproduction\tPASS\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"
  echo "[0493x24z] CASE=$TAG COMPLETE"
done

echo
echo "================================================================"
echo "[0493x24z] CAMPAIGN COMPLETE"
echo "[0493x24z] root=$OUT_BASE"
echo "[0493x24z] Add these V3 analyzer segments with forced-time offset 2.0:"
echo "  0.40:2.0:$OUT_BASE/Fr0p40/restart_extend_t2_to_t4"
echo "  0.55:2.0:$OUT_BASE/Fr0p55/restart_extend_t2_to_t4"
echo "================================================================"

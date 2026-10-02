#!/usr/bin/env bash
# =============================================================================
# 0493x24u — SHORT SATO Stage-A momentum-response screening
#
# Scientific question
#   Before investing in low-Mach / small-dt simulations, test the working
#   hypothesis that the cavity response is controlled to leading order by the
#   incident momentum loading:
#
#       h/D ~ f(Fr'_m)
#
#   while gas compressibility is treated as a second-order imperfection.
#
# This is deliberately a SHORT SCREENING campaign, not yet a quantitative
# Sato validation campaign.
#
# Fixed numerical/physical branch
#   - x24 short-nozzle corrected H/D = 0.8 geometry
#   - water/air density ratio
#   - M033 thermal state: kBT_g/m_g = 3.2
#   - dt = 4e-4
#   - same common thermally relaxed state for every forced case
#   - same Bo, sigma, gravity, topology and closure chain
#
# Varied parameter
#   TARGET_FRM_SATO = 0.25, 0.40, 0.55, 0.660364520158346
#   JET_SPEED is derived from Fr'_m ∝ U^2.
#
# Default forced duration
#   T_FORCED = 2.0  => 5000 steps/case at dt=4e-4.
#
# Interpretation
#   Success at this stage means a clean monotonic / approximately linear
#   h/D response versus the realized incident loading.  Stationarity is NOT
#   assumed; all cases are compared over the same physical time and common
#   late-time window.
#
# No C++/CUDA modification.
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SEED="${SEED:-493205}"
DT="${DT:-0.0004}"
KM="${KM:-3.2}"
GAS_MASS="${GAS_MASS:-0.0011735205616850552}"
GAS_KBT="${GAS_KBT:-0.003755265797392177}"
TARGET_H_OVER_D="${TARGET_H_OVER_D:-0.8}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-800000}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-24.0}"

T_FORCED="${T_FORCED:-2.0}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
RECORD_EVERY="${RECORD_EVERY:-20}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2500}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

FORCED_RUNNER="scripts/run_0493x24i_sato_short_nozzle_forced.sh"

# Reuse the already-qualified M033 zero-jet relaxed state from x24q.
COMMON_RELAX_STATE="${COMMON_RELAX_STATE:-runs/0493x24q_sato_mach_stationarity_seed${SEED}/M033_relax/restart_relax/output/state_step_00001000.smpcd}"

BASE_ROOT="${BASE_ROOT:-runs/0493x24u_sato_stageA_short_M033_seed${SEED}}"

# Reference point already used in the strict Sato H/D=0.8 setup.
REF_FR="${REF_FR:-0.660364520158346}"
REF_U="${REF_U:-5.9694820421182504}"

# Four screening levels. Override from shell if desired.
FR_TARGETS="${FR_TARGETS:-0.25 0.40 0.55 0.660364520158346}"

if [[ ! -f "$FORCED_RUNNER" ]]; then
  echo "[0493x24u] ERROR missing forced runner: $FORCED_RUNNER" >&2
  exit 2
fi

if [[ ! -f "$COMMON_RELAX_STATE" ]]; then
  echo "[0493x24u] ERROR missing common M033 relaxed state:" >&2
  echo "  $COMMON_RELAX_STATE" >&2
  echo "[0493x24u] Do not substitute another state silently." >&2
  exit 2
fi

read -r FORCED_STEPS ANALYSIS_START <<<"$(python3 - "$DT" "$T_FORCED" <<'PY'
import sys
dt=float(sys.argv[1]); T=float(sys.argv[2])
n=round(T/dt)
if abs(n*dt-T) > 1e-12:
    raise SystemExit("T_FORCED is not an integer number of steps")
print(int(n), int(round(0.75*n)))
PY
)" || exit 2

mkdir -p "$BASE_ROOT" || exit 2
PLAN="$BASE_ROOT/campaign_plan.tsv"
STATUS="$BASE_ROOT/campaign_status.tsv"

printf "case\ttargetFr\tjetSpeed\tMaProxy\tdt\tkBT_over_m\tTforced\tsteps\tanalysisStart\tanalysisEnd\tcommonState\n" > "$PLAN"
printf "case\tstage\tstatus\troot\n" > "$STATUS"

echo "================================================================"
echo " 0493x24u — SHORT SATO MOMENTUM-RESPONSE SCREENING"
echo "================================================================"
echo "[0493x24u] common state = $COMMON_RELAX_STATE"
echo "[0493x24u] dt=$DT  kBT/m=$KM  gasKBT=$GAS_KBT"
echo "[0493x24u] Tforced=$T_FORCED -> steps=$FORCED_STEPS"
echo "[0493x24u] common late window=${ANALYSIS_START}:${FORCED_STEPS}"
echo "[0493x24u] Fr targets: $FR_TARGETS"
echo "[0493x24u] LiveVis enabled=$LIVE_VIS_ENABLE; repository livevis_control.kv remains user-owned."
echo "================================================================"

for FR in $FR_TARGETS; do

  read -r U MACH CTH CJET CCOMB <<<"$(python3 - "$FR" "$REF_FR" "$REF_U" "$KM" "$DT" <<'PY'
import math,sys
fr,fr0,u0,km,dt=map(float,sys.argv[1:])
h=1.0/256.0
if fr <= 0 or fr0 <= 0:
    raise SystemExit("Fr targets must be positive")
# Current runner definition has Fr'_m proportional to U^2.
u=u0*math.sqrt(fr/fr0)
mach=u/math.sqrt(km)
cth=math.sqrt(km)*dt/h
cjet=u*dt/h
print(f"{u:.17g}", f"{mach:.12g}", f"{cth:.12g}", f"{cjet:.12g}", f"{cth+cjet:.12g}")
PY
)" || exit 2

  if ! python3 - "$CCOMB" <<'PY'
import sys
x=float(sys.argv[1])
raise SystemExit(0 if x <= 0.80 else 1)
PY
  then
    echo "[0493x24u] ERROR unresolved gas flight for Fr=$FR: Cthermal+Cjet=$CCOMB > 0.80" >&2
    exit 2
  fi

  SAFE_FR="${FR//./p}"
  TAG="Fr${SAFE_FR}"
  RUN_ROOT="$BASE_ROOT/$TAG"
  CASE_LABEL="0493x24u_M033_${TAG}"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$TAG" "$FR" "$U" "$MACH" "$DT" "$KM" "$T_FORCED" "$FORCED_STEPS" \
    "$ANALYSIS_START" "$FORCED_STEPS" "$COMMON_RELAX_STATE" >> "$PLAN"

  echo
  echo "----------------------------------------------------------------"
  echo "[0493x24u] CASE=$TAG"
  echo "[0493x24u] targetFr=$FR Ujet=$U Ma_proxy=$MACH"
  echo "[0493x24u] flights: thermal=$CTH jet=$CJET total=$CCOMB"
  echo "[0493x24u] root=$RUN_ROOT"
  echo "----------------------------------------------------------------"

  # Preflight using the exact production runner and exact case parameters.
  RESTART=1 \
  RESTART_STATE="$COMMON_RELAX_STATE" \
  RESTART_FROM_STEP=1000 \
  RESTART_TAG="short_stageA_screen" \
  CAMPAIGN_ROOT="$RUN_ROOT" \
  CASE_LABEL="$CASE_LABEL" \
  TARGET_H_OVER_D="$TARGET_H_OVER_D" \
  TARGET_FRM_SATO="$FR" \
  JET_SPEED="$U" \
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
  ANALYSIS_START_STEP="$ANALYSIS_START" \
  ANALYSIS_END_STEP="$FORCED_STEPS" \
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
    printf "%s\tpreflight\tFAIL\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
    exit "$rc"
  fi
  printf "%s\tpreflight\tPASS\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"

  # Production.
  RESTART=1 \
  RESTART_STATE="$COMMON_RELAX_STATE" \
  RESTART_FROM_STEP=1000 \
  RESTART_TAG="short_stageA_screen" \
  CAMPAIGN_ROOT="$RUN_ROOT" \
  CASE_LABEL="$CASE_LABEL" \
  TARGET_H_OVER_D="$TARGET_H_OVER_D" \
  TARGET_FRM_SATO="$FR" \
  JET_SPEED="$U" \
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
  ANALYSIS_START_STEP="$ANALYSIS_START" \
  ANALYSIS_END_STEP="$FORCED_STEPS" \
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
    printf "%s\tproduction\tFAIL\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
    exit "$rc"
  fi

  printf "%s\tproduction\tPASS\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
  echo "[0493x24u] CASE=$TAG COMPLETE"
done

echo
echo "================================================================"
echo "[0493x24u] CAMPAIGN COMPLETE"
echo "[0493x24u] root=$BASE_ROOT"
echo "[0493x24u] plan=$PLAN"
echo "[0493x24u] status=$STATUS"
echo
echo "[0493x24u] Screening interpretation:"
echo "  1) compare h/D at the same physical time/window;"
echo "  2) inspect late dh/dt for every case;"
echo "  3) reconstruct realized incident Fr'_m from the near-interface gas field;"
echo "  4) only if a coherent h/D-vs-Fr'_m trend appears, invest in longer runs."
echo "================================================================"

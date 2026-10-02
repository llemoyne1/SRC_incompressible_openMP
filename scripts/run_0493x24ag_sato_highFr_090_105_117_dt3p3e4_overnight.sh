#!/usr/bin/env bash
# Generated campaign runner. No C++/CUDA source modification.
# Uses a temporary runner copy only to distinguish "load a common relaxed state"
# from a physical forced-flow continuation, so that the initial inlet ramp is
# preserved on the first forced segment.

# =============================================================================
# 0493x24ag — SATO HIGH-Fr COMPLEMENT, COMMON dt=3.3e-4
#
# Target modified Froude numbers:
#   Fr' = 0.90, 1.05, 1.17
#
# Scientific contract:
#   - one common KM2 branch: kBT_g/m_g = 2.0
#   - one common timestep: dt = 3.3e-4
#   - fresh zero-jet relaxation at this dt before the forced cases
#   - all three forced cases start from exactly the same resulting relaxed dump
#   - one initial ramp t=0 -> 0.2, then uninterrupted forcing
#   - no intermediate restart in article data
#   - rho1,rho2,ux,uy recorded
#   - safety dumps only
#
# Default forced length: 18000 steps => T = 5.94
# Default article window: t >= 1.0
#
# Override example:
#   FORCED_STEPS=24242 gives T ~ 8 at dt=3.3e-4.
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SEED="${SEED:-493205}"
BASE_RUNNER="${BASE_RUNNER:-scripts/run_0493x24d_sato_airwater_density_probe.sh}"
PATCHED_RUNNER="${PATCHED_RUNNER:-tools/run_0493x24ag_common_state_ramped_case_tmp.sh}"

BASE_COMMON_STATE="${BASE_COMMON_STATE:-runs/0493x24x_sato_Fr075_KM2_short_seed${SEED}/relax/restart_relax_KM2/output/state_step_00001000.smpcd}"
BASE_ROOT="${BASE_ROOT:-runs/0493x24ag_sato_highFr_KM2_dt3p3e4_seed${SEED}}"

DT="${DT:-0.00033}"
GAS_KBT_OVER_MASS_REF="${GAS_KBT_OVER_MASS_REF:-2.0}"
GAS_KBT="${GAS_KBT:-0.0023470411233701104}"

TARGET_H_OVER_D="${TARGET_H_OVER_D:-0.8}"
BATH_HEIGHT="${BATH_HEIGHT:-0.81640625}"
NOZZLE_LENGTH_CELLS="${NOZZLE_LENGTH_CELLS:-31}"
NOZZLE_INNER_WIDTH_CELLS="${NOZZLE_INNER_WIDTH_CELLS:-20}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-800000}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-24.0}"

RELAX_STEPS="${RELAX_STEPS:-6000}"
FORCED_STEPS="${FORCED_STEPS:-18000}"
ARTICLE_T_START="${ARTICLE_T_START:-1.0}"

RAMP_START="${RAMP_START:-0.0}"
RAMP_END="${RAMP_END:-0.20}"

RECORD_EVERY="${RECORD_EVERY:-20}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-3000}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

MODE="${MODE:-production}"
START_CASE="${START_CASE:-Fr0p90}"

CASES=(
  "Fr0p90 0.90"
  "Fr1p05 1.05"
  "Fr1p17 1.17"
)

[[ -f "$BASE_RUNNER" ]] || { echo "[0493x24ag] ERROR missing $BASE_RUNNER" >&2; exit 2; }
[[ -s "$BASE_COMMON_STATE" ]] || { echo "[0493x24ag] ERROR missing base state $BASE_COMMON_STATE" >&2; exit 2; }

case "$MODE" in preflight|production) ;; *) echo "[0493x24ag] ERROR MODE=$MODE" >&2; exit 2;; esac

mkdir -p "$(dirname "$PATCHED_RUNNER")" "$BASE_ROOT" || exit 2

python3 - "$BASE_RUNNER" "$PATCHED_RUNNER" <<'PY_PATCH'
from pathlib import Path
import sys
src,dst=map(Path,sys.argv[1:3])
txt=src.read_text()
old='''  # Do not re-ramp the inlet on a continuation.
  JET_RAMP_START_TIME=0.0; JET_RAMP_END_TIME=0.0; JET_RAMP_INITIAL_FACTOR=1.0; JET_RAMP_FINAL_FACTOR=1.0
  INLET_RAMP_ENABLE=false
else
  RESTART_FROM_STEP=0
  INLET_RAMP_ENABLE=true
fi
'''
new='''  # 0493x24ag: distinguish state loading from forced-flow continuation.
  if [[ "${FORCE_RAMP_ON_RESTART:-0}" == "1" ]]; then
    INLET_RAMP_ENABLE=true
    echo "[0493x24ag] common-state start: preserving inlet ramp ${JET_RAMP_START_TIME}->${JET_RAMP_END_TIME}"
  else
    JET_RAMP_START_TIME=0.0
    JET_RAMP_END_TIME=0.0
    JET_RAMP_INITIAL_FACTOR=1.0
    JET_RAMP_FINAL_FACTOR=1.0
    INLET_RAMP_ENABLE=false
  fi
else
  RESTART_FROM_STEP=0
  INLET_RAMP_ENABLE=true
fi
'''
if txt.count(old) != 1:
    raise SystemExit("[0493x24ag] ERROR restart/ramp block not uniquely found; refusing patch")
dst.write_text(txt.replace(old,new))
dst.chmod(0o755)
print(f"[0493x24ag] temporary runner: {dst}")
PY_PATCH

RELAX_ROOT="$BASE_ROOT/common_relax_dt3p3e4"
RELAX_FINAL_STATE="$RELAX_ROOT/restart_common_dt_relax/output/state_step_$(printf '%08d' "$RELAX_STEPS").smpcd"

ARTICLE_START_STEP="$(python3 - "$ARTICLE_T_START" "$DT" <<'PY'
import sys
print(int(round(float(sys.argv[1])/float(sys.argv[2]))))
PY
)"

PLAN="$BASE_ROOT/campaign_plan.tsv"
STATUS="$BASE_ROOT/campaign_status.tsv"
printf "case\ttargetFr\tjetSpeed\tdt\tsteps\tphysicalTime\tarticleStartStep\tcommonState\n" > "$PLAN"
printf "case\tstage\tstatus\troot\n" > "$STATUS"

echo "================================================================"
echo " 0493x24ag — HIGH-Fr SATO COMPLEMENT"
echo " Fr' = 0.90, 1.05, 1.17"
echo " dt = $DT ; kBTg/mg = $GAS_KBT_OVER_MASS_REF"
echo " relax = $RELAX_STEPS steps"
echo " forced = $FORCED_STEPS steps"
echo "================================================================"

run_relax() {
  local preflight="$1"
  FORCE_RAMP_ON_RESTART=0 \
  RESTART=1 \
  RESTART_STATE="$BASE_COMMON_STATE" \
  RESTART_FROM_STEP=0 \
  RESTART_TAG="common_dt_relax" \
  CAMPAIGN_MODE=case \
  CAMPAIGN_ROOT="$RELAX_ROOT" \
  CASE_LABEL="0493x24ag_common_relax_dt3p3e4" \
  TARGET_H_OVER_D="$TARGET_H_OVER_D" \
  TARGET_FRM_SATO=0.0 \
  JET_SPEED=0.0 \
  GAS_KBT="$GAS_KBT" \
  GAS_KBT_OVER_MASS_REF="$GAS_KBT_OVER_MASS_REF" \
  DT="$DT" \
  BATH_HEIGHT="$BATH_HEIGHT" \
  NOZZLE_INNER_WIDTH_CELLS="$NOZZLE_INNER_WIDTH_CELLS" \
  NOZZLE_LENGTH_CELLS="$NOZZLE_LENGTH_CELLS" \
  DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
  INACTIVE_SLOTS_CELL_FRACTION="$INACTIVE_SLOTS_CELL_FRACTION" \
  STEPS="$RELAX_STEPS" \
  ANALYSIS_START_STEP=0 \
  ANALYSIS_END_STEP="$RELAX_STEPS" \
  RECORD_ENABLE=true \
  FILTERED_RECORDING_ENABLE=1 \
  RECORD_FIELDS="rho1,rho2,ux,uy" \
  RECORD_EVERY="$RECORD_EVERY" \
  FILTER_SAMPLE_EVERY="$RECORD_EVERY" \
  DUMP_STATE_EVERY="$RELAX_STEPS" \
  DUMP_ROLE_FILTER=all \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  LIVE_PROGRESS="$LIVE_PROGRESS" \
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
  LIVE_VIS_HOLD_ON_EXIT=0 \
  CLEAN_RUN_ROOT=1 \
  PREFLIGHT_ONLY="$preflight" \
  bash "$PATCHED_RUNNER"
}

echo "[0493x24ag] preflight common relaxation..."
run_relax 1 || exit $?
printf "common_relax\tpreflight\tPASS\t%s\n" "$RELAX_ROOT" >> "$STATUS"

if [[ "$MODE" == "preflight" ]]; then
  COMMON_FOR_PREFLIGHT="$BASE_COMMON_STATE"
else
  echo "[0493x24ag] running fresh common relaxation at dt=$DT ..."
  run_relax 0 || exit $?
  [[ -s "$RELAX_FINAL_STATE" ]] || {
    echo "[0493x24ag] ERROR expected relaxed state not found: $RELAX_FINAL_STATE" >&2
    exit 2
  }
  printf "common_relax\tproduction\tPASS\t%s\n" "$RELAX_ROOT" >> "$STATUS"
  COMMON_FOR_PREFLIGHT="$RELAX_FINAL_STATE"
fi

started=0
for spec in "${CASES[@]}"; do
  read -r TAG FR <<<"$spec"

  if [[ "$started" == "0" ]]; then
    if [[ "$TAG" == "$START_CASE" ]]; then started=1; else continue; fi
  fi

  U="$(python3 - "$FR" <<'PY'
import math,sys
fr=float(sys.argv[1])
D=20/256
rho_ratio=0.0011735205616850552
g=0.5
c=(math.pi/4.0)**2
print(f"{math.sqrt(fr*(1/rho_ratio)*g*D/c):.17g}")
PY
)" || exit 2

  python3 - "$DT" "$GAS_KBT_OVER_MASS_REF" "$U" "$TAG" <<'PY'
import math,sys
dt,km,u=float(sys.argv[1]),float(sys.argv[2]),float(sys.argv[3]); tag=sys.argv[4]
h=1/256
cth=math.sqrt(km)*dt/h
cjet=abs(u)*dt/h
ctot=cth+cjet
print(f"[0493x24ag] {tag}: U={u:.9g} Cthermal={cth:.6g} Cjet={cjet:.6g} Ctotal={ctot:.6g}")
if ctot>0.80:
    raise SystemExit(f"[0493x24ag] ERROR {tag}: flight guard {ctot:.8g} > 0.80")
PY

  CASE_ROOT="$BASE_ROOT/$TAG"
  TACT="$(python3 - "$FORCED_STEPS" "$DT" <<'PY'
import sys
print(int(sys.argv[1])*float(sys.argv[2]))
PY
)"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$TAG" "$FR" "$U" "$DT" "$FORCED_STEPS" "$TACT" "$ARTICLE_START_STEP" "$COMMON_FOR_PREFLIGHT" >> "$PLAN"

  run_forced() {
    local preflight="$1"
    local state="$2"
    FORCE_RAMP_ON_RESTART=1 \
    RESTART=1 \
    RESTART_STATE="$state" \
    RESTART_FROM_STEP=0 \
    RESTART_TAG="common_relaxed_start" \
    CAMPAIGN_MODE=case \
    CAMPAIGN_ROOT="$CASE_ROOT" \
    CASE_LABEL="0493x24ag_${TAG}_article" \
    TARGET_H_OVER_D="$TARGET_H_OVER_D" \
    TARGET_FRM_SATO="$FR" \
    JET_SPEED="$U" \
    GAS_KBT="$GAS_KBT" \
    GAS_KBT_OVER_MASS_REF="$GAS_KBT_OVER_MASS_REF" \
    DT="$DT" \
    BATH_HEIGHT="$BATH_HEIGHT" \
    NOZZLE_INNER_WIDTH_CELLS="$NOZZLE_INNER_WIDTH_CELLS" \
    NOZZLE_LENGTH_CELLS="$NOZZLE_LENGTH_CELLS" \
    DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
    INACTIVE_SLOTS_CELL_FRACTION="$INACTIVE_SLOTS_CELL_FRACTION" \
    JET_RAMP_START_TIME="$RAMP_START" \
    JET_RAMP_END_TIME="$RAMP_END" \
    JET_RAMP_INITIAL_FACTOR=0.0 \
    JET_RAMP_FINAL_FACTOR=1.0 \
    STEPS="$FORCED_STEPS" \
    ANALYSIS_START_STEP="$ARTICLE_START_STEP" \
    ANALYSIS_END_STEP="$FORCED_STEPS" \
    RECORD_ENABLE=true \
    FILTERED_RECORDING_ENABLE=1 \
    RECORD_FIELDS="rho1,rho2,ux,uy" \
    RECORD_EVERY="$RECORD_EVERY" \
    FILTER_SAMPLE_EVERY="$RECORD_EVERY" \
    DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
    DUMP_ROLE_FILTER=all \
    SUMMARY_EVERY="$SUMMARY_EVERY" \
    LIVE_PROGRESS="$LIVE_PROGRESS" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
    LIVE_VIS_HOLD_ON_EXIT=0 \
    CLEAN_RUN_ROOT=1 \
    PREFLIGHT_ONLY="$preflight" \
    bash "$PATCHED_RUNNER"
  }

  echo "[0493x24ag] preflight $TAG..."
  run_forced 1 "$COMMON_FOR_PREFLIGHT" || exit $?
  printf "%s\tpreflight\tPASS\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"

  if [[ "$MODE" == "preflight" ]]; then
    continue
  fi

  echo "[0493x24ag] running $TAG Fr'=$FR ..."
  run_forced 0 "$RELAX_FINAL_STATE"
  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\tproduction\tFAIL\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"
    exit "$rc"
  fi
  printf "%s\tproduction\tPASS\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"
done

echo "================================================================"
if [[ "$MODE" == "preflight" ]]; then
  echo "[0493x24ag] PREFLIGHTS COMPLETE"
else
  echo "[0493x24ag] CAMPAIGN COMPLETE"
fi
echo "[0493x24ag] root=$BASE_ROOT"
echo "================================================================"

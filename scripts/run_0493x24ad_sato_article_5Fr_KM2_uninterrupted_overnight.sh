#!/usr/bin/env bash
# =============================================================================
# 0493x24ad — ARTICLE SATO OVERNIGHT, FIVE Fr, SINGLE UNINTERRUPTED RUNS
#
# Five cases:
#   Fr' = 0.25, 0.40, 0.55, 0.660364520158346, 0.75
#
# All five cases start from EXACTLY the same stabilized KM2 particle state,
# use dt=4e-4 and kBT_g/m_g=2.0, apply ONE smooth inlet ramp over t=0..0.2,
# then run continuously to t=8 (20000 steps) with NO intermediate restart.
#
# Restart dumps are written only as crash protection.
# Article statistics are intended on the common window t=1..8.
#
# IMPORTANT:
# The historical x24d restart path interprets RESTART=1 as a continuation and
# forcibly disables the inlet ramp. Here RESTART=1 is needed only to READ the
# common stabilized state, while this is the START of a new forced experiment.
#
# This campaign therefore creates a TEMPORARY COPY of x24d under tools/ and
# modifies ONLY that runner-level restart/ramp policy. No C++/CUDA source and
# no original project runner is modified.
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SEED="${SEED:-493205}"

BASE_RUNNER="${BASE_RUNNER:-scripts/run_0493x24d_sato_airwater_density_probe.sh}"
PATCHED_RUNNER="${PATCHED_RUNNER:-tools/run_0493x24ad_sato_common_state_ramped_case_tmp.sh}"

COMMON_STATE="${COMMON_STATE:-runs/0493x24x_sato_Fr075_KM2_short_seed${SEED}/relax/restart_relax_KM2/output/state_step_00001000.smpcd}"
BASE_ROOT="${BASE_ROOT:-runs/0493x24ad_sato_article_5Fr_KM2_uninterrupted_seed${SEED}}"

DT="${DT:-0.0004}"
GAS_KBT_OVER_MASS_REF="${GAS_KBT_OVER_MASS_REF:-2.0}"
GAS_MASS="${GAS_MASS:-0.0011735205616850552}"
GAS_KBT="${GAS_KBT:-0.0023470411233701104}"

TARGET_H_OVER_D="${TARGET_H_OVER_D:-0.8}"
BATH_HEIGHT="${BATH_HEIGHT:-0.81640625}"
NOZZLE_LENGTH_CELLS="${NOZZLE_LENGTH_CELLS:-31}"
NOZZLE_INNER_WIDTH_CELLS="${NOZZLE_INNER_WIDTH_CELLS:-20}"

DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-800000}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-24.0}"

PHYSICAL_TIME="${PHYSICAL_TIME:-8.0}"
RAMP_START="${RAMP_START:-0.0}"
RAMP_END="${RAMP_END:-0.20}"
ARTICLE_T_START="${ARTICLE_T_START:-1.0}"

RECORD_EVERY="${RECORD_EVERY:-20}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2500}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

MODE="${MODE:-production}"
START_CASE="${START_CASE:-Fr0p25}"

CASES=(
  "Fr0p25 0.25"
  "Fr0p40 0.40"
  "Fr0p55 0.55"
  "Fr0p660364520158346 0.660364520158346"
  "Fr0p75 0.75"
)

[[ -f "$BASE_RUNNER" ]] || {
  echo "[0493x24ad] ERROR missing base runner: $BASE_RUNNER" >&2
  exit 2
}
[[ -s "$COMMON_STATE" ]] || {
  echo "[0493x24ad] ERROR missing common stabilized state:" >&2
  echo "  $COMMON_STATE" >&2
  exit 2
}

case "$MODE" in
  preflight|production) ;;
  *)
    echo "[0493x24ad] ERROR MODE must be preflight or production" >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname "$PATCHED_RUNNER")" "$BASE_ROOT" || exit 2

python3 - "$BASE_RUNNER" "$PATCHED_RUNNER" <<'PY_PATCH'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
txt = src.read_text()

old = '''  # Do not re-ramp the inlet on a continuation.
  JET_RAMP_START_TIME=0.0; JET_RAMP_END_TIME=0.0; JET_RAMP_INITIAL_FACTOR=1.0; JET_RAMP_FINAL_FACTOR=1.0
  INLET_RAMP_ENABLE=false
else
  RESTART_FROM_STEP=0
  INLET_RAMP_ENABLE=true
fi
'''

new = '''  # 0493x24ad runner-only distinction:
  # RESTART=1 normally means continuation and therefore no re-ramp.
  # Here it can instead mean "load common stabilized state and START forcing".
  if [[ "${FORCE_RAMP_ON_RESTART:-0}" == "1" ]]; then
    INLET_RAMP_ENABLE=true
    echo "[0493x24ad] common-state start: preserving inlet ramp ${JET_RAMP_START_TIME}->${JET_RAMP_END_TIME}, factors ${JET_RAMP_INITIAL_FACTOR}->${JET_RAMP_FINAL_FACTOR}"
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

n = txt.count(old)
if n != 1:
    raise SystemExit(
        f"[0493x24ad] ERROR expected exactly one restart/ramp block in {src}, found {n}; refusing unsafe patch"
    )

dst.write_text(txt.replace(old, new))
dst.chmod(0o755)
print(f"[0493x24ad] temporary runner created: {dst}")
PY_PATCH

COMMON_STATE_SHA="$(sha256sum "$COMMON_STATE" | awk '{print $1}')"
BASE_RUNNER_SHA="$(sha256sum "$BASE_RUNNER" | awk '{print $1}')"
PATCHED_RUNNER_SHA="$(sha256sum "$PATCHED_RUNNER" | awk '{print $1}')"
GIT_HEAD="$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
GIT_DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

read -r STEPS ARTICLE_START_STEP <<<"$(python3 - "$DT" "$PHYSICAL_TIME" "$ARTICLE_T_START" <<'PY'
import sys
dt,T,t0=map(float,sys.argv[1:])
n=round(T/dt); n0=round(t0/dt)
if abs(n*dt-T)>1e-12:
    raise SystemExit("PHYSICAL_TIME is not an integer number of steps")
if abs(n0*dt-t0)>1e-12:
    raise SystemExit("ARTICLE_T_START is not an integer number of steps")
if not (0 <= n0 < n):
    raise SystemExit("require 0 <= ARTICLE_T_START < PHYSICAL_TIME")
print(int(n),int(n0))
PY
)" || exit 2

PLAN="$BASE_ROOT/campaign_plan.tsv"
STATUS="$BASE_ROOT/campaign_status.tsv"
AUDIT="$BASE_ROOT/campaign_audit.txt"

printf "case\ttargetFr\tjetSpeed\tdt\tkBT_over_m\tgasKBT\tsteps\tphysicalTime\trampStart\trampEnd\tarticleStartStep\tarticleEndStep\tcommonState\n" > "$PLAN"
printf "case\tstage\tstatus\troot\n" > "$STATUS"

cat > "$AUDIT" <<EOF
campaign=0493x24ad_sato_article_5Fr_KM2_uninterrupted
createdUtc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
gitHead=$GIT_HEAD
gitDirtyCount=$GIT_DIRTY
baseRunner=$BASE_RUNNER
baseRunnerSha256=$BASE_RUNNER_SHA
temporaryRunner=$PATCHED_RUNNER
temporaryRunnerSha256=$PATCHED_RUNNER_SHA
commonState=$COMMON_STATE
commonStateSha256=$COMMON_STATE_SHA
seed=$SEED
dt=$DT
gasKBTOverMass=$GAS_KBT_OVER_MASS_REF
gasKBT=$GAS_KBT
targetHOverD=$TARGET_H_OVER_D
bathHeight=$BATH_HEIGHT
nozzleLengthCells=$NOZZLE_LENGTH_CELLS
steps=$STEPS
physicalTime=$PHYSICAL_TIME
ramp=$RAMP_START:$RAMP_END:0->1
articleWindow=$ARTICLE_START_STEP:$STEPS
recordEvery=$RECORD_EVERY
dumpEvery=$DUMP_STATE_EVERY
EOF

echo "================================================================"
echo " 0493x24ad — ARTICLE SATO 5-Fr UNINTERRUPTED OVERNIGHT"
echo "================================================================"
echo "[0493x24ad] common state : $COMMON_STATE"
echo "[0493x24ad] state SHA256 : $COMMON_STATE_SHA"
echo "[0493x24ad] branch        : dt=$DT, kBTg/mg=$GAS_KBT_OVER_MASS_REF"
echo "[0493x24ad] duration      : T=$PHYSICAL_TIME = $STEPS steps / case"
echo "[0493x24ad] initial ramp  : t=$RAMP_START -> $RAMP_END, factor 0 -> 1"
echo "[0493x24ad] article window: t=$ARTICLE_T_START -> $PHYSICAL_TIME"
echo "[0493x24ad] dumps         : every $DUMP_STATE_EVERY steps (safety only)"
echo "[0493x24ad] recordings    : rho,ux,uy every $RECORD_EVERY steps"
echo "[0493x24ad] mode          : $MODE startCase=$START_CASE"
echo "================================================================"

started=0

for spec in "${CASES[@]}"; do
  read -r TAG FR <<<"$spec"

  if [[ "$started" == "0" ]]; then
    if [[ "$TAG" == "$START_CASE" ]]; then
      started=1
    else
      continue
    fi
  fi

  U="$(python3 - "$FR" <<'PY'
import math,sys
fr=float(sys.argv[1])
D=20/256
rho_ratio=0.0011735205616850552
g=0.5
c=(math.pi/4.0)**2
u=math.sqrt(fr*(1.0/rho_ratio)*g*D/c)
print(f"{u:.17g}")
PY
)" || exit 2

  python3 - "$DT" "$GAS_KBT_OVER_MASS_REF" "$U" "$TAG" <<'PY'
import math,sys
dt,km,u=float(sys.argv[1]),float(sys.argv[2]),float(sys.argv[3])
tag=sys.argv[4]
h=1/256
cth=math.sqrt(km)*dt/h
cjet=abs(u)*dt/h
ctot=cth+cjet
print(f"[0493x24ad] {tag}: U={u:.9g} Cthermal={cth:.6g} Cjet={cjet:.6g} Ctotal={ctot:.6g}")
if ctot>0.80:
    raise SystemExit(f"[0493x24ad] ERROR {tag}: flight guard {ctot:.8g} > 0.80")
PY

  CASE_ROOT="$BASE_ROOT/$TAG"
  CASE_LABEL="0493x24ad_${TAG}_KM2_article"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$TAG" "$FR" "$U" "$DT" "$GAS_KBT_OVER_MASS_REF" "$GAS_KBT" \
    "$STEPS" "$PHYSICAL_TIME" "$RAMP_START" "$RAMP_END" \
    "$ARTICLE_START_STEP" "$STEPS" "$COMMON_STATE" >> "$PLAN"

  echo
  echo "----------------------------------------------------------------"
  echo "[0493x24ad] CASE=$TAG targetFr=$FR Ujet=$U"
  echo "[0493x24ad] root=$CASE_ROOT"
  echo "----------------------------------------------------------------"

  run_case() {
    local preflight="$1"

    FORCE_RAMP_ON_RESTART=1 \
    RESTART=1 \
    RESTART_STATE="$COMMON_STATE" \
    RESTART_FROM_STEP=0 \
    RESTART_TAG="common_relaxed_start" \
    CAMPAIGN_MODE=case \
    CAMPAIGN_ROOT="$CASE_ROOT" \
    CASE_LABEL="$CASE_LABEL" \
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
    STEPS="$STEPS" \
    ANALYSIS_START_STEP="$ARTICLE_START_STEP" \
    ANALYSIS_END_STEP="$STEPS" \
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

  run_case 1
  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\tpreflight\tFAIL\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"
    exit "$rc"
  fi
  printf "%s\tpreflight\tPASS\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"

  if [[ "$MODE" == "preflight" ]]; then
    continue
  fi

  run_case 0
  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\tproduction\tFAIL\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"
    exit "$rc"
  fi
  printf "%s\tproduction\tPASS\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"

  echo "[0493x24ad] CASE=$TAG COMPLETE"
done

echo
echo "================================================================"
if [[ "$MODE" == "preflight" ]]; then
  echo "[0493x24ad] ALL REQUESTED PREFLIGHTS PASS"
else
  echo "[0493x24ad] CAMPAIGN COMPLETE"
fi
echo "[0493x24ad] root=$BASE_ROOT"
echo
echo "[0493x24ad] V3/V4-style analysis roots:"
for spec in "${CASES[@]}"; do
  read -r TAG FR <<<"$spec"
  echo "  --case ${FR}:0.0:${BASE_ROOT}/${TAG}/restart_common_relaxed_start"
done
echo
echo "[0493x24ad] If a case is interrupted, do not merge a manual restart into the"
echo "[0493x24ad] article statistics without a fresh inlet-recovery audit."
echo "================================================================"

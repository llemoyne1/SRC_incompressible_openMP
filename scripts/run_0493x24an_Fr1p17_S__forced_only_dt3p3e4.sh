#!/usr/bin/env bash
# =============================================================================
# 0493x24an — forced-only high-Fr bridge campaign: Fr'=2.0 and 2.5
#
# Same thermal/time branch as Fr'=3 V2:
#   kBT/m = 2.0
#   dt    = 2.2e-4
#
# No relaxation is run here.
# Both cases start from the same existing stabilized zero-jet state.
# Fields recorded: rho1,rho2,ux,uy.
# Default FORCED_STEPS=30000 -> T=6.6.
#
# Usage:
#   cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
#   MODE=preflight bash scripts/run_0493x24an_Fr2_Fr2p5_forced_only_dt2p2e4.sh
#   LIVE_PROGRESS=1 bash scripts/run_0493x24an_Fr2_Fr2p5_forced_only_dt2p2e4.sh
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SEED="${SEED:-493205}"

BASE_RUNNER="${BASE_RUNNER:-scripts/run_0493x24d_sato_airwater_density_probe.sh}"
PATCHED_RUNNER="${PATCHED_RUNNER:-tools/run_0493x24an_common_state_ramped_case_tmp.sh}"

V2_ROOT="${V2_ROOT:-runs/0493x24ah_Fr3_atomization_KM2_V2_dt2p2e4_seed${SEED}}"
STABILIZED_STATE="${STABILIZED_STATE:-$V2_ROOT/common_relax_dt2p2e4/restart_common_dt_relax/output/state_step_00005000.smpcd}"

BASE_ROOT="${BASE_ROOT:-runs/0493x24an_Fr1p17_forced_only_KM2_dt3p3e4_seed${SEED}}"

DT="${DT:-0.00033}"
GAS_KBT_OVER_MASS_REF="${GAS_KBT_OVER_MASS_REF:-2.0}"
GAS_KBT="${GAS_KBT:-0.0023470411233701104}"

TARGET_H_OVER_D="${TARGET_H_OVER_D:-0.8}"
BATH_HEIGHT="${BATH_HEIGHT:-0.81640625}"
NOZZLE_LENGTH_CELLS="${NOZZLE_LENGTH_CELLS:-31}"
NOZZLE_INNER_WIDTH_CELLS="${NOZZLE_INNER_WIDTH_CELLS:-20}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-800000}"

# The loaded state carries its actual inactive-pool capacity.
# Override this only if you want the recorded environment to match a specific
# explicit V2 value.
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-100.0}"

FORCED_STEPS="${FORCED_STEPS:-30000}"

RAMP_START="${RAMP_START:-0.0}"
RAMP_END="${RAMP_END:-0.20}"

RECORD_EVERY="${RECORD_EVERY:-10}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-3000}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

MODE="${MODE:-production}"
START_CASE="${START_CASE:-Fr1p17}"

CASES=(
#  "Fr2p0 2.0"
#  "Fr2p5 2.5"
  "Fr1p17 1.17"
)

[[ -f "$BASE_RUNNER" ]] || {
  echo "[0493x24an] ERROR missing base runner: $BASE_RUNNER" >&2
  exit 2
}

[[ -s "$STABILIZED_STATE" ]] || {
  echo "[0493x24an] ERROR missing stabilized state:" >&2
  echo "  $STABILIZED_STATE" >&2
  echo "[0493x24an] Set STABILIZED_STATE explicitly if the V2 state has another path." >&2
  exit 2
}

case "$MODE" in
  preflight|production) ;;
  *)
    echo "[0493x24an] ERROR MODE=$MODE; expected preflight|production" >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname "$PATCHED_RUNNER")" "$BASE_ROOT" || exit 2

python3 - "$BASE_RUNNER" "$PATCHED_RUNNER" <<'PY_PATCH'
from pathlib import Path
import sys

src, dst = map(Path, sys.argv[1:3])
txt = src.read_text()

old = """  # Do not re-ramp the inlet on a continuation.
  JET_RAMP_START_TIME=0.0; JET_RAMP_END_TIME=0.0; JET_RAMP_INITIAL_FACTOR=1.0; JET_RAMP_FINAL_FACTOR=1.0
  INLET_RAMP_ENABLE=false
else
  RESTART_FROM_STEP=0
  INLET_RAMP_ENABLE=true
fi
"""

new = """  # 0493x24an: distinguish loading a stabilized common state from
  # a physical forced-flow continuation.
  if [[ "${FORCE_RAMP_ON_RESTART:-0}" == "1" ]]; then
    INLET_RAMP_ENABLE=true
    echo "[0493x24an] common-state start: preserving inlet ramp ${JET_RAMP_START_TIME}->${JET_RAMP_END_TIME}"
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
"""

if txt.count(old) != 1:
    raise SystemExit(
        "[0493x24an] ERROR restart/ramp block not uniquely found; refusing patch"
    )

dst.write_text(txt.replace(old, new))
dst.chmod(0o755)
print(f"[0493x24an] temporary runner: {dst}")
PY_PATCH

PLAN="$BASE_ROOT/campaign_plan.tsv"
STATUS="$BASE_ROOT/campaign_status.tsv"

printf "case\ttargetFr\tUjet\tdt\tkBT_over_m\tgas_kBT\tforced_steps\tphysical_time\tstate\n" > "$PLAN"
printf "case\tstage\tstatus\tpath\n" > "$STATUS"

started=0

for item in "${CASES[@]}"; do
  read -r TAG FR <<< "$item"

  if [[ "$started" == "0" ]]; then
    if [[ "$TAG" != "$START_CASE" ]]; then
      continue
    fi
    started=1
  fi

  U="$(python3 - "$FR" <<'PY'
import math, sys
fr = float(sys.argv[1])
D = 20.0 / 256.0
rho_ratio = 0.0011735205616850552
g = 0.5
c = (math.pi / 4.0) ** 2
u = math.sqrt(fr * (1.0 / rho_ratio) * g * D / c)
print(f"{u:.17g}")
PY
)" || exit 2

  python3 - "$DT" "$GAS_KBT_OVER_MASS_REF" "$U" "$TAG" <<'PY'
import math, sys
dt, km, u = map(float, sys.argv[1:4])
tag = sys.argv[4]
h = 1.0 / 256.0
cth = math.sqrt(km) * dt / h
cjet = abs(u) * dt / h
ctot = cth + cjet
print(
    f"[0493x24an] {tag}: "
    f"U={u:.9g} Cthermal={cth:.6g} Cjet={cjet:.6g} Ctotal={ctot:.6g}"
)
if ctot > 0.80:
    raise SystemExit(
        f"[0493x24an] ERROR {tag}: flight guard {ctot:.8g} > 0.80"
    )
PY

  CASE_ROOT="$BASE_ROOT/$TAG"
  CASE_LABEL="0493x24an_${TAG}_KM2_forced_only"

  PHYSICAL_TIME="$(python3 - "$FORCED_STEPS" "$DT" <<'PY'
import sys
print(f"{int(sys.argv[1]) * float(sys.argv[2]):.12g}")
PY
)"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n"     "$TAG" "$FR" "$U" "$DT" "$GAS_KBT_OVER_MASS_REF" "$GAS_KBT"     "$FORCED_STEPS" "$PHYSICAL_TIME" "$STABILIZED_STATE" >> "$PLAN"

  echo
  echo "----------------------------------------------------------------"
  echo "[0493x24an] CASE=$TAG targetFr=$FR Ujet=$U"
  echo "[0493x24an] start state=$STABILIZED_STATE"
  echo "[0493x24an] root=$CASE_ROOT"
  echo "----------------------------------------------------------------"

  run_case() {
    local preflight="$1"

    FORCE_RAMP_ON_RESTART=1     RESTART=1     RESTART_STATE="$STABILIZED_STATE"     RESTART_FROM_STEP=0     RESTART_TAG="common_relaxed_start"     CAMPAIGN_MODE=case     CAMPAIGN_ROOT="$CASE_ROOT"     CASE_LABEL="$CASE_LABEL"     TARGET_H_OVER_D="$TARGET_H_OVER_D"     TARGET_FRM_SATO="$FR"     JET_SPEED="$U"     GAS_KBT="$GAS_KBT"     GAS_KBT_OVER_MASS_REF="$GAS_KBT_OVER_MASS_REF"     DT="$DT"     BATH_HEIGHT="$BATH_HEIGHT"     NOZZLE_INNER_WIDTH_CELLS="$NOZZLE_INNER_WIDTH_CELLS"     NOZZLE_LENGTH_CELLS="$NOZZLE_LENGTH_CELLS"     DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX"     INACTIVE_SLOTS_CELL_FRACTION="$INACTIVE_SLOTS_CELL_FRACTION"     JET_RAMP_START_TIME="$RAMP_START"     JET_RAMP_END_TIME="$RAMP_END"     JET_RAMP_INITIAL_FACTOR=0.0     JET_RAMP_FINAL_FACTOR=1.0     STEPS="$FORCED_STEPS"     ANALYSIS_START_STEP=0     ANALYSIS_END_STEP="$FORCED_STEPS"     RECORD_ENABLE=true     FILTERED_RECORDING_ENABLE=1     RECORD_FIELDS="rho1,rho2,ux,uy"     RECORD_EVERY="$RECORD_EVERY"     FILTER_SAMPLE_EVERY="$RECORD_EVERY"     DUMP_STATE_EVERY="$DUMP_STATE_EVERY"     DUMP_ROLE_FILTER=all     SUMMARY_EVERY="$SUMMARY_EVERY"     LIVE_PROGRESS="$LIVE_PROGRESS"     LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"     LIVE_VIS_HOLD_ON_EXIT=0     CLEAN_RUN_ROOT=1     PREFLIGHT_ONLY="$preflight"     bash "$PATCHED_RUNNER"
  }

  echo "[0493x24an] preflight $TAG..."
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

  echo "[0493x24an] production $TAG..."
  run_case 0
  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\tproduction\tFAIL\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"
    exit "$rc"
  fi
  printf "%s\tproduction\tPASS\t%s\n" "$TAG" "$CASE_ROOT" >> "$STATUS"

  echo "[0493x24an] CASE=$TAG COMPLETE"
done

echo
echo "================================================================"
echo "[0493x24an] COMPLETE"
echo "[0493x24an] root=$BASE_ROOT"
echo "[0493x24an] common stabilized state reused:"
echo "  $STABILIZED_STATE"
echo "[0493x24an] outputs:"
echo "  $BASE_ROOT/Fr2p0/restart_common_relaxed_start"
echo "  $BASE_ROOT/Fr2p5/restart_common_relaxed_start"
echo "================================================================"

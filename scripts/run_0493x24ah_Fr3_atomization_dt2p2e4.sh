#!/usr/bin/env bash
# Generated campaign runner. No C++/CUDA source modification.
# Uses a temporary runner copy only to distinguish "load a common relaxed state"
# from a physical forced-flow continuation, so that the initial inlet ramp is
# preserved on the first forced segment.

# =============================================================================
# 0493x24ah — QUALITATIVE ATOMIZATION TEST, Fr'=3.0, dt=2.2e-4
#
# This case is intentionally qualitative and must not enter the Sato fit.
# A fresh zero-jet relaxation is made at the new dt before forcing.
#
# Default:
#   relaxation = 5000 steps => T=1.1
#   forcing    = 10000 steps => T=2.2
#   recordings = rho1,rho2,ux,uy every 10 steps
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SEED="${SEED:-493205}"
BASE_RUNNER="${BASE_RUNNER:-scripts/run_0493x24d_sato_airwater_density_probe.sh}"
PATCHED_RUNNER="${PATCHED_RUNNER:-tools/run_0493x24ah_common_state_ramped_case_tmp.sh}"
BASE_COMMON_STATE="${BASE_COMMON_STATE:-runs/0493x24x_sato_Fr075_KM2_short_seed${SEED}/relax/restart_relax_KM2/output/state_step_00001000.smpcd}"

BASE_ROOT="${BASE_ROOT:-runs/0493x24ah_Fr3_atomization_KM2_S_dt2p2e4_seed${SEED}}"

TARGET_FRM_SATO="${TARGET_FRM_SATO:-3.0}"
DT="${DT:-0.00022}"
GAS_KBT_OVER_MASS_REF="${GAS_KBT_OVER_MASS_REF:-2.0}"
GAS_KBT="${GAS_KBT:-0.0023470411233701104}"

TARGET_H_OVER_D="${TARGET_H_OVER_D:-0.8}"
BATH_HEIGHT="${BATH_HEIGHT:-0.81640625}"
NOZZLE_LENGTH_CELLS="${NOZZLE_LENGTH_CELLS:-31}"
NOZZLE_INNER_WIDTH_CELLS="${NOZZLE_INNER_WIDTH_CELLS:-20}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-800000}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-100.0}"

RELAX_STEPS="${RELAX_STEPS:-5000}"
FORCED_STEPS="${FORCED_STEPS:-30000}"

RAMP_START="${RAMP_START:-0.0}"
RAMP_END="${RAMP_END:-0.20}"

RECORD_EVERY="${RECORD_EVERY:-10}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2000}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
MODE="${MODE:-production}"

[[ -f "$BASE_RUNNER" ]] || { echo "[0493x24ah] ERROR missing $BASE_RUNNER" >&2; exit 2; }
[[ -s "$BASE_COMMON_STATE" ]] || { echo "[0493x24ah] ERROR missing $BASE_COMMON_STATE" >&2; exit 2; }
case "$MODE" in preflight|production) ;; *) echo "[0493x24ah] ERROR MODE=$MODE" >&2; exit 2;; esac

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
new='''  # 0493x24ah: distinguish state loading from forced-flow continuation.
  if [[ "${FORCE_RAMP_ON_RESTART:-0}" == "1" ]]; then
    INLET_RAMP_ENABLE=true
    echo "[0493x24ah] common-state start: preserving inlet ramp ${JET_RAMP_START_TIME}->${JET_RAMP_END_TIME}"
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
    raise SystemExit("[0493x24ah] ERROR restart/ramp block not uniquely found; refusing patch")
dst.write_text(txt.replace(old,new))
dst.chmod(0o755)
print(f"[0493x24ah] temporary runner: {dst}")
PY_PATCH

RELAX_ROOT="$BASE_ROOT/common_relax_dt2p2e4"
RELAX_FINAL_STATE="$RELAX_ROOT/restart_common_dt_relax/output/state_step_$(printf '%08d' "$RELAX_STEPS").smpcd"
CASE_ROOT="$BASE_ROOT/Fr3p0"

U="$(python3 - "$TARGET_FRM_SATO" <<'PY'
import math,sys
fr=float(sys.argv[1])
D=20/256
rho_ratio=0.0011735205616850552
g=0.5
c=(math.pi/4.0)**2
print(f"{math.sqrt(fr*(1/rho_ratio)*g*D/c):.17g}")
PY
)" || exit 2

python3 - "$DT" "$GAS_KBT_OVER_MASS_REF" "$U" <<'PY'
import math,sys
dt,km,u=map(float,sys.argv[1:])
h=1/256
cth=math.sqrt(km)*dt/h
cjet=abs(u)*dt/h
ctot=cth+cjet
print(f"[0493x24ah] Fr'=3: U={u:.9g} Cthermal={cth:.6g} Cjet={cjet:.6g} Ctotal={ctot:.6g}")
if ctot>0.80:
    raise SystemExit(f"[0493x24ah] ERROR flight guard {ctot:.8g} > 0.80")
PY

run_relax() {
  local preflight="$1"
  FORCE_RAMP_ON_RESTART=0 \
  RESTART=1 \
  RESTART_STATE="$BASE_COMMON_STATE" \
  RESTART_FROM_STEP=0 \
  RESTART_TAG="common_dt_relax" \
  CAMPAIGN_MODE=case \
  CAMPAIGN_ROOT="$RELAX_ROOT" \
  CASE_LABEL="0493x24ah_common_relax_dt2p2e4" \
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
  CASE_LABEL="0493x24ah_Fr3_atomization" \
  TARGET_H_OVER_D="$TARGET_H_OVER_D" \
  TARGET_FRM_SATO="$TARGET_FRM_SATO" \
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
  ANALYSIS_START_STEP=0 \
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

echo "================================================================"
echo " 0493x24ah — QUALITATIVE Fr'=3.0 ATOMIZATION TEST"
echo " dt=$DT U=$U"
echo " relax=$RELAX_STEPS steps ; forced=$FORCED_STEPS steps"
echo " recordings: rho1,rho2,ux,uy every $RECORD_EVERY steps"
echo "================================================================"

echo "[0493x24ah] preflight relaxation..."
run_relax 1 || exit $?

if [[ "$MODE" == "preflight" ]]; then
  echo "[0493x24ah] preflight forced case..."
  run_forced 1 "$BASE_COMMON_STATE" || exit $?
  echo "[0493x24ah] PREFLIGHT PASS"
  exit 0
fi

echo "[0493x24ah] fresh relaxation at dt=$DT..."
run_relax 0 || exit $?
[[ -s "$RELAX_FINAL_STATE" ]] || {
  echo "[0493x24ah] ERROR expected relaxed state missing: $RELAX_FINAL_STATE" >&2
  exit 2
}

echo "[0493x24ah] forced Fr'=3.0..."
run_forced 1 "$RELAX_FINAL_STATE" || exit $?
run_forced 0 "$RELAX_FINAL_STATE" || exit $?

echo "================================================================"
echo "[0493x24ah] COMPLETE"
echo "[0493x24ah] root=$BASE_ROOT"
echo "[0493x24ah] qualitative forced root=$CASE_ROOT/restart_common_relaxed_start"
echo "================================================================"

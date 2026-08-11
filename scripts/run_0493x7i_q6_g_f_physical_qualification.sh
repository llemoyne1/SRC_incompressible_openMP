#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0493x7i is a dumps-only physical comparison layer on top of the 0493x7h
# run_ok routing.  It changes no C++/CUDA physics and does not post-process
# during the simulation.  MATLAB analysis is intentionally offline.
RUN_ROOT="${RUN_ROOT:-runs/0493x7i_q6_g_f_physical_qualification}"
CASES="${CASES:-tg poiseuille bend_pipe io_box}"
QUAL_MODES="${QUAL_MODES:-src src-q6 src-q6-g-f}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

# Dump plans.  They are deliberately case-specific because particle-state
# dumps are much larger for the 300x300 same-face box than for TG/Poiseuille.
X7I_TG_STEPS="${X7I_TG_STEPS:-10000}"
X7I_TG_DUMP_EVERY="${X7I_TG_DUMP_EVERY:-500}"
X7I_TG_SUMMARY_EVERY="${X7I_TG_SUMMARY_EVERY:-100}"

X7I_POISEUILLE_STEPS="${X7I_POISEUILLE_STEPS:-10000}"
X7I_POISEUILLE_DUMP_EVERY="${X7I_POISEUILLE_DUMP_EVERY:-500}"
X7I_POISEUILLE_SUMMARY_EVERY="${X7I_POISEUILLE_SUMMARY_EVERY:-100}"

# Bend-pipe and same-face IO are startup qualifications.  The bend defaults to
# rest so the pressure/projection-mediated response is measurable, while U0
# remains the inlet target.  All Darcy modes use the same filled fictitious
# domain so the comparison isolates the flow operator rather than initialization.
X7I_BEND_STEPS="${X7I_BEND_STEPS:-1000}"
X7I_BEND_DUMP_EVERY="${X7I_BEND_DUMP_EVERY:-25}"
X7I_BEND_SUMMARY_EVERY="${X7I_BEND_SUMMARY_EVERY:-25}"
X7I_BEND_START_FROM_REST="${X7I_BEND_START_FROM_REST:-1}"
X7I_BEND_COMMON_FILLED_STATE="${X7I_BEND_COMMON_FILLED_STATE:-1}"

X7I_IO_BOX_STEPS="${X7I_IO_BOX_STEPS:-500}"
X7I_IO_BOX_DUMP_EVERY="${X7I_IO_BOX_DUMP_EVERY:-50}"
X7I_IO_BOX_SUMMARY_EVERY="${X7I_IO_BOX_SUMMARY_EVERY:-25}"

truthy_0493x7i() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac
}

run_tg_0493x7i() {
  echo "[0493x7i] TG forced: vortex-core population qualification"
  RUN_MODES="$QUAL_MODES" \
  BASE_RUN_ROOT="$RUN_ROOT/tg" \
  STEPS="$X7I_TG_STEPS" \
  DUMP_STATE_EVERY="$X7I_TG_DUMP_EVERY" \
  SUMMARY_EVERY="$X7I_TG_SUMMARY_EVERY" \
  TG_HOLE_ENABLE=false \
  LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=1 FILTERED_RECORDING_ENABLE=0 \
  DUMP_ROLE_FILTER=fluid LIVE_PROGRESS="$LIVE_PROGRESS" \
  CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
  bash scripts/run_ok_tg.sh
}

run_poiseuille_0493x7i() {
  echo "[0493x7i] Poiseuille: normalized-profile qualification"
  RUN_MODES="$QUAL_MODES" \
  BASE_RUN_ROOT="$RUN_ROOT/poiseuille" \
  STEPS="$X7I_POISEUILLE_STEPS" \
  DUMP_STATE_EVERY="$X7I_POISEUILLE_DUMP_EVERY" \
  SUMMARY_EVERY="$X7I_POISEUILLE_SUMMARY_EVERY" \
  LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=1 FILTERED_RECORDING_ENABLE=0 \
  DUMP_ROLE_FILTER=fluid LIVE_PROGRESS="$LIVE_PROGRESS" \
  CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
  bash scripts/run_ok_poiseuille.sh
}

run_bend_pipe_0493x7i() {
  local velocity_mode="uniform_x"
  if truthy_0493x7i "$X7I_BEND_START_FROM_REST"; then velocity_mode="zero"; fi
  echo "[0493x7i] bend pipe: startup qualification velocityMode=$velocity_mode commonFilledDarcy=$X7I_BEND_COMMON_FILLED_STATE"
  RUN_MODES="$QUAL_MODES" \
  BASE_RUN_ROOT="$RUN_ROOT/bend_pipe" \
  STEPS="$X7I_BEND_STEPS" \
  DUMP_STATE_EVERY="$X7I_BEND_DUMP_EVERY" \
  SUMMARY_EVERY="$X7I_BEND_SUMMARY_EVERY" \
  VELOCITY_MODE="$velocity_mode" \
  RUN_OK_DARCY_COMMON_FILLED_STATE="$X7I_BEND_COMMON_FILLED_STATE" \
  LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 FILTERED_RECORDING_ENABLE=0 \
  DUMP_ROLE_FILTER=fluid LIVE_PROGRESS="$LIVE_PROGRESS" \
  CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
  bash scripts/run_ok_bend_pipe.sh
}

run_io_box_0493x7i() {
  echo "[0493x7i] same-face IO box: startup qualification"
  RUN_MODES="$QUAL_MODES" \
  BASE_RUN_ROOT="$RUN_ROOT/io_box" \
  STEPS="$X7I_IO_BOX_STEPS" \
  DUMP_STATE_EVERY="$X7I_IO_BOX_DUMP_EVERY" \
  SUMMARY_EVERY="$X7I_IO_BOX_SUMMARY_EVERY" \
  LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 FILTERED_RECORDING_ENABLE=0 \
  DUMP_ROLE_FILTER=fluid LIVE_PROGRESS="$LIVE_PROGRESS" \
  CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
  bash scripts/run_ok_io_box_same_face.sh
}

echo "[0493x7i] Q6-g-f physical qualification"
echo "[0493x7i] root=$RUN_ROOT modes=$QUAL_MODES cases=$CASES preflight=$PREFLIGHT_ONLY"
echo "[0493x7i] post-processing=offline MATLAB; no analysis runs during simulation"

for case_name in $CASES; do
  echo
  echo "============================================================"
  echo "[0493x7i] case=$case_name"
  echo "============================================================"
  case "$case_name" in
    tg) run_tg_0493x7i ;;
    poiseuille) run_poiseuille_0493x7i ;;
    bend_pipe|bend) run_bend_pipe_0493x7i ;;
    io_box|io_box_same_face|sameface) run_io_box_0493x7i ;;
    *) echo "[0493x7i] ERROR unknown case=$case_name" >&2; exit 2 ;;
  esac
done

if ! truthy_0493x7i "$PREFLIGHT_ONLY"; then
  echo
  echo "[0493x7i] simulations complete"
  echo "[0493x7i] MATLAB post-process from repository root:"
  echo "  addpath('matlab'); out = analyze_0493x7i_q6_g_f_qualification('$RUN_ROOT');"
fi

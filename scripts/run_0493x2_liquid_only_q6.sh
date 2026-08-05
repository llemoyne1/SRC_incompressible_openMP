#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Closed-box control used to determine whether Q6 alone can prevent the
# gravitational collapse of a fully occupied liquid.  There are no gas
# particles and no free interface; all other physical settings follow the
# current 0493x dam-break study unless explicitly overridden.
export LIQUID_ONLY=1
export Lx="${Lx:-1.0}"
export Ly="${Ly:-1.0}"
export NX="${NX:-200}"
export NY="${NY:-200}"
export GAMMA="${GAMMA:-10}"
export STEPS="${STEPS:-5000}"
export DT="${DT:-0.005}"
export KBT="${KBT:-0.05}"
export GRAVITY_Y="${GRAVITY_Y:--0.5}"
export LIQUID_MASS="${LIQUID_MASS:-1000.0}"
export GAS_MASS="${GAS_MASS:-1.0}"
export RUN_MODES="${RUN_MODES:-src-q6}"
RUN_LABEL="${RUN_MODES// /_}"
RUN_LABEL="${RUN_LABEL//,/_}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-500}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
export BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x2_liquid_only_${NX}x${NY}_g${GAMMA}_${RUN_LABEL}}"

exec bash "$ROOT/scripts/run_0493x0_dam_break_demo.sh"

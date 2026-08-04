#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# Compact end-to-end qualification of the new static four-wall resident path.
# It reuses the dam-break generator and strict post-check while disabling all
# visualization/recording overhead.
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x1_closed_box_smoke}" \
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}" \
Lx="${Lx:-1.0}" Ly="${Ly:-1.0}" \
NX="${NX:-48}" NY="${NY:-32}" GAMMA="${GAMMA:-6}" \
STEPS="${STEPS:-60}" DT="${DT:-0.002}" KBT="${KBT:-0.02}" \
COLUMN_WIDTH="${COLUMN_WIDTH:-0.25}" COLUMN_HEIGHT="${COLUMN_HEIGHT:-0.75}" \
LIQUID_MASS="${LIQUID_MASS:-100.0}" GAS_MASS="${GAS_MASS:-1.0}" \
GRAVITY_Y="${GRAVITY_Y:--0.02}" \
BC_LEFT="${BC_LEFT:-specular}" BC_RIGHT="${BC_RIGHT:-specular}" \
BC_BOTTOM="${BC_BOTTOM:-solid}" BC_TOP="${BC_TOP:-specular}" \
WALL_ACCOMMODATION="${WALL_ACCOMMODATION:-1.0}" \
Q6_PROJECTION_TOLERANCE="${Q6_PROJECTION_TOLERANCE:-1.0e-7}" \
Q6_PROJECTION_MAX_ITERATIONS="${Q6_PROJECTION_MAX_ITERATIONS:-1200}" \
SUMMARY_EVERY="${SUMMARY_EVERY:-5}" DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-30}" \
RUN_MODES="${RUN_MODES:-src src-q6}" \
LIVE_VIS_ENABLE=0 FILTERED_RECORDING_ENABLE=0 LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
bash scripts/run_0493x0_dam_break_demo.sh

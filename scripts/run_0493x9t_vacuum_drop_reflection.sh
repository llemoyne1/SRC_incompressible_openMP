#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0493x9t first qualification: reproduce a high-kBT liquid drop in vacuum and
# turn on the conservative internal reflection closure.  This deliberately uses
# the viscosity-qualified VK microscopic fluid.  Sigma=9450 is kept as a hard
# stress by default because the pre-x9t vacuum drop visibly evaporated there;
# it can be reduced independently after the kinetic closure is qualified.
export TARGET=wall
export RUN_ROOT="${RUN_ROOT:-runs/0493x9t_vacuum_drop_reflection}"
export GAMMA="${GAMMA:-20}"
export DT="${DT:-0.002}"
export KBT="${KBT:-0.125}"
export LIQUID_MASS="${LIQUID_MASS:-1.0}"
export ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
export RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
export GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
export THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
export THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
export THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
export THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
export THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

export SIGMA_ACTIVE="${SIGMA_ACTIVE:-9450.0}"
export SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"
export KINETIC_REFLECTION_FRACTION="${KINETIC_REFLECTION_FRACTION:-1.0}"
export EVAPORATION_TARGET_TYPE="${EVAPORATION_TARGET_TYPE:--1}"

export DROP_RADIUS_CELLS="${DROP_RADIUS_CELLS:-40}"
export DROP_CENTER_X="${DROP_CENTER_X:-1.5625}"
export DROP_CENTER_Y="${DROP_CENTER_Y:-0.78125}"
export DROP_VX="${DROP_VX:-0.0}"
export DROP_VY="${DROP_VY:-0.0}"
export GRAVITY_Y="${GRAVITY_Y:-0.0}"
export PUDDLE_DEPTH_CELLS="${PUDDLE_DEPTH_CELLS:-40}"

export STEPS="${STEPS:-5000}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-20}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-10}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"

printf '%s\n' \
  "[0493x9t-suite] qualification=vacuum-drop VK-fluid" \
  "[0493x9t-suite] gamma=$GAMMA dt=$DT kBT=$KBT mass=$LIQUID_MASS rotation=$ROTATION_ANGLE" \
  "[0493x9t-suite] sigma=$SIGMA_ACTIVE r=$KINETIC_REFLECTION_FRACTION evapTarget=$EVAPORATION_TARGET_TYPE" \
  "[0493x9t-suite] drop R/h=$DROP_RADIUS_CELLS center=($DROP_CENTER_X,$DROP_CENTER_Y) v=($DROP_VX,$DROP_VY) g=$GRAVITY_Y"

bash scripts/run_0493x9s_splash.sh

CSV="$RUN_ROOT/output/cuda_phase_kinetic_reflection_0493x9t.csv"
if [[ -f "$CSV" ]]; then
  python3 scripts/analyze_0493x9t_reflection.py --csv "$CSV"
else
  echo "[0493x9t-suite] WARNING audit CSV absent: $CSV" >&2
fi

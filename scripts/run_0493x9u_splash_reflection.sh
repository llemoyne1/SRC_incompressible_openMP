#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
export TARGET="${TARGET:-wall}"
export RUN_ROOT="${RUN_ROOT:-runs/0493x9u_splash_${TARGET}}"
export KINETIC_REFLECTION_FRACTION="${KINETIC_REFLECTION_FRACTION:-1.0}"
export EVAPORATION_TARGET_TYPE="${EVAPORATION_TARGET_TYPE:--1}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
printf '[0493x9u-splash] target=%s r=%s runRoot=%s\n' "$TARGET" "$KINETIC_REFLECTION_FRACTION" "$RUN_ROOT"
bash scripts/run_0493x9s_splash.sh
CSV="$RUN_ROOT/output/cuda_phase_kinetic_reflection_0493x9u.csv"
[[ -f "$CSV" ]] && python3 scripts/analyze_0493x9u_reflection.py --csv "$CSV"

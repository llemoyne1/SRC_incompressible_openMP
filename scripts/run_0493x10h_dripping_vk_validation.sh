#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export RUN_ROOT="${RUN_ROOT:-runs/0493x10h_dripping_vk_validation}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"

printf '%s\n' \
  "[0493x10h-drip] VK dripping capability with MOBILE interface semantics" \
  "[0493x10h-drip] non-donor liquid may advance alpha into vacuum; relative thermal donors are reflected" \
  "[0493x10h-drip] x10g global single-component reservoir still limits interpretation after pinch-off"

bash scripts/run_0493x10g_dripping_vk_validation.sh

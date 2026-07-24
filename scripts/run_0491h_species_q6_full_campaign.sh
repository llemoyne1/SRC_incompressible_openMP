#!/usr/bin/env bash
set -euo pipefail

# 0491h full validation campaign.
# Defaults launch:
#   - path matrix: 3 seeds x 1000 steps;
#   - strict resident, energy, boundary/Darcy and custom checks at 1000 steps;
#   - long src-q6 and src-q6-resampling checks at 10000 steps.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

RUN_ROOT="${RUN_ROOT:-runs/0491h_species_q6_full_campaign}"
VALIDATION_PROFILE="${VALIDATION_PROFILE:-full}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"

export RUN_ROOT VALIDATION_PROFILE BIN
export LIVE_VIS_ENABLE LIVE_VIS_HOLD_ON_EXIT FILTERED_RECORDING_ENABLE

echo "[0491h-full] root=$RUN_ROOT profile=$VALIDATION_PROFILE bin=$BIN"
echo "[0491h-full] path matrix: seeds='${PATH_SEEDS:-491101 491102 491103}' steps=${PATH_STEPS:-1000}"
echo "[0491h-full] long src-q6=${LONG_Q6_STEPS:-10000} long src-q6-resampling=${LONG_RESAMPLING_Q6_STEPS:-10000}"

bash scripts/run_0491h_species_q6_software_validation.sh

#!/usr/bin/env bash
set -euo pipefail

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0461a}"
: "${BASE_STRESS_ROOT:=runs/0463_sparse_gate_endurance}"
: "${STEPS:=1000}"
: "${SUMMARY_EVERY:=100}"
: "${DEVICE_GATE_EVERY:=100}"
: "${SEEDS:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_PROGRESS:=1}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"

BIN="$BIN" \
BASE_STRESS_ROOT="$BASE_STRESS_ROOT" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
SEEDS="$SEEDS" \
LIVE_PROGRESS="$LIVE_PROGRESS" \
RUN_MODES="$RUN_MODES" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
bash scripts/run_0462_sparse_gate_stress.sh

#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0438h clean periodic equivalence profile.
# Purpose: validate path identity only where the physics should be identical:
# periodic, wall-free, no chi/Darcy, no inlet/outlet, no corrective guards.
#
# This wrapper introduces no new solver parameter.  It only sets existing
# environment controls before delegating to the 0438b sweep orchestrator.

: "${BIN:?Set BIN to the CUDA resident executable to test}"

export MPCD_CUDA_ACTIVE_PREFIX_HOST_TAIL_FULL_REPAIR_0315H="${MPCD_CUDA_ACTIVE_PREFIX_HOST_TAIL_FULL_REPAIR_0315H:-1}"
export MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_FULL_ROLE_TAIL_0315K="${MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_FULL_ROLE_TAIL_0315K:-1}"

# Disable CUDA-local resampling auxiliaries for the equivalence matrix.  These
# are robustness/performance mechanisms, not part of the clean wall-free identity
# comparison.
export MASS_RECONDITION_ENABLE="${MASS_RECONDITION_ENABLE:-0}"
export RESAMPLING_SURVEY_ENABLE="${RESAMPLING_SURVEY_ENABLE:-0}"
export RESAMPLING_ADAPTIVE_FLAG_ENABLE="${RESAMPLING_ADAPTIVE_FLAG_ENABLE:-0}"
export CUDA_EMPTY_REFILL_ENABLE_OVERRIDE="${CUDA_EMPTY_REFILL_ENABLE_OVERRIDE:-0}"
export GUARD_EVERY="${GUARD_EVERY:-1000000000}"

# Make the CPU population guard inert in homogeneous periodic runs without
# introducing a new public solver flag.
export GUARD_NMIN="${GUARD_NMIN:-1}"
export GUARD_NTARGET="${GUARD_NTARGET:-40}"
export GUARD_NMAX="${GUARD_NMAX:-100000}"

# Keep the CPU weighted-resampling reconditioning phases that are part of the
# reference path, but keep the mass guard off for identity tests.
export RESAMPLING_EXTRACTION_ENABLE="${RESAMPLING_EXTRACTION_ENABLE:-true}"
export RESAMPLING_INSERTION_ENABLE="${RESAMPLING_INSERTION_ENABLE:-true}"
export RESAMPLING_REMAP_ENABLE="${RESAMPLING_REMAP_ENABLE:-true}"
export RESAMPLING_THERMAL_RENORMALIZATION_ENABLE="${RESAMPLING_THERMAL_RENORMALIZATION_ENABLE:-true}"
export RESAMPLING_MASS_GUARD_ENABLE="${RESAMPLING_MASS_GUARD_ENABLE:-false}"

CASE="${CASE:-shear}"
GAMMAS="${GAMMAS:-40}"
SEEDS="${SEEDS:-1628638 1628639 1628640}"
RUN_MODES="${RUN_MODES:-src src-resampling src-q6 src-q6-resampling}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
FAIL_ON_ANY="${FAIL_ON_ANY:-1}"

if [[ "$CASE" == "shear" ]]; then
  STEPS_LIST="${STEPS_LIST:-2000}"
  BASE_SWEEP_ROOT="${BASE_SWEEP_ROOT:-runs/0438h_shear_periodic_equiv_clean_g40_s2000_3seeds}"
elif [[ "$CASE" == "tg" ]]; then
  STEPS_LIST="${STEPS_LIST:-1000}"
  BASE_SWEEP_ROOT="${BASE_SWEEP_ROOT:-runs/0438h_tg_periodic_equiv_clean_g40_s1000_3seeds}"
else
  echo "[0438h] ERROR unsupported CASE=$CASE; expected shear or tg" >&2
  exit 2
fi

export CASE GAMMAS STEPS_LIST SEEDS RUN_MODES BASE_SWEEP_ROOT SUMMARY_EVERY LIVE_VIS_ENABLE FILTERED_RECORDING_ENABLE FAIL_ON_ANY

bash scripts/run_0438b_periodic_equiv_sweep.sh

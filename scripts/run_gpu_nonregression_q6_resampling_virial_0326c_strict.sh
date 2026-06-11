#!/usr/bin/env bash
set -euo pipefail

# 0326c strict audit wrapper.
# By default it does not rerun the solver; it parses an existing 0326b artifact
# and checks whether Q6/resampling/virial were actually exercised.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR_0326B=${ART_DIR_0326B:-dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326b}
OUT_DIR_0326C=${OUT_DIR_0326C:-dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326c_strict}
RUN_0326B_FIRST=${RUN_0326B_FIRST:-0}

if [[ "$RUN_0326B_FIRST" == "1" ]]; then
  echo "[0326c-strict] running 0326b first"
  SRC_BUILD=${SRC_BUILD:-0} NX=${NX:-32} NY=${NY:-32} STEPS=${STEPS:-80} GAMMA=${GAMMA:-20} INACTIVE_SLOTS=${INACTIVE_SLOTS:-100000} \
    bash scripts/run_gpu_nonregression_q6_resampling_virial_0326b.sh
fi

python3 scripts/summarize_gpu_nonregression_q6_resampling_virial_0326c_strict.py "$ART_DIR_0326B" "$OUT_DIR_0326C"

#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

RUN_ROOT="${RUN_ROOT:-runs/0493w6_independent_masked_postapply_diagnostic}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export RUN_ROOT LIVE_PROGRESS

# Reuse the already-qualified 0493w5 state matrix and selectivity checks, then
# add the 0493w6 diagnostic contract on the same four one-step runs.
bash scripts/run_0493w5_independent_masked_periodic_smoke.sh
python3 scripts/check_0493w6_independent_masked_postapply.py --run-root "$RUN_ROOT"

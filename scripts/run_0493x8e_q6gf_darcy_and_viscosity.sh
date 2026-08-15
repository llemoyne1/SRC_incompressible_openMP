#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}" bash scripts/run_0493x8e_q6gf_tg_viscosity_ensemble.sh
LIVE_PROGRESS="${LIVE_PROGRESS:-1}" bash scripts/run_0493x8e_q6gf_darcy_alpha_sweep.sh
echo "[0493x8e] Then run MATLAB analyzer shown by the sweep runner."

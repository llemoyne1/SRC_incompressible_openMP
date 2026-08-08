#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

python3 scripts/check_0493x5a2_generator_profiles.py
LIVE_PROGRESS=1 PREFLIGHT_ONLY=1 \
  BASE_RUN_ROOT=runs/0493x5b_nonregression_preflight \
  bash scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh

echo "[0493x5b-nonregression] PASS"

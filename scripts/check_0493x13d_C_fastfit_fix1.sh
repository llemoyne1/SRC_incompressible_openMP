#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
python3 -m py_compile scripts/analyze_0493x13d_C_damped_mode.py
bash -n scripts/run_0493x13d_C_damped_analysis.sh
python3 scripts/analyze_0493x13d_C_damped_mode.py --repo-root "$ROOT" --benchmark-self-test
printf '%s\n' '[0493x13d-C-fastfit-fix1-check] syntax/selftest/benchmark PASS'

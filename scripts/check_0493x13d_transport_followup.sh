#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
for f in scripts/run_0493x13d_H_longwave_Ny256.sh scripts/analyze_0493x13d_H_longwave_Ny256.py scripts/analyze_0493x13d_C_damped_mode.py scripts/run_0493x13d_C_damped_analysis.sh; do [[ -f "$f" ]] || { echo "missing $f" >&2; exit 2; }; done
for dep in scripts/generate_0493x13b_shear_state.py scripts/analyze_0493x13b_constitutive_transport.py scripts/analyze_0493w1_src_fluid_calibrator.py; do [[ -f "$dep" ]] || { echo "missing dependency $dep" >&2; exit 2; }; done
bash -n scripts/run_0493x13d_H_longwave_Ny256.sh scripts/run_0493x13d_C_damped_analysis.sh
python3 -m py_compile scripts/analyze_0493x13d_H_longwave_Ny256.py scripts/analyze_0493x13d_C_damped_mode.py
python3 scripts/analyze_0493x13d_C_damped_mode.py --repo-root "$ROOT" --self-test
PREFLIGHT_ONLY=1 PREFLIGHT_FIRST_SEED_ONLY=1 bash scripts/run_0493x13d_H_longwave_Ny256.sh
printf '%s\n' '[0493x13d-check] syntax/dependencies/Cdamp-selftest/H256-preflight PASS'

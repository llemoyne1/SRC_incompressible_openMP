#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
python3 scripts/check_0493x17d_fix2_full_particle_coverage.py || exit $?
python3 -m py_compile scripts/analyze_0493x17d_fixed_membrane_publishable.py scripts/check_0493x17d_fix2_full_particle_coverage.py || exit $?
bash -n scripts/run_0493x17d_fixed_membrane_publishable.sh scripts/apply_0493x17d_fix2_full_particle_coverage.sh || exit $?
echo "[0493x17d-fix2-check] structural checks PASS"

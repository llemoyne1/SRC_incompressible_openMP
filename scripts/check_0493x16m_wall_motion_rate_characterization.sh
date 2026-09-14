#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
fail=0
pass(){ echo "PASS $1"; }
bad(){ echo "FAIL $1" >&2; fail=1; }
[[ -f scripts/run_0493x16m_wall_motion_rate_characterization.sh ]] && bash -n scripts/run_0493x16m_wall_motion_rate_characterization.sh && pass runner_syntax || bad runner_syntax
[[ -f scripts/analyze_0493x16m_wall_motion_rate_characterization.py ]] && python3 -m py_compile scripts/analyze_0493x16m_wall_motion_rate_characterization.py && pass analyzer_syntax || bad analyzer_syntax
grep -q 'q2Root=x16m-bisection-1e-8cell' src/cuda_q6_resident_0400.cu && pass x16m_present || bad x16m_present
grep -q 'DT_FIXED="${DT_FIXED:-0.002}"' scripts/run_0493x16m_wall_motion_rate_characterization.sh && pass fluid_dt_fixed || bad fluid_dt_fixed
grep -q 'for factor in 1 2 4' scripts/run_0493x16m_wall_motion_rate_characterization.sh && pass rate_sweep_1_2_4 || bad rate_sweep_1_2_4
grep -q 'DEFORM_PERIOD_STEPS="$period"' scripts/run_0493x16m_wall_motion_rate_characterization.sh && pass deformation_period_only || bad deformation_period_only
grep -q 'DUMP_STATE_EVERY=0' scripts/run_0493x16m_wall_motion_rate_characterization.sh && pass no_large_dumps || bad no_large_dumps
(( fail == 0 )) || exit 2
echo "0493x16m wall-motion-rate characterization checks: ALL PASS"

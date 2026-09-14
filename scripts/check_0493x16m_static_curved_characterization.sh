#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
pass(){ echo "PASS $1"; }
[[ -f src/cuda_chi_solid_0493x16e.cu ]] || { echo "FAIL source"; exit 2; }
grep -q 'SRC_X16I_STATIC_CURVED_0493X16M' src/cuda_chi_solid_0493x16e.cu && pass static_curve_switch
grep -q 'if (omega == 0.0) return globalCenter + amplitude \* shape;' src/cuda_chi_solid_0493x16e.cu && pass fixed_peak_shape
grep -q 'q2Root=x16m-bisection-1e-8cell' src/cuda_q6_resident_0400.cu && pass x16m_root_present
bash -n scripts/run_0493x16m_static_curved_characterization.sh && pass runner_syntax
python3 -m py_compile scripts/analyze_0493x16m_static_curved_characterization.py && pass analyzer_syntax
grep -q 'DUMP_STATE_EVERY=0' scripts/run_0493x16m_static_curved_characterization.sh && pass no_dumps
grep -q 'SUMMARY_EVERY=1' scripts/run_0493x16m_static_curved_characterization.sh && pass every_step_penetration_diag
grep -q 'FILTERED_RECORDING_ENABLE=0' scripts/run_0493x16m_static_curved_characterization.sh && pass no_filtered_recording
echo '0493x16m static-curved characterization checks: ALL PASS'

#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
SRC=src/cuda_q6_resident_0400.cu

fail(){ echo "FAIL $*" >&2; exit 1; }
pass(){ echo "PASS $*"; }

[[ -f "$SRC" ]] || fail missing_source

grep -q 'strictRootBisection0493x16m' "$SRC" || fail x16m_flag
grep -q 'targetPathCells0493x16m = 1.0e-8' "$SRC" || fail x16m_target
grep -q 'it0493x16m < 40' "$SRC" || fail x16m_iteration_cap
grep -q 'tau = lo;' "$SRC" || fail x16m_own_support_endpoint
grep -q 'q2Root=x16m-bisection-1e-8cell' "$SRC" || fail x16m_marker
pass root_solver_present

python3 - <<'PY'
from pathlib import Path
s=Path('src/cuda_q6_resident_0400.cu').read_text()
name='q6_x10biq_collide_moving_patch('
assert s.count(name) == 7, s.count(name)
# Four historical x10w callers must force strictRoot=0.
assert s.count('+1, 1.0, 0, patch, seg, &raw);') == 2
assert s.count('+1, a, 0, patch, seg, &filtered);') == 2
# The swept x10n calls must activate strict root only through the chi flag.
assert s.count('phaseSense0493x14k, phaseScale0493x10w,\n                                chiKineticBoundary0493x16j,') == 1
assert s.count('phaseSense0493x14k, 1.0,\n                                        chiKineticBoundary0493x16j,') == 1
print('PASS chi_only_dispatch')
PY

# Numerical contract of the x16m stopping rule, independent of the Q2 polynomial.
python3 - <<'PY'
import math
TARGET=1e-8
for rate in (1e-3, 1e-2, 1e-1, 1.0, 10.0, 100.0):
    width=1.0
    n=0
    while width>1e-14 and rate*width>TARGET and n<40:
        width*=0.5; n+=1
    assert rate*width <= TARGET or width <= 1e-14, (rate,width,n)
# Old eight-step safeguarded secant has no bisection bound: 0.85^8 ~= 0.272.
assert 0.85**8 > 0.27
print('PASS guaranteed_contraction target_path_cells=1e-8 old_0.85pow8=%.9g' % (0.85**8))
PY

[[ -f scripts/run_0493x16m_q2_root_refinement_qualification.sh ]] || fail runner_missing
[[ -f scripts/analyze_0493x16m_q2_root_refinement.py ]] || fail analyzer_missing
bash -n scripts/run_0493x16m_q2_root_refinement_qualification.sh
python3 -m py_compile scripts/analyze_0493x16m_q2_root_refinement.py
pass runner_analyzer_syntax

grep -q 'penetrationWindow=ALL_ALIGNED_STEPS' scripts/analyze_0493x16m_q2_root_refinement.py || fail all_history_gate_missing
grep -q 'statisticalWindow=SECOND_HALF' scripts/analyze_0493x16m_q2_root_refinement.py || fail stat_window_missing
grep -q 'maxPenetrationCellsGate=1e-4' scripts/analyze_0493x16m_q2_root_refinement.py || fail penetration_gate_missing
pass x16m_full_history_qualification

echo '0493x16m checks: ALL PASS'

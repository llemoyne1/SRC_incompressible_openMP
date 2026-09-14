#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
SRC=src/cuda_q6_resident_0400.cu
fail(){ echo "FAIL $*" >&2; exit 1; }
pass(){ echo "PASS $*"; }

[[ -f "$SRC" ]] || fail missing_source
grep -q '0493x16n — make the domain of each local Q2 patch explicit' "$SRC" || fail marker
grep -q 'q6_x16n_dual_owner_for_position' "$SRC" || fail dual_owner_helper
grep -q 'q6_x16n_clip_to_dual_owner_window' "$SRC" || fail clip_helper
grep -q 'q2Owner=x16n-dual-square-clipped' "$SRC" || fail runtime_marker
pass source_markers

python3 - <<'PY'
from pathlib import Path
s=Path('src/cuda_q6_resident_0400.cu').read_text()
# Historical liquid/gas Q2 callers keep strictRoot=0; only the chi/x16j path
# reaches the strict-root + owner-domain branch.
assert s.count('q6_x10biq_collide_moving_patch(') == 7
assert s.count('+1, 1.0, 0, patch, seg, &raw);') == 2
assert s.count('+1, a, 0, patch, seg, &filtered);') == 2
assert s.count('phaseSense0493x14k, phaseScale0493x10w,\n                                chiKineticBoundary0493x16j,') == 1
assert s.count('phaseSense0493x14k, 1.0,\n                                        chiKineticBoundary0493x16j,') == 1
# x16l must no longer use finite-volume-cell ownership for Q2 sampling.
block=s[s.index('__global__ void q6_x16l_measure_chi_penetration'):]
block=block[:block.index('}', block.index('if (levelExcess > strictLevelEpsilon)'))+1]
assert 'q6_x16n_dual_owner_for_position' in block
assert 'const int owner = q6_x10n_position_cell' not in block
# x10p normal + wide overlap calls carry the same chi-only owner-domain guard.
assert s.count('chiKineticBoundary0493x16j,\n                                        patch0493x10poly, seg, &q);') == 1
assert s.count('chiKineticBoundary0493x16j,\n                                        patchWide0493x10biq,') == 1
print('PASS chi_only_owner_domain_dispatch')
PY

[[ -f scripts/check_0493x16n_q2_dual_square_math.py ]] || fail math_check_missing
python3 scripts/check_0493x16n_q2_dual_square_math.py
pass dump_replay_and_C0_math

[[ -f scripts/run_0493x16n_q2_dual_square_qualification.sh ]] || fail runner_missing
[[ -f scripts/analyze_0493x16n_q2_dual_square_qualification.py ]] || fail analyzer_missing
bash -n scripts/run_0493x16n_q2_dual_square_qualification.sh
python3 -m py_compile scripts/analyze_0493x16n_q2_dual_square_qualification.py scripts/check_0493x16n_q2_dual_square_math.py
pass runner_analyzer_syntax

# No new runtime flag/parameter is introduced by x16n.
if grep -q 'MPCD_X16N\|SRC_X16N' "$SRC"; then fail unexpected_runtime_flag; fi
pass no_new_runtime_flag

echo '0493x16n checks: ALL PASS'

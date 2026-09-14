#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
SRC=src/cuda_q6_resident_0400.cu
PATCH=patches/0493x16q_chi_overlap_deadzone_fix.patch
[[ -f "$SRC" ]] || { echo '[0493x16q-check] missing source' >&2; exit 2; }
[[ -f "$PATCH" ]] || { echo '[0493x16q-check] missing patch' >&2; exit 2; }

grep -q 'q2Topology=x16p-boundary-root-trace' "$SRC"
grep -q 'overlapTol=x16q-chi-1e-10h' "$SRC"
grep -q '0493x16q: the chi/Q2 swept path rejects an event' "$SRC"
echo 'PASS source_markers'

python3 - "$SRC" "$PATCH" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(); p=Path(sys.argv[2]).read_text()
needle='''const double sideTol0493x10p = chiKineticBoundary0493x16j\n                    ? 1.0e-10 * h0493x10p\n                    : 1.0e-8 * fmax(1.0, h0493x10p);'''
assert needle in s
# Historical liquid/gas tolerance remains exactly the pre-x16q expression in the false branch.
assert ': 1.0e-8 * fmax(1.0, h0493x10p);' in s
# Q2 swept-side gate remains untouched.
assert 'const double sideTol = 1.0e-10;' in s
assert 'if (f0 < -sideTol) return false;' in s
# No new runtime/config switch.
assert 'MPCD_X16Q' not in s and 'SRC_X16Q' not in s
# Patch scope is resident CUDA only.
mods=[ln for ln in p.splitlines() if ln.startswith('--- a/')]
assert mods == ['--- a/src/cuda_q6_resident_0400.cu'], mods
# x16p topology and prior geometry chain stay present.
for marker in ('q2Root=x16m-bisection-1e-8cell','q2Owner=x16n-dual-square-clipped','q2Edges=x16o-q2-edge-roots','q2Topology=x16p-boundary-root-trace'):
    assert marker in s
print('PASS chi_only_overlap_tolerance')
print('PASS historical_phase_tolerance_unchanged')
print('PASS q2_swept_gate_unchanged')
print('PASS no_new_runtime_flag')
print('PASS source_patch_scope')
PY
python3 scripts/check_0493x16q_overlap_deadzone_math.py
bash -n scripts/run_0493x16q_overlap_deadzone_smoke.sh
bash -n scripts/run_0493x16q_overlap_deadzone_qualification.sh
python3 -m py_compile scripts/analyze_0493x16q_overlap_deadzone_smoke.py scripts/analyze_0493x16q_overlap_deadzone_qualification.py
echo '0493x16q checks: ALL PASS'

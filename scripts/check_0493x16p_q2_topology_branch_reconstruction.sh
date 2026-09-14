#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
SRC=src/cuda_q6_resident_0400.cu
PATCH=patches/0493x16p_q2_topology_branch_reconstruction.patch
[[ -f "$SRC" ]] || { echo '[0493x16p-check] missing source' >&2; exit 2; }

grep -q '0493x16p: full Q2 boundary-root topology for the chi material wall' "$SRC"
grep -q 'q6_x16p_q2_unit_edge_roots' "$SRC"
grep -q 'q6_x16p_collect_boundary_roots' "$SRC"
grep -q 'q6_x16p_trace_partner' "$SRC"
grep -q 'q2Topology=x16p-boundary-root-trace' "$SRC"
grep -q 'q2Edges=x16o-q2-edge-roots' "$SRC"
grep -q 'q2Owner=x16n-dual-square-clipped' "$SRC"
grep -q 'q2Root=x16m-bisection-1e-8cell' "$SRC"
echo 'PASS source_markers'

python3 - "$SRC" "$PATCH" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(); p=Path(sys.argv[2]).read_text()
assert 'if (!useSolidVelocity0493x16j && (code == 0 || code == 15)) continue;' in s
assert 'if (useSolidVelocity0493x16j) {' in s
assert 'q6_x16p_collect_boundary_roots(' in s
assert 'nr > 4' in s and 'nr != 0 && nr != 2 && nr != 4' in s
assert 'q6_x16p_trace_partner(qtop, roots, 0)' in s
# Historical builders are retained; x16p is entered only via useSolidVelocity0493x16j.
assert s.count('q6_x10o_edge_crossing_q6_thermal(') >= 4
assert s.count('q6_x10n_edge_crossing(') >= 4
assert 'MPCD_X16P' not in s and 'SRC_X16P' not in s
# Patch must only modify the resident CUDA source; no hidden parameter/header changes.
mods=[ln for ln in p.splitlines() if ln.startswith('--- a/')]
assert mods == ['--- a/src/cuda_q6_resident_0400.cu'], mods
print('PASS chi_only_topology_dispatch')
print('PASS historical_phase_builders_retained')
print('PASS two_segment_capacity_enforced')
print('PASS no_new_runtime_flag')
print('PASS source_patch_scope')
PY

python3 scripts/check_0493x16p_q2_topology_math.py
bash -n scripts/run_0493x16p_q2_topology_qualification.sh
python3 -m py_compile scripts/analyze_0493x16p_q2_topology_qualification.py

echo '0493x16p checks: ALL PASS'

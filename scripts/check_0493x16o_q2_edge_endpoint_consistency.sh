#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
SRC=src/cuda_q6_resident_0400.cu
[[ -f "$SRC" ]] || { echo '[0493x16o-check] missing source' >&2; exit 2; }

grep -q '0493x16o: Q2-consistent edge root for the chi material wall' "$SRC"
grep -q 'q6_x16o_q2_unit_edge_root' "$SRC"
grep -q 'q6_x16o_q2_edge_theta' "$SRC"
grep -q 'q2Edges=x16o-q2-edge-roots' "$SRC"
grep -q 'q2Owner=x16n-dual-square-clipped' "$SRC"
grep -q 'q2Root=x16m-bisection-1e-8cell' "$SRC"

echo 'PASS source_markers'

# The changed edge helper is reachable only from the pre-existing chi solid
# branch. Historical x10o thermal and plain x10n edge builders remain present.
python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert s.count('} else if (useSolidVelocity0493x16j) {') == 1
block=s.split('} else if (useSolidVelocity0493x16j) {',1)[1].split('} else {',1)[0]
assert block.count('q6_x16j_edge_crossing_chi_solid') == 4
assert block.count('owner, 0, alpha') == 1
assert block.count('owner, 1, alpha') == 1
assert block.count('owner, 2, alpha') == 1
assert block.count('owner, 3, alpha') == 1
assert 'q6_x10o_edge_crossing_q6_thermal' in s
assert 'q6_x10n_edge_crossing(' in s
# No new environment/runtime flag: x16o is a consistency correction to the
# already-selected chi path, not a selectable physics mode.
assert 'MPCD_X16O' not in s and 'SRC_X16O' not in s
print('PASS chi_only_dispatch_historical_edges_unchanged')
print('PASS no_new_runtime_flag')
PY

python3 scripts/check_0493x16o_q2_edge_endpoint_math.py
bash -n scripts/run_0493x16o_q2_edge_endpoint_qualification.sh
python3 -m py_compile scripts/analyze_0493x16o_q2_edge_endpoint_qualification.py

echo '0493x16o checks: ALL PASS'

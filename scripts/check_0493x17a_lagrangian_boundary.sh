#!/usr/bin/env bash
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
SRC=src/cuda_q6_resident_0400.cu
fail(){ echo "[0493x17a] FAIL $*" >&2; exit 2; }
pass(){ echo "[0493x17a] PASS $*"; }
[[ -f "$SRC" ]] || fail "missing $SRC"
for marker in \
  '0493x17a — PERSISTENT LAGRANGIAN MATERIAL BOUNDARY EXTRACTED FROM chi=0.5' \
  'backend=x17a-lagrangian-edge-mesh' \
  'source=initial-chi-0.5 chiReextract=never' \
  'collision=space-time-moving-segment-quadratic' \
  'q6_x17a_extract_initial_chi_contour' \
  'q6_x17a_apply_lagrangian_boundary' \
  'q6_x17a_advance_lagrangian_edges'; do
  grep -q "$marker" "$SRC" || fail "source marker absent: $marker"
done
pass source_markers
python3 - "$SRC" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8').read()
marker=s.index('// 0493x17a keeps the x16j public switch')
a=s.index('bool apply_chi_kinetic_boundary_0493x16j(', marker)
b=s.index('\nbool supported_subset_0400',a)
blk=s[a:b]
assert 'q6_x17a_apply_lagrangian_boundary<<<' in blk
assert 'q6_x10n_apply_continuous_moving_interface<<<' not in blk
assert 'q6_x10n_build_continuous_interface<<<' not in blk
assert 'cuda_darcy_brinkman_0343_device_chi_field' in blk
assert 'params.chiKineticBoundaryMode != "specular"' in blk
assert 'chiReextract=never' in blk
print('[0493x17a] PASS chi_specular_backend_replaced_only')
PY
[[ $? -eq 0 ]] || exit $?
# No new public parameter or input format is introduced by x17a.
if grep -R -n '0493x17a' include/simulation_params.h src/params_io_base.cpp 2>/dev/null | grep -q .; then
  fail 'x17a unexpectedly changed public parameter parsing'
fi
pass no_new_user_parameter
# Historical Darcy implementation is intentionally not part of this patch.
grep -q 'darcyBrinkmanEnable' src/params_io_base.cpp || fail 'Darcy parameter path unexpectedly missing'
pass historical_darcy_path_present
python3 scripts/check_0493x17a_lagrangian_boundary_math.py || exit $?
echo '[0493x17a] ALL CHECKS PASS'

#!/usr/bin/env bash
ROOT="${ROOT:-$(pwd)}"
cd "$ROOT" || exit $?
fail=0
pass(){ echo "[0493x16l-check] PASS $1"; }
bad(){ echo "[0493x16l-check] FAIL $1" >&2; fail=1; }

for f in include/cuda_q6_resident_0400.h src/cuda_q6_resident_0400.cu src/src_mpcd_base.cpp \
         scripts/run_0493x16l_chi_penetration_qualification.sh \
         scripts/analyze_0493x16l_chi_penetration.py; do
  [[ -s "$f" ]] || bad "missing $f"
done

if grep -q 'cuda_q6_record_chi_penetration_poststream_0493x16l' include/cuda_q6_resident_0400.h && \
   grep -q 'q6_x16l_measure_chi_penetration' src/cuda_q6_resident_0400.cu && \
   grep -q 'chi_penetration_0493x16l.csv' src/cuda_q6_resident_0400.cu; then
  pass "Q2 particle-position penetration diagnostic present"
else bad "diagnostic implementation markers"; fi

python3 - <<'PY' || exit 3
from pathlib import Path
s=Path('src/src_mpcd_base.cpp').read_text()
a=s.find('synchronize_chi_solid_dynamics_poststream_0493x16f(')
b=s.find('cuda_q6_record_chi_penetration_poststream_0493x16l(', a)
c=s.find('MPCD_PROFILE_PHASE(result.profile, Collision)', a)
if not (a>=0 and b>a and c>b):
    raise SystemExit('[0493x16l-check] FAIL diagnostic is not post-geometry-sync / pre-collision')
print('[0493x16l-check] PASS timing=poststream_geometry_sync_before_collision')
PY
[[ $? -eq 0 ]] || fail=1

if grep -q 'strictLevelEpsilon0493x16l = 1.0e-6' src/cuda_q6_resident_0400.cu && \
   grep -q 'q6_x10biq_build_patch' src/cuda_q6_resident_0400.cu; then
  pass "strict tolerance and existing x10 Q2 reused"
else bad "Q2/tolerance markers"; fi

if ! grep -RIn '0493x16l' include/simulation_params.h src/params_io_base.cpp >/dev/null; then
  pass "no new simulation parameter"
else bad "unexpected x16l simulation parameter"; fi

if grep -q 'fictitiousMassRelativeDifference0493x16c_INFORMATIONAL' scripts/analyze_0493x16l_chi_penetration.py; then
  pass "x16c fictitious mass informational only"
else bad "x16c still appears to gate final qualification"; fi

if bash -n scripts/run_0493x16l_chi_penetration_qualification.sh; then pass "runner bash syntax"; else bad "runner bash syntax"; fi
if python3 -m py_compile scripts/analyze_0493x16l_chi_penetration.py; then pass "analyzer python syntax"; else bad "analyzer python syntax"; fi
rm -rf scripts/__pycache__

if command -v g++ >/dev/null 2>&1; then
  if g++ -std=c++17 -fsyntax-only -Iinclude src/src_mpcd_base.cpp; then pass "host dispatcher syntax"; else bad "host dispatcher syntax"; fi
fi

if grep -q 'RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"' scripts/run_0493x16j_chi_kinetic_specular_case.sh; then
  pass "filtered recorder still excludes chi"
else bad "cannot confirm 0432 chi exclusion"; fi

if [[ $fail -ne 0 ]]; then exit 2; fi
echo "[0493x16l-check] ALL PASS"

#!/usr/bin/env bash
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
SRC="src/cuda_chi_solid_0493x16e.cu"
fail=0
pass() { echo "PASS $1"; }
bad() { echo "FAIL $1" >&2; fail=1; }

grep -Fq 'cuda_q6_apply_chi_kinetic_boundary_prestream_0493x16j' src/src_mpcd_base.cpp && pass x16j_fix1_prestream || bad x16j_fix1_prestream
grep -Fq 'kineticLevelHalfWidth0493x16k = 2.0 * dx' "$SRC" && pass level_width || bad level_width
grep -Fq '0.5 - sd / (2.0 * kineticLevelHalfWidth0493x16k)' "$SRC" && pass signed_level || bad signed_level
grep -Fq '? static_cast<float>(1.0 - solidLevel0493x16k)' "$SRC" && pass kinetic_chi_provider || bad kinetic_chi_provider
grep -Fq ': (solid > 0.5 ? 0.0f : 1.0f);' "$SRC" && pass historical_binary_branch_preserved || bad historical_binary_branch_preserved

# x16k is limited to the moving-geometry provider and the existing x16c
# diagnostic selector. It must not touch the Darcy forcing law or x10n reflection.
extra=$(grep -RIl '0493x16k' include src 2>/dev/null | grep -Ev '^(include/cuda_chi_solid_0493x16e.h|src/cuda_chi_solid_0493x16e.cu|src/cuda_darcy_brinkman_0343.cu)$' || true)
if [[ -n "$extra" ]]; then bad source_scope; else pass source_scope; fi
grep -Fq 'cuda_chi_solid_0493x16k_device_solid_fraction' include/cuda_chi_solid_0493x16e.h && pass solid_fraction_api || bad solid_fraction_api
grep -Fq 'exactSolidFraction0493x16k' src/cuda_darcy_brinkman_0343.cu && pass fictitious_mass_semantics || bad fictitious_mass_semantics

# Analytic geometry preflight: for a translated planar slab the published
# S=1-chi ramp and its local Q2 interpolant must recover sd=0 independently
# of subcell phase. No numpy/pandas required.
python3 - <<'PY'
import math
Lx=0.5; nx=128; dx=Lx/nx; half=4.0*dx

def S(x,center):
    sd=abs(x-center)-half
    return min(1.0,max(0.0,0.5-sd/(4.0*dx)))

def q2(fm,f0,fp,z):
    d1=0.5*(fp-fm); d2=0.5*(fp-2.0*f0+fm)
    return f0+d1*z+d2*z*z

def root_bisect(fm,f0,fp):
    lo,hi=0.0,1.0
    flo=q2(fm,f0,fp,lo)-0.5
    fhi=q2(fm,f0,fp,hi)-0.5
    if flo==0.0: return lo
    if fhi==0.0: return hi
    if flo*fhi>0.0: raise RuntimeError('Q2 root not bracketed')
    for _ in range(80):
        mid=0.5*(lo+hi); fm0=q2(fm,f0,fp,mid)-0.5
        if flo*fm0<=0.0: hi=mid; fhi=fm0
        else: lo=mid; flo=fm0
    return 0.5*(lo+hi)

worst_edge=0.0; worst_q2=0.0
for k in range(-499,500):
    frac=k/1000.0
    center=(64.0+frac)*dx
    boundary=center-half
    xs=[(i+0.5)*dx for i in range(nx)]
    vals=[S(x,center) for x in xs]
    edge=None
    for i in range(1,nx-2):
        if vals[i] < 0.5 <= vals[i+1]:
            edge=i; break
    if edge is None: raise RuntimeError('no rising wall edge')
    t=(0.5-vals[edge])/(vals[edge+1]-vals[edge])
    xedge=xs[edge]+t*dx
    worst_edge=max(worst_edge,abs(xedge-boundary)/dx)
    z=root_bisect(vals[edge-1],vals[edge],vals[edge+1])
    xq2=xs[edge]+z*dx
    worst_q2=max(worst_q2,abs(xq2-boundary)/dx)
if worst_edge > 5e-13 or worst_q2 > 5e-12:
    raise SystemExit(f'FAIL geometry_covariance edge={worst_edge:.3e} q2={worst_q2:.3e}')
print(f'PASS geometry_covariance edgeErrCells={worst_edge:.3e} q2ErrCells={worst_q2:.3e}')
PY
[[ $? -eq 0 ]] || fail=1

bash -n scripts/run_0493x16k_galilean_geometry_smoke.sh && pass runner_syntax || bad runner_syntax
python3 -m py_compile scripts/analyze_0493x16k_galilean_geometry_smoke.py && pass analyzer_syntax || bad analyzer_syntax

# 0432 does not support chi; x16k files must not request it.
if grep -REn 'RECORD_FIELDS=.*chi|recordFields[[:space:]]*=.*chi' scripts/run_0493x16k_galilean_geometry_smoke.sh >/dev/null; then
  bad recorder_no_chi
else
  pass recorder_no_chi
fi

exit "$fail"

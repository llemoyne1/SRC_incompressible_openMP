#!/usr/bin/env python3
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
req={
    'include/simulation_params.h':['chiSolidMembraneBendingStiffness'],
    'src/params_io_base.cpp':['chiSolidMembraneBendingStiffness'],
    'src/cuda_q6_resident_0400.cu':['q6_x17d_bending_internal_forces','bendingEnergy','maxAbsAngleChange'],
    'scripts/run_0493x17d_visible_membrane.sh':['MEMBRANE_K_BENDING','chiSolidMembraneBendingStiffness = $MEMBRANE_K_BENDING'],
}
for rel,needles in req.items():
    text=(ROOT/rel).read_text()
    for n in needles:
        if n not in text:
            raise SystemExit(f'FAIL missing {n!r} in {rel}')

# Analytical sanity check of the angular force used by the CUDA kernel.
def wrap(a): return math.atan2(math.sin(a),math.cos(a))
def energy(P,B=5e-4):
    p,c,n=P; p0=(-1.0,0.0); c0=(0.0,0.0); n0=(1.0,0.0)
    ax,ay=p[0]-c[0],p[1]-c[1]; bx,by=n[0]-c[0],n[1]-c[1]
    a0x,a0y=p0[0]-c0[0],p0[1]-c0[1]; b0x,b0y=n0[0]-c0[0],n0[1]-c0[1]
    th=math.atan2(ax*by-ay*bx,ax*bx+ay*by)
    th0=math.atan2(a0x*b0y-a0y*b0x,a0x*b0x+a0y*b0y)
    d=wrap(th-th0); l0=1.0
    return 0.5*(B/l0)*d*d

def force(P,B=5e-4):
    p,c,n=P
    ax,ay=p[0]-c[0],p[1]-c[1]; bx,by=n[0]-c[0],n[1]-c[1]
    a2=ax*ax+ay*ay; b2=bx*bx+by*by
    th=math.atan2(ax*by-ay*bx,ax*bx+ay*by)
    d=wrap(th-math.pi)
    k=B
    gax,gay=ay/a2,-ax/a2; gbx,gby=-by/b2,bx/b2
    sc=-k*d
    fm=(sc*gax,sc*gay); fp=(sc*gbx,sc*gby)
    fi=(-fm[0]-fp[0],-fm[1]-fp[1])
    return [fm,fi,fp]

P=[(-1.0,0.10),(0.0,0.0),(1.0,-0.05)]
F=force(P)
if abs(sum(q[0] for q in F))>1e-12 or abs(sum(q[1] for q in F))>1e-12:
    raise SystemExit('FAIL bending force does not conserve net force')
eps=1e-6
for i in range(3):
    for j in range(2):
        A=[list(q) for q in P]; A[i][j]+=eps
        ep=energy([tuple(q) for q in A])
        A=[list(q) for q in P]; A[i][j]-=eps
        em=energy([tuple(q) for q in A])
        fn=-(ep-em)/(2*eps)
        if abs(fn-F[i][j])>5e-9:
            raise SystemExit(f'FAIL finite-difference bending force i={i} j={j}: {F[i][j]} vs {fn}')
print('PASS angular-bending force finite-difference + net-force closure')
print('PASS fix3 structural checks')

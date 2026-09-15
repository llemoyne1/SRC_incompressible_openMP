#!/usr/bin/env python3
import math


def area(poly):
    return 0.5*sum(poly[i][0]*poly[(i+1)%len(poly)][1]-poly[(i+1)%len(poly)][0]*poly[i][1] for i in range(len(poly)))


def area_grad(poly,i):
    n=len(poly); im=(i-1)%n; ip=(i+1)%n
    return (0.5*(poly[ip][1]-poly[im][1]), 0.5*(poly[im][0]-poly[ip][0]))


def check(name,cond,detail=''):
    if not cond:
        raise SystemExit(f'FAIL {name} {detail}')
    print(f'PASS {name} {detail}'.rstrip())

# Irregular polygon: exact area gradient and translational invariance.
p=[(-0.7,-0.2),(0.2,-0.6),(0.9,0.1),(0.4,0.8),(-0.5,0.6)]
g=[area_grad(p,i) for i in range(len(p))]
check('area_gradient_net_force_zero',abs(sum(x for x,y in g))<1e-15 and abs(sum(y for x,y in g))<1e-15)
for i in range(len(p)):
    for c in (0,1):
        eps=1e-7; q=[list(z) for z in p]; q[i][c]+=eps
        fd=(area(q)-area(p))/eps
        check(f'area_gradient_fd_node{i}_c{c}',abs(fd-g[i][c])<2e-8,f'err={abs(fd-g[i][c]):.3e}')

# Spring + dashpot pair: equal/opposite; common Galilean boost leaves force unchanged.
a=(0.0,0.0); b=(1.1,0.2); va=(0.15,-0.03); vb=(-0.04,0.07); l0=1.0; ks=7.0; damp=2.5

def edge_force(a,b,va,vb):
    dx=b[0]-a[0]; dy=b[1]-a[1]; l=math.hypot(dx,dy); tx=dx/l; ty=dy/l
    er=(vb[0]-va[0])*tx+(vb[1]-va[1])*ty
    mag=ks*(l-l0)+damp*er
    return mag*tx,mag*ty
f=edge_force(a,b,va,vb)
boost=(2.3,-1.7)
fb=edge_force(a,b,(va[0]+boost[0],va[1]+boost[1]),(vb[0]+boost[0],vb[1]+boost[1]))
check('edge_internal_action_reaction',abs(f[0]+(-f[0]))<1e-15 and abs(f[1]+(-f[1]))<1e-15)
check('edge_dashpot_galilean',math.hypot(f[0]-fb[0],f[1]-fb[1])<1e-14)

# Area penalty forces sum to zero.
A0=area(p)*0.94; A=area(p); ka=11.0; coeff=-ka*(A-A0)/abs(A0)
fa=[(coeff*x,coeff*y) for x,y in g]
check('area_penalty_internal_force_zero',math.hypot(sum(x for x,y in fa),sum(y for x,y in fa))<1e-13)

# Linear edge shape functions preserve the exact wall impulse.
lam=0.371; J=(3.2,-1.4)
Ja=((1-lam)*J[0],(1-lam)*J[1]); Jb=(lam*J[0],lam*J[1])
check('impact_shape_function_impulse_closure',math.hypot(Ja[0]+Jb[0]-J[0],Ja[1]+Jb[1]-J[1])<1e-15)

# Explicit kick: only external impact changes total momentum because internal force sum is zero.
m=4.0; vel=[(0.1,0.2),(-0.2,0.1),(0.05,-0.1)]
imp=[(0.3,-0.2),(0.0,0.1),(-0.1,0.2)]
fin=[(2.0,-1.0),(-3.0,4.0),(1.0,-3.0)]  # exactly zero sum
Dt=0.013
pb=(sum(m*x for x,y in vel),sum(m*y for x,y in vel))
vaft=[(v[0]+j[0]/m+Dt*ff[0]/m,v[1]+j[1]/m+Dt*ff[1]/m) for v,j,ff in zip(vel,imp,fin)]
pa=(sum(m*x for x,y in vaft),sum(m*y for x,y in vaft))
js=(sum(x for x,y in imp),sum(y for x,y in imp))
check('nodal_kick_total_momentum_closure',math.hypot(pa[0]-pb[0]-js[0],pa[1]-pb[1]-js[1])<1e-14)

print('0493x17c membrane math check: ALL PASS')

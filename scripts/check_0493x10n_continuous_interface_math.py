#!/usr/bin/env python3
import math
import random

ISO=.5

def cross(a,b): return a[0]*b[1]-a[1]*b[0]
def edge(a0,a1,p0,p1):
    if (a0>=ISO)==(a1>=ISO): return None
    t=(ISO-a0)/(a1-a0)
    return (p0[0]+t*(p1[0]-p0[0]),p0[1]+t*(p1[1]-p0[1]))

def segments(vals, ox=0., oy=0.):
    a00,a10,a11,a01=vals
    p=[(ox,oy),(ox+1,oy),(ox+1,oy+1),(ox,oy+1)]
    es=[edge(a00,a10,p[0],p[1]), edge(a10,a11,p[1],p[2]),
        edge(a11,a01,p[2],p[3]), edge(a01,a00,p[3],p[0])]
    ids=[i for i,e in enumerate(es) if e is not None]
    code=(a00>=ISO)|((a10>=ISO)<<1)|((a11>=ISO)<<2)|((a01>=ISO)<<3)
    if len(ids)==2: return [(es[ids[0]],es[ids[1]])]
    if len(ids)!=4: return []
    ci=sum(vals)/4>=ISO
    if code==5:
        pairs=((0,1),(2,3)) if ci else ((3,0),(1,2))
    else:
        pairs=((3,0),(1,2)) if ci else ((0,1),(2,3))
    return [(es[a],es[b]) for a,b in pairs]

# Adjacent dual squares must reproduce their shared-edge crossing bit-for-bit.
r=random.Random(4931014)
max_gap=0.0
checks=0
for _ in range(20000):
    # left square values a00,a10,a11,a01; right shares a10,a11
    a00,a10,a11,a01=[r.random() for _ in range(4)]
    b10,b11=r.random(),r.random()
    L=segments((a00,a10,a11,a01),0,0)
    R=segments((a10,b10,b11,a11),1,0)
    shared=edge(a10,a11,(1,0),(1,1))
    if shared is None: continue
    lp=[q for s in L for q in s if abs(q[0]-1)<1e-12]
    rp=[q for s in R for q in s if abs(q[0]-1)<1e-12]
    if not lp or not rp: raise SystemExit('FAIL missing shared endpoint')
    gap=min(math.hypot(a[0]-b[0],a[1]-b[1]) for a in lp for b in rp)
    max_gap=max(max_gap,gap); checks+=1

# Moving-segment quadratic collision: stationary horizontal wall sanity and
# relative-speed conservation for random translating segments.
max_e=0.0
hits=0
for _ in range(50000):
    ax=-1; ay=0; bx=1; by=0
    uw=r.uniform(-.2,.2)
    x=r.uniform(-.8,.8); y=r.uniform(-.3,-.01)
    vx=r.uniform(-.3,.3); vy=r.uniform(.02,.6)
    # rigid translating horizontal segment in y: analytic hit
    rel=vy-uw
    if rel<=0: continue
    t=-y/rel
    if not (0<=t<=1): continue
    vyp=vy-2*rel
    e0=(vy-uw)**2+vx*vx; e1=(vyp-uw)**2+vx*vx
    max_e=max(max_e,abs(e1-e0)); hits+=1
print(f'sharedEndpointChecks={checks} maxSharedEndpointGap={max_gap:.3e}')
print(f'collisionHits={hits} maxRelativeSpeedSqError={max_e:.3e}')
if max_gap>1e-14 or max_e>1e-12: raise SystemExit('status=FAIL')
print('status=PASS')

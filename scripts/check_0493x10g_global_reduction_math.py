#!/usr/bin/env python3
import math
import random

rng = random.Random(4931007)
n = 320000
block_threads = 256
blocks = 1024
stride = block_threads * blocks

# Sparse donor cells + O(5000) receiver cells, matching the x10f regime.
donor = {}
for _ in range(220):
    c = rng.randrange(n)
    A = 10.0 ** rng.uniform(-5.0, -1.0)
    ang = rng.uniform(-math.pi, math.pi)
    smag = math.sqrt(A) * rng.uniform(0.1, 1.0)
    donor[c] = (A, smag*math.cos(ang), smag*math.sin(ang),
                rng.uniform(-1.0, 1.0)*math.sqrt(A))
recv = {}
for _ in range(5200):
    c = rng.randrange(n)
    m = rng.uniform(1.0, 40.0)
    ux = rng.uniform(-0.2, 0.2)
    uy = rng.uniform(-0.2, 0.2)
    recv[c] = (m, m*ux, m*uy)

def direct():
    A=Sx=Sy=H=M=Px=Py=sn=0.0; dc=rc=0
    for c,(a,sx,sy,h) in donor.items():
        A+=a; Sx+=sx; Sy+=sy; H+=h; sn+=math.hypot(sx,sy); dc+=1
    for c,(m,px,py) in recv.items():
        M+=m; Px+=px; Py+=py; rc+=1
    return (A,Sx,Sy,H,M,Px,Py,sn,dc,rc)

# Emulate x10g grouping order at a coarse level: one partial per CUDA block
# after the same grid-stride assignment, then sum partials.
def hierarchical():
    p = [[0.0]*8 + [0,0] for _ in range(blocks)]
    for c,(a,sx,sy,h) in donor.items():
        tid = c % stride
        b = tid // block_threads
        q=p[b]; q[0]+=a; q[1]+=sx; q[2]+=sy; q[3]+=h; q[7]+=math.hypot(sx,sy); q[8]+=1
    for c,(m,px,py) in recv.items():
        tid = c % stride
        b = tid // block_threads
        q=p[b]; q[4]+=m; q[5]+=px; q[6]+=py; q[9]+=1
    out=[0.0]*8+[0,0]
    for q in p:
        for j in range(8): out[j]+=q[j]
        out[8]+=q[8]; out[9]+=q[9]
    return tuple(out)

d=direct(); h=hierarchical()
scale=max(1.0, *(abs(x) for x in d[:8]))
maxdiff=max(abs(d[i]-h[i]) for i in range(8))
if d[8:] != h[8:]: raise SystemExit('FAIL integer counts differ')
if maxdiff > 5e-12*scale:
    raise SystemExit(f'FAIL reduction difference {maxdiff:.3e} scale={scale:.3e}')

A,Sx,Sy,H,M,Px,Py,*_ = h
ux,uy=Px/M,Py/M
B=(Sx*Sx+Sy*Sy)/M
a=2.0*(H-(ux*Sx+uy*Sy))/(A+B)
res=a*((ux*Sx+uy*Sy)-H)+0.5*a*a*(A+B)
print(f'maxDirectHierarchicalDifference={maxdiff:.3e}')
print(f'analyticRootResidual={abs(res):.3e}')
print(f'partialBlocks={blocks}')
print('status=PASS')

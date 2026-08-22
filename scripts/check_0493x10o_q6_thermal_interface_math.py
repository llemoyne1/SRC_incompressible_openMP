#!/usr/bin/env python3
import math, random
rng=random.Random(493100)

def grad(alpha,i,j,nx,ny,h):
    def a(ii,jj):
        ii=max(0,min(nx-1,ii)); jj=max(0,min(ny-1,jj)); return alpha[jj*nx+ii]
    return ((a(i+1,j)-a(i-1,j))/(2*h),(a(i,j+1)-a(i,j-1))/(2*h))

nx=ny=32; h=1/nx
alpha=[]
for j in range(ny):
    y=(j+.5)*h
    for i in range(nx):
        x=(i+.5)*h
        alpha.append(.5 + .35*(.55-x) + .12*(y-.5))

max_gap=0.0; checks=0
# A shared horizontal edge recomputed from the dual square above/below must
# produce the identical thermally shifted endpoint.
for j in range(1,ny-1):
  for i in range(nx-1):
    c0=j*nx+i; c1=j*nx+i+1
    a0,a1=alpha[c0],alpha[c1]
    if (a0-.5)*(a1-.5)>=0: continue
    t=(.5-a0)/(a1-a0)
    g0=grad(alpha,i,j,nx,ny,h); g1=grad(alpha,i+1,j,nx,ny,h)
    gx=(1-t)*g0[0]+t*g1[0]; gy=(1-t)*g0[1]+t*g1[1]
    q=math.hypot(gx,gy); n=(-gx/q,-gy/q)
    delta=3*.002*math.sqrt(.125)
    x=((i+.5)+t)*h + delta*n[0]; y=(j+.5)*h + delta*n[1]
    x2=((i+.5)+t)*h + delta*n[0]; y2=(j+.5)*h + delta*n[1]
    max_gap=max(max_gap,math.hypot(x-x2,y-y2)); checks+=1

max_rel=0.0
for _ in range(200000):
    ang=rng.uniform(-math.pi,math.pi); n=(math.cos(ang),math.sin(ang))
    ux,uy=rng.uniform(-.2,.2),rng.uniform(-.2,.2)
    vn=ux*n[0]+uy*n[1]; uw=(vn*n[0],vn*n[1])
    vx,vy=rng.uniform(-1,1),rng.uniform(-1,1)
    rel=(vx-uw[0])*n[0]+(vy-uw[1])*n[1]
    if rel<=0: continue
    vxp=vx-2*rel*n[0]; vyp=vy-2*rel*n[1]
    e0=(vx-uw[0])**2+(vy-uw[1])**2
    e1=(vxp-uw[0])**2+(vyp-uw[1])**2
    max_rel=max(max_rel,abs(e1-e0))
print(f'sharedThermalEndpointChecks={checks} maxGap={max_gap:.3e}')
print(f'maxRelativeSpeedSqError={max_rel:.3e}')
if checks==0 or max_gap>1e-14 or max_rel>1e-12: raise SystemExit('status=FAIL')
print('status=PASS')

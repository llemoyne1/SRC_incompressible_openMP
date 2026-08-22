#!/usr/bin/env python3
import math
import random

rng=random.Random(4931010)

def rid(c,nx,B,sx,sy,nbx):
    i=c%nx; j=c//nx
    bx=0 if i<sx else 1+(i-sx)//B
    by=0 if j<sy else 1+(j-sy)//B
    return by*nbx+bx

def test(B):
    nx,ny=200,120
    sx,sy=(B-1)//2, B//2
    nbx=2+(nx-1)//B
    nby=2+(ny-1)//B
    slots=nbx*nby
    seen=[0]*slots
    for c in range(nx*ny):
        r=rid(c,nx,B,sx,sy,nbx)
        if not (0<=r<slots):
            raise SystemExit(f'FAIL B={B}: invalid reservoir id {r}')
        seen[r]+=1
    if sum(seen)!=nx*ny:
        raise SystemExit(f'FAIL B={B}: partition coverage')

    maxP=maxE=0.0
    active=0
    for _ in range(2000):
        nd=rng.randint(1,8)
        nrx=rng.randint(5,80)
        donors=[]
        A=Sx=Sy=H=0.0
        for _ in range(nd):
            m=rng.uniform(.5,2.0); g=rng.uniform(.01,.8)
            ang=rng.uniform(-math.pi,math.pi)
            nxv,nyv=math.cos(ang),math.sin(ang)
            vx=rng.uniform(-.5,.5); vy=rng.uniform(-.5,.5)
            donors.append((m,g,nxv,nyv,vx,vy))
            A+=m*g*g; Sx+=m*g*nxv; Sy+=m*g*nyv
            H+=m*g*(vx*nxv+vy*nyv)
        receivers=[]; M=Px=Py=0.0
        for _ in range(nrx):
            m=rng.uniform(.5,2.0); vx=rng.uniform(-.5,.5); vy=rng.uniform(-.5,.5)
            receivers.append((m,vx,vy)); M+=m; Px+=m*vx; Py+=m*vy
        ux,uy=Px/M,Py/M
        den=A+(Sx*Sx+Sy*Sy)/M
        num=2*(H-(ux*Sx+uy*Sy))
        a=num/den
        if not (a>0 and math.isfinite(a)):
            continue
        active+=1
        dux=a*Sx/M; duy=a*Sy/M
        dpx=dpy=dE=0.0
        for m,g,nxv,nyv,vx,vy in donors:
            nvx=vx-a*g*nxv; nvy=vy-a*g*nyv
            dpx+=m*(nvx-vx); dpy+=m*(nvy-vy)
            dE+=.5*m*((nvx*nvx+nvy*nvy)-(vx*vx+vy*vy))
        for m,vx,vy in receivers:
            nvx=vx+dux; nvy=vy+duy
            dpx+=m*(nvx-vx); dpy+=m*(nvy-vy)
            dE+=.5*m*((nvx*nvx+nvy*nvy)-(vx*vx+vy*vy))
        maxP=max(maxP,math.hypot(dpx,dpy)); maxE=max(maxE,abs(dE))
    print(f'B={B} slots={slots} usedSlots={sum(v>0 for v in seen)} '
          f'activeSynthetic={active} maxMomentumResidual={maxP:.3e} '
          f'maxEnergyResidual={maxE:.3e}')
    if maxP>1e-10 or maxE>1e-10:
        raise SystemExit(f'FAIL B={B}: conservation residual')

for B in (4,5):
    test(B)
print('status=PASS')

#!/usr/bin/env python3
import math

NX,NY=128,64
LX,LY=0.5,0.25
DX,DY=LX/NX,LY/NY
CENTER=0.28434587341779827-0.00016304981207798663
AMP=0.0029296875
THICK=0.03125
DT=0.002
WALL_VX=0.081524906038987016

# x16o dump event, step 203 -> 204
PARTICLES={
 41966:(0.27146489396109313,0.06329723503311291,0.64019605441869,-0.8406814337423347),
 44384:(0.271252080748421,0.061453969920459574,0.6944434585599288,0.48656183126717784),
}

def wrap_delta(x,c,L):
    d=x-c
    return d-round(d/L)*L

def S_cell(i,j):
    i%=NX; j%=NY
    x=(i+0.5)*DX; y=(j+0.5)*DY
    local=CENTER+AMP*math.sin(2*math.pi*y/LY)
    sd=abs(wrap_delta(x,local,LX))-0.5*THICK
    return min(1.0,max(0.0,0.5-sd/(4*DX)))

def quad(fm,f0,fp,t):
    d1=0.5*(fp-fm); d2=0.5*(fp-2*f0+fm)
    return f0+d1*t+d2*t*t, d1+2*d2*t

def eval_q2(i,j,xi,eta):
    rv=[]; rx=[]
    for jj in (j-1,j,j+1):
        v,d=quad(S_cell(i-1,jj),S_cell(i,jj),S_cell(i+1,jj),xi)
        rv.append(v); rx.append(d)
    val,gy=quad(rv[0],rv[1],rv[2],eta)
    gx,_=quad(rx[0],rx[1],rx[2],eta)
    return val-0.5,gx,gy

def edge_roots(fm,f0,fp):
    a=0.5*(fp-2*f0+fm); b=0.5*(fp-fm); c=f0-0.5
    out=[]
    def add(r):
        if -2e-10 <= r <= 1+2e-10:
            r=min(1.0,max(0.0,r))
            if not out or abs(r-out[-1])>1e-9: out.append(r)
    if abs(a)<=1e-13:
        if abs(b)<=1e-13: return out
        add(-c/b); return out
    d=b*b-4*a*c
    if d < -1e-12: return out
    if abs(d)<=1e-12:
        add(-b/(2*a)); return out
    sd=math.sqrt(max(0.0,d)); r0=(-b-sd)/(2*a); r1=(-b+sd)/(2*a)
    if r1<r0:r0,r1=r1,r0
    add(r0); add(r1); return out

def owner_roots(i,j):
    triples=[
      (S_cell(i-1,j),S_cell(i,j),S_cell(i+1,j)),
      (S_cell(i+1,j-1),S_cell(i+1,j),S_cell(i+1,j+1)),
      (S_cell(i-1,j+1),S_cell(i,j+1),S_cell(i+1,j+1)),
      (S_cell(i,j-1),S_cell(i,j),S_cell(i,j+1)),
    ]
    pts=[]; per=[]
    for e,t in enumerate(triples):
        rs=edge_roots(*t); per.append(len(rs))
        for r in rs:
            if e==0:p=(r,0.0,e,r)
            elif e==1:p=(1.0,r,e,1+r)
            elif e==2:p=(r,1.0,e,2+(1-r))
            else:p=(0.0,r,e,3+(1-r))
            if not any((p[0]-q[0])**2+(p[1]-q[1])**2<=1e-16 for q in pts):pts.append(p)
    pts.sort(key=lambda p:p[3])
    return pts,per

def margin(x,y):return min(x,1-x,y,1-y)

def trace_partner(i,j,roots,start=0):
    x,y=roots[start][0],roots[start][1]
    f,gx,gy=eval_q2(i,j,x,y); gn=math.hypot(gx,gy)
    tx,ty=-gy/gn,gx/gn; probe=2e-4
    mp=margin(x+probe*tx,y+probe*ty); mm=margin(x-probe*tx,y-probe*ty)
    if mm>mp:tx,ty=-tx,-ty
    x+=probe*tx; y+=probe*ty; otx,oty=tx,ty
    for it in range(256):
        for _ in range(3):
            f,gx,gy=eval_q2(i,j,x,y); g2=gx*gx+gy*gy
            if not g2>1e-24:return -1
            x-=f*gx/g2; y-=f*gy/g2
        if it>1 and margin(x,y)<0.04:
            candidates=[(((x-r[0])**2+(y-r[1])**2),k) for k,r in enumerate(roots) if k!=start]
            d2,k=min(candidates)
            if d2<=0.05**2:return k
        f,gx,gy=eval_q2(i,j,x,y); gn=math.hypot(gx,gy)
        ntx,nty=-gy/gn,gx/gn
        if ntx*otx+nty*oty<0:ntx,nty=-ntx,-nty
        otx,oty=ntx,nty; x+=(1/64)*ntx; y+=(1/64)*nty
    return -1

r68,p68=owner_roots(68,15)
assert p68==[1,2,1,0] and len(r68)==4,(p68,r68)
partner=trace_partner(68,15,r68,0)
assert partner==1,partner
print(f'PASS owner=(68,15) roots=4 perEdge={p68} tracePair=0->{partner} remaining=2->3')

r69,p69=owner_roots(69,15)
code=0
for bit,val in enumerate((S_cell(69,15),S_cell(70,15),S_cell(70,16),S_cell(69,16))):
    if val>=0.5:code|=1<<bit
assert code==15,code
assert p69==[0,0,0,2] and len(r69)==2,(p69,r69)
print(f'PASS owner=(69,15) cornerCode={code} hiddenRoots=2 perEdge={p69} branch=left-root0<->left-root1')

# Confirm the two dump particles really cross this hidden owner Q2 in the moving-wall frame.
xb=(69+0.5)*DX; yb=(15+0.5)*DY
for pid,(x0,y0,vx,vy) in PARTICLES.items():
    def state(t):
        xr=x0+(vx-WALL_VX)*t
        yr=y0+vy*t
        xi=(xr-xb)/DX; eta=(yr-yb)/DY
        f,_,_=eval_q2(69,15,xi,eta)
        return f,xi,eta
    # scan only points inside the owner and find the first sign change own-support -> material.
    prev=None; bracket=None
    for k in range(1001):
        t=DT*k/1000
        f,xi,eta=state(t)
        if -1e-12<=xi<=1+1e-12 and -1e-12<=eta<=1+1e-12:
            if prev is not None and prev[1]<=0 and f>=0:
                bracket=(prev[0],t); break
            prev=(t,f)
    assert bracket is not None,(pid,state(0),state(DT))
    lo,hi=bracket
    for _ in range(60):
        m=0.5*(lo+hi); fm,_,_=state(m)
        if fm<=0:lo=m
        else:hi=m
    tc=0.5*(lo+hi); fc,xi,eta=state(tc)
    assert 0<=xi<=1 and 0<=eta<=1
    print(f'PASS pid={pid} hiddenOwnerCrossing tau/dt={tc/DT:.9f} local=({xi:.9f},{eta:.9f})')

print('0493x16p Q2 topology math check: ALL PASS')

#!/usr/bin/env python3
"""Generate a periodic SRC state with a pure transverse shear mode u_x(y).
Campaign-only tooling: does not modify solver/source physics.
"""
from __future__ import annotations
import argparse, math, random, struct
from pathlib import Path
MAGIC=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE"))

def args():
    p=argparse.ArgumentParser()
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--Lx',type=float,required=True); p.add_argument('--Ly',type=float,required=True)
    p.add_argument('--Nx',type=int,required=True); p.add_argument('--Ny',type=int,required=True)
    p.add_argument('--gamma',type=int,required=True); p.add_argument('--kBT',type=float,required=True)
    p.add_argument('--mass',type=float,default=1.0); p.add_argument('--seed',type=int,required=True)
    p.add_argument('--mode-y',type=int,default=1); p.add_argument('--amplitude',type=float,required=True)
    return p.parse_args()

def offsets(slot):
    fx=((slot+0.5)*0.6180339887498949)%1.0; fy=((slot+0.5)*0.4142135623730950)%1.0
    margin=0.04
    return margin+(1-2*margin)*fx, margin+(1-2*margin)*fy

def thermal(n,kbt,mass,seed):
    r=random.Random(seed)
    q=[(r.gauss(0,1),r.gauss(0,1)) for _ in range(n)]
    mx=sum(u for u,_ in q)/n; my=sum(v for _,v in q)/n
    q=[(u-mx,v-my) for u,v in q]
    e=0.5*mass*sum(u*u+v*v for u,v in q); target=n*kbt
    s=math.sqrt(target/e) if e>0 else 0.0
    return [(s*u,s*v) for u,v in q]

def main():
    a=args()
    if min(a.Lx,a.Ly,a.kBT,a.mass,a.amplitude)<=0 or min(a.Nx,a.Ny)<8 or a.gamma<4 or a.mode_y<1:
        raise SystemExit('[0493x13b-shear-state] invalid input')
    if a.mode_y*8>a.Ny: raise SystemExit('[0493x13b-shear-state] wavelength must contain >=8 cells')
    x=[];y=[];vx=[];vy=[];typ=[];mass=[];role=[]
    ky=2*math.pi*a.mode_y/a.Ly
    for j in range(a.Ny):
        yc=(j+0.5)*a.Ly/a.Ny
        ubx=a.amplitude*math.sin(ky*yc)
        for i in range(a.Nx):
            cell=i+a.Nx*j
            th=thermal(a.gamma,a.kBT,a.mass,a.seed+104729*cell)
            for slot,(tx,ty) in enumerate(th):
                fx,fy=offsets(slot)
                x.append((i+fx)*a.Lx/a.Nx); y.append((j+fy)*a.Ly/a.Ny)
                vx.append(ubx+tx); vy.append(ty); typ.append(0); mass.append(a.mass); role.append(1)
    M=sum(mass); ux=sum(m*u for m,u in zip(mass,vx))/M; uy=sum(m*v for m,v in zip(mass,vy))/M
    vx=[u-ux for u in vx]; vy=[v-uy for v in vy]
    n=len(x); a.output.parent.mkdir(parents=True,exist_ok=True); reserved=[0]*8; reserved[0]=1; reserved[1]=1
    with a.output.open('wb') as f:
        f.write(MAGIC); f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4)); f.write(struct.pack('<8Q',*reserved))
        for vals,fmt in ((x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')):
            f.write(struct.pack(f'<{n}{fmt}',*vals))
    print(f'[0493x13b-shear-state] path={a.output} N={n} grid={a.Nx}x{a.Ny} gamma={a.gamma} modeY={a.mode_y} amplitude={a.amplitude:.9g}')
if __name__=='__main__': main()

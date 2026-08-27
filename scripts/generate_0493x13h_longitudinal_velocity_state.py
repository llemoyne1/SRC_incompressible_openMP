#!/usr/bin/env python3
"""Generate a periodic SRC state with a longitudinal velocity mode u_x(x).

Campaign-only tooling for 0493x13e.  Density is initially uniform (exactly gamma
particles per collision cell); the coherent velocity is
    u_x = U0 sin(2*pi*mode_x*x/Lx)
with U0 = Ma_ref * c_s_ref supplied by the runner.  Cell-relative thermal noise
is generated exactly as in the x13b shear state generator and the global mean
momentum is removed.  No solver/source code is modified.
"""
from __future__ import annotations
import argparse, json, math, random, struct
from pathlib import Path

MAGIC=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE"))

def parse_args():
    p=argparse.ArgumentParser()
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--metadata',type=Path,default=None)
    p.add_argument('--Lx',type=float,required=True); p.add_argument('--Ly',type=float,required=True)
    p.add_argument('--Nx',type=int,required=True); p.add_argument('--Ny',type=int,required=True)
    p.add_argument('--gamma',type=int,required=True); p.add_argument('--kBT',type=float,required=True)
    p.add_argument('--mass',type=float,default=1.0); p.add_argument('--seed',type=int,required=True)
    p.add_argument('--mode-x',type=int,default=1); p.add_argument('--amplitude',type=float,required=True)
    p.add_argument('--mach-requested',type=float,default=float('nan'))
    p.add_argument('--sound-speed-reference',type=float,default=float('nan'))
    return p.parse_args()

def offsets(slot):
    fx=((slot+0.5)*0.6180339887498949)%1.0; fy=((slot+0.5)*0.4142135623730950)%1.0
    margin=.04
    return margin+(1-2*margin)*fx, margin+(1-2*margin)*fy

def thermal(n,kbt,mass,seed):
    r=random.Random(seed)
    q=[(r.gauss(0,1),r.gauss(0,1)) for _ in range(n)]
    mx=sum(u for u,_ in q)/n; my=sum(v for _,v in q)/n
    q=[(u-mx,v-my) for u,v in q]
    e=.5*mass*sum(u*u+v*v for u,v in q); target=n*kbt
    s=math.sqrt(target/e) if e>0 else 0.0
    return [(s*u,s*v) for u,v in q]

def main():
    a=parse_args()
    if min(a.Lx,a.Ly,a.kBT,a.mass,a.amplitude)<=0 or min(a.Nx,a.Ny)<8 or a.gamma<4 or a.mode_x<1:
        raise SystemExit('[0493x13e-longitudinal-state] invalid input')
    if a.mode_x*8>a.Nx:
        raise SystemExit('[0493x13e-longitudinal-state] wavelength must contain >=8 cells')
    x=[];y=[];vx=[];vy=[];typ=[];mass=[];role=[]
    k=2*math.pi*a.mode_x/a.Lx
    for j in range(a.Ny):
        for i in range(a.Nx):
            cell=i+a.Nx*j
            th=thermal(a.gamma,a.kBT,a.mass,a.seed+104729*cell)
            for slot,(tx,ty) in enumerate(th):
                fx,fy=offsets(slot)
                xp=(i+fx)*a.Lx/a.Nx; yp=(j+fy)*a.Ly/a.Ny
                ux=a.amplitude*math.sin(k*xp)
                x.append(xp);y.append(yp);vx.append(ux+tx);vy.append(ty)
                typ.append(0);mass.append(a.mass);role.append(1)
    M=sum(mass)
    meanx=sum(m*u for m,u in zip(mass,vx))/M; meany=sum(m*v for m,v in zip(mass,vy))/M
    vx=[u-meanx for u in vx];vy=[v-meany for v in vy]
    # Fourier amplitude actually realized in the full particle state.
    cre=0.0;cim=0.0
    for m,xp,u in zip(mass,x,vx):
        ph=k*xp
        cre += m*u*math.cos(ph); cim -= m*u*math.sin(ph)
    mode_amp=2*math.hypot(cre,cim)/M
    n=len(x);a.output.parent.mkdir(parents=True,exist_ok=True)
    reserved=[0]*8;reserved[0]=1;reserved[1]=1
    with a.output.open('wb') as f:
        f.write(MAGIC);f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4));f.write(struct.pack('<8Q',*reserved))
        for vals,fmt in ((x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')):
            f.write(struct.pack(f'<{n}{fmt}',*vals))
    meta={
      'method':'x13e_uniform_density_longitudinal_velocity_mode','seed':a.seed,'Nx':a.Nx,'Ny':a.Ny,
      'gamma':a.gamma,'modeX':a.mode_x,'requestedVelocityAmplitude':a.amplitude,
      'realizedVelocityFourierAmplitude':mode_amp,'relativeVelocityAmplitudeError':(mode_amp-a.amplitude)/a.amplitude,
      'machRequested':a.mach_requested,'soundSpeedReference':a.sound_speed_reference,
      'totalParticles':n,'expectedParticles':a.Nx*a.Ny*a.gamma,'initialDensityUniform':True,
      'globalMeanVxAfterRemoval':sum(m*u for m,u in zip(mass,vx))/M,
      'globalMeanVyAfterRemoval':sum(m*u for m,u in zip(mass,vy))/M,
    }
    if a.metadata:
        a.metadata.parent.mkdir(parents=True,exist_ok=True);a.metadata.write_text(json.dumps(meta,indent=2,sort_keys=True)+'\n')
    print(f"[0493x13e-longitudinal-state] path={a.output} N={n} grid={a.Nx}x{a.Ny} gamma={a.gamma} U0={a.amplitude:.9g} realized={mode_amp:.9g} MaReq={a.mach_requested:.6g}")

if __name__=='__main__':main()

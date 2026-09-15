#!/usr/bin/env python3
"""Generate a closed-chamber MPCD state with a density jump across a piston.

The binary format matches src_mpcd_case_generator_0434.py.  Fluid is generated
in every cell; particles initially inside the chi piston are removed once at
startup by darcyInitialDeactivateBelowChi=0.5, preserving the x17b contract.
"""
import argparse, math, os, random, struct

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--state',required=True); ap.add_argument('--Lx',type=float,required=True); ap.add_argument('--Ly',type=float,required=True)
    ap.add_argument('--Nx',type=int,required=True); ap.add_argument('--Ny',type=int,required=True)
    ap.add_argument('--gamma-left',type=int,required=True); ap.add_argument('--gamma-right',type=int,required=True)
    ap.add_argument('--split-x',type=float,required=True); ap.add_argument('--kBT',type=float,default=0.125); ap.add_argument('--mass',type=float,default=1.0); ap.add_argument('--seed',type=int,default=4931712)
    a=ap.parse_args()
    if not (a.Lx>0 and a.Ly>0 and a.Nx>0 and a.Ny>0 and 0<a.split_x<a.Lx): raise SystemExit('0493x17d invalid piston state geometry')
    if a.gamma_left<=0 or a.gamma_right<=0 or a.mass<=0 or a.kBT<0: raise SystemExit('0493x17d invalid piston state thermodynamics')
    rng=random.Random(a.seed); dx=a.Lx/a.Nx; dy=a.Ly/a.Ny; sig=math.sqrt(a.kBT/a.mass) if a.kBT>0 else 0.0
    x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
    for j in range(a.Ny):
        for i in range(a.Nx):
            xc=(i+0.5)*dx; g=a.gamma_left if xc<a.split_x else a.gamma_right
            for _ in range(g):
                x.append((i+rng.random())*dx); y.append((j+rng.random())*dy)
                vx.append(sig*rng.gauss(0,1)); vy.append(sig*rng.gauss(0,1)); typ.append(0); mass.append(a.mass); role.append(1)
    # Remove finite-sample mean drift separately on each side so the initial
    # pressure jump is not contaminated by a bulk velocity bias.
    for left in (True,False):
        idx=[k for k,xx in enumerate(x) if (xx<a.split_x)==left]
        if idx:
            mx=sum(vx[k] for k in idx)/len(idx); my=sum(vy[k] for k in idx)/len(idx)
            for k in idx: vx[k]-=mx; vy[k]-=my
    os.makedirs(os.path.dirname(a.state) or '.',exist_ok=True)
    magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE')); n=len(x); reserved=[0]*8; reserved[0]=1; reserved[1]=1
    with open(a.state,'wb') as f:
        f.write(magic); f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4)); f.write(struct.pack('<8Q',*reserved))
        for arr,fmt in [(x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')]: f.write(struct.pack(f'<{n}{fmt}',*arr))
    print(f'[0493x17d-piston-generate] state={a.state} N={n} grid={a.Nx}x{a.Ny} gammaLeft={a.gamma_left} gammaRight={a.gamma_right} splitX={a.split_x:.17g} kBT={a.kBT:.17g}')
if __name__=='__main__': main()

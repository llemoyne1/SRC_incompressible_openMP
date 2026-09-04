#!/usr/bin/env python3
"""0493x14ah — circular liquid drop at rest in an initially developed gas Poiseuille profile.

The streamwise direction is periodic in the runner.  This generator only prepares
an initial parabolic carrier profile; no inlet/outlet reservoir is involved.
"""
from __future__ import annotations
import argparse, json, math, random, struct, sys
from array import array
from pathlib import Path
MAGIC=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE"))

def pi(s):
    v=int(s)
    if v<=0: raise argparse.ArgumentTypeError('positive integer required')
    return v

def pf(s):
    v=float(s)
    if not math.isfinite(v) or v<=0: raise argparse.ArgumentTypeError('positive finite required')
    return v

def nn(s):
    v=float(s)
    if not math.isfinite(v) or v<0: raise argparse.ArgumentTypeError('nonnegative finite required')
    return v

def coprime(n,start,avoid=-1):
    for off in range(n):
        c=1+((start+off-1)%n)
        if c!=avoid and math.gcd(c,n)==1: return c
    return 1

def paired(rng,n,m,kbt):
    if n<=0:return []
    if n==1 or kbt==0:return [(0.0,0.0)]*n
    a=[]
    for _ in range(n//2):
        x,y=rng.gauss(0,1),rng.gauss(0,1); a.extend(((x,y),(-x,-y)))
    if n%2:a.append((0.0,0.0))
    s2=sum(x*x+y*y for x,y in a)
    sc=math.sqrt(2*n*kbt/(m*s2)) if s2>0 else 0
    return [(sc*x,sc*y) for x,y in a]

def write(path,x,y,vx,vy,t,mass,role):
    n=len(x); reserved=[0]*8; reserved[0]=reserved[1]=1
    path.parent.mkdir(parents=True,exist_ok=True)
    arrs=(x,y,vx,vy,t,mass)
    if sys.byteorder=='big':
        for z in arrs:z.byteswap()
    try:
        with path.open('wb') as f:
            f.write(MAGIC); f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4)); f.write(struct.pack('<8Q',*reserved))
            for z in arrs:z.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder=='big':
            for z in arrs:z.byteswap()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--Lx',type=pf,default=2.0); ap.add_argument('--Ly',type=pf,default=1.0)
    ap.add_argument('--nx',type=pi,default=512); ap.add_argument('--ny',type=pi,default=256); ap.add_argument('--gamma',type=pi,default=20)
    ap.add_argument('--center-x',type=float,default=None); ap.add_argument('--center-y',type=float,default=None); ap.add_argument('--radius-cells',type=pf,default=40)
    ap.add_argument('--liquid-type',type=pi,default=1); ap.add_argument('--gas-type',type=pi,default=2)
    ap.add_argument('--liquid-mass',type=pf,default=1.0); ap.add_argument('--gas-mass',type=pf,default=0.1)
    ap.add_argument('--liquid-kBT',type=nn,default=0.02); ap.add_argument('--gas-kBT',type=nn,default=0.08)
    ap.add_argument('--gas-umax0',type=nn,default=0.075); ap.add_argument('--drop-ux0',type=float,default=0.0); ap.add_argument('--drop-uy0',type=float,default=0.0)
    ap.add_argument('--seed',type=int,default=493191)
    a=ap.parse_args()
    if a.gamma<2:ap.error('gamma>=2 required')
    if a.liquid_type==a.gas_type:ap.error('types must differ')
    dx,dy=a.Lx/a.nx,a.Ly/a.ny
    if abs(dx-dy)>1e-12*max(1,abs(dx),abs(dy)):ap.error('square cells required')
    h=dx; cx=a.Lx/2 if a.center_x is None else a.center_x; cy=a.Ly/2 if a.center_y is None else a.center_y; R=a.radius_cells*h
    if min(cy-R,a.Ly-cy-R)<=8*h:ap.error('drop-to-wall clearance must exceed 8h')
    if min(cx-R,a.Lx-cx-R)<=8*h:ap.error('initial drop must be away from the periodic seam by >8h')
    ax=coprime(a.gamma,3); ay=coprime(a.gamma,7,ax)
    rl=random.Random(a.seed^0x14A81); rg=random.Random(a.seed^0x14A82)
    x=array('d');y=array('d');vx=array('d');vy=array('d');typ=array('I');mass=array('d');role=bytearray(); nL=nG=mixed=0
    sumGasUx=0.0; sumLiqUx=0.0; sumGasUy=0.0; sumLiqUy=0.0
    def ugas(py):
        eta=2.0*py/a.Ly-1.0
        return max(0.0,a.gas_umax0*(1.0-eta*eta))
    for iy in range(a.ny):
      for ix in range(a.nx):
        pos=[]; kinds=[]
        for k in range(a.gamma):
            fx=((ax*k)%a.gamma+0.5)/a.gamma; fy=((ay*k)%a.gamma+0.5)/a.gamma
            px=(ix+fx)*dx; py=(iy+fy)*dy
            t=a.liquid_type if (px-cx)**2+(py-cy)**2<=R*R else a.gas_type
            pos.append((px,py)); kinds.append(t)
        nl=sum(t==a.liquid_type for t in kinds); ng=a.gamma-nl; nL+=nl;nG+=ng
        if nl and ng:mixed+=1
        vl=paired(rl,nl,a.liquid_mass,a.liquid_kBT); vg=paired(rg,ng,a.gas_mass,a.gas_kBT); il=ig=0
        for (px,py),t in zip(pos,kinds):
            if t==a.liquid_type:
                dux,duy=vl[il];il+=1; ux=a.drop_ux0+dux; uy=a.drop_uy0+duy; m=a.liquid_mass
                sumLiqUx += ux; sumLiqUy += uy
            else:
                dux,duy=vg[ig];ig+=1; ux=ugas(py)+dux; uy=duy; m=a.gas_mass
                sumGasUx += ux; sumGasUy += uy
            x.append(px);y.append(py);vx.append(ux);vy.append(uy);typ.append(t);mass.append(m);role.append(1)
    write(a.output,x,y,vx,vy,typ,mass,role)
    gasMeanUx=sumGasUx/nG if nG else 0.0; gasMeanUy=sumGasUy/nG if nG else 0.0
    liqMeanUx=sumLiqUx/nL if nL else 0.0; liqMeanUy=sumLiqUy/nL if nL else 0.0
    meta={'profile':'two_phase_drop_initial_poiseuille_periodic_x_0493x14ah','carrierContract':'initial Poiseuille only; x-periodic, y-solid in runner; no inlet/outlet/body force','Lx':a.Lx,'Ly':a.Ly,'nx':a.nx,'ny':a.ny,'h':h,'gamma':a.gamma,'centerX':cx,'centerY':cy,'radius':R,'radiusCells':a.radius_cells,'liquidType':a.liquid_type,'gasType':a.gas_type,'liquidMass':a.liquid_mass,'gasMass':a.gas_mass,'liquidKBT':a.liquid_kBT,'gasKBT':a.gas_kBT,'gasUmax0':a.gas_umax0,'gasUmeanParabolicNominal0':2*a.gas_umax0/3,'gasUmeanDiscrete0':gasMeanUx,'gasVmeanDiscrete0':gasMeanUy,'dropUmeanDiscrete0':[liqMeanUx,liqMeanUy],'dropUx0Requested':a.drop_ux0,'dropUy0Requested':a.drop_uy0,'particles':len(x),'liquidParticles':nL,'gasParticles':nG,'mixedCells':mixed,'seed':a.seed}
    a.output.with_suffix(a.output.suffix+'.json').write_text(json.dumps(meta,indent=2)+'\n')
    print(f"[0493x14ah-generate] grid={a.nx}x{a.ny} h={h:.10g} N={len(x)} R/h={a.radius_cells:g} center=({cx:.8g},{cy:.8g})")
    print(f"[0493x14ah-generate] liquid={nL} gas={nG} mixedCells={mixed} gasUmax0={a.gas_umax0:.8g} gasUmeanDiscrete0={gasMeanUx:.8g} dropUmean0=({liqMeanUx:.3e},{liqMeanUy:.3e})")
    return 0
if __name__=='__main__': raise SystemExit(main())

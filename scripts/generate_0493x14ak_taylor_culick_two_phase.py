#!/usr/bin/env python3
"""0493x14ak — generate a two-phase finite 2-D Taylor-Culick sheet.

The full box is populated at exactly gamma particles per simulation cell.
Particles inside a rounded rectangle are liquid (type 1 by default); the
exterior is gas (type 2). Liquid and gas thermal fluctuations are independently
paired inside each cell/species population, giving zero species-cell mean when
possible. Tooling only: no solver/source modification.
"""
from __future__ import annotations
import argparse, json, math, random, struct, sys
from array import array
from pathlib import Path

MAGIC=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE"))

def pos_int(s):
    v=int(s)
    if v<=0: raise argparse.ArgumentTypeError("expected positive integer")
    return v

def pos_float(s):
    v=float(s)
    if not math.isfinite(v) or v<=0: raise argparse.ArgumentTypeError("expected finite positive number")
    return v

def nonneg_float(s):
    v=float(s)
    if not math.isfinite(v) or v<0: raise argparse.ArgumentTypeError("expected finite non-negative number")
    return v

def coprime_multiplier(modulus,start,avoid=-1):
    for off in range(modulus):
        c=1+((start+off-1)%modulus)
        if c!=avoid and math.gcd(c,modulus)==1: return c
    return 1

def paired_velocities(rng,count,mass,kbt):
    if count<=0: return []
    if count==1 or kbt==0: return [(0.0,0.0)]*count
    vals=[]
    for _ in range(count//2):
        gx,gy=rng.gauss(0,1),rng.gauss(0,1)
        vals.extend(((gx,gy),(-gx,-gy)))
    if count%2: vals.append((0.0,0.0))
    s2=sum(u*u+v*v for u,v in vals)
    scale=math.sqrt(2.0*count*kbt/(mass*s2)) if s2>0 else 0.0
    return [(scale*u,scale*v) for u,v in vals]

def rounded_rectangle_inside(x,y,cx,cy,halfL,halfH,r):
    qx=abs(x-cx)-(halfL-r); qy=abs(y-cy)-(halfH-r)
    ox=max(qx,0.0); oy=max(qy,0.0)
    return math.hypot(ox,oy)+min(max(qx,qy),0.0) <= r

def write_state(path,x,y,vx,vy,typ,mass,role):
    n=len(x)
    if not all(len(a)==n for a in (y,vx,vy,typ,mass,role)): raise RuntimeError("inconsistent arrays")
    reserved=[0]*8; reserved[0]=1; reserved[1]=1
    path.parent.mkdir(parents=True,exist_ok=True)
    arrays=(x,y,vx,vy,typ,mass)
    if sys.byteorder=='big':
        for a in arrays:a.byteswap()
    try:
        with path.open('wb') as f:
            f.write(MAGIC); f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4)); f.write(struct.pack('<8Q',*reserved))
            for a in arrays:a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder=='big':
            for a in arrays:a.byteswap()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--Lx',type=pos_float,default=3.5); ap.add_argument('--Ly',type=pos_float,default=1.0)
    ap.add_argument('--nx',type=pos_int,default=896); ap.add_argument('--ny',type=pos_int,default=256)
    ap.add_argument('--gamma',type=pos_int,default=20)
    ap.add_argument('--center-x',type=float,default=1.75); ap.add_argument('--center-y',type=float,default=0.5)
    ap.add_argument('--sheet-length-cells',type=pos_float,default=768.0)
    ap.add_argument('--thickness-cells',type=pos_float,default=64.0)
    ap.add_argument('--edge-round-cells',type=pos_float,default=8.0)
    ap.add_argument('--liquid-type',type=pos_int,default=1); ap.add_argument('--gas-type',type=pos_int,default=2)
    ap.add_argument('--liquid-mass',type=pos_float,default=1.0); ap.add_argument('--gas-mass',type=pos_float,default=0.1)
    ap.add_argument('--liquid-kBT',type=nonneg_float,default=0.02); ap.add_argument('--gas-kBT',type=nonneg_float,default=0.08)
    ap.add_argument('--seed',type=int,default=4931501)
    a=ap.parse_args()
    if a.gamma<2: ap.error('gamma must be >=2')
    if a.liquid_type==a.gas_type: ap.error('liquid and gas types must differ')
    dx,dy=a.Lx/a.nx,a.Ly/a.ny
    if abs(dx-dy)>1e-12*max(1.0,abs(dx),abs(dy)): ap.error('square cells required')
    h=dx; L=a.sheet_length_cells*h; H=a.thickness_cells*h; rr=a.edge_round_cells*h
    if not all(math.isfinite(v) for v in (a.center_x,a.center_y)): ap.error('center must be finite')
    if not (0<rr<0.5*H and rr<0.5*L): ap.error('edge rounding must be positive and below half-extents')
    halfL,halfH=0.5*L,0.5*H
    xclr=min(a.center_x-halfL,a.Lx-(a.center_x+halfL)); yclr=min(a.center_y-halfH,a.Ly-(a.center_y+halfH))
    if min(xclr,yclr)<=16*h: ap.error(f'require >16h wall clearance; x={xclr/h:.6g}h y={yclr/h:.6g}h')

    ax=coprime_multiplier(a.gamma,3); ay=coprime_multiplier(a.gamma,7,avoid=ax)
    rngL=random.Random(a.seed ^ 0x14A4B); rngG=random.Random(a.seed ^ 0x14A4C)
    x=array('d'); y=array('d'); vx=array('d'); vy=array('d'); typ=array('I'); mass=array('d'); role=bytearray()
    nL=nG=mixed=liqCells=gasCells=0
    for iy in range(a.ny):
        for ix in range(a.nx):
            pos=[]; kinds=[]
            for q in range(a.gamma):
                fx=((ax*q)%a.gamma+0.5)/a.gamma; fy=((ay*q)%a.gamma+0.5)/a.gamma
                px=(ix+fx)*dx; py=(iy+fy)*dy
                t=a.liquid_type if rounded_rectangle_inside(px,py,a.center_x,a.center_y,halfL,halfH,rr) else a.gas_type
                pos.append((px,py)); kinds.append(t)
            nl=sum(t==a.liquid_type for t in kinds); ng=a.gamma-nl
            nL+=nl; nG+=ng
            if nl==a.gamma: liqCells+=1
            elif ng==a.gamma: gasCells+=1
            else: mixed+=1
            vl=paired_velocities(rngL,nl,a.liquid_mass,a.liquid_kBT); vg=paired_velocities(rngG,ng,a.gas_mass,a.gas_kBT)
            il=ig=0
            for (px,py),t in zip(pos,kinds):
                if t==a.liquid_type: ux,uy=vl[il]; il+=1; m=a.liquid_mass
                else: ux,uy=vg[ig]; ig+=1; m=a.gas_mass
                x.append(px); y.append(py); vx.append(ux); vy.append(uy); typ.append(t); mass.append(m); role.append(1)

    # Remove only roundoff-level total momentum.
    M=sum(mass); px0=sum(m*u for m,u in zip(mass,vx)); py0=sum(m*v for m,v in zip(mass,vy)); dux=px0/M; duy=py0/M
    for i in range(len(vx)): vx[i]-=dux; vy[i]-=duy
    write_state(a.output,x,y,vx,vy,typ,mass,role)

    target=L*H-(4.0-math.pi)*rr*rr; discrete=nL*dx*dy/a.gamma
    rhoL=a.gamma*a.liquid_mass/h**2; rhoG=a.gamma*a.gas_mass/h**2
    meta={
      'profile':'two_phase_taylor_culick_rounded_sheet_0493x14ak','Lx':a.Lx,'Ly':a.Ly,'nx':a.nx,'ny':a.ny,'h':h,'gamma':a.gamma,
      'centerX':a.center_x,'centerY':a.center_y,'sheetLength':L,'sheetLengthCells':a.sheet_length_cells,'thickness':H,'thicknessCells':a.thickness_cells,
      'edgeRoundRadius':rr,'edgeRoundCells':a.edge_round_cells,'continuousTargetArea':target,'discreteLiquidArea':discrete,'discreteAreaRelativeError':discrete/target-1,
      'xWallClearanceCells':xclr/h,'yWallClearanceCells':yclr/h,'liquidType':a.liquid_type,'gasType':a.gas_type,'liquidMass':a.liquid_mass,'gasMass':a.gas_mass,
      'liquidKBT':a.liquid_kBT,'gasKBT':a.gas_kBT,'rhoLiquidReference':rhoL,'rhoGasReference':rhoG,'rhoGasOverLiquid':rhoG/rhoL,
      'seed':a.seed,'particles':len(x),'liquidParticles':nL,'gasParticles':nG,'liquidCells':liqCells,'gasCells':gasCells,'mixedCells':mixed,
      'removedGlobalDriftVx':dux,'removedGlobalDriftVy':duy,
    }
    mp=a.output.with_suffix(a.output.suffix+'.json'); mp.write_text(json.dumps(meta,indent=2)+'\n')
    print(f'[0493x14ak-generate] grid={a.nx}x{a.ny} h={h:.10g} gamma={a.gamma} N={len(x)}')
    print(f'[0493x14ak-generate] liquid={nL} gas={nG} mixedCells={mixed} rhoG/rhoL={rhoG/rhoL:.9g}')
    print(f'[0493x14ak-generate] sheet L/h={a.sheet_length_cells:g} H/h={a.thickness_cells:g} edgeRound/h={a.edge_round_cells:g}')
    print(f'[0493x14ak-generate] targetArea={target:.12g} discreteArea={discrete:.12g} relErr={discrete/target-1:+.3e}')
    print(f'[0493x14ak-generate] wall clearance x/h={xclr/h:.6g} y/h={yclr/h:.6g}')
    print(f'[0493x14ak-generate] state={a.output}')
    return 0
if __name__=='__main__': raise SystemExit(main())

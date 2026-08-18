#!/usr/bin/env python3
"""Generate a deterministic two-species circular sessile cap for 0493x9i.

The physical wall is y=0 (outside the computational domain).  The liquid A cap
is the part of a circle inside y>=0.  For a prescribed contact angle theta
measured through liquid A, the circle centre is y_c=-R*cos(theta).  Therefore
its tangent meets the bottom wall at theta and the exact interface curvature is
+1/R with the x9d convention nAB=A->B.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import struct
import sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))


def pos_int(s):
    v=int(s)
    if v<=0: raise argparse.ArgumentTypeError('expected positive integer')
    return v


def pos_float(s):
    v=float(s)
    if not math.isfinite(v) or v<=0: raise argparse.ArgumentTypeError('expected finite positive number')
    return v


def nonneg_float(s):
    v=float(s)
    if not math.isfinite(v) or v<0: raise argparse.ArgumentTypeError('expected finite non-negative number')
    return v


def coprime_multiplier(modulus,start,avoid=-1):
    for off in range(modulus):
        c=1+((start+off-1)%modulus)
        if c!=avoid and math.gcd(c,modulus)==1: return c
    return 1


def paired_velocities(rng,count,mass,kbt):
    if count<=0: return []
    if kbt==0.0 or count==1: return [(0.0,0.0)]*count
    vals=[]
    for _ in range(count//2):
        gx,gy=rng.gauss(0.0,1.0),rng.gauss(0.0,1.0)
        vals.extend(((gx,gy),(-gx,-gy)))
    if count%2: vals.append((0.0,0.0))
    s2=sum(x*x+y*y for x,y in vals)
    scale=math.sqrt((2.0*count*kbt)/(mass*s2)) if s2>0 else 0.0
    return [(scale*x,scale*y) for x,y in vals]


def write_state(path,x,y,vx,vy,typ,mass,role):
    n=len(x)
    reserved=[0]*8; reserved[0]=1; reserved[1]=1
    path.parent.mkdir(parents=True,exist_ok=True)
    if sys.byteorder=='big':
        for a in (x,y,vx,vy,typ,mass): a.byteswap()
    try:
        with path.open('wb') as f:
            f.write(MAGIC)
            f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4))
            f.write(struct.pack('<8Q',*reserved))
            for a in (x,y,vx,vy,typ,mass): a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder=='big':
            for a in (x,y,vx,vy,typ,mass): a.byteswap()


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--Lx',type=pos_float,default=1.6)
    ap.add_argument('--Ly',type=pos_float,default=1.0)
    ap.add_argument('--nx',type=pos_int,default=320)
    ap.add_argument('--ny',type=pos_int,default=200)
    ap.add_argument('--gamma',type=pos_int,default=20)
    ap.add_argument('--center-x',type=float,default=None)
    ap.add_argument('--radius',type=pos_float,default=0.25)
    ap.add_argument('--contact-angle-deg',type=float,default=90.0)
    ap.add_argument('--liquid-type',type=pos_int,default=1)
    ap.add_argument('--gas-type',type=pos_int,default=2)
    ap.add_argument('--liquid-mass',type=pos_float,default=1.0)
    ap.add_argument('--gas-mass',type=pos_float,default=1.0)
    ap.add_argument('--kBT',type=nonneg_float,default=0.125)
    ap.add_argument('--seed',type=int,default=493930)
    args=ap.parse_args()
    if args.gamma<2: ap.error('gamma must be >=2')
    if args.liquid_type==args.gas_type: ap.error('liquid and gas types must differ')
    if not math.isfinite(args.contact_angle_deg) or not (0.0<args.contact_angle_deg<180.0):
        ap.error('contact angle must lie strictly between 0 and 180 for this cap generator')
    cx=args.Lx*0.5 if args.center_x is None else float(args.center_x)
    theta=math.radians(args.contact_angle_deg)
    cy=-args.radius*math.cos(theta)
    half_width=args.radius*math.sin(theta)
    cap_height=args.radius*(1.0-math.cos(theta))
    if cx-half_width<=0.0 or cx+half_width>=args.Lx:
        ap.error('cap contact points must remain away from side walls')
    if cap_height>=args.Ly:
        ap.error('cap must remain below the top wall')
    dx,dy=args.Lx/args.nx,args.Ly/args.ny
    if abs(dx-dy)>1e-12*max(1.0,abs(dx),abs(dy)):
        ap.error('square cells required')
    ax=coprime_multiplier(args.gamma,3); ay=coprime_multiplier(args.gamma,7,avoid=ax)
    rng=random.Random(args.seed)
    x=array('d'); y=array('d'); vx=array('d'); vy=array('d')
    typ=array('I'); mass=array('d'); role=bytearray()
    nl_tot=ng_tot=mixed=0
    for iy in range(args.ny):
        for ix in range(args.nx):
            positions=[]; types=[]
            for k in range(args.gamma):
                fx=((ax*k)%args.gamma+0.5)/args.gamma
                fy=((ay*k)%args.gamma+0.5)/args.gamma
                px,py=(ix+fx)*dx,(iy+fy)*dy
                inside=(px-cx)**2+(py-cy)**2 <= args.radius**2
                positions.append((px,py)); types.append(args.liquid_type if inside else args.gas_type)
            nl=sum(t==args.liquid_type for t in types); ng=args.gamma-nl
            mixed += int(nl>0 and ng>0); nl_tot+=nl; ng_tot+=ng
            vl=paired_velocities(rng,nl,args.liquid_mass,args.kBT)
            vg=paired_velocities(rng,ng,args.gas_mass,args.kBT)
            il=ig=0
            for (px,py),t in zip(positions,types):
                if t==args.liquid_type:
                    ux,uy=vl[il]; il+=1; m=args.liquid_mass
                else:
                    ux,uy=vg[ig]; ig+=1; m=args.gas_mass
                x.append(px); y.append(py); vx.append(ux); vy.append(uy)
                typ.append(t); mass.append(m); role.append(1)
    write_state(args.output,x,y,vx,vy,typ,mass,role)
    meta={
        'profile':'sessile_circular_cap_0493x9i','Lx':args.Lx,'Ly':args.Ly,
        'nx':args.nx,'ny':args.ny,'dx':dx,'dy':dy,'gamma':args.gamma,
        'centerX':cx,'centerY':cy,'radius':args.radius,
        'contactAngleDegrees':args.contact_angle_deg,
        'contactHalfWidth':half_width,'capHeight':cap_height,
        'exactCurvature':1.0/args.radius,
        'liquidType':args.liquid_type,'gasType':args.gas_type,
        'liquidMass':args.liquid_mass,'gasMass':args.gas_mass,'kBT':args.kBT,
        'seed':args.seed,'particles':len(x),'liquidParticles':nl_tot,'gasParticles':ng_tot,
        'mixedCells':mixed,'liquidFractionParticles':nl_tot/max(1,len(x)),
    }
    mp=args.output.with_suffix(args.output.suffix+'.json'); mp.write_text(json.dumps(meta,indent=2)+'\n')
    print(f"[0493x9i-generate] grid={args.nx}x{args.ny} gamma={args.gamma} N={len(x)} theta={args.contact_angle_deg:g} R={args.radius:g} center=({cx:g},{cy:g}) capHeight={cap_height:g} mixedCells={mixed}")
    print(f"[0493x9i-generate] exactKappa={1.0/args.radius:.17g} state={args.output}")
    print(f"[0493x9i-generate] metadata={mp}")
    return 0

if __name__=='__main__': raise SystemExit(main())

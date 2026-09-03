#!/usr/bin/env python3
"""Generate horizontal planar G_bottom|L|G_top state for x14t.

This orientation is deliberate: the qualified resident `wall` family is
periodic in x and wall-like in y.  Thus the liquid slab spans periodic x,
has no contact line, and the pressure-driven motion is along y.

Each native cell starts with exactly zero barycentric velocity and exact
requested 2-D kinetic kBT (for occupancy > 1).
"""
from __future__ import annotations
import argparse, json, math, random, struct, sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
FLUID_ROLE = 1

def pint(s):
    v=int(s)
    if v<=0: raise argparse.ArgumentTypeError("expected positive integer")
    return v

def nint(s):
    v=int(s)
    if v<0: raise argparse.ArgumentTypeError("expected non-negative integer")
    return v

def pfloat(s):
    v=float(s)
    if not math.isfinite(v) or v<=0: raise argparse.ArgumentTypeError("expected finite positive number")
    return v

def nnfloat(s):
    v=float(s)
    if not math.isfinite(v) or v<0: raise argparse.ArgumentTypeError("expected finite non-negative number")
    return v

def coprime_multiplier(modulus, start, avoid=-1):
    if modulus <= 1: return 1
    for off in range(modulus):
        c=1+((start+off-1)%modulus)
        if c != avoid and math.gcd(c,modulus)==1:
            return c
    return 1

def paired_velocities(rng, count, mass, kbt):
    if count<=0: return []
    if count==1 or kbt==0: return [(0.0,0.0)]*count
    vals=[]
    for _ in range(count//2):
        gx,gy=rng.gauss(0,1),rng.gauss(0,1)
        vals.extend(((gx,gy),(-gx,-gy)))
    if count%2: vals.append((0.0,0.0))
    s2=sum(u*u+v*v for u,v in vals)
    scale=math.sqrt((2.0*count*kbt)/(mass*s2))
    return [(scale*u,scale*v) for u,v in vals]

def write_state(path, x,y,vx,vy,typ,mass,role):
    n=len(x)
    path.parent.mkdir(parents=True, exist_ok=True)
    reserved=[0]*8; reserved[0]=1; reserved[1]=1
    if sys.byteorder=="big":
        for a in (x,y,vx,vy,typ,mass): a.byteswap()
    try:
        with path.open("wb") as f:
            f.write(MAGIC)
            f.write(struct.pack("<IIIIQIIII",2,0x01020304,2,1,n,1,1,8,4))
            f.write(struct.pack("<8Q",*reserved))
            for a in (x,y,vx,vy,typ,mass): a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder=="big":
            for a in (x,y,vx,vy,typ,mass): a.byteswap()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--output",type=Path,required=True)
    ap.add_argument("--Lx",type=pfloat,default=1.5625)
    ap.add_argument("--Ly",type=pfloat,default=1.0)
    ap.add_argument("--nx",type=pint,default=400)
    ap.add_argument("--ny",type=pint,default=256)
    ap.add_argument("--liquid-count",type=pint,default=20)
    ap.add_argument("--gas-bottom-count",type=nint,default=22)
    ap.add_argument("--gas-top-count",type=nint,default=18)
    ap.add_argument("--slab-width-cells",type=pint,default=80)
    ap.add_argument("--slab-center-cell",type=float,default=None)
    ap.add_argument("--liquid-type",type=pint,default=1)
    ap.add_argument("--gas-type",type=pint,default=2)
    ap.add_argument("--liquid-mass",type=pfloat,default=1.0)
    ap.add_argument("--gas-mass",type=pfloat,default=0.1)
    ap.add_argument("--liquid-kBT",type=nnfloat,default=0.02)
    ap.add_argument("--gas-kBT",type=nnfloat,default=0.08)
    ap.add_argument("--seed",type=int,default=493150)
    a=ap.parse_args()

    if a.liquid_type==a.gas_type: ap.error("liquid and gas types must differ")
    if a.slab_width_cells>=a.ny: ap.error("slab width must be smaller than ny")
    if a.gas_bottom_count<2 or a.gas_top_count<2: ap.error("gas occupancy must be >=2")

    dx,dy=a.Lx/a.nx,a.Ly/a.ny
    if abs(dx-dy)>1e-12*max(1.0,abs(dx),abs(dy)): ap.error("square cells required")

    center=a.ny/2 if a.slab_center_cell is None else a.slab_center_cell
    s0=center-a.slab_width_cells/2
    s1=center+a.slab_width_cells/2
    if abs(s0-round(s0))>1e-12 or abs(s1-round(s1))>1e-12:
        ap.error("slab interfaces must be cell aligned")
    j0,j1=int(round(s0)),int(round(s1))
    if not (0<j0<j1<a.ny): ap.error("slab must leave gas above and below")
    if j0 != a.ny-j1:
        ap.error("default piston requires equal bottom/top gas compartment heights")

    x=array("d"); y=array("d"); vx=array("d"); vy=array("d")
    typ=array("I"); mass=array("d"); role=bytearray()
    rngL=random.Random(a.seed ^ 0x14A7A1)
    rngGB=random.Random(a.seed ^ 0x14A7B2)
    rngGT=random.Random(a.seed ^ 0x14A7C3)
    nL=nGB=nGT=0

    for iy in range(a.ny):
        for ix in range(a.nx):
            if j0 <= iy < j1:
                count,ptype,pmass,pkbt,rng,start=a.liquid_count,a.liquid_type,a.liquid_mass,a.liquid_kBT,rngL,3
                nL += count
            elif iy < j0:
                count,ptype,pmass,pkbt,rng,start=a.gas_bottom_count,a.gas_type,a.gas_mass,a.gas_kBT,rngGB,5
                nGB += count
            else:
                count,ptype,pmass,pkbt,rng,start=a.gas_top_count,a.gas_type,a.gas_mass,a.gas_kBT,rngGT,7
                nGT += count
            ax=coprime_multiplier(count,start)
            ay=coprime_multiplier(count,start+4,avoid=ax)
            vv=paired_velocities(rng,count,pmass,pkbt)
            for k in range(count):
                fx=((ax*k)%count+0.5)/count
                fy=((ay*k)%count+0.5)/count
                ux,uy=vv[k]
                x.append((ix+fx)*dx); y.append((iy+fy)*dy)
                vx.append(ux); vy.append(uy)
                typ.append(ptype); mass.append(pmass); role.append(FLUID_ROLE)

    write_state(a.output,x,y,vx,vy,typ,mass,role)

    A=dx*dy
    pB=a.gas_bottom_count*a.gas_kBT/A
    pT=a.gas_top_count*a.gas_kBT/A
    rhoL=a.liquid_count*a.liquid_mass/A
    W=a.slab_width_cells*dy
    atheory=(pB-pT)/(rhoL*W)
    meta={
        "profile":"normal_pressure_piston_0493x14t_fix2_horizontal",
        "orientation":"horizontal_slab_motion_y",
        "Lx":a.Lx,"Ly":a.Ly,"nx":a.nx,"ny":a.ny,"dx":dx,"dy":dy,
        "slabStartCellY":j0,"slabEndCellY":j1,"slabWidthCells":a.slab_width_cells,
        "slabWidth":W,"liquidCountPerCell":a.liquid_count,
        "gasBottomCountPerCell":a.gas_bottom_count,"gasTopCountPerCell":a.gas_top_count,
        "liquidType":a.liquid_type,"gasType":a.gas_type,
        "liquidMass":a.liquid_mass,"gasMass":a.gas_mass,
        "liquidKBT":a.liquid_kBT,"gasKBT":a.gas_kBT,"seed":a.seed,
        "particles":len(x),"liquidParticles":nL,"gasBottomParticles":nGB,"gasTopParticles":nGT,
        "pBottom":pB,"pTop":pT,"deltaP":pB-pT,"rhoLiquid":rhoL,"aTheoryY":atheory,
        "initialTotalPx":sum(m*u for m,u in zip(mass,vx)),
        "initialTotalPy":sum(m*v for m,v in zip(mass,vy)),
    }
    mp=a.output.with_suffix(a.output.suffix+".json")
    mp.write_text(json.dumps(meta,indent=2)+"\n")
    print(f"[0493x14t-generate] orientation=horizontal motion=y grid={a.nx}x{a.ny} h={dy:.12g} slabY=[{j0},{j1}) width/h={a.slab_width_cells}")
    print(f"[0493x14t-generate] counts liquid={a.liquid_count} gasBottom={a.gas_bottom_count} gasTop={a.gas_top_count} N={len(x)}")
    print(f"[0493x14t-generate] pBottom={pB:.12g} pTop={pT:.12g} dP={pB-pT:.12g} rhoL={rhoL:.12g} aTheoryY={atheory:.12g}")
    print(f"[0493x14t-generate] state={a.output}")
    print(f"[0493x14t-generate] metadata={mp}")
    return 0

if __name__=="__main__":
    raise SystemExit(main())

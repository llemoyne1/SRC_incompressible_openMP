#!/usr/bin/env python3
"""0493x11b: generate a small-amplitude liquid/vacuum capillary-wave state.

The interface is
    y = H + a*cos(2*pi*mode*x/Lx + phase)
with vacuum above.  Occupancy is sampled with the same deterministic
sub-cell construction used by the x9 liquid/vacuum generators.  Each occupied
cell has zero mean initial velocity and the requested cell-relative kBT.
"""
from __future__ import annotations
import argparse, json, math, random, struct, sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))

def positive_int(x):
    v=int(x)
    if v<=0: raise argparse.ArgumentTypeError("expected positive integer")
    return v

def positive_float(x):
    v=float(x)
    if not math.isfinite(v) or v<=0: raise argparse.ArgumentTypeError("expected positive finite number")
    return v

def nonnegative_float(x):
    v=float(x)
    if not math.isfinite(v) or v<0: raise argparse.ArgumentTypeError("expected non-negative finite number")
    return v

def coprime_multiplier(modulus, start, avoid=-1):
    for off in range(modulus):
        c=1+((start+off-1)%modulus)
        if c!=avoid and math.gcd(c,modulus)==1:
            return c
    return 1

def paired_fluctuations(rng, count, mass, kbt):
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

def write_state(path, x,y,vx,vy,typ,mass,role):
    n=len(x)
    if not all(len(a)==n for a in (y,vx,vy,typ,mass,role)):
        raise RuntimeError("inconsistent arrays")
    reserved=[0]*8
    reserved[0]=1
    reserved[1]=1
    path.parent.mkdir(parents=True,exist_ok=True)
    arrays=(x,y,vx,vy,typ,mass)
    if sys.byteorder=="big":
        for a in arrays: a.byteswap()
    try:
        with path.open("wb") as f:
            f.write(MAGIC)
            f.write(struct.pack("<IIIIQIIII",2,0x01020304,2,1,n,1,1,8,4))
            f.write(struct.pack("<8Q",*reserved))
            for a in arrays: a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder=="big":
            for a in arrays: a.byteswap()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--output",type=Path,required=True)
    ap.add_argument("--Lx",type=positive_float,default=1.0)
    ap.add_argument("--Ly",type=positive_float,default=0.5)
    ap.add_argument("--nx",type=positive_int,default=256)
    ap.add_argument("--ny",type=positive_int,default=128)
    ap.add_argument("--gamma",type=positive_int,default=20)
    ap.add_argument("--mean-height",type=positive_float,default=0.25)
    ap.add_argument("--amplitude-cells",type=positive_float,default=2.0)
    ap.add_argument("--mode",type=positive_int,default=2)
    ap.add_argument("--phase",type=float,default=0.0)
    ap.add_argument("--liquid-type",type=positive_int,default=1)
    ap.add_argument("--liquid-mass",type=positive_float,default=1.0)
    ap.add_argument("--kBT",type=nonnegative_float,default=0.125)
    ap.add_argument("--seed",type=int,default=4931201)
    a=ap.parse_args()

    dx,dy=a.Lx/a.nx,a.Ly/a.ny
    if abs(dx-dy)>1e-12*max(1.0,abs(dx),abs(dy)):
        ap.error("square cells required")
    amp=a.amplitude_cells*dy
    if a.mean_height-amp <= 4*dy or a.mean_height+amp >= a.Ly-4*dy:
        ap.error("interface must remain at least four cells from top/bottom wall")
    wavelength=a.Lx/a.mode
    if amp/wavelength>0.05:
        ap.error("amplitude is too large for the intended linear-wave benchmark")
    k=2*math.pi*a.mode/a.Lx

    ax=coprime_multiplier(a.gamma,3)
    ay=coprime_multiplier(a.gamma,7,avoid=ax)
    rng=random.Random(a.seed)

    x=array("d"); y=array("d"); vx=array("d"); vy=array("d")
    typ=array("I"); mass=array("d"); role=bytearray()
    partial=occupied=0

    # Only cells below the largest possible interface height can be occupied.
    iy_max=min(a.ny-1,int(math.floor((a.mean_height+amp)/dy))+1)
    for iy in range(iy_max+1):
        for ix in range(a.nx):
            pts=[]
            for q in range(a.gamma):
                fx=((ax*q)%a.gamma+0.5)/a.gamma
                fy=((ay*q)%a.gamma+0.5)/a.gamma
                px=(ix+fx)*dx
                py=(iy+fy)*dy
                eta=a.mean_height+amp*math.cos(k*px+a.phase)
                if py<=eta:
                    pts.append((px,py))
            if not pts:
                continue
            occupied+=1
            if len(pts)!=a.gamma: partial+=1
            fluc=paired_fluctuations(rng,len(pts),a.liquid_mass,a.kBT)
            for (px,py),(du,dv) in zip(pts,fluc):
                x.append(px); y.append(py); vx.append(du); vy.append(dv)
                typ.append(a.liquid_type); mass.append(a.liquid_mass); role.append(1)

    write_state(a.output,x,y,vx,vy,typ,mass,role)
    meta={
        "profile":"capillary_wave_liquid_vacuum_0493x11b",
        "Lx":a.Lx,"Ly":a.Ly,"nx":a.nx,"ny":a.ny,"dx":dx,"dy":dy,
        "gamma":a.gamma,"meanHeight":a.mean_height,
        "amplitude":amp,"amplitudeCells":a.amplitude_cells,
        "mode":a.mode,"wavenumber":k,"wavelength":wavelength,"phase":a.phase,
        "liquidType":a.liquid_type,"liquidMass":a.liquid_mass,"kBT":a.kBT,
        "seed":a.seed,"particles":len(x),"occupiedCells":occupied,"partialCells":partial
    }
    mp=a.output.with_suffix(a.output.suffix+".json")
    mp.write_text(json.dumps(meta,indent=2)+"\n")
    print(
        f"[0493x11b-generate] grid={a.nx}x{a.ny} h={dx:.10g} gamma={a.gamma} "
        f"N={len(x)} mode={a.mode} lambda={wavelength:.8g} "
        f"H={a.mean_height:.8g} a={amp:.8g} a/lambda={amp/wavelength:.5f}"
    )
    print(f"[0493x11b-generate] state={a.output}")
    print(f"[0493x11b-generate] metadata={mp}")
    return 0

if __name__=="__main__":
    raise SystemExit(main())

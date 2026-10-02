#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import math
import re
import struct
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len(b"SRCMPCD_STATE"))

def read_array(f, code: str, n: int) -> array:
    a = array(code)
    a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state array")
    return a

def read_state(path: Path):
    with path.open("rb") as f:
        if f.read(16) != MAGIC:
            raise RuntimeError(f"{path}: bad magic")
        raw = f.read(40)
        if len(raw) != 40:
            raise RuntimeError(f"{path}: truncated header")
        version,endian,dim,layout,n,has_type,has_mass,real_bytes,type_bytes = struct.unpack(
            "<IIIIQIIII", raw
        )
        reserved = struct.unpack("<8Q", f.read(64))
        if (version,endian,dim,layout,has_type,has_mass,real_bytes,type_bytes) != (
            2,0x01020304,2,1,1,1,8,4
        ):
            raise RuntimeError(f"{path}: unsupported header")
        x = read_array(f,"d",n)
        y = read_array(f,"d",n)
        vx = read_array(f,"d",n)
        vy = read_array(f,"d",n)
        typ = read_array(f,"I",n)
        mass = read_array(f,"d",n)
        role = bytearray(f.read(n))
        if len(role) != n:
            raise RuntimeError(f"{path}: truncated role payload")
    return dict(n=n,x=x,y=y,vx=vx,vy=vy,typ=typ,mass=mass,role=role)

def linfit(xs, ys):
    n = len(xs)
    if n < 2:
        return math.nan, math.nan, math.nan
    sx=sum(xs); sy=sum(ys)
    sxx=sum(x*x for x in xs); sxy=sum(x*y for x,y in zip(xs,ys))
    den=n*sxx-sx*sx
    if abs(den) <= 0:
        return math.nan, math.nan, math.nan
    a=(n*sxy-sx*sy)/den
    b=(sy-a*sx)/n
    ybar=sy/n
    ssr=sum((yy-(a*x+b))**2 for x,yy in zip(xs,ys))
    sst=sum((yy-ybar)**2 for yy in ys)
    r2=1-ssr/sst if sst>0 else math.nan
    return a,b,r2

def step_from_name(path: Path):
    m=re.search(r"state_step_(\d+)\.smpcd$", path.name)
    return int(m.group(1)) if m else None

def analyse_state(path: Path, step: int, meta: dict, exclude: int):
    s=read_state(path)
    nx=int(meta["Nx"]); ny=int(meta["Ny"])
    Ly=float(meta["Ly"])
    h=Ly/ny
    nliq=int(meta["liquidCells"])
    yGamma=nliq*h
    lt=int(meta["liquidType"]); gt=int(meta["gasType"])
    Uw=float(meta["wallSpeedTop"])-float(meta.get("wallSpeedBottom",0.0))

    # Per-row, per-species mass and momentum.
    ML=[0.0]*ny; PL=[0.0]*ny; NL=[0]*ny
    MG=[0.0]*ny; PG=[0.0]*ny; NG=[0]*ny

    pxL=pxG=pyL=pyG=0.0
    mLtot=mGtot=0.0
    nL=nG=0

    for y,vx,vy,tp,m,role in zip(s["y"],s["vx"],s["vy"],s["typ"],s["mass"],s["role"]):
        if role != 1:
            continue
        j=min(ny-1,max(0,int(math.floor(y/h))))
        if tp == lt:
            ML[j]+=m; PL[j]+=m*vx; NL[j]+=1
            pxL+=m*vx; pyL+=m*vy; mLtot+=m; nL+=1
        elif tp == gt:
            MG[j]+=m; PG[j]+=m*vx; NG[j]+=1
            pxG+=m*vx; pyG+=m*vy; mGtot+=m; nG+=1

    uL=[PL[j]/ML[j] if ML[j]>0 else math.nan for j in range(ny)]
    uG=[PG[j]/MG[j] if MG[j]>0 else math.nan for j in range(ny)]
    yc=[(j+0.5)*h for j in range(ny)]

    rowsL=[j for j in range(exclude,nliq-exclude)
           if math.isfinite(uL[j])]
    rowsG=[j for j in range(nliq+exclude,ny-exclude)
           if math.isfinite(uG[j])]

    aL,bL,r2L=linfit([yc[j] for j in rowsL],[uL[j] for j in rowsL])
    aG,bG,r2G=linfit([yc[j] for j in rowsG],[uG[j] for j in rowsG])

    uLI=aL*yGamma+bL if math.isfinite(aL) else math.nan
    uGI=aG*yGamma+bG if math.isfinite(aG) else math.nan
    uBot=bL if math.isfinite(bL) else math.nan
    uTop=aG*Ly+bG if math.isfinite(aG) else math.nan

    return {
        "step":step,
        "aL":aL,"R2L":r2L,"aG":aG,"R2G":r2G,
        "aL_over_init":aL/float(meta["init_aL"]) if float(meta["init_aL"]) else math.nan,
        "aG_over_init":aG/float(meta["init_aG"]) if float(meta["init_aG"]) else math.nan,
        "uGammaL":uLI,"uGammaG":uGI,
        "interfaceSlipOverUw":(uGI-uLI)/Uw if Uw else math.nan,
        "bottomFitOverUw":uBot/Uw if Uw else math.nan,
        "topFitOverUw":uTop/Uw if Uw else math.nan,
        "meanUxL":pxL/mLtot if mLtot else math.nan,
        "meanUxG":pxG/mGtot if mGtot else math.nan,
        "PxL":pxL,"PxG":pxG,"PxTotal":pxL+pxG,
        "PyTotal":pyL+pyG,
        "massL":mLtot,"massG":mGtot,
        "nL":nL,"nG":nG,
        "topRowGasUx":uG[-1],
        "bottomRowLiquidUx":uL[0],
    }

def main():
    ap=argparse.ArgumentParser(
        description="Audit x23f particle-state shear/momentum independently of LiveVis recorder.")
    ap.add_argument("run_root", type=Path)
    ap.add_argument("--exclude-cells", type=int, default=4)
    args=ap.parse_args()

    rr=args.run_root
    meta_file=next((rr/"init").glob("*.json"))
    init_state=next((rr/"init").glob("*.smpcd"))
    meta=json.loads(meta_file.read_text())

    states=[(0,init_state)]
    for p in sorted((rr/"output").glob("state_step_*.smpcd")):
        st=step_from_name(p)
        if st is not None:
            states.append((st,p))
    states=sorted({st:p for st,p in states}.items())

    rows=[analyse_state(path,st,meta,args.exclude_cells) for st,path in states]
    p0=rows[0]["PxTotal"]
    for r in rows:
        r["PxTotal_over_init"]=r["PxTotal"]/p0 if p0 else math.nan

    outdir=rr/"analysis_0493x23f_semi_couette"
    outdir.mkdir(parents=True,exist_ok=True)
    csvpath=outdir/"dump_profile_momentum_audit_0493x23f.csv"
    with csvpath.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)

    print("===== 0493x23f PARTICLE-DUMP PROFILE / MOMENTUM AUDIT =====")
    print(f"run = {rr}")
    print(f"init aL={meta['init_aL']:.12g} aG={meta['init_aG']:.12g} "
          f"uGamma={meta['init_uInterface']:.12g}")
    print(" step        aL   aL/init       aG   aG/init     R2L    R2G  "
          "topFit/Uw topRow/Uw   Px/Px0")
    Uw=float(meta["wallSpeedTop"])-float(meta.get("wallSpeedBottom",0.0))
    for r in rows:
        print(f"{r['step']:5d}  {r['aL']:9.5g} {r['aL_over_init']:9.4f} "
              f"{r['aG']:9.5g} {r['aG_over_init']:9.4f} "
              f"{r['R2L']:7.4f} {r['R2G']:7.4f} "
              f"{r['topFitOverUw']:9.4f} {r['topRowGasUx']/Uw:9.4f} "
              f"{r['PxTotal_over_init']:9.4f}")
    print(f"CSV = {csvpath}")
    print("==========================================================")

if __name__=="__main__":
    main()

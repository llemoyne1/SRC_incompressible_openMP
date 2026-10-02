#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math, struct
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16-len(b"SRCMPCD_STATE"))

def read_array(f, code, n):
    a = array(code)
    a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state")
    return a

def read_state(path):
    with open(path, "rb") as f:
        if f.read(16) != MAGIC:
            raise RuntimeError("bad magic")
        version,endian,dim,layout,n,has_type,has_mass,real_bytes,type_bytes = struct.unpack(
            "<IIIIQIIII", f.read(40))
        reserved = struct.unpack("<8Q", f.read(64))
        if (version,endian,dim,layout,has_type,has_mass,real_bytes,type_bytes) != (2,0x01020304,2,1,1,1,8,4):
            raise RuntimeError("unsupported state header")
        x=read_array(f,"d",n); y=read_array(f,"d",n)
        vx=read_array(f,"d",n); vy=read_array(f,"d",n)
        typ=read_array(f,"I",n); mass=read_array(f,"d",n)
        role=bytearray(f.read(n))
        if len(role)!=n:
            raise RuntimeError("truncated role")
    return dict(n=n,x=x,y=y,vx=vx,vy=vy,typ=typ,mass=mass,role=role)

def linfit(xs, ys):
    n=len(xs)
    sx=sum(xs); sy=sum(ys)
    sxx=sum(x*x for x in xs); sxy=sum(x*y for x,y in zip(xs,ys))
    den=n*sxx-sx*sx
    a=(n*sxy-sx*sy)/den
    b=(sy-a*sx)/n
    ybar=sy/n
    ssr=sum((y-(a*x+b))**2 for x,y in zip(xs,ys))
    sst=sum((y-ybar)**2 for y in ys)
    r2=1-ssr/sst if sst>0 else float("nan")
    return a,b,r2

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("run_root", type=Path, nargs="?",
        default=Path("runs/0493x23f_article_semi_couette_64x64_Uw0075_seed593171"))
    args=ap.parse_args()
    rr=args.run_root
    js=next((rr/"init").glob("*.json"))
    state=next((rr/"init").glob("*.smpcd"))
    meta=json.loads(js.read_text())
    s=read_state(state)

    nx=int(meta["Nx"]); ny=int(meta["Ny"])
    Lx=float(meta["Lx"]); Ly=float(meta["Ly"])
    h=Ly/ny; nliq=int(meta["liquidCells"])
    yGamma=nliq*h
    Uw=float(meta["wallSpeedTop"])-float(meta.get("wallSpeedBottom",0.0))
    r=float(meta["initMuRatio"])

    rowM=[0.0]*ny; rowPx=[0.0]*ny; rowN=[0]*ny
    for y,vx,m,role in zip(s["y"],s["vx"],s["mass"],s["role"]):
        if role != 1:
            continue
        j=min(ny-1,max(0,int(math.floor(y/h))))
        rowM[j]+=m
        rowPx[j]+=m*vx
        rowN[j]+=1
    rowU=[rowPx[j]/rowM[j] if rowM[j]>0 else float("nan") for j in range(ny)]
    yc=[(j+0.5)*h for j in range(ny)]

    exc=4
    ml=[j for j,y in enumerate(yc) if y>=exc*h and y<=yGamma-exc*h]
    mg=[j for j,y in enumerate(yc) if y>=yGamma+exc*h and y<=Ly-exc*h]
    aL,bL,r2L=linfit([yc[j] for j in ml],[rowU[j] for j in ml])
    aG,bG,r2G=linfit([yc[j] for j in mg],[rowU[j] for j in mg])

    hL=yGamma; hG=Ly-yGamma
    aGth=Uw/(hG+r*hL)
    aLth=r*aGth
    uIth=aLth*hL

    print("===== 0493x23f INITIAL STATE PROFILE CHECK =====")
    print(f"state = {state}")
    print(f"initProfile = {meta.get('initProfile')}")
    print(f"Uw = {Uw:.12g} ; initMuRatio = {r:.12g}")
    print(f"theory: aL={aLth:.12g} aG={aGth:.12g} uGamma={uIth:.12g}")
    print(f"state : aL={aL:.12g} R2L={r2L:.9g}  gain={aL/aLth:.9g}")
    print(f"state : aG={aG:.12g} R2G={r2G:.9g}  gain={aG/aGth:.9g}")
    print(f"state : uBottomRow={rowU[0]:.12g} uTopRow={rowU[-1]:.12g}")
    print(f"state : uGammaLfit={aL*yGamma+bL:.12g} uGammaGfit={aG*yGamma+bG:.12g}")
    print(f"particles = {s['n']} ; row occupancy min/max = {min(rowN)}/{max(rowN)}")
    print("================================================")
if __name__=="__main__":
    main()

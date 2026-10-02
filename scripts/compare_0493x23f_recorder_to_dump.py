#!/usr/bin/env python3
from __future__ import annotations

import argparse, json, math, re, struct
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16-len(b"SRCMPCD_STATE"))

def read_array(f, code, n):
    a = array(code); a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state")
    return a

def read_state(path):
    with path.open("rb") as f:
        if f.read(16) != MAGIC:
            raise RuntimeError(f"{path}: bad magic")
        version,endian,dim,layout,n,has_type,has_mass,real_bytes,type_bytes = struct.unpack("<IIIIQIIII", f.read(40))
        reserved = struct.unpack("<8Q", f.read(64))
        if (version,endian,dim,layout,has_type,has_mass,real_bytes,type_bytes) != (2,0x01020304,2,1,1,1,8,4):
            raise RuntimeError(f"{path}: unsupported state header")
        x=read_array(f,"d",n); y=read_array(f,"d",n)
        vx=read_array(f,"d",n); vy=read_array(f,"d",n)
        typ=read_array(f,"I",n); mass=read_array(f,"d",n)
        role=bytearray(f.read(n))
        if len(role)!=n:
            raise RuntimeError("truncated role")
    return dict(n=n,x=x,y=y,vx=vx,vy=vy,typ=typ,mass=mass,role=role)

def parse_kv(path):
    out={}
    for line in path.read_text(errors="replace").splitlines():
        line=line.split("#",1)[0].strip()
        if not line or "=" not in line:
            continue
        k,v=line.split("=",1)
        out[k.strip()]=v.strip()
    return out

def read_f32(path, n):
    import array as ar
    a=ar.array("f")
    with path.open("rb") as f:
        a.fromfile(f,n)
    if len(a)!=n:
        raise RuntimeError(f"{path}: got {len(a)} floats, expected {n}")
    return [float(v) for v in a]

def linfit(xs, ys):
    n=len(xs)
    sx=sum(xs); sy=sum(ys)
    sxx=sum(x*x for x in xs); sxy=sum(x*y for x,y in zip(xs,ys))
    den=n*sxx-sx*sx
    a=(n*sxy-sx*sy)/den
    b=(sy-a*sx)/n
    yb=sy/n
    ssr=sum((y-(a*x+b))**2 for x,y in zip(xs,ys))
    sst=sum((y-yb)**2 for y in ys)
    r2=1-ssr/sst if sst>0 else math.nan
    return a,b,r2

def corr(a,b):
    aa=[x for x,y in zip(a,b) if math.isfinite(x) and math.isfinite(y)]
    bb=[y for x,y in zip(a,b) if math.isfinite(x) and math.isfinite(y)]
    if len(aa)<2: return math.nan
    ma=sum(aa)/len(aa); mb=sum(bb)/len(bb)
    va=sum((x-ma)**2 for x in aa); vb=sum((y-mb)**2 for y in bb)
    if va<=0 or vb<=0: return math.nan
    return sum((x-ma)*(y-mb) for x,y in zip(aa,bb))/math.sqrt(va*vb)

def main():
    ap=argparse.ArgumentParser(description="Compare x23f filtered recorder fields against an exact particle dump at the same step.")
    ap.add_argument("run_root", type=Path)
    ap.add_argument("--step", type=int, default=None, help="Exact step to compare; default = latest common dump/recorded step.")
    ap.add_argument("--exclude-cells", type=int, default=4)
    args=ap.parse_args()
    rr=args.run_root

    meta=json.loads(next((rr/"init").glob("*.json")).read_text())
    nx=int(meta["Nx"]); ny=int(meta["Ny"])
    Lx=float(meta["Lx"]); Ly=float(meta["Ly"])
    h=Ly/ny; nliq=int(meta["liquidCells"])
    yGamma=nliq*h; Uw=float(meta["wallSpeedTop"])-float(meta.get("wallSpeedBottom",0.0))

    recbase=rr/"output"/"recordings"
    recdirs=[p for p in recbase.iterdir() if p.is_dir()] if recbase.is_dir() else []
    recdir=None
    for p in recdirs:
        if list(p.glob("step_*_field_ux.f32")):
            recdir=p; break
    if recdir is None:
        raise RuntimeError(f"no recording directory under {recbase}")

    manifest=parse_kv(recdir/"manifest.kv") if (recdir/"manifest.kv").exists() else {}
    rnx=int(float(manifest.get("liveGridNx",manifest.get("Nx",nx))))
    rny=int(float(manifest.get("liveGridNy",manifest.get("Ny",ny))))
    if (rnx,rny)!=(nx,ny):
        raise RuntimeError(f"comparison script currently requires recorder grid == solver grid, got {rnx}x{rny} vs {nx}x{ny}")

    recsteps={}
    for p in recdir.glob("step_*_field_ux.f32"):
        m=re.match(r"step_(\d+)_field_ux\.f32$",p.name)
        if m: recsteps[int(m.group(1))]=p
    dumpsteps={}
    for p in (rr/"output").glob("state_step_*.smpcd"):
        m=re.match(r"state_step_(\d+)\.smpcd$",p.name)
        if m: dumpsteps[int(m.group(1))]=p
    common=sorted(set(recsteps)&set(dumpsteps))
    if args.step is None:
        if not common:
            raise RuntimeError("no common recorder/dump step")
        step=common[-1]
    else:
        step=args.step
        if step not in recsteps or step not in dumpsteps:
            raise RuntimeError(f"step {step} not present in both recorder and dumps; common={common}")

    state=read_state(dumpsteps[step])
    # Exact cell-bin reconstruction from particle dump.
    M=[0.0]*(nx*ny); Px=[0.0]*(nx*ny); N=[0]*(nx*ny)
    for x,y,vx,m,role in zip(state["x"],state["y"],state["vx"],state["mass"],state["role"]):
        if role!=1: continue
        ix=min(nx-1,max(0,int(math.floor((x%Lx)/(Lx/nx)))))
        iy=min(ny-1,max(0,int(math.floor(y/(Ly/ny)))))
        c=iy*nx+ix
        M[c]+=m; Px[c]+=m*vx; N[c]+=1
    U=[Px[c]/M[c] if M[c]>0 else 0.0 for c in range(nx*ny)]

    recU=read_f32(recsteps[step],nx*ny)
    rho_path=recdir/f"step_{step:010d}_field_rho.f32"
    recRho=read_f32(rho_path,nx*ny) if rho_path.exists() else [math.nan]*(nx*ny)

    def rowmean(v):
        return [sum(v[iy*nx:(iy+1)*nx])/nx for iy in range(ny)]
    def rowmassweighted(u, w):
        out=[]
        for iy in range(ny):
            us=u[iy*nx:(iy+1)*nx]; ws=w[iy*nx:(iy+1)*nx]
            sw=sum(ws)
            out.append(sum(a*b for a,b in zip(us,ws))/sw if sw>0 else math.nan)
        return out

    dumpRow=rowmassweighted(U,M)
    recRow=rowmassweighted(recU,recRho) if all(math.isfinite(v) for v in recRho) else rowmean(recU)
    recRowPlain=rowmean(recU)

    yc=[(j+0.5)*h for j in range(ny)]
    liq=list(range(args.exclude_cells,nliq-args.exclude_cells))
    gas=list(range(nliq+args.exclude_cells,ny-args.exclude_cells))
    def fit(rows, prof):
        return linfit([yc[j] for j in rows],[prof[j] for j in rows])

    dL=fit(liq,dumpRow); dG=fit(gas,dumpRow)
    rL=fit(liq,recRow);  rG=fit(gas,recRow)
    rpL=fit(liq,recRowPlain); rpG=fit(gas,recRowPlain)

    # Check the common "missing transpose" hypothesis directly.
    recUT=[0.0]*(nx*ny)
    for iy in range(ny):
        for ix in range(nx):
            recUT[iy*nx+ix]=recU[ix*ny+iy]
    recTRow=rowmean(recUT)
    rtL=fit(liq,recTRow); rtG=fit(gas,recTRow)

    # Best affine mapping recorder ux = alpha * dump ux + beta.
    md=sum(U)/len(U); mr=sum(recU)/len(recU)
    var=sum((x-md)**2 for x in U)
    alpha=sum((x-md)*(y-mr) for x,y in zip(U,recU))/var if var>0 else math.nan
    beta=mr-alpha*md if math.isfinite(alpha) else math.nan

    print("===== 0493x23f RECORDER vs PARTICLE DUMP =====")
    print(f"run = {rr}")
    print(f"recording = {recdir}")
    print(f"step = {step}, grid = {nx}x{ny}")
    print("")
    print("Particle dump row profile:")
    print(f"  aL={dL[0]:.12g} R2L={dL[2]:.6g}")
    print(f"  aG={dG[0]:.12g} R2G={dG[2]:.6g}")
    print(f"  top row / Uw = {dumpRow[-1]/Uw:.9g}")
    print("")
    print("Recorder ux, using recorder rho as row weight:")
    print(f"  aL={rL[0]:.12g} R2L={rL[2]:.6g}")
    print(f"  aG={rG[0]:.12g} R2G={rG[2]:.6g}")
    print(f"  top row / Uw = {recRow[-1]/Uw:.9g}")
    print("")
    print("Recorder ux, plain x-average:")
    print(f"  aL={rpL[0]:.12g} R2L={rpL[2]:.6g}")
    print(f"  aG={rpG[0]:.12g} R2G={rpG[2]:.6g}")
    print("")
    print("Recorder ux after transpose hypothesis:")
    print(f"  aL={rtL[0]:.12g} R2L={rtL[2]:.6g}")
    print(f"  aG={rtG[0]:.12g} R2G={rtG[2]:.6g}")
    print("")
    print(f"cellwise corr(recUx,dumpUx) = {corr(recU,U):.9g}")
    print(f"cellwise corr(transposed recUx,dumpUx) = {corr(recUT,U):.9g}")
    print(f"best affine recUx ~= alpha*dumpUx+beta: alpha={alpha:.9g}, beta={beta:.9g}")
    if all(math.isfinite(v) for v in recRho):
        rhoL=sum(recRho[:nliq*nx])/(nliq*nx)
        rhoG=sum(recRho[nliq*nx:])/(nliq*nx)
        print(f"recorder rho phase means: rhoL={rhoL:.9g}, rhoG={rhoG:.9g}, ratio={rhoG/rhoL:.9g}")
    print("================================================")
if __name__=="__main__":
    main()

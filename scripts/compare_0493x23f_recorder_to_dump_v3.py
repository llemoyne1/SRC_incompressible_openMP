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
    ap.add_argument("--step", type=int, default=None,
        help="Dump step to compare. The nearest recorded field is accepted within --max-step-delta.")
    ap.add_argument("--max-step-delta", type=int, default=1,
        help="Maximum |recorded_step-dump_step| accepted for the comparison (default: 1).")
    ap.add_argument("--exclude-cells", type=int, default=4)
    args=ap.parse_args()
    rr=args.run_root

    meta=json.loads(next((rr/"init").glob("*.json")).read_text())
    solverNx=int(meta["Nx"]); solverNy=int(meta["Ny"])
    Lx=float(meta["Lx"]); Ly=float(meta["Ly"])
    hSolver=Ly/solverNy; nliq=int(meta["liquidCells"])
    yGamma=nliq*hSolver
    Uw=float(meta["wallSpeedTop"])-float(meta.get("wallSpeedBottom",0.0))

    recbase=rr/"output"/"recordings"
    recdirs=[p for p in recbase.iterdir() if p.is_dir()] if recbase.is_dir() else []
    recdir=None
    for p in recdirs:
        if list(p.glob("step_*_field_ux.f32")):
            recdir=p; break
    if recdir is None:
        raise RuntimeError(f"no recording directory under {recbase}")

    manifest=parse_kv(recdir/"manifest.kv") if (recdir/"manifest.kv").exists() else {}
    rnx=int(float(manifest.get("liveGridNx",manifest.get("recordGridNx",solverNx))))
    rny=int(float(manifest.get("liveGridNy",manifest.get("recordGridNy",solverNy))))

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
        if common:
            dump_step=record_step=common[-1]
        else:
            # Prefer the latest dump for which a recorder frame is close enough.
            candidates=[]
            for ds in sorted(dumpsteps):
                rs=min(recsteps, key=lambda x: abs(x-ds))
                if abs(rs-ds) <= args.max_step_delta:
                    candidates.append((ds,rs))
            if not candidates:
                raise RuntimeError(
                    "no exact/common or near-common recorder/dump step; "
                    f"dump steps={sorted(dumpsteps)}, recorder range={min(recsteps)}..{max(recsteps)}, "
                    f"max_step_delta={args.max_step_delta}")
            dump_step,record_step=candidates[-1]
    else:
        dump_step=args.step
        if dump_step not in dumpsteps:
            raise RuntimeError(
                f"dump step {dump_step} not found; available dumps={sorted(dumpsteps)}")
        record_step=min(recsteps, key=lambda x: abs(x-dump_step))
        if abs(record_step-dump_step) > args.max_step_delta:
            raise RuntimeError(
                f"nearest recorder step to dump {dump_step} is {record_step} "
                f"(delta={record_step-dump_step}); increase --max-step-delta if intentional")

    state=read_state(dumpsteps[dump_step])
    # Reconstruct the particle dump directly on the RECORDER grid so that the
    # comparison is cell-for-cell with the .f32 payload.
    M=[0.0]*(rnx*rny); Px=[0.0]*(rnx*rny); N=[0]*(rnx*rny)
    dxRec=Lx/rnx; dyRec=Ly/rny
    for x,y,vx,m,role in zip(state["x"],state["y"],state["vx"],state["mass"],state["role"]):
        if role!=1: continue
        ix=min(rnx-1,max(0,int(math.floor((x%Lx)/dxRec))))
        iy=min(rny-1,max(0,int(math.floor(y/dyRec))))
        c=iy*rnx+ix
        M[c]+=m; Px[c]+=m*vx; N[c]+=1
    U=[Px[c]/M[c] if M[c]>0 else 0.0 for c in range(rnx*rny)]

    recU=read_f32(recsteps[record_step],rnx*rny)
    rho_path=recdir/f"step_{record_step:010d}_field_rho.f32"
    recRho=read_f32(rho_path,rnx*rny) if rho_path.exists() else [math.nan]*(rnx*rny)

    def rowmean(v):
        return [sum(v[iy*rnx:(iy+1)*rnx])/rnx for iy in range(rny)]
    def rowmassweighted(u, w):
        out=[]
        for iy in range(rny):
            us=u[iy*rnx:(iy+1)*rnx]; ws=w[iy*rnx:(iy+1)*rnx]
            sw=sum(ws)
            out.append(sum(a*b for a,b in zip(us,ws))/sw if sw>0 else math.nan)
        return out

    dumpRow=rowmassweighted(U,M)
    recRow=rowmassweighted(recU,recRho) if all(math.isfinite(v) for v in recRho) else rowmean(recU)
    recRowPlain=rowmean(recU)

    yc=[(j+0.5)*(Ly/rny) for j in range(rny)]
    excl=args.exclude_cells*hSolver
    liq=[j for j,y in enumerate(yc) if y >= excl and y <= yGamma-excl]
    gas=[j for j,y in enumerate(yc) if y >= yGamma+excl and y <= Ly-excl]
    def fit(rows, prof):
        return linfit([yc[j] for j in rows],[prof[j] for j in rows])

    dL=fit(liq,dumpRow); dG=fit(gas,dumpRow)
    rL=fit(liq,recRow);  rG=fit(gas,recRow)
    rpL=fit(liq,recRowPlain); rpG=fit(gas,recRowPlain)

    # Check the common "missing transpose" hypothesis directly.
    recUT=[0.0]*(rnx*rny)
    if rnx == rny:
        for iy in range(rny):
            for ix in range(rnx):
                recUT[iy*rnx+ix]=recU[ix*rny+iy]
    else:
        recUT=[math.nan]*(rnx*rny)
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
    print(f"dump step = {dump_step}, recorder step = {record_step}, delta = {record_step-dump_step}")
    print(f"solver grid = {solverNx}x{solverNy}, recorder grid = {rnx}x{rny}")
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
        split=max(0,min(rny,int(round(yGamma/(Ly/rny)))))
        rhoL=sum(recRho[:split*rnx])/(split*rnx)
        rhoG=sum(recRho[split*rnx:])/((rny-split)*rnx)
        print(f"recorder rho phase means: rhoL={rhoL:.9g}, rhoG={rhoG:.9g}, ratio={rhoG/rhoL:.9g}")
    print("================================================")
if __name__=="__main__":
    main()

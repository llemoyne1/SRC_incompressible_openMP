#!/usr/bin/env python3
"""Offline profile analysis for 0493x14w two-phase Couette.

Geometry:
    gas | liquid | gas
with x periodic and y walls moving at -Uw / +Uw.

The analysis reads only existing state dumps.  No runtime diagnostic is added.
It exploits the exact mirror geometry by forming antisymmetric top/bottom
profiles, which removes common x-drift and improves the interfacial slip estimate.

Primary observables:
  * extrapolated interfacial tangential slip uG^Gamma-uL^Gamma;
  * linearity (R^2) of each phase away from interface/walls;
  * slope ratio aL/aG = muG/muL if tangential stress is continuous;
  * gas-wall slip from the fitted gas profile;
  * convergence of slopes/slip between the last two dumps.
"""
from __future__ import annotations

import argparse, csv, json, math, re, struct, sys
from array import array
from pathlib import Path

MAGIC_PREFIX = b"SRCMPCD_STATE"

def read_array(f, typecode, n, itemsize):
    a = array(typecode)
    a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state")
    if sys.byteorder == "big" and itemsize > 1:
        a.byteswap()
    return a

def read_state(path: Path):
    with path.open("rb") as f:
        magic = f.read(16)
        if not magic.startswith(MAGIC_PREFIX):
            raise RuntimeError(f"bad state magic: {path}")
        fmt = "<IIIIQIIII"
        version,endian,dim,layout,n,has_type,has_mass,real_size,type_size = \
            struct.unpack(fmt, f.read(struct.calcsize(fmt)))
        reserved = struct.unpack("<8Q", f.read(64))
        if endian != 0x01020304 or dim != 2 or layout != 1:
            raise RuntimeError(f"unsupported state header: {path}")
        if not has_type or not has_mass or real_size != 8 or type_size != 4:
            raise RuntimeError(f"unsupported particle layout: {path}")
        n = int(n)
        x = read_array(f,"d",n,8)
        y = read_array(f,"d",n,8)
        vx = read_array(f,"d",n,8)
        vy = read_array(f,"d",n,8)
        typ = read_array(f,"I",n,4)
        mass = read_array(f,"d",n,8)
        if version >= 2:
            role_size = int(reserved[1]) if reserved[1] else 1
            if role_size != 1:
                raise RuntimeError(f"unsupported role size={role_size}")
            role = read_array(f,"B",n,1)
        else:
            role = array("B",[1])*n
    return x,y,vx,vy,typ,mass,role

def parse_step(path: Path):
    m = re.search(r"state_step_(\d+)\.smpcd$", path.name)
    return int(m.group(1)) if m else 0

def ols(points):
    if len(points) < 3:
        return math.nan, math.nan, math.nan, math.nan
    xs=[p[0] for p in points]; ys=[p[1] for p in points]
    mx=sum(xs)/len(xs); my=sum(ys)/len(ys)
    sxx=sum((x-mx)**2 for x in xs)
    if not (sxx > 0):
        return math.nan, math.nan, math.nan, math.nan
    a=sum((x-mx)*(y-my) for x,y in points)/sxx
    b=my-a*mx
    sse=sum((y-(a*x+b))**2 for x,y in points)
    sst=sum((y-my)**2 for y in ys)
    r2=1.0-sse/sst if sst>0 else (1.0 if sse<1e-30 else math.nan)
    rms=math.sqrt(sse/len(points))
    return a,b,r2,rms

def rel_change(a,b):
    if not (math.isfinite(a) and math.isfinite(b)):
        return math.nan
    den=max(abs(a),abs(b),1e-30)
    return abs(a-b)/den

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--initial",type=Path,required=True)
    ap.add_argument("--output-dir",type=Path,required=True)
    ap.add_argument("--analysis-dir",type=Path,required=True)
    ap.add_argument("--Lx",type=float,required=True)
    ap.add_argument("--Ly",type=float,required=True)
    ap.add_argument("--nx",type=int,required=True)
    ap.add_argument("--ny",type=int,required=True)
    ap.add_argument("--dt",type=float,required=True)
    ap.add_argument("--slab-start-cell",type=int,required=True)
    ap.add_argument("--slab-end-cell",type=int,required=True)
    ap.add_argument("--liquid-type",type=int,default=1)
    ap.add_argument("--gas-type",type=int,default=2)
    ap.add_argument("--wall-speed",type=float,required=True)
    ap.add_argument("--interface-exclude-cells",type=int,default=4)
    ap.add_argument("--wall-exclude-cells",type=int,default=4)
    args=ap.parse_args()

    hx=args.Lx/args.nx; hy=args.Ly/args.ny
    if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)):
        raise SystemExit("[0493x14w-analysis] square cells required")
    h=hy
    if args.ny % 2:
        raise SystemExit("[0493x14w-analysis] even ny required for mirror pairing")
    if args.slab_start_cell != args.ny-args.slab_end_cell:
        raise SystemExit("[0493x14w-analysis] liquid slab must be centered")
    if not (0 < args.slab_start_cell < args.slab_end_cell < args.ny):
        raise SystemExit("[0493x14w-analysis] invalid slab bounds")

    yc=0.5*args.Ly
    z_interface=0.5*(args.slab_end_cell-args.slab_start_cell)*h
    z_wall=0.5*args.Ly
    z_liq_max=z_interface-args.interface_exclude_cells*h
    z_gas_min=z_interface+args.interface_exclude_cells*h
    z_gas_max=z_wall-args.wall_exclude_cells*h
    if not (z_liq_max > 2*h and z_gas_max > z_gas_min+2*h):
        raise SystemExit("[0493x14w-analysis] fit windows too narrow")

    states={0:args.initial}
    for p in args.output_dir.glob("state_step_*.smpcd"):
        states[parse_step(p)]=p
    states=sorted(states.items())

    args.analysis_dir.mkdir(parents=True,exist_ok=True)
    raw_csv=args.analysis_dir/"couette_profiles_0493x14w.csv"
    asym_csv=args.analysis_dir/"couette_antisymmetric_profiles_0493x14w.csv"
    metrics_csv=args.analysis_dir/"couette_metrics_0493x14w.csv"
    summary_json=args.analysis_dir/"couette_summary_0493x14w.json"

    raw_fields=["step","time","j","y","z","species","count","mass","meanUx","meanUy"]
    asym_fields=["step","time","pair","z","species","uAntisym","uCommon","vyAntisym","vyCommon"]
    metric_fields=[
        "step","time","liquidSlope","liquidIntercept","liquidR2","liquidFitRms",
        "gasSlope","gasIntercept","gasR2","gasFitRms",
        "uGammaLiquid","uGammaGas","interfaceSlip","interfaceSlipOverUw",
        "muGasOverMuLiquidFromSlopes","gasWallExtrapolated","gasWallSlip","gasWallSlipOverUw",
        "liquidCommonRms","gasCommonRms","normalVelocityRms",
    ]

    metric_rows=[]
    with raw_csv.open("w",newline="") as fr, asym_csv.open("w",newline="") as fa:
        rw=csv.DictWriter(fr,fieldnames=raw_fields); rw.writeheader()
        aw=csv.DictWriter(fa,fieldnames=asym_fields); aw.writeheader()

        for step,path in states:
            x,y,vx,vy,typ,mass,role=read_state(path)
            # per species / y cell: [count,mass,px,py]
            bins={args.liquid_type:[[0,0.0,0.0,0.0] for _ in range(args.ny)],
                  args.gas_type:[[0,0.0,0.0,0.0] for _ in range(args.ny)]}
            for i in range(len(y)):
                if role[i] != 1: continue
                t=int(typ[i])
                if t not in bins: continue
                j=int(math.floor(y[i]/h))
                if j<0: j=0
                elif j>=args.ny: j=args.ny-1
                q=bins[t][j]
                q[0]+=1; q[1]+=mass[i]; q[2]+=mass[i]*vx[i]; q[3]+=mass[i]*vy[i]

            means={}
            for t,name in ((args.liquid_type,"liquid"),(args.gas_type,"gas")):
                arr=[]
                for j,q in enumerate(bins[t]):
                    cnt,mm,px,py=q
                    ux=px/mm if mm>0 else math.nan
                    uy=py/mm if mm>0 else math.nan
                    yy=(j+0.5)*h
                    arr.append((ux,uy,cnt,mm))
                    rw.writerow({"step":step,"time":step*args.dt,"j":j,"y":yy,"z":yy-yc,
                                 "species":name,"count":cnt,"mass":mm,"meanUx":ux,"meanUy":uy})
                means[t]=arr

            paired={}
            for t,name in ((args.liquid_type,"liquid"),(args.gas_type,"gas")):
                vals=[]
                for jb in range(args.ny//2):
                    jt=args.ny-1-jb
                    ub,vb,cb,mb=means[t][jb]
                    ut,vt,ct,mt=means[t][jt]
                    if not (math.isfinite(ub) and math.isfinite(ut)): continue
                    z=(jt+0.5)*h-yc
                    ua=0.5*(ut-ub); uc=0.5*(ut+ub)
                    va=0.5*(vt-vb) if math.isfinite(vb) and math.isfinite(vt) else math.nan
                    vc=0.5*(vt+vb) if math.isfinite(vb) and math.isfinite(vt) else math.nan
                    vals.append((z,ua,uc,va,vc))
                    aw.writerow({"step":step,"time":step*args.dt,"pair":jb,"z":z,
                                 "species":name,"uAntisym":ua,"uCommon":uc,
                                 "vyAntisym":va,"vyCommon":vc})
                paired[t]=vals

            lp=[(z,ua) for z,ua,uc,va,vc in paired[args.liquid_type]
                if 0.0 < z <= z_liq_max]
            gp=[(z,ua) for z,ua,uc,va,vc in paired[args.gas_type]
                if z_gas_min <= z <= z_gas_max]
            aL,bL,r2L,rmsL=ols(lp)
            aG,bG,r2G,rmsG=ols(gp)
            uLi=aL*z_interface+bL if math.isfinite(aL) else math.nan
            uGi=aG*z_interface+bG if math.isfinite(aG) else math.nan
            slip=uGi-uLi if math.isfinite(uGi) and math.isfinite(uLi) else math.nan
            uwall=aG*z_wall+bG if math.isfinite(aG) else math.nan
            wall_slip=args.wall_speed-uwall if math.isfinite(uwall) else math.nan
            ratio=aL/aG if math.isfinite(aL) and math.isfinite(aG) and abs(aG)>1e-30 else math.nan

            lcommon=[uc for z,ua,uc,va,vc in paired[args.liquid_type] if 0.0<z<=z_liq_max]
            gcommon=[uc for z,ua,uc,va,vc in paired[args.gas_type] if z_gas_min<=z<=z_gas_max]
            allvy=[]
            for t in (args.liquid_type,args.gas_type):
                for z,ua,uc,va,vc in paired[t]:
                    if math.isfinite(va): allvy.append(va)
                    if math.isfinite(vc): allvy.append(vc)
            lrms=math.sqrt(sum(v*v for v in lcommon)/len(lcommon)) if lcommon else math.nan
            grms=math.sqrt(sum(v*v for v in gcommon)/len(gcommon)) if gcommon else math.nan
            vyrms=math.sqrt(sum(v*v for v in allvy)/len(allvy)) if allvy else math.nan

            row={
                "step":step,"time":step*args.dt,
                "liquidSlope":aL,"liquidIntercept":bL,"liquidR2":r2L,"liquidFitRms":rmsL,
                "gasSlope":aG,"gasIntercept":bG,"gasR2":r2G,"gasFitRms":rmsG,
                "uGammaLiquid":uLi,"uGammaGas":uGi,"interfaceSlip":slip,
                "interfaceSlipOverUw":slip/args.wall_speed if args.wall_speed else math.nan,
                "muGasOverMuLiquidFromSlopes":ratio,
                "gasWallExtrapolated":uwall,"gasWallSlip":wall_slip,
                "gasWallSlipOverUw":wall_slip/args.wall_speed if args.wall_speed else math.nan,
                "liquidCommonRms":lrms,"gasCommonRms":grms,"normalVelocityRms":vyrms,
            }
            metric_rows.append(row)
            print("[0493x14w-analysis] "
                  f"step={step:6d} t={step*args.dt:.6g} "
                  f"aL={aL:+.6g} R2L={r2L:.5f} aG={aG:+.6g} R2G={r2G:.5f} "
                  f"uLΓ={uLi:+.6g} uGΓ={uGi:+.6g} slip/Uw={row['interfaceSlipOverUw']:+.4%} "
                  f"muG/muL|slope={ratio:.6g} wallSlip/Uw={row['gasWallSlipOverUw']:+.4%}")

    with metrics_csv.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=metric_fields); w.writeheader(); w.writerows(metric_rows)

    final=metric_rows[-1]
    prev=metric_rows[-2] if len(metric_rows)>=2 else None
    conv={}
    if prev:
        conv={
            "liquidSlopeRelativeChange":rel_change(final["liquidSlope"],prev["liquidSlope"]),
            "gasSlopeRelativeChange":rel_change(final["gasSlope"],prev["gasSlope"]),
            "interfaceSlipAbsoluteChangeOverUw":
                abs(final["interfaceSlipOverUw"]-prev["interfaceSlipOverUw"])
                if math.isfinite(final["interfaceSlipOverUw"]) and math.isfinite(prev["interfaceSlipOverUw"])
                else math.nan,
        }

    # Conservative structural status: quantitative tangential qualification is
    # intentionally not hard-coded until the first campaign is inspected.
    structural=(
        math.isfinite(final["liquidR2"]) and final["liquidR2"]>0.97 and
        math.isfinite(final["gasR2"]) and final["gasR2"]>0.97 and
        math.isfinite(final["interfaceSlipOverUw"]) and
        abs(final["interfaceSlipOverUw"])<0.20
    )
    summary={
        "benchmark":"0493x14w_two_phase_couette",
        "status":"PASS-like-structural" if structural else "REVIEW",
        "geometry":{
            "Lx":args.Lx,"Ly":args.Ly,"nx":args.nx,"ny":args.ny,"h":h,
            "slabStartCell":args.slab_start_cell,"slabEndCell":args.slab_end_cell,
            "zInterface":z_interface,
            "interfaceExcludeCells":args.interface_exclude_cells,
            "wallExcludeCells":args.wall_exclude_cells,
        },
        "wallSpeedMagnitude":args.wall_speed,
        "final":final,
        "convergenceFromPreviousDump":conv,
        "interpretation":{
            "interfaceSlip":"target near zero for tangential velocity continuity",
            "slopeRatio":"muGas/muLiquid = liquidSlope/gasSlope if tangential stress is continuous",
            "wallSlip":"diagnostic of the already-characterized thermal moving-wall coupling",
        }
    }
    summary_json.write_text(json.dumps(summary,indent=2,allow_nan=True)+"\n")

    print(f"[0493x14w-analysis] status={summary['status']}")
    if prev:
        print("[0493x14w-analysis] convergence "
              f"dSlopeL={conv['liquidSlopeRelativeChange']:.3%} "
              f"dSlopeG={conv['gasSlopeRelativeChange']:.3%} "
              f"dSlip/Uw={conv['interfaceSlipAbsoluteChangeOverUw']:.3%}")
    print(f"[0493x14w-analysis] metrics={metrics_csv}")
    print(f"[0493x14w-analysis] summary={summary_json}")

if __name__=="__main__":
    main()

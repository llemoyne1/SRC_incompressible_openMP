#!/usr/bin/env python3
"""
0493x14r — pooled bounded-ramp fit for gas-accessible volume.

Offline only. No solver/CUDA modification. Python standard library only.

Input:
  alpha_gas_volume_0493x14p_faces.csv

For each geometry independently:
  g = 1 - alpha
  y = Ng / Ntarget

Fit ONE pooled pair (g0,g1) over all selected candidate steps:

              0                        g <= g0
  f(g) =      (g-g0)/(g1-g0)          g0 < g < g1
              1                        g >= g1

Then use exactly that same fitted pair, without refitting, at every step:

  Ng_corr = Ng / f(g)

The script reports:
  * pooled fit RMSE in y-space;
  * per-step raw/corrected mean, std, RMS error and relative m=4;
  * fraction of samples in the low/high clamps;
  * binned y(g) means/std and sample counts;
  * optional no-reflection control scored with the candidate fit.

It writes dependency-free SVG plots:
  - binned Q6 and CIC cloud + bounded ramp;
  - per-step corrected m=4 versus time;
  - last-step corrected count versus interface angle.

The purpose is diagnostic: determine whether a simple bounded local volume law
can remove the cut-cell pressure bias before any CUDA implementation is proposed.
"""
from __future__ import annotations

import argparse, csv, html, math
from collections import defaultdict
from pathlib import Path

def read_faces(path: Path, wanted_steps):
    out=[]
    with path.open(newline="") as f:
        rd=csv.DictReader(f)
        req={"step","theta","Ng","gasFracQ6","gasFracCIC"}
        miss=req-set(rd.fieldnames or [])
        if miss:
            raise RuntimeError(f"{path}: missing columns {sorted(miss)}")
        for r in rd:
            st=int(float(r["step"]))
            if wanted_steps is not None and st not in wanted_steps:
                continue
            out.append({
                "step":st,
                "theta":float(r["theta"]),
                "Ng":float(r["Ng"]),
                "gQ6":float(r["gasFracQ6"]),
                "gCIC":float(r["gasFracCIC"]),
            })
    if not out:
        raise RuntimeError(f"{path}: no selected rows")
    return out

def ramp(g,g0,g1):
    if g <= g0: return 0.0
    if g >= g1: return 1.0
    return (g-g0)/(g1-g0)

def fit_ramp(rows,key,target):
    g=[r[key] for r in rows]
    y=[r["Ng"]/target for r in rows]

    # Physical search range determined only from observed g.
    gmin=max(0.0,min(g)-0.15)
    gmax=min(1.0,max(g)+0.05)

    def sse(g0,g1):
        if not (0.0 <= g0 < g1 <= 1.0): return float("inf")
        return sum((yi-ramp(gi,g0,g1))**2 for gi,yi in zip(g,y))

    best=(float("inf"),0.34,0.90)
    # Coarse search.
    n0=181
    n1=181
    for i in range(n0):
        g0=gmin+(min(0.70,gmax-0.05)-gmin)*i/(n0-1)
        lo=max(g0+0.05,0.55)
        if lo>=gmax: continue
        for j in range(n1):
            g1=lo+(gmax-lo)*j/(n1-1)
            q=sse(g0,g1)
            if q<best[0]:
                best=(q,g0,g1)

    # Local refinements.
    _,bg0,bg1=best
    span0=max(0.01,(min(0.70,gmax-0.05)-gmin)/20)
    span1=max(0.01,(gmax-max(bg0+0.05,0.55))/20)
    for _ in range(5):
        lo0=max(0.0,bg0-span0); hi0=min(bg1-0.02,bg0+span0)
        lo1=max(bg0+0.02,bg1-span1); hi1=min(1.0,bg1+span1)
        for i in range(101):
            g0=lo0+(hi0-lo0)*i/100
            for j in range(101):
                g1=lo1+(hi1-lo1)*j/100
                if g1<=g0: continue
                q=sse(g0,g1)
                if q<best[0]:
                    best=(q,g0,g1)
                    bg0,bg1=g0,g1
        span0*=0.25; span1*=0.25
    return best[1],best[2],best[0]

def mean(v):
    return sum(v)/len(v) if v else math.nan

def std(v):
    if not v:return math.nan
    m=mean(v)
    return math.sqrt(sum((x-m)**2 for x in v)/len(v))

def rmse(v,target):
    return math.sqrt(sum((x-target)**2 for x in v)/len(v)) if v else math.nan

def solve3(a,b):
    m=[list(a[i])+[b[i]] for i in range(3)]
    for c in range(3):
        piv=max(range(c,3),key=lambda r:abs(m[r][c]))
        if abs(m[piv][c])<1e-20:return None
        m[c],m[piv]=m[piv],m[c]
        q=m[c][c]
        for j in range(c,4):m[c][j]/=q
        for r in range(3):
            if r==c:continue
            q=m[r][c]
            for j in range(c,4):m[r][j]-=q*m[c][j]
    return [m[i][3] for i in range(3)]

def mode4_relative(theta,vals):
    good=[(t,v) for t,v in zip(theta,vals) if math.isfinite(v)]
    if len(good)<6:return math.nan
    s0=float(len(good));sc=ss=scc=sss=scs=sy=syc=sys_=0.0
    for th,y in good:
        c=math.cos(4*th);s=math.sin(4*th)
        sc+=c;ss+=s;scc+=c*c;sss+=s*s;scs+=c*s
        sy+=y;syc+=y*c;sys_+=y*s
    sol=solve3(((s0,sc,ss),(sc,scc,scs),(ss,scs,sss)),(sy,syc,sys_))
    if sol is None or abs(sol[0])<1e-30:return math.nan
    a0,ac,ass=sol
    return math.hypot(ac,ass)/abs(a0)

def evaluate(rows,key,target,g0,g1,min_fraction):
    pred=[ramp(r[key],g0,g1) for r in rows]
    y=[r["Ng"]/target for r in rows]
    y_rmse=math.sqrt(sum((a-b)**2 for a,b in zip(y,pred))/len(rows))
    corr=[];th=[];low=high=invalid=0
    for r,f in zip(rows,pred):
        if f<=0.0:low+=1
        if f>=1.0:high+=1
        if f<min_fraction:
            invalid+=1
            continue
        corr.append(r["Ng"]/f);th.append(r["theta"])
    return {
        "rows":len(rows),
        "g0":g0,"g1":g1,
        "predRmseFraction":y_rmse,
        "rawMean":mean([r["Ng"] for r in rows]),
        "rawStd":std([r["Ng"] for r in rows]),
        "rawRmsErr":rmse([r["Ng"] for r in rows],target),
        "rawM4Rel":mode4_relative([r["theta"] for r in rows],[r["Ng"] for r in rows]),
        "corrMean":mean(corr),
        "corrStd":std(corr),
        "corrRmsErr":rmse(corr,target),
        "corrM4Rel":mode4_relative(th,corr),
        "lowClamp":low,
        "highClamp":high,
        "invalidCorrection":invalid,
        "minFractionUsed":min_fraction,
    }

def per_step(rows,key,target,g0,g1,min_fraction):
    d=defaultdict(list)
    for r in rows:d[r["step"]].append(r)
    out=[]
    for st in sorted(d):
        q=evaluate(d[st],key,target,g0,g1,min_fraction)
        out.append({"step":st,**q})
    return out

def bins(rows,key,target,nbins):
    xs=[r[key] for r in rows]
    lo=max(0.0,min(xs));hi=min(1.0,max(xs))
    if hi<=lo:hi=lo+1e-6
    groups=[[] for _ in range(nbins)]
    for r in rows:
        i=int((r[key]-lo)/(hi-lo)*nbins)
        if i<0:i=0
        if i>=nbins:i=nbins-1
        groups[i].append(r)
    out=[]
    for i,gp in enumerate(groups):
        if not gp:continue
        gv=[r[key] for r in gp]
        y=[r["Ng"]/target for r in gp]
        out.append({
            "bin":i,
            "gLo":lo+(hi-lo)*i/nbins,
            "gHi":lo+(hi-lo)*(i+1)/nbins,
            "gMean":mean(gv),
            "yMean":mean(y),
            "yStd":std(y),
            "n":len(gp),
        })
    return out

def write_csv(path,rows):
    if not rows:return
    with path.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0].keys()))
        w.writeheader();w.writerows(rows)

def esc(x):return html.escape(str(x),quote=True)

def svg_binned(path,rows,binned,key,target,g0,g1,title):
    W,H=960,650; ml,mr,mt,mb=85,30,65,75
    pw=W-ml-mr;ph=H-mt-mb
    xs=[r[key] for r in rows];ys=[r["Ng"]/target for r in rows]
    xmin=max(0,min(xs)-0.03);xmax=min(1.0,max(xs)+0.03)
    ymin=max(0,min(ys)-0.08);ymax=max(1.05,min(1.35,max(ys)+0.08))
    def X(x):return ml+(x-xmin)/(xmax-xmin)*pw
    def Y(y):return mt+(ymax-y)/(ymax-ymin)*ph
    L=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
       f'<text x="{W/2}" y="30" text-anchor="middle" font-family="sans-serif" font-size="20">{esc(title)}</text>']
    for i in range(6):
        xv=xmin+(xmax-xmin)*i/5;xp=X(xv)
        yv=ymin+(ymax-ymin)*i/5;yp=Y(yv)
        L.append(f'<line x1="{xp}" y1="{mt}" x2="{xp}" y2="{mt+ph}" stroke-opacity="0.18"/>')
        L.append(f'<text x="{xp}" y="{mt+ph+25}" text-anchor="middle" font-family="sans-serif" font-size="12">{xv:.2f}</text>')
        L.append(f'<line x1="{ml}" y1="{yp}" x2="{ml+pw}" y2="{yp}" stroke-opacity="0.18"/>')
        L.append(f'<text x="{ml-10}" y="{yp+4}" text-anchor="end" font-family="sans-serif" font-size="12">{yv:.2f}</text>')
    L.append(f'<line x1="{ml}" y1="{mt+ph}" x2="{ml+pw}" y2="{mt+ph}"/>')
    L.append(f'<line x1="{ml}" y1="{mt}" x2="{ml}" y2="{mt+ph}"/>')
    # raw cloud
    for r in rows:
        L.append(f'<circle cx="{X(r[key]):.2f}" cy="{Y(r["Ng"]/target):.2f}" r="1.8" fill-opacity="0.12"/>')
    # binned means + std bars
    for b in binned:
        xp=X(b["gMean"]); ym=Y(b["yMean"])
        y1=Y(b["yMean"]-b["yStd"]);y2=Y(b["yMean"]+b["yStd"])
        L.append(f'<line x1="{xp}" y1="{y1}" x2="{xp}" y2="{y2}" stroke-width="1.4"/>')
        L.append(f'<circle cx="{xp}" cy="{ym}" r="4.0"/>')
    # fitted ramp
    pts=[]
    for i in range(301):
        g=xmin+(xmax-xmin)*i/300
        pts.append(f'{X(g):.2f},{Y(ramp(g,g0,g1)):.2f}')
    L.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke-width="2.2"/>')
    L.append(f'<text x="{ml+pw/2}" y="{H-22}" text-anchor="middle" font-family="sans-serif" font-size="15">g = 1 - alpha</text>')
    L.append(f'<text x="20" y="{mt+ph/2}" transform="rotate(-90 20 {mt+ph/2})" text-anchor="middle" font-family="sans-serif" font-size="15">Ng / Ntarget</text>')
    L.append(f'<text x="{ml+15}" y="{mt+20}" font-family="sans-serif" font-size="13">ramp: g0={g0:.4f}, g1={g1:.4f}</text>')
    L.append('</svg>')
    path.write_text("\n".join(L),encoding="utf-8")

def svg_m4(path,per_q6,per_cic,title):
    W,H=900,560;ml,mr,mt,mb=85,25,65,70;pw=W-ml-mr;ph=H-mt-mb
    steps=sorted({r["step"] for r in per_q6+per_cic})
    ymin=0.0
    vals=[r["rawM4Rel"] for r in per_q6]+[r["corrM4Rel"] for r in per_q6]+[r["corrM4Rel"] for r in per_cic]
    ymax=max(0.05,max(v for v in vals if math.isfinite(v))*1.15)
    xmin=min(steps);xmax=max(steps)
    def X(x):return ml+(x-xmin)/(xmax-xmin if xmax>xmin else 1)*pw
    def Y(y):return mt+(ymax-y)/(ymax-ymin)*ph
    L=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
       f'<text x="{W/2}" y="30" text-anchor="middle" font-family="sans-serif" font-size="20">{esc(title)}</text>']
    for i in range(6):
        y=ymin+(ymax-ymin)*i/5;yp=Y(y)
        L.append(f'<line x1="{ml}" y1="{yp}" x2="{ml+pw}" y2="{yp}" stroke-opacity="0.18"/>')
        L.append(f'<text x="{ml-10}" y="{yp+4}" text-anchor="end" font-family="sans-serif" font-size="12">{y:.3f}</text>')
    series=[
        ("raw Q6 trace",per_q6,"rawM4Rel",""),
        ("ramp Q6",per_q6,"corrM4Rel","8,5"),
        ("ramp CIC",per_cic,"corrM4Rel","2,4"),
    ]
    for j,(lab,rr,key,dash) in enumerate(series):
        pts=" ".join(f'{X(r["step"]):.2f},{Y(r[key]):.2f}' for r in rr if math.isfinite(r[key]))
        dd=f' stroke-dasharray="{dash}"' if dash else ""
        L.append(f'<polyline points="{pts}" fill="none" stroke-width="{1.4+0.3*j}"{dd}/>')
        for r in rr:
            if math.isfinite(r[key]):L.append(f'<circle cx="{X(r["step"]):.2f}" cy="{Y(r[key]):.2f}" r="3"/>')
    for st in steps:
        L.append(f'<text x="{X(st)}" y="{mt+ph+25}" text-anchor="middle" font-family="sans-serif" font-size="12">{st}</text>')
    for j,(lab,_,_,dash) in enumerate(series):
        y=mt+20+22*j;dd=f' stroke-dasharray="{dash}"' if dash else ""
        L.append(f'<line x1="{ml+15}" y1="{y}" x2="{ml+50}" y2="{y}" stroke-width="1.8"{dd}/>')
        L.append(f'<text x="{ml+60}" y="{y+4}" font-family="sans-serif" font-size="12">{esc(lab)}</text>')
    L.append(f'<text x="{ml+pw/2}" y="{H-20}" text-anchor="middle" font-family="sans-serif" font-size="15">step</text>')
    L.append(f'<text x="20" y="{mt+ph/2}" transform="rotate(-90 20 {mt+ph/2})" text-anchor="middle" font-family="sans-serif" font-size="15">relative m=4 amplitude</text>')
    L.append('</svg>')
    path.write_text("\n".join(L),encoding="utf-8")

def svg_angle(path,rows,key,target,g0,g1,min_fraction,title):
    last=max(r["step"] for r in rows)
    rr=[r for r in rows if r["step"]==last]
    raw=sorted((r["theta"],r["Ng"]) for r in rr)
    corr=[]
    for r in rr:
        f=ramp(r[key],g0,g1)
        if f>=min_fraction:
            corr.append((r["theta"],r["Ng"]/f))
    corr.sort()
    vals=[v for _,v in raw+corr]
    W,H=940,600;ml,mr,mt,mb=85,25,65,70;pw=W-ml-mr;ph=H-mt-mb
    xmin=-math.pi;xmax=math.pi;ymin=max(0,min(vals)-2);ymax=max(target+5,max(vals)+2)
    def X(x):return ml+(x-xmin)/(xmax-xmin)*pw
    def Y(y):return mt+(ymax-y)/(ymax-ymin)*ph
    L=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
       f'<text x="{W/2}" y="30" text-anchor="middle" font-family="sans-serif" font-size="20">{esc(title)} — step {last}</text>']
    for i in range(7):
        x=xmin+(xmax-xmin)*i/6
        L.append(f'<text x="{X(x)}" y="{mt+ph+25}" text-anchor="middle" font-family="sans-serif" font-size="12">{x:.2f}</text>')
    for i in range(6):
        y=ymin+(ymax-ymin)*i/5;yp=Y(y)
        L.append(f'<line x1="{ml}" y1="{yp}" x2="{ml+pw}" y2="{yp}" stroke-opacity="0.18"/>')
        L.append(f'<text x="{ml-10}" y="{yp+4}" text-anchor="end" font-family="sans-serif" font-size="12">{y:.1f}</text>')
    L.append(f'<line x1="{ml}" y1="{Y(target)}" x2="{ml+pw}" y2="{Y(target)}" stroke-dasharray="2,3"/>')
    L.append(f'<polyline points="{" ".join(f"{X(t):.2f},{Y(v):.2f}" for t,v in raw)}" fill="none" stroke-width="1.2"/>')
    L.append(f'<polyline points="{" ".join(f"{X(t):.2f},{Y(v):.2f}" for t,v in corr)}" fill="none" stroke-width="2.0" stroke-dasharray="8,5"/>')
    L.append(f'<text x="{ml+15}" y="{mt+20}" font-family="sans-serif" font-size="12">raw</text>')
    L.append(f'<text x="{ml+15}" y="{mt+42}" font-family="sans-serif" font-size="12">ramp corrected</text>')
    L.append(f'<text x="{ml+pw/2}" y="{H-20}" text-anchor="middle" font-family="sans-serif" font-size="15">interface angle theta (rad)</text>')
    L.append(f'<text x="20" y="{mt+ph/2}" transform="rotate(-90 20 {mt+ph/2})" text-anchor="middle" font-family="sans-serif" font-size="15">gas count</text>')
    L.append('</svg>')
    path.write_text("\n".join(L),encoding="utf-8")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--candidate",type=Path,required=True)
    ap.add_argument("--control",type=Path,default=None)
    ap.add_argument("--target",type=float,required=True)
    ap.add_argument("--steps",default="all")
    ap.add_argument("--bins",type=int,default=14)
    ap.add_argument("--min-fraction",type=float,default=0.05,
                    help="only for corrected-count diagnostics; fit itself uses exact bounded ramp")
    ap.add_argument("--outdir",type=Path,required=True)
    ap.add_argument("--prefix",default="accessible_volume_ramp_0493x14r")
    a=ap.parse_args()

    wanted=None if a.steps=="all" else {int(x.strip()) for x in a.steps.split(",") if x.strip()}
    cand=read_faces(a.candidate,wanted)
    ctrl=read_faces(a.control,wanted) if a.control else None
    a.outdir.mkdir(parents=True,exist_ok=True)

    summaries=[];per=[];binrows=[]
    per_geom={}
    fits={}
    for label,key in (("Q6","gQ6"),("CIC","gCIC")):
        g0,g1,sse=fit_ramp(cand,key,a.target)
        fits[label]=(g0,g1)
        pooled=evaluate(cand,key,a.target,g0,g1,a.min_fraction)
        summaries.append({"dataset":"candidate","geometry":label,**pooled})
        ps=per_step(cand,key,a.target,g0,g1,a.min_fraction)
        per_geom[label]=ps
        for r in ps:per.append({"dataset":"candidate","geometry":label,**r})
        bb=bins(cand,key,a.target,a.bins)
        for r in bb:binrows.append({"dataset":"candidate","geometry":label,**r})
        if ctrl is not None:
            cpool=evaluate(ctrl,key,a.target,g0,g1,a.min_fraction)
            summaries.append({"dataset":"control_scored_candidate_fit","geometry":label,**cpool})
            for r in per_step(ctrl,key,a.target,g0,g1,a.min_fraction):
                per.append({"dataset":"control_scored_candidate_fit","geometry":label,**r})
            for r in bins(ctrl,key,a.target,a.bins):
                binrows.append({"dataset":"control","geometry":label,**r})
        svg_binned(a.outdir/f"{a.prefix}_binned_{label.lower()}.svg",
                   cand,bb,key,a.target,g0,g1,
                   f"0493x14r bounded accessible-volume ramp — {label}")
        svg_angle(a.outdir/f"{a.prefix}_angle_{label.lower()}.svg",
                  cand,key,a.target,g0,g1,a.min_fraction,
                  f"0493x14r gas count — {label}")

    svg_m4(a.outdir/f"{a.prefix}_m4_vs_step.svg",
           per_geom["Q6"],per_geom["CIC"],
           "0493x14r m=4 before/after bounded-ramp correction")

    write_csv(a.outdir/f"{a.prefix}_summary.csv",summaries)
    write_csv(a.outdir/f"{a.prefix}_per_step.csv",per)
    write_csv(a.outdir/f"{a.prefix}_bins.csv",binrows)

    print("===== 0493x14r BOUNDED ACCESSIBLE-VOLUME RAMP =====")
    print(f"candidate={a.candidate.resolve()}")
    if a.control: print(f"control={a.control.resolve()}")
    print(f"target={a.target:g} steps={sorted({r['step'] for r in cand})} rows={len(cand)}")
    print()
    for label in ("Q6","CIC"):
        g0,g1=fits[label]
        print(f"{label}: f(g)=clamp((g-{g0:.8f})/({g1:.8f}-{g0:.8f}),0,1)")
        rr=[r for r in summaries if r["dataset"]=="candidate" and r["geometry"]==label][0]
        print(f"  pooled predRMSE(y)={rr['predRmseFraction']:.6f} "
              f"rawMean={rr['rawMean']:.3f} corrMean={rr['corrMean']:.3f} "
              f"rawRMS={rr['rawRmsErr']:.3f} corrRMS={rr['corrRmsErr']:.3f}")
        print(f"  clamps low/high={rr['lowClamp']}/{rr['highClamp']} "
              f"invalid(f<{a.min_fraction:g})={rr['invalidCorrection']}")
        print("  step   rawMean corrMean rawStd corrStd rawM4 corrM4 low high invalid")
        for r in per_geom[label]:
            print(f"  {r['step']:4d}   {r['rawMean']:.3f}   {r['corrMean']:.3f}   "
                  f"{r['rawStd']:.3f}  {r['corrStd']:.3f}  "
                  f"{r['rawM4Rel']:.5f} {r['corrM4Rel']:.5f} "
                  f"{r['lowClamp']:3d} {r['highClamp']:3d} {r['invalidCorrection']:3d}")
        print()

    print("Primary decision criterion:")
    print("  A useful production candidate should keep one pooled (g0,g1),")
    print("  bring corrMean near target at every step, and reduce m=4 at the")
    print("  same steps where raw m=4 becomes large, without many low-clamp samples.")
    print()
    print(f"summary={a.outdir/f'{a.prefix}_summary.csv'}")
    print(f"perStep={a.outdir/f'{a.prefix}_per_step.csv'}")
    print(f"bins={a.outdir/f'{a.prefix}_bins.csv'}")
    print(f"binnedQ6={a.outdir/f'{a.prefix}_binned_q6.svg'}")
    print(f"binnedCIC={a.outdir/f'{a.prefix}_binned_cic.svg'}")
    print(f"m4={a.outdir/f'{a.prefix}_m4_vs_step.svg'}")
    return 0

if __name__=="__main__":
    raise SystemExit(main())

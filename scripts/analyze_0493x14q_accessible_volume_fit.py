#!/usr/bin/env python3
"""
0493x14q — offline fit of gas-accessible fraction from x14p face samples.

Input
-----
The per-face CSV written by analyze_0493x14p_alpha_gas_volume_offline.py:
    alpha_gas_volume_0493x14p_faces.csv

No solver/CUDA modification. Standard Python library only: no numpy, pandas,
scipy or matplotlib.

For each geometry (Q6 alpha and kinetic CIC alpha), fit on the selected
candidate samples

    y = Ng / Ntarget
    g = 1 - alpha

with the deliberately small model family

    identity : f(g) = g                         (0 parameters)
    shift    : f(g) = g - delta                 (1 parameter)
    scale    : f(g) = s g                       (1 parameter)
    affine   : f(g) = a + b g                   (2 parameters)
    power    : f(g) = s g^beta                  (2 parameters)

The pressure/count correction corresponding to a model is

    Ng_corrected = Ng / f(g)

The script reports both prediction quality y ~= f(g) and the quantities that
matter physically for x6g:
    corrected mean/std/RMS relative to Ntarget,
    relative angular m=4 amplitude,
    predicted-fraction range,
    AICc (for comparison only; physical simplicity remains decisive).

The fit is pooled across all requested steps, so it cannot "chase" each time
sample independently. Per-step fits of the simple shift/scale laws are also
reported to test coefficient stability.

Optional --control:
A second x14p faces CSV (e.g. no-reflection case) is scored with the candidate
fit but never used to determine its coefficients.

Graphics
--------
Dependency-free SVG files:
    *_scatter_q6.svg
    *_scatter_cic.svg
show the pooled cloud y=Ng/Ntarget versus g=1-alpha and all candidate curves.

A second pair
    *_corrected_q6.svg
    *_corrected_cic.svg
shows corrected Ng versus interface angle at the last selected step, using the
best simple candidate (identity / shift / scale) and the best AICc model.

This is an offline diagnostic, not a proposal to put the fitted law into CUDA.
"""
from __future__ import annotations

import argparse
import csv
import html
import math
from pathlib import Path
from collections import defaultdict

EPS = 1.0e-9


def read_faces(path: Path, wanted_steps):
    rows = []
    with path.open(newline="") as f:
        rd = csv.DictReader(f)
        required = {"step", "theta", "Ng", "gasFracQ6", "gasFracCIC"}
        missing = required - set(rd.fieldnames or [])
        if missing:
            raise RuntimeError(f"{path}: missing columns: {sorted(missing)}")
        for r in rd:
            step = int(float(r["step"]))
            if wanted_steps is not None and step not in wanted_steps:
                continue
            ng = float(r["Ng"])
            rows.append({
                "step": step,
                "theta": float(r["theta"]),
                "Ng": ng,
                "gQ6": float(r["gasFracQ6"]),
                "gCIC": float(r["gasFracCIC"]),
            })
    if not rows:
        raise RuntimeError(f"{path}: no selected rows")
    return rows


def infer_target(rows, explicit):
    if explicit is not None:
        return float(explicit)
    # x14p face CSV does not carry target. For the present x14 drop campaign
    # gamma_g=20, but do not silently hard-code it: require --target.
    raise RuntimeError("--target is required (20 for the current x14 drop runs)")


def mean(v):
    return sum(v) / len(v) if v else math.nan


def std(v):
    if not v:
        return math.nan
    m = mean(v)
    return math.sqrt(sum((x-m)**2 for x in v) / len(v))


def rmse(v, target):
    return math.sqrt(sum((x-target)**2 for x in v) / len(v)) if v else math.nan


def solve2(s00, s01, s11, b0, b1):
    det = s00*s11 - s01*s01
    if abs(det) < 1e-30:
        return math.nan, math.nan
    return ((b0*s11-b1*s01)/det, (s00*b1-s01*b0)/det)


def fit_identity(g, y):
    return {}


def fit_shift(g, y):
    # minimize sum (y - (g-delta))^2
    return {"delta": mean([gi-yi for gi, yi in zip(g, y)])}


def fit_scale(g, y):
    den = sum(gi*gi for gi in g)
    s = sum(gi*yi for gi, yi in zip(g, y))/den if den > 1e-30 else math.nan
    return {"s": s}


def fit_affine(g, y):
    n = len(g)
    a, b = solve2(float(n), sum(g), sum(gi*gi for gi in g), sum(y), sum(gi*yi for gi,yi in zip(g,y)))
    return {"a": a, "b": b}


def fit_power(g, y):
    # Direct SSE grid/refinement in beta. For fixed beta, optimal scale s is analytic.
    # This avoids a log-fit bias and has no scipy dependency.
    valid = [(gi, yi) for gi, yi in zip(g, y) if gi > 1e-8]
    if not valid:
        return {"s": math.nan, "beta": math.nan}
    def eval_beta(beta):
        z = [gi**beta for gi, _ in valid]
        yy = [yi for _, yi in valid]
        den = sum(v*v for v in z)
        s = sum(v*t for v,t in zip(z,yy))/den if den > 1e-30 else math.nan
        sse = sum((t-s*v)**2 for v,t in zip(z,yy))
        return sse, s
    lo, hi = 0.10, 4.00
    best_b = 1.0
    best_sse, best_s = eval_beta(best_b)
    for _ in range(5):
        ngrid = 401
        step = (hi-lo)/(ngrid-1)
        for i in range(ngrid):
            b = lo+i*step
            sse, s = eval_beta(b)
            if sse < best_sse:
                best_sse, best_s, best_b = sse, s, b
        span = max(step*8.0, (hi-lo)*0.04)
        lo = max(0.02, best_b-span)
        hi = min(8.0, best_b+span)
    return {"s": best_s, "beta": best_b}


FITTERS = {
    "identity": (0, fit_identity),
    "shift": (1, fit_shift),
    "scale": (1, fit_scale),
    "affine": (2, fit_affine),
    "power": (2, fit_power),
}


def fmodel(name, p, g):
    if name == "identity":
        return g
    if name == "shift":
        return g-p["delta"]
    if name == "scale":
        return p["s"]*g
    if name == "affine":
        return p["a"]+p["b"]*g
    if name == "power":
        return p["s"]*(max(g, EPS)**p["beta"])
    raise KeyError(name)


def params_text(name, p):
    if name == "identity":
        return "f=g"
    if name == "shift":
        return f"f=g-{p['delta']:.8g}"
    if name == "scale":
        return f"f={p['s']:.8g}*g"
    if name == "affine":
        return f"f={p['a']:.8g}+{p['b']:.8g}*g"
    if name == "power":
        return f"f={p['s']:.8g}*g^{p['beta']:.8g}"
    return ""


def solve3(a, b):
    m = [list(a[i])+[b[i]] for i in range(3)]
    for c in range(3):
        piv = max(range(c,3), key=lambda r: abs(m[r][c]))
        if abs(m[piv][c]) < 1e-20:
            return None
        m[c],m[piv]=m[piv],m[c]
        q=m[c][c]
        for j in range(c,4): m[c][j]/=q
        for r in range(3):
            if r == c: continue
            q=m[r][c]
            for j in range(c,4): m[r][j]-=q*m[c][j]
    return [m[i][3] for i in range(3)]


def mode4_relative(theta, vals):
    if len(vals) < 6:
        return math.nan
    s0=float(len(vals)); sc=ss=scc=sss=scs=sy=syc=sys_=0.0
    for th,y in zip(theta, vals):
        c=math.cos(4*th); s=math.sin(4*th)
        sc+=c; ss+=s; scc+=c*c; sss+=s*s; scs+=c*s
        sy+=y; syc+=y*c; sys_+=y*s
    sol=solve3(((s0,sc,ss),(sc,scc,scs),(ss,scs,sss)),(sy,syc,sys_))
    if sol is None or abs(sol[0])<1e-30:
        return math.nan
    a0,ac,ass=sol
    return math.hypot(ac,ass)/abs(a0)


def aicc(n, sse, k):
    if n <= 0 or not (sse > 0):
        return -math.inf if sse == 0 else math.nan
    base = n*math.log(sse/n) + 2*k
    if n-k-1 <= 0:
        return math.inf
    return base + 2*k*(k+1)/(n-k-1)


def score(rows, geom_key, target, name, p):
    g=[r[geom_key] for r in rows]
    y=[r["Ng"]/target for r in rows]
    pred=[fmodel(name,p,gi) for gi in g]
    residual=[yi-fi for yi,fi in zip(y,pred)]
    sse=sum(v*v for v in residual)
    valid_frac=[fi for fi in pred if math.isfinite(fi)]
    corrected=[]
    theta=[]
    invalid=0
    for r,fi in zip(rows,pred):
        if not math.isfinite(fi) or fi <= 0.0:
            invalid += 1
            continue
        corrected.append(r["Ng"]/fi)
        theta.append(r["theta"])
    k=FITTERS[name][0]
    return {
        "n": len(rows),
        "model": name,
        "params": params_text(name,p),
        "predRmseFraction": math.sqrt(sse/len(rows)),
        "aicc": aicc(len(rows),sse,k),
        "fractionMin": min(valid_frac) if valid_frac else math.nan,
        "fractionMax": max(valid_frac) if valid_frac else math.nan,
        "fractionOutOf01": sum(1 for v in valid_frac if v <= 0 or v > 1),
        "invalidCorrection": invalid,
        "correctedMean": mean(corrected),
        "correctedStd": std(corrected),
        "correctedRmsErr": rmse(corrected,target),
        "correctedCv": std(corrected)/mean(corrected) if corrected and mean(corrected)!=0 else math.nan,
        "m4CorrectedRel": mode4_relative(theta,corrected),
        "m4RawRel": mode4_relative([r["theta"] for r in rows],[r["Ng"] for r in rows]),
    }


def fit_all(rows, geom_key, target):
    g=[r[geom_key] for r in rows]
    y=[r["Ng"]/target for r in rows]
    params={}
    scores=[]
    for name,(k,fitfun) in FITTERS.items():
        p=fitfun(g,y)
        params[name]=p
        scores.append(score(rows,geom_key,target,name,p))
    return params,scores


def per_step_simple(rows, geom_key, target):
    groups=defaultdict(list)
    for r in rows: groups[r["step"]].append(r)
    out=[]
    for st in sorted(groups):
        rr=groups[st]
        g=[r[geom_key] for r in rr]
        y=[r["Ng"]/target for r in rr]
        ps=fit_shift(g,y)
        pc=fit_scale(g,y)
        out.append({
            "step":st,
            "n":len(rr),
            "gMean":mean(g),
            "NgMean":mean([r["Ng"] for r in rr]),
            "shiftDelta":ps["delta"],
            "scaleS":pc["s"],
            "shiftCorrMean":score(rr,geom_key,target,"shift",ps)["correctedMean"],
            "shiftM4":score(rr,geom_key,target,"shift",ps)["m4CorrectedRel"],
            "scaleCorrMean":score(rr,geom_key,target,"scale",pc)["correctedMean"],
            "scaleM4":score(rr,geom_key,target,"scale",pc)["m4CorrectedRel"],
        })
    return out


def xml_escape(s):
    return html.escape(str(s), quote=True)


def svg_scatter(path, rows, geom_key, target, params, title):
    W,H=980,680
    ml,mr,mt,mb=90,30,70,80
    pw=W-ml-mr; ph=H-mt-mb
    gs=[r[geom_key] for r in rows]
    ys=[r["Ng"]/target for r in rows]
    xmin=max(0.0,min(gs)-0.03); xmax=min(1.02,max(gs)+0.03)
    ymin=max(0.0,min(ys)-0.08); ymax=min(1.35,max(max(ys)+0.08,1.05))
    if xmax<=xmin: xmax=xmin+1
    if ymax<=ymin: ymax=ymin+1
    def X(x): return ml+(x-xmin)/(xmax-xmin)*pw
    def Y(y): return mt+(ymax-y)/(ymax-ymin)*ph
    L=[]
    L.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
    L.append('<rect x="0" y="0" width="100%" height="100%" fill="white"/>')
    L.append(f'<text x="{W/2}" y="32" text-anchor="middle" font-family="sans-serif" font-size="20">{xml_escape(title)}</text>')
    # grid/ticks
    for i in range(6):
        xv=xmin+i*(xmax-xmin)/5
        xp=X(xv)
        L.append(f'<line x1="{xp:.2f}" y1="{mt}" x2="{xp:.2f}" y2="{mt+ph}" stroke="#dddddd"/>')
        L.append(f'<text x="{xp:.2f}" y="{mt+ph+28}" text-anchor="middle" font-family="sans-serif" font-size="12">{xv:.2f}</text>')
        yv=ymin+i*(ymax-ymin)/5
        yp=Y(yv)
        L.append(f'<line x1="{ml}" y1="{yp:.2f}" x2="{ml+pw}" y2="{yp:.2f}" stroke="#dddddd"/>')
        L.append(f'<text x="{ml-12}" y="{yp+4:.2f}" text-anchor="end" font-family="sans-serif" font-size="12">{yv:.2f}</text>')
    L.append(f'<line x1="{ml}" y1="{mt+ph}" x2="{ml+pw}" y2="{mt+ph}" stroke="black"/>')
    L.append(f'<line x1="{ml}" y1="{mt}" x2="{ml}" y2="{mt+ph}" stroke="black"/>')
    L.append(f'<text x="{ml+pw/2}" y="{H-24}" text-anchor="middle" font-family="sans-serif" font-size="15">g = 1 - alpha</text>')
    L.append(f'<text x="22" y="{mt+ph/2}" transform="rotate(-90 22 {mt+ph/2})" text-anchor="middle" font-family="sans-serif" font-size="15">Ng / Ntarget</text>')
    # points
    for r in rows:
        L.append(f'<circle cx="{X(r[geom_key]):.2f}" cy="{Y(r["Ng"]/target):.2f}" r="2.2" fill="black" fill-opacity="0.18"/>')
    # model curves, all monochrome with distinct dash patterns
    dash={"identity":"","shift":"8,5","scale":"2,4","affine":"12,4,2,4","power":"5,3"}
    width={"identity":1.2,"shift":2.0,"scale":2.0,"affine":1.6,"power":1.6}
    for name in FITTERS:
        pts=[]
        for i in range(241):
            gx=xmin+i*(xmax-xmin)/240
            fy=fmodel(name,params[name],gx)
            if math.isfinite(fy):
                pts.append(f'{X(gx):.2f},{Y(fy):.2f}')
        dd=f' stroke-dasharray="{dash[name]}"' if dash[name] else ""
        L.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="black" stroke-width="{width[name]}"{dd}/>')
    # legend
    lx=ml+15; ly=mt+20
    labels=["identity","shift","scale","affine","power"]
    for j,name in enumerate(labels):
        yy=ly+22*j
        dd=f' stroke-dasharray="{dash[name]}"' if dash[name] else ""
        L.append(f'<line x1="{lx}" y1="{yy}" x2="{lx+38}" y2="{yy}" stroke="black" stroke-width="{width[name]}"{dd}/>')
        L.append(f'<text x="{lx+48}" y="{yy+4}" font-family="sans-serif" font-size="12">{xml_escape(name)}: {xml_escape(params_text(name,params[name]))}</text>')
    L.append('</svg>')
    path.write_text("\n".join(L),encoding="utf-8")


def svg_corrected_angle(path, rows, geom_key, target, params, simple_name, best_name, title):
    last=max(r["step"] for r in rows)
    rr=[r for r in rows if r["step"]==last]
    W,H=980,680
    ml,mr,mt,mb=90,30,70,80
    pw=W-ml-mr; ph=H-mt-mb
    xmin=-math.pi; xmax=math.pi
    raw=[r["Ng"] for r in rr]
    series=[("raw",raw)]
    for name in dict.fromkeys([simple_name,best_name]):
        vals=[]
        for r in rr:
            f=fmodel(name,params[name],r[geom_key])
            vals.append(r["Ng"]/f if f>0 else math.nan)
        series.append((name,vals))
    allv=[v for _,vv in series for v in vv if math.isfinite(v)]
    ymin=max(0,min(allv)-2); ymax=max(target+5,max(allv)+2)
    def X(x): return ml+(x-xmin)/(xmax-xmin)*pw
    def Y(y): return mt+(ymax-y)/(ymax-ymin)*ph
    L=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
       '<rect x="0" y="0" width="100%" height="100%" fill="white"/>',
       f'<text x="{W/2}" y="32" text-anchor="middle" font-family="sans-serif" font-size="20">{xml_escape(title)} — step {last}</text>']
    for i in range(7):
        xv=xmin+i*(xmax-xmin)/6
        xp=X(xv)
        L.append(f'<line x1="{xp:.2f}" y1="{mt}" x2="{xp:.2f}" y2="{mt+ph}" stroke="#dddddd"/>')
        L.append(f'<text x="{xp:.2f}" y="{mt+ph+28}" text-anchor="middle" font-family="sans-serif" font-size="12">{xv:.2f}</text>')
    for i in range(6):
        yv=ymin+i*(ymax-ymin)/5
        yp=Y(yv)
        L.append(f'<line x1="{ml}" y1="{yp:.2f}" x2="{ml+pw}" y2="{yp:.2f}" stroke="#dddddd"/>')
        L.append(f'<text x="{ml-12}" y="{yp+4:.2f}" text-anchor="end" font-family="sans-serif" font-size="12">{yv:.1f}</text>')
    L.append(f'<line x1="{ml}" y1="{Y(target):.2f}" x2="{ml+pw}" y2="{Y(target):.2f}" stroke="black" stroke-dasharray="2,3"/>')
    patterns={"raw":"","shift":"8,5","scale":"2,4","identity":"10,4","affine":"12,4,2,4","power":"5,3"}
    for idx,(name,vals) in enumerate(series):
        pts=sorted([(r["theta"],v) for r,v in zip(rr,vals) if math.isfinite(v)])
        poly=" ".join(f'{X(th):.2f},{Y(v):.2f}' for th,v in pts)
        dash=patterns.get(name,"")
        dd=f' stroke-dasharray="{dash}"' if dash else ""
        L.append(f'<polyline points="{poly}" fill="none" stroke="black" stroke-width="{1.2+0.5*idx}"{dd}/>')
    L.append(f'<text x="{ml+pw/2}" y="{H-24}" text-anchor="middle" font-family="sans-serif" font-size="15">interface angle theta (rad)</text>')
    L.append(f'<text x="22" y="{mt+ph/2}" transform="rotate(-90 22 {mt+ph/2})" text-anchor="middle" font-family="sans-serif" font-size="15">Ng corrected</text>')
    ly=mt+18
    for j,(name,_) in enumerate(series):
        yy=ly+22*j
        dash=patterns.get(name,"")
        dd=f' stroke-dasharray="{dash}"' if dash else ""
        L.append(f'<line x1="{ml+15}" y1="{yy}" x2="{ml+53}" y2="{yy}" stroke="black" stroke-width="1.8"{dd}/>')
        L.append(f'<text x="{ml+63}" y="{yy+4}" font-family="sans-serif" font-size="12">{xml_escape(name)}</text>')
    L.append('</svg>')
    path.write_text("\n".join(L),encoding="utf-8")


def write_csv(path, rows):
    if not rows:
        return
    fields=list(rows[0].keys())
    with path.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=fields)
        w.writeheader(); w.writerows(rows)


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--candidate",type=Path,required=True,help="specular-reflection x14p faces CSV")
    ap.add_argument("--control",type=Path,default=None,help="optional no-reflection x14p faces CSV")
    ap.add_argument("--target",type=float,required=True,help="target bulk gas particles/cell; current x14 drop = 20")
    ap.add_argument("--steps",default="all",help="all or comma-separated list")
    ap.add_argument("--outdir",type=Path,default=None)
    ap.add_argument("--prefix",default="accessible_volume_fit_0493x14q")
    args=ap.parse_args()

    wanted=None if args.steps=="all" else {int(x.strip()) for x in args.steps.split(",") if x.strip()}
    cand=read_faces(args.candidate,wanted)
    ctrl=read_faces(args.control,wanted) if args.control else None
    target=args.target
    outdir=(args.outdir if args.outdir else args.candidate.parent).resolve()
    outdir.mkdir(parents=True,exist_ok=True)

    all_scores=[]
    all_perstep=[]
    fitted={}
    for label,key in (("Q6","gQ6"),("CIC","gCIC")):
        pars,scores=fit_all(cand,key,target)
        fitted[label]=pars
        for s in scores:
            all_scores.append({"dataset":"candidate","geometry":label,**s})
        if ctrl is not None:
            for name in FITTERS:
                all_scores.append({"dataset":"control","geometry":label,**score(ctrl,key,target,name,pars[name])})
        for r in per_step_simple(cand,key,target):
            all_perstep.append({"dataset":"candidate","geometry":label,**r})
        if ctrl is not None:
            # refit per step on control only for diagnostics of coefficient stability;
            # these coefficients are not used to score the candidate.
            for r in per_step_simple(ctrl,key,target):
                all_perstep.append({"dataset":"control_ownfit","geometry":label,**r})

        svg_scatter(outdir/f"{args.prefix}_scatter_{label.lower()}.svg",
                    cand,key,target,pars,
                    f"0493x14q candidate cloud — {label} geometry")
        simple=min((s for s in scores if s["model"] in ("identity","shift","scale")),
                   key=lambda s:s["correctedRmsErr"])["model"]
        best=min(scores,key=lambda s:s["aicc"])["model"]
        svg_corrected_angle(outdir/f"{args.prefix}_corrected_{label.lower()}.svg",
                            cand,key,target,pars,simple,best,
                            f"0493x14q corrected gas count — {label}")

    write_csv(outdir/f"{args.prefix}_models.csv",all_scores)
    write_csv(outdir/f"{args.prefix}_per_step.csv",all_perstep)

    print("===== 0493x14q ACCESSIBLE-VOLUME FIT =====")
    print(f"candidate={args.candidate.resolve()}")
    if args.control: print(f"control={args.control.resolve()}")
    print(f"target={target:g} selectedRows={len(cand)} steps={sorted({r['step'] for r in cand})}")
    print()
    for label in ("Q6","CIC"):
        rows=[r for r in all_scores if r["dataset"]=="candidate" and r["geometry"]==label]
        print(f"--- {label} ---")
        print("model     params                              predRMSE  corrMean corrStd corrRMS m4corr f[min,max] out01 AICc")
        for r in rows:
            print(f"{r['model']:<9} {r['params']:<35} "
                  f"{r['predRmseFraction']:.5f}  {r['correctedMean']:.3f} "
                  f"{r['correctedStd']:.3f} {r['correctedRmsErr']:.3f} "
                  f"{r['m4CorrectedRel']:.5f} "
                  f"[{r['fractionMin']:.3f},{r['fractionMax']:.3f}] "
                  f"{r['fractionOutOf01']:>5} {r['aicc']:.2f}")
        simple=min((r for r in rows if r["model"] in ("identity","shift","scale")),
                   key=lambda r:r["correctedRmsErr"])
        besta=min(rows,key=lambda r:r["aicc"])
        print(f"bestSimpleByCorrectedRMS={simple['model']} {simple['params']}")
        print(f"bestAICc={besta['model']} {besta['params']}")
        print()

    print("Coefficient stability by step (candidate):")
    for label in ("Q6","CIC"):
        print(f"  {label}:")
        for r in [x for x in all_perstep if x["dataset"]=="candidate" and x["geometry"]==label]:
            print(f"    step={r['step']:4d} gMean={r['gMean']:.4f} "
                  f"delta={r['shiftDelta']:.5f} scale={r['scaleS']:.5f} "
                  f"m4Shift={r['shiftM4']:.5f} m4Scale={r['scaleM4']:.5f}")

    print()
    print("Decision rule:")
    print("  Prefer identity/shift/scale if one coefficient is stable across time and removes most m=4.")
    print("  Treat affine/power only as evidence of systematic nonlinearity unless their gain is large and stable.")
    print("  Reject a production law whose predicted accessible fraction leaves (0,1] on the observed trace range.")
    print()
    print(f"models={outdir/f'{args.prefix}_models.csv'}")
    print(f"perStep={outdir/f'{args.prefix}_per_step.csv'}")
    print(f"scatterQ6={outdir/f'{args.prefix}_scatter_q6.svg'}")
    print(f"scatterCIC={outdir/f'{args.prefix}_scatter_cic.svg'}")
    print(f"correctedQ6={outdir/f'{args.prefix}_corrected_q6.svg'}")
    print(f"correctedCIC={outdir/f'{args.prefix}_corrected_cic.svg'}")
    return 0

if __name__=="__main__":
    raise SystemExit(main())

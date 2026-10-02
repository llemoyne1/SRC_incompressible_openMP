#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations
import argparse, csv, math
from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt

SATO_LINEAR_COEFF = 1.30
SATO_HIGH_COEFF = 1.37
HIGH_EXPONENT = 0.73
CRITICAL_FR = 1.17

def ffloat(x, default=math.nan):
    try:
        y=float(x)
        return y if math.isfinite(y) else default
    except Exception:
        return default

def read_summary(path: Path):
    if not path.exists():
        raise SystemExit(f"[x24ao] ERROR missing input: {path}")
    with path.open("r", newline="") as h:
        rows=list(csv.DictReader(h))
    if not rows:
        raise SystemExit(f"[x24ao] ERROR empty/no rows: {path}")
    req={"targetFr","meanHOverD","stdHOverD"}
    miss=req-set(rows[0].keys())
    if miss:
        raise SystemExit(f"[x24ao] ERROR {path} missing columns: {sorted(miss)}")
    out=[]
    for r in rows:
        fr=ffloat(r["targetFr"]); hm=ffloat(r["meanHOverD"]); hs=ffloat(r["stdHOverD"])
        if math.isfinite(fr) and math.isfinite(hm):
            out.append(dict(fr=fr,h=hm,hs=hs))
    return out

def dedupe(rows):
    d={}
    for r in rows:
        d[round(r["fr"],12)]=r
    return [d[k] for k in sorted(d)]

def fit_origin(x,y):
    x=np.asarray(x,float); y=np.asarray(y,float)
    m=np.isfinite(x)&np.isfinite(y)
    x=x[m]; y=y[m]
    if len(x)<2 or np.dot(x,x)<=0:
        return math.nan,math.nan
    a=float(np.dot(x,y)/np.dot(x,x))
    yp=a*x
    ssr=float(np.sum((y-yp)**2))
    sst=float(np.sum((y-np.mean(y))**2))
    r2=1.0-ssr/sst if sst>0 else math.nan
    return a,r2

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--low-summary",required=True)
    ap.add_argument("--high-summary",required=True)
    ap.add_argument("--out",default="analysis/0493x24ao_two_regime_sato_fit")
    ap.add_argument("--critical-fr",type=float,default=CRITICAL_FR)
    ap.add_argument("--high-min-fr",type=float,default=2.0)
    ap.add_argument("--high-exponent",type=float,default=HIGH_EXPONENT)
    ap.add_argument("--sato-band",type=float,default=0.20)
    args=ap.parse_args()

    out=Path(args.out); out.mkdir(parents=True,exist_ok=True)
    rows=dedupe(read_summary(Path(args.low_summary))+read_summary(Path(args.high_summary)))

    low=[r for r in rows if r["fr"] < args.critical_fr-1e-12]
    crit=[r for r in rows if abs(r["fr"]-args.critical_fr)<=1e-9]
    high=[r for r in rows if r["fr"] >= args.high_min_fr-1e-12]
    if len(low)<2: raise SystemExit("[x24ao] ERROR fewer than 2 low-Fr points")
    if len(high)<2: raise SystemExit("[x24ao] ERROR fewer than 2 high-Fr points")

    frl=np.array([r["fr"] for r in low]); hl=np.array([r["h"] for r in low])
    a,r2l=fit_origin(frl,hl)

    frh=np.array([r["fr"] for r in high]); hh=np.array([r["h"] for r in high])
    b,r2h=fit_origin(frh**args.high_exponent,hh)

    fra=np.array([r["fr"] for r in rows]); ha=np.array([r["h"] for r in rows]); hsa=np.array([r["hs"] for r in rows])

    plt.rcParams.update({
        "font.family":"DejaVu Sans","font.size":10,"axes.labelsize":11,
        "legend.fontsize":9,"xtick.labelsize":10,"ytick.labelsize":10,
        "pdf.fonttype":42,"ps.fonttype":42,"lines.linewidth":1.8,"lines.markersize":6.0,
    })
    fig,ax=plt.subplots(figsize=(6.8,5.0))

    x1=np.linspace(0,args.critical_fr,300)
    y1=SATO_LINEAR_COEFF*x1
    ax.fill_between(x1,(1-args.sato_band)*y1,(1+args.sato_band)*y1,alpha=0.16,label="Sato ±20%")
    ax.plot(x1,y1,label=rf"Sato subcritical: $h/D={SATO_LINEAR_COEFF:.2f}\,Fr'$")
    ax.plot(x1,a*x1,"--",label=rf"SRC subcritical fit: $h/D={a:.3f}\,Fr'$")

    xmax=max(float(np.max(fra)),3.0)
    x2=np.linspace(args.high_min_fr,xmax,300)
    ax.plot(x2,SATO_HIGH_COEFF*x2**args.high_exponent,
            label=rf"Sato high-$Fr'$: $h/D={SATO_HIGH_COEFF:.2f}\,Fr'^{{{args.high_exponent:.2f}}}$")
    ax.plot(x2,b*x2**args.high_exponent,"--",
            label=rf"SRC high-$Fr'$ fit: $h/D={b:.3f}\,Fr'^{{{args.high_exponent:.2f}}}$")

    ax.errorbar(fra,ha,yerr=hsa,fmt="o",capsize=3.5,label="SRC/MPCD",zorder=5)
    ax.axvline(args.critical_fr,linestyle=":",linewidth=1.0,alpha=0.65)
    ax.text(args.critical_fr,0.03,rf"$Fr'_c={args.critical_fr:g}$",
            rotation=90,va="bottom",ha="right",transform=ax.get_xaxis_transform(),fontsize=9)

    ax.set_xlabel("Target modified Froude number $Fr'$")
    ax.set_ylabel("Cavity depth $h/D$")
    ax.set_xlim(left=0); ax.set_ylim(bottom=0); ax.grid(True,alpha=0.25); ax.legend(loc="upper left")
    fig.tight_layout()
    pdf=out/"fig_two_regime_depth_vs_froude.pdf"
    png=out/"fig_two_regime_depth_vs_froude.png"
    fig.savefig(pdf,format="pdf",bbox_inches="tight")
    fig.savefig(png,dpi=300,bbox_inches="tight")
    plt.close(fig)

    with (out/"two_regime_fit_summary.csv").open("w",newline="") as h:
        fields=["targetFr","meanHOverD","stdHOverD","usedLowFit","usedHighFit",
                "satoLinearPrediction","srcLinearPrediction","satoHighPrediction","srcHighPrediction"]
        w=csv.DictWriter(h,fieldnames=fields); w.writeheader()
        for r in rows:
            fr=r["fr"]
            w.writerow({
                "targetFr":f"{fr:.12g}","meanHOverD":f"{r['h']:.12g}","stdHOverD":f"{r['hs']:.12g}",
                "usedLowFit":int(fr<args.critical_fr-1e-12),
                "usedHighFit":int(fr>=args.high_min_fr-1e-12),
                "satoLinearPrediction":f"{SATO_LINEAR_COEFF*fr:.12g}" if fr<=args.critical_fr+1e-12 else "",
                "srcLinearPrediction":f"{a*fr:.12g}" if fr<=args.critical_fr+1e-12 else "",
                "satoHighPrediction":f"{SATO_HIGH_COEFF*fr**args.high_exponent:.12g}" if fr>=args.high_min_fr-1e-12 else "",
                "srcHighPrediction":f"{b*fr**args.high_exponent:.12g}" if fr>=args.high_min_fr-1e-12 else "",
            })

    with (out/"report.txt").open("w") as h:
        h.write("0493x24ao — two-regime Sato/SRC fit\n===================================\n\n")
        h.write(f"Subcritical: h/D = {a:.8f} Fr', R2={r2l:.8f}\n")
        h.write(f"Sato subcritical coefficient = {SATO_LINEAR_COEFF:.8f}\n")
        h.write(f"Relative coefficient difference = {(a-SATO_LINEAR_COEFF)/SATO_LINEAR_COEFF:+.4%}\n\n")
        if crit:
            for r in crit:
                h.write(f"Critical Fr'={r['fr']:.8g}: h/D={r['h']:.8g} +/- {r['hs']:.8g}\n")
        h.write("\n")
        h.write(f"High-Fr fixed exponent {args.high_exponent:.8f}:\n")
        h.write(f"h/D = {b:.8f} Fr'^{args.high_exponent:.8f}, R2={r2h:.8f}\n")
        h.write(f"Sato high-Fr coefficient = {SATO_HIGH_COEFF:.8f}\n")
        h.write(f"Relative coefficient difference = {(b-SATO_HIGH_COEFF)/SATO_HIGH_COEFF:+.4%}\n\n")
        h.write("Per-point high-Fr normalized coefficient (h/D)/Fr'^0.73:\n")
        for r in high:
            c=r["h"]/(r["fr"]**args.high_exponent)
            h.write(f"Fr'={r['fr']:.8g}: {c:.8f}\n")

    print(f"[x24ao] low fit:  h/D = {a:.6f} Fr', R2={r2l:.6f}")
    print(f"[x24ao] high fit: h/D = {b:.6f} Fr'^{args.high_exponent:.3f}, R2={r2h:.6f}")
    print("[x24ao] wrote", pdf)

if __name__=="__main__":
    main()

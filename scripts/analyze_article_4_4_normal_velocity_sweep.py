#!/usr/bin/env python3
"""
OFFLINE analyzer for a matched normal-incidence velocity sweep.

Input manifest CSV columns:
  label,U,rho,excess_mean[,excess_std,nG,TG]

This script does NOT launch simulations.
It tests excess_mean ~ C * rho * U^2 through the origin.
"""
import argparse,csv,math
from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt

ap=argparse.ArgumentParser()
ap.add_argument("csv")
ap.add_argument("--out",default="article_figures/fig_4_4_normal_excess_scaling")
a=ap.parse_args()

with open(a.csv,newline="") as f:
    R=list(csv.DictReader(f))
if len(R)<3:
    raise SystemExit("need at least 3 rows for a meaningful scaling check")

x=np.array([float(r["rho"])*float(r["U"])**2 for r in R])
y=np.array([float(r["excess_mean"]) for r in R])
den=float(np.dot(x,x))
C=float(np.dot(x,y)/den) if den>0 else float("nan")
fit=C*x
ssres=float(np.sum((y-fit)**2))
sst=float(np.sum((y-y.mean())**2))
r2=1-ssres/sst if sst>0 else float("nan")

print(f"C={C:.17g}")
print(f"R2_origin={r2:.9g}")
for r,xx,yy,ff in zip(R,x,y,fit):
    print(r["label"],"rhoU2=",xx,"excess=",yy,"fit=",ff)

fig,ax=plt.subplots(figsize=(6.2,4.2))
ax.plot(x,y,marker="o",linestyle="none",label="MPCD")
xx=np.linspace(0,max(x)*1.05 if max(x)>0 else 1,200)
ax.plot(xx,C*xx,label=rf"Fit through origin, $R^2={r2:.3f}$")
ax.set_xlabel(r"$\rho_G U_G^2$")
ax.set_ylabel(r"$\langle\Pi_{nn}^{excess}\rangle$")
ax.grid(True,alpha=.25)
ax.legend(frameon=False)
out=Path(a.out); out.parent.mkdir(parents=True,exist_ok=True)
for ext in ("pdf","svg","png"):
    kw={"bbox_inches":"tight"}
    if ext=="png":kw["dpi"]=300
    fig.savefig(out.with_suffix("."+ext),**kw)

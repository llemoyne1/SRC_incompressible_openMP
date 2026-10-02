#!/usr/bin/env python3
"""
Article figure for Section 4.4: two-phase Couette profile.

This is OFFLINE only. It reads the already-produced x14w analysis files.
No solver run is launched.

Default run:
  runs/0493x14w_two_phase_couette_Uw0075_seed593170

The existing analyzer should have produced:
  analysis/couette_summary_0493x14w.json
  analysis/couette_late_averaged_profiles_0493x14w.csv

Usage from repository root:
  python3 scripts/make_article_4_4_couette.py
"""
import argparse, csv, json, math
from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt

ap=argparse.ArgumentParser()
ap.add_argument("--run-root", default="runs/0493x14w_two_phase_couette_Uw0075_seed593170")
ap.add_argument("--mu-ratio", type=float, default=0.23769,
                help="independent muG/muL reference used in historical qualification")
ap.add_argument("--out", default="article_figures/fig_4_4_couette")
a=ap.parse_args()

root=Path(a.run_root)
summary_path=root/"analysis"/"couette_summary_0493x14w.json"
if not summary_path.is_file():
    raise SystemExit(f"missing {summary_path}; run the existing x14w offline analyzer first")
S=json.loads(summary_path.read_text())
prof=Path(S["files"]["lateAveragedProfiles"])
if not prof.is_absolute() and not prof.is_file():
    # summary path is repository-relative in historical output
    prof=Path(S["files"]["lateAveragedProfiles"])
if not prof.is_file():
    raise SystemExit(f"missing {prof}")

with prof.open(newline="") as f:
    rr=list(csv.DictReader(f))
if not rr:
    raise SystemExit("empty late-averaged profile")

cols=list(rr[0])
print("[4.4 Couette] columns:", ",".join(cols))

def pick(cands, contains=()):
    for c in cands:
        if c in cols: return c
    for c in cols:
        lc=c.lower()
        if all(s.lower() in lc for s in contains):
            return c
    return None

zcol=pick(["z","zCenter","zFold","y","yc"], contains=("z",))
oddcol=pick(["oddUx","uOdd","antisymmetricUx","uxOdd","u_a"],
            contains=("odd","ux"))
if oddcol is None:
    oddcol=pick([], contains=("antisym","ux"))
phasecol=pick(["phase","region","family","phaseFamily"])
if zcol is None or oddcol is None:
    raise SystemExit(
        "Cannot identify z/antisymmetric-velocity columns automatically. "
        f"Header={cols}"
    )

z=np.array([float(r[zcol]) for r in rr])
u=np.array([float(r[oddcol]) for r in rr])

Uw=float(S["wallSpeedMagnitude"])
L=float(S["geometry"]["Ly"])
H=0.5*L
zI=float(S["lateAverage"]["zInterfaceDynamic"])
la=S["lateAverage"]
aL=float(la["liquidSlope"]); bL=float(la["liquidIntercept"])
aG=float(la["gasSlope"]); bG=float(la["gasIntercept"])

# Ideal stationary continuum, using dynamic interface location and independent viscosity ratio.
r=float(a.mu_ratio)
aGref=Uw/((H-zI)+r*zI)
aLref=r*aGref
uIref=aLref*zI
zz=np.linspace(0,H,500)
uref=np.where(zz<=zI, aLref*zz, uIref+aGref*(zz-zI))

fig,ax=plt.subplots(figsize=(6.6,4.5))
ax.plot(z/H,u/Uw,marker="o",linestyle="none",markersize=3.2,
        label="MPCD late-time odd profile")
ax.plot(zz/H,uref/Uw,linewidth=1.6,label="Stationary continuum reference")
ax.plot(zz[zz<=zI]/H,(aL*zz[zz<=zI]+bL)/Uw,linestyle="--",linewidth=1.2,
        label="Liquid/gas linear fits")
ax.plot(zz[zz>=zI]/H,(aG*zz[zz>=zI]+bG)/Uw,linestyle="--",linewidth=1.2)
ax.axvline(zI/H,linestyle=":",linewidth=1.0)
ax.set_xlabel(r"Half-channel coordinate $z/H$")
ax.set_ylabel(r"$u_a/U_w$")
ax.grid(True,alpha=.25)
ax.legend(frameon=False,fontsize=8)

tau_ratio=(aL/aG)/r
slip=float(la["interfaceSlipOverUw"])
ax.text(.03,.97,
        rf"$a_L/a_G={aL/aG:.4f}$"+"\n"+
        rf"$\mu_G/\mu_L={r:.4f}$"+"\n"+
        rf"$\tau_L/\tau_G={tau_ratio:.4f}$"+"\n"+
        rf"$\Delta u_\Gamma/U_w={slip:.3f}$",
        transform=ax.transAxes,va="top",fontsize=9)

out=Path(a.out); out.parent.mkdir(parents=True,exist_ok=True)
for ext in ("pdf","svg","png"):
    kw={"bbox_inches":"tight"}
    if ext=="png": kw["dpi"]=300
    fig.savefig(out.with_suffix("."+ext),**kw)
print("[4.4 Couette] wrote", out)

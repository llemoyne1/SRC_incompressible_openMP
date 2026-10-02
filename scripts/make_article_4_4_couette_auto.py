#!/usr/bin/env python3
import argparse, csv, json
from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt

ap = argparse.ArgumentParser()
ap.add_argument("--run-root", default="runs/0493x14w_two_phase_couette_Uw0075_seed593170")
ap.add_argument("--summary", default="")
ap.add_argument("--mu-ratio", type=float, default=0.23769)
ap.add_argument("--out", default="article_figures/fig_4_4_couette")
a = ap.parse_args()

fallback = {
    "wallSpeedMagnitude": 0.075,
    "geometry": {"Ly": 0.5},
    "lateAverage": {
        "liquidSlope": 0.11718597086002695,
        "liquidIntercept": -0.00016329157489998903,
        "gasSlope": 0.5051904093164586,
        "gasIntercept": -0.053338362953896636,
        "uGammaLiquid": 0.01533588936588949,
        "uGammaGas": 0.013478829463273313,
        "interfaceSlipOverUw": -0.024760798701549035,
        "zInterfaceDynamic": 0.1322614031956309
    },
    "files": {}
}

root = Path(a.run_root)
summary_path = Path(a.summary) if a.summary else root/"analysis"/"couette_summary_0493x14w.json"
raw_profile = None

if summary_path.is_file():
    S = json.loads(summary_path.read_text())
    print(f"[4.4 Couette] using local summary: {summary_path}")
    p = S.get("files", {}).get("lateAveragedProfiles", "")
    if p:
        for c in [Path(p), root/"analysis"/Path(p).name, summary_path.parent/Path(p).name]:
            if c.is_file():
                raw_profile = c
                break
else:
    S = fallback
    print("[4.4 Couette] WARNING: historical analysis files are not present locally.")
    print("[4.4 Couette] Using audited historical v2 FIT METRICS only.")
    print("[4.4 Couette] No solver run is launched.")

Uw = float(S["wallSpeedMagnitude"])
H = 0.5*float(S["geometry"]["Ly"])
la = S["lateAverage"]
zI = float(la["zInterfaceDynamic"])
aL = float(la["liquidSlope"]); bL = float(la["liquidIntercept"])
aG = float(la["gasSlope"]); bG = float(la["gasIntercept"])
r = float(a.mu_ratio)

aGref = Uw / ((H-zI) + r*zI)
aLref = r*aGref
uIref = aLref*zI

zz = np.linspace(0,H,500)
uref = np.where(zz <= zI, aLref*zz, uIref + aGref*(zz-zI))
ufit = np.where(zz <= zI, aL*zz+bL, aG*zz+bG)

fig, ax = plt.subplots(figsize=(6.6,4.5))

if raw_profile is not None:
    with raw_profile.open(newline="") as f:
        rr = list(csv.DictReader(f))
    cols = list(rr[0])

    def pick(exacts, contains=()):
        for c in exacts:
            if c in cols:
                return c
        for c in cols:
            lc = c.lower()
            if all(s.lower() in lc for s in contains):
                return c
        return None

    zcol = pick(["z","zCenter","zFold","y","yc"], ("z",))
    ucol = pick(["oddUx","uOdd","antisymmetricUx","uxOdd","u_a"], ("odd","ux"))
    if ucol is None:
        ucol = pick([], ("antisym","ux"))
    if zcol is None or ucol is None:
        raise SystemExit(f"cannot identify z / antisymmetric Ux columns in {cols}")

    z = np.array([float(q[zcol]) for q in rr])
    u = np.array([float(q[ucol]) for q in rr])
    ax.plot(z/H, u/Uw, marker="o", linestyle="none", markersize=3.0,
            label="MPCD late-time odd profile")
    print(f"[4.4 Couette] using raw profile: {raw_profile}")
    kind = "RAW_PROFILE"
else:
    kind = "FIT_ONLY"

ax.plot(zz/H, uref/Uw, linewidth=1.6, label="Stationary continuum reference")
ax.plot(zz/H, ufit/Uw, linestyle="--", linewidth=1.4, label="Late numerical linear fits")
ax.axvline(zI/H, linestyle=":", linewidth=1.0, label=r"$\alpha=0.5$ interface")
ax.scatter([zI/H,zI/H],
           [float(la["uGammaLiquid"])/Uw, float(la["uGammaGas"])/Uw],
           s=28, label="Interface extrapolations")

tau_ratio = (aL/aG)/r
ax.set_xlabel(r"Half-channel coordinate $z/H$")
ax.set_ylabel(r"Antisymmetric velocity $u_a/U_w$")
ax.grid(True, alpha=.25)
ax.legend(frameon=False, fontsize=8)
ax.text(.03,.97,
        rf"$a_L/a_G={aL/aG:.4f}$" + "\n" +
        rf"$\mu_G/\mu_L={r:.4f}$" + "\n" +
        rf"$\tau_L/\tau_G={tau_ratio:.4f}$" + "\n" +
        rf"$\Delta u_\Gamma/U_w={float(la['interfaceSlipOverUw']):.3f}$",
        transform=ax.transAxes, va="top", fontsize=9)
fig.tight_layout()

out = Path(a.out)
out.parent.mkdir(parents=True, exist_ok=True)
for ext in ("pdf","png","svg"):
    kw = {"bbox_inches":"tight"}
    if ext == "png":
        kw["dpi"] = 300
    fig.savefig(out.with_suffix("."+ext), **kw)

print(f"[4.4 Couette] figure_kind={kind}")
print(f"[4.4 Couette] tauL/tauG={tau_ratio:.9g}")
print(f"[4.4 Couette] stress mismatch={(tau_ratio-1)*100:+.3f}%")
print(f"[4.4 Couette] wrote {out}.pdf/.png/.svg")

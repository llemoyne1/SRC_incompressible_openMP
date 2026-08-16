#!/usr/bin/env python3
"""0493x8q short-run checker. Standard library only."""
import argparse, csv, statistics
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("summary", type=Path)
ap.add_argument("--expected-n0", type=int, default=None)
ap.add_argument("--window", type=int, default=50)
a = ap.parse_args()

with a.summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
rows = [r for r in rows if r.get("step", "") != ""]
if len(rows) < 2:
    raise SystemExit("need step 0 plus active rows")

def v(r,k):
    x=r.get(k,"")
    return float(x) if x not in ("",None) else 0.0

req=("nFluidParticles","inletReservoirDeleted","inletBackflowDeleted",
     "outletParticlesDeleted","outletParticlesInserted","inletParticlesInserted",
     "inletNetParticleDelta")
missing=[k for k in req if k not in rows[0]]
if missing: raise SystemExit("missing columns: "+", ".join(missing))
active=[r for r in rows if int(float(r["step"]))>0]
w=active[-min(a.window,len(active)):]
n0=int(round(v(rows[0],"nFluidParticles")))
n1=int(round(v(rows[-1],"nFluidParticles")))
mean=lambda k: statistics.fmean(v(r,k) for r in w)
in_eff=mean("inletParticlesInserted")-mean("inletReservoirDeleted")-mean("inletBackflowDeleted")
out_plus=mean("outletParticlesDeleted")
out_minus=mean("outletParticlesInserted")
out_net=out_plus-out_minus
net=mean("inletNetParticleDelta")
closure=(n1-n0)-sum(v(r,"inletNetParticleDelta") for r in active)
print("===== 0493x8q NEUMANN =====")
print(f"file              : {a.summary}")
print(f"steps             : {len(active)}")
print(f"Nfluid            : {n0} -> {n1}")
print(f"delta N           : {n1-n0:+d} ({100*(n1-n0)/n0:+.5f} %)")
print(f"closure error     : {closure:+.3f}")
print(f"window            : last {len(w)}")
print(f"inlet effective   : {in_eff:.3f} /step")
print(f"outlet outgoing + : {out_plus:.3f} /step")
print(f"outlet incoming - : {out_minus:.3f} /step")
print(f"outlet net        : {out_net:.3f} /step")
print(f"boundary net      : {net:+.3f} /step")
print(f"outlet net/inlet  : {out_net/in_eff:.6f}" if in_eff else "outlet net/inlet  : nan")
if a.expected_n0 is not None:
    print("CHECK initial N    :", "PASS" if n0==a.expected_n0 else f"FAIL expected {a.expected_n0}")
print("CHECK exact closure:", "PASS" if abs(closure)<0.5 else "FAIL")

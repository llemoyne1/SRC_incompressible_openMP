#!/usr/bin/env python3
import argparse, csv, math
from pathlib import Path

def read_rows(path):
    with Path(path).open(newline="") as f:
        return list(csv.DictReader(f))

def isum(rs, key):
    return sum(int(float(r.get(key, 0) or 0)) for r in rs)

def fmaxabs(rs, key):
    vals = []
    for r in rs:
        try:
            v = float(r.get(key, 0) or 0)
        except ValueError:
            continue
        if math.isfinite(v):
            vals.append(abs(v))
    return max(vals, default=0.0)

def ratio(a, b):
    return a / b if b else 0.0

ap = argparse.ArgumentParser()
ap.add_argument("--diag", required=True)
ap.add_argument("--audit", required=True)
a = ap.parse_args()

d = read_rows(a.diag)
u = read_rows(a.audit)
if not d:
    raise SystemExit("[0493x9w-check] ERROR empty x9v diagnostic CSV")
if not u:
    raise SystemExit("[0493x9w-check] ERROR empty x9u reflection CSV")

support = isum(d, "supportExitCrossings")
bulk = isum(d, "supportExitBathAlphaGEHalf")
outer = isum(d, "supportExitBathAlphaLTHalf")
miss_occ = isum(d, "missedOccupiedOuterTarget")
pred_outer = isum(d, "detectorPredictedOuterTarget")
bath_fail = isum(d, "bathSearchFailures")
selected = isum(d, "selectedReflections")
applied = isum(d, "appliedReflections")
unsupported = isum(d, "unsupportedReflections")
no_recv = isum(d, "unsupportedNoReceiverMass")
still_out = isum(d, "appliedStillOutwardRelative")
still_rel = isum(d, "appliedStillRelativeExit")
miss_abs = isum(d, "missedRelativeButAbsoluteExit")
abs_exit = isum(d, "absoluteSupportExitCandidates")

first_outer = int(float(d[0].get("outerSupportParticles", 0) or 0))
last_outer = int(float(d[-1].get("outerSupportParticles", 0) or 0))
last_sparse = int(float(d[-1].get("outerSupportCellParticlesLT3", 0) or 0))

max_dp = max(fmaxabs(d, "deltaPx"), fmaxabs(d, "deltaPy"))
max_de = fmaxabs(d, "deltaKineticEnergy")
strict_bulk_ok = support > 0 and outer == 0 and bulk == support
conservative = max_dp <= 1e-10 and max_de <= 1e-10

print("===== 0493x9w STRICT-BULK KINETIC REFLECTION =====")
print(f"diag={a.diag}")
print(f"audit={a.audit}")
print(f"rows={len(d)} lastStep={d[-1].get('step','?')} reflectionFraction={d[-1].get('reflectionFraction','?')}")
print("--- invariant A: every support-exit recoil bath is physical bulk ---")
print(f"supportExit={support} bathAlpha>=0.5={bulk} bathAlpha<0.5={outer} "
      f"outerBathFraction={ratio(outer,support):.6%} strictBulkOK={int(strict_bulk_ok)}")
print("--- invariant B: occupied halo must not bootstrap cohesive support ---")
print(f"detectorPredictedOuterTarget={pred_outer} missedOccupiedOuterTarget={miss_occ} "
      f"missFraction={ratio(miss_occ,pred_outer):.6%}")
print("--- bounded bath search / unsupported path ---")
print(f"bathSearchFailures={bath_fail} selected={selected} applied={applied} unsupported={unsupported} "
      f"unsupportedFraction={ratio(unsupported,selected):.6%} noReceiverMass={no_recv}")
print("--- post-reflection checks retained from x9v ---")
print(f"appliedStillOutwardRelative={still_out}/{applied} ({ratio(still_out,applied):.6%})")
print(f"appliedStillRelativeExit={still_rel}/{applied} ({ratio(still_rel,applied):.6%})")
print(f"missedRelativeButAbsoluteExit={miss_abs}/{abs_exit} ({ratio(miss_abs,abs_exit):.6%}) [diagnostic; not a gate]")
print("--- halo population proxy ---")
print(f"outerSupport first={first_outer} last={last_outer} growth={last_outer-first_outer:+d} "
      f"lastSparseLT3={last_sparse}")
print("--- conservation ---")
print(f"max|deltaP|={max_dp:.6e} max|deltaKE|={max_de:.6e} conservative={int(conservative)}")
status = "PASS-structural" if strict_bulk_ok and conservative else "FAIL"
print(f"status={status}")

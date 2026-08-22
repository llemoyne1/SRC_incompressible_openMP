#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: analyze_0493x10e_final_endpoint_mirror.py <cuda_phase_kinetic_crossing_0493x9z.csv>')
p = Path(sys.argv[1])
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10e-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def S(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def pct(a,b): return 100.0*a/b if b else 0.0

last = rows[-1]
checks = S('hardFinalEndpointChecks')
out = S('hardFinalEndpointOutsideBefore')
att = S('hardFinalMirrorAttempts')
acc = S('hardFinalMirrorAccepted')
nfb = S('hardFinalMirrorNormalFallbacks')
hfb = S('hardFinalMirrorHardFallbacks')
local = S('hardFinalLocalAnchorCorrections')
miss = S('hardFinalLocalAnchorMisses')
after = S('hardFinalEndpointOutsideAfter')
maxdeep = max(I(r,'deepOuterParticles') for r in rows)
nonin = S('analyticNonInwardPositiveCells')
invalid = S('analyticInvalidCells')
trivial = S('analyticTrivialCells')

print('===== 0493x10e FINAL ENDPOINT TANGENT MIRROR =====')
print(f'file={p} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- barrier load ---')
print(f'outsideBefore={out}/{checks} ({pct(out,checks):.6f}%)')
print(f'mirrorAttempts={att} accepted={acc} ({pct(acc,att):.3f}%)')
print(f'normalFallbacks={nfb} hardFallbacks={hfb} localAnchorCorrections={local}')
print(f'outsideAfter={after}/{checks} anchorMisses={miss} maxDeepOuter={maxdeep}')
print('--- x10d conservation retained ---')
print(f'max|deltaP|={max(maxabs("deltaPx"),maxabs("deltaPy")):.12e}')
print(f'max|deltaKE|={maxabs("deltaKineticEnergy"):.12e}')
print(f'nonInwardPositiveCells={nonin} trivial={trivial} invalid={invalid}')
print(f'last meanA={F(last,"analyticDonorScaleMean"):.9g} mean|a-2|={F(last,"analyticDonorScaleAbsFromSpecularMean"):.9g}')

ret = (after == 0 and miss == 0)
cons = max(maxabs('deltaPx'), maxabs('deltaPy')) < 1e-9 and maxabs('deltaKineticEnergy') < 1e-9
print('hardRetentionContract=' + ('PASS' if ret else 'FAIL'))
print('conservationContract=' + ('PASS' if cons else 'FAIL'))
print('shapeContract=VISUAL_PENDING')

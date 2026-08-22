#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: analyze_0493x10a_geometry_seal.py <cuda_phase_kinetic_crossing_0493x9z.csv>")
path=Path(sys.argv[1])
with path.open(newline='') as f: rows=list(csv.DictReader(f))
if not rows: raise SystemExit('[0493x10a-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def ratio(a,b): return a/b if b else 0.0

last=rows[-1]
interior=isum('interiorCrossings')
applied=isum('appliedReflections')
still=isum('appliedStillOutwardRelative')
preout=isum('appliedInteriorPredictedOutside')
finalout=isum('appliedInteriorFinalOutside')
seals=isum('endpointSealCorrections')
sealFallback=isum('endpointSealSampleFallbacks')
normalFallback=isum('crossingPointNormalFallbacks')
unsupported=isum('unsupportedReflections')
outer0=I(rows[0],'phaseAOuterCellParticles'); outer1=I(last,'phaseAOuterCellParticles')
deep0=I(rows[0],'deepOuterParticles'); deep1=I(last,'deepOuterParticles')
maxdp=max(maxabs('deltaPx'),maxabs('deltaPy'))
maxde=maxabs('deltaKineticEnergy')

print('===== 0493x10a CROSSING-NORMAL + ENDPOINT SEAL =====')
print(f'file={path} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- geometry ---')
print(f'interiorCrossings={interior} preSealPredictedOutside={preout}/{interior} ({ratio(preout,interior):.3%})')
print(f'endpointSealCorrections={seals} sampleFallbacks={sealFallback}')
print(f'appliedInteriorFinalOutside={finalout}/{interior} ({ratio(finalout,interior):.6%})')
print(f'crossingPointNormalFallbacks={normalFallback}')
print('--- individual velocity invariant ---')
print(f'applied={applied} stillOutwardRelative={still} unsupported={unsupported}')
print('--- halo proxies ---')
print(f'outer first={outer0} last={outer1} growth={outer1-outer0:+d}')
print(f'deepOuter first={deep0} last={deep1} growth={deep1-deep0:+d}')
print('--- unchanged x9z reaction audit ---')
print(f'max|deltaP|={maxdp:.6e} max|deltaKE|={maxde:.6e} '
      f'lastMeanLambdaDev={F(last,"reactionLambdaDeviationAbsMean"):.6e}')

geometry_ok = finalout == 0 and still == 0 and applied > 0
print(f'geometryContract={"PASS" if geometry_ok else "FAIL"}')
if not geometry_ok:
    raise SystemExit(3)

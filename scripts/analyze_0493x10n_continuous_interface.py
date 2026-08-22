#!/usr/bin/env python3
import csv
import math
import sys
from pathlib import Path

if len(sys.argv) < 2:
    raise SystemExit('usage: analyze_0493x10n_continuous_interface.py <csv> [--mode static|dripping]')
p = Path(sys.argv[1])
mode = 'unknown'
if '--mode' in sys.argv:
    k = sys.argv.index('--mode')
    if k + 1 < len(sys.argv): mode = sys.argv[k+1]
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10n-check] ERROR empty CSV')
def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def fsum(k): return sum(F(r,k) for r in rows)
def maxf(k): return max((F(r,k) for r in rows), default=0.0)

seg=isum('continuousWallSegmentsBuilt')
iface=isum('continuousWallInterfaceDualCells')
amb=isum('continuousWallAmbiguousDualCells')
inv=isum('continuousWallInvalidDualCells')
old=isum('continuousWallOldStationaryCrossingCandidates')
rel=isum('continuousWallOldStationaryCrossingReleased')
no_near=isum('continuousWallNoNearbySegment')
no_hit=isum('continuousWallCandidateNoHit')
coll=isum('continuousWallCollisions')
sec=isum('continuousWallSecondCollisions')
third=isum('continuousWallThirdCollisions')
limit=isum('continuousWallCollisionLimitReached')
mult=isum('continuousWallMultipleCollisionCandidates')
outw=isum('continuousWallRelativeStillOutward')
eref=fsum('continuousWallRelativeSpeedSqReferenceSum')
eerr=fsum('continuousWallRelativeSpeedSqAbsErrorSum')
ix=fsum('continuousWallImpulseX'); iy=fsum('continuousWallImpulseY')

last=rows[-1]
print('===== 0493x10n Q6-CONTINUOUS MOVING INTERFACE =====')
print(f'file={p} mode={mode} rows={len(rows)} lastStep={I(last,"step")}')
print('--- continuous Q6-style reconstruction ---')
print(f'interfaceDualCells={iface} segmentsBuilt={seg} ambiguous={amb} invalid={inv}')
print('--- moving segment collision path ---')
print(f'collisions={coll} second={sec} third={third} collisionLimitReached={limit} multipleCandidates={mult}')
print(f'oldStationaryCrossings={old} releasedByMovingInterface={rel} releasedFraction={(rel/old if old else 0):.6%}')
print(f'oldCrossingNoNearbySegment={no_near} oldCrossingCandidateButNoHit={no_hit}')
print(f'relativeStillOutward={outw} relativeSpeedSqRelativeError={(eerr/eref if eref else 0):.12e}')
print(f'interfaceImpulse=({ix:.9g},{iy:.9g}) absImpulseSum={fsum("continuousWallImpulseAbsSum"):.9g}')
print(f'positionShiftAbsSum={fsum("continuousWallPositionShiftAbsSum"):.9g}')
print('--- pre-wall Q6/B1 predictor retained ---')
print(f'meanVn={F(last,"preWallMeanVn"):.9g} massWeightedMeanVn=' +
      (f'{F(last,"preWallMassVnSum")/F(last,"preWallMassSum"):.9g}' if F(last,'preWallMassSum') else '0'))
if 'preWallAlphaArea' in last:
    print(f'alphaArea first/last={F(rows[0],"preWallAlphaArea"):.9g}/{F(last,"preWallAlphaArea"):.9g}')
if mode == 'dripping' and 'preWallLowerTipY' in last:
    print(f'tipY first/last={F(rows[0],"preWallLowerTipY"):.9g}/{F(last,"preWallLowerTipY"):.9g}')
geom = inv == 0 and seg > 0
collision = outw == 0 and (eerr/eref if eref else 0) < 1e-10
# A continuous reconstruction should make an old stationary crossing without
# any nearby segment exceptional. Candidate-but-no-hit can legitimately occur
# because the interface itself moves.
coverage = (no_near == 0)
print('continuousGeometryContract=' + ('PASS' if geom else 'FAIL'))
print('continuousCoverageContract=' + ('PASS' if coverage else 'FAIL'))
print('movingSegmentCollisionContract=' + ('PASS' if collision else 'FAIL'))
print('freeSurfaceImpulseFeedback=DIAGNOSTIC_ONLY_NOT_APPLIED')
print('shapeAdvanceEvaporationContract=VISUAL_REVIEW')
print('mobileSolidExtension=GENERIC_MOVING_SEGMENT_ENDPOINT_VELOCITIES_PLUS_IMPULSE')

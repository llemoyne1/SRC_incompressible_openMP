#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path

ap=argparse.ArgumentParser()
ap.add_argument('csv')
ap.add_argument('--mode', choices=('static','dripping'), default='static')
a=ap.parse_args()
p=Path(a.csv)
with p.open(newline='') as f:
    rows=list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10m-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def fsum(k): return sum(F(r,k) for r in rows)
def mx(k): return max((F(r,k) for r in rows), default=0.0)
def wmean(k,count='movingWallCollisions'):
    den=isum(count)
    return sum(F(r,k)*I(r,count) for r in rows)/den if den else 0.0

last=rows[-1]
coll=isum('movingWallCollisions')
old=isum('movingWallOldStationaryCrossingCandidates')
released=isum('movingWallOldStationaryCrossingReleased')
relerr=fsum('movingWallRelativeSpeedSqAbsErrorSum')
relref=fsum('movingWallRelativeSpeedSqReferenceSum')
relative_error=relerr/max(relref,1e-300)

print('===== 0493x10m MOVING INTERFACE WALL =====')
print(f'file={p} mode={a.mode} rows={len(rows)} lastStep={I(last,"step")}')
print('--- implicit interface object ---')
print(f'planesBuilt={isum("movingWallInterfaceCellsBuilt")} '
      f'velocityFallbacks={isum("movingWallInterfaceVelocityFallbacks")} '
      f'invalidPlanes={isum("movingWallInvalidInterfaceCells")}')
print('--- moving-wall collision path ---')
print(f'particlesWithCandidate={isum("movingWallParticlesWithCandidate")} '
      f'collisions={coll} multipleCandidates={isum("movingWallMultipleCollisionCandidates")}')
print(f'oldStationaryCrossings={old} releasedByMovingWall={released} '
      f'releasedFraction={(released/old if old else 0):.6%}')
print(f'advance/recede/stationary={isum("movingWallAdvanceCollisions")}/'
      f'{isum("movingWallRecedeCollisions")}/'
      f'{isum("movingWallStationaryCollisions")}')
print(f'meanHitFraction={wmean("movingWallMeanCollisionTimeFraction"):.9g} '
      f'meanWallVn={wmean("movingWallMeanWallVn"):.9g} '
      f'rmsWallVn={wmean("movingWallRmsWallVn"):.9g} '
      f'mean|wallVn|={wmean("movingWallMeanAbsWallVn"):.9g}')
print(f'relativeStillOutward={isum("movingWallRelativeStillOutward")} '
      f'finalRelativeOutside={isum("movingWallFinalRelativeOutside")}')
print(f'relativeSpeedSqRelativeError={relative_error:.12e}')
print(f'interfaceImpulse=({fsum("movingWallImpulseX"):.9g},'
      f'{fsum("movingWallImpulseY"):.9g}) '
      f'absImpulseSum={fsum("movingWallImpulseAbsSum"):.9g}')
print(f'positionShiftAbsSum={fsum("movingWallPositionShiftAbsSum"):.9g}')
print('--- halo context ---')
deep=[I(r,'deepOuterParticles') for r in rows]
shell=[I(r,'shellParticles') for r in rows]
outer=[I(r,'phaseAOuterCellParticles') for r in rows]
print(f'outer first/max/last={outer[0]}/{max(outer)}/{outer[-1]}')
print(f'shell first/max/last={shell[0]}/{max(shell)}/{shell[-1]}')
print(f'deepOuter first/max/last={deep[0]}/{max(deep)}/{deep[-1]}')

# x10l remains useful: compare what Q6/B1 predicts to what alpha actually did.
if 'preWallVnSum' in last:
    nvel=sum(I(r,'preWallVelocityCells') for r in rows)
    mean_vn=fsum('preWallVnSum')/nvel if nvel else 0.0
    mt=fsum('preWallVelocityMassSum')
    mw=fsum('preWallMassVnSum')/mt if mt else 0.0
    print('--- pre-wall Q6/B1 predictor retained ---')
    print(f'meanVn={mean_vn:.9g} massWeightedMeanVn={mw:.9g}')
    print(f'alphaArea first/last={F(rows[0],"preWallAlphaArea"):.9g}/'
          f'{F(last,"preWallAlphaArea"):.9g}')
    if a.mode=='dripping':
        print(f'tipY first/last={F(rows[0],"preWallLowerTipY"):.9g}/'
              f'{F(last,"preWallLowerTipY"):.9g}')

path_ok=(isum('receiverCorrectedParticles')==0 and
         isum('reactionActiveCells')==0 and
         isum('mesoReactionActiveReservoirs')==0)
geom_ok=(isum('movingWallInvalidInterfaceCells')==0)
collision_ok=(isum('movingWallRelativeStillOutward')==0 and
              isum('movingWallFinalRelativeOutside')==0 and
              relative_error < 1e-10)
print('movingWallPathContract=' + ('PASS' if path_ok else 'FAIL'))
print('movingWallGeometryContract=' + ('PASS' if geom_ok else 'REVIEW'))
print('movingWallCollisionContract=' + ('PASS' if collision_ok else 'FAIL'))
print('freeSurfaceImpulseFeedback=DIAGNOSTIC_ONLY_NOT_APPLIED')
print('shapeAndAdvanceContract=VISUAL_AND_ALPHA_MOTION_REVIEW')
print('mobileSolidExtension=PRIMITIVE_READY_PLANE_VELOCITY_PLUS_IMPULSE')

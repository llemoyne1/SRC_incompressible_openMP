#!/usr/bin/env python3
import argparse, csv, math
from pathlib import Path

ap=argparse.ArgumentParser()
ap.add_argument('csv')
ap.add_argument('--mode',choices=('static','dripping'),required=True)
a=ap.parse_args()
p=Path(a.csv)
with p.open(newline='') as f: rows=list(csv.DictReader(f))
if not rows: raise SystemExit('[0493x10o-check] ERROR empty CSV')

def F(r,k): return float(r.get(k,0) or 0)
def I(r,k): return int(float(r.get(k,0) or 0))
def isum(k): return sum(I(r,k) for r in rows)
def mx(k): return max((F(r,k) for r in rows), default=0.0)
def wmean(k,count):
    den=sum(I(r,count) for r in rows)
    return sum(F(r,k)*I(r,count) for r in rows)/den if den else 0.0

last=rows[-1]
coll=isum('continuousWallCollisions')
endpoints=isum('q6ThermalInterfaceEndpointSamples')
fallback=isum('q6ThermalHydroFallbacks')
no_seg=isum('continuousWallNoNearbySegment')
rel_out=isum('continuousWallRelativeStillOutward')
limit=isum('continuousWallCollisionLimitReached')
mean_vn=wmean('q6ThermalMeanHydroVn','q6ThermalInterfaceEndpointSamples')
rms_vn=math.sqrt(max(0.0, sum((F(r,'q6ThermalRmsHydroVn')**2)*I(r,'q6ThermalInterfaceEndpointSamples') for r in rows)/endpoints)) if endpoints else 0.0
mean_abs=wmean('q6ThermalMeanAbsHydroVn','q6ThermalInterfaceEndpointSamples')
mean_delta=wmean('q6ThermalMeanThickness','q6ThermalInterfaceEndpointSamples')
rel_err=max((F(r,'continuousWallRelativeSpeedSqAbsErrorSum')/(F(r,'continuousWallRelativeSpeedSqReferenceSum')+1e-300) for r in rows), default=0.0)

print('===== 0493x10o Q6 HYDRO + THERMAL INTERFACE WALL =====')
print(f'file={p} mode={a.mode} rows={len(rows)} lastStep={I(last,"step")}')
print('--- Q6 hydrodynamic interface kinematics ---')
print(f'endpointSamples={endpoints} hydroFallbacks={fallback}')
print(f'meanHydroVn={mean_vn:.9g} rmsHydroVn={rms_vn:.9g} mean|HydroVn|={mean_abs:.9g}')
print(f'meanThermalThickness={mean_delta:.9g}')
print('--- continuous thermal-envelope collision ---')
print(f'collisions={coll} second={isum("continuousWallSecondCollisions")} third={isum("continuousWallThirdCollisions")} limitReached={limit}')
print(f'oldStationaryCrossings={isum("continuousWallOldStationaryCrossingCandidates")} released={isum("continuousWallOldStationaryCrossingReleased")}')
print(f'noNearbySegment={no_seg} candidateButNoHit={isum("continuousWallCandidateNoHit")} relativeStillOutward={rel_out}')
print(f'maxRelativeSpeedSqRelativeError={rel_err:.12e}')
print('--- alpha motion predictor context ---')
print(f'preWallMeanVn(last)={F(last,"preWallVnSum")/max(1,I(last,"preWallVelocityCells")):.9g}')
print(f'alphaArea(last)={F(last,"preWallAlphaArea"):.9g} tipY(last)={F(last,"preWallLowerTipY"):.9g}')

geom = no_seg == 0
hydro = endpoints > 0 and fallback == 0
coll_ok = rel_out == 0 and rel_err < 1e-10
print('q6HydroFieldContract=' + ('PASS' if hydro else 'FAIL'))
print('thermalContinuousGeometryContract=' + ('PASS' if geom else 'FAIL'))
print('thermalMovingWallCollisionContract=' + ('PASS' if coll_ok else 'FAIL'))
print('freeSurfaceImpulseFeedback=DIAGNOSTIC_ONLY_NOT_APPLIED')
print('shapeAdvanceEvaporationContract=VISUAL_REVIEW')
print('mobileSolidExtension=GENERIC_MOVING_SEGMENT_PRIMITIVE_RETAINED')

#!/usr/bin/env python3
"""Analyze 0493x9f ellipse-relaxation diagnostics (stdlib only)."""
import argparse, csv, json, math
from pathlib import Path

def rows(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f))

def f(row, key): return float(row[key])
def i(row, key): return int(float(row[key]))
def mean(vals): return sum(vals)/len(vals) if vals else 0.0

def stdev(vals):
    if len(vals) < 2: return 0.0
    m=mean(vals)
    return math.sqrt(sum((x-m)*(x-m) for x in vals)/(len(vals)-1))

ap=argparse.ArgumentParser()
ap.add_argument('--pressure', required=True)
ap.add_argument('--velocity', required=True)
ap.add_argument('--shape', required=True)
ap.add_argument('--json', required=True)
ap.add_argument('--center-x', type=float, required=True)
ap.add_argument('--center-y', type=float, required=True)
ap.add_argument('--initial-rx', type=float, required=True)
ap.add_argument('--initial-ry', type=float, required=True)
ap.add_argument('--tail-fraction', type=float, default=0.5)
a=ap.parse_args()
P=rows(a.pressure); V=rows(a.velocity); S=rows(a.shape)
if not P or not V or not S:
    raise SystemExit('[0493x9f-analysis] missing pressure/velocity/shape rows')
p=P[-1]; v=V[-1]; s=S[-1]
steps_common=sorted(set(i(r,'step') for r in P) & set(i(r,'step') for r in V) & set(i(r,'step') for r in S))
if not steps_common: raise SystemExit('[0493x9f-analysis] no common steps')
last=steps_common[-1]
p=next(r for r in reversed(P) if i(r,'step')==last)
v=next(r for r in reversed(V) if i(r,'step')==last)
s=next(r for r in reversed(S) if i(r,'step')==last)
frac=min(1.0,max(0.05,a.tail_fraction)); n=max(1,int(math.ceil(len(steps_common)*frac)))
tail_steps=set(steps_common[-n:])
PT=[r for r in P if i(r,'step') in tail_steps]
VT=[r for r in V if i(r,'step') in tail_steps]
ST=[r for r in S if i(r,'step') in tail_steps]
rx0=max(a.initial_rx,a.initial_ry); ry0=min(a.initial_rx,a.initial_ry)
reff0=math.sqrt(a.initial_rx*a.initial_ry)
xcm=f(s,'xCM'); ycm=f(s,'yCM'); dcm=math.hypot(xcm-a.center_x,ycm-a.center_y)
rmaj=f(s,'momentRadiusMajor'); rmin=f(s,'momentRadiusMinor')
ratio=f(s,'axisRatio'); ell=f(s,'ellipticity')
rintmin=f(s,'interfaceRadiusMin'); rintmax=f(s,'interfaceRadiusMax')
report={
    'status':'PASS-structural','step':last,'time':f(s,'time'),'sigma':f(p,'sigma'),
    'initialCenter':[a.center_x,a.center_y], 'particleCenterOfMass':[xcm,ycm],
    'particleCenterDisplacement':dcm,
    'secondMoment':{'Mxx':f(s,'Mxx'),'Mxy':f(s,'Mxy'),'Myy':f(s,'Myy')},
    'principalEigenvalues':[f(s,'lambdaMajor'),f(s,'lambdaMinor')],
    'momentRadiusMajor':rmaj,'momentRadiusMinor':rmin,'axisRatio':ratio,
    'ellipticity':ell,'principalAngleDeg':f(s,'principalAngleDeg'),
    'interfaceRadiusMin':rintmin,'interfaceRadiusMax':rintmax,
    'interfaceRadiusMean':f(s,'interfaceRadiusMean'),'interfaceRadiusStd':f(s,'interfaceRadiusStd'),
    'interfaceRadialSpan':f(s,'interfaceRadialSpan'),
    'effectiveRadius':f(p,'effectiveRadius'),
    'initialRadii':[rx0,ry0],'initialEffectiveRadius':reff0,
    'majorRadiusChangeFromInitial':rmaj-rx0,
    'minorRadiusChangeFromInitial':rmin-ry0,
    'interfaceSpeedRmsTrueBand':f(v,'interfaceSpeedRms'),
    'interfaceCellsTrueBand':i(v,'interfaceCells'),
    'liquidSpeedRms':f(v,'liquidSpeedRms'),
    'tailRows':len(ST),
    'tailMomentRadiusMajorMean':mean([f(r,'momentRadiusMajor') for r in ST]),
    'tailMomentRadiusMajorStd':stdev([f(r,'momentRadiusMajor') for r in ST]),
    'tailMomentRadiusMinorMean':mean([f(r,'momentRadiusMinor') for r in ST]),
    'tailMomentRadiusMinorStd':stdev([f(r,'momentRadiusMinor') for r in ST]),
    'tailAxisRatioMean':mean([f(r,'axisRatio') for r in ST]),
    'tailEllipticityMean':mean([f(r,'ellipticity') for r in ST]),
    'tailInterfaceRadiusMaxMean':mean([f(r,'interfaceRadiusMax') for r in ST]),
    'tailInterfaceRadiusMinMean':mean([f(r,'interfaceRadiusMin') for r in ST]),
    'tailCenterDisplacementMean':mean([math.hypot(f(r,'xCM')-a.center_x,f(r,'yCM')-a.center_y) for r in ST]),
    'tailInterfaceSpeedRmsTrueBandMean':mean([f(r,'interfaceSpeedRms') for r in VT]),
    'tailEffectiveRadiusMean':mean([f(r,'effectiveRadius') for r in PT]),
    'shapeDefinition':'mass-weighted liquid-particle second moment; radii=2*sqrt(covariance eigenvalues)',
    'interfaceBandDefinition':'cell adjacent to >=1 face straddling physical x6c alpha=0.5',
    'interfaceRadiusDefinition':'alpha=0.5 crossing-point distance from particle COM',
}
Path(a.json).write_text(json.dumps(report,indent=2)+'\n')
print('[0493x9f-analysis] status=PASS-structural '
      f"step={last} sigma={report['sigma']:.8g} xCM={xcm:.8g} yCM={ycm:.8g} dCM={dcm:.3e} Reff={report['effectiveRadius']:.8g}")
print('[0493x9f-analysis] '
      f"momentRadii(major,minor)=({rmaj:.8g},{rmin:.8g}) axisRatio={ratio:.6g} ellipticity={ell:.6g} angleDeg={report['principalAngleDeg']:.5g}")
print('[0493x9f-analysis] '
      f"interfaceRadii(min,max)=({rintmin:.8g},{rintmax:.8g}) span={report['interfaceRadialSpan']:.8g} "
      f"trueBandCells={report['interfaceCellsTrueBand']} uIntRms={report['interfaceSpeedRmsTrueBand']:.6g}")
print('[0493x9f-analysis] '
      f"tail{len(ST)} major={report['tailMomentRadiusMajorMean']:.8g}±{report['tailMomentRadiusMajorStd']:.3g} "
      f"minor={report['tailMomentRadiusMinorMean']:.8g}±{report['tailMomentRadiusMinorStd']:.3g} "
      f"ratio={report['tailAxisRatioMean']:.6g} ell={report['tailEllipticityMean']:.6g} "
      f"RmaxIface={report['tailInterfaceRadiusMaxMean']:.8g} RminIface={report['tailInterfaceRadiusMinMean']:.8g}")
print(f'[0493x9f-analysis] report={a.json}')

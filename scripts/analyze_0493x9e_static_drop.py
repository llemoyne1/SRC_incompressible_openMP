#!/usr/bin/env python3
"""Analyze 0493x9e static-drop pressure/velocity/resultant diagnostics."""
import argparse, csv, json, math
from pathlib import Path

def rows(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f))

def f(row, key): return float(row[key])
def i(row, key): return int(float(row[key]))

def mean(vals): return sum(vals)/len(vals) if vals else 0.0

ap=argparse.ArgumentParser()
ap.add_argument('--pressure', required=True)
ap.add_argument('--velocity', required=True)
ap.add_argument('--species', required=True)
ap.add_argument('--json', required=True)
ap.add_argument('--liquid-type', type=int, default=1)
ap.add_argument('--tail-fraction', type=float, default=0.5)
a=ap.parse_args()
P=rows(a.pressure); V=rows(a.velocity); S=rows(a.species)
if not P or not V: raise SystemExit('[0493x9e-analysis] missing diagnostic rows')
p=P[-1]; v=V[-1]
liq=[r for r in S if int(float(r.get('type','-1'))) == a.liquid_type]
sl=max(liq, key=lambda r:int(float(r['step']))) if liq else None
sigma=f(p,'sigma'); reff=f(p,'effectiveRadius'); dp=f(p,'measuredPressureJump'); target=f(p,'laplaceTargetCurrent')
rel_dp=(dp-target)/target if abs(target)>0 else None
kmean=f(p,'curvatureMean'); keq=f(p,'equivalentCurvature')
rel_k=(kmean-keq)/keq if abs(keq)>0 else None
comx=float(sl['meanVx']) if sl else 0.0
comy=float(sl['meanVy']) if sl else 0.0
com=math.hypot(comx,comy)
frac=min(1.0,max(0.05,a.tail_fraction)); n=max(1,int(math.ceil(len(P)*frac))); PT=P[-n:]
steps={i(r,'step') for r in PT}; VT=[r for r in V if i(r,'step') in steps]
report={
 'status':'PASS-structural', 'rowsPressure':len(P), 'rowsVelocity':len(V),
 'step':i(p,'step'), 'time':f(p,'time'), 'sigma':sigma,
 'effectiveRadius':reff, 'equivalentCurvature':keq,
 'curvatureMean':kmean, 'curvatureRelativeError':rel_k,
 'liquidProjectionPressureGaugeMean':f(p,'liquidProjectionPressureGaugeMean'),
 'gasEosPressureGaugeMean':f(p,'gasEosPressureGaugeMean'),
 'measuredPressureJump':dp, 'laplaceTargetCurrent':target,
 'pressureJumpRelativeError':rel_dp,
 'deepLiquidCells':i(p,'deepLiquidCells'), 'deepGasCells':i(p,'deepGasCells'),
 'normalizedDiscreteResultant':f(p,'normalizedDiscreteResultant'),
 'capillaryResultantNorm':f(p,'capillaryResultantNorm'),
 'liquidSpeedRmsPostQ6':f(v,'liquidSpeedRms'), 'liquidSpeedMaxPostQ6':f(v,'liquidSpeedMax'),
 'coreSpeedRmsPostQ6':f(v,'coreSpeedRms'), 'coreSpeedMaxPostQ6':f(v,'coreSpeedMax'),
 'interfaceSpeedRmsPostQ6':f(v,'interfaceSpeedRms'), 'interfaceSpeedMaxPostQ6':f(v,'interfaceSpeedMax'),
 'liquidMeanVelocityPostQ6':[f(v,'liquidMeanVx'),f(v,'liquidMeanVy')],
 'particleCOMMeanVelocity':[comx,comy], 'particleCOMSpeed':com,
 'tailRows':n,
 'tailMeasuredPressureJumpMean':mean([f(r,'measuredPressureJump') for r in PT]),
 'tailLaplaceTargetMean':mean([f(r,'laplaceTargetCurrent') for r in PT]),
 'tailNormalizedDiscreteResultantMean':mean([f(r,'normalizedDiscreteResultant') for r in PT]),
 'tailLiquidSpeedRmsMean':mean([f(r,'liquidSpeedRms') for r in VT]),
 'tailInterfaceSpeedRmsMean':mean([f(r,'interfaceSpeedRms') for r in VT]),
 'pressureDefinition':'Q6 projection gauge rho_liquid_ref*phi/dt minus x6g gas EOS gauge',
 'velocityDefinition':'post-Q6/B1 cell-mean velocity before streaming/collision',
}
Path(a.json).write_text(json.dumps(report,indent=2)+'\n')
err='n/a' if rel_dp is None else f'{100*rel_dp:.3f}%'
kerr='n/a' if rel_k is None else f'{100*rel_k:.3f}%'
print('[0493x9e-analysis] status=PASS-structural '
      f"step={report['step']} sigma={sigma:.8g} Reff={reff:.8g} "
      f"kMean={kmean:.8g} kEq={keq:.8g} kErr={kerr} "
      f"dPmeas={dp:.8g} dPLaplace={target:.8g} dPErr={err}")
print('[0493x9e-analysis] '
      f"uRms(liq/core/int)=({f(v,'liquidSpeedRms'):.6g},{f(v,'coreSpeedRms'):.6g},{f(v,'interfaceSpeedRms'):.6g}) "
      f"uMax(liq/core/int)=({f(v,'liquidSpeedMax'):.6g},{f(v,'coreSpeedMax'):.6g},{f(v,'interfaceSpeedMax'):.6g}) "
      f"forceResidual={f(p,'normalizedDiscreteResultant'):.6g} "
      f"COM=({comx:.3e},{comy:.3e}) |COM|={com:.3e}")
print('[0493x9e-analysis] '
      f"tail{n} dPmean={report['tailMeasuredPressureJumpMean']:.8g} "
      f"targetMean={report['tailLaplaceTargetMean']:.8g} "
      f"uRmsMean={report['tailLiquidSpeedRmsMean']:.6g} "
      f"uIntRmsMean={report['tailInterfaceSpeedRmsMean']:.6g}")
print(f'[0493x9e-analysis] report={a.json}')

#!/usr/bin/env python3
"""Characterize x16m residual deformable-wall penetration versus wall motion rate.
Stdlib only; no pandas. MPCD dt is fixed. Prescribed deformation period is multiplied
by 1,2,4 while the number of deformation cycles is held fixed.
"""
from __future__ import annotations
import csv, math, re, statistics, sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('runs/0493x16m_wall_motion_rate_characterization')
FACTORS=(1,2,4)

def read_csv(p: Path):
    with p.open(newline='') as f: return list(csv.DictReader(f))
def fl(r,k): return float(r[k])
def it(r,k): return int(float(r[k]))
def rms(v): return math.sqrt(sum(x*x for x in v)/max(1,len(v)))
def percentile(vals,q):
    if not vals: return 0.0
    a=sorted(vals)
    x=(len(a)-1)*q
    i=int(math.floor(x)); j=min(i+1,len(a)-1); t=x-i
    return a[i]*(1-t)+a[j]*t

def parse_meta(p: Path):
    d={}
    if p.is_file():
        for line in p.read_text().splitlines():
            if '=' in line:
                k,v=line.split('=',1); d[k.strip()]=v.strip()
    return d

def elapsed_seconds(case: Path):
    files=list((case/'fresh'/'logs').glob('*.time'))
    if not files: return float('nan')
    text=files[0].read_text(errors='replace')
    m=re.search(r'elapsed=([0-9]+(?:\.[0-9]+)?)',text)
    if m: return float(m.group(1))
    m=re.search(r'([0-9]+(?:\.[0-9]+)?)',text)
    return float(m.group(1)) if m else float('nan')

def one(factor):
    case=ROOT/f'rate_x{factor}'
    out=case/'fresh'/'output'
    P=read_csv(out/'chi_penetration_0493x16l.csv')
    K=read_csv(out/'chi_kinetic_boundary_0493x16j.csv')
    meta=parse_meta(case/'fresh'/'run_meta_0493x16j.txt')
    if not P or not K: raise SystemExit(f'[0493x16m-char] empty CSV factor={factor}')
    period=int(float(meta.get('deformPeriodSteps','0')))
    amp=float(meta.get('deformAmplitudeCells','nan'))
    dt=float(meta.get('dt','nan')) if 'dt' in meta else None
    # dt is not in run_meta in older runners; recover from penetration times.
    if not dt or not math.isfinite(dt):
        if len(P)>=2: dt=fl(P[1],'time')-fl(P[0],'time')
        else: dt=fl(P[0],'time')/max(1,it(P[0],'step'))
    pos=[r for r in P if it(r,'strictInsideParticles')>0]
    depths=[fl(r,'maxPenetrationCells') for r in pos]
    strict_samples=sum(it(r,'strictInsideParticles') for r in P)
    raw_samples=sum(it(r,'rawInsideParticles') for r in P)
    top=sorted(pos,key=lambda r:fl(r,'maxPenetrationCells'),reverse=True)[:5]
    top_desc=[]
    for r in top:
        s=it(r,'step'); phase=(s % period)/period if period else float('nan')
        top_desc.append((s,fl(r,'time'),fl(r,'maxPenetrationCells'),phase,abs(math.cos(2*math.pi*phase))))
    cut=0.5*(it(K[0],'step')+it(K[-1],'step'))
    Ks=[r for r in K if it(r,'step')>=cut]
    elapsed=elapsed_seconds(case)
    max_shift=2.0*amp*math.sin(math.pi/period) if period else float('nan')
    cycles=len(P)/period if period else float('nan')
    return dict(factor=factor,period=period,steps=len(P),dt=dt,amp=amp,maxShift=max_shift,cycles=cycles,
                badSteps=len(pos),badFraction=len(pos)/len(P),strictSamples=strict_samples,rawSamples=raw_samples,
                maxPen=max(depths,default=0.0),medianPen=statistics.median(depths) if depths else 0.0,
                p95Pen=percentile(depths,0.95),gt1e4=sum(d>1e-4 for d in depths),gt1e3=sum(d>1e-3 for d in depths),
                gt1e2=sum(d>1e-2 for d in depths),maxStrict=max(it(r,'strictInsideParticles') for r in P),
                maxFlat=max(it(r,'flatGradientInsideParticles') for r in P),maxQ2Invalid=max(it(r,'q2InvalidParticles') for r in P),
                maxOrphan=max(it(r,'orphanNoSegment') for r in K),meanColl=sum(fl(r,'collisions') for r in Ks)/len(Ks),
                impulseRms=rms([fl(r,'wallImpulseX') for r in Ks]),elapsed=elapsed,top=top_desc)

M=[one(f) for f in FACTORS]

def ratio(a,b): return a/b if b>0 else float('inf') if a>0 else 1.0
def slope(ea,eb):
    if ea>0 and eb>0: return math.log(ea/eb,2.0)
    if ea>0 and eb==0: return float('inf')
    return float('nan')

E=[m['maxPen'] for m in M]
sl12=slope(E[0],E[1]); sl24=slope(E[1],E[2])
monotone=(E[1] <= E[0] and E[2] <= E[1])
resolved=(M[-1]['maxStrict']==0 and E[-1] <= 1e-4)
strong=(monotone and E[1] <= 0.6*E[0] and E[2] <= 0.6*E[1])
if resolved:
    interpretation='RESOLVED_AT_SLOW_WALL_MOTION'
elif strong:
    interpretation='CLEAR_WALL_MOTION_RATE_DEPENDENCE'
elif not monotone or (E[-1] >= 0.5*E[0] if E[0]>0 else False):
    interpretation='WEAK_OR_NONMONOTONE_RATE_DEPENDENCE'
else:
    interpretation='MIXED_RATE_DEPENDENCE'

lines=[
 '0493x16m deformable-wall motion-rate characterization',
 'fluidDtChanged=false',
 'fluidCollisionIntervalChanged=false',
 'deformationAmplitudeChanged=false',
 'deformationCyclesHeldApproximatelyConstant=true',
 f'interpretation={interpretation}',
 f'maxPenetrationMonotone={str(monotone).lower()}',
 f'maxPenetrationSlope_factor1_to_2={sl12}',
 f'maxPenetrationSlope_factor2_to_4={sl24}',
]
for m in M:
    lines += ['',f'[rate_x{m["factor"]}]',f'periodSteps={m["period"]}',f'steps={m["steps"]}',
              f'dt={m["dt"]:.17g}',f'cyclesObserved={m["cycles"]:.17g}',
              f'maxDeformationShiftCellsPerStep={m["maxShift"]:.17g}',
              f'badSteps={m["badSteps"]}',f'badStepFraction={m["badFraction"]:.17g}',
              f'rawInsideParticleSamples={m["rawSamples"]}',f'strictInsideParticleSamples={m["strictSamples"]}',
              f'maxStrictInsideParticles={m["maxStrict"]}',f'maxPenetrationCells={m["maxPen"]:.17g}',
              f'medianPositivePenetrationCells={m["medianPen"]:.17g}',f'p95PositivePenetrationCells={m["p95Pen"]:.17g}',
              f'positiveEventsGt1e-4={m["gt1e4"]}',f'positiveEventsGt1e-3={m["gt1e3"]}',f'positiveEventsGt1e-2={m["gt1e2"]}',
              f'maxFlatGradientInsideParticles={m["maxFlat"]}',f'maxQ2InvalidParticles={m["maxQ2Invalid"]}',
              f'maxOrphanNoSegment={m["maxOrphan"]}',f'secondHalfMeanCollisions={m["meanColl"]:.17g}',
              f'secondHalfImpulseRmsX={m["impulseRms"]:.17g}',f'elapsedSeconds={m["elapsed"]:.17g}']
    for j,(s,t,d,ph,c) in enumerate(m['top'],1):
        lines.append(f'top{j}=step:{s},time:{t:.17g},depthCells:{d:.17g},cyclePhase:{ph:.17g},absCosPhase:{c:.17g}')

analysis=ROOT/'analysis'; analysis.mkdir(parents=True,exist_ok=True)
out=analysis/'summary_0493x16m_wall_motion_rate.txt'; out.write_text('\n'.join(lines)+'\n')
with (analysis/'metrics_0493x16m_wall_motion_rate.csv').open('w',newline='') as f:
    w=csv.writer(f); w.writerow(['factor','periodSteps','steps','dt','cycles','maxDeformationShiftCellsPerStep','badSteps','badStepFraction','strictInsideParticleSamples','maxStrictInsideParticles','maxPenetrationCells','p95PositivePenetrationCells','eventsGt1e-4','eventsGt1e-3','eventsGt1e-2','meanCollisionsSecondHalf','impulseRmsXSecondHalf','elapsedSeconds'])
    for m in M:
        w.writerow([m['factor'],m['period'],m['steps'],m['dt'],m['cycles'],m['maxShift'],m['badSteps'],m['badFraction'],m['strictSamples'],m['maxStrict'],m['maxPen'],m['p95Pen'],m['gt1e4'],m['gt1e3'],m['gt1e2'],m['meanColl'],m['impulseRms'],m['elapsed']])
print(out.read_text(),end='')

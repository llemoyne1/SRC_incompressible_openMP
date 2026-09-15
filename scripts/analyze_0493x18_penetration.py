#!/usr/bin/env python3
"""0493x18 penetration / possible-through-crossing audit.

Stdlib only.  This analyzer is observation-only and works on existing x18a/x18b
runs.  It combines:
  - x16l post-stream closed-loop penetration audit,
  - x17a kinetic collision multiplicity audit,
  - x18a hinged-body kinematics.

Important limitation: the current production diagnostics do NOT keep per-particle
pre/post trajectory identities.  Therefore a particle that would cross the whole
solid and finish outside again is not directly counted as a through-crossing by
x16l.  Collision multiplicity (second/third collisions) is reported as a risk
indicator, not as proof of a through-crossing.
"""
import argparse
import csv
import math
from pathlib import Path
from statistics import median


def fv(row, key, default=0.0):
    try:
        v=row.get(key, '')
        return float(v) if v not in ('', None) else float(default)
    except (TypeError, ValueError):
        return float(default)


def iv(row, key, default=0):
    try:
        v=row.get(key, '')
        return int(float(v)) if v not in ('', None) else int(default)
    except (TypeError, ValueError):
        return int(default)


def read_rows(path):
    if not path.exists():
        return []
    with path.open(newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def read_meta(path):
    d={}
    if not path.exists(): return d
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            k,v=line.split('=',1); d[k.strip()]=v.strip()
    return d


def resolve(root):
    root=root.resolve()
    for run in (root, root/'fresh'):
        out=run/'output'
        if (out/'chi_penetration_0493x16l.csv').exists():
            return run,out
    raise FileNotFoundError(
        f"cannot find output/chi_penetration_0493x16l.csv under {root} or {root/'fresh'}")


def by_step(rows):
    return {iv(r,'step'):r for r in rows}


def nearest_step_row(index, step):
    if not index: return None
    if step in index: return index[step]
    keys=sorted(index)
    # diagnostics have modest cadence; linear fallback is fine and deterministic
    k=min(keys, key=lambda x: abs(x-step))
    return index[k]


def classify(max_strict, max_frac, max_depth, steps_strict, n_samples,
             few_count, few_fraction, few_depth):
    if max_strict == 0 and max_depth <= 1.0e-6:
        return 'CLEAN'
    allowed_affected=max(1, int(math.ceil(0.10*max(1,n_samples))))
    if (max_strict <= few_count and max_frac <= few_fraction and
            max_depth <= few_depth and steps_strict <= allowed_affected):
        return 'SPARSE_FEW_PARTICLES'
    return 'PENETRATION_PRESENT'


def analyze(root, few_count=10, few_fraction=1e-5, few_depth=0.25):
    run,out=resolve(Path(root))
    pen=read_rows(out/'chi_penetration_0493x16l.csv')
    kin=read_rows(out/'chi_kinetic_boundary_0493x16j.csv')
    dyn=read_rows(out/'chi_hinged_plate_0493x18a.csv')
    if not pen:
        raise RuntimeError('empty penetration diagnostic')

    kidx=by_step(kin); didx=by_step(dyn)
    sampled=[iv(r,'sampledParticles') for r in pen]
    raw=[iv(r,'rawInsideParticles') for r in pen]
    strict=[iv(r,'strictInsideParticles') for r in pen]
    depth=[fv(r,'maxPenetrationCells') for r in pen]
    q2bad=[iv(r,'q2InvalidParticles') for r in pen]
    flat=[iv(r,'flatGradientInsideParticles') for r in pen]
    steps=[iv(r,'step') for r in pen]
    times=[fv(r,'time') for r in pen]
    raw_frac=[r/max(1,n) for r,n in zip(raw,sampled)]
    strict_frac=[s/max(1,n) for s,n in zip(strict,sampled)]
    nz=[i for i,s in enumerate(strict) if s>0]
    raw_nz=[i for i,s in enumerate(raw) if s>0]
    worst=max(range(len(pen)), key=lambda i:(strict[i],depth[i],raw[i]))

    cadence=[]
    for a,b in zip(steps[:-1],steps[1:]):
        if b>a: cadence.append(b-a)

    coverage_min=min(sampled); coverage_max=max(sampled)
    coverage_constant=(coverage_min==coverage_max and coverage_min>0)
    max_strict=max(strict); max_depth=max(depth); max_frac=max(strict_frac)
    status=classify(max_strict,max_frac,max_depth,len(nz),len(pen),
                    few_count,few_fraction,few_depth)

    total_coll=sum(iv(r,'collisions') for r in kin)
    total_second=sum(iv(r,'secondCollisions') for r in kin)
    total_third=sum(iv(r,'thirdCollisions') for r in kin)
    kin_third_steps=sum(1 for r in kin if iv(r,'thirdCollisions')>0)
    violation_with_third=0
    for i in nz:
        kr=nearest_step_row(kidx,steps[i])
        if kr is not None and iv(kr,'thirdCollisions')>0:
            violation_with_third += 1

    wr=pen[worst]
    wstep=steps[worst]
    kd=nearest_step_row(kidx,wstep); dd=nearest_step_row(didx,wstep)

    meta18a=read_meta(run/'run_meta_0493x18a_hinged_plate.txt')
    meta18b=read_meta(run/'run_meta_0493x18b_hinged_fall.txt')
    meta={**meta18a,**meta18b}

    result={
        'run':str(run),
        'classification':status,
        'samples':len(pen),
        'medianDiagnosticCadenceSteps':median(cadence) if cadence else 0,
        'minSampledParticles':coverage_min,
        'maxSampledParticles':coverage_max,
        'particleCoverageConstant':coverage_constant,
        'maxRawInsideParticles':max(raw),
        'maxStrictInsideParticles':max_strict,
        'maxRawInsideFraction':max(raw_frac),
        'maxStrictInsideFraction':max_frac,
        'samplesWithRawInside':len(raw_nz),
        'samplesWithStrictInside':len(nz),
        'strictAffectedSampleFraction':len(nz)/max(1,len(pen)),
        'sumStrictParticleSamples':sum(strict),
        'maxPenetrationCells':max_depth,
        'maxQ2InvalidParticles':max(q2bad),
        'maxFlatGradientInsideParticles':max(flat),
        'firstStrictStep':steps[nz[0]] if nz else -1,
        'firstStrictTime':times[nz[0]] if nz else math.nan,
        'lastStrictStep':steps[nz[-1]] if nz else -1,
        'lastStrictTime':times[nz[-1]] if nz else math.nan,
        'worstStep':wstep,
        'worstTime':times[worst],
        'worstStrictInsideParticles':strict[worst],
        'worstRawInsideParticles':raw[worst],
        'worstPenetrationCells':depth[worst],
        'worstThetaDeg':fv(dd,'thetaDeg',math.nan) if dd else math.nan,
        'worstOmega':fv(dd,'omegaAfter',math.nan) if dd else math.nan,
        'worstCollisions':iv(kd,'collisions') if kd else -1,
        'worstSecondCollisions':iv(kd,'secondCollisions') if kd else -1,
        'worstThirdCollisions':iv(kd,'thirdCollisions') if kd else -1,
        'totalKineticCollisionsAtAuditSamples':total_coll,
        'totalSecondCollisionsAtAuditSamples':total_second,
        'totalThirdCollisionsAtAuditSamples':total_third,
        'auditSamplesWithThirdCollisions':kin_third_steps,
        'penetrationSamplesWithThirdCollisions':violation_with_third,
        'fluidRegimeLabel':meta.get('fluidRegimeLabel',''),
        'fluidDensityFactor':meta.get('fluidDensityFactor',''),
        'rho2D':meta.get('rho2D',''),
        'flowUx':meta.get('flowUx',''),
        'initialAngleDeg':meta.get('initialAngleDeg',''),
    }

    # Event rows: only samples with strict penetration, sorted chronologically.
    events=[]
    for i in nz:
        st=steps[i]; kr=nearest_step_row(kidx,st); dr=nearest_step_row(didx,st)
        events.append({
            'step':st,'time':times[i],
            'sampledParticles':sampled[i],
            'rawInsideParticles':raw[i],
            'strictInsideParticles':strict[i],
            'strictInsideFraction':strict_frac[i],
            'maxPenetrationCells':depth[i],
            'thetaDeg':fv(dr,'thetaDeg',math.nan) if dr else math.nan,
            'omegaAfter':fv(dr,'omegaAfter',math.nan) if dr else math.nan,
            'collisions':iv(kr,'collisions',-1) if kr else -1,
            'secondCollisions':iv(kr,'secondCollisions',-1) if kr else -1,
            'thirdCollisions':iv(kr,'thirdCollisions',-1) if kr else -1,
            'wallImpulseX':fv(kr,'wallImpulseX',math.nan) if kr else math.nan,
            'wallImpulseY':fv(kr,'wallImpulseY',math.nan) if kr else math.nan,
        })
    return run,result,events


def write_outputs(run,result,events,top_events):
    analysis=run.parent/'analysis' if run.name=='fresh' else run/'analysis'
    analysis.mkdir(parents=True,exist_ok=True)
    summary=analysis/'summary_0493x18_penetration.txt'
    lines=['0493x18 hinged-solid penetration / crossing audit']
    for k,v in result.items(): lines.append(f'{k}={v}')
    lines += ['', '[interpretation]',
              'x16lMeasure=closed-loop-parity+nearest-edge-depth (post-stream)',
              'directThroughCrossingCounter=NOT_AVAILABLE',
              'crossingRiskProxy=second/third x17a collision multiplicity only',
              'note=sumStrictParticleSamples counts particle-sample occurrences, not unique particle IDs']
    if events:
        lines += ['', '[strict_penetration_events]']
        ranked=sorted(events,key=lambda r:(r['strictInsideParticles'],r['maxPenetrationCells']),reverse=True)[:top_events]
        for e in ranked:
            lines.append(' '.join(f'{k}={v}' for k,v in e.items()))
    summary.write_text('\n'.join(lines)+'\n',encoding='utf-8')

    evpath=analysis/'penetration_events_0493x18.csv'
    fields=['step','time','sampledParticles','rawInsideParticles','strictInsideParticles',
            'strictInsideFraction','maxPenetrationCells','thetaDeg','omegaAfter',
            'collisions','secondCollisions','thirdCollisions','wallImpulseX','wallImpulseY']
    with evpath.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(events)
    return summary,evpath,lines


def main():
    ap=argparse.ArgumentParser(description='Detailed x18a/x18b penetration and crossing-risk audit')
    ap.add_argument('--root',required=True,help='run root, with or without /fresh')
    ap.add_argument('--few-count',type=int,default=10,
                    help='descriptive SPARSE threshold: maximum strict particles in one audit sample')
    ap.add_argument('--few-fraction',type=float,default=1e-5,
                    help='descriptive SPARSE threshold: strict fraction of sampled particles')
    ap.add_argument('--few-depth-cells',type=float,default=0.25,
                    help='descriptive SPARSE threshold: maximum penetration depth in cells')
    ap.add_argument('--top-events',type=int,default=20)
    a=ap.parse_args()
    run,result,events=analyze(a.root,a.few_count,a.few_fraction,a.few_depth_cells)
    summary,evpath,lines=write_outputs(run,result,events,a.top_events)
    print('\n'.join(lines))
    print(f'[0493x18-penetration] summary={summary}')
    print(f'[0493x18-penetration] events={evpath}')

if __name__=='__main__': main()

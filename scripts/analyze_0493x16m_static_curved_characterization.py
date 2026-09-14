#!/usr/bin/env python3
"""0493x16m fixed-curved-wall characterization (stdlib only, no pandas)."""
from __future__ import annotations
import csv, math, sys
from pathlib import Path
ROOT=Path(sys.argv[1]) if len(sys.argv)>1 else Path('runs/0493x16m_static_curved_characterization')
BURN=int(sys.argv[2]) if len(sys.argv)>2 else 200
FRAMES=('rest','boost')

def rows(p):
    with p.open(newline='') as f: return list(csv.DictReader(f))
def fi(r,k): return float(r[k])
def ii(r,k): return int(float(r[k]))
def rms(v): return math.sqrt(sum(x*x for x in v)/max(1,len(v)))
def rel(a,b,floor=1e-30): return abs(a-b)/max(abs(a),abs(b),floor)

def aligned(frame):
    out=ROOT/frame/'fresh'/'output'
    P=rows(out/'chi_penetration_0493x16l.csv')
    K=rows(out/'chi_kinetic_boundary_0493x16j.csv')
    D=rows(out/'chi_solid_dynamics_0493x16a.csv')
    kp={ii(r,'step'):r for r in K}; dp={ii(r,'step'):r for r in D}
    A=[(ii(r,'step'),r,kp[ii(r,'step')],dp[ii(r,'step')]) for r in P if ii(r,'step') in kp and ii(r,'step') in dp]
    if len(A)<20: raise SystemExit(f'[0493x16m-static-curve] too few aligned rows frame={frame}: {len(A)}')
    return A

def metrics(A):
    allP=[x[1] for x in A]
    meas=[x for x in A if x[0] > BURN]
    if len(meas)<20: raise SystemExit(f'[0493x16m-static-curve] too few post-burn rows: {len(meas)}')
    P=[x[1] for x in meas]; K=[x[2] for x in meas]; D=[x[3] for x in meas]
    positive=[]
    badsteps=0; occurrences=0
    gt1e4=gt1e3=gt1e2=0
    for r in P:
        n=ii(r,'strictInsideParticles')
        d=fi(r,'maxPenetrationCells')
        if n>0:
            badsteps+=1; occurrences+=n; positive.append(d)
            gt1e4 += d>1e-4; gt1e3 += d>1e-3; gt1e2 += d>1e-2
    return {
      'steps':len(A),'measurementSteps':len(meas),'badSteps':badsteps,'occurrences':occurrences,
      'initialMaxStrict':max(ii(r,'strictInsideParticles') for r in allP if ii(r,'step')<=BURN) if BURN>0 else 0,
      'initialMaxPen':max(fi(r,'maxPenetrationCells') for r in allP if ii(r,'step')<=BURN) if BURN>0 else 0.0,
      'maxRaw':max(ii(r,'rawInsideParticles') for r in P),
      'maxStrict':max(ii(r,'strictInsideParticles') for r in P),
      'maxStrictMass':max(fi(r,'strictInsideMass') for r in P),
      'maxPen':max(fi(r,'maxPenetrationCells') for r in P),
      'maxLevel':max(fi(r,'maxSolidLevelExcess') for r in P),
      'gt1e4':gt1e4,'gt1e3':gt1e3,'gt1e2':gt1e2,
      'maxFlat':max(ii(r,'flatGradientInsideParticles') for r in P),
      'maxQ2Invalid':max(ii(r,'q2InvalidParticles') for r in P),
      'maxOrphan':max(ii(r,'orphanNoSegment') for r in K),
      'meanColl':sum(fi(r,'collisions') for r in K)/len(K),
      'impulseRms':rms([fi(r,'wallImpulseX') for r in K]),
      'maxClosure':max(max(
          abs(fi(r,'cellLoadClosureResidualX0493x16b'))/max(1.0,abs(fi(r,'cellReactionSumX0493x16b')),abs(fi(r,'totalFluidImpulseX'))),
          abs(fi(r,'cellLoadClosureResidualY0493x16b'))/max(1.0,abs(fi(r,'cellReactionSumY0493x16b')),abs(fi(r,'totalFluidImpulseY')))
        ) for r in D),
      'maxAR':max(max(
          abs(fi(r,'actionReactionResidualX'))/max(1.0,abs(fi(r,'solidReactionImpulseX')),abs(fi(r,'totalFluidImpulseX'))),
          abs(fi(r,'actionReactionResidualY'))/max(1.0,abs(fi(r,'solidReactionImpulseY')),abs(fi(r,'totalFluidImpulseY')))
        ) for r in D),
      'omegaMax':max(abs(fi(r,'deformOmega0493x16i')) for r in D),
      'ampMin':min(fi(r,'deformAmplitude0493x16i') for r in D),
      'ampMax':max(fi(r,'deformAmplitude0493x16i') for r in D),
    }

M={fr:metrics(aligned(fr)) for fr in FRAMES}
A,B=M['rest'],M['boost']
cr=rel(A['meanColl'],B['meanColl'],1.0); ir=rel(A['impulseRms'],B['impulseRms'])
spatialLeak=(max(A['maxStrict'],B['maxStrict'])>0 or max(A['maxPen'],B['maxPen'])>1e-4)
staticOK=(max(A['omegaMax'],B['omegaMax'])<=1e-30 and min(A['ampMin'],B['ampMin'])>0)
mechanicsOK=(max(A['maxOrphan'],B['maxOrphan'])==0 and max(A['maxQ2Invalid'],B['maxQ2Invalid'])==0 and
             max(A['maxClosure'],B['maxClosure'])<=1e-12 and max(A['maxAR'],B['maxAR'])<=1e-10)
classification = 'SPATIAL_CURVATURE_LEAK_DETECTED' if spatialLeak else 'NO_STATIC_CURVATURE_LEAK'
status='PASS' if staticOK and mechanicsOK else 'REVIEW'
S=[
 '0493x16m fixed-curved-wall characterization',f'status={status}',
 f'classification={classification}',
 'shape=x_center(y)=X+A*sin(2*pi*y/Ly)', 'shapeTimeDependence=none',
 f'burnInSteps={BURN}','penetrationWindow=POST_BURN_ALL_STEPS','statisticalWindow=POST_BURN_ALL_STEPS',
 'interpretationIfLeak=spatial_detection_or_curved_Q2_issue',
 'interpretationIfNoLeak=time_dependent_shape_change_implicated',
 f'collisionRateRelativeDifference={cr:.17g}',f'impulseRmsRelativeDifference={ir:.17g}',
 f'staticShapeCheck={"PASS" if staticOK else "FAIL"}',f'mechanicsCheck={"PASS" if mechanicsOK else "FAIL"}'
]
for fr in FRAMES:
    m=M[fr]
    S += ['',f'[{fr}]',f'stepsTotal={m["steps"]}',f'measurementSteps={m["measurementSteps"]}',f'initialMaxStrictInsideParticles={m["initialMaxStrict"]}',f'initialMaxPenetrationCells={m["initialMaxPen"]:.17g}',f'badPenetrationSteps={m["badSteps"]}',
          f'strictPenetrationOccurrences={m["occurrences"]}',f'maxRawInsideParticles={m["maxRaw"]}',
          f'maxStrictInsideParticles={m["maxStrict"]}',f'maxStrictInsideMass={m["maxStrictMass"]:.17g}',
          f'maxPenetrationCells={m["maxPen"]:.17g}',f'maxSolidLevelExcess={m["maxLevel"]:.17g}',
          f'badStepsDepthGt1e-4={m["gt1e4"]}',f'badStepsDepthGt1e-3={m["gt1e3"]}',f'badStepsDepthGt1e-2={m["gt1e2"]}',
          f'maxOrphanNoSegment={m["maxOrphan"]}',f'maxQ2InvalidParticles={m["maxQ2Invalid"]}',
          f'meanCollisionsMeasurement={m["meanColl"]:.17g}',f'impulseRmsMeasurement={m["impulseRms"]:.17g}',
          f'maxRelativeCellLoadClosure={m["maxClosure"]:.17g}',f'maxRelativeActionReaction={m["maxAR"]:.17g}',
          f'deformOmegaMax={m["omegaMax"]:.17g}',f'deformAmplitudeMin={m["ampMin"]:.17g}',f'deformAmplitudeMax={m["ampMax"]:.17g}']
a=ROOT/'analysis'; a.mkdir(parents=True,exist_ok=True)
out=a/'summary_0493x16m_static_curved.txt'; out.write_text('\n'.join(S)+'\n')
print(out.read_text(),end='')
# Characterization itself succeeds if the intended static geometry was exercised and bookkeeping is sound.
sys.exit(0 if staticOK and mechanicsOK else 3)

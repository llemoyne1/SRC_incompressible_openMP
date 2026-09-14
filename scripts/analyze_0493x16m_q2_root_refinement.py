#!/usr/bin/env python3
"""0493x16m final material-wall qualification (stdlib only; no pandas).

Penetration/orphan/Q2-validity/load-closure/action-reaction gates are evaluated
on the complete aligned history.  Only stationary statistical comparisons
(collision rate, impulse RMS, informational fictitious mass) use the second half.
"""
from __future__ import annotations
import csv, math, sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('runs/0493x16m_q2_root_refinement_qualification')
KINDS=('rigid','deformable')
FRAMES=('rest','boost')

def rows(path: Path):
    with path.open(newline='') as f: return list(csv.DictReader(f))
def f(r,k): return float(r[k])
def i(r,k): return int(float(r[k]))
def rms(v): return math.sqrt(sum(x*x for x in v)/max(1,len(v)))
def reldiff(a,b,floor=1e-30): return abs(a-b)/max(abs(a),abs(b),floor)

def aligned(kind,frame):
    out=ROOT/kind/frame/'fresh'/'output'
    paths=(out/'chi_penetration_0493x16l.csv', out/'chi_kinetic_boundary_0493x16j.csv', out/'chi_solid_dynamics_0493x16a.csv')
    for p in paths:
        if not p.is_file(): raise SystemExit(f'[0493x16m] missing {p}')
    P,K,D=map(rows,paths)
    kp={i(r,'step'):r for r in K}; dp={i(r,'step'):r for r in D}
    a=[]
    for r in P:
        s=i(r,'step')
        if s in kp and s in dp: a.append((s,r,kp[s],dp[s]))
    if len(a)<20: raise SystemExit(f'[0493x16m] too few aligned rows for {kind}/{frame}: {len(a)}')
    return a

def metrics(data):
    P=[t[1] for t in data]; K=[t[2] for t in data]; D=[t[3] for t in data]
    s0,s1=data[0][0],data[-1][0]; cut=s0+0.5*(s1-s0)
    stat=[t for t in data if t[0]>=cut]
    Ks=[t[2] for t in stat]; Ds=[t[3] for t in stat]
    return {
      'stepsTotal':len(data), 'stepsStat':len(stat),
      'maxRawInside':max(i(r,'rawInsideParticles') for r in P),
      'maxStrictInside':max(i(r,'strictInsideParticles') for r in P),
      'maxRawInsideMass':max(f(r,'rawInsideMass') for r in P),
      'maxStrictInsideMass':max(f(r,'strictInsideMass') for r in P),
      'maxLevelExcess':max(f(r,'maxSolidLevelExcess') for r in P),
      'maxPenCells':max(f(r,'maxPenetrationCells') for r in P),
      'maxFlatInside':max(i(r,'flatGradientInsideParticles') for r in P),
      'maxQ2Invalid':max(i(r,'q2InvalidParticles') for r in P),
      'maxHostUpload':max(i(r,'hostUploadPerformed') for r in P),
      'meanCollisions':sum(f(r,'collisions') for r in Ks)/len(Ks),
      'impulseRms':rms([f(r,'wallImpulseX') for r in Ks]),
      'maxOrphan':max(i(r,'orphanNoSegment') for r in K),
      'meanFictMass':sum(f(r,'fictitiousFluidMass0493x16c') for r in Ds)/len(Ds),
      'maxClosure':max(max(
          abs(f(r,'cellLoadClosureResidualX0493x16b'))/max(1.0,abs(f(r,'cellReactionSumX0493x16b')),abs(f(r,'totalFluidImpulseX'))),
          abs(f(r,'cellLoadClosureResidualY0493x16b'))/max(1.0,abs(f(r,'cellReactionSumY0493x16b')),abs(f(r,'totalFluidImpulseY')))
      ) for r in D),
      'maxAR':max(max(
          abs(f(r,'actionReactionResidualX'))/max(1.0,abs(f(r,'solidReactionImpulseX')),abs(f(r,'totalFluidImpulseX'))),
          abs(f(r,'actionReactionResidualY'))/max(1.0,abs(f(r,'solidReactionImpulseY')),abs(f(r,'totalFluidImpulseY')))
      ) for r in D),
    }

M={k:{fr:metrics(aligned(k,fr)) for fr in FRAMES} for k in KINDS}
PASS=True
S=[
 '0493x16m chi-only guaranteed-Q2-root mobile-solid qualification',
 'status=PLACEHOLDER',
 'rootSolver=chi_only_bisection_targetPathCells_1e-8',
 'penetrationWindow=ALL_ALIGNED_STEPS',
 'statisticalWindow=SECOND_HALF',
 'strictLevelEpsilon=1e-6',
 'strictPenetrationCountGate=0',
 'maxPenetrationCellsGate=1e-4',
 'collisionRateRelGate=0.02',
 'impulseRmsRelGate=0.15',
 'actionReactionGate=1e-10',
 'cellLoadClosureGate=1e-12',
 'orphanGate=0']
for kind in KINDS:
    A,B=M[kind]['rest'],M[kind]['boost']
    cr=reldiff(A['meanCollisions'],B['meanCollisions'],1.0)
    ir=reldiff(A['impulseRms'],B['impulseRms'])
    fict=reldiff(A['meanFictMass'],B['meanFictMass'],1.0)
    mx=lambda key:max(A[key],B[key])
    ok=(mx('maxStrictInside')==0 and mx('maxStrictInsideMass')<=1e-12 and
        mx('maxPenCells')<=1e-4 and mx('maxFlatInside')==0 and
        mx('maxQ2Invalid')==0 and mx('maxOrphan')==0 and cr<=0.02 and
        ir<=0.15 and mx('maxClosure')<=1e-12 and mx('maxAR')<=1e-10)
    PASS &= ok
    S += ['',f'[{kind}]',f'stepsTotal={min(A["stepsTotal"],B["stepsTotal"])}',
          f'stepsComparedStatistical={min(A["stepsStat"],B["stepsStat"])}',
          f'restMaxRawInsideParticles={A["maxRawInside"]}',
          f'boostMaxRawInsideParticles={B["maxRawInside"]}',
          f'maxStrictInsideParticles={mx("maxStrictInside")}',
          f'maxStrictInsideMass={mx("maxStrictInsideMass"):.17g}',
          f'maxPenetrationCells={mx("maxPenCells"):.17g}',
          f'maxSolidLevelExcess={mx("maxLevelExcess"):.17g}',
          f'maxFlatGradientInsideParticles={mx("maxFlatInside")}',
          f'maxQ2InvalidParticles={mx("maxQ2Invalid")}',
          f'collisionRateRelativeDifference={cr:.17g}',
          f'impulseRmsRelativeDifference={ir:.17g}',
          f'maxOrphanNoSegment={mx("maxOrphan")}',
          f'maxRelativeCellLoadClosure={mx("maxClosure"):.17g}',
          f'maxRelativeActionReaction={mx("maxAR"):.17g}',
          f'fictitiousMassRelativeDifference0493x16c_INFORMATIONAL={fict:.17g}',
          f'maxDiagnosticHostUploadPerformed={mx("maxHostUpload")}',
          f'qualification={"PASS" if ok else "REVIEW"}']
S[1]=f'status={"PASS" if PASS else "REVIEW"}'
a=ROOT/'analysis'; a.mkdir(parents=True,exist_ok=True)
out=a/'summary_0493x16m.txt'; out.write_text('\n'.join(S)+'\n')
print(out.read_text(),end='')
sys.exit(0 if PASS else 3)

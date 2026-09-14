#!/usr/bin/env python3
import csv, math, pathlib, sys

root=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else 'runs/0493x16k_galilean_geometry_smoke')
boost=float(sys.argv[2] if len(sys.argv)>2 else '0.08')

def rows(path):
    with open(path,newline='') as f:
        return {int(round(float(r['step']))):r for r in csv.DictReader(f)}

def fv(r,k): return float(r[k])
def iv(r,k): return int(round(float(r[k])))
def rel(a,b,scale=1e-30): return abs(a-b)/max(abs(a),abs(b),scale)

out=[]; passed=True
for kind in ('rigid','deformable'):
    cases={}
    for frame in ('rest','boost'):
        base=root/kind/frame/'fresh'/'output'
        K=rows(base/'chi_kinetic_boundary_0493x16j.csv')
        D=rows(base/'chi_solid_dynamics_0493x16a.csv')
        if 1 not in K or 2 not in K or 1 not in D:
            raise SystemExit(f'missing diagnostic steps for {kind}/{frame}')
        cases[frame]=(K,D)
    KR,DR=cases['rest']; KB,DB=cases['boost']
    r1,b1=KR[1],KB[1]; r2,b2=KR[2],KB[2]
    step1_imp_rel=rel(fv(r1,'wallImpulseX'),fv(b1,'wallImpulseX'),1.0)
    overlap_r=iv(r2,'initialOverlapResolved'); overlap_b=iv(b2,'initialOverlapResolved')
    overlap_diff=abs(overlap_b-overlap_r)
    vel_cov=abs((fv(DB[1],'velocityXAfter')-fv(DR[1],'velocityXAfter'))-boost)
    ar=max(abs(fv(DR[1],'actionReactionResidualX')),abs(fv(DB[1],'actionReactionResidualX')))
    orphan=max(iv(r1,'orphanNoSegment'),iv(b1,'orphanNoSegment'),iv(r2,'orphanNoSegment'),iv(b2,'orphanNoSegment'))
    ok=(step1_imp_rel <= 1e-6 and overlap_diff <= 2 and vel_cov <= 1e-8 and ar <= 1e-9 and orphan <= 2)
    passed = passed and ok
    out += [
        f'[{kind}]',
        f'step1ImpulseRelativeDifference={step1_imp_rel:.17g}',
        f'step2InitialOverlapRest={overlap_r}',
        f'step2InitialOverlapBoost={overlap_b}',
        f'step2InitialOverlapAbsDifference={overlap_diff}',
        f'step1SolidVelocityBoostCovarianceError={vel_cov:.17g}',
        f'step1MaxActionReactionAbs={ar:.17g}',
        f'maxOrphanFirstTwoSteps={orphan}',
        f'geometryGate={"PASS" if ok else "FAIL"}',
        ''
    ]

analysis=root/'analysis'; analysis.mkdir(parents=True,exist_ok=True)
summary=analysis/'summary_0493x16k_geometry_smoke.txt'
text='0493x16k Galilean moving-wall geometry smoke\nstatus='+('PASS' if passed else 'FAIL')+'\n'+'\n'.join(out)
summary.write_text(text+'\n')
print(text)
print(f'summary={summary}')
raise SystemExit(0 if passed else 2)

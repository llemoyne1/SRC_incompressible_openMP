#!/usr/bin/env python3
"""0493x16l final impermeability/Galilean diagnostic (stdlib only; no pandas)."""
from __future__ import annotations
import csv, math, sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('runs/0493x16l_chi_penetration_qualification')
KINDS = ('rigid', 'deformable')
FRAMES = ('rest', 'boost')

def rows(path: Path):
    with path.open(newline='') as f:
        return list(csv.DictReader(f))

def f(row, key): return float(row[key])
def i(row, key): return int(float(row[key]))
def reldiff(a,b,floor=1e-30): return abs(a-b)/max(abs(a),abs(b),floor)
def rms(vals): return math.sqrt(sum(x*x for x in vals)/max(1,len(vals)))

def aligned_case(kind, frame):
    out = ROOT/kind/frame/'fresh'/'output'
    p = out/'chi_penetration_0493x16l.csv'
    k = out/'chi_kinetic_boundary_0493x16j.csv'
    d = out/'chi_solid_dynamics_0493x16a.csv'
    for path in (p,k,d):
        if not path.is_file():
            raise SystemExit(f'[0493x16l] missing {path}')
    P,K,D = rows(p), rows(k), rows(d)
    kp={i(r,'step'):r for r in K}; dp={i(r,'step'):r for r in D}
    triples=[]
    for r in P:
        s=i(r,'step')
        if s in kp and s in dp: triples.append((s,r,kp[s],dp[s]))
    if len(triples)<20:
        raise SystemExit(f'[0493x16l] too few aligned rows for {kind}/{frame}: {len(triples)}')
    # Same statistical window as x16k: second half of the paired history.
    s0,s1=triples[0][0],triples[-1][0]
    cut=s0+0.5*(s1-s0)
    return [t for t in triples if t[0]>=cut]

def case_metrics(data):
    P=[t[1] for t in data]; K=[t[2] for t in data]; D=[t[3] for t in data]
    return {
        'steps': len(data),
        'maxRawInside': max(i(r,'rawInsideParticles') for r in P),
        'maxStrictInside': max(i(r,'strictInsideParticles') for r in P),
        'maxRawInsideMass': max(f(r,'rawInsideMass') for r in P),
        'maxStrictInsideMass': max(f(r,'strictInsideMass') for r in P),
        'maxLevelExcess': max(f(r,'maxSolidLevelExcess') for r in P),
        'maxPenCells': max(f(r,'maxPenetrationCells') for r in P),
        'maxFlatInside': max(i(r,'flatGradientInsideParticles') for r in P),
        'maxQ2Invalid': max(i(r,'q2InvalidParticles') for r in P),
        'maxHostUpload': max(i(r,'hostUploadPerformed') for r in P),
        'meanCollisions': sum(f(r,'collisions') for r in K)/len(K),
        'impulseRms': rms([f(r,'wallImpulseX') for r in K]),
        'maxOrphan': max(i(r,'orphanNoSegment') for r in K),
        'meanFictMass': sum(f(r,'fictitiousFluidMass0493x16c') for r in D)/len(D),
        'maxClosure': max(
            max(
                abs(f(r,'cellLoadClosureResidualX0493x16b'))/max(1.0,abs(f(r,'cellReactionSumX0493x16b')),abs(f(r,'totalFluidImpulseX'))),
                abs(f(r,'cellLoadClosureResidualY0493x16b'))/max(1.0,abs(f(r,'cellReactionSumY0493x16b')),abs(f(r,'totalFluidImpulseY')))
            ) for r in D
        ),
        'maxActionReaction': max(
            max(
                abs(f(r,'actionReactionResidualX'))/max(1.0,abs(f(r,'solidReactionImpulseX')),abs(f(r,'totalFluidImpulseX'))),
                abs(f(r,'actionReactionResidualY'))/max(1.0,abs(f(r,'solidReactionImpulseY')),abs(f(r,'totalFluidImpulseY')))
            ) for r in D
        ),
    }

allm={}
for kind in KINDS:
    allm[kind]={frame:case_metrics(aligned_case(kind,frame)) for frame in FRAMES}

# Final gates deliberately do NOT use x16c fictitious mass: x16l directly asks
# whether any particle lies on the material side of the Q2 wall.
PASS=True
summary=[]
summary.append('0493x16l direct poststream chi-penetration qualification')
summary.append('criteria=Q2_particle_position_not_cell_occupancy')
summary.append('strictLevelEpsilon=1e-6')
summary.append('strictPenetrationCountGate=0')
summary.append('maxPenetrationCellsGate=1e-4')
summary.append('collisionRateRelGate=0.02')
summary.append('impulseRmsRelGate=0.15')
summary.append('actionReactionGate=1e-10')
summary.append('cellLoadClosureGate=1e-12')
summary.append('orphanGate=0')

for kind in KINDS:
    A=allm[kind]['rest']; B=allm[kind]['boost']
    cr=reldiff(A['meanCollisions'],B['meanCollisions'],1.0)
    ir=reldiff(A['impulseRms'],B['impulseRms'],1e-30)
    fict=reldiff(A['meanFictMass'],B['meanFictMass'],1.0)
    max_strict=max(A['maxStrictInside'],B['maxStrictInside'])
    max_strict_mass=max(A['maxStrictInsideMass'],B['maxStrictInsideMass'])
    max_depth=max(A['maxPenCells'],B['maxPenCells'])
    max_flat=max(A['maxFlatInside'],B['maxFlatInside'])
    max_invalid=max(A['maxQ2Invalid'],B['maxQ2Invalid'])
    max_orphan=max(A['maxOrphan'],B['maxOrphan'])
    max_closure=max(A['maxClosure'],B['maxClosure'])
    max_ar=max(A['maxActionReaction'],B['maxActionReaction'])
    # Host upload is reported, not a physics gate: qualified resident cases should be zero.
    ok=(max_strict==0 and max_strict_mass<=1e-12 and max_depth<=1e-4 and
        max_flat==0 and max_invalid==0 and max_orphan==0 and
        cr<=0.02 and ir<=0.15 and max_closure<=1e-12 and max_ar<=1e-10)
    PASS=PASS and ok
    summary += [
        '', f'[{kind}]', f'stepsCompared={min(A["steps"],B["steps"])}',
        f'restMaxRawInsideParticles={A["maxRawInside"]}',
        f'boostMaxRawInsideParticles={B["maxRawInside"]}',
        f'maxStrictInsideParticles={max_strict}',
        f'maxStrictInsideMass={max_strict_mass:.17g}',
        f'maxPenetrationCells={max_depth:.17g}',
        f'maxFlatGradientInsideParticles={max_flat}',
        f'maxQ2InvalidParticles={max_invalid}',
        f'collisionRateRelativeDifference={cr:.17g}',
        f'impulseRmsRelativeDifference={ir:.17g}',
        f'maxOrphanNoSegment={max_orphan}',
        f'maxRelativeCellLoadClosure={max_closure:.17g}',
        f'maxRelativeActionReaction={max_ar:.17g}',
        f'fictitiousMassRelativeDifference0493x16c_INFORMATIONAL={fict:.17g}',
        f'maxDiagnosticHostUploadPerformed={max(A["maxHostUpload"],B["maxHostUpload"])}',
        f'qualification={"PASS" if ok else "REVIEW"}',
    ]
summary.insert(1, f'status={"PASS" if PASS else "REVIEW"}')
analysis=ROOT/'analysis'; analysis.mkdir(parents=True,exist_ok=True)
out=analysis/'summary_0493x16l.txt'
out.write_text('\n'.join(summary)+'\n')
print(out.read_text(), end='')
sys.exit(0 if PASS else 3)

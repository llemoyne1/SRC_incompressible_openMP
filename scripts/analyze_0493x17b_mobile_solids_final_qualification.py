#!/usr/bin/env python3
from __future__ import annotations
import csv, math, sys
from pathlib import Path
ROOT=Path(sys.argv[1]) if len(sys.argv)>1 else Path('runs/0493x17b_mobile_solids_final_qualification')
CASES=('static_rest','static_boost','rigid_rest','rigid_boost','deform_rest','deform_boost')

def rows(p):
    if not p.is_file(): raise SystemExit(f'[0493x17b] missing {p}')
    with p.open(newline='') as f: return list(csv.DictReader(f))
def ff(r,k): return float(r[k])
def ii(r,k): return int(float(r[k]))
def rms(v): return math.sqrt(sum(x*x for x in v)/max(1,len(v)))
def rel(a,b,floor=1e-30): return abs(a-b)/max(abs(a),abs(b),floor)

def case_path(name):
    if name.startswith('static_'): return ROOT/'static_curved'/name.split('_',1)[1]/'fresh'/'output'
    kind,frame=name.split('_',1); return ROOT/'full_mobile'/kind/frame/'fresh'/'output'

def metric(name):
    out=case_path(name)
    P=rows(out/'chi_penetration_0493x16l.csv'); K=rows(out/'chi_kinetic_boundary_0493x16j.csv'); D=rows(out/'chi_solid_dynamics_0493x16a.csv')
    kp={ii(r,'step'):r for r in K}; dp={ii(r,'step'):r for r in D}
    A=[(ii(r,'step'),r,kp[ii(r,'step')],dp[ii(r,'step')]) for r in P if ii(r,'step') in kp and ii(r,'step') in dp]
    if len(A)<20: raise SystemExit(f'[0493x17b] too few aligned rows {name}: {len(A)}')
    cut=A[0][0]+.5*(A[-1][0]-A[0][0]); S=[t for t in A if t[0]>=cut]
    mesh=out/'chi_lagrangian_mesh_0493x17a.txt'
    md={}
    if mesh.is_file():
        for line in mesh.read_text().splitlines():
            if '=' in line:
                k,v=line.split('=',1); md[k.strip()]=v.strip()
    return dict(
      rows=len(A), edges=int(md.get('edges','-1')), reextract=md.get('chiReextract','MISSING'),
      maxRaw=max(ii(t[1],'rawInsideParticles') for t in A),
      maxStrict=max(ii(t[1],'strictInsideParticles') for t in A),
      maxPen=max(ff(t[1],'maxPenetrationCells') for t in A),
      meanColl=sum(ff(t[2],'collisions') for t in S)/len(S),
      impulseRms=rms([ff(t[2],'wallImpulseX') for t in S]),
      maxClosure=max(max(
        abs(ff(t[3],'cellLoadClosureResidualX0493x16b'))/max(1.0,abs(ff(t[3],'cellReactionSumX0493x16b')),abs(ff(t[3],'totalFluidImpulseX'))),
        abs(ff(t[3],'cellLoadClosureResidualY0493x16b'))/max(1.0,abs(ff(t[3],'cellReactionSumY0493x16b')),abs(ff(t[3],'totalFluidImpulseY')))
      ) for t in A),
      maxAR=max(max(
        abs(ff(t[3],'actionReactionResidualX'))/max(1.0,abs(ff(t[3],'solidReactionImpulseX')),abs(ff(t[3],'totalFluidImpulseX'))),
        abs(ff(t[3],'actionReactionResidualY'))/max(1.0,abs(ff(t[3],'solidReactionImpulseY')),abs(ff(t[3],'totalFluidImpulseY')))
      ) for t in A),
      omega=max(abs(ff(t[3],'deformOmega0493x16i')) for t in A),
      amp=max(abs(ff(t[3],'deformAmplitude0493x16i')) for t in A),
    )
M={c:metric(c) for c in CASES}

def pair(a,b):
    A,B=M[a],M[b]
    return rel(A['meanColl'],B['meanColl'],1.0),rel(A['impulseRms'],B['impulseRms'],1e-30)
static_cr,static_ir=pair('static_rest','static_boost')
rigid_cr,rigid_ir=pair('rigid_rest','rigid_boost')
deform_cr,deform_ir=pair('deform_rest','deform_boost')
pen_gate=1e-6
all_impermeable=all(M[c]['maxStrict']==0 and M[c]['maxPen']<=pen_gate for c in CASES)
all_mesh=all(M[c]['edges']>0 and M[c]['reextract']=='never' for c in CASES)
mechanics=all(M[c]['maxClosure']<=1e-12 and M[c]['maxAR']<=1e-10 for c in CASES)
galilean=(static_cr<=.02 and rigid_cr<=.02 and deform_cr<=.02 and static_ir<=.15 and rigid_ir<=.15 and deform_ir<=.15)
static_shape=M['static_rest']['omega']<=1e-30 and M['static_boost']['omega']<=1e-30 and M['static_rest']['amp']>0 and M['static_boost']['amp']>0
ok=all_impermeable and all_mesh and mechanics and galilean and static_shape
lines=[
 '0493x17b persistent-Lagrangian-boundary qualification',
 f'status={"PASS" if ok else "REVIEW"}',
 'userGeometryInput=chi',
 'materialBoundary=initial_chi_0.5_contour',
 'initialFluidSupport=outside_material_boundary',
 'initialization=one_time_exclusion_no_runtime_remap',
 'geometryAuthorityAfterInitialization=Lagrangian_edge_mesh',
 'chiReextract=never',
 'collision=space_time_moving_segment_quadratic',
 'response=local_frame_specular',
 'historicalDarcyPath=UNCHANGED_WHEN_KINETIC_OFF',
 f'penetrationGateCells={pen_gate:.17g}',
 f'zeroStrictPenetrationAllCases={"PASS" if all_impermeable else "FAIL"}',
 f'meshPersistenceAllCases={"PASS" if all_mesh else "FAIL"}',
 f'actionReactionAndLoadClosure={"PASS" if mechanics else "FAIL"}',
 f'galileanStatisticalCheck={"PASS" if galilean else "REVIEW"}',
 f'staticShapeCheck={"PASS" if static_shape else "FAIL"}',
 f'staticCollisionRateRelativeDifference={static_cr:.17g}',
 f'staticImpulseRmsRelativeDifference={static_ir:.17g}',
 f'rigidCollisionRateRelativeDifference={rigid_cr:.17g}',
 f'rigidImpulseRmsRelativeDifference={rigid_ir:.17g}',
 f'deformCollisionRateRelativeDifference={deform_cr:.17g}',
 f'deformImpulseRmsRelativeDifference={deform_ir:.17g}',
]
for c in CASES:
    m=M[c]; lines += ['',f'[{c}]',f'edges={m["edges"]}',f'rows={m["rows"]}',f'maxRawInsideParticles={m["maxRaw"]}',f'maxStrictInsideParticles={m["maxStrict"]}',f'maxPenetrationCells={m["maxPen"]:.17g}',f'meanCollisionsSecondHalf={m["meanColl"]:.17g}',f'impulseRmsSecondHalf={m["impulseRms"]:.17g}',f'maxRelativeCellLoadClosure={m["maxClosure"]:.17g}',f'maxRelativeActionReaction={m["maxAR"]:.17g}']
out=ROOT/'analysis'/'summary_0493x17b.txt'; out.parent.mkdir(parents=True,exist_ok=True); out.write_text('\n'.join(lines)+'\n')
print(out.read_text(),end=''); sys.exit(0 if ok else 3)

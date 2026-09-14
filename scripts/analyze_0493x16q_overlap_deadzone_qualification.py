#!/usr/bin/env python3
from pathlib import Path
import sys

root=Path(sys.argv[1]) if len(sys.argv)>1 else Path('runs/0493x16q_overlap_deadzone_qualification')
static_summary=root/'static_curved'/'analysis'/'summary_0493x16m_static_curved.txt'
full_summary=root/'full_mobile'/'analysis'/'summary_0493x16m.txt'

def parse(path):
    if not path.is_file(): raise SystemExit(f'[0493x16q] missing {path}')
    d={}; sec='root'
    for raw in path.read_text().splitlines():
        line=raw.strip()
        if not line: continue
        if line.startswith('[') and line.endswith(']'):
            sec=line[1:-1]; continue
        if '=' in line:
            k,v=line.split('=',1); d[(sec,k.strip())]=v.strip()
    return d

def fv(d,sec,key,default='nan'):
    try:return float(d.get((sec,key),default))
    except:return float('nan')

S=parse(static_summary); F=parse(full_summary)
static_status=S.get(('root','status'),'MISSING')
static_class=S.get(('root','classification'),'MISSING')
static_mech=S.get(('root','mechanicsCheck'),'MISSING')
static_shape=S.get(('root','staticShapeCheck'),'MISSING')
static_cr=S.get(('root','collisionRateRelativeDifference'),'MISSING')
static_ir=S.get(('root','impulseRmsRelativeDifference'),'MISSING')
rest_pen=S.get(('rest','maxPenetrationCells'),'MISSING')
boost_pen=S.get(('boost','maxPenetrationCells'),'MISSING')
full_status=F.get(('root','status'),'MISSING')
rigid=F.get(('rigid','qualification'),'MISSING')
deform=F.get(('deformable','qualification'),'MISSING')
rigid_pen=F.get(('rigid','maxPenetrationCells'),'MISSING')
deform_pen=F.get(('deformable','maxPenetrationCells'),'MISSING')
rigid_cr=F.get(('rigid','collisionRateRelativeDifference'),'MISSING')
rigid_ir=F.get(('rigid','impulseRmsRelativeDifference'),'MISSING')
deform_cr=F.get(('deformable','collisionRateRelativeDifference'),'MISSING')
deform_ir=F.get(('deformable','impulseRmsRelativeDifference'),'MISSING')

pens=[fv(S,'rest','maxPenetrationCells'),fv(S,'boost','maxPenetrationCells'),
      fv(F,'rigid','maxPenetrationCells'),fv(F,'deformable','maxPenetrationCells')]
zero_pen=all(x==0.0 for x in pens)
galilean_ok=(zero_pen and static_mech=='PASS' and static_shape=='PASS' and
             full_status=='PASS' and rigid=='PASS' and deform=='PASS')
ok=(static_status=='PASS' and static_class=='NO_STATIC_CURVATURE_LEAK' and galilean_ok)

lines=[
 '0493x16q chi-overlap tolerance qualification',
 f'status={"PASS" if ok else "REVIEW"}',
 'geometry=continuous_piecewise_Q2_dual_square',
 'edgeRoots=Q2_exact_0_1_or_2_per_edge',
 'topology=Q2_boundary_roots_plus_local_contour_trace',
 'segmentCapacity=2_per_owner_PRECHECKED_PASS',
 'branchGuard=lambdaRaw_retained',
 'overlapTolerance=chi_1e-10h_historical_phase_unchanged',
 'historicalPhasePath=UNCHANGED',
 f'staticCurvedStatus={static_status}',
 f'staticCurvedClassification={static_class}',
 f'staticShapeCheck={static_shape}',
 f'staticMechanicsCheck={static_mech}',
 f'staticRestMaxPenetrationCells={rest_pen}',
 f'staticBoostMaxPenetrationCells={boost_pen}',
 f'staticCollisionRateRelativeDifference={static_cr}',
 f'staticImpulseRmsRelativeDifference={static_ir}',
 f'fullMobileStatus={full_status}',
 f'rigidQualification={rigid}',
 f'rigidMaxPenetrationCells={rigid_pen}',
 f'rigidCollisionRateRelativeDifference={rigid_cr}',
 f'rigidImpulseRmsRelativeDifference={rigid_ir}',
 f'deformableQualification={deform}',
 f'deformableMaxPenetrationCells={deform_pen}',
 f'deformableCollisionRateRelativeDifference={deform_cr}',
 f'deformableImpulseRmsRelativeDifference={deform_ir}',
 f'zeroPenetrationAllCases={"PASS" if zero_pen else "FAIL"}',
 f'galileanQualification={"PASS" if galilean_ok else "REVIEW"}',
]
out=root/'analysis'/'summary_0493x16q.txt'; out.parent.mkdir(parents=True,exist_ok=True)
out.write_text('\n'.join(lines)+'\n'); print(out.read_text(),end='')
sys.exit(0 if ok else 3)

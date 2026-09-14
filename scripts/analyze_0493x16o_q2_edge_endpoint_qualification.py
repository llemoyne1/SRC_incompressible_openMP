#!/usr/bin/env python3
from pathlib import Path
import sys

root=Path(sys.argv[1]) if len(sys.argv)>1 else Path('runs/0493x16o_q2_edge_endpoint_qualification')
static_summary=root/'static_curved'/'analysis'/'summary_0493x16m_static_curved.txt'
full_summary=root/'full_mobile'/'analysis'/'summary_0493x16m.txt'

def parse(path):
    if not path.is_file(): raise SystemExit(f'[0493x16o] missing {path}')
    d={}; sec='root'
    for raw in path.read_text().splitlines():
        line=raw.strip()
        if not line: continue
        if line.startswith('[') and line.endswith(']'):
            sec=line[1:-1]; continue
        if '=' in line:
            k,v=line.split('=',1); d[(sec,k.strip())]=v.strip()
    return d

S=parse(static_summary); F=parse(full_summary)
static_status=S.get(('root','status'),'MISSING')
static_class=S.get(('root','classification'),'MISSING')
full_status=F.get(('root','status'),'MISSING')
rigid=F.get(('rigid','qualification'),'MISSING')
deform=F.get(('deformable','qualification'),'MISSING')
rest_pen=S.get(('rest','maxPenetrationCells'),'MISSING')
boost_pen=S.get(('boost','maxPenetrationCells'),'MISSING')
rigid_pen=F.get(('rigid','maxPenetrationCells'),'MISSING')
deform_pen=F.get(('deformable','maxPenetrationCells'),'MISSING')
ok=(static_status=='PASS' and static_class=='NO_STATIC_CURVATURE_LEAK' and
    full_status=='PASS' and rigid=='PASS' and deform=='PASS')
lines=[
 '0493x16o Q2-consistent edge-endpoint qualification',
 f'status={"PASS" if ok else "REVIEW"}',
 'geometry=piecewise_Q2_owner_square_plus_Q2_edge_roots',
 'branchGuard=lambdaRaw_retained',
 'historicalPhasePath=UNCHANGED',
 f'staticCurvedStatus={static_status}',
 f'staticCurvedClassification={static_class}',
 f'staticRestMaxPenetrationCells={rest_pen}',
 f'staticBoostMaxPenetrationCells={boost_pen}',
 f'fullMobileStatus={full_status}',
 f'rigidQualification={rigid}',
 f'rigidMaxPenetrationCells={rigid_pen}',
 f'deformableQualification={deform}',
 f'deformableMaxPenetrationCells={deform_pen}',
]
out=root/'analysis'/'summary_0493x16o.txt'; out.parent.mkdir(parents=True,exist_ok=True)
out.write_text('\n'.join(lines)+'\n'); print(out.read_text(),end='')
sys.exit(0 if ok else 3)

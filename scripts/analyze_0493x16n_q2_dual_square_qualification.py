#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('runs/0493x16n_q2_dual_square_qualification')
static_summary = root / 'static_curved' / 'analysis' / 'summary_0493x16m_static_curved.txt'
full_summary = root / 'full_mobile' / 'analysis' / 'summary_0493x16m.txt'

def parse(path):
    if not path.exists():
        raise SystemExit(f'[0493x16n] missing {path}')
    d={}
    section='root'
    for raw in path.read_text().splitlines():
        line=raw.strip()
        if not line: continue
        if line.startswith('[') and line.endswith(']'):
            section=line[1:-1]
            continue
        if '=' in line:
            k,v=line.split('=',1)
            d[(section,k.strip())]=v.strip()
    return d

S=parse(static_summary)
F=parse(full_summary)
static_class=S.get(('root','classification'),'MISSING')
static_status=S.get(('root','status'),'MISSING')
full_status=F.get(('root','status'),'MISSING')
rigid=F.get(('rigid','qualification'),'MISSING')
deform=F.get(('deformable','qualification'),'MISSING')

# x16n is meant to remove the overlap-patch false-positive diagnostic while
# preserving all physical qualification gates.  Require both the fixed-curved
# stress case and the complete rigid/deformable suite to pass.
ok = (static_status == 'PASS' and
      static_class == 'NO_STATIC_CURVATURE_LEAK' and
      full_status == 'PASS' and rigid == 'PASS' and deform == 'PASS')

lines=[
 '0493x16n piecewise-Q2 dual-square qualification',
 f'status={"PASS" if ok else "REVIEW"}',
 'geometryConvention=owner_dual_square_[0,1]^2',
 'historicalPhasePath=UNCHANGED',
 f'staticCurvedStatus={static_status}',
 f'staticCurvedClassification={static_class}',
 f'fullMobileStatus={full_status}',
 f'rigidQualification={rigid}',
 f'deformableQualification={deform}',
]
out=root/'analysis'/'summary_0493x16n.txt'
out.parent.mkdir(parents=True,exist_ok=True)
out.write_text('\n'.join(lines)+'\n')
print(out.read_text(),end='')
sys.exit(0 if ok else 3)

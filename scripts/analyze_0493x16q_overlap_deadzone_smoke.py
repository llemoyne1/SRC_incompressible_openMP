#!/usr/bin/env python3
import csv, sys
from pathlib import Path
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path('runs/0493x16q_overlap_deadzone_smoke')
p=root/'fresh'/'output'/'chi_penetration_0493x16l.csv'
if not p.is_file(): raise SystemExit(f'[0493x16q-smoke] missing {p}')
rows={}
maxd=0.0; bad=0
with p.open(newline='') as f:
    for r in csv.DictReader(f):
        s=int(float(r['step'])); rows[s]=r
        d=float(r['maxPenetrationCells']); maxd=max(maxd,d)
        if int(float(r['strictInsideParticles']))>0: bad+=1
r=rows.get(127)
if r is None: raise SystemExit('[0493x16q-smoke] missing step 127')
strict=int(float(r['strictInsideParticles'])); d127=float(r['maxPenetrationCells'])
ok=(strict==0 and d127==0.0)
print('0493x16q overlap-deadzone targeted smoke')
print(f'status={"PASS" if ok else "REVIEW"}')
print(f'step127StrictInsideParticles={strict}')
print(f'step127MaxPenetrationCells={d127:.17g}')
print(f'maxPenetrationCellsThroughRun={maxd:.17g}')
print(f'badStepsThroughRun={bad}')
sys.exit(0 if ok else 3)

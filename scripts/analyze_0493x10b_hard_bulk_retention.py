#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: analyze_0493x10b_hard_bulk_retention.py <cuda_phase_kinetic_crossing_0493x9z.csv>')
path = Path(sys.argv[1])
with path.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10b-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def rat(a,b): return a/b if b else 0.0

last = rows[-1]
interior = isum('interiorCrossings')
final_interior_out = isum('appliedInteriorFinalOutside')
recoverable = isum('shellRecoverableParticles')
candidates = isum('shellHardRetentionCandidates')
already = isum('shellHardRetentionAlreadyInside')
corrected = isum('shellHardRetentionCorrections')
fallbacks = isum('shellHardRetentionFallbacks')
final_shell_out = isum('shellHardRetentionFinalOutside')
outer0, outer1 = I(rows[0],'phaseAOuterCellParticles'), I(last,'phaseAOuterCellParticles')
shell0, shell1 = I(rows[0],'shellParticles'), I(last,'shellParticles')
deep0, deep1 = I(rows[0],'deepOuterParticles'), I(last,'deepOuterParticles')
maxdp = max(maxabs('deltaPx'), maxabs('deltaPy'))
maxde = maxabs('deltaKineticEnergy')

print('===== 0493x10b HARD BULK RETENTION =====')
print(f'file={path} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- x10a interior contract ---')
print(f'interiorCrossings={interior} finalOutside={final_interior_out}/{interior} ({rat(final_interior_out,interior):.6%})')
print('--- recoverable shell hard retention (r=1) ---')
print(f'shellRecoverable={recoverable} candidates={candidates}')
print(f'alreadyNaturallyInside={already} corrected={corrected} fallbacks={fallbacks}')
print(f'shellHardRetentionFinalOutside={final_shell_out}/{candidates} ({rat(final_shell_out,candidates):.6%})')
print('--- halo outcome ---')
print(f'outer first={outer0} last={outer1} growth={outer1-outer0:+d}')
print(f'shell first={shell0} last={shell1} growth={shell1-shell0:+d}')
print(f'deepOuter first={deep0} last={deep1} growth={deep1-deep0:+d}')
print('--- unchanged reaction audit (not a pass criterion) ---')
print(f'max|deltaP|={maxdp:.6e} max|deltaKE|={maxde:.6e} lastMeanLambdaDev={F(last,"reactionLambdaDeviationAbsMean"):.6e}')
geometry_ok = final_interior_out == 0 and final_shell_out == 0
retention_ok = deep1 == deep0 == 0
print('hardGeometryContract=' + ('PASS' if geometry_ok else 'FAIL'))
print('bulkRetentionOutcome=' + ('PASS' if retention_ok else 'FAIL'))

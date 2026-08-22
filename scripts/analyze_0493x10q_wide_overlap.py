#!/usr/bin/env python3
import csv
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        'usage: analyze_0493x10q_wide_overlap.py '
        '<cuda_phase_kinetic_crossing_0493x9z.csv>'
    )

p = Path(sys.argv[1])
if not p.exists():
    raise SystemExit(f'[0493x10q] missing CSV: {p}')
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10q] empty CSV')

required = [
    'x10pInitialOutside',
    'x10pInitialOverlapResolved',
    'x10pInitialOverlapOutwardReflected',
    'x10pInitialOverlapInwardReleased',
    'x10pInitialOutsideTooDeep',
    'x10qWideSearchTriggered',
    'x10qWideSearchFoundSegment',
    'x10qOrphanNoSegmentAfterWideSearch',
    'x10qDeepOverlapResolved',
    'x10qOverlapResolveFailure',
    'x10qResolvedNearestDistanceMax',
]
missing = [k for k in required if k not in rows[0]]
if missing:
    raise SystemExit('[0493x10q] missing CSV columns: ' + ', '.join(missing))

def isum(k):
    return sum(int(float(r.get(k) or 0)) for r in rows)

def fmax(k):
    return max(float(r.get(k) or 0.0) for r in rows)

outside = isum('x10pInitialOutside')
resolved = isum('x10pInitialOverlapResolved')
outward = isum('x10pInitialOverlapOutwardReflected')
inward = isum('x10pInitialOverlapInwardReleased')
legacy_too_deep = isum('x10pInitialOutsideTooDeep')
wide_triggered = isum('x10qWideSearchTriggered')
wide_found = isum('x10qWideSearchFoundSegment')
orphan = isum('x10qOrphanNoSegmentAfterWideSearch')
deep_resolved = isum('x10qDeepOverlapResolved')
resolve_fail = isum('x10qOverlapResolveFailure')
max_nearest = fmax('x10qResolvedNearestDistanceMax')

print('===== 0493x10q WIDE INITIAL-OVERLAP RECOVERY =====')
print(f'file={p} rows={len(rows)}')
print(
    f'initialOutside={outside} resolved={resolved} '
    f'outwardReflected={outward} inwardReleased={inward} '
    f'legacyTooDeepUnresolved={legacy_too_deep}'
)
print(
    f'wideSearchTriggered={wide_triggered} foundSegment={wide_found} '
    f'orphanNoSegmentAfterWideSearch={orphan}'
)
print(
    f'deepOverlapResolved={deep_resolved} resolveFailure={resolve_fail} '
    f'maxResolvedNearestDistance={max_nearest:.12g}'
)
contract = (
    resolved == outward + inward
    and legacy_too_deep == 0
    and orphan == 0
    and resolve_fail == 0
    and wide_triggered == wide_found + orphan
)
print('x10qWideOverlapRecoveryContract=' + ('PASS' if contract else 'FAIL'))

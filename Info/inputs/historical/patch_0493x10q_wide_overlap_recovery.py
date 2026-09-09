#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'

if not SRC.exists():
    raise SystemExit(f'[0493x10q-patch] missing {SRC}')

text = SRC.read_text()
for tag in (
    '0493x10o-q6-hydrodynamic-thermal-interface',
    '0493x10p-initial-overlap-resolution',
):
    if tag not in text:
        raise SystemExit(f'[0493x10q-patch] prerequisite not found: {tag}')
if '0493x10q-wide-overlap-recovery' in text:
    raise SystemExit('[0493x10q-patch] x10q already appears applied')


def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10q-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)

# ---------------------------------------------------------------------------
# Audit fields. Keep x10p legacy tooDeep as an unresolved-only counter; x10q
# no longer rejects deep overlaps, so it should remain zero in a fresh run.
# ---------------------------------------------------------------------------
replace_once(
'''    unsigned long long x10pInitialOutsideTooDeep = 0ull;
    double x10pInitialOverlapPenetrationSum = 0.0;
    double x10pInitialOverlapMaxPenetration = 0.0;
};
''',
'''    unsigned long long x10pInitialOutsideTooDeep = 0ull;
    double x10pInitialOverlapPenetrationSum = 0.0;
    double x10pInitialOverlapMaxPenetration = 0.0;

    // 0493x10q: rare broad-phase recovery when the normal 3x3 search cannot
    // see the reconstructed kinetic interface from a vacuum-side cell.
    unsigned long long x10qWideSearchTriggered = 0ull;
    unsigned long long x10qWideSearchFoundSegment = 0ull;
    unsigned long long x10qOrphanNoSegmentAfterWideSearch = 0ull;
    unsigned long long x10qDeepOverlapResolved = 0ull;
    unsigned long long x10qOverlapResolveFailure = 0ull;
    double x10qResolvedNearestDistanceMax = 0.0;
};
''',
'audit x10q fields',
)

# ---------------------------------------------------------------------------
# Add a 7x7 ring fallback only for event 0, only when the ordinary 3x3 search
# found no finite segment at all, and only when the particle's current cell is
# on the alpha<0.5 side. The ordinary swept-collision path remains 3x3.
# ---------------------------------------------------------------------------
anchor = '''            if (resolveInitialOverlap0493x10p && event == 0 && nearest.valid) {
'''
if text.count(anchor) != 1:
    raise SystemExit(
        f'[0493x10q-patch] x10p overlap-resolution anchor: expected 1, found {text.count(anchor)}'
    )

wide = r'''            // 0493x10q: fallback broad phase for initial overlap only.
            // Cost remains on the rare path: the normal swept search above is
            // unchanged (3x3). If no segment is visible from a vacuum-side
            // cell, inspect only the outer ring of a 7x7 neighborhood.
            if (resolveInitialOverlap0493x10p && event == 0 &&
                !nearest.valid && alpha && alpha[cc] < 0.5) {
                if (audit)
                    atomicAdd(&audit->x10qWideSearchTriggered, 1ull);

                for (int dj0493x10q = -3; dj0493x10q <= 3; ++dj0493x10q) {
                    for (int di0493x10q = -3; di0493x10q <= 3; ++di0493x10q) {
                        if (di0493x10q >= -1 && di0493x10q <= 1 &&
                            dj0493x10q >= -1 && dj0493x10q <= 1)
                            continue; // already covered by the normal 3x3 search
                        const int owner0493x10q = q6_x10n_cell_index(
                            ci + di0493x10q, cj + dj0493x10q,
                            nx, ny, periodicX, periodicY);
                        if (owner0493x10q < 0) continue;
                        const int ns0493x10q =
                            static_cast<int>(segCount[owner0493x10q]);
                        for (int slot0493x10q = 0;
                             slot0493x10q < ns0493x10q && slot0493x10q < 2;
                             ++slot0493x10q) {
                            const int s0493x10q =
                                2 * owner0493x10q + slot0493x10q;
                            MovingSegment0493x10n seg0493x10q{};
                            seg0493x10q.ax = segAx[s0493x10q];
                            seg0493x10q.ay = segAy[s0493x10q];
                            seg0493x10q.bx = segBx[s0493x10q];
                            seg0493x10q.by = segBy[s0493x10q];
                            seg0493x10q.uax = segUax[s0493x10q];
                            seg0493x10q.uay = segUay[s0493x10q];
                            seg0493x10q.ubx = segUbx[s0493x10q];
                            seg0493x10q.uby = segUby[s0493x10q];
                            seg0493x10q.ownerCell = owner0493x10q;

                            InitialOverlapNearest0493x10p q0493x10q{};
                            if (q6_x10p_closest_current_segment(
                                    cx, cy, elapsed, lx, ly,
                                    periodicX, periodicY,
                                    seg0493x10q, &q0493x10q) &&
                                q0493x10q.distance < nearestDistance0493x10p) {
                                nearestDistance0493x10p = q0493x10q.distance;
                                nearest = q0493x10q;
                            }
                        }
                    }
                }

                if (audit) {
                    if (nearest.valid)
                        atomicAdd(&audit->x10qWideSearchFoundSegment, 1ull);
                    else
                        atomicAdd(
                            &audit->x10qOrphanNoSegmentAfterWideSearch, 1ull);
                }
            }

'''
text = text.replace(anchor, wide + anchor, 1)

# ---------------------------------------------------------------------------
# Remove the 2.5h hard refusal. If a finite nearest segment is known and the
# particle is on its vacuum side, resolve the overlap regardless of depth.
# Deep cases are counted separately. No new physics: same x10p depenetration
# and moving-frame specular law.
# ---------------------------------------------------------------------------
old_block = r'''                    if (nearest.distance <= 2.5 * h0493x10p) {
                        MovingSegmentCollision0493x10n overlap{};
                        if (q6_x10p_resolve_initial_overlap(
                                cx, cy, cvx, cvy, mass,
                                sideTol0493x10p, nearest, &overlap)) {
                            best = overlap;
                            bestSeg = nearest.seg;
                            bestTau = 0.0;
                            if (audit) {
                                atomicAdd(
                                    &audit->x10pInitialOverlapResolved, 1ull);
                                if (overlap.overlapOutwardReflected)
                                    atomicAdd(
                                        &audit->x10pInitialOverlapOutwardReflected,
                                        1ull);
                                else
                                    atomicAdd(
                                        &audit->x10pInitialOverlapInwardReleased,
                                        1ull);
                                atomic_add_double_0400(
                                    &audit->x10pInitialOverlapPenetrationSum,
                                    overlap.penetration);
                                q6_x10p_atomic_max_positive_double(
                                    &audit->x10pInitialOverlapMaxPenetration,
                                    overlap.penetration);
                            }
                        }
                    } else if (audit) {
                        atomicAdd(&audit->x10pInitialOutsideTooDeep, 1ull);
                    }
'''
new_block = r'''                    const bool deepOverlap0493x10q =
                        nearest.distance > 2.5 * h0493x10p;
                    MovingSegmentCollision0493x10n overlap{};
                    if (q6_x10p_resolve_initial_overlap(
                            cx, cy, cvx, cvy, mass,
                            sideTol0493x10p, nearest, &overlap)) {
                        best = overlap;
                        bestSeg = nearest.seg;
                        bestTau = 0.0;
                        if (audit) {
                            atomicAdd(
                                &audit->x10pInitialOverlapResolved, 1ull);
                            if (overlap.overlapOutwardReflected)
                                atomicAdd(
                                    &audit->x10pInitialOverlapOutwardReflected,
                                    1ull);
                            else
                                atomicAdd(
                                    &audit->x10pInitialOverlapInwardReleased,
                                    1ull);
                            atomic_add_double_0400(
                                &audit->x10pInitialOverlapPenetrationSum,
                                overlap.penetration);
                            q6_x10p_atomic_max_positive_double(
                                &audit->x10pInitialOverlapMaxPenetration,
                                overlap.penetration);
                            q6_x10p_atomic_max_positive_double(
                                &audit->x10qResolvedNearestDistanceMax,
                                nearest.distance);
                            if (deepOverlap0493x10q)
                                atomicAdd(
                                    &audit->x10qDeepOverlapResolved, 1ull);
                        }
                    } else if (audit) {
                        // This should be numerically exceptional: nearest is
                        // already finite and signedDistance>sideTol.
                        atomicAdd(&audit->x10qOverlapResolveFailure, 1ull);
                    }
'''
replace_once(old_block, new_block, 'remove 2.5h refusal')

# ---------------------------------------------------------------------------
# CSV diagnostics.
# ---------------------------------------------------------------------------
replace_once(
'''               "x10pInitialOverlapPenetrationSum,"
               "x10pInitialOverlapMaxPenetration,"
               "contract\\n";
''',
'''               "x10pInitialOverlapPenetrationSum,"
               "x10pInitialOverlapMaxPenetration,"
               "x10qWideSearchTriggered,x10qWideSearchFoundSegment,"
               "x10qOrphanNoSegmentAfterWideSearch,"
               "x10qDeepOverlapResolved,x10qOverlapResolveFailure,"
               "x10qResolvedNearestDistanceMax,"
               "contract\\n";
''',
'CSV x10q header',
)

replace_once(
'''        << a.x10pInitialOverlapPenetrationSum << ','
        << a.x10pInitialOverlapMaxPenetration << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'''        << a.x10pInitialOverlapPenetrationSum << ','
        << a.x10pInitialOverlapMaxPenetration << ','
        << a.x10qWideSearchTriggered << ','
        << a.x10qWideSearchFoundSegment << ','
        << a.x10qOrphanNoSegmentAfterWideSearch << ','
        << a.x10qDeepOverlapResolved << ','
        << a.x10qOverlapResolveFailure << ','
        << a.x10qResolvedNearestDistanceMax << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'CSV x10q row',
)

replace_once(
'''           "0493x10p-initial-overlap-resolution;"
           "x10p-nearest-finite-moving-segment-before-s0-sign;"
''',
'''           "0493x10p-initial-overlap-resolution;"
           "0493x10q-wide-overlap-recovery;"
           "x10q-normal-swept-search-remains-3x3;"
           "x10q-initial-overlap-fallback-ring-7x7-only-when-no-3x3-segment;"
           "x10q-known-deep-overlap-always-resolved;"
           "x10p-nearest-finite-moving-segment-before-s0-sign;"
''',
'contract x10q tags',
)

# Postconditions BEFORE writing any source file.
for marker in (
    'x10qWideSearchTriggered',
    'x10qOrphanNoSegmentAfterWideSearch',
    'x10qDeepOverlapResolved',
    '0493x10q-wide-overlap-recovery',
):
    if marker not in text:
        raise SystemExit(f'[0493x10q-patch] postcondition missing marker {marker}')
if 'if (nearest.distance <= 2.5 * h0493x10p)' in text:
    raise SystemExit('[0493x10q-patch] postcondition failed: old 2.5h refusal remains')

# ---------------------------------------------------------------------------
# Standalone analyzer; do not patch the evolving x10o/x10p analyzers in place.
# ---------------------------------------------------------------------------
analyzer = r'''#!/usr/bin/env python3
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
'''

runner = r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
mkdir -p logs

export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}"
export LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
export LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}"
export LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
export FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"

RUN_ROOT="${RUN_ROOT:-runs/0493x10q_wide_overlap_static_s4500_1000}"
export RUN_ROOT

echo '===== 0493x10q STATIC 1000 / WIDE OVERLAP RECOVERY ====='
echo '[0493x10q] normal swept broad phase=3x3; initial-overlap fallback=outer ring to 7x7'
echo '[0493x10q] known s0>0 overlap is always resolved; 2.5h is diagnostic only'
echo "[0493x10q] liveEvery=$LIVE_VIS_EVERY recordEvery=$LIVE_VIS_RECORD_EVERY fields=$LIVE_VIS_RECORD_FIELDS filterSampleEvery=$FILTER_SAMPLE_EVERY"

STEPS="${STEPS:-1000}" \
SUMMARY_EVERY="${SUMMARY_EVERY:-25}" \
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}" \
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}" \
bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh \
2>&1 | tee logs/0493x10q_wide_overlap_static_1000.log

CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
python3 scripts/analyze_0493x10q_wide_overlap.py "$CSV"
'''

# Syntax-check generated auxiliary files before mutating the repository.
compile(analyzer, '<analyze_0493x10q_wide_overlap.py>', 'exec')

# Commit all outputs only after all semantic/postcondition checks above passed.
AN = ROOT / 'scripts/analyze_0493x10q_wide_overlap.py'
RUN = ROOT / 'scripts/run_0493x10q_wide_overlap_static_1000.sh'
AN.write_text(analyzer)
AN.chmod(0o755)
RUN.write_text(runner)
RUN.chmod(0o755)
SRC.write_text(text)

print('[0493x10q-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10q-patch] normal swept collision search remains 3x3')
print('[0493x10q-patch] rare initial-overlap fallback searches outer ring to 7x7')
print('[0493x10q-patch] removed 2.5h rejection for an already identified nearest finite segment')
print('[0493x10q-patch] no new particle pass/kernel; Q6/interface/reflection physics unchanged')
print('[0493x10q-patch] wrote standalone analyzer and static 1000-step qualification runner')

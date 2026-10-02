#!/usr/bin/env python3
import csv, json, math, statistics, sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit('usage: analyze_0493x22b_bulk_projection_cost.py TIMING_CSV GPU_CSV OUTDIR')

timing = Path(sys.argv[1])
gpu = Path(sys.argv[2])
out = Path(sys.argv[3])
out.mkdir(parents=True, exist_ok=True)

with timing.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x22b-analysis] empty timing CSV')

for r in rows:
    r['rep'] = int(r['rep'])
    r['order'] = int(r['order'])
    r['steps'] = int(r['steps'])
    r['elapsed'] = float(r['elapsed'])
    r['seconds_per_step'] = float(r['seconds_per_step'])

byrep = {}
for r in rows:
    byrep.setdefault(r['rep'], {})[r['variant']] = r
expected = sorted(byrep)
if len(expected) != 5 or any(set(byrep[k]) != {'A0','A1'} for k in expected):
    raise SystemExit(f'[0493x22b-analysis] expected 5 complete A0/A1 pairs; got reps={expected}')

def median(xs): return statistics.median(xs)
def mad(xs):
    m = median(xs)
    return median([abs(x-m) for x in xs])
def cv(xs):
    m = statistics.mean(xs)
    return statistics.pstdev(xs)/m if m else math.nan

s0 = [r['seconds_per_step'] for r in rows if r['variant']=='A0']
s1 = [r['seconds_per_step'] for r in rows if r['variant']=='A1']
pairs = []
for rep in expected:
    a0 = byrep[rep]['A0']['seconds_per_step']
    a1 = byrep[rep]['A1']['seconds_per_step']
    ratio = a1/a0
    pairs.append({
        'rep': rep,
        'A0_seconds_per_step': a0,
        'A1_seconds_per_step': a1,
        'ratio_A1_over_A0': ratio,
        'overhead_percent': 100.0*(ratio-1.0),
        'A0_order': byrep[rep]['A0']['order'],
        'A1_order': byrep[rep]['A1']['order'],
    })

# GPU review: descriptive safeguard only. A pair is REVIEW if P-state changes
# between any pre-run samples for its two members or if their pre-run SM clocks
# differ by >10%. Nothing is silently excluded.
gpu_rows = []
if gpu.exists() and gpu.stat().st_size:
    with gpu.open(newline='') as f:
        gpu_rows = list(csv.DictReader(f))

def gpu_pre(variant, rep):
    stage = f'pre_{variant.lower()}_r{rep}'
    return next((r for r in gpu_rows if r.get('stage')==stage), None)

gpu_reviews = 0
for p in pairs:
    a = gpu_pre('A0', p['rep']); b = gpu_pre('A1', p['rep'])
    status='OK'; reason=''
    if a and b:
        pa=(a.get('pstate') or '').strip(); pb=(b.get('pstate') or '').strip()
        try:
            ca=float(a.get('clocks_sm_mhz','nan')); cb=float(b.get('clocks_sm_mhz','nan'))
        except ValueError:
            ca=cb=math.nan
        reasons=[]
        if pa and pb and pa != pb: reasons.append(f'pstate {pa}/{pb}')
        if math.isfinite(ca) and math.isfinite(cb) and max(abs(ca),abs(cb))>0:
            if abs(ca-cb)/max(abs(ca),abs(cb)) > 0.10:
                reasons.append(f'preclock {ca:g}/{cb:g} MHz')
        if reasons:
            status='REVIEW'; reason='; '.join(reasons); gpu_reviews += 1
    elif gpu_rows:
        status='REVIEW'; reason='missing pre-run GPU sample'; gpu_reviews += 1
    p['gpu_pair_status']=status
    p['gpu_pair_reason']=reason

ratios=[p['ratio_A1_over_A0'] for p in pairs]
over=[p['overhead_percent'] for p in pairs]
summary={
    'variant_A0':'underlying SRC',
    'variant_A1':'SRC + liquid particle/field projection',
    'pairs':len(pairs),
    'A0_median_seconds_per_step':median(s0),
    'A1_median_seconds_per_step':median(s1),
    'projection_cost_ratio_paired_median':median(ratios),
    'projection_overhead_percent_paired_median':median(over),
    'projection_overhead_percent_paired_MAD':mad(over),
    'A0_CV':cv(s0),
    'A1_CV':cv(s1),
    'gpu_pair_review_count':gpu_reviews,
    'interpretation':'paired binary-only timing; each pair compares identical initial state/seed; no pair silently excluded',
}

pairs_csv=out/'timing_bulk_pairs.csv'
with pairs_csv.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(pairs[0].keys()),lineterminator='\n')
    w.writeheader(); w.writerows(pairs)

(out/'timing_bulk_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
lines=[
    '===== 0493x22b BULK PROJECTION COST =====',
    f"pairs={summary['pairs']}",
    f"A0_median_seconds_per_step={summary['A0_median_seconds_per_step']:.17g}",
    f"A1_median_seconds_per_step={summary['A1_median_seconds_per_step']:.17g}",
    f"projection_cost_ratio_paired_median={summary['projection_cost_ratio_paired_median']:.17g}",
    f"projection_overhead_percent_paired_median={summary['projection_overhead_percent_paired_median']:.12g}",
    f"projection_overhead_percent_paired_MAD={summary['projection_overhead_percent_paired_MAD']:.12g}",
    f"A0_CV={summary['A0_CV']:.12g}",
    f"A1_CV={summary['A1_CV']:.12g}",
    f"gpu_pair_review_count={gpu_reviews}",
]
for p in pairs:
    lines.append(f"rep{p['rep']}: ratio={p['ratio_A1_over_A0']:.12g} overheadPct={p['overhead_percent']:.12g} gpu={p['gpu_pair_status']} {p['gpu_pair_reason']}")
(out/'timing_bulk_summary.txt').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))

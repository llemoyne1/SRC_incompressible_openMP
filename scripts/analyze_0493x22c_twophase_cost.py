#!/usr/bin/env python3
import csv, json, math, statistics, sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit('usage: analyze_0493x22c_twophase_cost.py TIMING_CSV GPU_CSV OUTDIR')

timing=Path(sys.argv[1]); gpu=Path(sys.argv[2]); out=Path(sys.argv[3]); out.mkdir(parents=True,exist_ok=True)
with timing.open(newline='') as f: rows=list(csv.DictReader(f))
if not rows: raise SystemExit('[0493x22c-analysis] empty timing CSV')
for r in rows:
    r['rep']=int(r['rep']); r['order']=int(r['order']); r['steps']=int(r['steps'])
    r['elapsed']=float(r['elapsed']); r['seconds_per_step']=float(r['seconds_per_step'])
byrep={}
for r in rows: byrep.setdefault(r['rep'],{})[r['variant']]=r
reps=sorted(byrep)
if len(reps)!=5 or any(set(byrep[k])!={'B0','B1'} for k in reps):
    raise SystemExit(f'[0493x22c-analysis] expected 5 complete B0/B1 pairs; got reps={reps}')

def med(xs): return statistics.median(xs)
def mad(xs):
    m=med(xs); return med([abs(x-m) for x in xs])
def cv(xs):
    m=statistics.mean(xs); return statistics.pstdev(xs)/m if m else math.nan

s0=[r['seconds_per_step'] for r in rows if r['variant']=='B0']
s1=[r['seconds_per_step'] for r in rows if r['variant']=='B1']
pairs=[]
for rep in reps:
    b0=byrep[rep]['B0']['seconds_per_step']; b1=byrep[rep]['B1']['seconds_per_step']; ratio=b1/b0
    pairs.append(dict(rep=rep,B0_seconds_per_step=b0,B1_seconds_per_step=b1,
        ratio_B1_over_B0=ratio,overhead_percent=100*(ratio-1),
        B0_order=byrep[rep]['B0']['order'],B1_order=byrep[rep]['B1']['order']))

gpu_rows=[]
if gpu.exists() and gpu.stat().st_size:
    with gpu.open(newline='') as f: gpu_rows=list(csv.DictReader(f))
def pre(v,rep):
    stage=f'pre_{v.lower()}_r{rep}'
    return next((r for r in gpu_rows if r.get('stage')==stage),None)
reviews=0
for p in pairs:
    a=pre('B0',p['rep']); b=pre('B1',p['rep']); status='OK'; reason=''
    reasons=[]
    if a and b:
        pa=(a.get('pstate') or '').strip(); pb=(b.get('pstate') or '').strip()
        try: ca=float(a.get('clocks_sm_mhz','nan')); cb=float(b.get('clocks_sm_mhz','nan'))
        except ValueError: ca=cb=math.nan
        if pa and pb and pa!=pb: reasons.append(f'pstate {pa}/{pb}')
        if math.isfinite(ca) and math.isfinite(cb) and max(abs(ca),abs(cb))>0 and abs(ca-cb)/max(abs(ca),abs(cb))>0.10:
            reasons.append(f'preclock {ca:g}/{cb:g} MHz')
    elif gpu_rows:
        reasons.append('missing pre-run GPU sample')
    if reasons:
        status='REVIEW'; reason='; '.join(reasons); reviews+=1
    p['gpu_pair_status']=status; p['gpu_pair_reason']=reason

rat=[p['ratio_B1_over_B0'] for p in pairs]; over=[p['overhead_percent'] for p in pairs]
summary={
    'variant_B0':'kinetic two-species reference',
    'variant_B1':'full liquid-gas particle/field chain',
    'pairs':len(pairs),
    'B0_median_seconds_per_step':med(s0),
    'B1_median_seconds_per_step':med(s1),
    'full_chain_cost_ratio_paired_median':med(rat),
    'full_chain_overhead_percent_paired_median':med(over),
    'full_chain_overhead_percent_paired_MAD':mad(over),
    'B0_CV':cv(s0),'B1_CV':cv(s1),'gpu_pair_review_count':reviews,
    'interpretation':'paired binary-only timing; B0 is a computational reference, not a physical validation model; no pair silently excluded'
}
with (out/'timing_twophase_pairs.csv').open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(pairs[0].keys()),lineterminator='\n'); w.writeheader(); w.writerows(pairs)
(out/'timing_twophase_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
lines=['===== 0493x22c TWO-PHASE FULL-CHAIN COST =====',f"pairs={len(pairs)}",
 f"B0_median_seconds_per_step={summary['B0_median_seconds_per_step']:.17g}",
 f"B1_median_seconds_per_step={summary['B1_median_seconds_per_step']:.17g}",
 f"full_chain_cost_ratio_paired_median={summary['full_chain_cost_ratio_paired_median']:.17g}",
 f"full_chain_overhead_percent_paired_median={summary['full_chain_overhead_percent_paired_median']:.12g}",
 f"full_chain_overhead_percent_paired_MAD={summary['full_chain_overhead_percent_paired_MAD']:.12g}",
 f"B0_CV={summary['B0_CV']:.12g}",f"B1_CV={summary['B1_CV']:.12g}",f"gpu_pair_review_count={reviews}"]
for p in pairs:
    lines.append(f"rep{p['rep']}: ratio={p['ratio_B1_over_B0']:.12g} overheadPct={p['overhead_percent']:.12g} gpu={p['gpu_pair_status']} {p['gpu_pair_reason']}")
(out/'timing_twophase_summary.txt').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))

#!/usr/bin/env python3
import csv, statistics, sys
from pathlib import Path
src, out_txt, out_pairs = map(Path, sys.argv[1:4])
rows=list(csv.DictReader(src.open()))
by={}
for r in rows:
    g=int(r['gamma']); p=int(r['pair']); by.setdefault((g,p),{})[r['variant']]=float(r['seconds_per_step'])
pairs=[]
for (g,p),d in sorted(by.items()):
    if set(d)!={'SRC_PROD','Q6GF_PROD_X7J'}: raise SystemExit(f'incomplete gamma={g} pair={p}: {d}')
    ratio=d['Q6GF_PROD_X7J']/d['SRC_PROD']; overhead=(ratio-1)*100
    pairs.append(dict(gamma=g,pair=p,src_s_per_step=d['SRC_PROD'],q6gf_s_per_step=d['Q6GF_PROD_X7J'],ratio=ratio,overhead_percent=overhead))
with out_pairs.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(pairs[0])); w.writeheader(); w.writerows(pairs)
lines=['===== 0493x22f GAMMA COST DISCRIMINATOR =====']
for g in sorted({x['gamma'] for x in pairs}):
    rr=[x for x in pairs if x['gamma']==g]
    sm=statistics.median(x['src_s_per_step'] for x in rr)
    qm=statistics.median(x['q6gf_s_per_step'] for x in rr)
    ratios=[x['ratio'] for x in rr]; rm=statistics.median(ratios)
    ovs=[x['overhead_percent'] for x in rr]; om=statistics.median(ovs)
    mad=statistics.median(abs(x-om) for x in ovs)
    lines += [f'gamma={g} pairs={len(rr)} SRC_median_s_per_step={sm:.12g} Q6GF_median_s_per_step={qm:.12g} ratio_median={rm:.9g} overhead_median_percent={om:.6g} overhead_MAD_percent={mad:.6g}']
if 8 in {x['gamma'] for x in pairs} and 20 in {x['gamma'] for x in pairs}:
    r8=statistics.median(x['ratio'] for x in pairs if x['gamma']==8)
    r20=statistics.median(x['ratio'] for x in pairs if x['gamma']==20)
    lines.append(f'ratio_gamma20_over_ratio_gamma8={r20/r8:.9g}')
lines.append('interpretation=diagnostic only; tests whether low gamma makes fixed-grid elliptic cost dominate the faster particle baseline')
out_txt.write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))

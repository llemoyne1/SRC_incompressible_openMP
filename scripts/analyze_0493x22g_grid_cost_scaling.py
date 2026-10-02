#!/usr/bin/env python3
import csv, math, statistics, sys
from pathlib import Path
src, out_txt, out_pairs, out_medians = map(Path, sys.argv[1:5])
rows=list(csv.DictReader(src.open()))
by={}
for r in rows:
    n=int(r['N']); p=int(r['pair']); by.setdefault((n,p),{})[r['variant']]=float(r['seconds_per_step'])
pairs=[]
for (n,p),d in sorted(by.items()):
    if set(d)!={'SRC_PROD','Q6GF_PROD_X7J'}:
        raise SystemExit(f'incomplete N={n} pair={p}: {d}')
    ratio=d['Q6GF_PROD_X7J']/d['SRC_PROD']; overhead=(ratio-1.0)*100.0
    pairs.append(dict(N=n,cells=n*n,pair=p,src_s_per_step=d['SRC_PROD'],q6gf_s_per_step=d['Q6GF_PROD_X7J'],ratio=ratio,overhead_percent=overhead,increment_s_per_step=d['Q6GF_PROD_X7J']-d['SRC_PROD']))
if not pairs: raise SystemExit('no complete pairs')
with out_pairs.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(pairs[0])); w.writeheader(); w.writerows(pairs)
med=[]
for n in sorted({x['N'] for x in pairs}):
    rr=[x for x in pairs if x['N']==n]
    vals={k:[x[k] for x in rr] for k in ('src_s_per_step','q6gf_s_per_step','ratio','overhead_percent','increment_s_per_step')}
    m={k:statistics.median(v) for k,v in vals.items()}
    mad=statistics.median(abs(x-m['overhead_percent']) for x in vals['overhead_percent'])
    med.append(dict(N=n,cells=n*n,pairs=len(rr),src_median_s_per_step=m['src_s_per_step'],q6gf_median_s_per_step=m['q6gf_s_per_step'],increment_median_s_per_step=m['increment_s_per_step'],ratio_median=m['ratio'],overhead_median_percent=m['overhead_percent'],overhead_MAD_percent=mad))
with out_medians.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(med[0])); w.writeheader(); w.writerows(med)

def log_slope(key):
    pts=[(math.log(float(r['N'])), math.log(float(r[key]))) for r in med if float(r[key])>0]
    if len(pts)<2: return float('nan')
    xm=sum(x for x,_ in pts)/len(pts); ym=sum(y for _,y in pts)/len(pts)
    den=sum((x-xm)**2 for x,_ in pts)
    return sum((x-xm)*(y-ym) for x,y in pts)/den if den else float('nan')

lines=['===== 0493x22g GRID COST SCALING AT CONSTANT GAMMA =====']
for r in med:
    lines.append(
        f"N={r['N']} cells={r['cells']} pairs={r['pairs']} "
        f"SRC_median_s_per_step={r['src_median_s_per_step']:.12g} "
        f"Q6GF_median_s_per_step={r['q6gf_median_s_per_step']:.12g} "
        f"increment_median_s_per_step={r['increment_median_s_per_step']:.12g} "
        f"ratio_median={r['ratio_median']:.9g} "
        f"overhead_median_percent={r['overhead_median_percent']:.6g} "
        f"overhead_MAD_percent={r['overhead_MAD_percent']:.6g}"
    )
lines.append(f"scaling_exponent_vs_linear_N_SRC={log_slope('src_median_s_per_step'):.6g}")
lines.append(f"scaling_exponent_vs_linear_N_Q6GF={log_slope('q6gf_median_s_per_step'):.6g}")
lines.append(f"scaling_exponent_vs_linear_N_increment={log_slope('increment_median_s_per_step'):.6g}")
lines.append('interpretation=diagnostic only; constant gamma/h/dt/kBT/solver settings, periodic square grid; only N and therefore domain size/cell count/particle count vary')
out_txt.write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))

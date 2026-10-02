#!/usr/bin/env python3
import csv, json, math, sys
from pathlib import Path
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path('runs/0493x22e_q6_production_cost_forensics')
outdir=root/'analysis'; outdir.mkdir(parents=True,exist_ok=True)
wallp=root/'forensic_wall.csv'
if not wallp.exists(): raise SystemExit(f'missing {wallp}')
wall={}
with wallp.open(newline='') as f:
    for r in csv.DictReader(f):
        wall[(r['grid'],r['variant'])]=r

def fnum(x,default=math.nan):
    try:return float(x)
    except:return default

def read_phase(p):
    d={}
    if not p.exists(): return d
    with p.open(newline='') as f:
        for r in csv.DictReader(f): d[r['phase']]=r
    return d

def q6map(p):
    d={}
    if not p.exists(): return d
    with p.open(newline='') as f:
        for r in csv.DictReader(f): d[(r['group'],r['phase'])]=r
    return d

def last(p):
    if not p.exists(): return {}
    with p.open(newline='') as f: rows=list(csv.DictReader(f))
    return rows[-1] if rows else {}

grids=['G128','G256']; variants=['SRC_PROD','Q6_PROD_0407','Q6GF_PROD_X7J']
rows=[]
for g in grids:
  for v in variants:
    w=wall[(g,v)]; steps=int(w['steps']); wallms=1000*float(w['elapsed_s'])/steps
    od=root/'outputs'/f'{g}_{v}'
    ph=read_phase(od/'phase_profile_0163.csv'); qm=q6map(od/'q6_cg_profile_0163.csv')
    prof=fnum(ph.get('total_profiled',{}).get('ms_per_step'))
    dep=fnum(qm.get(('q6_adapter','q6_deposit_cell_velocity'),{}).get('ms_per_q6_step'))
    solve=fnum(qm.get(('q6_adapter','q6_project_face_field'),{}).get('ms_per_q6_step'))
    apply=fnum(qm.get(('q6_adapter','q6_apply_particle_velocity_correction'),{}).get('ms_per_q6_step'))
    total=fnum(qm.get(('q6_adapter','total_q6_adapter'),{}).get('ms_per_q6_step'))
    sp=last(od/'cuda_species_q6_0491.csv'); ind=last(od/'cuda_species_q6_independent_masked_0493w5.csv')
    iterations=fnum(sp.get('q6Iterations',''))
    resident=fnum(ind.get('residentCg0493x7j','')); blocks=fnum(ind.get('residentCgBlocks0493x7j',''))
    nonq6=prof-total if math.isfinite(prof) and math.isfinite(total) else prof
    rows.append(dict(grid=g,variant=v,nx=int(w['nx']),ny=int(w['ny']),cells=int(w['cells']),wall_ms_per_step=wallms,
                     profiled_ms_per_step=prof,q6_adapter_ms_per_step=total,q6_deposit_ms=dep,q6_solve_ms=solve,q6_apply_ms=apply,
                     non_q6_profiled_ms_per_step=nonq6,q6_fraction_wall=(total/wallms if math.isfinite(total) and wallms>0 else 0.0),
                     q6_iterations_final_audit=iterations,residentCg0493x7j=resident,residentCgBlocks0493x7j=blocks))

outcsv=outdir/'q6_production_cost_forensics.csv'
with outcsv.open('w',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=list(rows[0]));wr.writeheader();wr.writerows(rows)
D={(r['grid'],r['variant']):r for r in rows}
def ratio(g,a,b): return D[(g,a)]['wall_ms_per_step']/D[(g,b)]['wall_ms_per_step']
lines=['===== 0493x22e Q6 PRODUCTION COST FORENSICS =====']
for g in grids:
    lines.append(f'--- {g} ({D[(g,"SRC_PROD")]["nx"]}x{D[(g,"SRC_PROD")]["ny"]}, cells={D[(g,"SRC_PROD")]["cells"]}) ---')
    for v in variants:
        r=D[(g,v)]
        lines.append(f"{v}: wall={r['wall_ms_per_step']:.6g} ms/step profiled={r['profiled_ms_per_step']:.6g} q6Adapter={r['q6_adapter_ms_per_step']:.6g} q6Solve={r['q6_solve_ms']:.6g} q6FracWall={100*r['q6_fraction_wall']:.3f}% iterations={r['q6_iterations_final_audit']} residentCg={r['residentCg0493x7j']} blocks={r['residentCgBlocks0493x7j']}")
    lines.append(f"Q6_PROD_0407_over_SRC={ratio(g,'Q6_PROD_0407','SRC_PROD'):.9g}")
    lines.append(f"Q6GF_PROD_X7J_over_SRC={ratio(g,'Q6GF_PROD_X7J','SRC_PROD'):.9g}")
    lines.append(f"Q6GF_over_Q6={ratio(g,'Q6GF_PROD_X7J','Q6_PROD_0407'):.9g}")
lines.append('interpretation=production-profile diagnostic only; no article cost claim until grid scaling and phase decomposition are reviewed')
(outdir/'q6_production_cost_forensics_summary.txt').write_text('\n'.join(lines)+'\n')
json.dump({'rows':rows},(outdir/'q6_production_cost_forensics_summary.json').open('w'),indent=2,allow_nan=True)
print('\n'.join(lines))

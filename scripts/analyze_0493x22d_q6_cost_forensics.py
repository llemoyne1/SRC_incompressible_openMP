#!/usr/bin/env python3
import csv, json, math, sys
from pathlib import Path

root=Path(sys.argv[1]) if len(sys.argv)>1 else Path('runs/0493x22d_q6_cost_forensics')
wall_csv=root/'forensic_wall.csv'
outdir=root/'analysis'; outdir.mkdir(parents=True, exist_ok=True)

if not wall_csv.exists():
    raise SystemExit(f'missing {wall_csv}')
wall={}
with wall_csv.open(newline='') as f:
    for r in csv.DictReader(f):
        wall[r['variant']] = {
            'elapsed_s': float(r['elapsed_s']),
            'steps': int(r['steps']),
            'wall_ms_per_step': 1000.0*float(r['elapsed_s'])/int(r['steps'])
        }

def read_phase(p):
    d={}
    if not p.exists(): return d
    with p.open(newline='') as f:
        for r in csv.DictReader(f):
            d[r['phase']]={k:r[k] for k in r}
    return d

def fnum(x, default=math.nan):
    try: return float(x)
    except Exception: return default

def last_csv(p):
    if not p.exists(): return {}
    with p.open(newline='') as f:
        rows=list(csv.DictReader(f))
    return rows[-1] if rows else {}

variants=['SRC','Q6_AUTO0407','Q6_OFF0407','Q6GF_AUTO0407','Q6GF_OFF0407']
rows=[]
for v in variants:
    od=root/'outputs'/v
    ph=read_phase(od/'phase_profile_0163.csv')
    q6=read_phase(od/'q6_cg_profile_0163.csv')  # keyed by phase; duplicates across groups are not used below
    # parse q6 profile explicitly because phase names can overlap groups
    q6rows=[]
    qp=od/'q6_cg_profile_0163.csv'
    if qp.exists():
        with qp.open(newline='') as f: q6rows=list(csv.DictReader(f))
    q6map={(r['group'],r['phase']):r for r in q6rows}
    sp=last_csv(od/'cuda_species_q6_0491.csv')
    ind=last_csv(od/'cuda_species_q6_independent_masked_0493w5.csv')
    rt=last_csv(od/'runtime_summary.csv')
    w=wall.get(v,{})
    wallms=w.get('wall_ms_per_step',math.nan)
    prof_total=fnum(ph.get('total_profiled',{}).get('ms_per_step'))
    q6_phase=fnum(ph.get('q6_projection',ph.get('q6',ph.get('Q6Projection',{}))).get('ms_per_step'))
    if not math.isfinite(q6_phase):
        # exact step-profile name in current source is usually q6_projection
        for key,val in ph.items():
            if 'q6' in key.lower() and key!='total_profiled':
                q6_phase=fnum(val.get('ms_per_step')); break
    dep=fnum(q6map.get(('q6_adapter','q6_deposit_cell_velocity'),{}).get('ms_per_q6_step'))
    solve=fnum(q6map.get(('q6_adapter','q6_project_face_field'),{}).get('ms_per_q6_step'))
    apply=fnum(q6map.get(('q6_adapter','q6_apply_particle_velocity_correction'),{}).get('ms_per_q6_step'))
    if not math.isfinite(solve):
        # robust fallback: total q6 adapter buckets mapped by source are phase indexes; locate by semantic text
        for (g,p),rr in q6map.items():
            pl=p.lower()
            if g=='q6_adapter' and ('project_face' in pl or 'cg' in pl or 'solve' in pl): solve=fnum(rr.get('ms_per_q6_step'))
            if g=='q6_adapter' and 'deposit_cell' in pl: dep=fnum(rr.get('ms_per_q6_step'))
            if g=='q6_adapter' and ('particle_velocity_correction' in pl or 'apply_particle' in pl): apply=fnum(rr.get('ms_per_q6_step'))
    q6adapter=fnum(q6map.get(('q6_adapter','total_q6_adapter'),{}).get('ms_per_q6_step'))
    iterations=fnum(sp.get('q6Iterations', rt.get('q6Iterations','')))
    resident=fnum(ind.get('residentCg0493x7j',''))
    blocks=fnum(ind.get('residentCgBlocks0493x7j',''))
    # species audit is authoritative for Q6GF timings if present
    if sp:
        dep_sp=1000.0*fnum(sp.get('depositSeconds',''))
        solve_sp=1000.0*fnum(sp.get('solveSeconds',''))
        apply_sp=1000.0*fnum(sp.get('applySeconds',''))
        total_sp=1000.0*fnum(sp.get('totalSeconds',''))
    else:
        dep_sp=solve_sp=apply_sp=total_sp=math.nan
    rows.append({
        'variant':v,'wall_ms_per_step':wallms,'profiled_ms_per_step':prof_total,
        'q6_phase_ms_per_step':q6_phase,'q6_phase_over_wall':q6_phase/wallms if wallms>0 and math.isfinite(q6_phase) else math.nan,
        'q6_adapter_ms_per_step':q6adapter,'q6_deposit_ms':dep,'q6_solve_ms':solve,'q6_apply_ms':apply,
        'species_audit_deposit_ms':dep_sp,'species_audit_solve_ms':solve_sp,'species_audit_apply_ms':apply_sp,'species_audit_total_ms':total_sp,
        'q6_iterations_final_audit':iterations,'residentCg0493x7j':resident,'residentCgBlocks0493x7j':blocks,
    })

csvout=outdir/'q6_cost_forensics.csv'
with csvout.open('w',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=list(rows[0])); wr.writeheader(); wr.writerows(rows)
D={r['variant']:r for r in rows}
def ratio(a,b,key='wall_ms_per_step'):
    x=D[a][key]; y=D[b][key]
    return x/y if y and math.isfinite(x) and math.isfinite(y) else math.nan
summary=[]
summary.append('===== 0493x22d Q6 COST FORENSICS =====')
for r in rows:
    summary.append(f"{r['variant']}: wall={r['wall_ms_per_step']:.6g} ms/step profiled={r['profiled_ms_per_step']:.6g} q6Phase={r['q6_phase_ms_per_step']:.6g} q6/wall={100*r['q6_phase_over_wall']:.3f}% q6Solve={r['q6_solve_ms']:.6g} ms residentCg={r['residentCg0493x7j']} blocks={r['residentCgBlocks0493x7j']}")
summary.append(f"Q6_AUTO0407_over_SRC={ratio('Q6_AUTO0407','SRC'):.9g}")
summary.append(f"Q6_OFF0407_over_SRC={ratio('Q6_OFF0407','SRC'):.9g}")
summary.append(f"Q6_OFF_over_AUTO={ratio('Q6_OFF0407','Q6_AUTO0407'):.9g}")
summary.append(f"Q6GF_AUTO0407_over_SRC={ratio('Q6GF_AUTO0407','SRC'):.9g}")
summary.append(f"Q6GF_OFF0407_over_SRC={ratio('Q6GF_OFF0407','SRC'):.9g}")
summary.append(f"Q6GF_OFF_over_AUTO={ratio('Q6GF_OFF0407','Q6GF_AUTO0407'):.9g}")
summary.append('interpretation=diagnostic only; use internal phase fractions to identify cost source before any article performance claim')
(outdir/'q6_cost_forensics_summary.txt').write_text('\n'.join(summary)+'\n')
json.dump({'rows':rows,'ratios':{
    'Q6_AUTO0407_over_SRC':ratio('Q6_AUTO0407','SRC'),
    'Q6_OFF0407_over_SRC':ratio('Q6_OFF0407','SRC'),
    'Q6_OFF_over_AUTO':ratio('Q6_OFF0407','Q6_AUTO0407'),
    'Q6GF_AUTO0407_over_SRC':ratio('Q6GF_AUTO0407','SRC'),
    'Q6GF_OFF0407_over_SRC':ratio('Q6GF_OFF0407','SRC'),
    'Q6GF_OFF_over_AUTO':ratio('Q6GF_OFF0407','Q6GF_AUTO0407'),
}},(outdir/'q6_cost_forensics_summary.json').open('w'),indent=2,allow_nan=True)
print('\n'.join(summary))

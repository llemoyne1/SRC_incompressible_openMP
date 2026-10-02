#!/usr/bin/env python3
import csv, sys
from pathlib import Path

root=Path(sys.argv[1]); grids=[int(x) for x in sys.argv[2].split()]; gamma=int(sys.argv[3])
outdir=root/'analysis'; outdir.mkdir(parents=True,exist_ok=True)

def read_csv(path):
    with open(path,newline='') as f: return list(csv.DictReader(f))

def phase_map(path):
    return {r['phase']:float(r['ms_per_step']) for r in read_csv(path)}

def q6_map(path):
    return {(r['group'],r['phase']):float(r['ms_per_q6_step']) for r in read_csv(path)}

rows=[]; qrows=[]
for n in grids:
    dat={}
    for v in ('SRC_PROD','Q6GF_PROD_X7J'):
        od=root/'outputs'/f'N{n}_pair1_{v}'
        pp=od/'phase_profile_0163.csv'
        if not pp.exists(): raise SystemExit(f'missing {pp}')
        pm=phase_map(pp); dat[v]=pm
        for phase,ms in pm.items():
            rows.append({'N':n,'cells':n*n,'gamma':gamma,'variant':v,'phase':phase,'ms_per_step':ms})
        if v=='Q6GF_PROD_X7J':
            qp=od/'q6_cg_profile_0163.csv'
            if not qp.exists(): raise SystemExit(f'missing {qp}')
            qm=q6_map(qp)
            for (group,phase),ms in qm.items():
                qrows.append({'N':n,'cells':n*n,'gamma':gamma,'group':group,'phase':phase,'ms_per_q6_step':ms})
    src=dat['SRC_PROD']; q=dat['Q6GF_PROD_X7J']
    def g(m,k): return m.get(k,0.0)
    q6tot=g(q,'q6_projection')
    src_total=g(src,'total_profiled'); q_total=g(q,'total_profiled')
    qm={(r['group'],r['phase']):r['ms_per_q6_step'] for r in qrows if r['N']==n}
    qa=qm.get(('q6_adapter','total_q6_adapter'),0.0)
    solve=qm.get(('q6_adapter','q6_project_face_field'),0.0)
    deposit=qm.get(('q6_adapter','q6_deposit_cell_velocity'),0.0)
    apply=qm.get(('q6_adapter','q6_apply_particle_velocity_correction'),0.0)
    print(f'N={n} SRCprofile={src_total:.6g} Q6GFprofile={q_total:.6g} phaseQ6={q6tot:.6g} q6Adapter={qa:.6g} solve={solve:.6g} deposit={deposit:.6g} apply={apply:.6g}')

for name,data,fields in [
    ('grid_phase_profile.csv',rows,['N','cells','gamma','variant','phase','ms_per_step']),
    ('grid_q6_profile.csv',qrows,['N','cells','gamma','group','phase','ms_per_q6_step'])]:
    with open(outdir/name,'w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(data)

lines=['===== 0493x22h GRID PHASE PROFILE AT CONSTANT GAMMA =====']
for n in grids:
    src={r['phase']:r['ms_per_step'] for r in rows if r['N']==n and r['variant']=='SRC_PROD'}
    q={r['phase']:r['ms_per_step'] for r in rows if r['N']==n and r['variant']=='Q6GF_PROD_X7J'}
    qm={(r['group'],r['phase']):r['ms_per_q6_step'] for r in qrows if r['N']==n}
    st=src.get('total_profiled',0); qt=q.get('total_profiled',0)
    qa=qm.get(('q6_adapter','total_q6_adapter'),0); solve=qm.get(('q6_adapter','q6_project_face_field'),0)
    dep=qm.get(('q6_adapter','q6_deposit_cell_velocity'),0); app=qm.get(('q6_adapter','q6_apply_particle_velocity_correction'),0)
    nonq6=max(0.0, qt-qa)
    lines.append(f'N={n} cells={n*n} SRC_profile_ms={st:.9g} Q6GF_profile_ms={qt:.9g} Q6_adapter_ms={qa:.9g} Q6_solve_ms={solve:.9g} Q6_deposit_ms={dep:.9g} Q6_apply_ms={app:.9g} Q6GF_nonQ6_ms={nonq6:.9g}')
lines.append('interpretation=diagnostic decomposition only; exact x22g production paths, gamma constant, internal profiles ON')
(outdir/'grid_phase_profile_summary.txt').write_text('\n'.join(lines)+'\n')

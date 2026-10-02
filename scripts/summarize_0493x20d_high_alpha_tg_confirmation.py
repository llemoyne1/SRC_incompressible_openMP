#!/usr/bin/env python3
import csv, json, math, sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'runs/0493x20d_high_alpha_tg_confirmation')
matrix = root / 'campaign_matrix.csv'
summary = root / 'summary'
summary.mkdir(parents=True, exist_ok=True)
if not matrix.exists():
    raise SystemExit(f'[0493x20d-summary] ERROR missing matrix: {matrix}')
with matrix.open(newline='', encoding='utf-8') as f:
    cases = list(csv.DictReader(f))
MODELS=('src','src-q6-g-f')

def fnum(x):
    try:
        if x is None or x == '': return None
        v=float(x)
        return v if math.isfinite(v) else None
    except Exception:
        return None

def mean_std(vals):
    vals=[float(v) for v in vals if v is not None and math.isfinite(float(v))]
    if not vals: return None,None,None,0
    n=len(vals); m=sum(vals)/n
    s=math.sqrt(sum((x-m)**2 for x in vals)/(n-1)) if n>1 else 0.0
    return m,s,(s/abs(m) if m else None),n

def write_csv(path, rows, fields):
    with path.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore');w.writeheader();w.writerows(rows)

agg=[]; real=[]; data={}
for c in cases:
    cid=c['case_id']; alpha=float(c['alpha_SRC_deg']); data[cid]={}
    for model in MODELS:
        p=root/'configs'/cid/model/'analysis'/'fluid_characterization.json'
        if not p.exists():
            agg.append({'case_id':cid,'alpha_SRC_deg':alpha,'model':model,'status':'MISSING'})
            continue
        d=json.loads(p.read_text(encoding='utf-8')); data[cid][model]=d
        h=fnum(d.get('cellSize')); dt=fnum(d.get('dt')); kbt=fnum(d.get('kBT')); mass=fnum(d.get('particleMass'))
        ell=(dt/h)*math.sqrt(kbt/mass) if all(v is not None for v in (h,dt,kbt,mass)) and h and mass else None
        nu=fnum(d.get('viscosityKinematic')); scale=(dt/(h*h)) if h and dt is not None else None
        runs=d.get('tgRuns') or []
        r2=[fnum(r.get('R2')) for r in runs]; r2=[x for x in r2 if x is not None]
        agg.append({
            'case_id':cid,'alpha_SRC_deg':alpha,'gamma':d.get('gamma'),'lambdaMeanOverH':d.get('lambdaMeanOverCell'),
            'ell':ell,'h':h,'dt':dt,'kBT':kbt,'m':mass,'gridNx':256,'gridNy':256,'tgModeX':1,'tgModeY':1,
            'model':model,'status':d.get('status'),'viscosity_status':d.get('viscosityStatus'),
            'nu_eff':nu,'nu_std':d.get('viscosityStd'),'nu_CV':d.get('viscosityCV'),
            'mean_fit_R2':sum(r2)/len(r2) if r2 else None,'min_fit_R2':min(r2) if r2 else None,
            'nu_star':nu*scale if nu is not None and scale is not None else None,'n_tg':len(runs),
            'tg_time':c.get('tg_time'),'tg_dumps':c.get('tg_dumps')})
        for r in runs:
            real.append({'case_id':cid,'alpha_SRC_deg':alpha,'model':model,'seed':r.get('seed'),'status':r.get('status'),
                         'nu':r.get('nu'),'fit_R2':r.get('R2'),'finalRatio':r.get('finalRatio'),'fitPoints':r.get('fitPoints')})

ratios=[]
for c in cases:
    cid=c['case_id']; row={'case_id':cid,'alpha_SRC_deg':float(c['alpha_SRC_deg'])}
    s=data.get(cid,{}).get('src'); q=data.get(cid,{}).get('src-q6-g-f')
    if not s or not q:
        row['ratio_status']='MISSING'; ratios.append(row); continue
    ns=fnum(s.get('viscosityKinematic')); nq=fnum(q.get('viscosityKinematic'))
    row.update({'src_status':s.get('status'),'q6gf_status':q.get('status'),
                'src_viscosity_status':s.get('viscosityStatus'),'q6gf_viscosity_status':q.get('viscosityStatus'),
                'R_nu_ratio_of_means':nq/ns if ns not in (None,0) and nq is not None else None,
                'delta_nu_relative':nq/ns-1 if ns not in (None,0) and nq is not None else None})
    sm={r.get('seed'):fnum(r.get('nu')) for r in (s.get('tgRuns') or [])}
    qm={r.get('seed'):fnum(r.get('nu')) for r in (q.get('tgRuns') or [])}
    vals=[qm[k]/sm[k] for k in sorted(set(sm)&set(qm),key=lambda x:(x is None,x)) if sm[k] not in (None,0) and qm[k] is not None]
    m,sd,cv,n=mean_std(vals)
    row.update({'R_nu_paired_mean':m,'R_nu_paired_std':sd,'R_nu_paired_CV':cv,'R_nu_paired_n':n})
    sts={str(s.get('viscosityStatus')),str(q.get('viscosityStatus'))}
    row['ratio_status']='INVALID' if ('INVALID' in sts or 'MISSING' in sts) else ('REVIEW' if 'REVIEW' in sts else 'PASS')
    ratios.append(row)

write_csv(summary/'x20d_results_aggregated.csv',agg,
 ['case_id','alpha_SRC_deg','gamma','lambdaMeanOverH','ell','h','dt','kBT','m','gridNx','gridNy','tgModeX','tgModeY','model','status','viscosity_status','nu_eff','nu_std','nu_CV','mean_fit_R2','min_fit_R2','nu_star','n_tg','tg_time','tg_dumps'])
write_csv(summary/'x20d_realizations.csv',real,
 ['case_id','alpha_SRC_deg','model','seed','status','nu','fit_R2','finalRatio','fitPoints'])
write_csv(summary/'x20d_ratios_paired.csv',ratios,
 ['case_id','alpha_SRC_deg','ratio_status','src_status','q6gf_status','src_viscosity_status','q6gf_viscosity_status','R_nu_ratio_of_means','delta_nu_relative','R_nu_paired_mean','R_nu_paired_std','R_nu_paired_CV','R_nu_paired_n'])
print(f'[0493x20d-summary] cases={len(cases)} model-cases={len(agg)} realizations={len(real)}')
for name in ('x20d_results_aggregated.csv','x20d_realizations.csv','x20d_ratios_paired.csv'):
    print(f'[0493x20d-summary] wrote {summary/name}')

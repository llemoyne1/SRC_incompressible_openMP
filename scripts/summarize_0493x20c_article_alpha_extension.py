#!/usr/bin/env python3
import csv, json, math, sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'runs/0493x20c_article_alpha_extension')
matrix = root / 'campaign_matrix.csv'
summary = root / 'summary'
summary.mkdir(parents=True, exist_ok=True)

if not matrix.exists():
    raise SystemExit(f'[0493x20c-summary] ERROR missing matrix: {matrix}')

with matrix.open(newline='', encoding='utf-8') as f:
    cases = list(csv.DictReader(f))

MODELS = ('src', 'src-q6-g-f')

def fnum(x):
    try:
        if x is None or x == '': return None
        v=float(x)
        return v if math.isfinite(v) else None
    except Exception:
        return None

def mean_std(vals):
    vals=[float(v) for v in vals if v is not None and math.isfinite(float(v))]
    n=len(vals)
    if not vals: return None,None,None,0
    m=sum(vals)/n
    if n>1:
        s=math.sqrt(sum((x-m)**2 for x in vals)/(n-1))
    else:
        s=0.0
    cv=s/abs(m) if m != 0 else None
    return m,s,cv,n

def write_csv(path, rows, fields):
    with path.open('w', newline='', encoding='utf-8') as f:
        w=csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
        w.writeheader(); w.writerows(rows)

agg=[]
real=[]
data_by_case={}

for c in cases:
    cid=c['case_id']
    alpha=float(c['alpha_SRC_deg'])
    data_by_case[cid]={}
    for model in MODELS:
        p=root/'configs'/cid/model/'analysis'/'fluid_characterization.json'
        if not p.exists():
            agg.append({'case_id':cid,'alpha_SRC_deg':alpha,'model':model,'status':'MISSING'})
            continue
        d=json.loads(p.read_text(encoding='utf-8'))
        data_by_case[cid][model]=d
        h=fnum(d.get('cellSize')); dt=fnum(d.get('dt')); kbt=fnum(d.get('kBT')); mass=fnum(d.get('particleMass'))
        ell=(dt/h)*math.sqrt(kbt/mass) if all(v is not None for v in (h,dt,kbt,mass)) and h and mass else None
        nu=fnum(d.get('viscosityKinematic')); D=fnum(d.get('selfDiffusion'))
        scale=(dt/(h*h)) if h and dt is not None else None
        row={
            'case_id':cid,'alpha_SRC_deg':alpha,'gamma':d.get('gamma'),'lambdaMeanOverH':d.get('lambdaMeanOverCell'),
            'ell':ell,'h':h,'dt':dt,'kBT':kbt,'m':mass,'model':model,'status':d.get('status'),
            'viscosity_status':d.get('viscosityStatus'),'nu_eff':nu,'nu_std':d.get('viscosityStd'),'nu_CV':d.get('viscosityCV'),
            'diffusion_status':d.get('diffusionStatus'),'D_self':D,'D_std':d.get('selfDiffusionStd'),'D_CV':d.get('selfDiffusionCV'),
            'Sc':d.get('Schmidt'),'nu_star':nu*scale if nu is not None and scale is not None else None,
            'D_star':D*scale if D is not None and scale is not None else None,
            'n_tg':len(d.get('tgRuns') or []),'n_msd':len(d.get('msdRuns') or []),
            'tg_time':c.get('tg_time'),'tg_dumps':c.get('tg_dumps'),'msd_time':c.get('msd_time'),'msd_dumps':c.get('msd_dumps')
        }
        agg.append(row)
        for r in d.get('tgRuns') or []:
            real.append({'case_id':cid,'alpha_SRC_deg':alpha,'model':model,'experiment':'tg','seed':r.get('seed'),
                         'status':r.get('status'),'value':r.get('nu'),'fit_R2':r.get('R2'),'finalRatio':r.get('finalRatio'),
                         'fitPoints':r.get('fitPoints')})
        for r in d.get('msdRuns') or []:
            value=r.get('selfDiffusion', r.get('D', r.get('value')))
            r2=r.get('R2', r.get('fitR2'))
            real.append({'case_id':cid,'alpha_SRC_deg':alpha,'model':model,'experiment':'msd','seed':r.get('seed'),
                         'status':r.get('status'),'value':value,'fit_R2':r2,'finalRatio':'','fitPoints':r.get('fitPoints','')})

ratio=[]
for c in cases:
    cid=c['case_id']; alpha=float(c['alpha_SRC_deg'])
    s=data_by_case.get(cid,{}).get('src'); q=data_by_case.get(cid,{}).get('src-q6-g-f')
    row={'case_id':cid,'alpha_SRC_deg':alpha}
    if not s or not q:
        row['ratio_status']='MISSING'; ratio.append(row); continue
    ns=fnum(s.get('viscosityKinematic')); nq=fnum(q.get('viscosityKinematic'))
    Ds=fnum(s.get('selfDiffusion')); Dq=fnum(q.get('selfDiffusion'))
    row.update({
        'src_status':s.get('status'),'q6gf_status':q.get('status'),
        'src_viscosity_status':s.get('viscosityStatus'),'q6gf_viscosity_status':q.get('viscosityStatus'),
        'src_diffusion_status':s.get('diffusionStatus'),'q6gf_diffusion_status':q.get('diffusionStatus'),
        'R_nu_ratio_of_means':nq/ns if ns and nq is not None else None,
        'delta_nu_relative':nq/ns-1 if ns and nq is not None else None,
        'R_D_ratio_of_means':Dq/Ds if Ds and Dq is not None else None,
        'delta_D_relative':Dq/Ds-1 if Ds and Dq is not None else None,
    })
    # Paired seed ratios when the JSON exposes per-run lists.
    for key, arrkey, valkeys, prefix in [
        ('nu','tgRuns',('nu',),'R_nu_paired'),
        ('D','msdRuns',('selfDiffusion','D','value'),'R_D_paired')]:
        sm={r.get('seed'):r for r in s.get(arrkey) or []}
        qm={r.get('seed'):r for r in q.get(arrkey) or []}
        vals=[]
        for seed in sorted(set(sm)&set(qm), key=lambda x: (x is None, x)):
            def getv(r):
                for k in valkeys:
                    v=fnum(r.get(k))
                    if v is not None: return v
                return None
            a=getv(sm[seed]); b=getv(qm[seed])
            if a not in (None,0) and b is not None: vals.append(b/a)
        m,sd,cv,n=mean_std(vals)
        row[prefix+'_mean']=m; row[prefix+'_std']=sd; row[prefix+'_CV']=cv; row[prefix+'_n']=n
    bad={'INVALID','MISSING'}
    statuses={str(s.get('viscosityStatus')),str(q.get('viscosityStatus')),str(s.get('diffusionStatus')),str(q.get('diffusionStatus'))}
    row['ratio_status']='INVALID' if statuses & bad else ('REVIEW' if 'REVIEW' in statuses else 'PASS')
    ratio.append(row)

agg_fields=['case_id','alpha_SRC_deg','gamma','lambdaMeanOverH','ell','h','dt','kBT','m','model','status',
            'viscosity_status','nu_eff','nu_std','nu_CV','diffusion_status','D_self','D_std','D_CV','Sc','nu_star','D_star',
            'n_tg','n_msd','tg_time','tg_dumps','msd_time','msd_dumps']
real_fields=['case_id','alpha_SRC_deg','model','experiment','seed','status','value','fit_R2','finalRatio','fitPoints']
ratio_fields=['case_id','alpha_SRC_deg','ratio_status','src_status','q6gf_status','src_viscosity_status','q6gf_viscosity_status',
              'src_diffusion_status','q6gf_diffusion_status','R_nu_ratio_of_means','delta_nu_relative','R_nu_paired_mean','R_nu_paired_std','R_nu_paired_CV','R_nu_paired_n',
              'R_D_ratio_of_means','delta_D_relative','R_D_paired_mean','R_D_paired_std','R_D_paired_CV','R_D_paired_n']
write_csv(summary/'x20c_results_aggregated.csv',agg,agg_fields)
write_csv(summary/'x20c_realizations.csv',real,real_fields)
write_csv(summary/'x20c_ratios_paired.csv',ratio,ratio_fields)

print(f'[0493x20c-summary] cases={len(cases)} model-cases={len(agg)} realizations={len(real)}')
for name in ('x20c_results_aggregated.csv','x20c_realizations.csv','x20c_ratios_paired.csv'):
    print(f'[0493x20c-summary] wrote {summary/name}')

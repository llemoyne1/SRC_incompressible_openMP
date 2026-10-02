#!/usr/bin/env python3
"""0493x21e-fix3: analysis-only review of the completed radius campaign.

This script does NOT modify solver data or rerun simulations.  It consumes the
existing x21e article outputs plus the already-written active pressure histories.
It exists to resolve two review points in the v1 article analyzer:
  1. preserve the signed offline x6c/p3/x9r curvature instead of negating it;
  2. do not label a pressure-fit slope as sigma_eff unless the pressure observable
     is independently shown to support a Laplace-law interpretation.

The script therefore reports signed shadow and active-plateau pressure fits side
by side and leaves the physical assignment as REVIEW / NOT_ASSIGNED.
No pandas dependency.
"""
from __future__ import annotations
import argparse, csv, math
from pathlib import Path

VERSION='0493x21e-fix3-article-capillary-review-v1'

def F(r,k,default=math.nan):
    try: return float(r.get(k,''))
    except Exception: return default

def mean(v):
    q=[x for x in v if math.isfinite(x)]
    return sum(q)/len(q) if q else math.nan

def sd(v):
    q=[x for x in v if math.isfinite(x)]
    if len(q)<2: return 0.0 if len(q)==1 else math.nan
    m=mean(q); return math.sqrt(sum((x-m)**2 for x in q)/(len(q)-1))

def read_csv(p:Path):
    with p.open(newline='') as f: return list(csv.DictReader(f))

def write_csv(p:Path, rows):
    p.parent.mkdir(parents=True,exist_ok=True)
    if not rows: p.write_text(''); return
    with p.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

def resolve(repo:Path,s:str):
    p=Path(s)
    return p if p.is_absolute() else repo/p

def linfit(x,y):
    q=[(a,b) for a,b in zip(x,y) if math.isfinite(a) and math.isfinite(b)]
    n=len(q)
    if n<3:return dict(n=n,intercept=math.nan,slope=math.nan,R2=math.nan,slope_se=math.nan)
    xx=[a for a,b in q]; yy=[b for a,b in q]
    xm=mean(xx); ym=mean(yy); sxx=sum((a-xm)**2 for a in xx)
    if sxx<=0:return dict(n=n,intercept=math.nan,slope=math.nan,R2=math.nan,slope_se=math.nan)
    slope=sum((a-xm)*(b-ym) for a,b in q)/sxx; intercept=ym-slope*xm
    res=[b-(intercept+slope*a) for a,b in q]
    sse=sum(z*z for z in res); sst=sum((b-ym)**2 for b in yy)
    r2=1-sse/sst if sst>0 else math.nan
    se=math.sqrt((sse/(n-2))/sxx) if n>2 else math.nan
    return dict(n=n,intercept=intercept,slope=slope,R2=r2,slope_se=se)

def originfit(x,y):
    q=[(a,b) for a,b in zip(x,y) if math.isfinite(a) and math.isfinite(b)]
    n=len(q); den=sum(a*a for a,b in q)
    if n<2 or den<=0:return dict(n=n,slope0=math.nan,slope0_se=math.nan)
    s=sum(a*b for a,b in q)/den
    res=[b-s*a for a,b in q]
    se=math.sqrt(sum(z*z for z in res)/(max(1,n-1)*den))
    return dict(n=n,slope0=s,slope0_se=se)

def pressure_plateau(active:Path,start:int,end:int):
    p=active/'output'/'cuda_static_drop_pressure_0493x9e.csv'
    if not p.is_file(): return None
    rr=read_csv(p)
    q=[r for r in rr if start<=int(round(F(r,'step',-1)))<=end]
    if not q:return None
    keys=['measuredPressureJump','liquidProjectionPressureGaugeMean','gasEosPressureGaugeMean','laplaceTargetCurrent']
    out={'plateau_pressure_samples':len(q)}
    for k in keys:
        vals=[F(r,k) for r in q]
        out[k+'_plateau_mean']=mean(vals); out[k+'_plateau_std']=sd(vals)
    return out

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--repo',type=Path,default=Path('.'))
    ap.add_argument('--campaign-root',type=Path,required=True)
    a=ap.parse_args(); repo=a.repo.resolve(); camp=a.campaign_root
    if not camp.is_absolute(): camp=(repo/camp).resolve()
    src=camp/'article_capillary_outputs'/'data'/'capillary_realizations.csv'
    if not src.is_file(): raise SystemExit(f'[x21e-fix3] missing {src}')
    rr=read_csv(src); outdir=camp/'article_capillary_review_fix3'; (outdir/'data').mkdir(parents=True,exist_ok=True); (outdir/'figures').mkdir(parents=True,exist_ok=True)

    detail=[]; missing_plateau=[]
    for r in rr:
        # Preserve production/offline sign exactly.  The v1 column kappa_num_mean
        # was sign-flipped; kappa_code_mean_signed is the reconstructed p3/x9r value.
        k=F(r,'kappa_code_mean_signed')
        kth=F(r,'kappa_th')
        dp_shadow=F(r,'delta_p_code_signed')
        active=resolve(repo,r['active_run'])
        start=int(round(F(r,'averaging_start',-1))); end=int(round(F(r,'averaging_end',-1)))
        pp=pressure_plateau(active,start,end)
        if pp is None:
            missing_plateau.append(r['case_id']); pp={}
        row={
          'case_id':r['case_id'],'seed':r['seed'],'R_init_over_h':r['R_init_over_h'],'R_eff_over_h':r['R_eff_over_h'],
          'kappa_th':kth,'kappa_num_signed':k,'kappa_num_over_kappa_th':k/kth if math.isfinite(k) and kth else math.nan,
          'kappa_abs_relative_error':abs(abs(k)-kth)/kth if math.isfinite(k) and kth else math.nan,
          'delta_p_shadow_signed':dp_shadow,
          'shadow_gain_signed':dp_shadow/(F(r,'sigma_target')*k) if math.isfinite(dp_shadow) and math.isfinite(k) and abs(k)>1e-30 else math.nan,
          'U_interface_rms':F(r,'U_sp_rms'),'U_interface_rms_over_U_sigma':F(r,'U_sp_rms_over_U_sigma'),
          'clip_fraction':F(r,'clip_fraction'),'axis_ratio':F(r,'axis_ratio'),'article_use':r['article_use'],
          'plateau_start':start,'plateau_end':end,'active_run':r['active_run'],
        }
        row.update(pp); detail.append(row)
    write_csv(outdir/'data'/'capillary_review_realizations.csv',detail)

    groups=[]
    radii=sorted({F(r,'R_init_over_h') for r in detail})
    for rc in radii:
        q=[r for r in detail if F(r,'R_init_over_h')==rc and int(float(r['article_use']))==1]
        def ms(k): return mean([F(r,k) for r in q]),sd([F(r,k) for r in q])
        reff,reffsd=ms('R_eff_over_h'); kth,kthsd=ms('kappa_th'); kn,knsd=ms('kappa_num_signed'); ke,kesd=ms('kappa_abs_relative_error')
        ds,dssd=ms('delta_p_shadow_signed'); sg,sgsd=ms('shadow_gain_signed'); ur,ursd=ms('U_interface_rms_over_U_sigma'); cf,cfsd=ms('clip_fraction')
        pp,ppsd=ms('measuredPressureJump_plateau_mean')
        groups.append({
          'R_init_over_h':rc,'n':len(q),'R_eff_over_h_mean':reff,'R_eff_over_h_std_seed':reffsd,
          'kappa_th_mean':kth,'kappa_num_signed_mean':kn,'kappa_num_signed_std_seed':knsd,
          'kappa_num_over_kappa_th':kn/kth if kth else math.nan,'kappa_abs_relative_error_mean':ke,'kappa_abs_relative_error_std_seed':kesd,
          'delta_p_shadow_signed_mean':ds,'delta_p_shadow_signed_std_seed':dssd,'shadow_gain_signed_mean':sg,'shadow_gain_signed_std_seed':sgsd,
          'pressure_jump_plateau_mean':pp,'pressure_jump_plateau_std_seed':ppsd,
          'U_interface_rms_over_U_sigma_mean':ur,'U_interface_rms_over_U_sigma_std_seed':ursd,
          'clip_fraction_mean':cf,'clip_fraction_std_seed':cfsd,
        })
    write_csv(outdir/'data'/'capillary_review_radius_means.csv',groups)

    x=[g['kappa_num_signed_mean'] for g in groups]
    yshadow=[g['delta_p_shadow_signed_mean'] for g in groups]
    yplateau=[g['pressure_jump_plateau_mean'] for g in groups]
    sf=linfit(x,yshadow); so=originfit(x,yshadow); pf=linfit(x,yplateau); po=originfit(x,yplateau)
    fitrows=[]
    for name,f,o in [('shadow_signed',sf,so),('active_plateau_signed',pf,po)]:
        fitrows.append({'observable':name,'n_radius_groups':f['n'],'free_slope':f['slope'],'free_slope_se':f['slope_se'],'free_intercept':f['intercept'],'free_R2':f['R2'],'origin_slope':o['slope0'],'origin_slope_se':o['slope0_se'],'physical_assignment':'NOT_ASSIGNED_REVIEW'})
    write_csv(outdir/'data'/'capillary_pressure_fit_review.csv',fitrows)

    sig=F(rr[0],'sigma_target') if rr else math.nan
    lines=[
      '===== 0493x21e-fix3 ARTICLE CAPILLARY REVIEW =====',
      f'analyzerVersion={VERSION}',f'realizations={len(detail)} radiusGroups={len(groups)} sigmaTarget={sig:.12g}',
      f'missingActivePlateauHistories={len(missing_plateau)}',
      'curvatureConvention=SIGNED_OFFLINE_X6C_P3_X9R_PRESERVED_NO_ARTICLE_SIGN_FLIP',
      'pressureConvention=SIGNED_X9E_MEASURED_PRESSURE_JUMP_PRESERVED_NO_SIGN_FLIP',
      f'shadowFreeSlope={sf["slope"]:.12g} shadowSlopeSE={sf["slope_se"]:.12g} shadowIntercept={sf["intercept"]:.12g} shadowR2={sf["R2"]:.9g}',
      f'shadowOriginSlope={so["slope0"]:.12g} shadowOriginSlopeSE={so["slope0_se"]:.12g}',
      f'plateauFreeSlope={pf["slope"]:.12g} plateauSlopeSE={pf["slope_se"]:.12g} plateauIntercept={pf["intercept"]:.12g} plateauR2={pf["R2"]:.9g}',
      f'plateauOriginSlope={po["slope0"]:.12g} plateauOriginSlopeSE={po["slope0_se"]:.12g}',
      'sigmaEffective=NOT_ASSIGNED',
      'status=REVIEW_PRESSURE_OBSERVABLE',
      'note=do not use the v1 fitted_sigma_eff value; it depends on sign flips and the free fit is not a validated Laplace calibration.',
      'note=U_interface_rms contains thermal MPCD fluctuations and is not labelled a pure spurious-current amplitude.',
      'note=no new simulation is requested by this analyzer; active plateau histories are reused when present.',
    ]
    if missing_plateau: lines.append('missingPlateauCases='+';'.join(missing_plateau))
    (outdir/'capillary_review_summary.txt').write_text('\n'.join(lines)+'\n')

    # Diagnostic figures, deliberately separate rather than a publication figure.
    try:
        import matplotlib.pyplot as plt
        # curvature
        fig=plt.figure(figsize=(5.4,4.2)); ax=fig.add_subplot(111)
        xx=[g['kappa_th_mean'] for g in groups]; yy=[g['kappa_num_signed_mean'] for g in groups]; ye=[g['kappa_num_signed_std_seed'] for g in groups]
        ax.errorbar(xx,yy,yerr=ye,fmt='o',capsize=3,label='signed reconstructed curvature')
        lo=min(xx+yy); hi=max(xx+yy); ax.plot([lo,hi],[lo,hi],'--',label='ideal')
        ax.set_xlabel('1/R_eff'); ax.set_ylabel('kappa_num (signed)'); ax.legend(fontsize=8); fig.tight_layout(); fig.savefig(outdir/'figures'/'review_curvature_vs_invReff.pdf'); fig.savefig(outdir/'figures'/'review_curvature_vs_invReff.png',dpi=200); plt.close(fig)
        # pressure
        fig=plt.figure(figsize=(5.8,4.4)); ax=fig.add_subplot(111)
        ax.errorbar(x,yshadow,yerr=[g['delta_p_shadow_signed_std_seed'] for g in groups],fmt='o',capsize=3,label='same-state shadow increment')
        if all(math.isfinite(v) for v in yplateau): ax.plot(x,yplateau,'s',label='active plateau mean')
        lo=min(x); hi=max(x); ax.plot([lo,hi],[sig*lo,sig*hi],'--',label='ideal sigma*kappa')
        if math.isfinite(sf['slope']): ax.plot([lo,hi],[sf['intercept']+sf['slope']*lo,sf['intercept']+sf['slope']*hi],label=f'shadow free fit, R2={sf["R2"]:.3f}')
        ax.set_xlabel('kappa_num (signed)'); ax.set_ylabel('pressure observable (signed)'); ax.legend(fontsize=8); fig.tight_layout(); fig.savefig(outdir/'figures'/'review_pressure_vs_kappa.pdf'); fig.savefig(outdir/'figures'/'review_pressure_vs_kappa.png',dpi=200); plt.close(fig)
        # thermal-inclusive interface RMS
        fig=plt.figure(figsize=(5.4,4.2)); ax=fig.add_subplot(111)
        ax.errorbar([g['R_eff_over_h_mean'] for g in groups],[g['U_interface_rms_over_U_sigma_mean'] for g in groups],yerr=[g['U_interface_rms_over_U_sigma_std_seed'] for g in groups],fmt='o-',capsize=3)
        ax.set_xlabel('R_eff/h'); ax.set_ylabel('U_interface,rms / U_sigma (thermal-inclusive)'); fig.tight_layout(); fig.savefig(outdir/'figures'/'review_interface_rms.pdf'); fig.savefig(outdir/'figures'/'review_interface_rms.png',dpi=200); plt.close(fig)
    except Exception as e:
        (outdir/'figures'/'FIGURE_ERROR.txt').write_text(str(e)+'\n')

    print('\n'.join(lines))
    print(f'outputs={outdir}')

if __name__=='__main__': main()

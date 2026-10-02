#!/usr/bin/env python3
import csv, math, sys
from pathlib import Path
from statistics import fmean, stdev


def rows(path):
    with path.open(newline='') as f:
        return list(csv.DictReader(f))

def F(r,k,default=math.nan):
    try:
        v=float(r[k])
        return v if math.isfinite(v) else default
    except Exception:
        return default

def mean(xs):
    xs=[x for x in xs if math.isfinite(x)]
    return fmean(xs) if xs else math.nan

def sd(xs):
    xs=[x for x in xs if math.isfinite(x)]
    return stdev(xs) if len(xs)>1 else 0.0

def rel_drift(rs,key):
    n=len(rs)
    if n<6: return math.inf
    m=max(2,n//5)
    a=mean([F(r,key) for r in rs[:m]])
    b=mean([F(r,key) for r in rs[-m:]])
    c=mean([F(r,key) for r in rs])
    return abs(b-a)/max(abs(c),1e-30)

def select_plateau(pr):
    # Earliest acceptable quasi-stationary tail. Pressure is deliberately a
    # weaker gate than geometry: this is a pilot, not the final regression.
    for frac in (0.40,0.50,0.60,0.70):
        j=int(frac*len(pr)); rr=pr[j:]
        if len(rr)<20: continue
        dr=rel_drift(rr,'effectiveRadius')
        da=rel_drift(rr,'alphaArea')
        dp=rel_drift(rr,'measuredPressureJump')
        if dr<=0.01 and da<=0.02 and dp<=0.10:
            return rr,frac,'PASS',dr,da,dp
    j=max(0,int(0.70*len(pr)))
    rr=pr[j:]
    return rr,0.70,'REVIEW',rel_drift(rr,'effectiveRadius'),rel_drift(rr,'alphaArea'),rel_drift(rr,'measuredPressureJump')

def tail_from_step(rr, step0):
    return [r for r in rr if int(float(r.get('step','-1')))>=step0]

def main():
    if len(sys.argv)!=2:
        raise SystemExit('usage: analyze_0493x21d_article_capillary_pilot.py RUN_ROOT')
    root=Path(sys.argv[1])
    out=root/'output'; ana=root/'analysis'; ana.mkdir(parents=True,exist_ok=True)
    pfile=out/'cuda_static_drop_pressure_0493x9e.csv'
    vfile=out/'cuda_static_drop_velocity_0493x9e.csv'
    lfile=out/'cuda_surface_tension_limiter_0493x9r.csv'
    sfile=out/'cuda_ellipse_shape_0493x9f.csv'
    for p in (pfile,vfile,lfile):
        if not p.is_file(): raise SystemExit(f'[x21d-analyze] missing {p}')
    pr=rows(pfile); vr=rows(vfile); lr=rows(lfile); sr=rows(sfile) if sfile.is_file() else []
    if len(pr)<20: raise SystemExit('[x21d-analyze] too few pressure samples')
    pp,frac,pstat,dr,da,dpdr=select_plateau(pr)
    step0=int(float(pp[0]['step'])); step1=int(float(pp[-1]['step']))
    vv=tail_from_step(vr,step0); ll=tail_from_step(lr,step0); ss=tail_from_step(sr,step0)

    sigma=mean([F(r,'sigma') for r in pp])
    rho=mean([F(r,'rhoLiquidRef') for r in pp])
    reff=mean([F(r,'effectiveRadius') for r in pp])
    area=mean([F(r,'alphaArea') for r in pp])
    keq=1.0/reff
    kmean=mean([F(r,'curvatureMean') for r in pp])
    kstd_space=mean([F(r,'curvatureStd') for r in pp])
    ktime=sd([F(r,'curvatureMean') for r in pp])
    kerr=abs(abs(kmean)-keq)/keq
    pl=mean([F(r,'liquidProjectionPressureGaugeMean') for r in pp])
    pg=mean([F(r,'gasEosPressureGaugeMean') for r in pp])
    dpress=mean([F(r,'measuredPressureJump') for r in pp])
    dpress_tstd=sd([F(r,'measuredPressureJump') for r in pp])
    sigma_eff=dpress/kmean if math.isfinite(kmean) and abs(kmean)>1e-30 else math.nan
    ratio=sigma_eff/sigma if sigma else math.nan
    usp_rms=mean([F(r,'interfaceSpeedRms') for r in vv])
    usp_max=max([F(r,'interfaceSpeedMax') for r in vv if math.isfinite(F(r,'interfaceSpeedMax'))] or [math.nan])
    usig=math.sqrt(sigma/(rho*reff)) if sigma>0 and rho>0 and reff>0 else math.nan
    usp_red=usp_rms/usig if usig>0 else math.nan
    clip_mean=mean([F(r,'clipFraction',0.0) for r in ll])
    clip_max=max([F(r,'clipFraction',0.0) for r in ll] or [0.0])
    reff_h=math.nan
    # rho = gamma*m/h^2 and this pilot locks gamma=8,m=1.
    if rho>0: reff_h=reff*math.sqrt(rho/8.0)
    axis=mean([F(r,'axisRatio') for r in ss]) if ss else math.nan
    ell=mean([F(r,'ellipticity') for r in ss]) if ss else math.nan

    # Pilot gates validate the measurement pipeline; they do not assert the
    # final article calibration.  A high clipping fraction is surfaced, not hidden.
    notes=[]
    if pstat!='PASS': notes.append('plateau_geometry_or_pressure_review')
    if kerr>0.15: notes.append('curvature_error_above_15pct')
    if clip_max>0.10: notes.append('limiter_clip_above_10pct')
    status='PASS_PIPELINE' if pstat=='PASS' else 'REVIEW_PIPELINE'

    row={
      'case_id':'0493x21d_article_capillary_pilot','seed':'4932401',
      'sigma_target':sigma,'R_eff':reff,'R_eff_over_h':reff_h,'alpha_area':area,
      'kappa_th_abs':keq,'kappa_num_mean_signed':kmean,'kappa_num_abs_over_kappa_th':abs(kmean)/keq,
      'kappa_num_spatial_std':kstd_space,'kappa_num_time_std':ktime,'kappa_relative_error':kerr,
      'p_L':pl,'p_G':pg,'delta_p':dpress,'delta_p_time_std':dpress_tstd,
      'sigma_eff_local_signed':sigma_eff,'sigma_eff_over_sigma_local':ratio,
      'U_sp_max':usp_max,'U_sp_rms':usp_rms,'U_sigma':usig,'U_sp_rms_over_U_sigma':usp_red,
      'clip_fraction_mean':clip_mean,'clip_fraction_max':clip_max,
      'axis_ratio':axis,'ellipticity':ell,
      'averaging_start_step':step0,'averaging_end_step':step1,
      'Reff_relative_drift':dr,'area_relative_drift':da,'pressure_relative_drift':dpdr,
      'plateau_status':pstat,'status':status,'notes':';'.join(notes) if notes else 'none'
    }
    with (ana/'capillary_pilot_realization_0493x21d.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(row)); w.writeheader(); w.writerow(row)
    txt='\n'.join([
      '===== 0493x21d ARTICLE CAPILLARY PILOT =====',
      f'plateauStatus={pstat} fractionStart={frac:.2f} steps={step0}..{step1}',
      f'Reff={reff:.9g} Reff/h={reff_h:.6g} drift={dr:.3%} areaDrift={da:.3%}',
      f'kappaThAbs={keq:.9g} kappaNumMeanSigned={kmean:.9g} kappaAbsRatio={abs(kmean)/keq:.6g} Ekappa={kerr:.3%}',
      f'pL={pl:.9g} pG={pg:.9g} deltaP={dpress:.9g} deltaPTimeStd={dpress_tstd:.9g}',
      f'sigmaTarget={sigma:.9g} sigmaEffLocalSigned={sigma_eff:.9g} sigmaEff/sigma={ratio:.6g}',
      f'UspRms={usp_rms:.9g} UspMax={usp_max:.9g} Usigma={usig:.9g} UspRms/Usigma={usp_red:.6g}',
      f'clipMean={clip_mean:.3%} clipMax={clip_max:.3%}',
      f'axisRatio={axis:.9g} ellipticity={ell:.9g}',
      f'status={status}',
      'notes=' + (';'.join(notes) if notes else 'none'),
      'interpretation=pilot only; validates plateau/curvature/pressure/spurious-current extraction before multi-radius campaign',
      ''
    ])
    (ana/'capillary_pilot_report_0493x21d.txt').write_text(txt)
    print(txt,end='')

if __name__=='__main__': main()

#!/usr/bin/env python3
from __future__ import annotations

import argparse, csv, importlib.util, math, shutil, statistics, sys, zipfile
from pathlib import Path

ANALYZER_VERSION = "0493x21e-article-capillary-radius-v1"


def read_rows(path: Path):
    with path.open(newline='') as f:
        return list(csv.DictReader(f))


def F(r, k, default=math.nan):
    try:
        v = float(r[k])
        return v if math.isfinite(v) else default
    except Exception:
        return default


def mean(xs):
    a = [float(x) for x in xs if math.isfinite(float(x))]
    return statistics.fmean(a) if a else math.nan


def sd(xs):
    a = [float(x) for x in xs if math.isfinite(float(x))]
    return statistics.stdev(a) if len(a) > 1 else 0.0


def rel_drift(rs, key):
    if len(rs) < 6:
        return math.inf
    n = max(2, len(rs)//5)
    a = mean([F(r, key) for r in rs[:n]])
    b = mean([F(r, key) for r in rs[-n:]])
    c = mean([F(r, key) for r in rs])
    return abs(b-a)/max(abs(c), 1e-30)


def write_csv(path: Path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text('')
        return
    keys = []
    for r in rows:
        for k in r:
            if k not in keys:
                keys.append(k)
    with path.open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader(); w.writerows(rows)


def load_reconstruction_module(repo: Path):
    p = repo/'scripts'/'analyze_0493x13n_rim_traction_v2.py'
    if not p.is_file():
        raise SystemExit(f'[x21e] missing validated offline reconstruction helper: {p}')
    spec = importlib.util.spec_from_file_location('x13n_recon', p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def select_checkpoint(run_root: Path, radius_cells: float, seed: int, out: Path):
    pfile = run_root/'output'/'cuda_static_drop_pressure_0493x9e.csv'
    sfile = run_root/'output'/'cuda_ellipse_shape_0493x9f.csv'
    if not pfile.is_file():
        raise SystemExit(f'[x21e-select] missing {pfile}')
    pr = read_rows(pfile)
    sr = read_rows(sfile) if sfile.is_file() else []
    if len(pr) < 30:
        raise SystemExit(f'[x21e-select] too few x9e rows in {run_root}: {len(pr)}')
    shapes = {int(round(F(r,'step',-1))): r for r in sr}
    status='REVIEW'; chosen=None
    for frac in (0.40,0.50,0.60,0.70):
        j=int(frac*len(pr)); rr=pr[j:]
        dr=rel_drift(rr,'effectiveRadius'); da=rel_drift(rr,'alphaArea')
        steps=[int(round(F(r,'step',-1))) for r in rr]
        axisvals=[F(shapes[s],'axisRatio') for s in steps if s in shapes and math.isfinite(F(shapes[s],'axisRatio'))]
        axis=mean(axisvals) if axisvals else math.nan
        if dr<=0.01 and da<=0.02 and (not math.isfinite(axis) or axis<=1.08):
            status='PASS'; chosen=(rr,frac,dr,da,axis); break
    if chosen is None:
        frac=0.70; rr=pr[int(frac*len(pr)):]
        dr=rel_drift(rr,'effectiveRadius'); da=rel_drift(rr,'alphaArea')
        steps=[int(round(F(r,'step',-1))) for r in rr]
        axisvals=[F(shapes[s],'axisRatio') for s in steps if s in shapes and math.isfinite(F(shapes[s],'axisRatio'))]
        axis=mean(axisvals) if axisvals else math.nan
        chosen=(rr,frac,dr,da,axis)
    rr,frac,dr,da,axis=chosen
    start=int(round(F(rr[0],'step'))); end=int(round(F(rr[-1],'step')))
    dumps=[]
    for p in (run_root/'output').glob('state_step_*.smpcd'):
        try: dumps.append((int(p.stem.split('_')[-1]),p))
        except Exception: pass
    eligible=[z for z in dumps if start<=z[0]<=end]
    if not eligible:
        raise SystemExit(f'[x21e-select] no dump inside plateau {start}..{end} for {run_root}')
    cp_step, cp = max(eligible)
    row={
        'radiusCells':radius_cells,'seed':seed,'runRoot':str(run_root),
        'plateauStatus':status,'plateauFractionStart':frac,'plateauStartStep':start,'plateauEndStep':end,
        'ReffPlateauMean':mean([F(r,'effectiveRadius') for r in rr]),
        'alphaAreaPlateauMean':mean([F(r,'alphaArea') for r in rr]),
        'ReffRelativeDrift':dr,'alphaAreaRelativeDrift':da,'axisRatioPlateauMean':axis,
        'checkpointStep':cp_step,'checkpointState':str(cp)
    }
    write_csv(out,[row])
    print(f"[x21e-select] R/h={radius_cells:g} seed={seed} plateau={status} {start}..{end} checkpoint={cp_step}")


def first_positive(path: Path):
    rr=read_rows(path)
    pos=[r for r in rr if F(r,'step',0)>0]
    if not pos: raise RuntimeError(f'no positive-step row in {path}')
    return pos[0]


def all_face_curvatures(alpha,curv,carrier,nx,ny,dx,dy,kmax,periodicX=False,periodicY=False):
    pressure=[1 if carrier[c] and alpha[c]>=.5 else 0 for c in range(nx*ny)]
    vals=[]; represented=uncovered=truncation=clipped=0; rawmax=effmax=0.0
    def proc(c,q,axis):
        nonlocal represented,uncovered,truncation,clipped,rawmax,effmax
        ac,aq=alpha[c],alpha[q]
        ch=ac>=.5 and aq<.5; qh=aq>=.5 and ac<.5
        crossing=ch or qh
        pc,pq=bool(pressure[c]),bool(pressure[q])
        if pc and pq: return
        if pc or pq:
            if not crossing:
                truncation+=1; return
            ah=ac if ch else aq; al=aq if ch else ac; den=ah-al
            if den<=1e-14:return
            theta=(ah-.5)/den
            high=c if ch else q; low=q if ch else c
            kr=(1-theta)*curv[high]+theta*curv[low]
            if not math.isfinite(kr):return
            ke=max(-kmax,min(kmax,kr)) if kmax>0 else kr
            clip=kmax>0 and abs(kr)>kmax
            represented+=1; clipped+=int(clip)
            rawmax=max(rawmax,abs(kr)); effmax=max(effmax,abs(ke))
            vals.append((axis,kr,ke,int(clip),theta))
            return
        if crossing: uncovered+=1
    for iy in range(ny):
        for ix in range(nx):
            c=iy*nx+ix
            if periodicX or ix<nx-1:
                proc(c,iy*nx+((ix+1)%nx),'x')
            if periodicY or iy<ny-1:
                proc(c,((iy+1)%ny)*nx+ix,'y')
    return {'represented':represented,'uncovered':uncovered,'truncation':truncation,'clipped':clipped,'rawMax':rawmax,'effMax':effmax},vals


def linfit(x,y):
    n=len(x)
    if n<2:return (math.nan,math.nan,math.nan,math.nan)
    xm=mean(x); ym=mean(y); sxx=sum((a-xm)**2 for a in x)
    if sxx<=0:return (math.nan,math.nan,math.nan,math.nan)
    b=sum((a-xm)*(c-ym) for a,c in zip(x,y))/sxx
    a=ym-b*xm
    res=[c-(a+b*z) for z,c in zip(x,y)]
    sse=sum(r*r for r in res); sst=sum((c-ym)**2 for c in y)
    r2=1-sse/sst if sst>0 else math.nan
    se=math.sqrt((sse/(n-2))/sxx) if n>2 else math.nan
    return a,b,r2,se


def originfit(x,y):
    den=sum(z*z for z in x)
    b=sum(z*c for z,c in zip(x,y))/den if den>0 else math.nan
    res=[c-b*z for z,c in zip(x,y)] if math.isfinite(b) else []
    se=math.sqrt(sum(r*r for r in res)/(max(1,len(x)-1)*den)) if den>0 and len(x)>1 else math.nan
    return b,se


def tex_escape(s):
    return str(s).replace('_','\\_')


def final_analysis(repo: Path, campaign: Path, manifest: Path, sigma: float, binary_sha: str):
    mod=load_reconstruction_module(repo)
    mrows=read_rows(manifest)
    if not mrows: raise SystemExit('[x21e] empty manifest')
    reals=[]; validation_lines=[]
    for m in mrows:
        rc=float(m['radiusCells']); seed=int(m['seed']); active=Path(m['activeRoot'])
        sel=read_rows(Path(m['selectionCsv']))[0]
        cp=Path(sel['checkpointState']); cpstep=int(sel['checkpointStep'])
        kv=mod.parse_kv(mod.find_params(active))
        Lx=mod.as_float(kv,'Lx');Ly=mod.as_float(kv,'Ly');nx=mod.as_int(kv,'Nx');ny=mod.as_int(kv,'Ny');dx=Lx/nx;dy=Ly/ny
        minfill=mod.as_float(kv,'speciesQ6MinOccupancyFraction'); rmin=mod.as_float(kv,'surfaceTensionMinRadiusCells'); kmax=1/(rmin*min(dx,dy))
        periodicX=kv.get('bcX','').lower()=='periodic'; periodicY=kv.get('bcY','').lower()=='periodic'
        liquid_type=1; ref=None
        for key,val in kv.items():
            if key.startswith('species') and key[7:].isdigit():
                tok=val.split()
                if tok and int(tok[0])==liquid_type: ref=float(tok[-1]); break
        if ref is None: raise RuntimeError(f'cannot infer ref mass in {active}')
        raw,Mcp,N,xcm=mod.deposit_fill(cp,nx,ny,Lx,Ly,liquid_type,ref)
        _,alpha=mod.physical_alpha(raw,nx,ny,.125,periodicX,periodicY)
        carrier=mod.carrier_mask(raw,nx,ny,minfill,periodicX,periodicY)
        curv=mod.p3_curvature(alpha,nx,ny,dx,dy,periodicX,periodicY)
        stats,faces=all_face_curvatures(alpha,curv,carrier,nx,ny,dx,dy,kmax,periodicX,periodicY)
        kr=[z[1] for z in faces]; ke=[z[2] for z in faces]
        kraw=mean(kr); keff=mean(ke); kstd=sd(ke)
        area=sum(alpha)*dx*dy; reff=math.sqrt(area/math.pi); kth=1/reff
        # Article sign convention: positive curvature and pressure jump for a convex liquid drop.
        karticle=-keff; kraw_article=-kraw
        kerr=abs(abs(keff)-kth)/kth

        ra=first_positive(Path(m['shadowActiveRoot'])/'output'/'cuda_static_drop_pressure_0493x9e.csv')
        rz=first_positive(Path(m['shadowZeroRoot'])/'output'/'cuda_static_drop_pressure_0493x9e.csv')
        pa=F(ra,'measuredPressureJump'); pz=F(rz,'measuredPressureJump'); dp_code=pa-pz; dp_article=-dp_code
        pL=F(ra,'liquidProjectionPressureGaugeMean'); pG=F(ra,'gasEosPressureGaugeMean')
        sigma_local=dp_code/keff if abs(keff)>1e-30 else math.nan
        gain=sigma_local/sigma if sigma else math.nan
        reffa=F(ra,'effectiveRadius');reffz=F(rz,'effectiveRadius'); areaa=F(ra,'alphaArea');areaz=F(rz,'alphaArea')
        rad_mismatch=abs(reffa-reffz)/max(abs(reffa),1e-30); area_mismatch=abs(areaa-areaz)/max(abs(areaa),1e-30)

        # Validate offline reconstruction against the actual one-step active shadow x9r audit.
        lim=first_positive(Path(m['shadowActiveRoot'])/'output'/'cuda_surface_tension_limiter_0493x9r.csv')
        sf=int(round(F(lim,'capillaryFaces',-1))); sc=int(round(F(lim,'clippedFaces',-1)))
        sraw=F(lim,'capillaryKappaRawAbsMax'); seff=F(lim,'capillaryKappaEffectiveAbsMax')
        efaces=abs(stats['represented']-sf)/max(1,sf)
        eclip=abs(stats['clipped']-sc)/max(1,sc) if sc>0 else (0.0 if stats['clipped']==0 else math.inf)
        eraw=abs(stats['rawMax']-sraw)/max(abs(sraw),1e-30)
        eeff=abs(stats['effMax']-seff)/max(abs(seff),1e-30)
        recon='PASS' if efaces<=.02 and (abs(stats['clipped']-sc)<=3 or eclip<=.10) and eraw<=.10 and eeff<=.03 else 'REVIEW'

        # Plateau data / spurious currents.
        pstart=int(sel['plateauStartStep']); pend=int(sel['plateauEndStep'])
        vr=read_rows(active/'output'/'cuda_static_drop_velocity_0493x9e.csv')
        vv=[r for r in vr if pstart<=int(round(F(r,'step',-1)))<=pend]
        usp_rms=mean([F(r,'interfaceSpeedRms') for r in vv]); usp_max=max([F(r,'interfaceSpeedMax') for r in vv] or [math.nan])
        pr=read_rows(active/'output'/'cuda_static_drop_pressure_0493x9e.csv')
        pp=[r for r in pr if pstart<=int(round(F(r,'step',-1)))<=pend]
        rho=mean([F(r,'rhoLiquidRef') for r in pp]); usigma=math.sqrt(sigma/(rho*reff)) if rho>0 else math.nan
        ured=usp_rms/usigma if usigma>0 else math.nan
        shape=read_rows(active/'output'/'cuda_ellipse_shape_0493x9f.csv') if (active/'output'/'cuda_ellipse_shape_0493x9f.csv').is_file() else []
        ss=[r for r in shape if pstart<=int(round(F(r,'step',-1)))<=pend]
        axis=mean([F(r,'axisRatio') for r in ss]) if ss else math.nan
        ell=mean([F(r,'ellipticity') for r in ss]) if ss else math.nan

        initstates=list((active/'init').glob('*.smpcd'))
        M0=math.nan
        if initstates:
            try: _,M0,_,_=mod.deposit_fill(initstates[0],nx,ny,Lx,Ly,liquid_type,ref)
            except Exception: pass
        mdrift=(Mcp-M0)/M0 if math.isfinite(M0) and M0 else math.nan
        clipfrac=stats['clipped']/max(1,stats['represented'])
        plateau=sel['plateauStatus']
        article_use=int(plateau=='PASS' and recon=='PASS' and (not math.isfinite(axis) or axis<=1.08) and clipfrac<=.10 and (not math.isfinite(mdrift) or abs(mdrift)<=.01) and rad_mismatch<=.005 and area_mismatch<=.01)
        status='PASS' if article_use else 'REVIEW'
        row={
            'case_id':f'R{rc:g}_seed{seed}','seed':seed,'h':dx,'dt':mod.as_float(kv,'dt'),'kBT':0.125,'gamma':8,'alpha_SRC_deg':120,
            'sigma_target':sigma,'R_init':rc*dx,'R_init_over_h':rc,'R_eff':reff,'R_eff_over_h':reff/dx,
            'kappa_th':kth,'kappa_code_mean_signed':keff,'kappa_num_mean':karticle,'kappa_raw_mean_article_sign':kraw_article,
            'kappa_num_std':kstd,'kappa_relative_error':kerr,'capillary_faces':stats['represented'],'clip_fraction':clipfrac,
            'p_L_active_shadow':pL,'p_G_active_shadow':pG,'pressure_jump_active_shadow':pa,'pressure_jump_sigma0_shadow':pz,
            'delta_p_code_signed':dp_code,'delta_p':dp_article,'sigma_eff_local':sigma_local,'delta_p_over_sigma_kappa':gain,
            'U_sp_max':usp_max,'U_sp_rms':usp_rms,'U_sigma':usigma,'U_sp_rms_over_U_sigma':ured,
            'mass_initial':M0,'mass_checkpoint':Mcp,'mass_drift':mdrift,
            'axis_ratio':axis,'ellipticity':ell,'relaxation_start':0,'averaging_start':pstart,'averaging_end':pend,
            'checkpoint_step':cpstep,'Reff_relative_drift':F(sel,'ReffRelativeDrift'),'area_relative_drift':F(sel,'alphaAreaRelativeDrift'),
            'shadow_radius_mismatch':rad_mismatch,'shadow_area_mismatch':area_mismatch,
            'reconstruction_status':recon,'plateau_status':plateau,'article_use':article_use,'status':status,
            'active_run':str(active),'shadow_active_run':m['shadowActiveRoot'],'shadow_sigma0_run':m['shadowZeroRoot'],'checkpoint_state':str(cp)
        }
        reals.append(row)
        validation_lines.append(f"R/h={rc:g} seed={seed}: plateau={plateau} recon={recon} articleUse={article_use} faces={stats['represented']}/{sf} clip={stats['clipped']}/{sc} eRawMax={eraw:.3g} eEffMax={eeff:.3g}")

    art=campaign/'article_capillary_outputs'; data=art/'data'; figs=art/'figures'; tabs=art/'tables'; scr=art/'scripts'
    for d in (data,figs,tabs,scr): d.mkdir(parents=True,exist_ok=True)
    write_csv(data/'capillary_realizations.csv',reals)

    groups=[]
    for rc in sorted({r['R_init_over_h'] for r in reals}):
        rr=[r for r in reals if r['R_init_over_h']==rc]
        use=[r for r in rr if r['article_use']==1]
        src=use if use else rr
        def ms(k): return mean([r[k] for r in src]),sd([r[k] for r in src])
        reff_h,reff_h_sd=ms('R_eff_over_h'); kr,kr_sd=ms('kappa_num_mean'); kth,kth_sd=ms('kappa_th'); ke,ke_sd=ms('kappa_relative_error')
        dp,dp_sd=ms('delta_p'); se,se_sd=ms('sigma_eff_local'); gain,gain_sd=ms('delta_p_over_sigma_kappa'); ur,ur_sd=ms('U_sp_rms'); umax,umax_sd=ms('U_sp_max'); ured,ured_sd=ms('U_sp_rms_over_U_sigma'); clip,clip_sd=ms('clip_fraction')
        groups.append({'R_init_over_h':rc,'n_total':len(rr),'n_article':len(use),'R_eff_over_h_mean':reff_h,'R_eff_over_h_std':reff_h_sd,
                       'kappa_th_mean':kth,'kappa_num_mean':kr,'kappa_num_std_seed':kr_sd,'kappa_num_over_kappa_th':kr/kth if kth else math.nan,
                       'E_kappa_mean':ke,'E_kappa_std_seed':ke_sd,'delta_p_mean':dp,'delta_p_std_seed':dp_sd,
                       'sigma_eff_local_mean':se,'sigma_eff_local_std_seed':se_sd,'sigma_eff_over_sigma_mean':gain,'sigma_eff_over_sigma_std_seed':gain_sd,
                       'U_sp_rms_mean':ur,'U_sp_rms_std_seed':ur_sd,'U_sp_max_mean':umax,'U_sp_max_std_seed':umax_sd,
                       'U_sp_rms_over_U_sigma_mean':ured,'U_sp_rms_over_U_sigma_std_seed':ured_sd,'clip_fraction_mean':clip,'clip_fraction_std_seed':clip_sd,
                       'status':'PASS' if len(use)>=2 else 'REVIEW'})
    write_csv(data/'capillary_aggregated.csv',groups)

    fitgroups=[g for g in groups if g['status']=='PASS' and math.isfinite(g['kappa_num_mean']) and math.isfinite(g['delta_p_mean'])]
    xs=[g['kappa_num_mean'] for g in fitgroups]; ys=[g['delta_p_mean'] for g in fitgroups]
    intercept,slope,r2,slope_se=linfit(xs,ys); slope0,slope0_se=originfit(xs,ys)
    relerr=abs(slope-sigma)/sigma if math.isfinite(slope) else math.nan

    trace=[{'campaign':'0493x21e_article_capillary_radius','binarySha256':binary_sha,'analyzerVersion':ANALYZER_VERSION,'sigmaTarget':sigma,
            'radii':' '.join(f"{g['R_init_over_h']:g}" for g in groups),'realizations':len(reals),'articleRealizations':sum(r['article_use'] for r in reals)}]
    write_csv(data/'capillary_traceability.csv',trace)

    # Main figure requested by Section 3.4 brief.
    try:
        import matplotlib.pyplot as plt
        fig,axs=plt.subplots(1,3,figsize=(12.2,3.7))
        ax=axs[0]
        x=[g['kappa_th_mean'] for g in groups]; y=[g['kappa_num_mean'] for g in groups]; ye=[g['kappa_num_std_seed'] for g in groups]
        ax.errorbar(x,y,yerr=ye,fmt='o',capsize=3,label='numerical')
        lo=min(x+y); hi=max(x+y); ax.plot([lo,hi],[lo,hi],'--',label=r'$\kappa=1/R_{eff}$')
        ax.set_xlabel(r'$1/R_{eff}$'); ax.set_ylabel(r'$\kappa_{num}$'); ax.set_title('(a) Curvature'); ax.legend(fontsize=8)
        ax=axs[1]
        x=[g['kappa_num_mean'] for g in fitgroups]; y=[g['delta_p_mean'] for g in fitgroups]; xe=[g['kappa_num_std_seed'] for g in fitgroups]; ye=[g['delta_p_std_seed'] for g in fitgroups]
        ax.errorbar(x,y,xerr=xe,yerr=ye,fmt='o',capsize=3,label='radius means')
        if x:
            lo=min(x)*.95; hi=max(x)*1.05
            ax.plot([lo,hi],[sigma*lo,sigma*hi],'--',label=rf'$\sigma\kappa$, $\sigma={sigma:g}$')
            if math.isfinite(slope): ax.plot([lo,hi],[intercept+slope*lo,intercept+slope*hi],label=rf'fit $\sigma_{{eff}}={slope:.4g}$')
        ax.set_xlabel(r'$\kappa_{num}$'); ax.set_ylabel(r'$\Delta p_{cap}$'); ax.set_title('(b) Laplace law'); ax.legend(fontsize=8)
        ax=axs[2]
        x=[g['R_eff_over_h_mean'] for g in groups]; y=[g['U_sp_rms_over_U_sigma_mean'] for g in groups]; ye=[g['U_sp_rms_over_U_sigma_std_seed'] for g in groups]
        ax.errorbar(x,y,yerr=ye,fmt='o-',capsize=3)
        ax.set_xlabel(r'$R_{eff}/h$'); ax.set_ylabel(r'$U_{sp,rms}/U_\sigma$'); ax.set_title('(c) Spurious currents')
        fig.tight_layout()
        fig.savefig(figs/'fig_07_capillary_calibration.pdf',bbox_inches='tight')
        fig.savefig(figs/'fig_07_capillary_calibration.png',dpi=220,bbox_inches='tight')
        plt.close(fig)
    except Exception as e:
        (figs/'FIGURE_ERROR.txt').write_text(str(e)+'\n')

    # Compact global article table.
    maxek=max([g['E_kappa_mean'] for g in groups if math.isfinite(g['E_kappa_mean'])] or [math.nan])
    maxu=max([g['U_sp_rms_mean'] for g in groups if math.isfinite(g['U_sp_rms_mean'])] or [math.nan])
    rmin=min([g['R_eff_over_h_mean'] for g in groups]); rmax=max([g['R_eff_over_h_mean'] for g in groups])
    globalrow={'imposed_sigma':sigma,'fitted_sigma_eff':slope,'slope_std_error':slope_se,'relative_error':relerr,'R2':r2,'intercept':intercept,
               'origin_fit_sigma_eff':slope0,'origin_fit_std_error':slope0_se,'R_eff_over_h_min':rmin,'R_eff_over_h_max':rmax,
               'maximum_curvature_error':maxek,'maximum_mean_U_sp_rms':maxu,'radii_used':len(fitgroups)}
    write_csv(tabs/'table_03_capillary_calibration.csv',[globalrow])
    tex='''\\begin{tabular}{ccccccc}\n\\toprule\n$\\sigma$ & $\\sigma_{eff}$ & rel. error & $R^2$ & intercept & $R_{eff}/h$ range & max. $E_\\kappa$ \\\\\n\\midrule\n'''
    tex+=f"{sigma:.6g} & {slope:.6g} & {100*relerr:.3f}\\% & {r2:.6f} & {intercept:.6g} & {rmin:.2f}--{rmax:.2f} & {100*maxek:.2f}\\% \\\\\n"
    tex+='\\bottomrule\n\\end{tabular}\n'
    (tabs/'table_03_capillary_calibration.tex').write_text(tex)

    write_csv(tabs/'table_S3_capillary_map.csv',groups)
    t=['\\begin{tabular}{rrrrrrrr}','\\toprule',r'$R_0/h$ & $R_{eff}/h$ & $\kappa_{num}/\kappa_{th}$ & $E_\kappa$ & $\Delta p$ & $\sigma_{eff}/\sigma$ & $U_{sp,rms}$ & $U_{sp,rms}/U_\sigma$ \\','\\midrule']
    for g in groups:
        t.append(f"{g['R_init_over_h']:.0f} & {g['R_eff_over_h_mean']:.3f} & {g['kappa_num_over_kappa_th']:.4f} & {100*g['E_kappa_mean']:.2f}\\% & {g['delta_p_mean']:.5g} & {g['sigma_eff_over_sigma_mean']:.4f} & {g['U_sp_rms_mean']:.4g} & {g['U_sp_rms_over_U_sigma_mean']:.4f} \\\\")
    t += ['\\bottomrule','\\end{tabular}','']
    (tabs/'table_S3_capillary_map.tex').write_text('\n'.join(t))

    captions=f'''fig_07_capillary_calibration.pdf / .png\n(a) Numerical interface curvature reconstructed with the same x6c/p3/x9r chain used by the Q6 capillary boundary condition, compared with 1/R_eff.\n(b) Paired capillary pressure increment from one-step sigma={sigma:g}/sigma=0 shadow branches versus the reconstructed numerical curvature. The dashed line is Delta p=sigma*kappa; the solid line is the unconstrained fit.\n(c) Interfacial spurious-current RMS normalized by U_sigma=sqrt(sigma/(rho R_eff)). Points are radius means; error bars are +/- one standard deviation over seeds.\nSign convention: the code uses negative curvature and pressure jump for a convex liquid drop with its outward normal; panels (a,b) report the corresponding positive article convention.\n'''
    (art/'capillary_figure_table_captions.txt').write_text(captions)
    (art/'capillary_latex_insertion.tex').write_text('\\includegraphics[width=\\textwidth]{figures/fig_07_capillary_calibration.pdf}\n\n\\input{tables/table_03_capillary_calibration.tex}\n')
    checks=['0493x21e article capillary checks',f'realizations={len(reals)}',f'articleUse={sum(r["article_use"] for r in reals)}',f'radiusGroups={len(groups)}',f'fitRadiusGroups={len(fitgroups)}',f'binarySha256={binary_sha}']+validation_lines
    (art/'capillary_article_checks.txt').write_text('\n'.join(checks)+'\n')
    summary=[
        '0493x21e CAPILLARY ARTICLE SUMMARY',
        f'R_eff/h range={rmin:.6g}..{rmax:.6g}',
        f'sigma_target={sigma:.9g}',
        f'sigma_eff_free_intercept={slope:.9g}',
        f'sigma_eff_relative_error={relerr:.6%}',
        f'intercept={intercept:.9g}',f'R2={r2:.9g}',f'slope_standard_error={slope_se:.9g}',
        f'origin_fit_sigma_eff={slope0:.9g}',
        f'maximum_radius_mean_curvature_error={maxek:.6%}',
        f'maximum_radius_mean_U_sp_rms={maxu:.9g}',
        f'valid_radius_groups_for_primary_fit={len(fitgroups)}/{len(groups)}',
        'Taylor-Culick=not rerun in x21e; reuse qualified data after static calibration.',
        'resolution_control=not yet run; decide from x21e trends.',
        ''
    ]
    (art/'capillary_article_summary.txt').write_text('\n'.join(summary))
    (art/'README.txt').write_text('Article-ready outputs for Section 3.4. Primary pressure observable is the same-checkpoint one-step shadow increment; no long sigma=0 free-drop baseline is used. Curvature is reconstructed offline with the production x6c/p3/x9r chain and checked against the runtime x9r counters.\n')

    # Copy reproducibility scripts if present.
    for name in ('analyze_0493x21e_article_capillary_radius_campaign.py','run_0493x21e_article_capillary_radius_campaign.sh'):
        p=repo/'scripts'/name
        if p.is_file(): shutil.copy2(p,scr/name)
    zpath=campaign/'article_capillary_outputs.zip'
    with zipfile.ZipFile(zpath,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for p in art.rglob('*'):
            if p.is_file(): z.write(p,p.relative_to(campaign))
    print('===== 0493x21e ARTICLE CAPILLARY OUTPUTS =====')
    print(f'realizations={len(reals)} articleUse={sum(r["article_use"] for r in reals)} radiusGroups={len(groups)} fitGroups={len(fitgroups)}')
    print(f'sigmaEff={slope:.9g} +/- {slope_se:.3g} intercept={intercept:.9g} R2={r2:.9g}')
    print(f'outputs={art}')
    print(f'zip={zpath}')


def main():
    ap=argparse.ArgumentParser()
    sub=ap.add_subparsers(dest='cmd',required=True)
    s=sub.add_parser('select-checkpoint')
    s.add_argument('--run-root',type=Path,required=True); s.add_argument('--radius-cells',type=float,required=True); s.add_argument('--seed',type=int,required=True); s.add_argument('--out',type=Path,required=True)
    f=sub.add_parser('final')
    f.add_argument('--repo',type=Path,required=True); f.add_argument('--campaign-root',type=Path,required=True); f.add_argument('--manifest',type=Path,required=True); f.add_argument('--sigma',type=float,required=True); f.add_argument('--binary-sha256',required=True)
    a=ap.parse_args()
    if a.cmd=='select-checkpoint': select_checkpoint(a.run_root,a.radius_cells,a.seed,a.out)
    else: final_analysis(a.repo,a.campaign_root,a.manifest,a.sigma,a.binary_sha256)

if __name__=='__main__': main()

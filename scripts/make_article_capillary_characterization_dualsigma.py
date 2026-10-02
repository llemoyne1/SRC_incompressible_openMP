#!/usr/bin/env python3
"""0493x21n — dual-sigma article capillary characterization.

Purpose: article-only post-processing. No solver run, no compilation, no model change.
Treats sigma=1e4 and sigma=1e3 as two physical capillary-response cases in the
article figure. Internal x12cal metrology gates are retained only in traceability.

No pandas dependency.
"""
from __future__ import annotations
import argparse, csv, hashlib, math, shutil, zipfile
from pathlib import Path

VERSION = "0493x21n-dual-sigma-capillary-article-v1"
BINARY_SHA256 = "422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc"


def read_csv(path: Path):
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows, fields=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    if fields is None:
        fields = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader(); w.writerows(rows)


def f(row, key): return float(row[key])


def sha256(path: Path):
    h=hashlib.sha256()
    with path.open('rb') as fp:
        for block in iter(lambda: fp.read(1<<20), b''): h.update(block)
    return h.hexdigest()


def origin_fit(x,y):
    den=sum(a*a for a in x)
    if den<=0: raise ValueError('zero origin-fit denominator')
    slope=sum(a*b for a,b in zip(x,y))/den
    res=[b-slope*a for a,b in zip(x,y)]
    n=len(x)
    se=math.sqrt(sum(r*r for r in res)/((n-1)*den)) if n>1 else math.nan
    return slope,se


def discover(repo:Path, explicit, candidates, label):
    if explicit:
        p=Path(explicit); p=p if p.is_absolute() else repo/p
        if not p.is_file(): raise SystemExit(f'[x21n] missing {label}: {p}')
        return p.resolve()
    for c in candidates:
        p=repo/c
        if p.is_file(): return p.resolve()
    raise SystemExit('[x21n] cannot locate %s; tried:\n%s'%(label,'\n'.join('  '+str(repo/c) for c in candidates)))


def fixed_fit(times, values, omega, beta):
    cols=[]; t0=times[0]
    for ta in times:
        t=ta-t0; d=math.exp(-beta*t)
        cols.append((d*math.cos(omega*t),d*math.sin(omega*t),1.0))
    A=[[sum(c[i]*c[j] for c in cols) for j in range(3)] for i in range(3)]
    b=[sum(c[i]*y for c,y in zip(cols,values)) for i in range(3)]
    aug=[A[i][:]+[b[i]] for i in range(3)]
    for i in range(3):
        piv=max(range(i,3),key=lambda r:abs(aug[r][i]))
        if abs(aug[piv][i])<1e-18: raise RuntimeError('singular fit')
        aug[i],aug[piv]=aug[piv],aug[i]
        q=aug[i][i]
        for j in range(i,4): aug[i][j]/=q
        for r in range(3):
            if r==i: continue
            q=aug[r][i]
            for j in range(i,4): aug[r][j]-=q*aug[i][j]
    co=[aug[i][3] for i in range(3)]
    pred=[co[0]*c[0]+co[1]*c[1]+co[2] for c in cols]
    ym=sum(values)/len(values)
    sse=sum((a-b)**2 for a,b in zip(values,pred)); sst=sum((a-ym)**2 for a in values)
    r2=1-sse/sst if sst>0 else math.nan
    return pred,r2


def trace_for_mode(rows, mode_row):
    nfit=int(float(mode_row['fitFramesEnsemble']))
    if len(rows)<nfit: raise SystemExit(f'[x21n] trace too short ({len(rows)} < {nfit})')
    rr=rows[:nfit]
    t=[float(r['time']) for r in rr]; y=[float(r['modePrimary']) for r in rr]
    pred,r2=fixed_fit(t,y,float(mode_row['omegaFitEnsemble']),float(mode_row['betaFitEnsemble']))
    r2stored=float(mode_row['fitR2Ensemble'])
    if abs(r2-r2stored)>2e-6:
        raise SystemExit(f'[x21n] fit reproduction mismatch stored={r2stored:.12g} reproduced={r2:.12g}')
    norm=y[0]
    if abs(norm)<1e-14: norm=max(abs(v) for v in y)
    t0=t[0]; Tth=2*math.pi/float(mode_row['omegaTheoryDeclared'])
    out=[]
    for ta,yy,pp in zip(t,y,pred):
        out.append({'tau_theory':f'{(ta-t0)/Tth:.15g}','time':f'{ta-t0:.15g}',
                    'normalized_amplitude':f'{yy/norm:.15g}','normalized_fit':f'{pp/norm:.15g}'})
    return out,r2stored


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--repo',type=Path,default=Path('.'))
    ap.add_argument('--preflight',action='store_true')
    ap.add_argument('--output-dir',default='runs/0493x21n_article_capillary_dualsigma/article_capillary_outputs_v3_dualsigma')
    args=ap.parse_args(); repo=args.repo.resolve()

    static_base=Path('runs/0493x21e_article_capillary_radius_s10000/article_capillary_review_fix3/data')
    hi_base=Path('runs/0493x21g_article_capillary_wave_n234_ensemble_seed4932501_4933501_4934501/analysis')
    lo_base=Path('runs/0493x21i_article_capillary_sigma1000_n3_ensemble/analysis')
    static_means=discover(repo,None,[static_base/'capillary_review_radius_means.csv'],'static radius means')
    static_real=discover(repo,None,[static_base/'capillary_review_realizations.csv'],'static realizations')
    hi_sum=discover(repo,None,[hi_base/'capillary_calibration_0493x12cal.csv'],'sigma=10000 summary')
    hi_modes=discover(repo,None,[hi_base/'capillary_calibration_modes_0493x12cal.csv'],'sigma=10000 modes')
    hi_cases=discover(repo,None,[hi_base/'capillary_calibration_cases_0493x12cal.csv'],'sigma=10000 cases')
    hi_trace=discover(repo,None,[hi_base/'traces/mode_n3_ensemble_trace.csv'],'sigma=10000 n3 trace')
    lo_sum=discover(repo,None,[lo_base/'capillary_calibration_0493x12cal.csv'],'sigma=1000 summary')
    lo_modes=discover(repo,None,[lo_base/'capillary_calibration_modes_0493x12cal.csv'],'sigma=1000 modes')
    lo_cases=discover(repo,None,[lo_base/'capillary_calibration_cases_0493x12cal.csv'],'sigma=1000 cases')
    lo_trace=discover(repo,None,[lo_base/'traces/mode_n3_ensemble_trace.csv'],'sigma=1000 n3 trace')

    S=read_csv(static_means); SR=read_csv(static_real)
    DH=read_csv(hi_sum); MH=read_csv(hi_modes); CH=read_csv(hi_cases); TH=read_csv(hi_trace)
    DL=read_csv(lo_sum); ML=read_csv(lo_modes); CL=read_csv(lo_cases); TL=read_csv(lo_trace)
    if len(S)!=6 or len(SR)!=18: raise SystemExit('[x21n] static dataset size mismatch')
    if len(DH)!=1 or len(DL)!=1: raise SystemExit('[x21n] dynamic summary size mismatch')
    if sorted(int(float(r['mode'])) for r in MH)!=[2,3,4]: raise SystemExit('[x21n] sigma=10000 modes mismatch')
    if [int(float(r['mode'])) for r in ML]!=[3]: raise SystemExit('[x21n] sigma=1000 dataset must contain only n=3')
    dh,dl=DH[0],DL[0]; m3h=next(r for r in MH if int(float(r['mode']))==3); m3l=ML[0]

    # Strict apples-to-apples physics checks. The x12cal status is intentionally NOT an article gate here.
    same_keys=['rhoReference','Lx','Ly','Nx','Ny','cellSize','gamma','particleMass','kBT','meanDepth','amplitudeCells','minRadiusCells','x12aRadiusCells','kinematicViscosity','heightEstimator']
    for k in same_keys:
        if str(dh[k])!=str(dl[k]):
            # numeric formatting can differ; accept numerically equal values
            try:
                if abs(float(dh[k])-float(dl[k]))<=1e-12*max(1.0,abs(float(dh[k]))): continue
            except Exception: pass
            raise SystemExit(f'[x21n] physics mismatch for {k}: {dh[k]} vs {dl[k]}')
    if abs(float(dh['sigmaDeclared'])/float(dl['sigmaDeclared'])-10.0)>1e-12: raise SystemExit('[x21n] sigma ratio is not 10')
    if float(m3h['fitR2Ensemble'])<0.99 or float(m3l['fitR2Ensemble'])<0.99: raise SystemExit('[x21n] n=3 damped-oscillation fit R2 below 0.99')

    sigma_h=float(dh['sigmaDeclared']); sigma_l=float(dl['sigmaDeclared'])
    om_h=float(m3h['omegaFitEnsemble']); om_l=float(m3l['omegaFitEnsemble'])
    omth_h=float(m3h['omegaTheoryDeclared']); omth_l=float(m3l['omegaTheoryDeclared'])
    ratio_meas=om_l/om_h; ratio_theory=math.sqrt(sigma_l/sigma_h); ratio_rel=ratio_meas/ratio_theory-1.0

    if args.preflight:
        print(f'[x21n] PRELIGHT PASS version={VERSION}')
        print(f'[x21n] sigmaHigh={sigma_h:g} sigmaLow={sigma_l:g}')
        print(f'[x21n] n3 R2 high/low={float(m3h["fitR2Ensemble"]):.9g}/{float(m3l["fitR2Ensemble"]):.9g}')
        print(f'[x21n] omegaLow/omegaHigh={ratio_meas:.12g} theory={ratio_theory:.12g} relativeError={ratio_rel:.6%}')
        return

    out=(repo/args.output_dir).resolve()
    if out.exists(): shutil.rmtree(out)
    for sub in ['figures','tables','data','scripts']: (out/sub).mkdir(parents=True,exist_ok=True)

    h=float(dh['cellSize']); rho=float(dh['rhoReference']); kBT=float(dh['kBT']); m=float(dh['particleMass']); gamma=float(dh['gamma']); a_cells=float(dh['amplitudeCells']); a=a_cells*h
    vth=math.sqrt(kBT/m); vcell=math.sqrt(kBT/(gamma*m))

    # Static geometry.
    static_rows=[]; xk=[]; yk=[]; yerr=[]
    for r in S:
        reff_h=f(r,'R_eff_over_h_mean'); reff=reff_h*h; inv=1/reff; kn=abs(f(r,'kappa_num_signed_mean')); ks=f(r,'kappa_num_signed_std_seed'); kth=inv
        static_rows.append({'R_eff':f'{reff:.15g}','R_eff_over_h':f'{reff_h:.15g}','inv_R_eff':f'{inv:.15g}','kappa_mean':f'{kn:.15g}','kappa_seed_std':f'{ks:.15g}','G_kappa':f'{kn/kth:.15g}','E_kappa':f'{abs(kn-kth)/kth:.15g}'})
        xk.append(inv); yk.append(kn); yerr.append(ks)
    Gk,Gk_se=origin_fit(xk,yk); write_csv(out/'data/capillary_article_static.csv',static_rows)

    # Wave rows: all three high-sigma modes plus low-sigma n=3, with identical scientific role.
    wave=[]
    for r in sorted(MH,key=lambda z:int(float(z['mode']))):
        om=float(r['omegaFitEnsemble']); oth=float(r['omegaTheoryDeclared']); sg=float(r['surfaceTensionGainEnsemble'])
        wave.append({'sigma_declared':f'{sigma_h:.15g}','mode':int(float(r['mode'])),'k':r['wavenumber'],'H':dh['meanDepth'],'omega_meas':r['omegaFitEnsemble'],'omega_theory':r['omegaTheoryDeclared'],'omega_ratio':f'{om/oth:.15g}','G_dynamic':r['surfaceTensionGainEnsemble'],'fit_R2':r['fitR2Ensemble'],'seed_gain_std':r['seedGainStd'],'internal_x12cal_status':r['status'],'article_role':'capillary_surface-tension_response'})
    r=m3l; om=float(r['omegaFitEnsemble']); oth=float(r['omegaTheoryDeclared'])
    wave.append({'sigma_declared':f'{sigma_l:.15g}','mode':3,'k':r['wavenumber'],'H':dl['meanDepth'],'omega_meas':r['omegaFitEnsemble'],'omega_theory':r['omegaTheoryDeclared'],'omega_ratio':f'{om/oth:.15g}','G_dynamic':r['surfaceTensionGainEnsemble'],'fit_R2':r['fitR2Ensemble'],'seed_gain_std':r['seedGainStd'],'internal_x12cal_status':r['status'],'article_role':'capillary_surface-tension_response'})
    write_csv(out/'data/capillary_wave_article_dualsigma.csv',wave)

    # Actual n=3 traces for both sigma values, normalized by their own theoretical periods.
    trh,r2h=trace_for_mode(TH,m3h); trl,r2l=trace_for_mode(TL,m3l)
    dual=[]
    for rr in trh: dual.append({'sigma_declared':f'{sigma_h:.15g}',**rr})
    for rr in trl: dual.append({'sigma_declared':f'{sigma_l:.15g}',**rr})
    write_csv(out/'data/capillary_wave_trace_n3_dualsigma.csv',dual)

    # Cross-sigma summary and thermal agitation metrics.
    uh=a*om_h; ul=a*om_l
    cross=[{
        'sigma_high':sigma_h,'sigma_low':sigma_l,'mode':3,'same_kBT':kBT,'same_amplitude_cells':a_cells,
        'omega_high':om_h,'omega_low':om_l,'omega_low_over_high':ratio_meas,'sqrt_sigma_ratio':ratio_theory,'relative_scaling_error':ratio_rel,
        'R2_high':float(m3h['fitR2Ensemble']),'R2_low':float(m3l['fitR2Ensemble']),
        'v_thermal_1D':vth,'v_cell_mean_thermal_scale':vcell,'aomega_high':uh,'aomega_low':ul,
        'aomega_over_vthermal_high':uh/vth,'aomega_over_vthermal_low':ul/vth,
        'aomega_over_vcell_high':uh/vcell,'aomega_over_vcell_low':ul/vcell,
    }]
    write_csv(out/'data/capillary_cross_sigma_summary.csv',cross)

    # Traceability retains historical x12cal status, but it is not used as article classification.
    trace=[]
    for r in CH:
        trace.append({'dataset':'wave_sigma10000','sigma_declared':sigma_h,'mode':r.get('mode',''),'seed':r.get('seed',''),'internal_case':r.get('case',''),'source_path':r.get('trace',''),'binary_sha256':BINARY_SHA256,'internal_x12cal_status':r.get('status',''),'article_role':'capillary_surface-tension_response'})
    for r in CL:
        trace.append({'dataset':'wave_sigma1000','sigma_declared':sigma_l,'mode':r.get('mode',''),'seed':r.get('seed',''),'internal_case':r.get('case',''),'source_path':r.get('trace',''),'binary_sha256':BINARY_SHA256,'internal_x12cal_status':r.get('status',''),'article_role':'capillary_surface-tension_response'})
    write_csv(out/'data/capillary_article_traceability_dualsigma.csv',trace)

    # Figure 5.
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    matplotlib.rcParams.update({'font.size':8,'axes.labelsize':8,'xtick.labelsize':7,'ytick.labelsize':7,'legend.fontsize':6.5,'pdf.fonttype':42,'ps.fonttype':42})
    fig,axs=plt.subplots(1,3,figsize=(7.35,2.6),constrained_layout=True)
    ax=axs[0]
    ax.errorbar(xk,yk,yerr=yerr,fmt='o',capsize=2.2,label='reconstructed')
    hi=max(xk)*1.06; ax.plot([0,hi],[0,hi],'--',linewidth=1.0,label='ideal')
    ax.plot([0,hi],[0,Gk*hi],'-',linewidth=1.0,label=rf'fit: $G_\kappa={Gk:.3f}$')
    ax.set_xlabel(r'$1/R_{\rm eff}$'); ax.set_ylabel(r'reconstructed $|\kappa|$'); ax.set_xlim(left=0); ax.set_ylim(bottom=0); ax.legend(frameon=False); ax.text(.02,.98,'(a)',transform=ax.transAxes,ha='left',va='top',fontweight='bold')

    ax=axs[1]
    thx=[float(r['tau_theory']) for r in trh]; thy=[float(r['normalized_amplitude']) for r in trh]; thp=[float(r['normalized_fit']) for r in trh]
    tlx=[float(r['tau_theory']) for r in trl]; tly=[float(r['normalized_amplitude']) for r in trl]; tlp=[float(r['normalized_fit']) for r in trl]
    ax.plot(thx,thy,'o',markersize=2.0,label=rf'$\sigma={sigma_h:.0f}$ data')
    ax.plot(thx,thp,'-',linewidth=1.1,label=rf'$\sigma={sigma_h:.0f}$ fit')
    ax.plot(tlx,tly,'s',markersize=1.9,label=rf'$\sigma={sigma_l:.0f}$ data')
    ax.plot(tlx,tlp,'--',linewidth=1.1,label=rf'$\sigma={sigma_l:.0f}$ fit')
    ax.set_xlabel(r'$t/T_{\rm th}$'); ax.set_ylabel(r'$A(t)/A(0)$')
    ax.text(.98,.97,rf'$n=3$, $a=2h$'+'\n'+rf'$R^2={r2h:.4f}$ / ${r2l:.4f}$',transform=ax.transAxes,ha='right',va='top',fontsize=6.5)
    ax.legend(frameon=False,loc='lower left',ncol=1); ax.text(.02,.98,'(b)',transform=ax.transAxes,ha='left',va='top',fontweight='bold')

    ax=axs[2]
    X=[];Y=[]; grp=[]; labels=[]
    for rr in wave:
        x=float(rr['omega_theory'])**2; y=float(rr['omega_meas'])**2
        X.append(x);Y.append(y);grp.append(float(rr['sigma_declared']));labels.append(int(rr['mode']))
    # same scientific footing; only marker shape distinguishes declared sigma.
    for sig,marker in [(sigma_h,'o'),(sigma_l,'s')]:
        xs=[x for x,g in zip(X,grp) if g==sig]; ys=[y for y,g in zip(Y,grp) if g==sig]
        ax.plot(xs,ys,marker,linestyle='None',markersize=5,label=rf'$\sigma={sig:.0f}$')
        for x,y,n,g in zip(X,Y,labels,grp):
            if g==sig: ax.annotate(f'n={n}',(x,y),xytext=(3,3),textcoords='offset points',fontsize=6.2)
    xmin=min(X)*0.75; xmax=max(X)*1.25
    ax.plot([xmin,xmax],[xmin,xmax],'--',linewidth=1.0,label='finite-depth capillary law')
    Gall,_=origin_fit(X,Y); ax.plot([xmin,xmax],[Gall*xmin,Gall*xmax],'-',linewidth=1.0,label=rf'all-point fit: $G={Gall:.3f}$')
    ax.set_xscale('log'); ax.set_yscale('log'); ax.set_xlim(xmin,xmax); ax.set_ylim(min(min(Y)*0.75,xmin),max(max(Y)*1.25,xmax))
    ax.set_xlabel(r'$(\sigma/\rho)k^3\tanh(kH)=\omega_{\rm th}^2$'); ax.set_ylabel(r'$\omega_{\rm meas}^2$')
    ax.text(.98,.04,rf'$\omega_{{10^3}}/\omega_{{10^4}}={ratio_meas:.4f}$'+'\n'+rf'$\sqrt{{10^3/10^4}}={ratio_theory:.4f}$',transform=ax.transAxes,ha='right',va='bottom',fontsize=6.3)
    ax.legend(frameon=False,loc='upper left'); ax.text(.02,.98,'(c)',transform=ax.transAxes,ha='left',va='top',fontweight='bold')
    fig.savefig(out/'figures/fig_05_capillary_characterization_dualsigma.pdf',bbox_inches='tight')
    fig.savefig(out/'figures/fig_05_capillary_characterization_dualsigma.png',dpi=300,bbox_inches='tight'); plt.close(fig)

    # Table 3: equal columns for the two declared sigma values.
    rows=[
      ('Declared surface tension',f'{sigma_h:.0f}',f'{sigma_l:.0f}'),
      ('$k_BT$',f'{kBT:.3f}',f'{kBT:.3f}'),
      (r'$\sqrt{k_BT/m}$',f'{vth:.4f}',f'{vth:.4f}'),
      ('Representative mode','$n=3$','$n=3$'),
      ('Initial amplitude','$2h$','$2h$'),
      (r'$\omega_{\rm th}$',f'{omth_h:.5f}',f'{omth_l:.5f}'),
      (r'$\omega_{\rm meas}$',f'{om_h:.5f}',f'{om_l:.5f}'),
      (r'$\omega_{\rm meas}/\omega_{\rm th}$',f'{om_h/omth_h:.5f}',f'{om_l/omth_l:.5f}'),
      ('Damped-fit $R^2$',f'{r2h:.6f}',f'{r2l:.6f}'),
      (r'$G_{\omega^2}=(\omega_{\rm meas}/\omega_{\rm th})^2$',f'{(om_h/omth_h)**2:.5f}',f'{(om_l/omth_l)**2:.5f}'),
      (r'$a\omega_{\rm meas}/\sqrt{k_BT/m}$',f'{uh/vth:.4f}',f'{ul/vth:.4f}'),
      (r'$a\omega_{\rm meas}/\sqrt{k_BT/(\gamma m)}$',f'{uh/vcell:.4f}',f'{ul/vcell:.4f}'),
    ]
    tcsv=out/'tables/table_03_capillary_characterization_dualsigma.csv'
    with tcsv.open('w',newline='',encoding='utf-8') as fp:
        w=csv.writer(fp); w.writerow(['Quantity',f'sigma={sigma_h:.0f}',f'sigma={sigma_l:.0f}']); w.writerows([(q,a,b) for q,a,b in rows]);
        w.writerow(['Cross-sigma frequency ratio',f'{ratio_meas:.8f}',f'theory {ratio_theory:.8f}']); w.writerow(['Relative scaling error',f'{100*ratio_rel:.3f}%',''])
        w.writerow(['Static curvature gain G_kappa',f'{Gk:.4f} +/- {Gk_se:.4f}','same reconstruction'])
    tex=['\\begin{table}[t]','\\centering','\\caption{Static-interface geometry and capillary-wave response for two declared surface-tension values at the same thermal state.}','\\label{tab:capillary_characterization}','\\begin{tabular}{lcc}','\\hline',f'Quantity & $\\sigma={sigma_h:.0f}$ & $\\sigma={sigma_l:.0f}$ \\\\','\\hline']
    tex += [f'{q} & {a1} & {b1} \\\\' for q,a1,b1 in rows]
    tex += ['\\hline',f'$\\omega_{{10^3}}/\\omega_{{10^4}}$ & \\multicolumn{{2}}{{c}}{{{ratio_meas:.5f} (theory: {ratio_theory:.5f})}} \\\\',f'Relative scaling error & \\multicolumn{{2}}{{c}}{{{100*ratio_rel:.2f}\\%}} \\\\',f'Static curvature gain $G_\\kappa$ & \\multicolumn{{2}}{{c}}{{{Gk:.3f} $\\pm$ {Gk_se:.3f}}} \\\\','\\hline','\\end{tabular}','\\end{table}','']
    (out/'tables/table_03_capillary_characterization_dualsigma.tex').write_text('\n'.join(tex),encoding='utf-8')

    caption=(
      "Capillary characterization of the particle/field free-surface closure at two declared surface-tension values under the same thermal state. "
      "(a) Reconstructed curvature magnitude of equilibrated circular interfaces versus inverse effective radius; symbols are three-realization means, error bars one standard deviation, the dashed line is $|\\kappa|=1/R_{\\rm eff}$, and the solid line is the origin-constrained reconstruction fit. "
      "(b) Ensemble-averaged $n=3$ capillary-wave responses for $\\sigma=10^4$ and $10^3$, initialized with the same amplitude $a=2h$ and plotted against time normalized by each theoretical capillary period. Damped-oscillation fits give $R^2=%.4f$ and %.4f, respectively. "
      "(c) Measured squared angular frequency versus the finite-depth capillary prediction $(\\sigma/\\rho)k^3\\tanh(kH)$, including the three resolved modes at $\\sigma=10^4$ and the same intermediate mode at $\\sigma=10^3$. The dashed line is the capillary law and the solid line the origin-constrained fit to all displayed points. For $n=3$, reducing $\\sigma$ by one decade changes the measured frequency by a factor %.4f, compared with the capillary prediction $\\sqrt{0.1}=%.4f$. The low-$\\sigma$ response occurs at the same $k_BT=0.125$, where the coherent wave velocity is substantially smaller relative to the thermal particle-velocity scale."
      %(r2h,r2l,ratio_meas,ratio_theory))
    (out/'capillary_figure_caption.txt').write_text(caption+'\n',encoding='utf-8')
    latex=('\\begin{figure*}[t]\n\\centering\n\\includegraphics[width=\\textwidth]{figures/fig_05_capillary_characterization_dualsigma.pdf}\n\\caption{'+caption+'}\n\\label{fig:capillary_characterization}\n\\end{figure*}\n')
    (out/'capillary_latex_insertion.tex').write_text(latex,encoding='utf-8')

    summary=(f"""STATIC:\n- radius groups/seeds: 6/3 (18 realizations)\n- G_kappa,0 = {Gk:.9f} +/- {Gk_se:.9f}\n\nDYNAMIC SURFACE-TENSION RESPONSE:\n- same thermal state: kBT={kBT:.12g}, gamma={gamma:.12g}, m={m:.12g}\n- thermal velocity sqrt(kBT/m)={vth:.12g}\n- sigma={sigma_h:.12g}, n=3: omega={om_h:.12g}, omega/theory={om_h/omth_h:.12g}, R2={r2h:.12g}, G_omega2={(om_h/omth_h)**2:.12g}\n- sigma={sigma_l:.12g}, n=3: omega={om_l:.12g}, omega/theory={om_l/omth_l:.12g}, R2={r2l:.12g}, G_omega2={(om_l/omth_l)**2:.12g}\n- omega_low/omega_high={ratio_meas:.12g}\n- sqrt(sigma_low/sigma_high)={ratio_theory:.12g}\n- relative scaling error={ratio_rel:.12g}\n- a*omega/vthermal: high={uh/vth:.12g}, low={ul/vth:.12g}\n- a*omega/vcellthermal: high={uh/vcell:.12g}, low={ul/vcell:.12g}\n\nARTICLE INTERPRETATION:\n- both sigma values are treated as capillary surface-tension responses in the figure and main table.\n- historical x12cal metrology statuses remain only in traceability and are not used as article labels.\n- sigma=1e4 additionally provides the three-mode quantitative dispersion map n=2,3,4.\n""")
    (out/'capillary_article_summary.txt').write_text(summary,encoding='utf-8')

    checks=[f'version={VERSION}',f'staticMeansSha256={sha256(static_means)}',f'highSummarySha256={sha256(hi_sum)}',f'highModesSha256={sha256(hi_modes)}',f'highTraceSha256={sha256(hi_trace)}',f'lowSummarySha256={sha256(lo_sum)}',f'lowModesSha256={sha256(lo_modes)}',f'lowTraceSha256={sha256(lo_trace)}',f'n3R2High={r2h:.12g}',f'n3R2Low={r2l:.12g}',f'crossSigmaMeasuredRatio={ratio_meas:.12g}',f'crossSigmaTheoryRatio={ratio_theory:.12g}',f'crossSigmaRelativeError={ratio_rel:.12g}',f'allPointOriginGain={Gall:.12g}','x12calMetrologyStatusUsedAsArticleLabel=false','solverModified=false','newSimulationRun=false','']
    (out/'capillary_article_checks.txt').write_text('\n'.join(checks),encoding='utf-8')
    readme=(f"""article_capillary_outputs_v3_dualsigma — {VERSION}\n\nArticle framing\n---------------\nThe figure and main table treat sigma=10000 and sigma=1000 on equal scientific footing as observed capillary surface-tension responses. The controlled comparison uses the same n=3 mode, a=2h, kBT=0.125, gamma, density, geometry, thermostat, reconstruction, and production capillary path; only the declared sigma changes by one decade.\n\nThe key cross-sigma observation is omega_low/omega_high={ratio_meas:.8f}, versus sqrt(0.1)={ratio_theory:.8f} (relative difference {100*ratio_rel:.3f}%). Damped-wave R2 values are {r2h:.6f} and {r2l:.6f}.\n\nInternal x12cal PASS/REVIEW/INVALID labels answer a stricter frequency-metrology question and are retained only in the traceability CSV. They are not shown as article classifications.\n\nNo solver code is modified and no simulation is launched.\n""")
    (out/'README.txt').write_text(readme,encoding='utf-8')
    shutil.copy2(Path(__file__),out/'scripts/make_article_capillary_characterization_dualsigma.py')

    zpath=out.parent/'article_capillary_outputs_v3_dualsigma.zip'
    if zpath.exists(): zpath.unlink()
    with zipfile.ZipFile(zpath,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for p in sorted(out.rglob('*')):
            if p.is_file(): z.write(p,Path('article_capillary_outputs_v3_dualsigma')/p.relative_to(out))
    print(f'[x21n] PASS dual-sigma article output: ratio={ratio_meas:.8f}, theory={ratio_theory:.8f}, rel={100*ratio_rel:.3f}%')
    print(f'[x21n] output={out}')
    print(f'[x21n] zip={zpath}')

if __name__=='__main__': main()

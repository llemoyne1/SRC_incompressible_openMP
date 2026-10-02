#!/usr/bin/env python3
"""0493x21h — article-only capillary characterization finalization.

Consumes frozen x21e static-drop review data and frozen x21g/x12cal capillary-wave
calibration data. Generates Figure 5, Table 3, article CSVs and traceability.
No solver data are modified and no simulation is run.

No pandas dependency.
"""
from __future__ import annotations
import argparse, csv, hashlib, math, shutil, sys, zipfile
from pathlib import Path

VERSION = "0493x21h-article-capillary-finalization-v1"
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


def f(row, key):
    return float(row[key])


def sha256(path: Path):
    h = hashlib.sha256()
    with path.open("rb") as fp:
        for block in iter(lambda: fp.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def origin_fit(x, y):
    den = sum(a*a for a in x)
    if den <= 0:
        raise ValueError("origin fit has zero denominator")
    slope = sum(a*b for a, b in zip(x, y)) / den
    residuals = [b - slope*a for a, b in zip(x, y)]
    n = len(x)
    se = math.sqrt(sum(r*r for r in residuals) / ((n-1)*den)) if n > 1 else math.nan
    return slope, se


def stdev(values):
    if len(values) < 2: return 0.0
    m = sum(values)/len(values)
    return math.sqrt(sum((x-m)**2 for x in values)/(len(values)-1))


def discover(repo: Path, explicit: str|None, candidates, label):
    if explicit:
        p = Path(explicit)
        if not p.is_absolute(): p = repo/p
        if not p.is_file(): raise SystemExit(f"[x21h] missing {label}: {p}")
        return p.resolve()
    for c in candidates:
        p = repo/c
        if p.is_file(): return p.resolve()
    raise SystemExit("[x21h] cannot locate %s; tried:\n%s" % (label, "\n".join("  "+str(repo/c) for c in candidates)))


def linear_coefficients_for_fixed_omega_beta(times, values, omega, beta):
    # 3x3 normal equations for C exp(-bt)cos(wt) + S exp(-bt)sin(wt) + offset
    cols=[]
    t0=times[0]
    for ta in times:
        t=ta-t0; d=math.exp(-beta*t)
        cols.append((d*math.cos(omega*t), d*math.sin(omega*t), 1.0))
    A=[[sum(c[i]*c[j] for c in cols) for j in range(3)] for i in range(3)]
    b=[sum(c[i]*y for c,y in zip(cols,values)) for i in range(3)]
    # Gaussian elimination
    aug=[A[i][:]+[b[i]] for i in range(3)]
    for i in range(3):
        piv=max(range(i,3), key=lambda r: abs(aug[r][i]))
        if abs(aug[piv][i]) < 1e-18: raise RuntimeError("singular fixed-frequency fit")
        aug[i],aug[piv]=aug[piv],aug[i]
        q=aug[i][i]
        for j in range(i,4): aug[i][j]/=q
        for r in range(3):
            if r==i: continue
            q=aug[r][i]
            for j in range(i,4): aug[r][j]-=q*aug[i][j]
    coeff=[aug[i][3] for i in range(3)]
    pred=[coeff[0]*c[0]+coeff[1]*c[1]+coeff[2] for c in cols]
    ym=sum(values)/len(values)
    sse=sum((a-bb)**2 for a,bb in zip(values,pred))
    sst=sum((a-ym)**2 for a in values)
    r2=1-sse/sst if sst>0 else math.nan
    return coeff,pred,r2


def latex_escape(s):
    return str(s).replace("%", r"\%").replace("_", r"\_")


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--repo", type=Path, default=Path("."))
    ap.add_argument("--static-means")
    ap.add_argument("--static-realizations")
    ap.add_argument("--dynamic-summary")
    ap.add_argument("--dynamic-modes")
    ap.add_argument("--dynamic-cases")
    ap.add_argument("--n3-trace")
    ap.add_argument("--output-dir", default="runs/0493x21h_article_capillary_outputs_v2/article_capillary_outputs_v2")
    ap.add_argument("--preflight", action="store_true")
    args=ap.parse_args()
    repo=args.repo.resolve()
    campaign_static=Path("runs/0493x21e_article_capillary_radius_s10000")
    campaign_dyn=Path("runs/0493x21g_article_capillary_wave_n234_ensemble_seed4932501_4933501_4934501/analysis")

    static_means=discover(repo,args.static_means,[
        campaign_static/"article_capillary_review_fix3/data/capillary_review_radius_means.csv",
    ],"x21e fix3 radius means")
    static_real=discover(repo,args.static_realizations,[
        campaign_static/"article_capillary_review_fix3/data/capillary_review_realizations.csv",
    ],"x21e fix3 realizations")
    dyn_summary=discover(repo,args.dynamic_summary,[campaign_dyn/"capillary_calibration_0493x12cal.csv"],"x21g dynamic summary")
    dyn_modes=discover(repo,args.dynamic_modes,[campaign_dyn/"capillary_calibration_modes_0493x12cal.csv"],"x21g mode summary")
    dyn_cases=discover(repo,args.dynamic_cases,[campaign_dyn/"capillary_calibration_cases_0493x12cal.csv"],"x21g case summary")
    n3_trace=discover(repo,args.n3_trace,[campaign_dyn/"traces/mode_n3_ensemble_trace.csv"],"x21g n=3 ensemble trace")

    S=read_csv(static_means); SR=read_csv(static_real); D=read_csv(dyn_summary); M=read_csv(dyn_modes); C=read_csv(dyn_cases); T=read_csv(n3_trace)
    if len(S)!=6: raise SystemExit(f"[x21h] expected 6 static radius groups, found {len(S)}")
    if len(SR)!=18: raise SystemExit(f"[x21h] expected 18 static realizations, found {len(SR)}")
    if len(D)!=1: raise SystemExit(f"[x21h] expected one dynamic summary row, found {len(D)}")
    if sorted(int(float(r['mode'])) for r in M)!=[2,3,4]: raise SystemExit("[x21h] modes are not exactly 2,3,4")
    if len(C)!=9: raise SystemExit(f"[x21h] expected 9 dynamic cases, found {len(C)}")
    d=D[0]
    if d.get("status")!="PASS": raise SystemExit(f"[x21h] global dynamic calibration is not PASS: {d.get('status')}")
    if any(r.get("status")!="PASS" for r in M): raise SystemExit("[x21h] at least one mode ensemble is not PASS")
    if float(d['surfaceTensionGainModeRelativeStd'])>0.05: raise SystemExit("[x21h] cross-mode spread exceeds frozen 5% criterion")
    if float(d['meanFitR2'])<0.98: raise SystemExit("[x21h] mean fit R2 below frozen criterion")
    if args.preflight:
        print(f"[x21h] PRELIGHT PASS version={VERSION}")
        for name,p in [("staticMeans",static_means),("staticRealizations",static_real),("dynamicSummary",dyn_summary),("dynamicModes",dyn_modes),("dynamicCases",dyn_cases),("n3Trace",n3_trace)]:
            print(f"[x21h] {name}={p}")
        print(f"[x21h] Gsigma={float(d['surfaceTensionGain']):.12g} sigmaEff={float(d['surfaceTensionEffective']):.12g}")
        return

    out=(repo/args.output_dir).resolve();
    if out.exists(): shutil.rmtree(out)
    for sub in ["figures","tables","data","scripts"]: (out/sub).mkdir(parents=True,exist_ok=True)

    h=float(d['cellSize']); nu=float(d['kinematicViscosity']); rho=float(d['rhoReference']); sigma_decl=float(d['sigmaDeclared']); sigma_eff=float(d['surfaceTensionEffective']); Gsigma=float(d['surfaceTensionGain'])

    # Article static CSV, magnitudes by explicit final-paper convention.
    static_rows=[]
    xk=[]; yk=[]
    for r in S:
        reff_h=f(r,'R_eff_over_h_mean'); reff=reff_h*h; inv=1/reff
        kn_signed=f(r,'kappa_num_signed_mean'); kn=abs(kn_signed); kstd=f(r,'kappa_num_signed_std_seed')
        kth=1/reff; gain=kn/kth; err=abs(kn-kth)/kth
        static_rows.append({
            'R_eff':f"{reff:.15g}",'R_eff_over_h':f"{reff_h:.15g}",'inv_R_eff':f"{inv:.15g}",
            'kappa_mean':f"{kn:.15g}",'kappa_seed_std':f"{kstd:.15g}",'G_kappa':f"{gain:.15g}",'E_kappa':f"{err:.15g}",
        })
        xk.append(inv); yk.append(kn)
    Gk,Gk_se=origin_fit(xk,yk)
    write_csv(out/'data/capillary_article_static.csv',static_rows)

    # Article dynamic CSV.
    mode_rows=[]
    for r in sorted(M,key=lambda z:int(float(z['mode']))):
        mode_rows.append({
            'mode':int(float(r['mode'])),'k':r['wavenumber'],'H':d['meanDepth'],
            'omega_meas':r['omegaFitEnsemble'],
            'omega_uncertainty':str(0.5*float(r['omegaFitEnsemble'])*float(r['seedGainStd'])/float(r['surfaceTensionGainEnsemble'])),
            'omega_theory_declared':r['omegaTheoryDeclared'],'sigma_eff_mode':r['sigmaEffectiveEnsemble'],
            'G_sigma_mode':r['surfaceTensionGainEnsemble'],'fit_R2':r['fitR2Ensemble'],'status':r['status']
        })
    write_csv(out/'data/capillary_wave_article.csv',mode_rows)

    # Representative n=3 trace, use exactly the frozen production fit frame count.
    m3=next(r for r in M if int(float(r['mode']))==3)
    nfit=int(float(m3['fitFramesEnsemble']))
    if len(T)<nfit: raise SystemExit(f"[x21h] n=3 trace has {len(T)} rows but fit requires {nfit}")
    fitT=T[:nfit]
    times=[float(r['time']) for r in fitT]; vals=[float(r['modePrimary']) for r in fitT]
    coeff,pred,r2_repro=linear_coefficients_for_fixed_omega_beta(times,vals,float(m3['omegaFitEnsemble']),float(m3['betaFitEnsemble']))
    r2_stored=float(m3['fitR2Ensemble'])
    if abs(r2_repro-r2_stored)>2e-6:
        raise SystemExit(f"[x21h] n=3 fit reproduction mismatch: stored={r2_stored:.12g}, reproduced={r2_repro:.12g}")
    norm=vals[0]
    if abs(norm)<1e-14: norm=math.hypot(coeff[0],coeff[1])
    t0=times[0]
    trace_rows=[]
    for ta,y,p in zip(times,vals,pred):
        trace_rows.append({'time':f"{ta-t0:.15g}",'normalized_amplitude':f"{y/norm:.15g}",'normalized_fit':f"{p/norm:.15g}"})
    write_csv(out/'data/capillary_wave_trace_representative.csv',trace_rows)

    # Traceability: one row per realization where possible.
    trace_rows_meta=[]
    for r in SR:
        trace_rows_meta.append({
            'dataset':'static_drop','mode':'','seed':r.get('seed',''),'internal_case':r.get('case_id',''),
            'source_path':r.get('active_run',''),'binary_sha256':BINARY_SHA256,
            'analyzer':'analyze_0493x21e_fix3_article_capillary_review.py','status':r.get('article_use',''),
            'sigma_declared':sigma_decl,'gamma':d['gamma'],'kBT':d['kBT'],'h':h,'dt':'0.0063471328149122585'
        })
    for r in C:
        trace_rows_meta.append({
            'dataset':'capillary_wave','mode':r.get('mode',''),'seed':r.get('seed',''),'internal_case':r.get('case',''),
            'source_path':r.get('trace',''),'binary_sha256':BINARY_SHA256,
            'analyzer':'analyze_0493x12cal_capillary_calibrator.py','status':r.get('status',''),
            'sigma_declared':sigma_decl,'gamma':d['gamma'],'kBT':d['kBT'],'h':h,'dt':'0.0063471328149122585'
        })
    write_csv(out/'data/capillary_article_traceability.csv',trace_rows_meta)

    # Figure 5.
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    matplotlib.rcParams.update({'font.size':8,'axes.labelsize':8,'xtick.labelsize':7,'ytick.labelsize':7,'legend.fontsize':6.7,'pdf.fonttype':42,'ps.fonttype':42})
    fig,axs=plt.subplots(1,3,figsize=(7.2,2.55),constrained_layout=True)
    # (a)
    ax=axs[0]
    ax.errorbar(xk,yk,yerr=[f(r,'kappa_num_signed_std_seed') for r in S],fmt='o',capsize=2.2,label='reconstructed')
    lo=0; hi=max(xk)*1.06
    ax.plot([lo,hi],[lo,hi],'--',linewidth=1.0,label='ideal')
    ax.plot([lo,hi],[Gk*lo,Gk*hi],'-',linewidth=1.0,label=rf'fit: $G_\kappa={Gk:.3f}$')
    ax.set_xlabel(r'$1/R_{\rm eff}$'); ax.set_ylabel(r'reconstructed $|\kappa|$'); ax.set_xlim(left=0); ax.set_ylim(bottom=0)
    ax.legend(frameon=False,loc='best'); ax.text(0.02,0.98,'(a)',transform=ax.transAxes,ha='left',va='top',fontweight='bold')
    # (b)
    ax=axs[1]
    tx=[float(r['time']) for r in trace_rows]; yy=[float(r['normalized_amplitude']) for r in trace_rows]; pp=[float(r['normalized_fit']) for r in trace_rows]
    ax.plot(tx,yy,'o',markersize=2.2,label='ensemble')
    ax.plot(tx,pp,'-',linewidth=1.2,label='damped fit')
    ax.set_xlabel(r'$t$'); ax.set_ylabel(r'$A(t)/A(0)$')
    ax.text(0.98,0.97,f'$n=3$\n$R^2={r2_stored:.4f}$\n$\\omega={float(m3["omegaFitEnsemble"]):.3f}$',transform=ax.transAxes,ha='right',va='top',fontsize=6.6)
    ax.legend(frameon=False,loc='lower left'); ax.text(0.02,0.98,'(b)',transform=ax.transAxes,ha='left',va='top',fontweight='bold')
    # (c)
    ax=axs[2]
    xx=[float(r['omegaTheoryDeclared'])**2 for r in M]
    yy=[float(r['omegaFitEnsemble'])**2 for r in M]
    ye=[x*float(r['seedGainStd']) for x,r in zip(xx,M)]
    ax.errorbar(xx,yy,yerr=ye,fmt='o',capsize=2.2,label='modes')
    top=max(max(xx),max(yy))*1.08
    ax.plot([0,top],[0,top],'--',linewidth=1.0,label='unit slope')
    ax.plot([0,top],[0,Gsigma*top],'-',linewidth=1.1,label=rf'fit: $G_\sigma={Gsigma:.3f}$')
    for x,y,r in zip(xx,yy,M): ax.annotate(f"n={int(float(r['mode']))}",(x,y),xytext=(3,3),textcoords='offset points',fontsize=6.5)
    ax.set_xlabel(r'$(\sigma_{\rm decl}/\rho)k^3\tanh(kH)$'); ax.set_ylabel(r'$\omega_{\rm meas}^2$'); ax.set_xlim(left=0); ax.set_ylim(bottom=0)
    ax.legend(frameon=False,loc='best'); ax.text(0.02,0.98,'(c)',transform=ax.transAxes,ha='left',va='top',fontweight='bold')
    fig.savefig(out/'figures/fig_05_capillary_characterization.pdf',bbox_inches='tight')
    fig.savefig(out/'figures/fig_05_capillary_characterization.png',dpi=300,bbox_inches='tight')
    plt.close(fig)

    # Table 3.
    reff_range=(min(float(r['R_eff_over_h']) for r in static_rows),max(float(r['R_eff_over_h']) for r in static_rows))
    mode_gains=[float(r['G_sigma_mode']) for r in mode_rows]
    oh=[nu*math.sqrt(rho/(sigma_eff*float(r['R_eff']))) for r in static_rows]
    relerr=100*(sigma_eff/sigma_decl-1)
    table=[
      ('Static-drop realizations','18'),('Resolved $R_{\\rm eff}/h$ range',f'{reff_range[0]:.2f}--{reff_range[1]:.2f}'),
      ('Curvature gain $G_\\kappa$',f'{Gk:.3f} $\\pm$ {Gk_se:.3f}'),('Declared surface tension $\\sigma_{\\rm decl}$',f'{sigma_decl:.0f}'),
      ('Capillary-wave modes','$n=2,3,4$'),('Realizations per mode','3'),('Dynamic gain $G_\\sigma$',f'{Gsigma:.5f}'),
      ('Effective surface tension $\\sigma_{\\rm eff}$',f'{sigma_eff:.2f}'),('Relative surface-tension error',f'{relerr:.2f}\\%'),
      ('Mean wave-fit $R^2$',f'{float(d["meanFitR2"]):.5f}'),('Cross-mode gain spread',f'{100*float(d["surfaceTensionGainModeRelativeStd"]):.2f}\\%'),
      ('Calibration status','PASS')]
    with (out/'tables/table_03_capillary_characterization.csv').open('w',newline='',encoding='utf-8') as fp:
        w=csv.writer(fp); w.writerow(['Quantity','Value']); w.writerows([(q,v.replace('\\%','%').replace('$','').replace('\\pm','+/-').replace('\\','')) for q,v in table])
    tex=['\\begin{table}[t]','\\centering','\\caption{Capillary characterization of the particle/field free-surface closure.}','\\label{tab:capillary_characterization}','\\begin{tabular}{ll}','\\hline','Quantity & Value \\\\','\\hline']
    tex += [f'{q} & {v} \\\\' for q,v in table]
    tex += ['\\hline','\\end{tabular}','\\end{table}','']
    (out/'tables/table_03_capillary_characterization.tex').write_text('\n'.join(tex),encoding='utf-8')

    caption=(
"Capillary characterization of the particle/field free-surface closure. "
"(a) Reconstructed curvature magnitude of equilibrated circular interfaces as a function of the inverse effective radius. "
"Symbols denote ensemble means over three independent realizations and error bars one standard deviation; the dashed line shows the ideal two-dimensional relation $|\\kappa|=1/R_{\\rm eff}$ and the solid line the fit constrained through the origin. "
"(b) Representative normalized capillary-wave amplitude and corresponding damped-oscillation fit for the intermediate resolved mode $n=3$. "
"(c) Measured squared angular frequency as a function of the finite-depth capillary-wave prediction based on the declared surface-tension parameter for modes $n=2,3,4$. "
"The dashed line denotes unit slope and the solid line the fitted dynamic gain, $\\sigma_{\\rm eff}/\\sigma_{\\rm decl}=G_\\sigma=%.5f$, giving $\\sigma_{\\rm eff}=%.2f$." % (Gsigma,sigma_eff))
    (out/'capillary_figure_caption.txt').write_text(caption+'\n',encoding='utf-8')
    latex=("\\begin{figure*}[t]\n\\centering\n\\includegraphics[width=\\textwidth]{figures/fig_05_capillary_characterization.pdf}\n"
           "\\caption{"+caption+"}\n\\label{fig:capillary_characterization}\n\\end{figure*}\n")
    (out/'capillary_latex_insertion.tex').write_text(latex,encoding='utf-8')

    summary=[
      'STATIC:',f'- radius groups / seeds: 6 / 3 (18 realizations)',f'- R_eff/h range: {reff_range[0]:.6f} .. {reff_range[1]:.6f}',
      f'- G_kappa,0: {Gk:.9f} +/- {Gk_se:.9f}',f'- G_kappa range by radius: {min(float(r["G_kappa"]) for r in static_rows):.6f} .. {max(float(r["G_kappa"]) for r in static_rows):.6f}',
      f'- maximum relative curvature error: {max(float(r["E_kappa"]) for r in static_rows):.6f}',
      '', 'DYNAMIC:',f'- sigma_decl: {sigma_decl:.12g}', '- modes: 2,3,4', '- seeds per mode: 3',
    ]
    for r in mode_rows: summary.append(f'- n={r["mode"]}: omega={float(r["omega_meas"]):.10g}, G_sigma={float(r["G_sigma_mode"]):.10g}, R2={float(r["fit_R2"]):.10g}, status={r["status"]}')
    summary += [f'- G_sigma global (origin regression in omega^2): {Gsigma:.12g}',f'- sigma_eff: {sigma_eff:.12g}',f'- relative sigma error: {relerr:.6f} %',
      f'- mean fit R2: {float(d["meanFitR2"]):.12g}',f'- cross-mode relative gain std: {float(d["surfaceTensionGainModeRelativeStd"]):.12g}', '- status: PASS',
      '', 'DIMENSIONLESS:',f'- nu_eff: {nu:.12g}',f'- rho_L: {rho:.12g}',f'- Oh(R_eff) range using sigma_eff: {min(oh):.8g} .. {max(oh):.8g}', '']
    (out/'capillary_article_summary.txt').write_text('\n'.join(summary),encoding='utf-8')

    checks=[
      f'version={VERSION}', 'status=PASS', f'staticMeansSha256={sha256(static_means)}',f'staticRealizationsSha256={sha256(static_real)}',
      f'dynamicSummarySha256={sha256(dyn_summary)}',f'dynamicModesSha256={sha256(dyn_modes)}',f'dynamicCasesSha256={sha256(dyn_cases)}',f'n3TraceSha256={sha256(n3_trace)}',
      f'curvatureGainRecomputed={Gk:.12g}',f'curvatureGainSE={Gk_se:.12g}',f'dynamicGainFrozen={Gsigma:.12g}',f'sigmaEffectiveFrozen={sigma_eff:.12g}',
      f'n3StoredR2={r2_stored:.12g}',f'n3ReproducedR2={r2_repro:.12g}',f'crossModeRelativeStd={float(d["surfaceTensionGainModeRelativeStd"]):.12g}',
      'pressureAbsoluteUsed=false','x9eShownInArticle=false','interfaceRmsShownInArticle=false','solverModified=false','newSimulationRun=false','']
    (out/'capillary_article_checks.txt').write_text('\n'.join(checks),encoding='utf-8')

    readme=(f"""article_capillary_outputs_v2 — generated by {VERSION}\n\nFrozen inputs:\n- x21e static-drop fix3 review: 6 radii x 3 seeds\n- x21g/x12cal dynamic calibration: n=2,3,4 x 3 seeds, GLOBAL PASS\n\nPrimary article values:\n- G_kappa,0 = {Gk:.9f} +/- {Gk_se:.9f}\n- G_sigma = {Gsigma:.12g}\n- sigma_eff = {sigma_eff:.12g}\n- sigma_eff/sigma_decl - 1 = {relerr:.6f}%\n- mean fit R2 = {float(d['meanFitR2']):.12g}\n- cross-mode relative gain std = {100*float(d['surfaceTensionGainModeRelativeStd']):.6f}%\n\nThe static pressure observable and thermal-inclusive interface RMS are deliberately excluded from the final article figure.\nNo solver code or simulation output is modified.\n""")
    (out/'README.txt').write_text(readme,encoding='utf-8')
    shutil.copy2(Path(__file__),out/'scripts/make_article_capillary_characterization.py')

    zip_path=out.parent/'article_capillary_outputs_v2.zip'
    if zip_path.exists(): zip_path.unlink()
    with zipfile.ZipFile(zip_path,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for p in sorted(out.rglob('*')):
            if p.is_file(): z.write(p,Path('article_capillary_outputs_v2')/p.relative_to(out))
    print(f"[x21h] PASS Gkappa={Gk:.9g}+/-{Gk_se:.4g} Gsigma={Gsigma:.12g} sigmaEff={sigma_eff:.12g}")
    print(f"[x21h] outputs={out}")
    print(f"[x21h] zip={zip_path}")

if __name__=='__main__': main()

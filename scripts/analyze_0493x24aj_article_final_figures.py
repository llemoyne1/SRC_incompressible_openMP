#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""0493x24aj — figures finales article Sato / SRC-MPCD (version 1).

Entrées CSV attendues :
  article_interface_summary*.csv
  gas_loading_summary*.csv
  shape_fit_summary*.csv

Sorties PDF :
  fig01_h_over_D_vs_target_Fr.pdf
  fig02_widths_vs_target_Fr.pdf
  fig03_incident_speed_ratio_vs_target_Fr.pdf
  fig04_incident_to_nozzle_momentum_ratio_vs_target_Fr.pdf
  fig05_shape_fit_rmse_vs_target_Fr.pdf
  fig06_shape_fit_r2_vs_target_Fr.pdf
  fig07_shape_fit_rmse_ratio_vs_target_Fr.pdf

Le script utilise uniquement csv/numpy/matplotlib (pas pandas).
"""

import argparse, csv, glob, math, os
from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt


def f(v, default=float('nan')):
    try:
        x=float(v)
        return x if math.isfinite(x) else default
    except Exception:
        return default


def read_rows(path):
    with open(path, newline='') as h:
        return list(csv.DictReader(h))


def expand(patterns):
    out=[]
    for p in patterns:
        out.extend(sorted(glob.glob(p)))
    seen=set(); uniq=[]
    for p in out:
        if p not in seen:
            uniq.append(p); seen.add(p)
    return uniq


def keyed(paths):
    d={}
    for p in paths:
        for r in read_rows(p):
            if 'targetFr' not in r: continue
            fr=f(r['targetFr'])
            if math.isnan(fr): continue
            rr={k:(f(v) if k!='source' else v) for k,v in r.items()}
            rr['targetFr']=fr
            rr['source']=os.path.basename(p)
            d[round(fr,9)]=rr
    return d


def style():
    plt.rcParams.update({
        'font.size':11,'axes.labelsize':12,'legend.fontsize':10,
        'xtick.labelsize':11,'ytick.labelsize':11,
        'pdf.fonttype':42,'ps.fonttype':42,'lines.linewidth':2.0
    })


def save(path):
    plt.tight_layout(); plt.savefig(path,bbox_inches='tight'); plt.close()


def vals(rows,key):
    return np.array([r.get(key,float('nan')) for r in rows],float)


def fig_depth(rows,out):
    rows=[r for r in rows if math.isfinite(r.get('meanHOverD',float('nan')))]
    if not rows: return float('nan')
    x=vals(rows,'targetFr'); y=vals(rows,'meanHOverD'); e=vals(rows,'stdHOverD')
    xx=np.linspace(0,max(x)*1.08,300)
    slope=float(np.dot(x,y)/np.dot(x,x))
    plt.figure(figsize=(6.5,4.8))
    plt.fill_between(xx,0.8*1.3*xx,1.2*1.3*xx,alpha=.18,label='Sato ±20%')
    plt.plot(xx,1.3*xx,label="Sato: h/D = 1.30 Fr'")
    plt.plot(xx,slope*xx,'--',label=f"SRC fit through 0: {slope:.3f} Fr'")
    plt.errorbar(x,y,yerr=e,fmt='o',capsize=4,label='SRC/MPCD')
    plt.xlabel("Target modified Froude number Fr'"); plt.ylabel('Cavity depth h/D')
    plt.xlim(left=0); plt.ylim(bottom=0); plt.grid(alpha=.3); plt.legend(loc='upper left')
    save(out); return slope


def fig_width(rows,out):
    rows=[r for r in rows if math.isfinite(r.get('meanMouthWidthOverD',float('nan')))]
    if not rows: return
    x=vals(rows,'targetFr')
    plt.figure(figsize=(6.5,4.8))
    for key,err,label,fmt in [
        ('meanMouthWidthOverD','stdMouthWidthOverD','Mouth width','o-'),
        ('meanWidth10DepthOverD','stdWidth10DepthOverD','Width at 10% depth','s-'),
        ('meanWidth50DepthOverD','stdWidth50DepthOverD','Width at 50% depth','^-')]:
        plt.errorbar(x,vals(rows,key),yerr=vals(rows,err),fmt=fmt,capsize=4,label=label)
    plt.xlabel("Target modified Froude number Fr'"); plt.ylabel('Characteristic width / D')
    plt.xlim(left=0); plt.ylim(bottom=0); plt.grid(alpha=.3); plt.legend()
    save(out)


def fig_gas(rows,out,key,err,ylabel):
    rows=[r for r in rows if math.isfinite(r.get(key,float('nan')))]
    if not rows:return
    x=vals(rows,'targetFr')
    plt.figure(figsize=(6.5,4.8))
    plt.errorbar(x,vals(rows,key),yerr=vals(rows,err),fmt='o-',capsize=4)
    plt.xlabel("Target modified Froude number Fr'"); plt.ylabel(ylabel)
    plt.xlim(left=0); plt.ylim(bottom=0); plt.grid(alpha=.3)
    save(out)


def fig_shape(rows,out,kind):
    rows=[r for r in rows if math.isfinite(r.get('parabolaRMSEOverD',float('nan')))]
    if not rows:return
    x=vals(rows,'targetFr')
    plt.figure(figsize=(6.5,4.8))
    if kind=='rmse':
        plt.plot(x,vals(rows,'parabolaRMSEOverD'),'o-',label='Parabola fit')
        plt.plot(x,vals(rows,'ellipseRMSEOverD'),'s-',label='Ellipse fit')
        plt.ylabel('RMSE / D')
    elif kind=='r2':
        plt.plot(x,vals(rows,'parabolaR2'),'o-',label='Parabola fit')
        plt.plot(x,vals(rows,'ellipseR2'),'s-',label='Ellipse fit')
        plt.ylabel(r'Coefficient of determination $R^2$'); plt.ylim(0,1.02)
    else:
        plt.plot(x,vals(rows,'rmseRatioParabolaOverEllipse'),'o-')
        plt.axhline(1,ls='--',lw=1.5,label='Parity')
        plt.ylabel('RMSE(parabola) / RMSE(ellipse)')
    plt.xlabel("Target modified Froude number Fr'"); plt.xlim(left=0); plt.grid(alpha=.3); plt.legend()
    save(out)


def write_merged(path, interface, gas, shape):
    ks=sorted(set(interface)|set(gas)|set(shape))
    cols=['targetFr','meanHOverD','stdHOverD','satoHOverD','relativeErrorToSato',
          'meanMouthWidthOverD','stdMouthWidthOverD','meanWidth10DepthOverD','stdWidth10DepthOverD',
          'meanWidth50DepthOverD','stdWidth50DepthOverD','meanIncidentSpeedRatioToNominal',
          'stdIncidentSpeedRatioToNominal','meanIncidentToNozzleMomentumRatio','stdIncidentToNozzleMomentumRatio',
          'parabolaRMSEOverD','parabolaR2','ellipseRMSEOverD','ellipseR2','rmseRatioParabolaOverEllipse']
    with open(path,'w',newline='') as h:
        w=csv.writer(h); w.writerow(cols)
        for k in ks:
            i=interface.get(k,{}); g=gas.get(k,{}); s=shape.get(k,{})
            src={**i,**g,**s}; w.writerow([k]+[src.get(c,'') for c in cols[1:]])


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--interface-summaries',nargs='*',default=['article_interface_summary*.csv'])
    ap.add_argument('--gas-loading-summaries',nargs='*',default=['gas_loading_summary*.csv'])
    ap.add_argument('--shape-fit-summaries',nargs='*',default=['shape_fit_summary*.csv'])
    ap.add_argument('--outdir',default='analysis/0493x24aj_article_final_figures')
    a=ap.parse_args()
    Path(a.outdir).mkdir(parents=True,exist_ok=True); style()
    I=keyed(expand(a.interface_summaries)); G=keyed(expand(a.gas_loading_summaries)); S=keyed(expand(a.shape_fit_summaries))
    ir=[I[k] for k in sorted(I)]; gr=[G[k] for k in sorted(G)]; sr=[S[k] for k in sorted(S)]
    slope=fig_depth(ir,os.path.join(a.outdir,'fig01_h_over_D_vs_target_Fr.pdf'))
    fig_width(ir,os.path.join(a.outdir,'fig02_widths_vs_target_Fr.pdf'))
    fig_gas(gr,os.path.join(a.outdir,'fig03_incident_speed_ratio_vs_target_Fr.pdf'),
            'meanIncidentSpeedRatioToNominal','stdIncidentSpeedRatioToNominal','Incident speed / nominal nozzle speed')
    fig_gas(gr,os.path.join(a.outdir,'fig04_incident_to_nozzle_momentum_ratio_vs_target_Fr.pdf'),
            'meanIncidentToNozzleMomentumRatio','stdIncidentToNozzleMomentumRatio','Incident / nozzle momentum proxy')
    fig_shape(sr,os.path.join(a.outdir,'fig05_shape_fit_rmse_vs_target_Fr.pdf'),'rmse')
    fig_shape(sr,os.path.join(a.outdir,'fig06_shape_fit_r2_vs_target_Fr.pdf'),'r2')
    fig_shape(sr,os.path.join(a.outdir,'fig07_shape_fit_rmse_ratio_vs_target_Fr.pdf'),'ratio')
    write_merged(os.path.join(a.outdir,'article_merged_summary.csv'),I,G,S)
    with open(os.path.join(a.outdir,'article_figure_notes.txt'),'w') as h:
        h.write(f"h/D fit through origin slope = {slope:.8g}\n")
        if sr:
            n=sum(1 for r in sr if r.get('rmseRatioParabolaOverEllipse',9)<1)
            h.write(f"Parabola RMSE < ellipse RMSE in {n}/{len(sr)} available cases.\n")
    print('[0493x24aj] output:',a.outdir)

if __name__=='__main__':
    main()

#!/usr/bin/env python3
import argparse,csv,math
from collections import defaultdict
from pathlib import Path
import matplotlib.pyplot as plt


def read(p):
    with open(p,newline='') as f:return list(csv.DictReader(f))
def fv(r,k): return float(r.get(k,'0') or 0.0)
def iv(r,k): return int(float(r.get(k,'0') or 0))
def meta(p):
    d={}
    for s in p.read_text().splitlines():
        if '=' in s:
            k,v=s.split('=',1); d[k.strip()]=v.strip()
    return d


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',default='runs/0493x17d_fixed_membrane_publishable'); a=ap.parse_args()
    root=Path(a.root); run=root/'fresh'; out=run/'output'; figdir=root/'analysis'/'article_figures'; figdir.mkdir(parents=True,exist_ok=True)
    md=meta(run/'run_meta_0493x17d_membrane_publishable.txt'); span=float(md['membraneSpan']); dt=float(md['dt'])
    nodes=read(out/'chi_membrane_nodes_0493x17c.csv'); mem=read(out/'chi_membrane_0493x17c.csv')
    by=defaultdict(list)
    for q in nodes: by[iv(q,'step')].append(q)
    steps=sorted(by)
    # Choose initial, three temporal landmarks, maximum-deflection snapshot and final.
    def amp(st): return max(abs(fv(q,'x')-fv(q,'x0')) for q in by[st])
    stmax=max(steps,key=amp)
    pick={steps[0],steps[-1],stmax}
    for f in (0.25,0.50,0.75): pick.add(steps[round(f*(len(steps)-1))])
    pick=sorted(pick)

    fig,ax=plt.subplots(figsize=(7.0,5.2))
    for st in pick:
        rr=sorted(by[st],key=lambda q:iv(q,'node')); x=[fv(q,'x') for q in rr]; y=[fv(q,'y') for q in rr]; x.append(x[0]); y.append(y[0]); ax.plot(x,y,label=f'step {st}')
    ax.set_aspect('equal',adjustable='box'); ax.set_xlabel('x'); ax.set_ylabel('y'); ax.legend(fontsize=8); ax.set_title('Clamped material membrane — actual deformation')
    fig.tight_layout(); fig.savefig(figdir/'membrane_shape_history.png',dpi=220); fig.savefig(figdir/'membrane_shape_history.pdf'); plt.close(fig)

    # Deflection history from all free nodes and a mid-span band.
    y0=[fv(q,'y0') for q in by[steps[0]]]; ymid=.5*(min(y0)+max(y0)); h=float(md['h'])
    t=[]; wmax=[]; wmid=[]
    for st in steps:
        rr=by[st]; t.append(fv(rr[0],'time'))
        free=[q for q in rr if not iv(q,'pinned0493x17d')]
        wmax.append(max(abs(fv(q,'x')-fv(q,'x0')) for q in free)/span)
        mm=[fv(q,'x')-fv(q,'x0') for q in free if abs(fv(q,'y0')-ymid)<=1.5*h]
        wmid.append((sum(mm)/len(mm))/span if mm else 0.0)
    fig,ax=plt.subplots(figsize=(7.0,4.4)); ax.plot(t,wmax,label=r'$w_{max}/L$'); ax.plot(t,wmid,label=r'$w_{mid}/L$'); ax.set_xlabel('time'); ax.set_ylabel('normalized deflection'); ax.legend(); ax.set_title('Membrane deflection history'); fig.tight_layout(); fig.savefig(figdir/'membrane_deflection_history.png',dpi=220); fig.savefig(figdir/'membrane_deflection_history.pdf'); plt.close(fig)

    tm=[fv(r,'time') for r in mem]; strain=[fv(r,'maxAbsEdgeStrain') for r in mem]; area=[fv(r,'areaRelativeChange') for r in mem]
    fig,ax=plt.subplots(figsize=(7.0,4.4)); ax.plot(tm,strain,label='max edge strain'); ax.plot(tm,[abs(x) for x in area],label='|area relative change|'); ax.set_xlabel('time'); ax.set_ylabel('dimensionless'); ax.legend(); ax.set_title('Membrane deformation controls'); fig.tight_layout(); fig.savefig(figdir/'membrane_strain_area.png',dpi=220); fig.savefig(figdir/'membrane_strain_area.pdf'); plt.close(fig)

    ffluid=[fv(r,'nodeReactionImpulseX')/dt for r in mem]; fsupport=[fv(r,'supportConstraintImpulseX')/dt for r in mem]
    fig,ax=plt.subplots(figsize=(7.0,4.4)); ax.plot(tm,ffluid,label='fluid force on membrane'); ax.plot(tm,fsupport,label='support reaction'); ax.set_xlabel('time'); ax.set_ylabel('x force'); ax.legend(); ax.set_title('Hydrodynamic load and clamp reaction'); fig.tight_layout(); fig.savefig(figdir/'membrane_force_balance.png',dpi=220); fig.savefig(figdir/'membrane_force_balance.pdf'); plt.close(fig)
    print(f'[0493x17d-pub] figures={figdir}')

if __name__=='__main__': main()

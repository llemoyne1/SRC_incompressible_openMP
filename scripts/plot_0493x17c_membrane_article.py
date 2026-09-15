#!/usr/bin/env python3
"""Create article-ready diagnostic figures from a completed 0493x17c pair."""
from __future__ import annotations
import argparse, csv
from pathlib import Path
import matplotlib.pyplot as plt


def read_csv(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f))


def snapshots(path):
    out={}
    for r in read_csv(path):
        s=int(r['step'])
        out.setdefault(s,[]).append((int(r['node']),float(r['x']),float(r['y'])))
    for s in out: out[s].sort()
    return out


def centered(poly):
    x=[p[1] for p in poly]; y=[p[2] for p in poly]
    cx=sum(x)/len(x); cy=sum(y)/len(y)
    xx=[v-cx for v in x]; yy=[v-cy for v in y]
    if xx: xx.append(xx[0]); yy.append(yy[0])
    return xx,yy


def save_both(fig, base):
    fig.savefig(str(base)+'.png', dpi=220, bbox_inches='tight')
    fig.savefig(str(base)+'.pdf', bbox_inches='tight')
    plt.close(fig)


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root', default='runs/0493x17c_membrane_fsi_qualification')
    ap.add_argument('--outdir', default='')
    a=ap.parse_args()
    root=Path(a.root); out=Path(a.outdir) if a.outdir else root/'analysis'/'article_figures'
    out.mkdir(parents=True,exist_ok=True)
    restout=root/'rest'/'fresh'/'output'; boostout=root/'boost'/'fresh'/'output'
    rs=snapshots(restout/'chi_membrane_nodes_0493x17c.csv')
    bs=snapshots(boostout/'chi_membrane_nodes_0493x17c.csv')
    steps=sorted(rs)
    pick=[]
    if steps:
        for frac in (0.0,0.33,0.66,1.0):
            pick.append(steps[round(frac*(len(steps)-1))])
        pick=list(dict.fromkeys(pick))

    fig,ax=plt.subplots()
    for st in pick:
        x,y=centered(rs[st]); ax.plot(x,y,label=f'step {st}')
    ax.set_aspect('equal',adjustable='box'); ax.set_xlabel('x - center x'); ax.set_ylabel('y - center y')
    ax.set_title('Fluid-driven membrane deformation'); ax.legend()
    save_both(fig,out/'membrane_shape_history_rest')

    common=sorted(set(rs)&set(bs))
    if common:
        st=common[-1]
        fig,ax=plt.subplots()
        x,y=centered(rs[st]); ax.plot(x,y,label='rest frame')
        x,y=centered(bs[st]); ax.plot(x,y,'--',label='boosted frame')
        ax.set_aspect('equal',adjustable='box'); ax.set_xlabel('x - center x'); ax.set_ylabel('y - center y')
        ax.set_title(f'Galilean comparison at step {st}'); ax.legend()
        save_both(fig,out/'membrane_galilean_final_shape')

    for name,key,ylabel in (
        ('area_history','areaRelativeChange','(A-A0)/|A0|'),
        ('strain_history','maxAbsEdgeStrain','max |edge strain|'),
        ('reaction_history','nodeReactionImpulseX','solid reaction impulse x'),
    ):
        fig,ax=plt.subplots()
        for label,odir in (('rest frame',restout),('boosted frame',boostout)):
            rr=read_csv(odir/'chi_membrane_0493x17c.csv')
            ax.plot([float(r['time']) for r in rr],[float(r[key]) for r in rr],label=label)
        ax.set_xlabel('time'); ax.set_ylabel(ylabel); ax.set_title(name.replace('_',' ').title()); ax.legend()
        save_both(fig,out/name)
    print(out)

if __name__=='__main__':
    main()

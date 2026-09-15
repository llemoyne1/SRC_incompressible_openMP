#!/usr/bin/env python3
import argparse,csv
from collections import defaultdict
from pathlib import Path
import matplotlib.pyplot as plt

def read(p):
    with open(p,newline='') as f:return list(csv.DictReader(f))
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',default='runs/0493x17d_article_solids'); a=ap.parse_args(); root=Path(a.root); figdir=root/'analysis'/'article_figures'; figdir.mkdir(parents=True,exist_ok=True)
    # Fixed membrane shape snapshots.
    r=read(root/'fixed_membrane'/'fresh'/'output'/'chi_membrane_nodes_0493x17c.csv'); by=defaultdict(list)
    for q in r: by[int(q['step'])].append(q)
    steps=sorted(by); pick=steps if len(steps)<=6 else [steps[round(i*(len(steps)-1)/5)] for i in range(6)]
    fig,ax=plt.subplots(figsize=(6.5,5.0))
    for st in pick:
        rr=sorted(by[st],key=lambda q:int(q['node'])); x=[float(q['x']) for q in rr]; y=[float(q['y']) for q in rr]; x.append(x[0]); y.append(y[0]); ax.plot(x,y,label=f'step {st}')
    ax.set_aspect('equal',adjustable='box'); ax.set_xlabel('x'); ax.set_ylabel('y'); ax.legend(); ax.set_title('Fixed flexible membrane: fluid-induced deflection'); fig.tight_layout(); fig.savefig(figdir/'fixed_membrane_shape_history.png',dpi=200); fig.savefig(figdir/'fixed_membrane_shape_history.pdf'); plt.close(fig)
    # Piston displacement.
    s=read(root/'pressure_piston'/'fresh'/'output'/'chi_solid_dynamics_0493x16a.csv'); t=[float(q['time']) for q in s]; x=[float(q['centerXAfter']) for q in s]; v=[float(q['velocityXAfter']) for q in s]
    fig,ax=plt.subplots(figsize=(6.5,4.2)); ax.plot(t,x); ax.set_xlabel('time'); ax.set_ylabel('piston center x'); ax.set_title('Pressure-driven piston displacement'); fig.tight_layout(); fig.savefig(figdir/'pressure_piston_displacement.png',dpi=200); fig.savefig(figdir/'pressure_piston_displacement.pdf'); plt.close(fig)
    fig,ax=plt.subplots(figsize=(6.5,4.2)); ax.plot(t,v); ax.set_xlabel('time'); ax.set_ylabel('piston velocity x'); ax.set_title('Pressure-driven piston velocity'); fig.tight_layout(); fig.savefig(figdir/'pressure_piston_velocity.png',dpi=200); fig.savefig(figdir/'pressure_piston_velocity.pdf'); plt.close(fig)
    print(f'[0493x17d] figures={figdir}')
if __name__=='__main__':main()

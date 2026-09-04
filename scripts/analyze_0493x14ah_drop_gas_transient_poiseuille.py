#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,json,math
from pathlib import Path

def read(path):
    with path.open(newline='',encoding='utf-8') as f:return list(csv.DictReader(f))
def linfit(xs,ys):
    n=len(xs); xm=sum(xs)/n; ym=sum(ys)/n; sxx=sum((x-xm)**2 for x in xs)
    if sxx<=0:return 0.0,ym,0.0
    b=sum((x-xm)*(y-ym) for x,y in zip(xs,ys))/sxx; a=ym-b*xm
    sst=sum((y-ym)**2 for y in ys); sse=sum((y-(a+b*x))**2 for x,y in zip(xs,ys)); r2=1-sse/sst if sst>0 else 1.0
    return b,a,r2

def unwrap_periodic(vals,L):
    if not vals:return []
    out=[vals[0]]; shift=0.0; prev=vals[0]
    for v in vals[1:]:
        d=v-prev
        if d > 0.5*L: shift -= L
        elif d < -0.5*L: shift += L
        out.append(v+shift); prev=v
    return out

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--run-root',type=Path,required=True); ap.add_argument('--liquid-type',type=int,default=1); ap.add_argument('--gas-type',type=int,default=2); ap.add_argument('--channel-center-y',type=float,required=True); ap.add_argument('--gas-umean0-nominal',type=float,required=True); ap.add_argument('--radius',type=float,required=True); ap.add_argument('--Lx',type=float,required=True)
    a=ap.parse_args(); out=a.run_root/'output'; ana=a.run_root/'analysis'; ana.mkdir(parents=True,exist_ok=True)
    shape=read(out/'cuda_ellipse_shape_0493x9f.csv'); species=read(out/'species_runtime_0493x14ah.csv')
    smap={(int(r['step']),int(r['type'])):r for r in species}
    trace=[]
    for r in shape:
        st=int(r['step']); keyL=(st,a.liquid_type); keyG=(st,a.gas_type)
        if keyL not in smap or keyG not in smap:continue
        L=smap[keyL];G=smap[keyG]
        trace.append({'step':st,'time':float(r['time']),'xCMWrapped':float(r['xCM']),'yCM':float(r['yCM']),'axisRatio':float(r['axisRatio']),'ellipticity':float(r['ellipticity']),'UdropX':float(L['meanVx']),'UdropY':float(L['meanVy']),'UgasGlobalX':float(G['meanVx']),'UgasGlobalY':float(G['meanVy']),'slipGlobalX':float(G['meanVx'])-float(L['meanVx'])})
    if len(trace)<5:raise SystemExit('insufficient aligned trace')
    xu=unwrap_periodic([r['xCMWrapped'] for r in trace],a.Lx)
    for r,x in zip(trace,xu):r['xCM']=x
    x0=trace[0]['xCM'];y0=trace[0]['yCM'];t0=trace[0]['time'];tend=trace[-1]['time']
    for r in trace:
        r['dx']=r['xCM']-x0;r['dy']=r['yCM']-y0;r['centerlineOffset']=r['yCM']-a.channel_center_y
    start=max(1,len(trace)//2); late=trace[start:]
    bx,ax,r2x=linfit([r['time'] for r in late],[r['xCM'] for r in late]); by,ay,r2y=linfit([r['time'] for r in late],[r['yCM'] for r in late])
    mean_drop=sum(r['UdropX'] for r in late)/len(late);mean_gas=sum(r['UgasGlobalX'] for r in late)/len(late)
    gas0=trace[0]['UgasGlobalX']; gasEnd=trace[-1]['UgasGlobalX']; gasMin=min(r['UgasGlobalX'] for r in trace)
    reversal=next((r for r in trace if r['UgasGlobalX']<=0.0),None)
    dx=trace[-1]['dx']; maxY=max(abs(r['centerlineOffset']) for r in trace)
    if reversal is not None:
        status='FAIL_CARRIER_REVERSAL'
    elif dx <= 0.0 or bx <= 0.0:
        status='FAIL_UPSTREAM_OR_NONADVECTED_DROP'
    elif maxY > 0.25*a.radius:
        status='REVIEW_TRANSVERSE_MIGRATION'
    else:
        status='PASS_DYNAMIC_DRAG'
    outcsv=ana/'drop_drag_trace_0493x14ah.csv'
    with outcsv.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(trace[0].keys()));w.writeheader();w.writerows(trace)
    summ={'status':status,'points':len(trace),'tStart':t0,'tEnd':tend,'xCM0':x0,'xCMEndUnwrapped':trace[-1]['xCM'],'dx':dx,'dxOverR':dx/a.radius,'yCM0':y0,'yCMEnd':trace[-1]['yCM'],'dy':trace[-1]['dy'],'maxAbsCenterlineOffset':maxY,'maxAbsCenterlineOffsetOverR':maxY/a.radius,'lateTrajectorySpeedX':bx,'lateTrajectorySpeedXR2':r2x,'lateTrajectorySpeedY':by,'lateTrajectorySpeedYR2':r2y,'lateLiquidMeanVx':mean_drop,'gasGlobalMeanVxFirstSample':gas0,'gasGlobalMeanVxEnd':gasEnd,'gasGlobalMeanVxMin':gasMin,'gasGlobalMeanVxLate':mean_gas,'gasRetentionEndOverFirst':gasEnd/gas0 if gas0 else None,'gasUmeanParabolicNominal0':a.gas_umean0_nominal,'gasSignReversalStep':None if reversal is None else reversal['step'],'gasSignReversalTime':None if reversal is None else reversal['time'],'axisRatioInitial':trace[0]['axisRatio'],'axisRatioFinal':trace[-1]['axisRatio'],'axisRatioMax':max(r['axisRatio'] for r in trace),'qualitativeContract':'transient initial-Poiseuille carrier must remain downstream (Ugas>0); drop must translate downstream by drag; y drift should remain small; no steady drag-law target is imposed'}
    js=ana/'drop_drag_summary_0493x14ah.json';js.write_text(json.dumps(summ,indent=2)+'\n')
    print('[0493x14ah-analysis] status=%s dx=%.6g (%.3f R) yShift=%.6g lateVxCM=%.6g R2=%.4f Ugas first/end/min=%.6g/%.6g/%.6g axisRatioMax=%.6g' % (status,dx,dx/a.radius,summ['dy'],bx,r2x,gas0,gasEnd,gasMin,summ['axisRatioMax']))
    if reversal is not None: print('[0493x14ah-analysis] carrier reversal at step=%d t=%.6g' % (reversal['step'],reversal['time']))
    print(f'[0493x14ah-analysis] trace={outcsv}')
    print(f'[0493x14ah-analysis] summary={js}')
if __name__=='__main__':main()

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

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--run-root',type=Path,required=True); ap.add_argument('--liquid-type',type=int,default=1); ap.add_argument('--gas-type',type=int,default=2); ap.add_argument('--channel-center-y',type=float,required=True); ap.add_argument('--gas-umean-nominal',type=float,required=True); ap.add_argument('--radius',type=float,required=True)
    a=ap.parse_args(); out=a.run_root/'output'; ana=a.run_root/'analysis'; ana.mkdir(parents=True,exist_ok=True)
    shape=read(out/'cuda_ellipse_shape_0493x9f.csv'); species=read(out/'species_runtime_0493x14ag.csv')
    smap={(int(r['step']),int(r['type'])):r for r in species}
    trace=[]
    for r in shape:
        st=int(r['step']); keyL=(st,a.liquid_type); keyG=(st,a.gas_type)
        if keyL not in smap or keyG not in smap:continue
        L=smap[keyL];G=smap[keyG]
        trace.append({'step':st,'time':float(r['time']),'xCM':float(r['xCM']),'yCM':float(r['yCM']),'axisRatio':float(r['axisRatio']),'ellipticity':float(r['ellipticity']),'UdropX':float(L['meanVx']),'UdropY':float(L['meanVy']),'UgasGlobalX':float(G['meanVx']),'UgasGlobalY':float(G['meanVy']),'slipGlobalX':float(G['meanVx'])-float(L['meanVx'])})
    if len(trace)<5:raise SystemExit('insufficient aligned trace')
    x0=trace[0]['xCM'];y0=trace[0]['yCM'];t0=trace[0]['time']; tend=trace[-1]['time']
    for r in trace:
        r['dx']=r['xCM']-x0;r['dy']=r['yCM']-y0;r['centerlineOffset']=r['yCM']-a.channel_center_y
    start=max(1,len(trace)//2); late=trace[start:]
    b,aa,r2=linfit([r['time'] for r in late],[r['xCM'] for r in late])
    by,ay,r2y=linfit([r['time'] for r in late],[r['yCM'] for r in late])
    mean_drop=sum(r['UdropX'] for r in late)/len(late);mean_gas=sum(r['UgasGlobalX'] for r in late)/len(late)
    outcsv=ana/'drop_drag_trace_0493x14ag.csv'
    with outcsv.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(trace[0].keys()));w.writeheader();w.writerows(trace)
    summ={'points':len(trace),'tStart':t0,'tEnd':tend,'xCM0':x0,'xCMEnd':trace[-1]['xCM'],'dx':trace[-1]['dx'],'dxOverR':trace[-1]['dx']/a.radius,'yCM0':y0,'yCMEnd':trace[-1]['yCM'],'dy':trace[-1]['dy'],'maxAbsCenterlineOffset':max(abs(r['centerlineOffset']) for r in trace),'lateTrajectorySpeedX':b,'lateTrajectorySpeedXR2':r2,'lateTrajectorySpeedY':by,'lateTrajectorySpeedYR2':r2y,'lateLiquidMeanVx':mean_drop,'lateGasGlobalMeanVx':mean_gas,'nominalGasMeanVx':a.gas_umean_nominal,'lateDropOverNominalGas':mean_drop/a.gas_umean_nominal if a.gas_umean_nominal else None,'axisRatioInitial':trace[0]['axisRatio'],'axisRatioFinal':trace[-1]['axisRatio'],'axisRatioMax':max(r['axisRatio'] for r in trace),'qualitativeContract':'drag must move drop downstream (dx>0); transverse drift should remain small; no exact drag-law target imposed in first dynamic qualification'}
    js=ana/'drop_drag_summary_0493x14ag.json';js.write_text(json.dumps(summ,indent=2)+'\n')
    print('[0493x14ag-analysis] dx=%.6g (%.3f R) yShift=%.6g lateVxCM=%.6g R2=%.4f lateUdrop=%.6g lateUgasGlobal=%.6g axisRatioMax=%.6g' % (summ['dx'],summ['dxOverR'],summ['dy'],b,r2,mean_drop,mean_gas,summ['axisRatioMax']))
    print(f'[0493x14ag-analysis] trace={outcsv}')
    print(f'[0493x14ag-analysis] summary={js}')
if __name__=='__main__':main()

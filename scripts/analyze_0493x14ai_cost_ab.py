#!/usr/bin/env python3
import csv, json, math, statistics, sys
from pathlib import Path


def median(xs):
    return statistics.median(xs) if xs else float('nan')

def mean(xs):
    return statistics.mean(xs) if xs else float('nan')

def stdev(xs):
    return statistics.stdev(xs) if len(xs) > 1 else 0.0

def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: analyze_0493x14ai_cost_ab.py timing.csv summary.json')
    csv_path = Path(sys.argv[1]); out_path = Path(sys.argv[2])
    rows=[]
    with csv_path.open(newline='') as f:
        for r in csv.DictReader(f):
            r['rep']=int(r['rep']); r['steps']=int(r['steps'])
            for k in ('elapsed','user','sys','seconds_per_step'):
                r[k]=float(r[k])
            rows.append(r)
    by={m:[r for r in rows if r['mode']==m] for m in ('OFF','ON')}
    if not by['OFF'] or not by['ON']:
        raise SystemExit('need both OFF and ON rows')
    off=[r['seconds_per_step'] for r in by['OFF']]
    on=[r['seconds_per_step'] for r in by['ON']]
    med_off=median(off); med_on=median(on)
    overhead_pct=100.0*(med_on-med_off)/med_off
    reps=sorted(set(r['rep'] for r in rows))
    paired=[]
    paired_delta_sps=[]
    for rep in reps:
        ro=[r for r in by['OFF'] if r['rep']==rep]
        rn=[r for r in by['ON'] if r['rep']==rep]
        if len(ro)==1 and len(rn)==1:
            delta=rn[0]['seconds_per_step']-ro[0]['seconds_per_step']
            paired_delta_sps.append(delta)
            paired.append(100.0*delta/ro[0]['seconds_per_step'])
    paired_med=median(paired)
    paired_delta_med=median(paired_delta_sps)
    pair_mad=median([abs(x-paired_med) for x in paired]) if paired else float('nan')
    cv_off=stdev(off)/mean(off) if mean(off)>0 else float('nan')
    cv_on=stdev(on)/mean(on) if mean(on)>0 else float('nan')
    noise_pct=100.0*max(cv_off,cv_on)
    if math.isfinite(pair_mad) and pair_mad > max(1.0, abs(paired_med)):
        status='COST_NOT_RESOLVED_RUN_TO_RUN_NOISE'
    elif paired_med <= 2.0:
        status='COST_NEGLIGIBLE_LE_2PCT'
    elif paired_med <= 5.0:
        status='COST_ACCEPTABLE_2_TO_5PCT'
    else:
        status='COST_SIGNIFICANT_GT_5PCT'
    summary={
        'status':status,
        'stepsPerRun':by['OFF'][0]['steps'],
        'repetitions':min(len(by['OFF']),len(by['ON'])),
        'offSecondsPerStepMedian':med_off,
        'onSecondsPerStepMedian':med_on,
        'medianOverheadPercent':overhead_pct,
        'pairedOverheadPercent':paired,
        'pairedMedianOverheadPercent':paired_med,
        'pairedMedianDeltaSecondsPerStep':paired_delta_med,
        'pairedMedianDeltaMicrosecondsPerStep':1.0e6*paired_delta_med,
        'pairedOverheadPercentMin':min(paired) if paired else float('nan'),
        'pairedOverheadPercentMax':max(paired) if paired else float('nan'),
        'pairedMadPercent':pair_mad,
        'offMeanSecondsPerStep':mean(off),
        'onMeanSecondsPerStep':mean(on),
        'offCvPercent':100.0*cv_off,
        'onCvPercent':100.0*cv_on,
        'runToRunNoiseProxyPercent':noise_pct,
        'contract':'binary-only /usr/bin/time from x14ah runner; LiveVis/recording off; same seed/physics; OFF/ON order alternated'
    }
    out_path.parent.mkdir(parents=True,exist_ok=True)
    out_path.write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
    print('[0493x14ai-cost] status='+status)
    print(f'[0493x14ai-cost] OFF median={med_off:.9g} s/step')
    print(f'[0493x14ai-cost] ON  median={med_on:.9g} s/step')
    print(f'[0493x14ai-cost] median overhead={overhead_pct:+.3f}% pairedMedian={paired_med:+.3f}% pairedMAD={pair_mad:.3f}%')
    print(f'[0493x14ai-cost] paired median delta={1.0e6*paired_delta_med:+.1f} us/step range=[{min(paired):+.3f},{max(paired):+.3f}]%')
    print(f'[0493x14ai-cost] run-to-run noise proxy={noise_pct:.3f}%')
    print(f'[0493x14ai-cost] json={out_path}')

if __name__=='__main__': main()

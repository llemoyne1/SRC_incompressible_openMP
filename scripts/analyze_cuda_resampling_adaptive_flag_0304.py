#!/usr/bin/env python3
import csv
import sys
from pathlib import Path


def read_csv(path):
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline='') as fh:
        return list(csv.DictReader(fh))


def as_float(row, key, default=0.0):
    try:
        return float(row.get(key, default) or default)
    except Exception:
        return default


def as_int(row, key, default=0):
    try:
        return int(float(row.get(key, default) or default))
    except Exception:
        return default


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: analyze_cuda_resampling_adaptive_flag_0304.py RUN_MANIFEST ART_DIR')
    manifest_path = Path(sys.argv[1])
    art_dir = Path(sys.argv[2])
    runs = read_csv(manifest_path)
    per_run = []
    timeseries = []
    for r in runs:
        run_root = Path(r['runRoot'])
        output_dir = run_root / 'output'
        summary_rows = read_csv(output_dir / 'summary_runtime.csv')
        flag_rows = read_csv(output_dir / 'cuda_resampling_adaptive_flag_0304.csv')
        final_summary = summary_rows[-1] if summary_rows else {}
        final_flag = flag_rows[-1] if flag_rows else {}
        trigger_rows = sum(as_int(row, 'triggerFlag') for row in flag_rows)
        low_rows = sum(as_int(row, 'triggeredByLowN') for row in flag_rows)
        empty_rows = sum(as_int(row, 'triggeredByEmpty') for row in flag_rows)
        max_empty = max([as_int(row, 'emptyWetCells') for row in flag_rows], default=0)
        max_low = max([as_int(row, 'lowNCells') for row in flag_rows], default=0)
        min_wet_values = [as_int(row, 'minNWet') for row in flag_rows if as_int(row, 'wetCells') > 0]
        min_min_wet = min(min_wet_values) if min_wet_values else 0
        mean_flag_seconds = (sum(as_float(row, 'totalSeconds') for row in flag_rows) / len(flag_rows)) if flag_rows else 0.0
        per_run.append({
            'caseName': r.get('caseName',''),
            'modeName': r.get('modeName',''),
            'uin': r.get('uin',''),
            'flagEvery': r.get('flagEvery',''),
            'triggerNMin': r.get('triggerNMin',''),
            'exitCode': r.get('exitCode',''),
            'runRoot': str(run_root),
            'summaryRows': len(summary_rows),
            'flagRows': len(flag_rows),
            'triggerRows': trigger_rows,
            'lowNTriggerRows': low_rows,
            'emptyTriggerRows': empty_rows,
            'maxEmptyWetCells': max_empty,
            'maxLowNCells': max_low,
            'minMinNWet': min_min_wet,
            'finalEmptyWetCells': as_int(final_flag, 'emptyWetCells'),
            'finalLowNCells': as_int(final_flag, 'lowNCells'),
            'finalTriggerFlag': as_int(final_flag, 'triggerFlag'),
            'finalMinNWet': as_int(final_flag, 'minNWet'),
            'finalMaxNWet': as_int(final_flag, 'maxNWet'),
            'meanFlagSeconds': mean_flag_seconds,
            'finalNFluidParticles': final_summary.get('nFluidParticles',''),
            'finalTotalMass': final_summary.get('totalMass',''),
            'finalPx': final_summary.get('Px',''),
            'finalPy': final_summary.get('Py',''),
            'finalKBT': final_summary.get('kBTEstimate',''),
            'finalStdN': final_summary.get('stdN',''),
            'finalMinN': final_summary.get('minN',''),
            'finalMaxN': final_summary.get('maxN',''),
            'wallTime': final_summary.get('wallTime',''),
        })
        for row in flag_rows:
            timeseries.append({
                'caseName': r.get('caseName',''),
                'modeName': r.get('modeName',''),
                'uin': r.get('uin',''),
                'step': row.get('step',''),
                'triggerFlag': row.get('triggerFlag',''),
                'triggeredByLowN': row.get('triggeredByLowN',''),
                'triggeredByEmpty': row.get('triggeredByEmpty',''),
                'emptyWetCells': row.get('emptyWetCells',''),
                'lowNCells': row.get('lowNCells',''),
                'minNWet': row.get('minNWet',''),
                'maxNWet': row.get('maxNWet',''),
                'totalSeconds': row.get('totalSeconds',''),
            })
    out1 = art_dir / 'cuda_resampling_adaptive_flag_0304_per_run.csv'
    out2 = art_dir / 'cuda_resampling_adaptive_flag_0304_timeseries.csv'
    if per_run:
        with out1.open('w', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=list(per_run[0].keys()))
            w.writeheader(); w.writerows(per_run)
    if timeseries:
        with out2.open('w', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=list(timeseries[0].keys()))
            w.writeheader(); w.writerows(timeseries)
    print(f'[0304-flag-analyze] per-run={out1}')
    print(f'[0304-flag-analyze] timeseries={out2}')


if __name__ == '__main__':
    main()

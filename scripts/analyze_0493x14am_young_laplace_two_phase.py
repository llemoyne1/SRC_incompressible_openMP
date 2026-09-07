#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path


def fval(row, key):
    try:
        v = float(row[key])
    except (KeyError, ValueError, TypeError):
        return float('nan')
    return v


def mean(xs):
    xs = [x for x in xs if math.isfinite(x)]
    return sum(xs) / len(xs) if xs else float('nan')


def stdev(xs):
    xs = [x for x in xs if math.isfinite(x)]
    return statistics.stdev(xs) if len(xs) >= 2 else 0.0 if xs else float('nan')


def sem(xs):
    xs = [x for x in xs if math.isfinite(x)]
    return stdev(xs) / math.sqrt(len(xs)) if xs else float('nan')


def linreg(xs, ys):
    pts = [(x, y) for x, y in zip(xs, ys) if math.isfinite(x) and math.isfinite(y)]
    if len(pts) < 2:
        return dict(n=len(pts), slope=float('nan'), intercept=float('nan'), r2=float('nan'))
    mx = sum(x for x, _ in pts) / len(pts)
    my = sum(y for _, y in pts) / len(pts)
    sxx = sum((x-mx)**2 for x, _ in pts)
    sxy = sum((x-mx)*(y-my) for x, y in pts)
    slope = sxy/sxx if sxx > 0 else float('nan')
    intercept = my - slope*mx
    ss_tot = sum((y-my)**2 for _, y in pts)
    ss_res = sum((y-(intercept+slope*x))**2 for x, y in pts)
    r2 = 1.0 - ss_res/ss_tot if ss_tot > 0 else 1.0
    return dict(n=len(pts), slope=slope, intercept=intercept, r2=r2)


def origin_slope(xs, ys):
    pts = [(x, y) for x, y in zip(xs, ys) if math.isfinite(x) and math.isfinite(y)]
    den = sum(x*x for x, _ in pts)
    return sum(x*y for x, y in pts)/den if den > 0 else float('nan')


def read_csv(path: Path):
    with path.open(newline='') as f:
        return list(csv.DictReader(f))


def run_summary(entry, tail_start):
    run_dir = Path(entry['run_dir'])
    pressure = run_dir/'output'/'cuda_static_drop_pressure_0493x9e.csv'
    if not pressure.is_file():
        raise RuntimeError(f'missing pressure diagnostic: {pressure}')
    rows = read_csv(pressure)
    if not rows:
        raise RuntimeError(f'empty pressure diagnostic: {pressure}')
    max_step = max(fval(r, 'step') for r in rows)
    tail_step = tail_start * max_step
    tail = [r for r in rows if fval(r, 'step') >= tail_step]
    if len(tail) < 10:
        raise RuntimeError(f'not enough tail samples in {pressure}: {len(tail)}')

    def vals(k): return [fval(r, k) for r in tail]
    out = {
        'radiusCellsDeclared': float(entry['radius_cells']),
        'replicate': int(entry['replicate']),
        'seed': int(entry['seed']),
        'runDir': str(run_dir),
        'tailStartStep': tail_step,
        'tailSamples': len(tail),
        'effectiveRadiusMean': mean(vals('effectiveRadius')),
        'effectiveRadiusStd': stdev(vals('effectiveRadius')),
        'equivalentCurvatureMean': mean(vals('equivalentCurvature')),
        'activeCurvatureMean': mean(vals('curvatureMean')),
        'activeCurvatureStdTemporal': stdev(vals('curvatureMean')),
        'pressureJumpMean': mean(vals('measuredPressureJump')),
        'pressureJumpStdTemporal': stdev(vals('measuredPressureJump')),
        'pressureJumpSemTemporal': sem(vals('measuredPressureJump')),
        'laplaceTargetMean': mean(vals('laplaceTargetCurrent')),
        'pressureJumpErrorMean': mean(vals('pressureJumpError')),
        'deepLiquidCellsMin': min(fval(r, 'deepLiquidCells') for r in tail),
        'deepGasCellsMin': min(fval(r, 'deepGasCells') for r in tail),
        'normalizedDiscreteResultantMean': mean(vals('normalizedDiscreteResultant')),
        'normalizedDiscreteResultantMax': max(vals('normalizedDiscreteResultant')),
        'discreteAbsTractionMean': mean(vals('discreteAbsTraction')),
    }
    out['jumpOverTarget'] = (out['pressureJumpMean']/out['laplaceTargetMean']
                             if out['laplaceTargetMean'] else float('nan'))

    limiter = run_dir/'output'/'cuda_surface_tension_limiter_0493x9r.csv'
    out['clipFractionMax'] = 0.0
    out['clipFractionMean'] = 0.0
    if limiter.is_file():
        lrows = read_csv(limiter)
        if lrows:
            lmax = max(fval(r, 'step') for r in lrows)
            ltail = [r for r in lrows if fval(r, 'step') >= tail_start*lmax]
            fr = []
            for r in ltail:
                cf = fval(r, 'clipFraction')
                if math.isfinite(cf):
                    fr.append(cf)
                    continue
                n = fval(r, 'capillaryFaces')
                c = fval(r, 'clippedFaces')
                if math.isfinite(n) and n > 0 and math.isfinite(c):
                    fr.append(c/n)
            if fr:
                out['clipFractionMax'] = max(fr)
                out['clipFractionMean'] = mean(fr)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', type=Path, required=True)
    ap.add_argument('--output-dir', type=Path, required=True)
    ap.add_argument('--sigma', type=float, required=True)
    ap.add_argument('--tail-start', type=float, default=0.5)
    args = ap.parse_args()
    if not (0.0 <= args.tail_start < 1.0):
        ap.error('--tail-start must be in [0,1)')
    with args.manifest.open(newline='') as f:
        manifest = list(csv.DictReader(f))
    if not manifest:
        raise SystemExit('[0493x14am-analysis] empty manifest')

    runs = [run_summary(e, args.tail_start) for e in manifest]
    by_r = defaultdict(list)
    for r in runs:
        by_r[r['radiusCellsDeclared']].append(r)

    groups = []
    for rc in sorted(by_r):
        rr = by_r[rc]
        def m(k): return mean([x[k] for x in rr])
        def sd(k): return stdev([x[k] for x in rr])
        groups.append({
            'radiusCellsDeclared': rc,
            'replicates': len(rr),
            'effectiveRadiusMean': m('effectiveRadiusMean'),
            'equivalentCurvatureMean': m('equivalentCurvatureMean'),
            'activeCurvatureMean': m('activeCurvatureMean'),
            'activeCurvatureAcrossRepStd': sd('activeCurvatureMean'),
            'pressureJumpMean': m('pressureJumpMean'),
            'pressureJumpAcrossRepStd': sd('pressureJumpMean'),
            'laplaceTargetMean': m('laplaceTargetMean'),
            'jumpOverTargetMean': m('jumpOverTarget'),
            'clipFractionMax': max(x['clipFractionMax'] for x in rr),
            'normalizedDiscreteResultantMax': max(x['normalizedDiscreteResultantMax'] for x in rr),
            'deepLiquidCellsMin': min(x['deepLiquidCellsMin'] for x in rr),
            'deepGasCellsMin': min(x['deepGasCellsMin'] for x in rr),
        })

    x_face = [g['activeCurvatureMean'] for g in groups]
    x_eq = [g['equivalentCurvatureMean'] for g in groups]
    y = [g['pressureJumpMean'] for g in groups]
    fit_face = linreg(x_face, y)
    fit_eq = linreg(x_eq, y)
    face0 = origin_slope(x_face, y)
    eq0 = origin_slope(x_eq, y)
    sigma = args.sigma
    med_jump = statistics.median(abs(v) for v in y if math.isfinite(v)) if y else float('nan')
    intercept_rel = abs(fit_face['intercept'])/med_jump if med_jump and math.isfinite(med_jump) else float('nan')
    max_clip = max(g['clipFractionMax'] for g in groups)
    face_gain = fit_face['slope']/sigma
    face_gain0 = face0/sigma
    # Screening gate only; final scientific qualification remains a human decision.
    candidate = (
        math.isfinite(face_gain) and abs(face_gain-1.0) <= 0.05 and
        math.isfinite(fit_face['r2']) and fit_face['r2'] >= 0.98 and
        math.isfinite(intercept_rel) and intercept_rel <= 0.05 and
        max_clip <= 0.01 and
        all(g['deepLiquidCellsMin'] > 0 and g['deepGasCellsMin'] > 0 for g in groups)
    )
    status = 'MECHANICAL_PASS_CANDIDATE' if candidate else 'REVIEW'

    result = {
        'benchmark': '0493x14am_two_phase_young_laplace_multiradius',
        'sigmaDeclared': sigma,
        'tailStartFraction': args.tail_start,
        'status': status,
        'statusIsScreeningOnly': True,
        'primaryFit': {
            'definition': 'tail-mean deep-liquid Q6 gauge pressure minus deep-gas x6g EOS gauge pressure versus tail-mean active p3 face curvature',
            **fit_face,
            'sigmaEff': fit_face['slope'],
            'Gsigma': face_gain,
            'sigmaEffThroughOrigin': face0,
            'GsigmaThroughOrigin': face_gain0,
            'interceptRelativeToMedianJump': intercept_rel,
        },
        'equivalentRadiusCrosscheck': {
            **fit_eq,
            'sigmaEff': fit_eq['slope'],
            'Gsigma': fit_eq['slope']/sigma,
            'sigmaEffThroughOrigin': eq0,
            'GsigmaThroughOrigin': eq0/sigma,
        },
        'maxClipFraction': max_clip,
        'groups': groups,
        'runs': runs,
        'screeningCriteria': {
            'absGsigmaMinus1Max': 0.05,
            'r2Min': 0.98,
            'interceptRelativeMax': 0.05,
            'clipFractionMax': 0.01,
            'requireDeepLiquidAndGas': True,
        },
    }

    args.output_dir.mkdir(parents=True, exist_ok=True)
    js = args.output_dir/'young_laplace_two_phase_0493x14am.json'
    js.write_text(json.dumps(result, indent=2) + '\n')

    runcsv = args.output_dir/'young_laplace_runs_0493x14am.csv'
    with runcsv.open('w', newline='') as f:
        keys = list(runs[0].keys())
        w = csv.DictWriter(f, fieldnames=keys); w.writeheader(); w.writerows(runs)
    gcsv = args.output_dir/'young_laplace_by_radius_0493x14am.csv'
    with gcsv.open('w', newline='') as f:
        keys = list(groups[0].keys())
        w = csv.DictWriter(f, fieldnames=keys); w.writeheader(); w.writerows(groups)

    txt = args.output_dir/'young_laplace_report_0493x14am.txt'
    lines = [
        '0493x14am — two-phase Young-Laplace multi-radius',
        '=================================================',
        f'status(screening only) = {status}',
        f'sigmaDeclared = {sigma:.12g}',
        '',
        'PRIMARY — active p3 face curvature:',
        f"sigmaEff = {fit_face['slope']:.12g}",
        f'G_sigma = {face_gain:.9g}',
        f"intercept = {fit_face['intercept']:.12g}",
        f"R2 = {fit_face['r2']:.9g}",
        f'sigmaEff(origin) = {face0:.12g}',
        f'G_sigma(origin) = {face_gain0:.9g}',
        f'intercept/median|dp| = {intercept_rel:.6g}',
        '',
        'CROSS-CHECK — equivalent curvature 1/R_eff:',
        f"sigmaEff = {fit_eq['slope']:.12g}",
        f"G_sigma = {fit_eq['slope']/sigma:.9g}",
        f"intercept = {fit_eq['intercept']:.12g}",
        f"R2 = {fit_eq['r2']:.9g}",
        '',
        'BY RADIUS:',
        'R/h    reps   kappa_active       dp_measured        dp/target    clipMax',
    ]
    for g in groups:
        lines.append(f"{g['radiusCellsDeclared']:5.1f}  {g['replicates']:4d}  "
                     f"{g['activeCurvatureMean']:16.9g}  {g['pressureJumpMean']:16.9g}  "
                     f"{g['jumpOverTargetMean']:10.6g}  {g['clipFractionMax']:9.3g}")
    lines += [
        '',
        'Interpretation contract:',
        '- no sigma=0 long baseline is used;',
        '- pressure jump is measured directly in one two-phase run/gauge;',
        '- x9e is an existing runtime diagnostic; this analyzer adds no solver instrumentation;',
        '- screening status is not a production freeze decision.',
        f'json = {js}',
    ]
    txt.write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    main()

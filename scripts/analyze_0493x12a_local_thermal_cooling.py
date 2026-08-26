#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path
import statistics


def read_rows(path):
    with path.open(newline='') as f:
        return list(csv.DictReader(f))


def fnum(row, key, default=float('nan')):
    try:
        return float(row.get(key, ''))
    except (TypeError, ValueError):
        return default


def main():
    ap = argparse.ArgumentParser(description='Summarize existing 0491f thermostat evidence for x12a.')
    ap.add_argument('run_dir', help='run case directory, e.g. runs/... or its output directory')
    ap.add_argument('--radius-cells', type=float, default=None,
                    help='static-drop R/h; when given, report expected x12a effective target')
    ap.add_argument('--radius-cut-cells', type=float, default=25.298221281347036)
    args = ap.parse_args()

    root = Path(args.run_dir)
    candidates = [
        root / 'cuda_species_q6_energy_0491f.csv',
        root / 'output' / 'cuda_species_q6_energy_0491f.csv',
        root / 'capillary' / 'output' / 'cuda_species_q6_energy_0491f.csv',
    ]
    energy = next((p for p in candidates if p.is_file()), None)
    if energy is None:
        raise SystemExit('missing cuda_species_q6_energy_0491f.csv under ' + str(root))

    rows = read_rows(energy)
    if not rows:
        raise SystemExit('empty ' + str(energy))
    tail = rows[max(0, len(rows)//2):]
    after = [fnum(r, 'thermostatKBTAfter') for r in tail]
    after = [x for x in after if math.isfinite(x)]
    before = [fnum(r, 'thermostatKBTBefore') for r in tail]
    before = [x for x in before if math.isfinite(x)]
    base = fnum(rows[-1], 'targetKBT')

    print('===== 0493x12a LOCAL THERMAL COOLING =====')
    print(f'file={energy} rows={len(rows)} lastStep={rows[-1].get("step","?")}')
    print(f'baseTargetKBT={base:.9g}')
    if before:
        print(f'tailMedianKBTBefore={statistics.median(before):.9g}')
    if after:
        med = statistics.median(after)
        print(f'tailMedianEffectiveTarget={med:.9g}')
        print(f'lastEffectiveTarget={after[-1]:.9g}')
    else:
        med = float('nan')

    if args.radius_cells is not None and math.isfinite(base):
        sqrtf = min(1.0, max(0.0, args.radius_cells / args.radius_cut_cells))
        factor = sqrtf * sqrtf
        expected = base * factor
        print(f'R/h={args.radius_cells:.9g} Rc/h={args.radius_cut_cells:.9g}')
        print(f'expectedFactor={factor:.9g} expectedEffectiveTarget={expected:.9g}')
        if math.isfinite(med) and expected > 0:
            rel = abs(med - expected) / expected
            print(f'medianRelativeDifference={rel:.3%}')
            if rel <= 0.15:
                print('thermalTargetContract=PASS_15PCT')
            else:
                print('thermalTargetContract=REVIEW')

    cross_candidates = [
        root / 'cuda_phase_kinetic_crossing_0493x9z.csv',
        root / 'output' / 'cuda_phase_kinetic_crossing_0493x9z.csv',
        root / 'capillary' / 'output' / 'cuda_phase_kinetic_crossing_0493x9z.csv',
    ]
    cross = next((p for p in cross_candidates if p.is_file()), None)
    if cross:
        cr = read_rows(cross)
        if cr:
            last = cr[-1]
            for key in ('preWallAlphaArea','alphaArea','preWallMeanVn','continuousWallCollisions'):
                if key in last:
                    print(f'{key}(last)={last[key]}')


if __name__ == '__main__':
    main()

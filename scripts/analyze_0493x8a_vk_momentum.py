#!/usr/bin/env python3
from __future__ import annotations
import argparse
import csv
import math
from pathlib import Path


def rows(path: Path):
    with path.open(newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def val(row, key, default=math.nan):
    try:
        return float(row[key])
    except Exception:
        return default


def parse_kv(path: Path):
    out = {}
    if not path.is_file():
        return out
    for raw in path.read_text().splitlines():
        line = raw.split('#', 1)[0].strip()
        if not line or '=' not in line:
            continue
        k, v = line.split('=', 1)
        out[k.strip()] = v.strip()
    return out


def analyze(run_dir: Path):
    od = run_dir / 'output'
    epath = od / 'darcy_exact_momentum_0493x8a.csv'
    spath = od / 'summary_runtime.csv'
    ppath = od / 'params_used.kv'
    E = rows(epath)
    S = rows(spath)
    if not E or len(S) < 2:
        raise RuntimeError(f'insufficient diagnostic rows: {run_dir}')
    s0, s1, e1 = S[0], S[-1], E[-1]
    p0, p1 = val(s0, 'Px'), val(s1, 'Px')
    m0, m1 = val(s0, 'totalMass'), val(s1, 'totalMass')
    scale = max(abs(p0), 1e-300)
    pars = parse_kv(ppath)
    dt = float(pars.get('dt', 'nan'))
    ax = float(pars.get('bodyAccelerationX', '0'))
    calls = int(round(val(e1, 'cumulativeCalls', 0)))
    body = ax * 0.5 * (m0 + m1) * dt * calls
    dp = p1 - p0
    darcy = val(e1, 'cumulativeMeanKickImpulseX')
    residual = dp - body - darcy
    whole = all(int(round(val(r, 'wholeDarcyApply', 0))) == 1 for r in E)
    applied = all(int(round(val(r, 'meanKickApplied', 0))) == 1 for r in E)
    return {
        'mode': run_dir.name,
        'runDir': str(run_dir),
        'Px0': p0, 'Px1': p1, 'deltaPx': dp, 'deltaPxOverP0': dp/scale,
        'mass0': m0, 'mass1': m1,
        'massRelativeChange': (m1-m0)/max(abs(m0),1e-300),
        'bodyImpulseX': body, 'bodyImpulseOverP0': body/scale,
        'exactDarcyImpulseX': darcy, 'exactDarcyImpulseOverP0': darcy/scale,
        'nonDarcyResidualImpulseX': residual,
        'nonDarcyResidualImpulseOverP0': residual/scale,
        'meanKickAppliedAllSamples': int(applied),
        'wholeDarcyApplyAllSamples': int(whole),
        'cumulativeCalls': calls,
        'finalMeanKickEquivalentAccelerationX': val(e1, 'meanKickEquivalentAccelerationX'),
        'finalDarcyReactionProxyX': val(e1, 'darcyReactionProxyX'),
        'finalDarcyPower': val(e1, 'darcyPower'),
        'finalSolidLeakRms': val(e1, 'solidLeakRms'),
        'q6GfPrestreamFinal': int(round(val(e1, 'q6GfPrestream', 0))),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', type=Path, default=Path('runs/0493x8a_vk_momentum_750'))
    ap.add_argument('--output', type=Path,
                    default=Path('runs/0493x8a_vk_momentum_750/momentum_decision_0493x8a.csv'))
    a = ap.parse_args()
    data = [analyze(a.root / m) for m in ('src', 'src-q6', 'src-q6-g-f')]
    a.output.parent.mkdir(parents=True, exist_ok=True)
    with a.output.open('w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=list(data[0]))
        w.writeheader(); w.writerows(data)
    print('\n===== 0493x8a EXACT DARCY MOMENTUM DECISION =====')
    print('mode          dPx/P0       body/P0       Darcy/P0      residual/P0   whole calls')
    for r in data:
        print(f"{r['mode']:<12s} {r['deltaPxOverP0']:+.6f}  "
              f"{r['bodyImpulseOverP0']:+.6e}  {r['exactDarcyImpulseOverP0']:+.6f}  "
              f"{r['nonDarcyResidualImpulseOverP0']:+.6f}    "
              f"{r['wholeDarcyApplyAllSamples']}    {r['cumulativeCalls']}")
    print('\nidentity: deltaPx = bodyImpulse + exactDarcyImpulse + nonDarcyResidual')
    print('required for primary VK: meanKickApplied=1 and wholeDarcyApply=1')
    print(f'output={a.output}')
    print('status=COMPLETE')


if __name__ == '__main__':
    main()

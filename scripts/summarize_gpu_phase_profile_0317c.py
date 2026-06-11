#!/usr/bin/env python3
from __future__ import annotations

import csv
import os
import sys
from pathlib import Path
from typing import Dict, List


def read_csv(path: Path) -> List[dict]:
    if not path.exists():
        return []
    with path.open(newline='', errors='replace') as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: List[dict], fields: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, '') for k in fields})


def fnum(x, default=0.0):
    try:
        if x is None or x == '':
            return default
        return float(x)
    except Exception:
        return default


def read_time_file(path: str) -> Dict[str, float]:
    out: Dict[str, float] = {}
    if not path or not os.path.exists(path):
        return out
    with open(path, newline='') as f:
        for row in csv.reader(f):
            if len(row) >= 2:
                out[row[0]] = fnum(row[1])
    return out


def last_runtime(run_root: Path) -> dict:
    rows = read_csv(run_root / 'output' / 'summary_runtime.csv')
    return rows[-1] if rows else {}


def sum_cuda_persistent(run_root: Path) -> dict:
    rows = read_csv(run_root / 'output' / 'cuda_persistent_src_collision_thermostat_0215.csv')
    sums = {
        'srcPersistentUpload_s': 0.0,
        'srcPersistentKernel_s': 0.0,
        'srcPersistentDownload_s': 0.0,
        'srcPersistentTotal_s': 0.0,
        'srcPersistentRows': len(rows),
    }
    for r in rows:
        sums['srcPersistentUpload_s'] += fnum(r.get('uploadSeconds'))
        sums['srcPersistentKernel_s'] += fnum(r.get('kernelSeconds'))
        sums['srcPersistentDownload_s'] += fnum(r.get('downloadSeconds'))
        sums['srcPersistentTotal_s'] += fnum(r.get('totalSeconds'))
    return sums


def phase_breakdown(target: str, repeat: str, run_root: Path) -> List[dict]:
    out: List[dict] = []
    for r in read_csv(run_root / 'output' / 'phase_profile_0163.csv'):
        out.append({
            'target': target,
            'repeat': repeat,
            'phase': r.get('phase', ''),
            'total_s': r.get('total_s', ''),
            'ms_per_step': r.get('ms_per_step', ''),
            'percent_total': r.get('percent_total', ''),
        })
    return out


def resident_breakdown(target: str, repeat: str, run_root: Path) -> List[dict]:
    rows = read_csv(run_root / 'output' / 'cuda_resident_phase_profile_0266.csv')
    agg: Dict[tuple, dict] = {}
    for r in rows:
        key = (r.get('mode', ''), r.get('phase', ''), r.get('requested', ''), r.get('supported', ''), r.get('handled', ''), r.get('applied', ''))
        a = agg.setdefault(key, {
            'target': target,
            'repeat': repeat,
            'mode': key[0], 'phase': key[1],
            'requested': key[2], 'supported': key[3], 'handled': key[4], 'applied': key[5],
            'rows': 0, 'upload_s': 0.0, 'kernel_s': 0.0, 'download_s': 0.0, 'total_s': 0.0,
            'uploadCalls': 0.0, 'downloadCalls': 0.0,
            'fluidParticles_max': 0.0,
        })
        a['rows'] += 1
        a['upload_s'] += fnum(r.get('uploadSeconds'))
        a['kernel_s'] += fnum(r.get('kernelSeconds'))
        a['download_s'] += fnum(r.get('downloadSeconds'))
        a['total_s'] += fnum(r.get('totalSeconds'))
        a['uploadCalls'] += fnum(r.get('uploadCalls'))
        a['downloadCalls'] += fnum(r.get('downloadCalls'))
        a['fluidParticles_max'] = max(a['fluidParticles_max'], fnum(r.get('fluidParticles')))
    out = list(agg.values())
    out.sort(key=lambda r: r['total_s'], reverse=True)
    return out


def main() -> int:
    if len(sys.argv) != 3:
        print('usage: summarize_gpu_phase_profile_0317c.py MANIFEST ART_DIR', file=sys.stderr)
        return 2
    manifest = Path(sys.argv[1])
    art_dir = Path(sys.argv[2])
    rows = read_csv(manifest)

    summary_rows: List[dict] = []
    phase_rows: List[dict] = []
    resident_rows: List[dict] = []
    for m in rows:
        target = m.get('target', '')
        rep = m.get('repeat', '')
        run_root = Path(m.get('runRoot', ''))
        t = read_time_file(m.get('timeFile', ''))
        runtime = last_runtime(run_root)
        cuda = sum_cuda_persistent(run_root)
        elapsed = t.get('elapsed_seconds', 0.0)
        steps = fnum(m.get('steps'))
        sim_wall = fnum(runtime.get('wallTime'))
        active = fnum(runtime.get('nFluidParticles')) or fnum(runtime.get('nFluid'))
        persistent_total = cuda['srcPersistentTotal_s']
        summary_rows.append({
            'target': target,
            'repeat': rep,
            'exitCode': m.get('exitCode', ''),
            'steps': int(steps) if steps else m.get('steps', ''),
            'elapsed_s': elapsed,
            'elapsed_ms_per_step': 1000.0 * elapsed / steps if steps else '',
            'simWall_s': sim_wall if sim_wall else '',
            'simWall_ms_per_step': 1000.0 * sim_wall / steps if steps and sim_wall else '',
            'nFluidParticles': active if active else '',
            **cuda,
            'srcPersistentTotal_percent_elapsed': 100.0 * persistent_total / elapsed if elapsed and persistent_total else '',
            'srcPersistentKernel_percent_elapsed': 100.0 * cuda['srcPersistentKernel_s'] / elapsed if elapsed and cuda['srcPersistentKernel_s'] else '',
            'srcPersistentTransfer_percent_elapsed': 100.0 * (cuda['srcPersistentUpload_s'] + cuda['srcPersistentDownload_s']) / elapsed if elapsed and persistent_total else '',
            'unaccountedByPersistent_s': elapsed - persistent_total if elapsed and persistent_total else '',
            'unaccountedByPersistent_percent_elapsed': 100.0 * (elapsed - persistent_total) / elapsed if elapsed and persistent_total else '',
            'runRoot': str(run_root),
            'note': m.get('note', ''),
        })
        phase_rows.extend(phase_breakdown(target, rep, run_root))
        resident_rows.extend(resident_breakdown(target, rep, run_root))

    write_csv(art_dir / 'gpu_phase_profile_0317c_summary.csv', summary_rows, [
        'target','repeat','exitCode','steps','elapsed_s','elapsed_ms_per_step','simWall_s','simWall_ms_per_step',
        'nFluidParticles','srcPersistentRows','srcPersistentUpload_s','srcPersistentKernel_s','srcPersistentDownload_s',
        'srcPersistentTotal_s','srcPersistentTotal_percent_elapsed','srcPersistentKernel_percent_elapsed',
        'srcPersistentTransfer_percent_elapsed','unaccountedByPersistent_s','unaccountedByPersistent_percent_elapsed',
        'runRoot','note'
    ])
    write_csv(art_dir / 'gpu_phase_profile_0317c_src_phase_breakdown.csv', phase_rows, [
        'target','repeat','phase','total_s','ms_per_step','percent_total'
    ])
    write_csv(art_dir / 'gpu_phase_profile_0317c_cuda_resident_breakdown.csv', resident_rows, [
        'target','repeat','mode','phase','requested','supported','handled','applied','rows',
        'upload_s','kernel_s','download_s','total_s','uploadCalls','downloadCalls','fluidParticles_max'
    ])
    print(f'[0317c-summary] wrote {art_dir / "gpu_phase_profile_0317c_summary.csv"}')
    print(f'[0317c-summary] wrote {art_dir / "gpu_phase_profile_0317c_src_phase_breakdown.csv"}')
    print(f'[0317c-summary] wrote {art_dir / "gpu_phase_profile_0317c_cuda_resident_breakdown.csv"}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

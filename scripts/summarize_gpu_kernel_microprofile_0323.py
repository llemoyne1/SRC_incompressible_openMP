#!/usr/bin/env python3
import csv
import re
import sys
from pathlib import Path
from collections import defaultdict


def clean_float(value):
    if value is None:
        return None
    s = str(value).strip().strip('"')
    if not s or s.lower() in {'na','n/a','nan'}:
        return None
    s = s.replace(',', '')
    m = re.search(r'[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?', s)
    if not m:
        return None
    try:
        return float(m.group(0))
    except ValueError:
        return None


def unit_to_seconds(value, unit):
    x = clean_float(value)
    if x is None:
        return None
    u = (unit or '').strip().lower()
    if u in {'second','seconds','s','sec'}:
        return x
    if u in {'millisecond','milliseconds','ms'}:
        return x * 1e-3
    if u in {'microsecond','microseconds','us','usecond','useconds','µs'}:
        return x * 1e-6
    if u in {'nanosecond','nanoseconds','ns'}:
        return x * 1e-9
    # Nsight Compute gpu__time_duration.sum is usually reported in nsecond/usecond
    # with an explicit unit column.  If the unit is absent, keep seconds only if
    # the value looks already small; otherwise treat it as ns conservatively.
    return x if x < 1000.0 else x * 1e-9


def parse_ncu_csv(path):
    rows = []
    with open(path, newline='', errors='replace') as f:
        sample = f.read(4096)
        f.seek(0)
        # Skip comment/banner lines until a CSV header containing Metric Name or Kernel Name.
        lines = [line for line in f if ('Metric Name' in line and 'Metric Value' in line) or line.startswith('"ID"') or line.startswith('ID,')]
        if not lines:
            f.seek(0)
            lines = [line for line in f if ',' in line]
        text = ''.join(lines)
    if not text.strip():
        return rows
    for r in csv.DictReader(text.splitlines()):
        metric = (r.get('Metric Name') or r.get('Metric') or '').strip()
        if metric and 'gpu__time_duration' not in metric:
            continue
        name = (r.get('Kernel Name') or r.get('Name') or r.get('Kernel') or r.get('Mangled Name') or '').strip()
        if not name:
            # Try any column that looks like a kernel name.
            for k,v in r.items():
                if v and ('kernel' in k.lower() or 'name' in k.lower()):
                    name = str(v).strip()
                    break
        value = r.get('Metric Value') or r.get('Duration') or r.get('Time') or r.get('Avg')
        unit = r.get('Metric Unit') or r.get('Unit') or ''
        sec = unit_to_seconds(value, unit)
        if name and sec is not None:
            rows.append((name, sec, 'ncu'))
    return rows


def parse_nvprof_csv(path):
    rows = []
    with open(path, errors='replace') as f:
        text = f.read()
    # nvprof --csv normally has several banner/comment lines, then a table.
    lines = [ln for ln in text.splitlines() if ',' in ln and not ln.startswith('==')]
    for i, ln in enumerate(lines):
        if 'Name' in ln and ('Duration' in ln or 'Time' in ln):
            table = '\n'.join(lines[i:])
            break
    else:
        return rows
    for r in csv.DictReader(table.splitlines()):
        name = (r.get('Name') or r.get('Kernel') or '').strip()
        dur = r.get('Duration') or r.get('Time')
        unit = r.get('Duration Unit') or r.get('Time Unit') or ''
        sec = unit_to_seconds(dur, unit)
        if name and sec is not None:
            rows.append((name, sec, 'nvprof'))
    return rows


def parse_raw(path):
    txt = Path(path).read_text(errors='replace')[:4096]
    if 'profiler_unavailable' in txt:
        return []
    rows = parse_ncu_csv(path)
    if rows:
        return rows
    return parse_nvprof_csv(path)


def main():
    art = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('dev_history/artifacts/gpu_kernel_microprofile_0323')
    manifest = art / 'gpu_kernel_microprofile_0323_manifest.csv'
    summary = art / 'gpu_kernel_microprofile_0323_top_kernels.csv'
    by_target = []
    if not manifest.exists():
        summary.write_text('target,kernel,total_s,percent,count,profiler\n')
        return
    for m in csv.DictReader(manifest.read_text().splitlines()):
        target = m['target']
        raw = Path(m['rawFile'])
        if not raw.exists():
            by_target.append((target, 'RAW_FILE_MISSING', 0.0, 0.0, 0, m.get('profiler','')))
            continue
        rows = parse_raw(raw)
        agg = defaultdict(float); count = defaultdict(int); profiler = m.get('profiler','')
        for name, sec, prof in rows:
            agg[name] += sec
            count[name] += 1
            profiler = prof
        total = sum(agg.values())
        if not agg:
            by_target.append((target, 'NO_KERNEL_ROWS_PARSED', 0.0, 0.0, 0, profiler))
        else:
            for name, sec in sorted(agg.items(), key=lambda kv: kv[1], reverse=True)[:30]:
                pct = 100.0 * sec / total if total > 0 else 0.0
                by_target.append((target, name, sec, pct, count[name], profiler))
    with summary.open('w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['target','kernel','total_s','percent','count','profiler'])
        for row in by_target:
            w.writerow(row)

if __name__ == '__main__':
    main()

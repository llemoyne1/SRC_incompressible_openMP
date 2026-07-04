#!/usr/bin/env bash
set -euo pipefail

: "${BASE_AUDIT_ROOT:=runs/0465_residency_audit}"
: "${PROFILE_ROOTS:=runs/0463_scaling_cuda_vs_cpu runs/0464_scaling_gate_every_200 runs/0463_sparse_gate_endurance runs/0462_sparse_gate_stress}"
: "${SRC_FILE:=src/cuda_resampling_pipeline_shadow_0445.cu}"

mkdir -p "$BASE_AUDIT_ROOT"
REPORT="$BASE_AUDIT_ROOT/residency_audit_report_0465.md"
EXCERPT="$BASE_AUDIT_ROOT/source_residency_excerpts_0465.txt"
CSV="$BASE_AUDIT_ROOT/residency_audit_summary_0465.csv"

{
  echo "# 0465 CUDA resampling residency audit"
  echo
  echo "Scope: identify why the validated 0460/0461 CUDA sparse-gate resampling path does not yet scale faster than the CPU baseline. This audit does not change solver behavior; it summarizes source-level host/device roundtrips and timing fractions from existing probe CSVs."
  echo
  echo "Profile roots: \`$PROFILE_ROOTS\`"
  echo
  echo "## Git reference"
  echo
  echo '```text'
  git log --oneline -10 || true
  echo '```'
  echo
  echo "## Working tree"
  echo
  echo '```text'
  git status --short || true
  echo '```'
  echo
} > "$REPORT"

{
  echo "# Source residency excerpts"
  echo
  echo "## Host/device copies and local buffers"
  grep -nE "apply_gpu_particle_edits_device_carrier_0455|upload_all\(|download_all\(|uploadSeconds|gateDownloadSeconds|stateDownloadSeconds|copy_from_host|copy_to_host|DeviceBuffer0445|thrust::stable_sort_by_key|materialize_passive_ops_donor_slices_kernel|dExtApplied.copy_to_host|dInsApplied.copy_to_host" "$SRC_FILE" || true
  echo
  echo "## Device-carrier body around upload/materialize/apply/download"
  nl -ba "$SRC_FILE" | sed -n '920,1345p' || true
  echo
  echo "## Call sites / wrappers"
  grep -R "apply_gpu_particle_edits_device_carrier_0455\|device_carrier_0455\|MPCD_CUDA_RESAMPLING_DEVICE_CARRIER" -n src scripts main* 2>/dev/null || true
} > "$EXCERPT"

python3 - "$CSV" "$REPORT" $PROFILE_ROOTS <<'PYEMBED'
import csv
import glob
import os
import sys
import statistics
from pathlib import Path

out_csv = Path(sys.argv[1])
report = Path(sys.argv[2])
roots = sys.argv[3:]

KEYS = [
    'uploadSeconds',
    'materializeKernelSeconds',
    'gateDownloadSeconds',
    'applyKernelSeconds',
    'stateDownloadSeconds',
    'totalSeconds',
]

def fnum(row, key):
    try:
        return float(row.get(key, '') or 0.0)
    except Exception:
        return 0.0

def infer_case(path):
    parts = Path(path).parts
    for p in parts:
        if '_g' in p and 'x' in p:
            return p
    for p in parts:
        if p.startswith('seed_') or p.startswith('seed'):
            return p
    return '?'

def infer_mode(path):
    if 'src-q6-resampling' in path:
        return 'src-q6-resampling'
    if 'src-resampling' in path:
        return 'src-resampling'
    return '?'

def infer_root(path):
    for root in roots:
        try:
            if Path(path).resolve().is_relative_to(Path(root).resolve()):
                return root
        except Exception:
            if str(path).startswith(root):
                return root
    return '?'

files = []
for root in roots:
    files.extend(glob.glob(os.path.join(root, '**', 'cuda_resampling_device_carrier_0455.csv'), recursive=True))
files = sorted(set(files))

rows_out = []
for p in files:
    try:
        with open(p, newline='') as fh:
            rows = list(csv.DictReader(fh))
    except Exception:
        continue
    handled = [r for r in rows if ('handled' not in r) or fnum(r, 'handled') == 1.0]
    if not handled:
        continue
    means = {k: statistics.mean([fnum(r, k) for r in handled]) for k in KEYS}
    maxs = {k: max([fnum(r, k) for r in handled]) for k in KEYS}
    total = means['totalSeconds'] if means['totalSeconds'] > 0.0 else 1.0
    transfer = means['uploadSeconds'] + means['gateDownloadSeconds'] + means['stateDownloadSeconds']
    kernels = means['materializeKernelSeconds'] + means['applyKernelSeconds']
    row = {
        'root': infer_root(p),
        'case': infer_case(p),
        'mode': infer_mode(p),
        'rows': len(rows),
        'handled_rows': len(handled),
    }
    row.update({f'mean_{k}': means[k] for k in KEYS})
    row.update({f'max_{k}': maxs[k] for k in KEYS})
    row['mean_transfer_fraction'] = transfer / total
    row['mean_kernel_fraction'] = kernels / total
    row['path'] = p
    rows_out.append(row)

if rows_out:
    with out_csv.open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(rows_out[0].keys()))
        w.writeheader()
        w.writerows(rows_out)
else:
    out_csv.write_text('no_rows\n')

with report.open('a') as f:
    f.write('## Timing summary\n\n')
    f.write(f'Parsed device-carrier CSV files: **{len(files)}**\n\n')
    if not rows_out:
        f.write('No handled device-carrier timing rows found.\n')
    else:
        f.write('| root | case | mode | handled rows | mean total ms | mean upload ms | mean gate dl ms | mean state dl ms | mean materialize ms | mean apply ms | transfer fraction | kernel fraction |\n')
        f.write('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
        for r in rows_out:
            f.write(
                '| {root} | {case} | {mode} | {handled_rows} | {tot:.3f} | {up:.3f} | {gate:.3f} | {state:.3f} | {mat:.3f} | {app:.3f} | {tf:.3f} | {kf:.3f} |\n'.format(
                    root=r['root'],
                    case=r['case'],
                    mode=r['mode'],
                    handled_rows=r['handled_rows'],
                    tot=1e3*r['mean_totalSeconds'],
                    up=1e3*r['mean_uploadSeconds'],
                    gate=1e3*r['mean_gateDownloadSeconds'],
                    state=1e3*r['mean_stateDownloadSeconds'],
                    mat=1e3*r['mean_materializeKernelSeconds'],
                    app=1e3*r['mean_applyKernelSeconds'],
                    tf=r['mean_transfer_fraction'],
                    kf=r['mean_kernel_fraction'],
                )
            )
        f.write('\n')
        f.write('## Interpretation rule\n\n')
        f.write('- If `transfer fraction` is high, the bottleneck is non-resident host/device roundtrip, not CUDA particle-edit compute.\n')
        f.write('- If `kernel fraction` is high and dominated by `materializeKernelSeconds`, the next target is the Thrust/cell-list materializer.\n')
        f.write('- If `apply ms` is small, optimizing particle extraction/insertion kernels cannot produce the main speedup.\n\n')
        f.write(f'Flat CSV: `{out_csv}`\n')
PYEMBED

cat >> "$REPORT" <<EOF

## Source excerpt file

Detailed source/call-site excerpts were written to:

\`$EXCERPT\`
EOF

cat "$REPORT"

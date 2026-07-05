#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BASE_0476_ROOT="${BASE_0476_ROOT:-runs/0476_materializer_authoritative_phase_attribution}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0475b}"
SCALE_CASES="${SCALE_CASES:-128x128x40}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
STEPS="${STEPS:-200}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DEVICE_GATE_EVERY="${DEVICE_GATE_EVERY:-50}"
UPSTREAM_GATE_EVERY="${UPSTREAM_GATE_EVERY:-50}"
SEEDS="${SEEDS:-1628638}"
MAX_SUMMARY_DELTA_TOL="${MAX_SUMMARY_DELTA_TOL:-1e-9}"

if [[ ! -x "$BIN" ]]; then
  echo "[0476] missing executable: $BIN" >&2
  exit 2
fi

RUN_SIMULATION="${RUN_SIMULATION:-1}"
if [[ "$RUN_SIMULATION" == "1" ]]; then
  rm -rf "$BASE_0476_ROOT"
fi
mkdir -p "$BASE_0476_ROOT"

echo "[0476] root=$BASE_0476_ROOT cases=[$SCALE_CASES] modes=[$RUN_MODES]"
echo "[0476] 0475b is authoritative through the compact 0458 carrier bridge"

if [[ "$RUN_SIMULATION" == "1" ]]; then
MPCD_INTERNAL_PROFILES=1 \
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1 \
MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1 \
MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474=1 \
MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=1 \
MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A=1 \
MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1 \
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450="$UPSTREAM_GATE_EVERY" \
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_EVERY_0451="$UPSTREAM_GATE_EVERY" \
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_EVERY_0453=1000000000 \
CPU_OP_CARRIER_0458=1 \
BIN="$BIN" \
BASE_SCALE_ROOT="$BASE_0476_ROOT" \
SCALE_CASES="$SCALE_CASES" \
RUN_MODES="$RUN_MODES" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
SEEDS="$SEEDS" \
MAX_SUMMARY_DELTA_TOL="$MAX_SUMMARY_DELTA_TOL" \
LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" \
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}" \
bash scripts/run_0464_scaling_cuda_vs_cpu.sh
fi

python3 - "$BASE_0476_ROOT" "$MAX_SUMMARY_DELTA_TOL" <<'PY'
import csv
import sys
from pathlib import Path

root = Path(sys.argv[1])
tol = float(sys.argv[2])

def rows(path):
    if not path.exists():
        return []
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))

def number(row, *keys, default=0.0):
    for key in keys:
        value = row.get(key, '')
        if value not in ('', None):
            try:
                return float(value)
            except ValueError:
                pass
    return default

def related(paths, case, mode, role='cuda'):
    markers = (f'/{case}/', f'/{role}/{mode}/')
    return [path for path in paths if all(marker in '/' + str(path.relative_to(root)) for marker in markers)]

scale_paths = list(root.rglob('scaling_cuda_vs_cpu_summary_0463.csv')) + list(root.rglob('scaling_cuda_vs_cpu_summary_0464.csv'))
scale_rows = []
for path in scale_paths:
    scale_rows.extend(rows(path))

mat_paths = list(root.rglob('cuda_resampling_operation_materialize_0453.csv'))
carrier_paths = list(root.rglob('cuda_resampling_device_carrier_0455.csv'))
up_paths = (list(root.rglob('cuda_resampling_upstream_apply_0451.csv')) +
            list(root.rglob('cuda_resampling_upstream_shadow_0450.csv')))
profile_paths = list(root.rglob('phase_profile_0163.csv'))

out = []
for scale in scale_rows:
    case, mode, seed = scale.get('case',''), scale.get('mode',''), scale.get('seed','')
    mat = [r for p in related(mat_paths, case, mode) for r in rows(p) if number(r, 'handled') == 1]
    carrier = [r for p in related(carrier_paths, case, mode) for r in rows(p) if number(r, 'handled') == 1]
    upstream = [r for p in related(up_paths, case, mode) for r in rows(p) if number(r, 'handled') == 1]
    apply_paths = list(root.rglob('cuda_resampling_pipeline_apply_0448.csv'))
    remap = [r for p in related(apply_paths, case, mode) for r in rows(p)
             if r.get('stage') == 'remap_thermal_0448' and number(r, 'handled') == 1]

    profile = []
    for path in related(profile_paths, case, mode):
        profile.extend(rows(path))
    profile = [r for r in profile if r.get('phase') != 'total_profiled']
    profile.sort(key=lambda r: number(r, 'ms_per_step'), reverse=True)
    top = profile[:3]

    cpu_wall = number(scale, 'cpuWall', 'cpu_wall_s')
    cuda_wall = number(scale, 'cudaWall', 'cuda_wall_s')
    speedup = number(scale, 'speedupCpuOverCuda', 'speedup')
    delta = number(scale, 'maxSummaryDelta', 'max_summary_delta', default=float('inf'))
    passed = number(scale, 'pass') == 1
    upstream_ok = bool(upstream and
                       sum(number(r, 'pass') for r in upstream) > 0 and
                       sum(number(r, 'upstreamSharedState0474') for r in upstream) > 0 and
                       sum(number(r, 'upstreamUploadSkipped0474') for r in upstream) > 0)
    authority_ok = bool(mat and carrier and upstream_ok and
                        sum(number(r, 'applied') for r in mat) > 0 and
                        sum(number(r, 'materializerSharedState0475') for r in mat) > 0 and
                        sum(number(r, 'materializerUploadSkipped0475') for r in mat) > 0 and
                        sum(number(r, 'cpuOpCarrier0458') for r in carrier) > 0 and
                        max((number(r, 'thrustCellListMaterializer0460') for r in carrier), default=0) == 0)
    row = {
        'case': case, 'mode': mode, 'seed': seed,
        'pass': int(passed and authority_ok and delta <= tol),
        'cpu_wall_s': cpu_wall, 'cuda_wall_s': cuda_wall, 'speedup': speedup,
        'max_summary_delta': delta,
        'mat_rows': len(mat), 'mat_pass': sum(int(number(r,'pass') == 1) for r in mat),
        'mat_apply': sum(int(number(r,'applied') == 1) for r in mat),
        'mat_shared': sum(int(number(r,'materializerSharedState0475') == 1) for r in mat),
        'mat_upload_skipped': sum(int(number(r,'materializerUploadSkipped0475') == 1) for r in mat),
        'mat_compact_dl': sum(int(number(r,'materializerCompactDownload0475') == 1) for r in mat),
        'mat_max_plan_upload_s': max((number(r,'planUploadSeconds0475') for r in mat), default=0),
        'mat_max_kernel_s': max((number(r,'kernelSeconds') for r in mat), default=0),
        'mat_max_download_s': max((number(r,'downloadSeconds') for r in mat), default=0),
        'mat_max_total_s': max((number(r,'totalSeconds') for r in mat), default=0),
        'carrier_rows': len(carrier),
        'carrier_cpuop_rows': sum(int(number(r,'cpuOpCarrier0458') == 1) for r in carrier),
        'carrier_thrust_rows': sum(int(number(r,'thrustCellListMaterializer0460') == 1) for r in carrier),
        'carrier_skip_upload': sum(int(number(r,'residentSharedUploadSkipped0472') == 1) for r in carrier),
        'carrier_patch': sum(int(number(r,'residentHostPatchback0473') == 1) for r in carrier),
        'up_rows': len(upstream), 'up_pass': sum(int(number(r,'pass') == 1) for r in upstream),
        'up_shared': sum(int(number(r,'upstreamSharedState0474') == 1) for r in upstream),
        'up_skip_upload': sum(int(number(r,'upstreamUploadSkipped0474') == 1) for r in upstream),
        'remap_rows': len(remap),
        'remap_shared': sum(int(number(r,'remapSharedState') == 1) for r in remap),
        'remap_upload_skipped': sum(int(number(r,'remapUploadSkipped') == 1) for r in remap),
        'remap_upload_s': sum(number(r,'remapStateUploadSeconds') for r in remap),
        'remap_download_s': sum(number(r,'remapStateDownloadSeconds') for r in remap),
        'remap_kernel_s': sum(number(r,'remapKernelSeconds') for r in remap),
        'thermal_kernel_s': sum(number(r,'thermalKernelSeconds') for r in remap),
    }
    for index in range(3):
        item = top[index] if index < len(top) else {}
        row[f'profile_top{index+1}'] = item.get('phase','')
        row[f'profile_top{index+1}_ms'] = number(item,'ms_per_step')
    out.append(row)

summary = root / 'materializer_authoritative_summary_0476.csv'
report = root / 'materializer_authoritative_report_0476.md'
fields = list(out[0]) if out else ['case','mode','pass']
with summary.open('w', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    writer.writerows(out)

with report.open('w') as stream:
    stream.write('# 0476 materializer-authoritative scaling and phase attribution\n\n')
    stream.write('0475b builds and validates the operation vector. The 0458 compact bridge then makes that vector the carrier input, so the carrier does not independently rerun the 0460 materializer. This is authoritative but not yet host-free: compact operations are downloaded by 0475b and uploaded by 0458.\n\n')
    stream.write(f'PASS-like rows: **{sum(r["pass"] for r in out)}/{len(out)}**\n\n')
    stream.write('| case | mode | pass | CPU wall s | CUDA wall s | speedup | max delta | mat apply/shared/skip/dl | carrier CPUop/thrust/skip/patch | upstream pass/shared/skip | remap rows/shared/skip | remap up/dl/kernel/thermal s | top CUDA phases |\n')
    stream.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- |\n')
    for r in out:
        phases = ', '.join(f'{r[f"profile_top{i}"]}={r[f"profile_top{i}_ms"]:.3f} ms' for i in range(1,4) if r[f'profile_top{i}'])
        stream.write(f'| {r["case"]} | {r["mode"]} | {r["pass"]} | {r["cpu_wall_s"]:.3f} | {r["cuda_wall_s"]:.3f} | {r["speedup"]:.3f} | {r["max_summary_delta"]:.3e} | {r["mat_apply"]}/{r["mat_shared"]}/{r["mat_upload_skipped"]}/{r["mat_compact_dl"]} | {r["carrier_cpuop_rows"]}/{r["carrier_thrust_rows"]}/{r["carrier_skip_upload"]}/{r["carrier_patch"]} | {r["up_pass"]}/{r["up_shared"]}/{r["up_skip_upload"]} | {r["remap_rows"]}/{r["remap_shared"]}/{r["remap_upload_skipped"]} | {r["remap_upload_s"]:.3e}/{r["remap_download_s"]:.3e}/{r["remap_kernel_s"]:.3e}/{r["thermal_kernel_s"]:.3e} | {phases} |\n')
    stream.write(f'\nFlat CSV: `{summary}`\n')

print(report.read_text())
if not out or any(r['pass'] != 1 for r in out):
    raise SystemExit(1)
PY

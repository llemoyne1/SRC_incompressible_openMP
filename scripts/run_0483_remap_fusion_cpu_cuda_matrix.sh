#!/usr/bin/env bash
set -euo pipefail

# 0483 — CPU/CUDA physical-equivalence and timing matrix for resident remap-kernel fusion.
# Scope: validates the uncommitted 0483 fusion of target-energy accumulation and remap-mass apply
# on the already-committed resident stack 0479..0482, using the 0464 CPU/CUDA scaling harness.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

: "${BIN:?Set BIN to the 0483 candidate solver binary}"
BASE_0483_ROOT="${BASE_0483_ROOT:-runs/0483_remap_fusion_cpu_cuda_matrix}"
SCALE_CASES="${SCALE_CASES:-64x64x40 96x96x40 128x128x40}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
SEEDS="${SEEDS:-1628638}"
STEPS="${STEPS:-200}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DEVICE_GATE_EVERY="${DEVICE_GATE_EVERY:-50}"
UPSTREAM_GATE_EVERY="${UPSTREAM_GATE_EVERY:-50}"
MAX_SUMMARY_DELTA_TOL="${MAX_SUMMARY_DELTA_TOL:-1e-9}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
RUN_SIMULATION="${RUN_SIMULATION:-1}"

if [[ ! -x "$BIN" ]]; then
  echo "[0483] missing executable: $BIN" >&2
  exit 2
fi
if [[ ! -x scripts/run_0464_scaling_cuda_vs_cpu.sh ]]; then
  echo "[0483] missing scripts/run_0464_scaling_cuda_vs_cpu.sh" >&2
  exit 2
fi

if [[ "$RUN_SIMULATION" == "1" ]]; then
  rm -rf "$BASE_0483_ROOT"
fi
mkdir -p "$BASE_0483_ROOT"

cat > "$BASE_0483_ROOT/launch_0483.env" <<ENV
BIN=$BIN
SCALE_CASES=$SCALE_CASES
RUN_MODES=$RUN_MODES
SEEDS=$SEEDS
STEPS=$STEPS
SUMMARY_EVERY=$SUMMARY_EVERY
DEVICE_GATE_EVERY=$DEVICE_GATE_EVERY
UPSTREAM_GATE_EVERY=$UPSTREAM_GATE_EVERY
MAX_SUMMARY_DELTA_TOL=$MAX_SUMMARY_DELTA_TOL
LIVE_PROGRESS=$LIVE_PROGRESS
LIVE_VIS_ENABLE=$LIVE_VIS_ENABLE
FILTERED_RECORDING_ENABLE=$FILTERED_RECORDING_ENABLE
ENV

echo "[0483] root=$BASE_0483_ROOT"
echo "[0483] bin=$BIN"
echo "[0483] cases=[$SCALE_CASES] seeds=[$SEEDS] modes=[$RUN_MODES] steps=$STEPS"
echo "[0483] resident flags: 0471/0472/0473/0474/0475/0475A/0475B + compact 0458 carrier + committed 0479..0482"
echo "[0483] tested code delta: fused target-energy + remap-mass kernel in cuda_resampling_pipeline_shadow_0445.cu"

if [[ "$RUN_SIMULATION" == "1" ]]; then
MPCD_INTERNAL_PROFILES=1 \
MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1 \
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
BASE_SCALE_ROOT="$BASE_0483_ROOT" \
SCALE_CASES="$SCALE_CASES" \
RUN_MODES="$RUN_MODES" \
SEEDS="$SEEDS" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
MAX_SUMMARY_DELTA_TOL="$MAX_SUMMARY_DELTA_TOL" \
LIVE_PROGRESS="$LIVE_PROGRESS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
bash scripts/run_0464_scaling_cuda_vs_cpu.sh
fi

python3 - "$BASE_0483_ROOT" "$MAX_SUMMARY_DELTA_TOL" <<'PY'
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
    out = []
    for path in paths:
        rel = '/' + str(path.relative_to(root))
        if f'/{case}/' in rel and f'/{role}/{mode}/' in rel:
            out.append(path)
    return out

scale_paths = list(root.rglob('scaling_cuda_vs_cpu_summary_0463.csv')) + list(root.rglob('scaling_cuda_vs_cpu_summary_0464.csv'))
scale_rows = []
for path in scale_paths:
    scale_rows.extend(rows(path))

apply_paths = list(root.rglob('cuda_resampling_pipeline_apply_0448.csv'))
carrier_paths = list(root.rglob('cuda_resampling_device_carrier_0455.csv'))
mat_paths = list(root.rglob('cuda_resampling_operation_materialize_0453.csv'))
up_paths = list(root.rglob('cuda_resampling_upstream_apply_0451.csv')) + list(root.rglob('cuda_resampling_upstream_shadow_0450.csv'))
profile_paths = list(root.rglob('phase_profile_0163.csv'))

out = []
for scale in scale_rows:
    case = scale.get('case', '')
    mode = scale.get('mode', '')
    seed = scale.get('seed', '')
    if not case or not mode:
        continue

    apply_rows = [r for p in related(apply_paths, case, mode) for r in rows(p) if number(r, 'handled') == 1]
    remap_rows = [r for r in apply_rows if r.get('stage') == 'remap_thermal_0448']
    carrier_rows = [r for p in related(carrier_paths, case, mode) for r in rows(p) if number(r, 'handled') == 1]
    mat_rows = [r for p in related(mat_paths, case, mode) for r in rows(p) if number(r, 'handled') == 1]
    up_rows = [r for p in related(up_paths, case, mode) for r in rows(p) if number(r, 'handled') == 1]

    profile = []
    for path in related(profile_paths, case, mode):
        profile.extend(rows(path))
    profile = [r for r in profile if r.get('phase') != 'total_profiled']
    profile.sort(key=lambda r: number(r, 'ms_per_step'), reverse=True)
    top = profile[:3]

    cpu_wall = number(scale, 'cpuWall', 'cpu_wall_s')
    cuda_wall = number(scale, 'cudaWall', 'cuda_wall_s')
    speedup = number(scale, 'speedupCpuOverCuda', 'speedup')
    max_delta = number(scale, 'maxSummaryDelta', 'max_summary_delta', default=float('inf'))
    scale_pass = number(scale, 'pass') == 1

    remap_count = len(remap_rows)
    remap_shared = sum(int(number(r, 'remapSharedState') == 1) for r in remap_rows)
    remap_upload_skipped = sum(int(number(r, 'remapUploadSkipped') == 1) for r in remap_rows)
    remap_upload_s = sum(number(r, 'remapStateUploadSeconds') for r in remap_rows)
    remap_download_s = sum(number(r, 'remapStateDownloadSeconds') for r in remap_rows)
    remap_kernel_s = sum(number(r, 'remapKernelSeconds') for r in remap_rows)
    thermal_kernel_s = sum(number(r, 'thermalKernelSeconds') for r in remap_rows)
    remap_total_s = sum(number(r, 'totalSeconds') for r in remap_rows)

    carrier_cpuop = sum(int(number(r, 'cpuOpCarrier0458') == 1) for r in carrier_rows)
    carrier_compact = max((number(r, 'compactOpsCapacity0458', 'gpuOpsCapacity', default=0.0) for r in carrier_rows), default=0.0)
    carrier_gpu_ops = max((number(r, 'gpuOps', 'passiveOps', default=0.0) for r in carrier_rows), default=0.0)
    invalid_mat = max((number(r, 'invalidMaterializeOps') for r in carrier_rows), default=0.0)
    invalid_apply = max((number(r, 'invalidApplyOps') for r in carrier_rows), default=0.0)
    op_mismatch = max((number(r, 'opMismatch') for r in carrier_rows), default=0.0)
    dup_mismatch = max((number(r, 'duplicateParticleMismatch') for r in carrier_rows), default=0.0)

    materializer_ok = bool(mat_rows and sum(int(number(r, 'applied') == 1) for r in mat_rows) > 0)
    upstream_ok = bool(up_rows and sum(int(number(r, 'pass') == 1) for r in up_rows) > 0)
    resident_ok = bool(remap_count > 0 and remap_shared > 0 and remap_upload_skipped > 0)
    carrier_ok = bool(carrier_rows and carrier_cpuop > 0 and invalid_mat == 0 and invalid_apply == 0 and op_mismatch == 0 and dup_mismatch == 0)
    pass_0483 = int(scale_pass and max_delta <= tol and materializer_ok and upstream_ok and resident_ok and carrier_ok)

    row = {
        'case': case,
        'mode': mode,
        'seed': seed,
        'pass': pass_0483,
        'scale_pass': int(scale_pass),
        'cpu_wall_s': cpu_wall,
        'cuda_wall_s': cuda_wall,
        'speedup_cpu_over_cuda': speedup,
        'max_summary_delta': max_delta,
        'max_delta_key': scale.get('maxDeltaKey', ''),
        'remap_rows': remap_count,
        'remap_shared_rows': remap_shared,
        'remap_upload_skipped_rows': remap_upload_skipped,
        'remap_upload_s_sum': remap_upload_s,
        'remap_download_s_sum': remap_download_s,
        'remap_kernel_s_sum': remap_kernel_s,
        'thermal_kernel_s_sum': thermal_kernel_s,
        'remap_total_s_sum': remap_total_s,
        'remap_kernel_s_avg': remap_kernel_s / remap_count if remap_count else 0.0,
        'thermal_kernel_s_avg': thermal_kernel_s / remap_count if remap_count else 0.0,
        'remap_total_s_avg': remap_total_s / remap_count if remap_count else 0.0,
        'carrier_rows': len(carrier_rows),
        'carrier_cpuop_rows': carrier_cpuop,
        'carrier_max_gpu_ops': carrier_gpu_ops,
        'carrier_max_compact_capacity': carrier_compact,
        'invalid_materialize_ops': invalid_mat,
        'invalid_apply_ops': invalid_apply,
        'op_mismatch': op_mismatch,
        'duplicate_particle_mismatch': dup_mismatch,
        'materializer_rows': len(mat_rows),
        'upstream_rows': len(up_rows),
    }
    for index in range(3):
        item = top[index] if index < len(top) else {}
        row[f'profile_top{index+1}'] = item.get('phase', '')
        row[f'profile_top{index+1}_ms'] = number(item, 'ms_per_step')
    out.append(row)

summary = root / 'remap_fusion_cpu_cuda_summary_0483.csv'
report = root / 'remap_fusion_cpu_cuda_report_0483.md'
fields = list(out[0].keys()) if out else ['case', 'mode', 'seed', 'pass']
with summary.open('w', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    writer.writerows(out)

pass_count = sum(int(r.get('pass', 0)) for r in out)
with report.open('w') as stream:
    stream.write('# 0483 resident remap-fusion CPU/CUDA matrix\n\n')
    stream.write('Scope: validate the fused remap target-energy + mass-apply kernel against the CPU path, with the resident resampling stack enabled through 0476 plus the committed 0479--0482 optimizations. The expected physical result is CPU/CUDA equivalence within `MAX_SUMMARY_DELTA_TOL`; the expected performance signature is a reduced remap kernel launch/memory component, visible in `remapKernelSeconds`, without changing `thermalKernelSeconds` semantics.\n\n')
    stream.write(f'PASS-like rows: **{pass_count}/{len(out)}**\n\n')
    stream.write('| case | mode | seed | pass | CPU wall s | CUDA wall s | speedup | max delta | remap rows/shared/skip | remap kernel sum s | thermal sum s | remap total sum s | carrier rows/cpuop | invalid mat/apply | mismatch op/dup | top phases |\n')
    stream.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | --- | --- | --- | --- |\n')
    for r in out:
        phases = ', '.join(f'{r[f"profile_top{i}"]}={r[f"profile_top{i}_ms"]:.3f} ms' for i in range(1, 4) if r[f'profile_top{i}'])
        stream.write(
            f'| {r["case"]} | {r["mode"]} | {r["seed"]} | {r["pass"]} | '
            f'{r["cpu_wall_s"]:.3f} | {r["cuda_wall_s"]:.3f} | {r["speedup_cpu_over_cuda"]:.3f} | {r["max_summary_delta"]:.3e} | '
            f'{r["remap_rows"]}/{r["remap_shared_rows"]}/{r["remap_upload_skipped_rows"]} | '
            f'{r["remap_kernel_s_sum"]:.3e} | {r["thermal_kernel_s_sum"]:.3e} | {r["remap_total_s_sum"]:.3e} | '
            f'{r["carrier_rows"]}/{r["carrier_cpuop_rows"]} | '
            f'{r["invalid_materialize_ops"]:.0f}/{r["invalid_apply_ops"]:.0f} | '
            f'{r["op_mismatch"]:.0f}/{r["duplicate_particle_mismatch"]:.0f} | {phases} |\n'
        )
    stream.write(f'\nFlat CSV: `{summary}`\n')

print(report)
print(report.read_text())
if not out or pass_count != len(out):
    raise SystemExit(1)
PY

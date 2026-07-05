#!/usr/bin/env python3
from pathlib import Path

ROOT = Path.cwd()
HDR = ROOT / 'include' / 'cuda_resampling_pipeline_shadow_0445.h'
CU = ROOT / 'src' / 'cuda_resampling_pipeline_shadow_0445.cu'
MAIN = ROOT / 'src' / 'src_mpcd_base.cpp'

def read(p):
    if not p.exists():
        raise SystemExit(f'[0475a] missing file: {p}')
    return p.read_text()

def write(p, s):
    p.write_text(s)

def replace_once(s, old, new, label):
    if old not in s:
        raise SystemExit(f'[0475a] missing anchor: {label}')
    return s.replace(old, new, 1)

h = read(HDR)
if 'cuda_resampling_materializer_on_plan_0475a_requested' not in h:
    h = replace_once(
        h,
        'bool cuda_resampling_operation_materialize_0453_requested(std::uint64_t step);\n',
        'bool cuda_resampling_operation_materialize_0453_requested(std::uint64_t step);\n'
        'bool cuda_resampling_materializer_on_plan_0475a_requested();\n',
        'header declaration 0475a',
    )
    h = replace_once(
        h,
        'inline bool cuda_resampling_operation_materialize_0453_requested(std::uint64_t) { return false; }\n',
        'inline bool cuda_resampling_operation_materialize_0453_requested(std::uint64_t) { return false; }\n'
        'inline bool cuda_resampling_materializer_on_plan_0475a_requested() { return false; }\n',
        'header stub 0475a',
    )
    write(HDR, h)

s = read(CU)
if 'cuda_resampling_materializer_on_plan_0475a_requested' not in s:
    s = replace_once(
        s,
        'bool cuda_resampling_materializer_shared_state_0475_requested() {\n'
        '    return env_truthy_0445("MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475");\n'
        '}\n',
        'bool cuda_resampling_materializer_shared_state_0475_requested() {\n'
        '    return env_truthy_0445("MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475");\n'
        '}\n\n'
        'bool cuda_resampling_materializer_on_plan_0475a_requested() {\n'
        '    return env_truthy_0445("MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A");\n'
        '}\n',
        'cu env function 0475a',
    )

old = '''        if (!cuda_resampling_operation_materialize_0453_requested(step)) {
            d.skipped = true;
            d.skipReason = "operation materializer flag disabled";
            append_operation_materialize_csv_0453(params, d);
            return d;
        }
'''
new = '''        const bool materializerOnPlan0475A =
            cuda_resampling_materializer_on_plan_0475a_requested() &&
            !operationWorkspace.transferPlan.empty() &&
            !operationWorkspace.passiveExtractionOperations.empty();
        if (!cuda_resampling_operation_materialize_0453_requested(step) && !materializerOnPlan0475A) {
            d.skipped = true;
            d.skipReason = "operation materializer flag disabled";
            append_operation_materialize_csv_0453(params, d);
            return d;
        }
'''
if old in s:
    s = s.replace(old, new, 1)
elif 'materializerOnPlan0475A' not in s:
    raise SystemExit('[0475a] missing anchor: materializer request bypass')
write(CU, s)

m = read(MAIN)
if 'cudaResamplingOperationMaterializeOnPlan0475ARequested' not in m:
    m = replace_once(
        m,
        '    const bool cudaResamplingOperationMaterialize0453Requested =\n'
        '        cuda_resampling_operation_materialize_0453_requested(step);\n',
        '    const bool cudaResamplingOperationMaterialize0453Requested =\n'
        '        cuda_resampling_operation_materialize_0453_requested(step);\n'
        '    const bool cudaResamplingOperationMaterializeOnPlan0475ARequested =\n'
        '        cuda_resampling_materializer_on_plan_0475a_requested() &&\n'
        '        !workspace.resampling.transferPlan.empty() &&\n'
        '        !workspace.resampling.passiveExtractionOperations.empty();\n',
        'main on-plan request const',
    )
    m = replace_once(
        m,
        '    if (cudaResamplingOperationMaterialize0453Requested) {\n',
        '    if (cudaResamplingOperationMaterialize0453Requested ||\n'
        '        cudaResamplingOperationMaterializeOnPlan0475ARequested) {\n',
        'main materializer call condition',
    )
    write(MAIN, m)

print('[0475a] patched materializer on-plan trigger')

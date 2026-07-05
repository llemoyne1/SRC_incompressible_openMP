# 0484 CUDA resampling production strip

Patch 0484 keeps the validated resident SRC-resampling and SRC-Q6-resampling paths from 0477--0483, but removes development overhead from the default 0434/run_ok execution profile.

## Production defaults

When a 0434/run_ok script executes a resampling path, the common runner now exports:

- `MPCD_CUDA_RESAMPLING_PRODUCTION_STRIP_0484=1`
- `MPCD_CUDA_RESAMPLING_DIAG_CSV_0484=0`
- `MPCD_CUDA_RESAMPLING_FULL_GATE_0484=0`
- `MPCD_CUDA_RESAMPLING_REMAP_CELL_COUNT_DIAG_0484=0`
- `MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=0`
- `MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=0`
- `MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A=0`
- `MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=0`
- `MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B=0`

The functional resident path remains active:

- `MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1`
- `MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=1`
- `MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1`
- `MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1`
- `MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1`
- `MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=1`

The compact host patchback 0473 is deliberately kept: it is still the cheapest way to keep the host-side post-edit deposit coherent while the remaining post-edit/post-remap deposits are host consumers. It is not treated as a removable development diagnostic in this patch.

## What is stripped

0484 disables by default:

1. detailed success-row CSV writes from `cuda_resampling_pipeline_apply_0448.csv`, `cuda_resampling_transaction_0466.csv`, upstream shadow/apply CSVs, and operation-materializer CSVs;
2. the heavy full operation gate that downloads complete operation buffers for CPU/GPU comparison;
3. remap/thermal cell-count diagnostic downloads used only to populate `gpuRemapCells/gpuThermalCells` counters;
4. upstream CPU/CUDA validation shadows and operation-materializer validation gates in the 0434/run_ok production profile.

Failure rows are still allowed when the corresponding code path is entered and fails. Standard outputs such as `summary_runtime.csv`, phase profiles, final states, and physics summaries are unchanged.

## Re-enabling validation/debug behavior

For a validation run close to the 0477--0483 profile, override the runner variables:

```bash
RESAMPLING_PRODUCTION_STRIP=0 \
RESAMPLING_DIAG_CSV_ENABLE=1 \
RESAMPLING_FULL_GATE_ENABLE=1 \
RESAMPLING_REMAP_CELL_COUNT_DIAG_ENABLE=1 \
RESAMPLING_UPSTREAM_VALIDATE_ENABLE=1 \
RESAMPLING_OPERATION_MATERIALIZER_VALIDATE_ENABLE=1 \
bash scripts/run_ok_tg.sh
```

or set the corresponding low-level environment variables directly.

## Smoke test

The provided smoke launches one solver run by default:

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0484 \
AUTO_BUILD=0 \
bash scripts/run_0484_strip_smoke_src_only.sh
```

Expected with the default smoke configuration:

- one solver execution: `src-resampling`, `128x128x40`, `200` steps;
- no success-row detailed resampling CSVs in the output directory;
- `summary_runtime.csv` and standard run outputs still present.

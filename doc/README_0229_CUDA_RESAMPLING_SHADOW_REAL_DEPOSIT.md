# 0229 — CUDA resampling shadow on real weighted deposits

Patch 0229 moves the CUDA resampling prototype from synthetic standalone tests to
real `WeightedRealFluidDepositWorkspace` objects produced inside the SRC/MPCD
run.

The simulation remains CPU-authoritative.  When the executable is compiled with
`MPCD_ENABLE_CUDA_RESAMPLING` and run with:

```bash
MPCD_CUDA_RESAMPLING_SHADOW=1
```

`deposit_weighted_real_fluid()` calls the CUDA 0228 primitive after the CPU
classification/candidate-plan logic has completed.  The shadow path compares:

- poor receiver cell list,
- rich donor cell list,
- total receiver deficit,
- total donor excess,
- planned transfer mass when a CPU transfer plan was built.

The CUDA path receives `wetCell` as the active mask, because CPU resampling only
classifies poor/rich cells within the wet resampling domain.  This keeps the
shadow comparison valid for both `active_domain` and `occupied` wet-mask modes.

## Runtime controls

```bash
MPCD_CUDA_RESAMPLING_SHADOW=1
MPCD_CUDA_RESAMPLING_SHADOW_CSV=dev_history/artifacts/gpu_cuda_resampling_0229/detail.csv
MPCD_CUDA_RESAMPLING_SHADOW_STRICT=1
```

With strict mode enabled, a mismatch throws and fails the run.

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_resampling_shadow_0229.sh
```

Main output:

```text
dev_history/artifacts/gpu_cuda_resampling_0229/cuda_resampling_shadow_0229.csv
```

Expected result:

```text
PASS ... shadowRows>0 poorMismatch=0 richMismatch=0 failed=0/76
```

## Scope

This patch still does not mutate particles.  It validates the CUDA resampling
classification/compaction/plan on true simulation deposits.  The next patch can
start the first mutating part in a controlled way: donor-particle selection and
extraction/insertion shadow planning.

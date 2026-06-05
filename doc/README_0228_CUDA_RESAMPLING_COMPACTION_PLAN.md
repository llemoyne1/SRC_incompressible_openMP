# 0228 — CUDA resampling compaction and first transfer plan

This patch moves the resampling CUDA prototype beyond cell classification.
It adds a non-mutating primitive that:

1. classifies cells from an existing cell deposit,
2. compacts poor receiver cells and rich donor cells,
3. computes receiver deficits and donor excesses,
4. builds a deterministic greedy mass-transfer plan on the host from compacted GPU lists.

The particle state is not modified in this patch.  This is intentional: the next
risk boundary is extraction/insertion/remap of actual particles, so 0228 validates
the donor/receiver lists and planned mass balance first.

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
bash scripts/run_cuda_resampling_plan_smoke_0228.sh
```

Expected result:

```text
[0228-resampling-plan] PASS 64x64_g20 ... mismatches=0
[0228-resampling-plan] PASS 128x128_g20 ... mismatches=0
```

The CSV output is written to:

```text
dev_history/artifacts/gpu_cuda_resampling_0228/cuda_resampling_plan_smoke_0228.csv
```

## Scope

This is still a standalone CUDA validation patch.  No runtime simulation path is
changed.  The next patch should put this primitive in shadow mode on real
resampling deposits, then the following patch can start particle selection and
extraction/insertion.

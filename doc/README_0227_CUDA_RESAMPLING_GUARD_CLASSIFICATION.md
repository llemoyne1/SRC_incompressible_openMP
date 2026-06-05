# 0227 — CUDA resampling guard classification prototype

This patch deliberately pivots the GPU work away from classic SRC-only acceleration and toward the incompressible SRC/MPCD resampling path.

It adds a standalone CUDA primitive for the first safe resampling stage: cell classification from an existing weighted real-fluid deposit. Given per-cell population, mass and active-cell mask, the CUDA path classifies cells as:

- active / wet / dry;
- poor receiver candidates;
- rich donor candidates;
- target-band cells.

The patch does not yet mutate particles and does not alter `src_mpcd_base`. It is meant to validate the cell-side logic that later drives donor/receiver lists, transfer planning, insertion/extraction and local remap.

## Build and run

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
bash scripts/run_cuda_resampling_guard_smoke_0227.sh
```

Expected output:

```text
[0227-resampling-guard] PASS 64x64_g20 ... mismatches=0
[0227-resampling-guard] PASS 128x128_g20 ... mismatches=0
```

## Next step

If this passes, the next GPU resampling patch should use the real `WeightedRealFluidDepositWorkspace` from the simulation and run a shadow comparison of CPU vs CUDA classification inside the actual resampling cadence. Only after that should we move to candidate list compaction and mutation planning.

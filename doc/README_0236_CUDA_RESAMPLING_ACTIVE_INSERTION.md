# 0236 — CUDA resampling active insertion stage

This patch moves the first real mutating resampling sub-operation into CUDA,
while keeping the conservative CPU extraction plan and CPU pool bookkeeping.

## Scope

The active path is enabled with:

```bash
MPCD_CUDA_RESAMPLING_INSERTION_USE=1
```

The CPU path remains the default.

The step order is unchanged:

1. CPU builds the weighted real-fluid deposit and passive extraction plan;
2. CPU extraction marks selected particles inactive and updates the free pool;
3. CUDA reactivates the same particle slots in receiver cells using the same
   deterministic in-cell placement rule as the CPU insertion path;
4. CPU diagnostics and post-edit deposit remain unchanged.

This is deliberately narrower than a full CUDA resampling implementation.  It
validates a real mutating write-back stage while avoiding changes in donor
selection, pool semantics, remap, thermal renormalization, or diagnostics.

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_resampling_insertion_active_0236.sh
```

Expected criteria:

- `cuda_resampling_insertion` passes the 0162 comparison against CPU baseline;
- `failed_metrics = 0`;
- no change in Q6/projection path; Q6 is normally disabled for this harness;
- this is not expected to be faster yet, because the CUDA insertion primitive
  still uploads/downloads the full particle arrays.

## Next step

If 0236 passes, the next target is to move the insertion primitive onto
`CudaParticleState`, then combine it with `CudaCellWorkspace` and the existing
persistent SRC/thermostat path so that resampling mutates the already-resident
particle state rather than a temporary upload/download copy.

# 0199 — CUDA particle-to-cell moments deposit prototype

This patch starts the next GPU work package after the Q6 CUDA path: particle-to-cell deposit and cell moments.

## Scope

The patch deliberately does **not** modify the MPCD time step. It adds a standalone CUDA validator for a first atomic deposit kernel:

```text
particle SoA arrays
  -> cellId[i]
  -> cellCount[c]
  -> cellMass[c]
  -> cellPx[c], cellPy[c]
  -> cellUx[c], cellUy[c]
```

Only active `ParticleRole::Fluid` particles are deposited. `Latent` and `Inactive` slots are ignored exactly as in the CPU collision/moment deposit logic.

The first kernel uses direct CUDA atomics. This is not expected to be the final high-performance implementation. It is the safest validation target before considering block-local histograms, sorting/binning, persistent particle buffers, or integration into `src_collision_step`.

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
  bash scripts/build_cuda_cell_moments_0199.sh
```

## Smoke validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
bash scripts/run_cuda_cell_moments_smoke_0199.sh
```

The script writes:

```text
dev_history/artifacts/gpu_cuda_deposit_0199/cuda_cell_moments_smoke_0199.csv
dev_history/artifacts/gpu_cuda_deposit_0199/cuda_cell_moments_smoke_0199.log
```

## Validation criteria

Expected verdict:

```text
CUDA_CELL_MOMENTS_0199 PASS
```

Strict criteria:

```text
cellIdMismatches = 0
countMismatches  = 0
maxAbsMass       <= tolerance
maxAbsPx         <= tolerance
maxAbsPy         <= tolerance
maxAbsUx         <= tolerance
maxAbsUy         <= tolerance
```

The default tolerance is `1e-10`. Small floating-point differences are expected because CUDA atomics do not impose the same summation order as the CPU reference.

## Next steps

If 0199 passes, the next patch should add one of the following:

1. persistent CUDA buffers for particle arrays and cell moments;
2. timing comparison against the CPU collision deposit section;
3. optional runtime validation inside `src_collision_step` without changing dynamics;
4. then, only after validation, a guarded `cellMomentsBackend=cuda` path for TG periodic cases.

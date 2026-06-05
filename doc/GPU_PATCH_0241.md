# GPU patch 0241 — active resampling path connected to persistent 0239 kernels

## Purpose

Patch 0240 installed the active-path hook but deliberately kept it as a safe
CPU fallback.  Patch 0241 connects that hook to the validated 0239 persistent
`CudaParticleState` extraction/insertion kernels.

The active SRC/MPCD loop still builds and validates the weighted-resampling
operation lists on the CPU.  Once the lists are built, 0241:

1. uploads the current `ParticleState` into a persistent `CudaParticleState`,
2. prepares CPU-identical extraction diagnostics and pool bookkeeping,
3. applies extraction on the persistent GPU particle state using the 0239 kernel,
4. prepares CPU-identical insertion diagnostics and pool bookkeeping,
5. applies insertion on the persistent GPU particle state using the 0239 kernel,
6. downloads the updated particle state before the existing post-edit deposit.

This is a functional bridge, not yet the final zero-copy ownership model.  Its
main objective is to prove that the true active resampling section can delegate
its particle edits to the persistent CUDA backend without using the older
host-vector wrapper kernels.

## Files changed

- `src/cuda_resampling_persistent_active_path_0240.cpp`
  - replaces the 0240 `handled=false` stub by a guarded CUDA implementation;
  - keeps CPU-only builds safe through `#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_RESAMPLING)`;
  - mirrors the CPU extraction/insertion diagnostics and particle-pool updates;
  - calls `cuda_resampling_apply_extraction_operations_on_state_0239()` and
    `cuda_resampling_apply_insertion_operations_on_state_0239()`.

- `include/cuda_resampling_particle_ops.h`
  - adds `CudaResamplingInsertionApplyParams::useHashPlacement`.

- `src/cuda_resampling_particle_ops.cu`
  - keeps the historical 0239 hash placement as default;
  - allows the active path to request the CPU-compatible deterministic 4x4
    receiver-cell placement rule.

- `scripts/build_src_mpcd_cuda_0241.sh`
  - builds `build/src_mpcd_base_cuda_0241` with CUDA particle state and CUDA
    resampling enabled.

- `scripts/run_cuda_resampling_persistent_active_path_0241.sh`
  - runs the 0239 persistent-state smoke test;
  - compares CPU baseline against the 0241 active persistent resampling path for
    64x64 and 128x128 defaults.

## Runtime switches

The existing 0240 switch remains the activation switch for the hook:

```bash
MPCD_CUDA_RESAMPLING_PERSISTENT_0240=1
```

0241 adds a strictness switch, enabled by default:

```bash
MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0241_STRICT=1
```

When strict mode is enabled, a mismatch between the CPU-prepared operation count
and the number of operations applied by the CUDA kernels is fatal.

## Validation

Recommended command:

```bash
bash scripts/run_cuda_resampling_persistent_active_path_0241.sh
```

Useful overrides:

```bash
GRID_CASES="64:100 128:100" \
CASE_LIST=tg_periodic_full \
RUN_0239_SMOKE=1 \
bash scripts/run_cuda_resampling_persistent_active_path_0241.sh
```

The key expected result is a `PASS` comparison between:

- CPU baseline, and
- `persistent_active_path_0241` with `MPCD_CUDA_RESAMPLING_PERSISTENT_0240=1`.

## Limitations

0241 still uploads and downloads the particle state around the active edit
section.  The next architectural step is to keep `CudaParticleState` as the
owner of the current particle state across larger parts of the time loop and to
synchronize the host only for diagnostics, dumps, and validation.

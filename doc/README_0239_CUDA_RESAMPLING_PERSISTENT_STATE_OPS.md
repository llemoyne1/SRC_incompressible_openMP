# 0239 — CUDA resampling extraction/insertion on `CudaParticleState`

Patch 0239 moves the active resampling mutation primitives one step closer to
true GPU residency.  Patches 0236/0237 applied extraction and insertion through
host vectors: the whole particle arrays were uploaded/downloaded around the
mutation.  This patch adds variants that mutate an existing `CudaParticleState`
in place.

## New API

```cpp
bool cuda_resampling_apply_extraction_operations_on_state_0239(
    CudaParticleState& gpuState,
    const std::vector<std::uint32_t>& particleIndex,
    const std::vector<double>& particleMass,
    const std::vector<double>& momentumX,
    const std::vector<double>& momentumY,
    const CudaResamplingExtractionApplyParams& params,
    CudaResamplingPersistentOpsDiagnostics* diagnostics = nullptr);

bool cuda_resampling_apply_insertion_operations_on_state_0239(
    CudaParticleState& gpuState,
    const std::vector<std::uint32_t>& particleIndex,
    const std::vector<std::uint32_t>& receiverCell,
    const std::vector<std::uint32_t>& particleType,
    const std::vector<double>& particleMass,
    const std::vector<double>& momentumX,
    const std::vector<double>& momentumY,
    const std::vector<std::uint32_t>& insertionOrdinal,
    std::uint32_t Nx,
    std::uint32_t Ny,
    double dx,
    double dy,
    const CudaResamplingInsertionApplyParams& params,
    CudaResamplingPersistentOpsDiagnostics* diagnostics = nullptr);
```

Only the operation lists are copied to the GPU.  The particle arrays
`x/y/vx/vy/mass/type/role` are mutated directly on the resident state.

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
bash scripts/run_cuda_resampling_persistent_state_ops_smoke_0239.sh
```

The output CSV is:

```text
dev_history/artifacts/gpu_cuda_resampling_0239/cuda_resampling_persistent_state_ops_smoke_0239.csv
```

Acceptance criteria:

- `PASS` for both grid sizes;
- `roleMismatches = 0`;
- `typeMismatches = 0`;
- `maxAbsX/maxAbsY/maxAbsVx/maxAbsVy/maxAbsMass <= 1e-12`.

## Next step

If this passes, the active resampling path can use `CudaParticleState` instead of
host-vector upload/download wrappers.  That will be the first resampling mutation
path that is compatible with the persistent no-Q6 GPU stack.

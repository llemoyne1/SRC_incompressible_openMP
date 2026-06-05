# 0221 — CUDA persistent warning cleanup

This is a no-algorithm-change cleanup patch after validating the 0220 persistent particle-state path.

## Change

`src/cuda_persistent_mpcd_step.cu` no longer declares the unused local variable:

```cpp
const std::size_t nBytesD = n * sizeof(double);
```

The variable was left over from the legacy internal-upload path. In the shared `CudaParticleState` path, particle arrays are owned by the persistent particle-state manager, so the local `nBytesD` value is no longer needed.

## Expected effect

- Removes the NVCC warning:

```text
warning #177-D: variable "nBytesD" was declared but never referenced
```

- No numerical change.
- No runtime behavior change.
- No change to the CPU path.

## Recommended validation

Rebuild the CUDA target used in 0220 and rerun the same short validation:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_persistent_particle_state_active_0220.sh
```

Expected result: the same PASS status as 0220, with no `nBytesD` warning.

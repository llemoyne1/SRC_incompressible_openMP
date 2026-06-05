# 0222 — CudaParticleState upload fast path

This patch optimizes the already validated `CudaParticleState` path used by the
persistent CUDA deposit → SRC collision → thermostat substep.

## Motivation

After 0220/0221, the shared particle state was functionally correct, but the
step still paid a visible host-side overhead when uploading particle arrays.
The previous `upload_all()` and `upload_masses_and_roles()` implementations
rebuilt temporary host vectors for `role` and `type` at every upload, even when
`ParticleState` already stored those arrays explicitly.

This patch removes that avoidable host-side copy/allocation path:

- if `state.role` exists, upload it directly to device;
- if `state.type` exists, upload it directly to device;
- if either array is absent, preserve the old semantics by using `cudaMemset`
  to fill the device array with the default value;
- do not change physics, kernels, RNG, collision, thermostat, Q6, resampling, or
  validation thresholds.

## Scope

Modified file:

```text
src/cuda_particle_state.cu
```

Added validation harness:

```text
scripts/build_src_mpcd_cuda_0222.sh
scripts/run_cuda_persistent_particle_state_upload_fastpath_0222.sh
```

The patch is intentionally conservative: it does not skip any required data
upload and does not assume that masses or roles remain constant between steps.
It only removes redundant temporary host buffers before the required CUDA copy.

## Validation

Recommended validation:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_persistent_particle_state_upload_fastpath_0222.sh
```

Expected criteria:

- `verdict = PASS` for all rows;
- `failed_metrics = 0`;
- `sharedParticleStateFraction = 1` for `shared_particle_state`;
- `particleStateReusedAllocationFraction` close to 1 after the first call;
- `particleStateUploadSeconds` should be no worse than 0220 and may decrease.

## Interpretation

This is a host-side overhead cleanup. It will not eliminate the fundamental
CPU/GPU boundary yet. The next performance step is to keep the GPU particle
state authoritative across larger portions of the step, so positions/velocities
are not reuploaded every collision phase.

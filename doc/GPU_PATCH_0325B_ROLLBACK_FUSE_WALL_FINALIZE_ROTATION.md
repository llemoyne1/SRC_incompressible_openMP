# GPU patch 0325b — rollback of fused wall/finalize/rotation path

This differential archive intentionally removes the experimental 0325 fused kernel path from the active source state by restoring `src/cuda_persistent_mpcd_step.cu` and the VK CUDA runner to the validated pre-0325 / 0324 profiling state.

Measured reason:

- 0322 reference: about 7.54 s / 10000 steps on the VK periodic classic CUDA benchmark.
- 0325 enabled: about 9.18 s / 10000 steps.
- 0325 runtime-disabled while still compiled: about 9.64 s / 10000 steps.

The fusion did not reduce `srcPersistentKernel_s`, and it increased the collision envelope/download cost. Therefore 0325 should not be kept in the production/default path.

The optional 0324 kernel breakdown instrumentation remains available behind `SRC_GPU_KERNEL_BREAKDOWN_0324=1`; it is disabled by default and should not affect normal runs.

No Q6, resampling, virial, closed-capacity or inlet/outlet logic is changed by this rollback archive.

# GPU patch 0328 — appended internal kernel breakdown after 0327b

## Purpose

Patch 0328 is a profiling-only patch.  It improves the existing 0324 internal
CUDA-event microprofile so that, when explicitly requested, the file
`cuda_persistent_kernel_breakdown_0324.csv` is appended over all profiled solver
steps instead of being overwritten at each call of the persistent SRC step.

This is intended to re-rank the persistent collision/thermostat kernels on the
validated 0327b state, after the host `cellIdOut.assign(n,-1)` false download
was removed.

## Runtime flags

Normal runs are unchanged.  The append mode is enabled only when both flags are
true:

```bash
SRC_GPU_KERNEL_BREAKDOWN_0324=1
SRC_GPU_KERNEL_BREAKDOWN_APPEND_0328=1
```

The runner forwards these as:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_APPEND_0328=1
```

## Expected outputs

The dedicated harness writes under:

```text
dev_history/artifacts/gpu_kernel_breakdown_0328/
```

Important files:

```text
gpu_kernel_breakdown_0328_top_kernels.csv
gpu_kernel_breakdown_0328_rep_kernel_breakdown.csv
gpu_kernel_breakdown_0328_launch_sequence.csv
gpu_kernel_breakdown_0328_manifest.csv
runs/src_cuda_v2_0315m_periodic/rep_*/output/cuda_persistent_kernel_breakdown_0324.csv
```

Because CUDA events synchronize around every kernel launch, this harness is not
a performance benchmark.  Use short runs, typically 300 steps.

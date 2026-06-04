# Patch 0192 — CUDA Q6 timing and grid-scaling diagnostic

## Purpose

Patch 0192 keeps the SRC_GPU branch in the CUDA-only strategy, with the CPU/OpenMP path still used as the reference and default.  It does **not** expand the physics supported by the CUDA backend: `projectionBackend=cuda` remains limited to the fully periodic, unmasked Taylor--Green/Q6 subset.

The purpose of this patch is diagnostic rather than architectural.  After 0191, the persistent plan cache did not improve the 64x64 Taylor--Green runtime: the cached and uncached CUDA runs remained close, while CPU/OpenMP was still faster.  That indicates that plan upload/allocation is not the dominant bottleneck.  The likely bottleneck is the CG iteration structure itself: many small kernel launches and mandatory host-device synchronizations for CG scalars.

## Changes

- Adds optional aggregate timing for the CUDA Q6 CG solver, enabled by:

```bash
MPCD_CUDA_Q6_TIMING=1
```

- The summary is emitted at process exit as a single stderr line:

```text
[cuda_q6_timing_0192] solves=... iterations=... reductions=... operatorApplications=... totalSeconds=... ...
```

- Adds the timing fields to `CudaQ6CgDiagnostics` for later integration.
- Adds `scripts/build_src_mpcd_cuda_0192.sh`.
- Adds `scripts/run_cuda_q6_tg_timing_0192.sh`, which can run CPU/CUDA comparisons on one or more Taylor--Green grid sizes and writes a compact scaling CSV.

## Interpretation of timings

The timings are host wall-clock timings.  Unless `MPCD_CUDA_Q6_DEBUG_SYNC=1` is also set, individual kernel-launch phases mostly measure enqueue overhead.  Phases involving `cudaMemcpyDeviceToHost`, especially `hostReductionSeconds`, include the mandatory synchronization with preceding kernels.  Therefore, the most reliable quantities are:

- total CUDA Q6 CG time;
- number of solves;
- number of CG iterations;
- number of host reductions/synchronizations;
- average solve and iteration time.

The phase split is useful for locating synchronization pressure, but should not be read as a precise CUDA kernel profiler.  For kernel-level profiling, use Nsight Systems/Compute later.

## Default validation

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU

CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000' \
bash scripts/run_cuda_q6_tg_timing_0192.sh
```

For a heavier scaling test:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000 128:500 256:200' \
bash scripts/run_cuda_q6_tg_timing_0192.sh
```

Outputs:

```text
dev_history/artifacts/gpu_cuda_integration_0192/cuda_q6_tg_timing_scaling_0192.csv
runs/cuda_q6_tg_cpu_ref_0192_<grid>_<steps>/
runs/cuda_q6_tg_cuda_0192_<grid>_<steps>/
```

The script also checks that Poiseuille/non-periodic Q6 is still explicitly rejected for `projectionBackend=cuda`.

## Expected outcome

The 64x64 case is expected to remain slower on CUDA.  The key question for 0192 is whether the CUDA/CPU ratio improves as the grid grows.  If it does not, the next patch should reduce the CG scalar synchronization cost.  If it does, the next patch can safely focus on larger-domain performance and then consider expanding from fully periodic TG to the next Q6 subset.


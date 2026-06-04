# 0190 — CUDA Q6 launch-overhead cleanup

## Purpose

Patch 0189 fixed the residual-norm bug after periodic mean removal and restored
correct CUDA Q6 convergence on the integrated Taylor--Green subset. The 0189
validation showed that correctness was recovered, but also that the first
integrated CUDA path was much slower than the CPU reference on the 64x64 TG
validation case.

The measured 0189 comparison was:

- CPU reference wall time: about 16.40 s;
- CUDA wall time: about 62.59 s;
- CUDA/CPU wall-time ratio: about 3.82x slower;
- failed physical metrics: 0;
- compared physical metrics: 76;
- Q6 iterations: 140 on both CPU and CUDA;
- projected flux divergence after Q6: about 7e-11 on both CPU and CUDA.

This means the CUDA result is physically correct for the current subset, but the
implementation is still a correctness prototype, not a performance prototype.

## Change

Patch 0190 removes avoidable launch-time overhead inside the CUDA CG loop:

1. redundant `cudaDeviceSynchronize()` calls after kernel launches are disabled
   by default;
2. a debug environment variable `MPCD_CUDA_Q6_DEBUG_SYNC=1` restores explicit
   synchronization after each kernel when debugging CUDA failures;
3. redundant `cudaMemset()` calls on the per-block reduction buffer are removed
   before kernels that overwrite every block slot.

The CUDA kernels and numerical algorithm are otherwise unchanged.

## Expected numerical behavior

The patch should not change Q6 convergence or the physical summaries:

- `q6Applied = 1`;
- `q6Converged = 1`;
- `q6Iterations` should remain consistent with 0189/CPU for the TG subset;
- `q6ResidualRel` should remain finite and close to the CPU value;
- `q6DivAfterProjectedFluxRms` should remain small, typically around `1e-10` for
  the 64x64 TG regression.

## Expected performance behavior

This patch may reduce overhead, but it is not expected to make the 64x64 TG case
faster than CPU. The dominant remaining costs are still structural:

- the Q6 plan and RHS are copied to GPU for every projection call;
- the CG performs host-side scalar decisions after reductions;
- several kernels are launched per iteration;
- the tested grid is small for a GPU;
- the rest of the SRC/MPCD step remains CPU-side.

A real speedup will probably require a persistent CUDA Q6 context, device-side or
library-assisted reductions, and/or larger grids before comparing performance.

## Validation

Run:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
NX=64 NY=64 GAMMA=20 STEPS=1000 THREADS=8 \
bash scripts/run_cuda_q6_tg_regression_0190.sh
```

For CUDA debugging with explicit synchronization after each kernel:

```bash
MPCD_CUDA_Q6_DEBUG_SYNC=1 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
NX=64 NY=64 GAMMA=20 STEPS=1000 THREADS=8 \
bash scripts/run_cuda_q6_tg_regression_0190.sh
```

The unsupported Poiseuille CUDA guard remains intentionally active.

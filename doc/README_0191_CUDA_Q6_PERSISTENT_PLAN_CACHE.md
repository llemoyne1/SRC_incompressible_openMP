# Patch 0191 — CUDA Q6 persistent plan cache

## Scope

Patch 0191 keeps the CUDA-only strategy for the `SRC_GPU` branch and remains limited to the first validated subset:

- `projectionBackend=cuda`
- fully periodic boundary conditions in x and y
- no immersed-solid / projection mask
- Taylor--Green validation first

The CPU/OpenMP path remains the default and is not modified.

## Motivation

Patch 0190 fixed the launch-side overhead around synchronizations and redundant reduction-buffer clears, but the integrated Taylor--Green test remained slower than CPU on 64x64.  The dominant avoidable overhead at this stage is that every Q6 projection call reallocated and re-uploaded the constant elliptic operator plan to the GPU.

For the periodic Taylor--Green subset, the operator topology and coefficients are stable over the run.  Patch 0191 therefore introduces a thread-local CUDA CG workspace that keeps the following device buffers across calls:

- active and inactive cell lists;
- neighbour indices east/west/north/south;
- elliptic coefficients;
- CG scratch arrays `rhs`, `phi`, `r`, `p`, `Ap`;
- reduction block sums.

Only `rhs` is uploaded at every projection.  The plan is re-uploaded automatically if its signature changes.

## Safety controls

The cache is conservative:

- the plan signature includes dimensions, boundary types, active/inactive lists, neighbour maps and coefficients;
- a different grid, mask/topology or coefficient field triggers a re-upload;
- the cache is `thread_local`, avoiding cross-thread sharing;
- it can be disabled at runtime with

```bash
MPCD_CUDA_Q6_DISABLE_PLAN_CACHE=1
```

CUDA debug synchronizations from 0190 remain available:

```bash
MPCD_CUDA_Q6_DEBUG_SYNC=1
```

## Validation

Build and run:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
NX=64 NY=64 GAMMA=20 STEPS=1000 THREADS=8 \
bash scripts/run_cuda_q6_tg_regression_0191.sh
```

Optional cached-vs-uncached ablation:

```bash
RUN_CACHE_ABLATION=1 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
NX=64 NY=64 GAMMA=20 STEPS=1000 THREADS=8 \
bash scripts/run_cuda_q6_tg_regression_0191.sh
```

Expected correctness criteria:

- `q6Applied = 1`;
- `q6Converged = 1`;
- `q6Iterations` coherent with CPU, typically 140 for the 64x64 TG regression used in patches 0189--0190;
- `q6DivAfterProjectedFluxRms <= 1e-8`;
- zero failed physical metrics in the CPU/CUDA comparison.

Performance is not yet expected to beat CPU on 64x64.  The goal of 0191 is to remove one structural overhead and quantify the effect.  Larger grids will be more informative.

## Next likely steps

If 0191 remains numerically equivalent, the next performance patch should target remaining per-iteration host-device reductions in CG.  The current implementation still copies one block-sum array to host for every dot product.  A more efficient implementation would keep reductions on device or fuse CG update/reduction kernels.

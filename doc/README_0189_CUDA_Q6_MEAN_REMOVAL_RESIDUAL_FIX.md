# Patch 0189 — CUDA Q6 mean-removal residual-norm fix

Patch 0188 integrated the standalone CUDA CG into the fully periodic, unmasked
Taylor--Green Q6 path. The first integrated run showed that the CUDA path was
being accepted by the simulation but stopped after 25 iterations, exactly at the
first periodic gauge/mean-removal point. The reported `q6ResidualRel` became
zero while the final projected divergence remained much larger than the CPU
reference.

The issue was local to the CUDA CG diagnostics and stopping criterion after mean
removal. The CUDA code used the active-cell sum kernel after subtracting the mean
from the residual vector:

```text
rrNew = sum(r)
```

whereas the CG algorithm requires

```text
rrNew = sum(r*r)
```

The near-zero residual mean therefore masqueraded as a zero residual norm and
caused premature convergence at the first mean-removal period.

## Changes

- Add `q6_sum_active_squares_kernel` in `src/cuda_q6_backend.cu`.
- Use the square-sum kernel to recompute `rrNew` after CUDA residual mean removal.
- Add `scripts/build_src_mpcd_cuda_0189.sh` for a clean CUDA binary name.
- Add `scripts/run_cuda_q6_tg_regression_0189.sh`.

The CUDA subset remains unchanged:

```text
projectionBackend=cuda
fully periodic Q6
no immersed-solid mask
all cells active
```

Poiseuille, open boundaries, piston, immersed solids and Von Kármán remain CPU
until explicitly ported and validated.

## Validation

Run on the CUDA machine:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU

CUDA_ARCH_FLAGS='-arch=sm_89' \
NX=64 NY=64 GAMMA=20 STEPS=1000 THREADS=8 \
bash scripts/run_cuda_q6_tg_regression_0189.sh
```

The regression checks that CUDA Q6:

- is applied and converged;
- does not stop at the first 25-iteration gauge removal;
- reports a positive finite residual;
- reduces `q6DivAfterProjectedFluxRms` below the configured threshold;
- still rejects non-periodic Poiseuille explicitly.

The full CPU/CUDA comparison CSV is still produced, but bitwise or strict
trajectory equality over a long particle run is not used as the sole acceptance
criterion. Once CPU and CUDA floating-point reductions differ, the stochastic
particle/resampling trajectory can diverge while remaining physically acceptable.

Output files:

```text
dev_history/artifacts/gpu_cuda_integration_0189/cuda_q6_tg_compare_0189.csv
dev_history/artifacts/gpu_cuda_integration_0189/cuda_q6_tg_compare_summary_0189.csv
```

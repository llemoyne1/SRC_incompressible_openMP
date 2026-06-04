# 0195 — CUDA Q6 CG residual mean-removal norm shortcut

## Context

Patches 0188–0194 wired the CUDA Q6/elliptic CG backend into the fully periodic,
unmasked Taylor–Green subset.  The backend is numerically validated, but timing
runs show that it remains dominated by scalar CG reductions and host/device
synchronizations rather than by the elliptic stencil itself.

Patch 0193 tested a device-side scalar reduction and showed that the extra kernel
was slower for the current 64²/128² TG problem sizes.  Patch 0194 therefore
restored the host-block reduction path as the default.

## Change introduced here

Patch 0195 keeps the 0194 reduction mode as default and adds one low-risk
algebraic shortcut in the periodic gauge-fix part of CUDA CG.

During a CG iteration, `q6_axpy_residual_kernel` already computes:

```text
rrNew = sum(r_i^2)
```

When periodic mean removal is active, the code then subtracts the active-cell
mean from the residual:

```text
r_i <- r_i - mean(r)
```

The squared norm after this mean removal is exactly:

```text
sum((r_i - mean(r))^2) = sum(r_i^2) - sum(r_i)^2 / n
```

So once the residual sum `sum(r_i)` has been reduced to compute `mean(r)`, there
is no need to launch a separate post-subtraction `sum(r^2)` reduction.  Patch
0195 uses this identity by default and preserves the explicit recomputation path
for ablation.

## Runtime controls

Default 0195 behavior:

```bash
MPCD_CUDA_Q6_RESIDUAL_NORM_SHORTCUT=1
```

Legacy explicit post-mean-removal residual norm recomputation:

```bash
MPCD_CUDA_Q6_LEGACY_MEAN_REMOVAL_RESIDUAL_NORM=1
```

or equivalently:

```bash
MPCD_CUDA_Q6_RESIDUAL_NORM_SHORTCUT=0
```

The existing 0194 reduction-mode controls are unchanged:

```bash
MPCD_CUDA_Q6_HOST_BLOCK_SUM=1
MPCD_CUDA_Q6_DEVICE_SCALAR_REDUCTION=1
```

The 0194 default remains `host_blocks`; device-scalar reduction is still an
explicit ablation only.

## Validation

Build:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
  bash scripts/build_src_mpcd_cuda_0195.sh
```

Run the 64² TG validation and legacy ablation:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000' \
bash scripts/run_cuda_q6_tg_mean_removal_shortcut_0195.sh
```

Optional larger-grid run:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000 128:500' \
bash scripts/run_cuda_q6_tg_mean_removal_shortcut_0195.sh
```

To run only the default shortcut path:

```bash
RUN_LEGACY_ABLATION=0 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000' \
bash scripts/run_cuda_q6_tg_mean_removal_shortcut_0195.sh
```

Main output:

```text
dev_history/artifacts/gpu_cuda_integration_0195/cuda_q6_tg_mean_removal_shortcut_0195.csv
```

The timing line printed at process exit includes:

```text
residualNormShortcuts=<count>
```

For the default shortcut mode this count must be positive; for the legacy ablation
it must be zero.

## Expected impact

This is not expected to produce a large speedup.  The dominant cost is still the
two core CG scalar reductions per iteration (`pAp` and `rrNew`).  Patch 0195 only
removes the extra explicit residual-norm reduction triggered by periodic residual
mean removal every 25 iterations.

The goal is therefore modest but useful:

- preserve the validated CPU/CUDA numerical agreement;
- slightly reduce `cudaTimingReductions` and `hostReductionSeconds`;
- keep a reversible legacy path;
- prepare for a deeper CG-loop refactor in a later patch.

## Unsupported cases

The CUDA Q6 backend remains intentionally restricted to the fully periodic,
unmasked TG subset.  Poiseuille/wall, obstacle/backward-step, piston, open
boundaries and immersed masks must still fail explicitly with
`projectionBackend=cuda`.

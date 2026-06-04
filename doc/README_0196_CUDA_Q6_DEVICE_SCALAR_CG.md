# 0196 — CUDA Q6 device-scalar CG path

## Purpose

Patch 0196 attacks the main CUDA-Q6 bottleneck identified by the 0192--0195
regressions: host/device scalar synchronization inside the conjugate-gradient
loop.

The previous CUDA path performed, for each CG iteration:

1. `Ap = A p` and block reduction for `pAp` on GPU;
2. download `blockSums` to host and compute `pAp`;
3. compute `alpha = rr / pAp` on host;
4. update `phi,r` and block reduction for `rrNew` on GPU;
5. download `blockSums` to host and compute `rrNew`;
6. compute `beta = rrNew / rr` on host;
7. update `p` on GPU.

0196 adds a device-scalar path:

1. `Ap = A p` and block reduction for `pAp` on GPU;
2. reduce `pAp` to a device scalar, without host download;
3. compute `alpha = rr / pAp` inside the residual-update kernel;
4. update `phi,r` and block reduction for `rrNew` on GPU;
5. reduce `rrNew` to a device scalar and download only that single double for
   convergence control;
6. compute `beta = rrNew / rr` inside the direction-update kernel;
7. copy `rrNew -> rr` as a device scalar.

Thus the main loop goes from two mandatory host synchronization points per CG
iteration to one. This is a structural change, not another micro-optimization of
`blockSums` download size.

## Scope

The CUDA integration scope is unchanged:

- `projectionBackend=cuda` is still accepted only for fully periodic, unmasked Q6
  projection, currently used by the Taylor--Green periodic validation case.
- CPU/OpenMP remains the default and reference path.
- Poiseuille, obstacle/backward-step, piston, Von Kármán, immersed-solid and
  non-periodic Q6 cases must remain explicitly rejected by the CUDA backend.

## Runtime controls

Default 0196 CUDA path:

```bash
MPCD_CUDA_Q6_DEVICE_SCALAR_CG=1
```

Restore the previous host-scalar CG path:

```bash
MPCD_CUDA_Q6_DEVICE_SCALAR_CG=0
# or
MPCD_CUDA_Q6_LEGACY_HOST_SCALAR_CG=1
```

The negative 0193 scalar-reduction ablation remains disabled by default:

```bash
MPCD_CUDA_Q6_DEVICE_SCALAR_REDUCTION=0
MPCD_CUDA_Q6_HOST_BLOCK_SUM=1
```

The 0195 residual mean-removal shortcut is also kept as an explicit ablation
only, because the 0195 TG run showed that its local gain did not translate into a
global speedup:

```bash
MPCD_CUDA_Q6_RESIDUAL_NORM_SHORTCUT=0
MPCD_CUDA_Q6_LEGACY_MEAN_REMOVAL_RESIDUAL_NORM=1
```

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
  bash scripts/build_src_mpcd_cuda_0196.sh
```

## Validation

Fast regression:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000' \
bash scripts/run_cuda_q6_tg_device_scalar_0196.sh
```

More useful comparison:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000 128:500' \
bash scripts/run_cuda_q6_tg_device_scalar_0196.sh
```

The script compares:

- CPU reference;
- CUDA device-scalar CG path;
- CUDA legacy host-scalar CG path, unless `RUN_LEGACY_ABLATION=0`.

Main output:

```text
dev_history/artifacts/gpu_cuda_integration_0196/cuda_q6_tg_device_scalar_0196.csv
```

Per-mode validation comparison files are written in the same artifact directory.

## Expected diagnostics

In the timing line, the new path should show:

```text
deviceScalarCgIterations > 0
```

The legacy path should show:

```text
deviceScalarCgIterations = 0
```

The key performance signals are:

```text
hostReductionSeconds
deviceScalarReductionSeconds
cudaTimingReductions
wall CPU/CUDA
```

A successful numerical regression requires:

- `failed_metrics = 0` in the comparison summary;
- `q6Iterations CPU == q6Iterations CUDA`;
- `q6DivAfterProjectedFluxRms <= 1e-8`;
- unsupported non-periodic Poiseuille remains explicitly rejected.

## Interpretation

If 0196 works as intended, `hostReductionSeconds` should drop because the `pAp`
scalar no longer returns to the host at every CG iteration. Some time is expected
to move into `deviceScalarReductionSeconds`, but this should be cheaper than an
extra host synchronization at every iteration. If the wall-clock speed still does
not improve, the next optimization should fuse vector updates/reductions more
aggressively or move the convergence test to a less frequent cadence.

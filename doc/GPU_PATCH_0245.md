# GPU patch 0245 — periodic CUDA streaming smoke/physics validation

## Scope

Patch 0245 introduces the first CUDA force+stream path in the active
`src_mpcd_base` step, but deliberately restricts it to the strictly periodic
subset.

The CUDA path applies, for fluid particles only:

```text
vx += (bodyAccelerationX + TaylorGreenAx(x,y)) * dt
vy += (bodyAccelerationY + TaylorGreenAy(x,y)) * dt
x  += vx * dt
y  += vy * dt
periodic wrap in x/y
```

The downstream CPU boundary pass remains enabled and is idempotent for periodic
positions. All non-periodic cases keep the validated CPU streaming path.

## Explicit non-scope

The patch does **not** migrate:

- Q6/Q9 projection;
- SRC/MPCD collision;
- cell moments;
- thermostat;
- wall, obstacle, inlet/outlet, piston or segmented-boundary streaming.

Q6/Q9 are still forced to `PROJECTION_BACKEND=cpu` in the validation runner.

## New controls

```bash
MPCD_CUDA_STREAMING_PERIODIC_0245=1
MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS=256
```

The path is used only if all these conditions hold:

- `bcLeft=periodic` and `bcRight=periodic`;
- `bcBottom=periodic` and `bcTop=periodic`;
- no open-boundary segments;
- no immersed solid;
- positive `Lx`, `Ly`, non-negative `dt`.

Otherwise the CPU force+stream loop is used.

## Validation

```bash
bash scripts/run_cuda_streaming_periodic_0245.sh
```

Default cases:

```text
tg_periodic_full
64x64_s300
128x128_s300
```

Modes compared:

```text
cpu_baseline
cuda_resampling_0244_roles_only
cuda_streaming_periodic_0245
```

The second mode rechecks the already validated 0244 resampling path. The third
mode adds the new 0245 CUDA periodic streaming path on top of the 0244 resampling
path.

Expected criterion:

```text
verdict=PASS
failed_metrics=0
```

Results are written to:

```text
dev_history/artifacts/gpu_cuda_streaming_0245/cuda_streaming_periodic_0245.csv
```

## Interpretation

This patch is a functional and numerical equivalence milestone, not a global
performance milestone. Because collision and Q6 still run on CPU, the streaming
path performs an upload and download around the CUDA kernel. The expected value
is therefore validation of the kernel and integration hook, not yet a large
speedup.

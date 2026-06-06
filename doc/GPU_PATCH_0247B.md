# GPU patch 0247b — CUDA moving-y-wall piston streaming

## Purpose

Patch 0247b extends the validated CUDA streaming work to the closed piston
subset used by `piston_virial_full`:

- periodic x boundaries;
- solid/specular/bounceback y walls;
- active-domain top wall moving through `fluidYTopVelocity` / `fluidYMaxVelocity`;
- no inlet/outlet segments;
- no immersed solid;
- no Taylor--Green forcing.

The patch is intentionally limited to the force+stream and moving-y-wall
reflection step. Q6/Q9 projection, closed-capacity virial response, collision,
cell moments, thermostat and diagnostics remain CPU.

## New files

- `include/cuda_streaming_piston_0247b.h`
- `src/cuda_streaming_piston_0247b.cu`
- `scripts/build_src_mpcd_cuda_0247b.sh`
- `scripts/run_cuda_streaming_piston_0247b.sh`

`src/src_mpcd_base.cpp` is updated to try the 0247b path before the static
wall-simple 0246 path.

## Runtime switch

```bash
MPCD_CUDA_STREAMING_PISTON_0247B=1
```

The path is ignored unless the case matches the supported moving-y-wall piston
subset. Unsupported configurations fall back to the validated CPU path.

## Validation

```bash
bash scripts/run_cuda_streaming_piston_0247b.sh
```

Default validation:

- case: `piston_virial_full`
- grids: `64x64_s300`, `128x128_s300`
- modes:
  - `cpu_baseline`
  - `cuda_resampling_0244_roles_only`
  - `cuda_streaming_piston_0247b`

Expected criterion:

```text
verdict=PASS
failed_metrics=0
```

The output CSV is written to:

```text
dev_history/artifacts/gpu_cuda_streaming_piston_0247b/cuda_streaming_piston_0247b.csv
```

## Scope note

This does not migrate the virial kick itself to CUDA. The goal is only to finish
the boundary-condition family validation before moving to cell populations / cell
moments or collision.

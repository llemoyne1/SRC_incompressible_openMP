# GPU patch 0250 — active CUDA cell moments in the validated boundary stack

## Purpose

Patch 0250 is the first gain-oriented integration patch after closing the CUDA
boundary-condition validation sequence 0244--0249b.

It does not add a new numerical algorithm.  Instead, it activates an already
available CUDA particle-to-cell deposit path inside `src_collision_step` together
with the validated CUDA boundary/resampling stack:

- resampling active path `roles_only` from 0244,
- periodic streaming from 0245,
- wall-simple streaming from 0246,
- immersed rectangle handling from 0247a,
- piston/mobile-wall streaming from 0247b,
- full-face inlet/outlet extraction from 0249a,
- segmented inlet/outlet extraction from 0249b,
- active CUDA cell moments through `MPCD_CUDA_CELL_MOMENTS_USE=1`.

Q6/Q9, virial response, thermostat, hard-reservoir insertion and SRC rotation
remain CPU in this patch.

## Build

```bash
bash scripts/build_src_mpcd_cuda_0250.sh
```

The build is CUDA-enabled but keeps all accelerated paths runtime-gated.

## Validation

Default validation:

```bash
bash scripts/run_cuda_boundary_cell_moments_0250.sh
```

Default cases:

```text
tg_periodic_full
poiseuille_wall_full
open_rect_obstacle_full
piston_virial_full
segmented_u_turn_full
```

Default grids:

```text
64x64_s300
128x128_s300
```

The script compares three modes:

```text
cpu_baseline
cuda_boundary_stack_0249b
cuda_boundary_stack_cell_moments_0250
```

The output CSV is:

```text
dev_history/artifacts/gpu_cuda_cell_moments_0250/cuda_boundary_cell_moments_0250.csv
```

## Expected interpretation

The strict success criterion is unchanged:

```text
verdict=PASS
failed_metrics=0
```

For performance, the important columns are:

- `totalWallSpeedup`: total validation-case speedup versus CPU baseline,
- `maxCaseWallSpeedup`: legacy max-case speedup comparable to earlier scripts,
- `cellTotalSeconds`, `cellUploadSeconds`, `cellKernelSeconds`, `cellDownloadSeconds`,
- `cellAvgTotalSeconds`, `cellAvgKernelSeconds`.

A modest or absent global speedup is still possible because the current boundary
kernels download particle state to host before collision, and cell moments then
upload particle arrays again.  Patch 0250 measures whether replacing the CPU
O(Np) deposit by CUDA already pays for that transfer cost.  If not, the next
performance patch should remove the stream/download/deposit/upload ping-pong by
sharing a persistent `CudaParticleState` across streaming, boundary and deposit.

## Useful short runs

For a quick probe:

```bash
GRID_CASES="64:100" \
CASE_LIST="tg_periodic_full poiseuille_wall_full" \
bash scripts/run_cuda_boundary_cell_moments_0250.sh
```

For a focused large periodic test:

```bash
GRID_CASES="128:500" \
CASE_LIST="tg_periodic_full" \
bash scripts/run_cuda_boundary_cell_moments_0250.sh
```

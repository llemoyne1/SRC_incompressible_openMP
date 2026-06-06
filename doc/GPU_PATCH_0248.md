# GPU patch 0248 — combined boundary-condition stack validation

## Purpose

Patch 0248 is an integration/validation patch. It does not introduce a new CUDA
algorithmic kernel. Instead, it validates the boundary-condition CUDA modules
that were introduced separately in patches 0245--0247b under a single run.

Enabled CUDA modules in the `cuda_boundary_stack_0248` mode:

- 0244 resampling active path, `roles_only`, no `download_all`;
- 0245 periodic force/streaming, used by `tg_periodic_full`;
- 0246 wall-simple force/streaming, used by `poiseuille_wall_full`;
- 0247a immersed rectangle reflection, used by `open_rect_obstacle_full`;
- 0247b moving-y-wall piston force/streaming, used by `piston_virial_full`.

Each CUDA module remains internally gated. Unsupported cases fall back to the CPU
path.

## Explicitly still CPU

The following parts are deliberately not migrated in this patch:

- Q6/Q9 projection;
- SRC/MPCD collision;
- cell moments and cell population construction;
- hard inlet/outlet reservoir insertion/deletion;
- closed-capacity virial response;
- diagnostics and comparison machinery.

For `open_rect_obstacle_full`, the open inlet/outlet reservoir remains CPU. Patch
0248 validates only that the rectangle immersed-boundary CUDA module composes
correctly with the CPU open-boundary path.

## Run

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
bash scripts/run_cuda_boundary_stack_0248.sh
```

Default validation:

- cases: `tg_periodic_full poiseuille_wall_full open_rect_obstacle_full piston_virial_full`;
- grids: `64x64_s300` and `128x128_s300`;
- modes: `cpu_baseline`, `cuda_resampling_0244_roles_only`, `cuda_boundary_stack_0248`.

Output CSV:

```text
dev_history/artifacts/gpu_cuda_boundary_stack_0248/cuda_boundary_stack_0248.csv
```

Expected criterion:

```text
verdict=PASS
failed_metrics=0
```

for each non-baseline mode and each grid.

## Interpretation

A successful 0248 run closes the first CUDA boundary-condition validation block:
resampling + periodic streaming + wall-simple streaming + immersed rectangle +
piston streaming all compose without numerical regression on the four physical
reference cases. The next architectural step should be the GPU cell population /
cell moments path, because the loop remains dominated by CPU-owned field and
collision operations.

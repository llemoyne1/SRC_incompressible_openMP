# GPU patch 0256 — consolidated validation of persistent CUDA SRC collision

This patch adds a validation-only runner for the persistent CUDA SRC collision
path validated incrementally in 0252–0255.

It does not add a new numerical kernel. It composes the existing collision
feature flags over the four reference physics cases:

- `tg_periodic_full` — periodic collision path from 0252.
- `poiseuille_wall_full` — wall-simple path from 0253.
- `open_rect_obstacle_full` — immersed rectangle path from 0254.
- `piston_virial_full` — piston / closed-capacity path from 0255.

## Apply

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o gpu_patch_0256_files_only.zip
bash scripts/run_cuda_persistent_src_collision_stack_0256.sh
```

## Default validation matrix

```text
CASES="tg_periodic_full poiseuille_wall_full open_rect_obstacle_full piston_virial_full"
GRID_CASES="64:64:300 128:128:300"
```

For each case/grid pair, the runner compares:

```text
cpu_baseline
0251_persistent_cell_moments
0256_persistent_src_collision_stack
```

Expected result:

```text
verdict=PASS
failed_metrics=0
collisionActiveCalls > 0 for the 0256 mode
collisionSharedParticleStateFraction = 1
collisionSharedCellWorkspaceFraction = 1
collisionParticleStateUploadSeconds = 0
```

## Deliberately still CPU

- Q6/Q9 projection.
- Thermostat.
- Virial closure.
- Deterministic inlet reservoir / injection.
- Diagnostics and comparison harness.

`WALL_THERMAL_NOISE=0` is kept as in 0253–0255 so that the validation remains
bitwise/deterministically comparable to the CPU reference.

## Output

```text
dev_history/artifacts/gpu_cuda_src_collision_0256/cuda_persistent_src_collision_0256.csv
```

The CSV has one row per case/grid/mode and aggregates collision diagnostics from
`cuda_persistent_src_collision_thermostat_0215.csv` files produced in each run.

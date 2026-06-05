# GPU patch 0244 — physical validation of the active persistent resampling path

## Purpose

Patches 0241–0243 validated the active persistent CUDA resampling path on
short Taylor–Green smoke cases.  Patch 0244 does not add a new CUDA algorithm.
It adds a physical validation campaign that compares the CPU baseline against
the already validated 0243 active path on more representative configurations.

The validated CUDA path is:

```text
MPCD_CUDA_RESAMPLING_PERSISTENT_0240=1
MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_UPLOAD_MODE=roles_only
MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL=0
MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE=1
```

This remains a host-shadow architecture.  The CPU state is still authoritative
outside the resampling edit.  The objective is strict numerical equivalence, not
a full-GPU speedup.

## Scope

Default physical validation suite:

```text
tg_periodic_full
poiseuille_wall_full
```

Extended suite, enabled with `RUN_EXTENDED=1`:

```text
tg_periodic_full
poiseuille_wall_full
open_rect_obstacle_full
piston_virial_full
```

The default grid/step set is:

```text
64:300 128:300
```

where each entry is `NX:steps` and `NY=NX` unless `NY_OVERRIDE` is set.

## Important architectural point

Q6/Q9 remain CPU in this validation.  The runner explicitly forces all CUDA
paths except the persistent resampling edit to zero:

```text
MPCD_CUDA_CELL_MOMENTS_USE=0
MPCD_CUDA_THERMOSTAT_USE=0
MPCD_CUDA_SRC_COLLISION_USE=0
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=0
MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=0
```

and keeps:

```text
PROJECTION_ENABLE=true
PROJECTION_BACKEND=cpu
```

by default.

## Files added

```text
scripts/build_src_mpcd_cuda_0244.sh
scripts/run_cuda_resampling_persistent_active_physics_0244.sh
doc/GPU_PATCH_0244.md
```

No `.patch` file is included.

## Usage

After applying patch 0243, apply this zip and run:

```bash
bash scripts/run_cuda_resampling_persistent_active_physics_0244.sh
```

For the extended campaign:

```bash
RUN_EXTENDED=1 \
bash scripts/run_cuda_resampling_persistent_active_physics_0244.sh
```

For a longer validation:

```bash
GRID_CASES="64:1000 128:1000" \
RUN_EXTENDED=1 \
bash scripts/run_cuda_resampling_persistent_active_physics_0244.sh
```

For a specific GPU architecture:

```bash
CUDA_ARCH_FLAGS="--arch=sm_89" \
bash scripts/run_cuda_resampling_persistent_active_physics_0244.sh
```

## Output

The summary file is written to:

```text
dev_history/artifacts/gpu_cuda_resampling_0244/cuda_resampling_persistent_active_physics_0244.csv
```

Each active run is compared against its CPU baseline using
`compare_validation_mono_config_0162.py`.  Expected criterion:

```text
verdict=PASS
failed_metrics=0
```

for every row of the active-path mode.

## Interpretation

If the default core suite passes, the active CUDA resampling path has been shown
to be compatible with the periodic and wall-bounded physical validation cases.
If the extended suite passes, the same conclusion also covers the obstacle and
piston/virial validation cases, still with Q6/Q9 on CPU.

The next algorithmic migration step after a successful 0244 is the first
streaming CUDA patch, not further shadow-mode resampling optimization.

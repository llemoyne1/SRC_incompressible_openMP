# GPU patch 0325 — fuse wall/solid finalization and rotation setup

## Objective

Patch 0325 is a targeted follow-up to the 0324 CUDA-event kernel breakdown.
The 0324 profile did not identify a single dominant arithmetic kernel: the
remaining collision+thermostat cost is distributed over several short kernels.
Therefore 0325 targets launch/pass reduction rather than float conversion.

On the 192x64 VK-like periodic/wall/cylinder benchmark, the 0324 final-step
sample reported approximately:

- `setup_fill_rotation_tables_0272`: 0.0227 ms
- `add_wall_virtual_faces_persistent`: 0.0430 ms
- first `finalize_velocity_persistent`: 0.0092 ms

Together these represent about 21.6% of the sampled collision kernel time, but
not as one dominant arithmetic kernel.  The measured target is therefore the
launch sequence around virtual wall/solid momentum insertion and rotation table
setup.

## Change

A guarded fused cell kernel was added:

```text
add_wall_virtual_faces_finalize_rotation_persistent_0325_kernel
```

It performs in one cell pass:

1. wall / immersed rectangle / immersed circle virtual momentum contribution,
2. first cell velocity finalization,
3. device-side rotation table setup.

This replaces the sequence:

```text
setup_fill_rotation_tables_0272
add_wall_virtual_faces_persistent
finalize_velocity_persistent
```

on the shared resident collision+thermostat path when enabled.

## Runtime flag

Enabled in the VK runner by default:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSE_WALL_FINALIZE_ROTATION_0325=1
```

Disable with:

```bash
SRC_GPU_FUSE_WALL_FINALIZE_ROTATION_0325=0
```

## Expected result

In `cuda_persistent_kernel_breakdown_0324.csv`, with the 0324 breakdown enabled,
the old lines:

```text
setup_fill_rotation_tables_0272
add_wall_virtual_faces_persistent
finalize_velocity_persistent
```

should be replaced by:

```text
fuse_wall_finalize_rotation_0325
```

The expected gain is modest compared with 0318–0322, because 0324 showed the
remaining cost is broadly distributed. The goal is to verify launch reduction
without changing the SRC physics or the thermostat.

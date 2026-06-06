# GPU patch 0257 — minimal post-collision download

## Purpose

Patch 0257 targets the main bottleneck observed after the consolidated
persistent SRC collision validation 0256: the post-collision device-to-host
transfer.  Q6/Q9, thermostat, virial closure and diagnostics still run on CPU,
so the particle velocities and per-particle `cellId` still have to be downloaded
for the current continuation.  However, the collision-only CUDA path was also
downloading the post-collision cell count, cell mass and cell velocity arrays,
which are not consumed by the downstream CPU phases in the current production
ordering.

The new mode therefore keeps the strict numerical path but skips the
non-essential cell-field downloads:

```text
CUDA collision
→ download vx/vy
→ download cellId
→ download counters
→ skip cellCount/cellMass/cellUx/cellUy
→ Q6/Q9 CPU
→ thermostat CPU using cellId
```

## New switch

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
```

This switch is read inside the shared particle+cell persistent SRC collision
entry point.  It affects only the collision-only path used by 0252–0256.  The
persistent collision+thermostat path is unchanged.

## Validation script

```bash
bash scripts/run_cuda_persistent_src_collision_min_download_0257.sh
```

The script compares:

```text
cpu_baseline
0251_persistent_cell_moments
0256_full_collision_download
0257_minimal_collision_download
```

on the four reference physics cases:

```text
tg_periodic_full
poiseuille_wall_full
open_rect_obstacle_full
piston_virial_full
```

for:

```text
64x64_s300
128x128_s300
```

## Expected outcome

The required numerical criterion remains:

```text
verdict = PASS
failed_metrics = 0
```

The performance criterion is a reduction of:

```text
collisionDownloadSeconds
collisionTotalSeconds
```

relative to `0256_full_collision_download`.  The global wall-clock speedup may
remain limited because Q6/Q9, thermostat, virial closure, inlet reservoirs and
runtime diagnostics are still CPU-side.

## Limitations

This patch is deliberately not the final GPU-owner loop.  It does not skip the
velocity download, because Q6/Q9 and thermostat still need CPU-side velocities.
A larger subsequent patch would have to move the next velocity-consuming phase
onto CUDA or defer host synchronization to summary/dump steps.

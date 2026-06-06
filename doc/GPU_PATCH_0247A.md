# GPU patch 0247a — CUDA immersed rectangle boundary validation

## Scope

Patch 0247a keeps the same conservative migration strategy used in 0244--0246:
validate one boundary family at a time, with all unsupported physics falling back
to the OpenMP/CPU path.

This patch offloads only the immersed solid reflection for the static,
axis-aligned rectangle used by `open_rect_obstacle_full`:

- supported shape: `immersedSolidShape = rectangle`;
- supported body motion: static rectangle only (`immersedSolidVx = 0`,
  `immersedSolidVy = 0`, `immersedSolidOmega = 0`);
- CPU remains authoritative for force/stream, inlet/outlet handling, Q6/Q9,
  collision, cell moments, thermostat and diagnostics;
- CUDA resampling active path 0244/0243 may be kept enabled as an already
  validated companion path.

The CUDA call is inserted at the existing `Immersed` phase, after the CPU
boundary operator and before collision, matching the validated CPU order:

```text
force/stream -> boundary -> immersed solid -> collision -> Q6 -> ...
```

If the requested configuration is unsupported, the code falls back to
`apply_immersed_solid_reflection(...)` on CPU.

## New switch

```bash
MPCD_CUDA_IMMERSED_RECTANGLE_0247=1
```

Optional block size:

```bash
MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS=256
```

## Validation

Run from the repository root:

```bash
bash scripts/run_cuda_immersed_rectangle_0247a.sh
```

Default validation:

```text
case: open_rect_obstacle_full
grids: 64x64_s300, 128x128_s300
modes:
  - cpu_baseline
  - cuda_resampling_0244_roles_only
  - cuda_immersed_rectangle_0247a
```

Expected result:

```text
verdict=PASS
failed_metrics=0
```

Output CSV:

```text
dev_history/artifacts/gpu_cuda_immersed_rectangle_0247a/cuda_immersed_rectangle_0247a.csv
```

## Notes

Patch 0247a is a boundary-condition validation patch, not a performance patch.
It still uploads and downloads the particle state around the immersed-rectangle
kernel. This is intentional: the purpose is to validate the solid-mask/reflection
operator before migrating cell populations, moments, or the full owner-state
particle loop.

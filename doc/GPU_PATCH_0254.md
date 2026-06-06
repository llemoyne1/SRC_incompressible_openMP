# GPU patch 0254 — persistent SRC collision with immersed rectangle

## Scope

Patch 0254 extends the persistent CUDA SRC collision path validated in 0252/0253 to the deterministic immersed-rectangle subset used by `open_rect_obstacle_full`.

Validated target:

- case: `open_rect_obstacle_full`
- geometry: open inlet/outlet channel with a static rectangular immersed solid
- CUDA boundary stack: resampling 0244, boundary stack 0249a/0247a, persistent cell state 0251
- CUDA collision: persistent SRC collision consuming the shared 0251 particle state
- CPU: Q6/Q9 projection, thermostat, hard inlet reservoir/injection, diagnostics

## Deliberate restrictions

The CUDA collision branch is enabled only when:

- `MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=1`
- `immersedSolidEnable=true`
- `immersedSolidShape=rectangle`
- `immersedSolidVx=immersedSolidVy=immersedSolidOmega=0`
- `wallThermalNoise=0`
- full-domain bounds are used

Moving solids, circles, rotating solids and stochastic virtual-wall noise remain CPU-only for now.

## Algorithmic addition

The CUDA persistent collision backend already had deterministic virtual-wall mass/momentum contributions for external walls. Patch 0254 adds the corresponding immersed-rectangle virtual contribution:

```text
solidFraction(cell) * cellArea
→ equivalent virtual particle count
→ virtual mass and momentum added before cell mean velocity finalization
→ SRC rotation around the same cell mean as the CPU path
```

The rectangle solid fraction is computed on the device with the same sample-grid rule as the CPU helper `immersed_solid_fraction_in_cell()` for the static rectangle subset.

## Validation

Run:

```bash
bash scripts/run_cuda_persistent_src_collision_solid_0254.sh
```

Default validation:

```text
open_rect_obstacle_full
64x64_s300
128x128_s300
```

Compared modes:

```text
cpu_baseline
0251_persistent_cell_moments_solid
0254_persistent_src_collision_solid_shared
```

Expected criterion:

```text
verdict=PASS
failed_metrics=0
collisionActiveCalls > 0
collisionSharedParticleStateFraction = 1
collisionSharedCellWorkspaceFraction = 1
collisionParticleStateUploadSeconds = 0
```

Output:

```text
dev_history/artifacts/gpu_cuda_src_collision_0254/cuda_persistent_src_collision_0254.csv
```

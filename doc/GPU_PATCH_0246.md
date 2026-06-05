# GPU patch 0246 — CUDA wall-simple streaming validation

## Scope

Patch 0246 extends the CUDA force/stream hook beyond the strictly periodic
0245 subset.  The new path is intentionally narrow:

- `bcLeft = bcRight = periodic`,
- `bcBottom` and `bcTop` in `{solid, specular, bounceback}`,
- static active domain,
- no open-boundary segments,
- no immersed solid,
- no piston/domain-motion wall.

This is the Poiseuille wall-simple validation step.  Q6/Q9, cell moments,
collision, thermostat, diagnostics and the general boundary machinery remain CPU.
The already validated 0244 resampling active path is kept as a companion mode.

## New switch

```bash
MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
```

The periodic 0245 switch is forced to zero by the validation script when 0246 is
tested.

## CUDA operation

For fluid particles, the CUDA kernel applies:

```text
vx += ax dt
vy += ay dt
x  += vx dt
x periodic wrap
y  += vy dt
y wall reflection for bottom/top static walls
```

The CPU boundary pass still runs after this phase.  For the supported subset it
is idempotent, which keeps the global pipeline unchanged while validating the
wall-simple device update.

## Build and validation

```bash
bash scripts/run_cuda_streaming_wall_simple_0246.sh
```

Default validation:

```text
case       : poiseuille_wall_full
grids      : 64x64_s300, 128x128_s300
modes      : cpu_baseline, cuda_resampling_0244_roles_only, cuda_streaming_wall_simple_0246
projection : CPU
```

Output CSV:

```text
dev_history/artifacts/gpu_cuda_streaming_0246/cuda_streaming_wall_simple_0246.csv
```

Expected criterion:

```text
verdict=PASS
failed_metrics=0
```

## Non-goals

This patch does not migrate:

- open-channel inlet/outlet streaming,
- obstacle / immersed-solid reflection,
- piston / moving-domain reflection,
- Q6/Q9 projection,
- SRC collision,
- GPU-owned full time loop.

# GPU patch 0259 — durable classic SRC CUDA mode

Patch 0259 adds a durable runtime option for running a classic SRC/MPCD path
inside the SRC incompressible codebase.

## New parameter

```kv
srcClassicCudaModeEnable = true
```

Accepted aliases are:

```kv
classicSrcCudaModeEnable = true
classicSrcModeEnable = true
classicSrcCudaMode = true
```

When enabled, the step driver keeps the particle SRC/MPCD operators but
short-circuits the incompressible closure stages:

```text
force / streaming / boundary / immersed solid
→ SRC collision
→ no Q6/Q9 projection
→ no closed-capacity virial kick
→ deterministic cell-relative thermostat
```

The option is intentionally independent from `projectionEnable` and the
closed-capacity parameter blocks. This allows older validation cases, including
`piston_virial_full`, to be reused while forcing classic SRC physics.

## CUDA classic mode used by the runner

The 0259 runner compares:

```text
cpu_classic
0257_classic_cuda_collision_cpu_thermostat
0259_classic_cuda_fused_thermostat
```

The final mode uses the fused persistent CUDA path:

```text
CUDA streaming / boundary stack
→ CUDA cell moments + SRC collision
→ deterministic CUDA cell-relative thermostat
→ host download / diagnostics
```

This fused collision+thermostat order is valid here because Q6/Q9 and virial are
short-circuited. It must not be used as a replacement for the incompressible
operator ordering unless the projection stage is disabled.

## Deterministic validation settings

The runner enforces:

```text
srcClassicCudaModeEnable=true
projectionEnable=false
resamplingEnable=false
wallThermalNoise=0
thermostatEnable=true
thermostatMode=cell_relative_rescale
```

The thermostat is the deterministic relative-rescale thermostat, so strict
CPU/CUDA comparison remains possible.

## Scope

Default cases:

```text
tg_periodic_full
poiseuille_wall_full
open_rect_obstacle_full
piston_virial_full
```

The segmented U-turn inlet/outlet case is not included by default in this patch
because persistent CUDA SRC collision has not yet been validated for the fully
segmented/all-wall collision subset. Segmented inlet/outlet boundary handling
itself was validated in 0249b.

## Run

```bash
bash scripts/run_cuda_classic_src_mode_0259.sh
```

Short smoke:

```bash
GRID_CASES="64:64:100" \
CASES="tg_periodic_full poiseuille_wall_full" \
bash scripts/run_cuda_classic_src_mode_0259.sh
```

Expected result:

```text
verdict=PASS
failed_metrics=0
```

Output CSV:

```text
dev_history/artifacts/gpu_cuda_classic_src_0259/cuda_classic_src_mode_0259.csv
```

# GPU patch 0249a — full-face inlet/outlet CUDA pre-deactivation

## Goal

Patch 0249a adds the first CUDA treatment of non-segmented inlet/outlet boundary
conditions.  It is deliberately limited to full-face inlet/outlet pairs with the
existing hard inlet reservoir mode.

The target validation case is:

- `open_rect_obstacle_full`

## Scope

CUDA in 0249a:

- detects fluid particles that crossed a full-face inlet/outlet boundary;
- marks outlet exits as inactive;
- marks inlet backflow exits as inactive;
- clamps inactive slots back into the domain, matching the CPU hard-reservoir
  representation;
- returns hit and deletion counters, which are merged into the CPU boundary
  diagnostics.

CPU remains responsible for:

- hard-reservoir cell reconstruction/insertion;
- inlet thermal sampling and deterministic seeding;
- wall reflections on non-I/O faces;
- segmented `openBoundarySegment*` apertures;
- Q6/Q9 projection, collision, thermostat, diagnostics and virial response.

This split is intentional.  It validates the I/O deletion/deactivation part
without moving the stochastic hard-reservoir injector, which is the part most
likely to break bitwise reproducibility.

## Activation

The new path is compiled with:

```bash
-DMPCD_ENABLE_CUDA_INLET_OUTLET_FULLFACE_0249A
```

and activated at runtime with:

```bash
MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=1
```

The path refuses to run unless all of the following hold:

- `inletReservoirMode` resolves to `hard_cell_density` / `hard_density` /
  `hard` / `cell_density`;
- `openBoundarySegmentsEnable=false` and `openBoundarySegmentCount=0`;
- there is exactly one full-face inlet/outlet pair, either left/right or
  bottom/top;
- the two opposite I/O faces are one inlet and one outlet.

Unsupported cases fall back to the CPU path.

## Validation

Run:

```bash
bash scripts/run_cuda_inlet_outlet_fullface_0249a.sh
```

Default validation:

- `open_rect_obstacle_full`
- `64x64_s300`
- `128x128_s300`

Compared modes:

1. `cpu_baseline`
2. `cuda_boundary_stack_0248`
3. `cuda_inlet_outlet_fullface_0249a`

Expected criterion:

```text
verdict=PASS
failed_metrics=0
```

Output CSV:

```text
dev_history/artifacts/gpu_cuda_inlet_outlet_0249a/cuda_inlet_outlet_fullface_0249a.csv
```

## What remains CPU after 0249a

- segmented inlet/outlet apertures;
- hard-reservoir injection sampling;
- cell moments and populations in the active path;
- collision;
- Q6/Q9;
- virial response.

After this patch passes, the boundary-condition family is covered for the
non-segmented validation cases, and the next large integration step can move to
cell populations / moments or to segmented apertures, depending on project
priority.

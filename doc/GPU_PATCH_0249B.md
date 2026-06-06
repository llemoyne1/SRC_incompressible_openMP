# GPU patch 0249b — segmented inlet/outlet, same-face U-turn validation

## Scope

0249b adds a deliberately narrow CUDA inlet/outlet boundary path for compact
`openBoundarySegment*` apertures.  The validation target is a closed box with
both inlet and outlet on the left face `x=0`, so that the particle flow must turn
inside the domain.

The CUDA path only handles the extraction/deactivation part of segmented open
boundaries:

- detect a fluid particle crossing a segmented aperture;
- decide whether the crossed segment is inlet or outlet;
- mark the particle inactive;
- clamp the inactive slot back into the box;
- return hit/deletion counters.

The existing CPU path still performs:

- solid reflection on the uncovered portions of the segmented face;
- deterministic hard-reservoir insertion;
- Q6/Q9 projection;
- collision, thermostat and resampling diagnostics.

This keeps the generator/insertion side deterministic and comparable to the CPU
reference.

## Supported subset

0249b is intentionally restricted to the same-face U-turn case:

```text
bcLeft   = solid
bcRight  = solid
bcBottom = solid
bcTop    = solid
openBoundarySegmentsEnable = true
openBoundarySegment0 = left inlet  ...
openBoundarySegment1 = left outlet ...
```

Other segmented topologies remain CPU until separate validation patches.

## Validation

Run:

```bash
bash scripts/run_cuda_inlet_outlet_segmented_0249b.sh
```

The script compares:

```text
cpu_baseline
cuda_boundary_stack_0248
cuda_inlet_outlet_segmented_0249b
```

on:

```text
segmented_u_turn_full
64x64_s300
128x128_s300
```

Expected criterion:

```text
verdict=PASS
failed_metrics=0
```

The CSV is written to:

```text
dev_history/artifacts/gpu_cuda_inlet_outlet_0249b/cuda_inlet_outlet_segmented_0249b.csv
```

## Still CPU after this patch

- segmented hard-reservoir insertion;
- cell moments / populations;
- SRC collision;
- Q6/Q9;
- virial response.

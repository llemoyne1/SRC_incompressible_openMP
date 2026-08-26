# 0493x6b — phase-aware interface geometry diagnostic

## Purpose

0493x6b is the geometry-only step after the validated x6a gas-pressure diagnostic.
It does **not** change the Q6 operator, the free-surface boundary condition, the
particle correction, SRC collisions, Darcy/chi, boundaries or resampling.

The objective is to measure whether the binary `free_surface_masked` support can
be replaced by a phase-aware sub-cell interface representation before the gas
pressure is coupled into the incompressible projection.

## Phase quantity

The diagnostic reconstructs, directly from the already resident species-cell
mass deposit,

```
phaseFill(c) = sum_{species phaseFamily=liquid} M_s(c)
               / sum_{species phaseFamily=liquid} M_ref,s
```

The raw value is intentionally not clipped to `[0,1]`: values above one expose
local compression. It is therefore a **phase-fill proxy**, not yet a VOF field.
No extra `O(Ncells)` geometry array is allocated.

For every face of the exact pre-stream Q6 support separating an active liquid
cell from an in-domain inactive cell, x6b measures two linear crossing
locations between cell centres:

- `support theta`: crossing of the current support threshold
  `speciesQ6MinOccupancyFraction`;
- `half-iso theta`: crossing of `phaseFill=0.5`, only when it is actually
  bracketed by the two cells.

The current x5a operator always places the boundary at `theta=0.5`. x6b only
measures the alternatives; it does not consume them.

A raw phase-fill gradient is also reconstructed on interface cells to audit the
outward normal direction required later for surface tension. No curvature is
computed in x6b.

## Cost discipline

The diagnostic deliberately avoids a particle pass and avoids a persistent
geometry field. It adds one `O(Ncells)` CUDA pass and one small accumulator
copy to the host only at step 1 and on the existing `summaryEvery` cadence.
When `MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B` is disabled, this stage adds
no kernel launch.

This is diagnostic scaffolding only. Before any geometry quantity becomes part
of the production Q6 path, its calculation must be fused with the projection
stencil/support construction so that a separate full-grid pass is not retained
unnecessarily.

The CSV includes `diagnosticSeconds` so the cost can be measured directly.

## Run

```bash
LIVE_PROGRESS=1 \
STEPS=20 \
LIVE_VIS_ENABLE=0 \
LIVE_VIS_HOLD_ON_EXIT=0 \
bash scripts/run_0493x6b_phase_geometry_diagnostic.sh
```

The geometry audit is written to
`output/cuda_phase_interface_geometry_0493x6b.csv`.

## Intended next step

If x6b is numerically stable and the half-isosurface is sufficiently well
resolved, x6c will use a qualified sub-cell geometry for the **liquid-vacuum**
`p_gamma=0` projection first. Only after that non-regression will the x6a gas
pressure be coupled as the interface Dirichlet datum.

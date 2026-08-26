# 0493x6f — resident phase-interface pressure stencil (`pGamma = 0`)

## Purpose

0493x6f turns the x6c resident phase geometry into the pressure-domain stencil
that later stages will reuse for gas pressure and surface tension.  It is the
first active path whose physical interface is the filtered `alpha=0.5`
isosurface rather than the numerical occupancy-support boundary.

The intended sequence is:

```
x6c alpha -> x6f interface stencil -> x6g p_g -> x6h curvature -> x6i p_g + sigma*kappa
```

No gas pressure and no surface tension are introduced in x6f.  The interfacial
Q6 pressure remains zero gauge.

## Separation of roles

For `free_surface_masked`, the existing regularized occupancy mask remains the
**carrier**: it says where liquid particle data are sufficiently supported and
it remains the band on which particle corrections can be applied.

The new pressure mask is

```
pressureMask(c) = carrierMask(c) && alpha(c) >= 0.5
```

so the pressure unknowns are on the liquid side of the physical phase
indicator.  An `alpha=0.5` crossing that used to be `active-active` in x6e is
therefore an ordinary pressure-domain boundary in x6f.

This intentionally removes the x6d identification

```
carrier boundary == physical pressure boundary
```

which x6e disproved in the deformed dam-break.

## Prepared face stencil

One CUDA grid pass per Q6 solve creates:

- `phasePressureMask0493x6f`;
- `phaseFaceCoeffX0493x6f` for the east face owned by each cell;
- `phaseFaceCoeffY0493x6f` for the north face owned by each cell.

The coefficients are:

```
1             pressure interior face
1/theta       represented alpha=0.5 interface, theta >= 0.10
2             represented alpha=0.5 interface, theta < 0.10
0             no pressure coupling
```

with

```
theta = (alpha_liquid - 0.5)/(alpha_liquid - alpha_exterior).
```

The `theta < 0.10` treatment deliberately keeps the already-qualified x6d
small-cut-cell stabilization so x6f changes interface topology/preparation
without simultaneously changing the conditioning policy.

A face where `alpha >= 0.5` continues across the face but the carrier ends gets
coefficient zero and is counted as `carrierTruncationFaces`; it is **not**
converted into an artificial zero-pressure surface.  An `alpha=0.5` crossing
whose liquid side is outside the carrier is counted as
`uncoveredInterfaceFaces`.

External non-periodic domain faces are not reclassified by x6f.  Existing wall,
open-boundary, segmented-I/O and other external-BC logic remains authoritative.
Darcy/chi is likewise not reinterpreted in this patch.

## CG cost contract

The x6d path reconstructed `theta` from `alpha` inside every CG operator
application.  x6f does those reads/divisions/branches once in the preparation
pass.  Every CG iteration reads only the pressure mask and prepared X/Y face
coefficients.

For a 300x150 grid, x6f adds permanently while enabled:

```
45000 * (1 byte + 2 * 8 bytes) = 765000 bytes
```

in addition to the two x6c double fields.  No new particle pass is added.

## Correction band

The pressure solve and projected-divergence audit use the x6f pressure mask.
The cell correction is reconstructed on the historical carrier band before
being applied to liquid particles.  This lets an exterior-side mixed carrier
cell receive the adjacent interface-face pressure gradient without turning
that cell into a pressure unknown.

This is deliberately a first-order sharp-interface scaffold.  The static-drop
and curvature stages will determine whether a more elaborate interpolation is
needed; x6f does not add one pre-emptively.

## Strong topology audit

Set by the x6f runner:

```
MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0
MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1
MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
```

The sparse audit writes

```
cuda_phase_interface_stencil_0493x6f.csv
```

and verifies against x6e that, on every audited step,

```
representedInterfaceFaces
    = x6e(active-active + active-inactive/liquid-side)

uncoveredInterfaceFaces
    = x6e(active-inactive/exterior-side + inactive-inactive)

represented + uncovered = every alpha=0.5 crossing.
```

This is the key invariant showing that the alpha-defined interface, not the
carrier boundary, is what the prepared pressure stencil represents.

## Current scope

x6f is enabled only through the experimental environment gate and only in the
existing `free_surface_masked` path.  It is not yet the final multi-phase API.
The field definition already aggregates all species whose `phaseFamily` is
`Liquid`, but the current projected velocity/correction path remains the
qualified species-Q6 implementation.  A future phase-common projection should
reuse the stencil rather than duplicate it per species.

Most importantly, x6f contains no dam-break-specific geometry or dimensions.
The dam-break runner is only the first dynamic qualification case.

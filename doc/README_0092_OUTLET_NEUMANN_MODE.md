# 0092 — Neumann-like outlet mode for Q6/Q9 inlet/outlet projections

## Purpose

This note documents the first implementation of a Neumann-like outlet option for
Q6 velocity projection and Q9 mass-flux projection in the C++ SRC/MPCD
`feature/inlet-outlet` branch.

The validated full-channel inlet/outlet cases remain unchanged by default.  They
continue to use the historical balanced-flux policy:

```text
openBoundaryOutletMode = balanced_flux
```

The new option is explicit and opt-in:

```text
openBoundaryOutletMode = neumann
```

Aliases accepted by the parser are `free`, `zero_gradient` and
`zero_normal_gradient`.

## Numerical meaning

The implementation keeps the existing generic finite-volume elliptic projection
operator.  No FFT path and no outlet-specific solver were added.

For an inlet/outlet pair, the policy is now:

- the inlet projection flux remains prescribed from the ramped inlet velocity;
- with `balanced_flux`, the outlet projection flux is prescribed from the same
  ramped inlet target, as in the validated 0062/0063 policy;
- with `neumann`, the outlet projection flux is sampled from the current local
  base face flux before projection.

Thus, on the open part of the outlet, the projection applies zero normal
correction to the outlet flux.  This is the practical Neumann/zero-normal-gradient
condition for the pressure/projection correction in the compact face-field
layout.

For segmented apertures, the outlet aperture remains free but the complementary
part of the boundary remains impermeable: the sampled outlet profile is set to
zero outside the configured open segment.

## Parameters

```text
openBoundaryOutletMode = balanced_flux | neumann
```

Accepted aliases:

```text
balanced_flux: balanced_flux, prescribed_flux, balanced, prescribed, dirichlet
neumann      : neumann, free, zero_gradient, zero_normal_gradient
```

The setting affects Q6 and Q9 projection boundary fluxes.  It does not alter the
particle boundary handling: outlet particles crossing the outlet are still
deleted/recycled according to the existing inlet/outlet particle-reservoir path.

## Diagnostics to watch

In `balanced_flux` mode, the imposed inlet/outlet fluxes are globally balanced by
construction, up to profile/aperture discretisation.

In `neumann` mode, the outlet flux is whatever the current flow carries through
the outlet face.  Therefore the global open-boundary balance is a diagnostic, not
a constraint.  Monitor the following columns in `summary_runtime.csv`:

```text
q6OpenBoundaryFluxBalance
q6OpenBoundaryMeanDivergence
q9OpenBoundaryMassFluxBalance
q9OpenBoundaryMeanDivergence
```

A persistent non-zero balance means the simulated open domain is not yet in a
statistically balanced through-flow state, or that the outlet/aperture geometry
is constraining the flow.

## Updated slit/nozzle prototype

`scripts/run_open_channel_jet.sh` now defaults to:

```bash
OUTLET_MODE=neumann
```

Set

```bash
OUTLET_MODE=balanced_flux
```

to compare directly against the validated full-channel projection policy.

## Scope and cautions

This patch is intentionally conservative:

- no change to the default full-channel validation runners;
- no change to `method=classic`;
- no change to the elliptic solver topology;
- no immersed-solid Q9/virial boundary fix.

The method is intended first for physical segmented aperture / slit-nozzle cases.
The existing conclusion remains valid: Q9/virial behavior near immersed solids is
a separate branch-level problem and should be handled with a dedicated face/cell
solid mask.

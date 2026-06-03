# Generic elliptic projection core

This module introduces the first C++ elliptic projection core intended to be
shared by future Q6, Q9 and surface-tension developments.

The core is deliberately not named as a Q6-only module. It projects a generic
face field:

```text
F_new = F_base + F_corr
F_corr = -alpha grad(phi)
div(F_new) = target
```

which gives the elliptic problem

```text
A phi = target - div(F_base)
A     = -div(alpha grad)
```

For the currently implemented periodic and channel Neumann configurations, `A`
has a constant nullspace. The implementation therefore removes the mean of the
right-hand side and keeps `phi` mean-free.

## Discretization

The grid is finite-volume/cell-centered:

- scalar fields have one value per cell;
- `PeriodicFaceField.x(i,j)` is the east face of cell `(i,j)`;
- `PeriodicFaceField.y(i,j)` is the north face of cell `(i,j)`;
- divergence is computed by face flux differences;
- the correction flux is built from the same face gradient used by the operator.

The face-field name is historical: the same compact storage is now also used for
channel-like no-normal-flux boundaries. For a wall-normal direction, the high
boundary face is stored in the last cell and the low boundary face is implicit
and fixed to zero normal flux.

The operator is applied matrix-free and solved by conjugate gradients on the
compatible mean-zero subspace.


## Boundary configurations currently implemented

The generic core currently supports:

```text
periodic : periodic x, periodic y
channel  : periodic x, no-normal-flux walls in y
```

The channel configuration is the intended elliptic foundation for later
periodic-x / wall-y Q6 Poiseuille validation. It is still independent of the
particle solver: the Q6 adapter has not yet been switched to the channel operator
in this patch.

## Intended adapters

The same core can be used by different physical adapters.

### Q6 velocity projection

```text
F_base = face velocity u*
target = 0
alpha  = 1
```

The resulting correction flux is converted into a particle velocity correction.

### Q9 mass-flux projection

```text
F_base = face mass/occupancy flux N u*
target = density-relaxation or low-k target
alpha  = mass-flux correction coefficient
```

The resulting flux correction is converted into a particle velocity kick, with
appropriate mass/occupancy normalization.

### Future surface tension

The capillary module can reuse the same face geometry, gradients, divergence
and elliptic machinery when coupling capillary pressure/force to Q6/Q9.

## Generic elliptic low-pass filter

The same module also exposes a Helmholtz-type low-pass filter for cell-centered
fields:

```text
(I + length^2 A) f_filtered = f_input,
A = -div(alpha grad)
```

This filter uses the same matrix-free operator, face coefficients and boundary
policy as the projection solve. It is used by the Q9 adapter to reproduce the
MATLAB-style `elliptic_lowpass` filtering of the density-relaxation target, and
it is intentionally generic so that future interface and surface-tension modules
can reuse it for smoothed density, color, curvature or capillary-pressure fields.

## Standalone validation

Build:

```bash
./scripts/build_src_mpcd_base.sh
```

Run the manufactured periodic validation:

```bash
./build/validate_elliptic_projection --Nx 64 --Ny 48 --alphaVariation 0.25 \
  --bc periodic --csv elliptic_projection_periodic_validation.csv
```

Run the manufactured channel validation:

```bash
./build/validate_elliptic_projection --Nx 64 --Ny 48 --alphaVariation 0.25 \
  --bc channel --csv elliptic_projection_channel_validation.csv
```

Both validations construct a known cell scalar `phi_true`, build

```text
F_base = alpha grad(phi_true)
```

and projects it to zero divergence with `target=0`. A consistent operator must
recover `phi_true` up to an arbitrary constant and cancel the flux.

Expected diagnostics:

```text
converged = true
residualRel << 1
divAfterRms / divBeforeRms << 1
projectedFluxRms << 1
phiRmsErrorMeanFree << 1
```

This test validates the elliptic core independently of SRC/MPCD particles,
thermostats, walls, immersed solids, Q6 or Q9.

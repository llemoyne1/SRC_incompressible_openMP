# Generic periodic elliptic projection core

This module introduces the first C++ elliptic projection core intended to be
shared by future Q6, Q9 and surface-tension developments.

The core is deliberately not named as a Q6-only module. It projects a generic
periodic face field:

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

On a fully periodic domain, `A` has a constant nullspace. The implementation
therefore removes the mean of the right-hand side and keeps `phi` mean-free.

## Discretization

The grid is finite-volume/cell-centered:

- scalar fields have one value per cell;
- `PeriodicFaceField.x(i,j)` is the east face of cell `(i,j)`;
- `PeriodicFaceField.y(i,j)` is the north face of cell `(i,j)`;
- divergence is computed by face flux differences;
- the correction flux is built from the same face gradient used by the operator.

The operator is applied matrix-free and solved by conjugate gradients on the
compatible mean-zero periodic subspace.

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

## Standalone validation

Build:

```bash
./scripts/build_src_mpcd_base.sh
```

Run the manufactured periodic validation:

```bash
./build/validate_elliptic_projection --Nx 64 --Ny 48 --alphaVariation 0.25 \
  --csv elliptic_projection_validation.csv
```

The validation constructs a known cell scalar `phi_true`, builds

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

# Active fluid domain inside the fixed numerical box

The SRC/MPCD base executable now distinguishes two geometric objects:

1. the **fixed numerical box** `[0,Lx] x [0,Ly]`, used for fixed-size arrays, collision grid dimensions and periodic wrapping;
2. the **active fluid domain** inside that box, used by solid-wall reflection, solid-thermal wall fractions and physical density diagnostics.

For all existing fixed-domain runs, the active fluid domain is identical to the numerical box:

```text
fluidXMin0 = 0
fluidXMax0 = -1   # negative => Lx
fluidYMin0 = 0
fluidYMax0 = -1   # negative => Ly
```

The parser also accepts the aliases:

```text
fluidYTop0 = ...
fluidYTopVelocity = ...
```

which map to `fluidYMax0` and `fluidYMaxVelocity`. These aliases are intended to make later piston tests explicit:

```text
# Future top-piston style domain; not a complete EOS test by itself.
fluidYTop0 = 1.0
fluidYTopVelocity = -1.0e-5
```

## Runtime geometry

At time `t`, the active domain is

```text
xMin(t) = fluidXMin0 + fluidXMinVelocity * t
xMax(t) = fluidXMax0 + fluidXMaxVelocity * t   # with fluidXMax0<0 meaning Lx at t=0

yMin(t) = fluidYMin0 + fluidYMinVelocity * t
yMax(t) = fluidYMax0 + fluidYMaxVelocity * t   # with fluidYMax0<0 meaning Ly at t=0
```

The code currently keeps the numerical grid fixed. Moving bounds are therefore represented as a changing solid region inside the fixed box, not by remeshing.

## What uses the active domain

The active domain is used by:

- solid-wall reflection;
- solid-thermal wall virtual-mass fractions;
- the active fluid area reported in `summary_runtime.csv`;
- the physical mean density `totalMass / fluidArea`.

The fixed numerical box is still used by:

- periodic wrapping;
- the fixed collision-grid size `Nx x Ny`;
- dump arrays and post-processing binning unless a post-processing script explicitly masks the solid region.

## Periodic axes

A periodic axis must currently use a full static active domain on that axis. For example, if `bcLeft=bcRight=periodic`, then the active x-domain must remain `[0,Lx]` with zero x-boundary velocities. This avoids an ambiguous combination of changing fluid length with fixed periodic wrapping.

## Diagnostics policy

The runtime summary records only geometric quantities that cannot be reconstructed from a particle dump alone without knowing the exact time-dependent active-domain state:

```text
fluidXMin, fluidXMax, fluidYMin, fluidYMax, fluidArea, meanPhysicalDensity
```

Detailed density fields, profiles, fits and spectra remain post-processing tasks.

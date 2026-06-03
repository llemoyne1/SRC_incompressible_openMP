# Incompressible Q6/Q9 development status

This document summarizes the current state of the incompressible branch built on
top of the validated compressible SRC/MPCD base.

The compressible baseline remains available on `clean/src-mpcd-base`. The
incompressible development is carried by `feature/elliptic-q6-core`.

## Design rule

Q6, Q9 and the future surface-tension module must share the same discrete
elliptic machinery. The core object is not a Q6-specific pressure projection and
not a Q9-specific mass-flux correction. It is a generic face-flux projection:

```text
F_new = F_base - alpha grad(phi)
div(F_new) = target
```

Equivalently:

```text
-div(alpha grad(phi)) = target - div(F_base)
```

The same finite-volume/matrix-free operator is used for:

- periodic Q6 velocity projection;
- periodic-x / wall-y Q6 channel projection;
- Q9 mass-flux projection;
- elliptic low-pass filtering used by Q9;
- future interface/surface-tension smoothing, curvature filtering or capillary
  pressure filtering.

No FFT path is used in the C++ branch at this stage. This is deliberate: the C++
operator is intended to evolve toward OpenMP/MPI/CUDA implementations with local
stencils, halo exchanges and Krylov/multigrid-style solvers.

## Operator validation

The generic elliptic operator has been validated independently of the particles
with manufactured solutions.

Periodic validation, representative result:

```text
grid                         : 64 x 48
alphaVariation               : 0.25
converged                    : true
iterations                   : 142
residualRel                  : 9.82e-13
divAfter/divBefore           : 9.82e-13
projectedFluxRms             : 2.93e-12
phiRmsErrorMeanFree          : 1.12e-13
```

Channel validation, representative result:

```text
bc                           : channel
grid                         : 64 x 48
alphaVariation               : 0.25
converged                    : true
iterations                   : 227
residualRel                  : 8.89e-13
divAfter/divBefore           : 8.90e-13
projectedFluxRms             : 1.72e-12
phiRmsErrorMeanFree          : 1.00e-13
```

The channel case means periodic in `x` and no-normal-flux walls in `y`.

## Q6 validation

### Periodic Taylor-Green

The high-SNR short Taylor-Green validation uses:

```text
Nx = Ny = 64
gamma = 80
U0 = 0.08
kBT = 0.01
dt = 0.001
tEnd = 0.5
```

Representative comparison:

```text
classic : amplitudeRatio = 0.30892, correlationEnd = 0.74187, divRmsEnd = 0.72171
q6      : amplitudeRatio = 0.31210, correlationEnd = 0.88407, divRmsEnd = 0.32245
```

Q6 preserves the Taylor-Green amplitude while improving the reconstructed field
correlation and reducing the post-processed divergence.

### Poiseuille channel

The long Poiseuille validation uses periodic `x`, solid-thermal walls in `y`,
and the channel elliptic operator.

Representative comparison at `tEnd = 50`:

```text
classic : fitR2 = 0.76987, nuEff = 0.11691, kBTEnd = 0.0099887
q6      : fitR2 = 0.85934, nuEff = 0.11091, kBTEnd = 0.0099121
```

A later run with the same channel/Q6 machinery gave:

```text
classic : fitR2 = 0.76987, nuEff = 0.11691
q6      : fitR2 = 0.79313, nuEff = 0.12044
```

The exact fit numbers depend on the analysis window and run instance, but the
stable conclusion is that Q6/channel projection is numerically stable, reduces
runtime divergence to `O(1e-10)`, and does not destroy the Poiseuille profile.

## Q9 validation

### MATLAB alignment

The C++ Q9 implementation is intended to stay as close as possible to the
validated MATLAB method. In particular, C++ Q9 must not correct cell-by-cell
high-frequency occupancy noise. The validated MATLAB strategy was a low-k /
elliptically filtered correction of coherent density/flux errors.

The current C++ Q9 therefore uses:

```text
q9DensityRelaxationBeta = 5.0e-4
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
q9EllipticLowPassPasses = 1
```

The low-pass filter is implemented in the generic `elliptic_projection` module,
not locally in the Q9 adapter.

### Periodic beta sweep

The filtered Q9 sweep showed stable thermal behavior and small correction
velocities. Representative tail values:

```text
q9TargetFilterRatioTailMean      ~ 0.0068 to 0.0084
q9CorrectionVelocityRmsTailMean  ~ 0.0021
q9CorrectionVelocityMaxEnd       ~ 0.011 to 0.017
kBT                              ~ 0.0098
```

The unfiltered sweep is intentionally retained as a negative diagnostic: it
shows that projecting raw cell-level density noise is unstable and not the
validated Q9 method.

### Taylor-Green with filtered Q9

Representative comparison:

```text
classic     : amplitudeRatio = 0.30892, correlationEnd = 0.74187
q6          : amplitudeRatio = 0.31210, correlationEnd = 0.88407
q9_filtered : amplitudeRatio = 0.44815, correlationEnd = 0.93010
```

Filtered Q9 does not degrade the coherent Taylor-Green vortex. In this short
high-SNR case it preserves the coherent mode better than Q6 alone.

### Poiseuille channel with filtered Q9

After the low-k mismatch fix described in
`docs/Q9_LOWK_FILTERING_INCIDENT.md`, the long channel run reaches `tEnd = 50`.
Representative comparison:

```text
classic     : fitR2 = 0.76987, nuEff = 0.11691, kBTEnd = 0.0099887
q6          : fitR2 = 0.79313, nuEff = 0.12044, kBTEnd = 0.0099031
q9_filtered : fitR2 = 0.79540, nuEff = 0.11631, kBTEnd = 0.0099081
```

The filtered low-k density diagnostic is the relevant density metric for Q9:

```text
filteredStdNTailMean q6          = 0.054823
filteredStdNTailMean q9_filtered = 0.048259
filteredStdNRelToQ6              = 0.88028
```

So filtered Q9 reduces the low-k density component by about 12% relative to Q6,
while keeping the Poiseuille profile, viscosity estimate, temperature and wall
reflection diagnostics stable.

## Current validation chain

The current validated chain is:

```text
compressible SRC/MPCD base
solid_thermal wall model
active domain and moving immersed solids
periodic elliptic projection core
channel elliptic projection core
Q6 periodic
Q6 periodic-x / wall-y channel
Q9 periodic with elliptic low-pass filtering
Q9 Taylor-Green filtered
Q9 Poiseuille channel filtered
```

## Next candidates

Recommended next steps:

1. piston/Q9 validation using the filtered low-k Q9 formulation;
2. longer or multi-seed Poiseuille/Taylor-Green checks if statistical confidence
   is needed;
3. eventual interface/surface-tension module, still using the same elliptic
   operator and low-pass machinery;
4. later inlet/outlet support, with both particle-level reservoir conditions and
   corresponding elliptic-projection boundary conditions.

# Periodic Q9 beta sweep validation

This protocol explores the effect of the Q9 density-relaxation parameter
`q9DensityRelaxationBeta` in a fully periodic box using the MATLAB-like
`elliptic_lowpass` target filter.

The goal is not yet to tune a final physical model. The goal is to identify the
range where the Q9 mass-flux projection begins to visibly affect occupancy
fluctuations while keeping thermal stability, global momentum correction and the
elliptic residual under control.

## Scope

Validated scope for this sweep:

```text
periodic x / periodic y
fixed box
no wall
no immersed solid
no active moving domain
no virial/EOS term
no surface tension
```

The implementation intentionally reuses the generic finite-volume elliptic core.
There is no FFT path.

## 1. Generate the initial state

From the `matlab/` directory:

```matlab
addpath('.')
generate_q9_beta_sweep_state();
```

This writes:

```text
../initial_state_q9_sweep_32x32_g20.smpcd
```

## 2. Run the baseline and Q9 sweep

From the repository root:

```bash
./build/src_mpcd_base examples/params_periodic_q6_for_q9_beta_sweep.kv
./build/src_mpcd_base examples/params_periodic_q9_beta_0p0005_filtered_sweep.kv
./build/src_mpcd_base examples/params_periodic_q9_beta_0p0010_filtered_sweep.kv
./build/src_mpcd_base examples/params_periodic_q9_beta_0p0020_filtered_sweep.kv
./build/src_mpcd_base examples/params_periodic_q9_beta_0p0050_filtered_sweep.kv
./build/src_mpcd_base examples/params_periodic_q9_beta_0p0100_filtered_sweep.kv
```

Each run uses:

```text
Nx = Ny = 32
gamma = 20
dt = 0.001
nSteps = 5000
tEnd = 5
summaryEvery = 50
dumpStateEvery = 0
```

## 3. Analyze

From the `matlab/` directory:

```matlab
addpath('.')
out = validate_q9_beta_sweep('makePlots', true);
```

The default directories are `../runs/...`, so the script is intended to be run
from `matlab/`.

## Diagnostics to inspect

The most useful columns are:

```text
stdNTailMean
stdNTailRelToQ6
q9ResidualTailMedian
q9DensityStdRatioTailMean
q9CorrectionVelocityRmsTailMean
q9CorrectionVelocityMaxEnd
kBTTailMean
q9TargetFilterRatioEnd
```

For Q9, `q9MassFluxDivAfterRms` is not expected to be close to zero when
`q9DensityRelaxationBeta > 0`; it should follow the non-zero relaxation target.
The elliptic solve quality is measured by `q9ResidualRel`, and the immediate
per-step density-relaxation estimate is measured by
`q9DensityStdRatioEstimate`.

## Expected qualitative trend

The target filter changes the interpretation of the per-step estimate. It is no
longer expected to reduce the total cell-scale `std(N)` by exactly `1-beta`,
because only the filtered large-scale component of the density fluctuation is
relaxed. The useful regime is the one where occupancy statistics improve without
visible thermal drift or excessive correction velocity.

# Periodic Q9 mass-flux projection adapter

This document describes the first Q9 adapter built on top of the generic
elliptic face-field projection core.

The adapter is intentionally minimal and is validated first in a fully periodic
box. It does not introduce a FFT path. It reuses the same finite-volume
matrix-free elliptic core as Q6.

## Discrete form

The generic projection core solves

```text
F_new = F_base - alpha grad(phi)
div(F_new) = target
```

For Q6, `F_base` is a velocity face field and `target = 0`.

For this first Q9 adapter, `F_base` is a cell-owned mass/momentum flux:

```text
J_base = M_cell U_cell = cell momentum
```

and the target divergence is a uniform-density relaxation target:

```text
target = beta / dt * (M_cell - mean(M_cell))
```

Using the discrete continuity interpretation

```text
M_new = M_old - dt div(J_new)
```

this gives the estimate

```text
M_new ~= M_old - beta * (M_old - mean(M))
```

when the correction is applied with strength one.

## Parameters

Minimal periodic Q9 parameters:

```text
method = q9
projectionOperator = periodic_fv_cg
projectionMaxIterations = 300
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true

q9MassFluxProjectionEnable = true
q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta = 0.002
q9MomentumCorrectionEnable = true
```

`method = q9` enables both the Q6 velocity projection and the Q9 mass-flux
projection. This mirrors the intended hierarchy: Q9 is Q6 plus a mass-flux
relaxation stage.

## Scope of the first validation

The first validated scope is:

```text
periodic x / periodic y
fixed box
no immersed solid
no active moving domain
no virial/EOS term
no surface tension
```

The code path remains compact and does not add extra defensive runtime guards.
Other configurations should be introduced through dedicated validation cases.

## Smoke test

From the `matlab/` directory, generate the initial state:

```matlab
addpath('.')
generate_q9_periodic_smoke_state();
```

From the repository root, run the Q6 and Q9 comparison cases:

```bash
./build/src_mpcd_base examples/params_periodic_q6_for_q9_smoke.kv
./build/src_mpcd_base examples/params_periodic_q9_smoke.kv
```

From the `matlab/` directory, analyze the run:

```matlab
addpath('.')
out = validate_q9_periodic_smoke('makePlots', true);
```

## Diagnostics

The runtime summary includes Q9-specific columns:

```text
q9Applied
q9Converged
q9Iterations
q9ResidualRel
q9MassFluxDivBeforeRms
q9MassFluxDivAfterRms
q9TargetDivergenceRms
q9DensityStdBefore
q9DensityStdAfterEstimate
q9DensityStdRatioEstimate
q9CorrectionVelocityRms
q9MomentumResidualBeforeCorrection
```

For Q9, `q9MassFluxDivAfterRms` is not expected to be near zero when
`q9DensityRelaxationBeta > 0`; it should match the non-zero relaxation target.
The elliptic solve quality is measured by `q9ResidualRel`, and the immediate
mass-homogenization estimate is measured by `q9DensityStdRatioEstimate`.

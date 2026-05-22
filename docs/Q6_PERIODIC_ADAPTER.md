# Periodic Q6 adapter

This module is the first physical adapter using the generic elliptic projection
core. It is intentionally thin and minimal.

The adapter performs:

```text
particles -> cell-centered mass-weighted velocity U*
cell U*   -> periodic face field F* using the first Q6 cell-owned face convention
EllipticProjectionCore(F*, alpha=1, target=0)
face correction -> nearest-cell particle velocity correction
exact global momentum correction
```

In equations, the elliptic core solves

```text
-div(grad phi) = -div(F*)
F_projected    = F* - grad(phi)
```

so that, at the face-field level,

```text
div(F_projected) ~= 0.
```

## Parameters

```text
method = q6
projectionOperator = periodic_fv_cg
projectionMaxIterations = 300
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
```

`method = q6` enables the projection. The lower-level key
`projectionEnable = true` is also accepted.

## Documented validation scope

The first adapter is validated for fully periodic fixed boxes:

```text
bcX = periodic
bcY = periodic
fluid domain = full numerical box
no immersed solid
```

The code does not add runtime guards for this scope. This is deliberate: the
current policy is to keep the C++ runtime minimal and to document what has been
validated rather than overloading the core with defensive restrictions.

Parietal, immersed-solid, active-domain, inlet/outlet, Q9 and surface-tension
couplings should be added through the same elliptic core once their discrete
boundary/interface treatment is specified.

## Runtime diagnostics

`summary_runtime.csv` receives the following Q6 columns:

```text
q6Applied
q6Converged
q6Iterations
q6EmptyCells
q6ResidualRel
q6DivBeforeRms
q6DivBeforeMaxAbs
q6DivAfterProjectedFluxRms
q6DivAfterProjectedFluxMaxAbs
q6DivAfterCellVelocityRms
q6DivAfterCellVelocityMaxAbs
q6CorrectionVelocityRms
q6CorrectionVelocityMaxAbs
q6MomentumCorrectionVx
q6MomentumCorrectionVy
q6MomentumResidualBeforeCorrection
```

The most important first checks are:

```text
q6Applied = 1
q6Converged = 1
q6ResidualRel small
q6DivAfterProjectedFluxRms << q6DivBeforeRms
mass conserved
momentum conserved after the exact global correction
```

The smoke example keeps the mass-aware relative thermostat enabled, because a
strict velocity projection continuously removes compressive kinetic energy from
the microscopic velocity field. For diagnostic runs without thermostat, a strong
thermal decay is therefore expected and should not by itself be interpreted as a
mass or momentum conservation error.

`q6DivAfterProjectedFluxRms` is the divergence of the face field returned by the
elliptic core. `q6DivAfterCellVelocityRms` is the divergence obtained after
mapping the face correction back to the cell-owned Q6 velocity components. In
this first periodic adapter, both use the same discrete div/grad convention and
should therefore be of the same order.

## Smoke example

Generate an initial periodic state:

```matlab
addpath('matlab')

generate_smpcd_state_uniform( ...
    'output', 'initial_state_q6_32x32_g20.smpcd', ...
    'Lx', 1.0, ...
    'Ly', 1.0, ...
    'Nx', 32, ...
    'Ny', 32, ...
    'gamma', 20, ...
    'kBT', 0.01, ...
    'mass', 1.0, ...
    'type', 0, ...
    'seed', 12345);
```

Then run:

```bash
./build/src_mpcd_base examples/params_periodic_q6_smoke.kv
```

A compact MATLAB diagnostic is available:

```matlab
addpath('matlab')
plot_q6_projection_summary('runs/periodic_q6_smoke')
```

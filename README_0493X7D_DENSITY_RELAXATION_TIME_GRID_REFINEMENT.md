# 0493x7d — physical density-relaxation time and first grid refinement

0493x7d consolidates the successful 0493x7c Q6 density-RHS mechanism without
changing its operator.  The preferred physical input is now the relaxation time
`q6DensityRelaxationTime = tau`, for which

```
div(u_projected) = (rawFill - 1) / tau
betaPerStep = dt / tau
```

The old `q6DensityRelaxationBeta` remains available as a backward-compatible
per-step input.  Positive `time` and positive `beta` are mutually exclusive.
Validation checks the effective `dt/tau`; the host Q6 entry resolves that value
before launching the existing x7c kernels, so the CUDA RHS operator itself is unchanged.

The qualified 300x150 case used `dt=0.005`, `beta=0.02`, hence `tau=0.25`.
At `dt=0.0025`, keeping the same `tau=0.25` gives `betaPerStep=0.01`
automatically.

The Q6 audit now writes both the effective beta and effective relaxation time.
The x5a/x5b runners accept `Q6_DENSITY_RELAXATION_TIME` and log the resolved
`tau` and `betaPerStep`.

## Refinement runner

A short paired operator-scaling test is provided by

```
LIVE_PROGRESS=1 bash scripts/run_0493x7d_density_rhs_grid_refinement.sh
```

Defaults are 100 steps at 300x150, `dt=0.005`, and 200 steps at 600x300,
`dt=0.0025`, so both reach the same physical time.  Both use `tau=0.25`.
Set `COARSE_STEPS=500` for the longer 500/1000-step comparison.

This is deliberately an operator/refinement diagnostic, not by itself a proof
of full MPCD continuum convergence.  Keeping gamma fixed while changing cell
size and timestep can also change transport coefficients.  The first question
here is narrower: whether the density-RHS semantics and normalized volume
response remain controlled when `dt` and grid spacing are refined together.

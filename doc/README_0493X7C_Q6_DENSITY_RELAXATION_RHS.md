# 0493x7c — Q6 density-relaxation RHS

This patch moves density restoration into the CUDA-resident Q6 projection rather
than applying the x7b explicit virial velocity kick after projection.

For the liquid bulk only, the projection target becomes

    div(u_projected) = beta_rho * (rawFill - 1) / dt

where `rawFill` is the unbounded x6c liquid mass fill.  The sign follows the
continuity equation: an overfilled cell (`rawFill > 1`) receives positive target
divergence and expands; an underfilled bulk cell receives negative divergence.
The interface band itself keeps the ordinary x6f free-surface pressure treatment.

Parameter:

    q6DensityRelaxationBeta = 0.0

`beta=0` is an exact no-op.  `beta` is dimensionless and does not scale with
`Nx/Ny`.  The x7c path is intentionally limited to the already-qualified
x6c+x6f free-surface, fused-force, B1, single-projected-liquid subset.  The x7b
explicit virial kick and x7c density RHS are mutually exclusive.

The existing `divAfterProjectedFaceFluxRms` audit becomes the residual to the
active divergence constraint.  At `beta=0` that constraint is zero and the
column has exactly its historical meaning.  Two columns are appended to
`cuda_species_q6_independent_masked_0493w5.csv`:

- `q6DensityRelaxationBeta`
- `densityRelaxationTargetDivRms`

`q6Applied` remains the actual post-particle-application cell divergence; this is
intentional because the x7c target is non-zero.

The runner override is:

    Q6_DENSITY_RELAXATION_BETA=<value>

Use `VIRIAL_DENSITY_KICK_ENABLE=false` for x7c qualification.

# Patch 0123 — resampling particle-mass guard

This patch adds the first bounded particle-mass safety layer to the OpenMP
weighted-resampling branch.  It is disabled by default and therefore leaves the
SRC/Q6 baseline and all previous smoke tests unchanged.

## Parameters

```text
resamplingMassGuardEnable = false
resamplingParticleMassMin = 0.25
resamplingParticleMassMax = 4.0
```

Aliases accepted by the parser:

```text
resamplingMassSafetyEnable
resamplingMassMin
resamplingMassMax
```

The guard currently requires `resamplingRemapEnable=true`, because it is meant
as a local post-remap safety stage.

## Algorithm

For each non-empty wet cell, the guard checks feasibility:

```text
N_c m_min <= M_target <= N_c m_max
```

If feasible, it projects the current masses onto the bounded simplex

```text
m_min <= m_p <= m_max,
Σ_p m_p = M_target.
```

The implementation uses the additive Lagrange multiplier form

```text
m_p,new = clamp(m_p,old + λ, m_min, m_max)
```

with a deterministic bisection on `λ`.  This is a bounded redistribution, not a
plain clamp: the cell mass target is preserved whenever the bounds allow it.

After the mass projection, velocities are transformed as

```text
v_p <- U_target + α (v_p - U_current)
```

where `U_target` and the target relative thermal energy are measured before the
mass projection.  This restores local `M_c`, `U_c` and `E_th,c` up to roundoff.

## What is deliberately not done yet

The patch does not implement adaptive bound relaxation, species-dependent
bounds, latent wetting, or stochastic replacement.  Infeasible cells are skipped
and diagnosed explicitly.

## Validation

Run:

```bash
./scripts/run_resampling_mass_guard_smoke_0123.sh
```

Expected outcome:

```text
[0123 resampling mass guard smoke] OK
```

The smoke constructs cells with masses both below and above the requested bounds,
then verifies:

```text
resampMassGuardParticlesBelowMinBefore > 0
resampMassGuardParticlesAboveMaxBefore > 0
resampMassGuardParticlesBelowMinAfter  = 0
resampMassGuardParticlesAboveMaxAfter  = 0
resampMRelRms                          ~ roundoff
resampMassGuardMomentumResidualRms     ~ roundoff
resampMassGuardThermalEnergyResidualRms~ roundoff
```

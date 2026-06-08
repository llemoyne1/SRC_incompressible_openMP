# 0296 — Post-SRC CUDA mass reconditioning without support change

## Purpose

Patch 0296 introduces the first mutating CUDA brick of the resampling chantier, but it is deliberately **not** a population guard.  It performs a conservative, local reconditioning of particle masses after the validated SRC classic step has produced the fluid state.

The physical interpretation is unchanged from the 0294/0295 audit:

```text
SRC classic produces the fluid state.
Resampling/support-control only maintains the statistical particle representation.
```

Therefore 0296 is inserted after SRC classic and after the optional CPU closure stages that may be re-enabled later, at the same physical non-shifted-grid location as the validated MATLAB/OpenMP resampling sequence.

## What 0296 does

For every wet physical cell with at least two fluid particles, the CUDA operator computes the pre-reconditioning cell moments on the non-shifted grid:

```text
M_c = sum_i m_i
P_c = sum_i m_i v_i
```

It then moves each particle mass toward the local cell average mass:

```text
m_i' = m_i + strength * (M_c / N_c - m_i),    0 <= strength <= 1
```

Because the target is the cell average, the cell mass is conserved analytically when no particle is skipped:

```text
sum_i m_i' = M_c
```

The operator then applies a uniform velocity correction in the same cell to restore the pre-reconditioning momentum:

```text
v_i' = v_i - DeltaP_c / M_c
```

where `DeltaP_c` is the momentum change caused by the mass reconditioning before the velocity correction.

## What 0296 does not do

0296 does **not**:

```text
create particles
remove particles
activate Inactive particles
extract Fluid particles
change Fluid/Inactive/Latent roles
inject mass into solid or wall regions
perform Q6
perform population support repair
act as a hidden thermostat
```

The later population-support step remains 0297.  Thermal/energy restoration after support mutation remains 0298.

## Runtime switches

The operator is disabled by default and is controlled only by environment variables:

```bash
MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=1
MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY=10
MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH=1.0
```

The first implementation applies only when the shared CUDA particle state is explicitly fresh.  If the state is not fresh, the operator records a CSV row with `skippedBecauseStateNotFresh=1` and does not upload a stale host mirror.  This preserves the 0295 non-mutation lesson and avoids corrupting resident CUDA cases.

## Diagnostics

Each enabled run writes:

```text
<outputDir>/cuda_resampling_mass_recondition_0296.csv
```

The CSV reports, among other fields:

```text
fluidParticlesBefore / fluidParticlesAfter
wetCellsBefore / wetCellsAfter
appliedParticles / appliedCells
totalMassBefore / totalMassAfter
totalPxBefore / totalPxAfter
totalPyBefore / totalPyAfter
maxAbsCellMassError / maxRelCellMassError
maxAbsCellMomentumError / maxRelCellMomentumError
```

These diagnostics are intentionally general and light.  Case-specific interpretation remains in post-processing.

## Validation scope

The strict short validation uses the same four bit-reproducible witnesses retained for 0295:

```text
TG periodic
Poiseuille wall
backward step / rectangle
segmented U-box inlet/outlet
```

The validation runner compares mass-reconditioning OFF vs ON.  On the standard uniform-mass initial states, 0296 should produce CSV rows but no physical change in the summaries.

Von Kármán remains optional because the thermostat-enabled VK case is not OFF/OFF bit-reproducible.  It can be run with the thermostat disabled for a strict diagnostic, as in 0295.

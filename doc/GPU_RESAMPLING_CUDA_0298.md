# GPU resampling CUDA 0298 — post-SRC moment/energy restoration

## Purpose

Patch 0298 extends the local post-SRC CUDA population guard introduced in 0297 with a conservative
cell-relative kinetic-energy diagnostic and an optional restoration pass.

The physical convention remains unchanged:

```text
SRC classic CUDA produces the physical particle state.
Resampling/support-control is a post-SRC remeshing of representative particles.
It must preserve the field already produced by SRC rather than create a new one.
```

0297 already performs local split/merge operations that conserve mass and momentum by construction.
However, a merge of two particles into one generally removes relative kinetic energy in that cell.
0298 closes this gap by measuring, and optionally restoring, the cell-relative kinetic energy
`K_rel` after a support mutation.

## Insertion point

The insertion point is still the validated post-SRC physical-grid location:

```text
streaming / boundary conditions / SRC collision / thermostat
-> optional survey 0295
-> optional mass reconditioning 0296
-> local population guard 0297
-> 0298 relative-energy restoration when enabled
```

No Q6 CUDA path is introduced.  Q6 CPU/OpenMP remains a future-compatible handoff outside this patch.

## Algorithm

For each application of the population guard, 0298 computes the pre-mutation target

```text
K_rel,c = 1/2 sum_i m_i |v_i - U_c|^2
```

on the physical, non-shifted cell grid.

After split/merge mutation, the same quantity is recomputed.  If restoration is enabled with

```bash
MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298=1
```

then velocities in each cell are rescaled around the post-mutation cell mean velocity:

```text
v_i <- U_c + s_c (v_i - U_c)
s_c = sqrt(K_rel,target,c / K_rel,current,c)
```

with a safety cap:

```bash
MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE=4.0
```

Because the rescaling is around the cell mean velocity, cell momentum is preserved up to floating-point
roundoff.  Mass and support changes remain those of 0297.

## Diagnostics

The existing file

```text
cuda_resampling_population_guard_0297.csv
```

is extended with 0298 columns:

```text
momentRestoreRequested0298
energyRestoreApplied0298
energyRestoreParticleUpdates0298
energyRestoreSkippedParticles0298
energyRestoreMaxScale0298
totalKrelBefore0298
totalKrelAfterPreRestore0298
totalKrelAfter0298
maxAbsCellKrelErrorPreRestore0298
maxRelCellKrelErrorPreRestore0298
maxAbsCellKrelError0298
maxRelCellKrelError0298
```

The pre-restore columns quantify the thermal effect of split/merge itself.  The final columns quantify
the remaining error after the optional restoration pass.

## Validation strategy

Default validation remains non-triggering:

```text
NMIN=0
NMAX=0
```

This checks that the 0298 diagnostic/restoration code path is callable and non-perturbing when no
support mutation is requested.

Active tests are controlled experiments and should be interpreted through the diagnostic budgets rather
than strict OFF/ON equality, because an active population guard intentionally changes the particle
representation.


## Runtime switches

```bash
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298=1
MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE=4.0
MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MIN_CURRENT_KREL=1e-30
MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_ABS_TOL=1e-14
MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_REL_TOL=1e-12
```

The tolerance switches prevent microscopic roundoff-only differences from causing unnecessary velocity
rescaling in cells whose relative energy was not materially affected by the support mutation.

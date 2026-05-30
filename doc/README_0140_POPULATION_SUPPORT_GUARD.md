# 0140 — MATLAB-compatible population-support guard for weighted resampling

This patch restores the central MATLAB resampling mechanism in the OpenMP branch:
cell decisions are now allowed to use the active particle population support `N_c`,
not only the weighted cell mass `M_c`.

The new stage is gated by:

```kv
resamplingPopulationGuardEnable = true
resamplingPopulationNMin = 14
resamplingPopulationNTarget = 20
resamplingPopulationNMax = 26
```

When enabled, it runs every resampling step, before the previous mass-driven
transfer plan and before mass renormalisation:

- `N_c < NMin` and `N_c > 0`: split local heavy Fluid particles into inactive
  slots until `NTarget` is reached, subject to per-cell/per-step limits.
- `N_c > NMax`: merge-extract excess Fluid particles to Inactive until
  `NTarget` is reached, subject to per-cell/per-step limits.
- `N_c = 0`: the guard reports the empty underfilled wet cell but does not seed
  it by itself. Empty wet/dry front seeding remains the role of inlet, latent
  activation, or an explicit wet-front mechanism.

The split and merge-extract operations are local and conservative at cell level:

- split: `m -> m/2 + m/2`, same velocity, same position, new slot from Inactive;
- merge-extract: a light particle is merged into a heavy survivor and the light
  slot becomes Inactive, conserving local mass and momentum.

The implementation deliberately avoids global donor×receiver matching.  It uses
an existing compact CSR-style cell-particle index (`cellParticleOffsets`,
`cellParticleIndices`), so the stage is suitable for OpenMP optimisation later
without introducing `vector<vector<...>>` allocation patterns or global sorts.

The mass remap / mass guard cadence remains controlled separately by:

```kv
resamplingMassRenormalizationPeriod = K
```

The new population guard is therefore the discrete support-control stage, while
mass remapping remains the continuous weighted-mass correction.

New runtime diagnostics include:

```text
resampPopulationGuardAttempted
resampPopulationGuardApplied
resampPopulationGuardNMin/NTarget/NMax
resampPopulationGuardUnderfullCells
resampPopulationGuardOverfullCells
resampPopulationGuardCellsSplit
resampPopulationGuardCellsExtracted
resampPopulationGuardSplitParticlesCreated
resampPopulationGuardExtractedParticles
resampPopulationGuardWetNMinBefore/After
resampPopulationGuardWetLowNFractionBefore/After
```

Several existing validation launchers now enable the population guard in the
`q6_resampling` case by default.  It can be disabled without editing scripts:

```bash
RESAMP_POP_GUARD_ENABLE=false ./scripts/run_open_channel_rect_obstacle_resampling_validation_0138b.sh
```

Recommended first regression checks:

```bash
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection

ORECT_STEPS=1000 ORECT_DUMP_EVERY=250 ORECT_SUMMARY_EVERY=10 \
  ./scripts/run_open_channel_rect_obstacle_resampling_validation_0138b.sh

FILL_STEPS=1000 FILL_DUMP_EVERY=100 FILL_SUMMARY_EVERY=10 \
  ./scripts/run_injection_fill_resampling_validation_0139.sh
```

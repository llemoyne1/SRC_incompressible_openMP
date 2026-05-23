# Backward-step coherence diagnostics

This note documents the post-processing diagnostics added to distinguish
coherent separated structures from high-frequency SRC/MPCD noise in the
periodic forced backward-step runs.

The diagnostics are MATLAB-only and can be applied retroactively to existing
classic, masked-Q6 and masked-Q9 runs as long as the dumped `.smpcd` frames are
still present.

## Motivation

The scalar `omegaRmsDownstream` used by the earlier validators is now kept as a
backward-compatible alias for the RMS of the *time-averaged* downstream
vorticity field. It is useful, but it does not by itself quantify the temporal
noise level. A classic compressible run can show stronger vorticity while being
less organized, whereas Q6/Q9 can show lower amplitude but higher coherence.

The updated validator therefore separates the vorticity signal into:

- a coherent part, `mean_t omega`;
- a temporal fluctuation part, `omega - mean_t omega`;
- persistence of reversed streamwise velocity, `P(Ux < 0)`.

## New per-run table columns

`validate_backward_step_classic_long` now adds these columns to
`backward_step_classic_long_summary.csv` and to suite-level summaries:

- `omegaTotalRmsDownstream`: RMS based on `<omega^2>_t` in the downstream
  lower layer.
- `omegaFluctRmsDownstream`: RMS of temporal fluctuations around the mean
  vorticity field.
- `omegaCoherenceRatioDownstream`: `omegaCoherentRmsDownstream /
  omegaTotalRmsDownstream`. The existing `omegaRmsDownstream` is the coherent
  RMS.
- `omegaFluctToCoherentRatioDownstream`: temporal fluctuation RMS divided by
  coherent RMS.
- `omegaMeanLowKFractionDownstream`: fraction of the mean-vorticity spectral
  energy contained in low spatial modes of the downstream window.
- `uxReversePersistenceMeanDownstream`: spatial average of `P(Ux < 0)`.
- `uxReversePersistenceMaxDownstream`: maximum of `P(Ux < 0)`.
- `reversedLargestComponentFraction`: fraction of cells with mean `Ux < 0` that
  belong to the largest connected reversed component.
- `reversedComponentCount`: number of connected reversed components in the
  mean field.

## New field output

For each run, the validator writes:

```text
backward_step_coherence_fields.csv
```

with per-cell fields:

- `omegaTemporalRms`
- `omegaFluctRms`
- `omegaCoherenceCellRatio`
- `uxReverseProbability`

## Re-analyzing existing classic/Q6/Q9 runs

From the repository root:

```matlab
cd matlab
suite = validate_backward_step_masked_structure_suite();
```

This reprocesses the existing 30000-step classic/Q6/Q9 dumped frames and writes
updated tables and figures to:

```text
runs/backward_step_masked_structure_suite_analysis/
```

The additional figure is:

```text
backward_step_masked_structure_suite_coherence.png
```

For the parametric suite, use:

```matlab
cd matlab
suite = validate_backward_step_parametric_suite();
```

which also writes:

```text
backward_step_parametric_suite_coherence_metrics.png
```

## Interpretation

Useful qualitative patterns are:

- high `omegaTotalRmsDownstream` but low `omegaCoherenceRatioDownstream`:
  intense vorticity dominated by temporal fluctuations/noise;
- lower total RMS but higher coherence ratio and compact reversed component:
  smoother but more organized recirculation;
- high `reversedComponentCount` and low `reversedLargestComponentFraction`:
  fragmented reversed patches rather than a coherent bubble;
- high `uxReversePersistenceMaxDownstream`: at least one persistent reversed
  region exists during the averaging window.

## Population reliability companion diagnostics

The coherence metrics should be interpreted together with the population
reliability diagnostics documented in
`docs/BACKWARD_STEP_POPULATION_RELIABILITY_DIAGNOSTICS.md`. In particular,
apparent high vorticity in the classic particle run can be misleading if it is
associated with low-population cells in the separated region. The companion
metrics report downstream and recirculation population tails such as
`populationP05ReversedOverReference`,
`populationLowHalfRefFractionReversed`, and
`populationBelow5FractionReversed`.

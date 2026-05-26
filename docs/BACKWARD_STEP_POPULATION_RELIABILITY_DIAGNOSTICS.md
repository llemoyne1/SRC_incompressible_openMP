# Backward-step population reliability diagnostics

This document extends the backward-step coherence diagnostics with cell-population
statistics. The motivation is methodological: in particle methods, apparent
vorticity and recirculation can be dominated by cells with weak statistical
support. A method that keeps the population field better conditioned can be more
credible even if it reduces high-frequency vorticity amplitude.

The diagnostics are MATLAB post-processing only. They do not change the C++
solver or any run configuration.

## Cell-population reference

For each run, the post-processing computes a fluid reference population

```text
populationReferenceNFluid = mean(mean N over non-solid fluid cells)
```

This is preferred over a nominal `gamma` parameter for the immersed-step cases,
because the initial state excludes real particles from the rectangle while
keeping the total number of particles fixed. The fluid-cell mean population can
therefore differ from the nominal generator value.

## Scalar diagnostics

The per-run summary tables now include, in addition to the existing runtime
`stdNLate`, the following cell-field statistics:

```text
populationReferenceNFluid
populationMeanFluid
populationCvFluid
populationMinFluid
populationP05Fluid
populationP05FluidOverReference
populationLowHalfRefFractionFluid
populationBelow5FractionFluid
```

and the same type of quantities restricted to the downstream separated region:

```text
populationMeanDownstream
populationCvDownstream
populationMinDownstream
populationP05Downstream
populationP05DownstreamOverReference
populationLowHalfRefFractionDownstream
populationLowQuarterRefFractionDownstream
populationBelow5FractionDownstream
populationBelow10FractionDownstream
populationTemporalStdMeanDownstream
populationTemporalCvMeanDownstream
```

For the recirculating part of the downstream region, defined from the mean field
as `Ux < 0`, the summary also reports:

```text
populationMeanReversed
populationMinReversed
populationP05Reversed
populationP05ReversedOverReference
populationLowHalfRefFractionReversed
populationBelow5FractionReversed
populationTemporalCvMeanReversed
```

These columns are intended to answer whether a method is generating coherent
structures in statistically populated cells, or whether the apparent classic
vorticity is concentrated in low-population/noisy regions.

## Field outputs

For every analyzed run, the validator writes

```text
backward_step_population_fields.csv
```

with the columns

```text
x, y, NMean, NTemporalStd, NTemporalCv
```

where `NTemporalStd` and `NTemporalCv` are computed over the averaged dump
frames.

## Figures

The single-run validator adds a figure named

```text
Backward-step population reliability diagnostics
```

with maps of mean population, relative population, temporal `std(N)`, and
temporal `CV(N)`.

The classic/Q6/Q9 suite writes

```text
backward_step_masked_structure_suite_population.png
```

The parametric suite writes

```text
backward_step_parametric_suite_population_metrics.png
```

## Recommended reading

The main quantities to compare across classic/Q6/Q9 are:

```text
populationP05DownstreamOverReference
populationLowHalfRefFractionDownstream
populationTemporalCvMeanDownstream
populationP05ReversedOverReference
populationLowHalfRefFractionReversed
populationBelow5FractionReversed
```

A useful quasi-incompressible setting should preserve organized recirculation
and low-k vorticity while avoiding under-populated cells in the separated region.
If the classic case has larger total vorticity but also lower population tails
or more low-population recirculation cells, that vorticity should be interpreted
with caution.

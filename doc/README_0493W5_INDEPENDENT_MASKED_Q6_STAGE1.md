# 0493w5 — Independent masked species Q6, stage 1

## Purpose

The legacy `speciesQ6Mode=weighted` remains a barycentric mixture projection: one
mixture correction is redistributed between species and `fallback=common` can
therefore project a species whose declared Q6 strength is zero.  That operator
is retained unchanged for reproducibility, but it is not the target model for a
compressible gas coupled to an incompressible liquid.

Stage 1 adds:

```text
speciesQ6Mode = independent_masked
speciesQ6MinOccupancyFraction = 0.5
```

Its strict contract is:

```text
q6StrengthDeclared == 0  =>  no direct Q6 correction for that species
q6StrengthDeclared > 0   =>  a distinct masked Q6 solve for that species
```

No barycentric redistribution and no `fallback=common` are used in this mode.

## Occupancy support

For species `s` in cell `c`, the support proxy is

```text
w_s,c   = mass_s,c / referenceCellMass_s
phi_s,c = w_s,c / sum_r(w_r,c)
```

The raw mass fraction is deliberately not used: at a large liquid/gas density
ratio it would classify a cell containing a small liquid volume as liquid.
The species Q6 support is

```text
mask_s,c = (q6Strength_s > 0) && (mass_s,c > 0)
           && (phi_s,c >= speciesQ6MinOccupancyFraction)
```

The threshold is a runtime parameter.  The initial value `0.5` is a test value,
not a calibrated atomisation model.

## Stage-1 operator

For each enabled species, sequentially but from the same pre-Q6 particle state:

1. deposit its cell mass and momentum;
2. build its occupancy mask;
3. build a divergence RHS from its own cell velocity;
4. solve a masked Poisson system;
5. store that species correction;
6. after every solve has succeeded, apply each stored correction only to
   particles of the matching species.

Inactive cells are assigned correction pressure `phi=0`.  This gives a simple
Dirichlet boundary for the correction pressure at a species/gas interface.
Disconnected supports therefore form independent matrix blocks without an
explicit connected-component search.

All species solves are completed before any particle correction is applied.
This avoids order dependence when several species are declared incompressible
and prevents a partial state update if a later solve fails.

The legacy all-particle uniform momentum correction is not applied.  It would
modify species declared compressible.  The masked Dirichlet interface may exert
a net pressure impulse on the projected species; this impulse is reported.

## Deliberate stage-1 scope

The new mode is initially accepted only for a fully periodic `x/y` domain.
The following are deliberately deferred:

- open and segmented boundaries;
- wall, Darcy and immersed-solid topology;
- moving domains;
- resampling during the qualification run;
- hysteresis or temporal filtering of the occupancy mask;
- a physical gas-pressure or surface-tension interface condition.

`common` and `weighted` keep their existing code path and CSV schema.

## Diagnostics

A new file is written when the mode is active:

```text
cuda_species_q6_independent_masked_0493w5.csv
```

It reports, per species and step:

- declared strength and occupancy threshold;
- active cells and full-domain status;
- corrected particle count;
- convergence, iterations and residual;
- divergence before and after the masked projection;
- correction RMS/max;
- total direct Q6 momentum applied to the species.

The barycentric residual fields in the generic summary are zeroed because that
legacy invariant is not applicable to independent solves.

## Ad-hoc validation

CPU contract test:

```bash
bash scripts/run_0491a_species_q6_cpu_reference.sh
```

CUDA periodic smoke after rebuilding the livevis CUDA binary:

```bash
LIVE_PROGRESS=1 bash scripts/run_0493w5_independent_masked_periodic_smoke.sh
```

The smoke covers:

- `full`: monoespecies full-domain projection;
- `islands`: two disconnected projected liquid rectangles in compressible gas;
- `mixed60`: liquid occupancy `0.6`, above the `0.5` threshold;
- `mixed40`: liquid occupancy `0.4`, below the threshold.

It requires strong divergence reduction for active liquid support and requires
zero active cells and zero directly corrected particles for the gas whose Q6
strength is zero.

## Qualification meaning

This patch establishes operator selectivity and disconnected-support handling.
It does not yet establish the physically correct liquid/gas interface pressure
condition.  The next qualification step is to compare the full-domain result
against legacy monoespecies Q6, then exercise static planar and disconnected
supports before extending the operator to the segmented injection runner.

# 0144 — Explicit projection/resampling switches

Patch 0144 removes the historical `method=classic/q6` selector from the active
OpenMP resampling branch.  The selector had become redundant with
`projectionEnable` and could create contradictory configurations, for example
`method=q6` together with `projectionEnable=false`.

The active branch now uses two explicit top-level switches:

```text
projectionEnable = true|false
resamplingEnable = true|false
```

This gives four unambiguous modes:

| Label | projectionEnable | resamplingEnable | Interpretation |
|---|---:|---:|---|
| `classic` | false | false | Pure SRC/MPCD baseline. |
| `classic_resampling` | false | true | SRC/MPCD with numerical population-support guard, no incompressible projection. |
| `q6` | true | false | SRC/MPCD with Q6 velocity projection, no weighted resampling. |
| `q6_resampling` | true | true | Q6 plus population-driven weighted resampling. |

## Removed parameters

The following keys are intentionally no longer accepted by the parser:

```text
method
resamplingPopulationGuardEnable
resamplingNGuardEnable
resamplingSupportGuardEnable
```

This is deliberate: old scripts should fail loudly instead of silently selecting
a different physical mode.

## Resampling semantics

`resamplingEnable=true` now means that the population-driven weighted-resampling
chain is active.  The support guard is configured by the population band:

```text
resamplingPopulationNMin = 14
resamplingPopulationNTarget = 20
resamplingPopulationNMax = 26
```

Valid configurations are either:

```text
resamplingPopulationNMin > 0
resamplingPopulationNTarget > 0
resamplingPopulationNMax > 0
resamplingPopulationNMin < resamplingPopulationNTarget < resamplingPopulationNMax
```

or the inferred-default form:

```text
resamplingPopulationNMin = 0
resamplingPopulationNTarget = 0
resamplingPopulationNMax = 0
```

Partial zero/nonzero bands are rejected.

The existing technical controls remain available:

```text
resamplingExtractionEnable
resamplingInsertionEnable
resamplingRemapEnable
resamplingMassRenormalizationPeriod
resamplingThermalRenormalizationEnable
resamplingMassGuardEnable
resamplingParticleMassMin
resamplingParticleMassMax
```

These controls tune the mass/momentum/thermal stabilization associated with the
population guard; they no longer decide whether the population support guard is
present.

## Updated validation scripts

The current resampling validation launchers now write `projectionEnable` and
`resamplingEnable` directly and no longer emit `method` or
`resamplingPopulationGuardEnable`.  The main scripts run the four ablation cases:

```text
classic
classic_resampling
q6
q6_resampling
```

Representative scripts:

```bash
bash scripts/run_taylor_green_forced_random_population_resampling_validation_0130.sh
bash scripts/run_poiseuille_wallvp_resampling_validation_0131.sh
bash scripts/run_same_face_segmented_io_validation_0143.sh
```

For a short same-face inlet/outlet smoke test, for example:

```bash
RUN_ROOT=/tmp/src0144_segio \
SEGIO_STEPS=5 \
SEGIO_SUMMARY_EVERY=1 \
SEGIO_DUMP_EVERY=0 \
SEGIO_THREADS=2 \
bash scripts/run_same_face_segmented_io_validation_0143.sh
```

This requires the corresponding `.smpcd` initial state, as in the previous 0143
validation workflow.

## Expected interpretation

The new `classic_resampling` mode is the key addition for the next study.  It
keeps the SRC/MPCD transport, grid shift, collision and thermostat, and uses the
population guard as a purely numerical repair of the particle support.  It does
not impose the Q6 incompressible constraint:

```text
projectionEnable = false
resamplingEnable = true
```

This mode should therefore be compared against both `classic` and
`q6_resampling` to separate support-quality effects from incompressibility
effects.

# 0141 — Validation scripts updated for population-support resampling 0140

This patch updates the validation launchers so that the 0140 MATLAB-compatible population-support guard is explicitly enabled in every `q6_resampling` case that should be re-run after the 0140 pivot.

The C++ solver is not modified by this patch.

## Workflow convention

MATLAB prepares initial `.smpcd` states in `init/**`.
Bash scripts generate `params_*.kv` files and run `build/src_mpcd_base`.
MATLAB analyzes the resulting files in `runs/**`.

The launchers do not generate initial states.

## Output folders

The default run roots now use an `_0140` suffix so that the new campaign can be compared with previous runs, for example:

- `runs/taylor_green_random_population_resampling_0128_0140`
- `runs/poiseuille_wallvp_resampling_0131_0140`
- `runs/open_channel_rect_obstacle_resampling_0138b_0140`
- `runs/injection_fill_resampling_0139_0140`

Override any root with `RUN_ROOT=...` if needed.

## Resampling options enforced in q6_resampling cases

Each updated `q6_resampling` block contains the 0140 population-support parameters:

```kv
resamplingEnable = true
resamplingPopulationGuardEnable = true
resamplingPopulationNMin = 14
resamplingPopulationNTarget = 20
resamplingPopulationNMax = 26
resamplingPopulationMaxSplitsPerCell = 16
resamplingPopulationMaxSplitsPerStep = 200000
resamplingPopulationMaxExtractionsPerCell = 64
resamplingPopulationMaxExtractionsPerStep = 200000
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = 10
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = 0.5
resamplingParticleMassMax = 2.0
```

The values can be overridden without editing scripts:

```bash
RESAMP_N_MIN=14 \
RESAMP_N_TARGET=20 \
RESAMP_N_MAX=26 \
RESAMP_POP_GUARD_ENABLE=true \
TG_MASS_RENORM_PERIOD=10 \
./scripts/run_taylor_green_random_population_resampling_validation_0128.sh
```

For geometry-specific scripts, the mass renormalization period keeps the existing prefix:

- `TG_MASS_RENORM_PERIOD`
- `POIS_MASS_RENORM_PERIOD`
- `CYL_MASS_RENORM_PERIOD`
- `CCYL_MASS_RENORM_PERIOD`
- `BSTEP_MASS_RENORM_PERIOD`
- `ORECT_MASS_RENORM_PERIOD`
- `FILL_MASS_RENORM_PERIOD`

## Updated scripts

- `scripts/run_taylor_green_void_rich_resampling_validation_0127.sh`
- `scripts/run_taylor_green_random_population_resampling_validation_0128.sh`
- `scripts/run_taylor_green_forced_random_population_resampling_validation_0130.sh`
- `scripts/run_poiseuille_wallvp_resampling_validation_0131.sh`
- `scripts/run_periodic_cylinder_resampling_validation_0134.sh`
- `scripts/run_channel_cylinder_resampling_validation_0135.sh`
- `scripts/run_backward_step_resampling_validation_0136.sh`
- `scripts/run_open_channel_rect_obstacle_resampling_validation_0138b.sh`
- `scripts/run_injection_fill_resampling_validation_0139.sh`

A helper suite launcher is also added:

- `scripts/run_resampling_0140_validation_suite.sh`

By default it runs a moderate subset:

```bash
./scripts/run_resampling_0140_validation_suite.sh
```

Equivalent to:

```bash
VALIDATION_TESTS="tg_random poiseuille rect_obstacle fill" \
./scripts/run_resampling_0140_validation_suite.sh
```

Run a broader set with:

```bash
VALIDATION_TESTS="tg_void tg_random tg_forced poiseuille periodic_cylinder channel_cylinder bstep rect_obstacle fill" \
./scripts/run_resampling_0140_validation_suite.sh
```

## Recommended first campaign

After applying 0140 and this script update, run:

```bash
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
```

Then, in order:

```bash
ORECT_STEPS=1000 \
ORECT_DUMP_EVERY=250 \
ORECT_SUMMARY_EVERY=10 \
./scripts/run_open_channel_rect_obstacle_resampling_validation_0138b.sh

FILL_STEPS=1000 \
FILL_DUMP_EVERY=100 \
FILL_SUMMARY_EVERY=10 \
./scripts/run_injection_fill_resampling_validation_0139.sh

TG_STEPS=1000 \
TG_DUMP_EVERY=100 \
TG_SUMMARY_EVERY=5 \
./scripts/run_taylor_green_random_population_resampling_validation_0128.sh

POIS_STEPS=1000 \
POIS_DUMP_EVERY=1000000 \
POIS_SUMMARY_EVERY=10 \
./scripts/run_poiseuille_wallvp_resampling_validation_0131.sh
```

The decisive metrics after 0140 are:

- `resampPopulationGuardWetNMinAfter`
- `resampPopulationGuardWetLowNFractionAfter`
- `resampPopulationGuardSplitParticlesCreated`
- `resampPopulationGuardExtractedParticles`
- `resampParticleMassMax`
- `resampMRelRms`
- `stdN`

The first target is not to get a vortex street immediately. The target is to verify that wet cells keep enough active particles while the mass remains controlled.

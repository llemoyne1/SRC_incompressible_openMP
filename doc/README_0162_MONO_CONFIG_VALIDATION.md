# 0162 — mono-configuration validation campaign for the 0161 elliptic-operator optimisation

This differential package adds only validation tooling. It does not modify the
solver, the physics, or the build system.

## Rationale

The purpose is to compare the original source tree and the 0161-optimised source
tree with a compact but discriminating matrix. For each geometry, only the full
incompressible treatment is tested:

```text
Q6 projection + weighted resampling
```

A single OpenMP thread count is used, with `THREADS=8` by default. If this full
chain agrees between the original and 0161 code for `THREADS>1`, then the
probability of a hidden discrepancy in the separate `classic`, `q6`, or
`q6_resampling` sub-stages is very low. If a discrepancy appears, then the
validation can be expanded locally to isolate the responsible stage.

The closed-capacity virial term is exercised only in the piston case.

## Files

```text
scripts/generate_validation_state_0162.py
scripts/run_validation_mono_config_0162.sh
scripts/compare_validation_mono_config_0162.py
doc/README_0162_MONO_CONFIG_VALIDATION.md
```

## Default cases

```text
tg_periodic_full          periodic Taylor-Green, Q6 + resampling
poiseuille_wall_full      periodic-x / solid-y Poiseuille, Q6 + resampling
open_rect_obstacle_full   inlet/outlet + solid rectangle, Q6 + resampling
piston_virial_full        closed piston, Q6 + resampling + closed-capacity virial
```

Default numerical configuration:

```text
Nx = 64
Ny = 64
gamma = 20
steps = 1000
threads = 8
summaryEvery = 100
dumpStateEvery = 0
```

The states are generated deterministically by `generate_validation_state_0162.py`
so the original and optimised trees can use identical initial conditions without
MATLAB.

## Apply in both source trees

Apply this zip in both the original and optimised repositories:

```bash
unzip -o SRC_MPCD_openmp_validation_mono_0162_files_only.zip
chmod +x scripts/generate_validation_state_0162.py
chmod +x scripts/run_validation_mono_config_0162.sh
chmod +x scripts/compare_validation_mono_config_0162.py
```

## Build

Use the same build profile in both trees. For example:

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

or, if the optimised build script is not available in the original tree:

```bash
./scripts/build_src_mpcd_base.sh
```

## Run in the original tree

```bash
cd SRC_openMP_resampling
RUN_TAG=origin_0162 \
RUN_ROOT=runs/validation_mono_0162_origin \
THREADS=8 \
STEPS=1000 \
SUMMARY_EVERY=100 \
./scripts/run_validation_mono_config_0162.sh
```

## Run in the 0161 tree

```bash
cd SRC_openMP_optimized
RUN_TAG=opt0161_0162 \
RUN_ROOT=runs/validation_mono_0162_opt0161 \
THREADS=8 \
STEPS=1000 \
SUMMARY_EVERY=100 \
./scripts/run_validation_mono_config_0162.sh
```

## Compare

From either tree, run:

```bash
python3 scripts/compare_validation_mono_config_0162.py \
  --origin ../SRC_openMP_resampling/runs/validation_mono_0162_origin \
  --optimized ../SRC_openMP_optimized/runs/validation_mono_0162_opt0161 \
  --out validation_compare_0162.csv \
  --summary-out validation_compare_summary_0162.csv
```

The comparison produces:

```text
validation_compare_0162.csv          long-form metric-by-metric comparison
validation_compare_summary_0162.csv  one-line-per-case verdict and speedup
```

Timing fields are reported but ignored for pass/fail. Integer counters are
compared exactly. Floating-point fields use strict tolerances by default, with a
few pragmatic relaxed tolerances for solver residuals and flux diagnostics whose
last digits can change because of OpenMP reduction order.

## Recommended interpretation

A clean validation should show:

```text
q6Iterations identical or extremely close
q6Converged unchanged
q6ResidualRel same order of magnitude
q6DivAfterProjectedFluxRms unchanged to numerical tolerance
resamp counters unchanged
solid-leak diagnostics not degraded
open-boundary flux diagnostics not degraded
capacity/virial diagnostics unchanged in the piston case
```

If all cases pass, 0161 can be considered physically non-regressive on this
compact discriminating campaign. If a case fails, the next step is to rerun only
that geometry with an expanded local matrix, for example:

```text
classic
q6
q6_resampling
threads = 1, 4, 8
```

That expanded matrix is intentionally not part of the default 0162 campaign.

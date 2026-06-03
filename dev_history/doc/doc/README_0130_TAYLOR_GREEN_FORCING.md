# 0130 — Periodic Taylor--Green body forcing

This patch adds an optional Taylor--Green body acceleration to the OpenMP
resampling baseline.  It is a runtime C++ forcing term only: initial states are
still generated outside the executable, following the established workflow:

```text
MATLAB prepare_*.m -> init/**/*.smpcd
bash scripts/*.sh  -> params.kv + build/src_mpcd_base
MATLAB analyze_*.m -> runs/**/analysis
```

## Forcing definition

When enabled, each active `Fluid` particle receives before streaming:

```text
ax = A sin(2*pi*m_x*x/Lx) cos(2*pi*m_y*y/Ly)
ay =-A cos(2*pi*m_x*x/Lx) sin(2*pi*m_y*y/Ly)
```

The field is divergence-free, zero-mean on a periodic box, and aligned with the
standard Taylor--Green vortex used by the MATLAB initializers.

## New params.kv keys

```text
taylorGreenForcingEnable = false
taylorGreenForcingAmplitude = 0.0
taylorGreenForcingModeX = 1
taylorGreenForcingModeY = 1
```

Aliases accepted by the parser:

```text
tgForcingEnable
tgForcingAmplitude
tgForceAmplitude
tgForcingModeX
tgForcingModeY
```

The forcing is currently restricted to fully periodic runs (`bcX=periodic`,
`bcY=periodic`).

## Updated Taylor--Green launchers

The 0126/0127/0128 launchers now accept:

```bash
TG_FORCING_ENABLE=true|false
TG_FORCING_AMPLITUDE=0.02
TG_FORCING_MODE_X=1
TG_FORCING_MODE_Y=1
```

Defaults keep the previous unforced behavior:

```bash
TG_FORCING_ENABLE=false
TG_FORCING_AMPLITUDE=0.0
```

A convenience launcher is also added:

```bash
./scripts/run_taylor_green_forced_random_population_resampling_validation_0130.sh
```

It reuses the MATLAB-generated random-population initial state from 0128:

```matlab
cd matlab
prepare_taylor_green_random_population_resampling_0128( ...
    'output', '../init/taylor_green_random_population_resampling_0128/initial_state_tg_random_pop_0128.smpcd', ...
    'Nx', 32, 'Ny', 32, 'gamma', 20, ...
    'populationStd', 6.0, 'populationMin', 4, 'populationMax', 36, ...
    'flowAmplitude', 0.08, 'kBT', 0.001, 'seed', 1280128, ...
    'makePreview', true);
```

Then from the repository root:

```bash
TG_FORCING_AMPLITUDE=0.02 \
TG_STEPS=1000 \
TG_DUMP_EVERY=100 \
TG_SUMMARY_EVERY=5 \
TG_THREADS=8 \
./scripts/run_taylor_green_forced_random_population_resampling_validation_0130.sh
```

Post-process with the existing MATLAB analyzer:

```matlab
cd matlab
analyze_taylor_green_random_population_resampling_0128('../runs/taylor_green_forced_random_population_resampling_0130');
```

## Smoke test

```bash
./scripts/run_taylor_green_forcing_smoke_0130.sh
```

The smoke creates a tiny V2 `.smpcd` state internally, runs one unforced and one
forced step, and verifies that the forced mean kinetic energy matches the
analytical acceleration increment.

# SRC/MPCD C++ base refactor

This branch contains the cleaned starting point for a generic C++ SRC/MPCD code.
It deliberately removes the historical validation/benchmark scripts from the
working tree so that the new base architecture remains visible.

The historical OpenMP redistribution version is kept in Git history through the
reference tag/branch created before the cleanup.

## Current scope

Implemented:

- binary `.smpcd` particle state format with `x, y, vx, vy, type, mass`;
- MATLAB writer/reader/generator/inspector for `.smpcd` states;
- C++ reader/writer for `.smpcd` states;
- first rectangular 2-D SRC/MPCD base executable;
- mass-aware cell velocity in the SRC/MPCD collision;
- OpenMP-parallelized base kernels with preallocated collision workspace;
- minimal runtime summary CSV and optional `.smpcd` state dumps.

Not implemented yet in the base executable:

- explicit solid geometry/cylinder virtual particles;
- incompressible redistribution;
- Q6/Q9 pressure or mass-flux projection;
- virial/liquid EOS closure;
- case-specific physical diagnostics;
- inlet/outlet internal-flow boundary layer support.

## Build

```bash
./scripts/build_src_mpcd_base.sh
```

The executable is written to:

```text
build/src_mpcd_base
```

## Run

Generate an initial `.smpcd` state from MATLAB, then use a parameter file such as:

```text
examples/params_periodic_base.kv
examples/params_channel_y_bounceback.kv
examples/params_channel_y_specular.kv
examples/params_channel_x_bounceback.kv
examples/params_poiseuille_y_bounceback_vp.kv
```

Run for example:

```bash
./build/src_mpcd_base examples/params_periodic_base.kv
./build/src_mpcd_base examples/params_channel_y_bounceback.kv
```

Make sure that `inputState` in the parameter file points to the generated
`.smpcd` state. Use `numThreads` in the parameter file or `OMP_NUM_THREADS` in
the shell to control OpenMP parallelism. Example files use `numThreads = 4`; set it to `0` to leave the choice to the OpenMP runtime.

## Documentation

- `docs/SRCMPCD_STATE_BIN_V1.md`: binary particle-state format.
- `docs/SRC_MPCD_BASE.md`: periodic base executable and runtime contract.

## MATLAB post-processing

The base solver writes primitive dumps only. MATLAB helpers in `matlab/` provide
summary plots, sequential dump visualization and binned fields:

```matlab
addpath('matlab')
out = postprocess_smpcd_run('runs/periodic_base', 'field', 'rho');
```

Useful fields are `particles`, `N`, `rho`, `Ux`, `Uy`, `speed`, `omega` and
`type`. See `docs/MATLAB_POSTPROCESSING.md` for the full workflow.


## Rectangular wall virtual particles

The base executable now supports aggregate stochastic wall virtual particles for rectangular walls. They are enabled by `wallVpEnable = true` and contribute only to the collision-cell mass/momentum; they are not stored in `.smpcd` dumps. See `docs/WALL_VIRTUAL_PARTICLES.md` and the examples:

```bash
build/src_mpcd_base examples/params_channel_y_bounceback_vp.kv
build/src_mpcd_base examples/params_channel_x_bounceback_vp.kv
```


## First Poiseuille validation

The branch includes a lightweight MATLAB validation workflow for the primitive
`.smpcd` dumps. Run the first channel cases with:

```bash
./build/src_mpcd_base examples/params_poiseuille_y_specular.kv
./build/src_mpcd_base examples/params_poiseuille_y_bounceback.kv
./build/src_mpcd_base examples/params_poiseuille_y_bounceback_vp.kv
```

Then compare the profiles in MATLAB:

```matlab
addpath('matlab')
cmp = compare_poiseuille_runs({ ...
    'runs/poiseuille_y_specular', ...
    'runs/poiseuille_y_bounceback', ...
    'runs/poiseuille_y_bounceback_vp'}, ...
    'labels', {'specular', 'bounceback', 'bounceback+VP'}, ...
    'flowComponent', 'Ux', ...
    'profileDirection', 'y', ...
    'fitStartFraction', 0.5, ...
    'excludeWallCells', 2);
```

See `docs/POISEUILLE_VALIDATION.md` for details.

- `docs/MASS_AWARE_THERMOSTAT.md` documents the optional mass-aware cell-relative thermostat for forced channel calibration runs.

## Generic solid thermal wall model

The recommended solid-wall path is now `bcFace = solid` with aggregate thermal wall coupling controlled by a small set of parameters:

```text
wallAccommodation = 1.0
wallVpGamma = 0.0
wallKBT = -1.0
wallThermalNoise = 1.0
```

See `docs/SOLID_THERMAL_BOUNDARIES.md` and the examples `params_channel_y_solid_thermal.kv`, `params_channel_x_solid_thermal.kv`, and `params_poiseuille_y_solid_thermal_thermostat.kv`.

## Solid-thermal Poiseuille symmetry validation

The generic solid-wall model can be validated by transposing the Poiseuille channel:

```bash
./build/src_mpcd_base examples/params_poiseuille_y_solid_thermal_long.kv
./build/src_mpcd_base examples/params_poiseuille_x_solid_thermal_long.kv
```

Then in MATLAB:

```matlab
addpath('matlab')
out = validate_solid_thermal_poiseuille_symmetry( ...
    'runs/poiseuille_y_solid_thermal_long', ...
    'runs/poiseuille_x_solid_thermal_long', ...
    'fitStartFraction', 0.5, ...
    'excludeWallCells', 2);
```

This compares `Ux(y)` for solid y-walls with `Uy(x)` for solid x-walls. Agreement of the two profiles is the first axis-symmetry check for the generic `solid` thermal boundary condition.

## Sliding-wall Couette validation

Tangential solid-wall motion is tested with transposed Couette runs:

```bash
./build/src_mpcd_base examples/params_couette_y_solid_thermal_long.kv
./build/src_mpcd_base examples/params_couette_x_solid_thermal_long.kv
```

MATLAB post-processing:

```matlab
addpath('matlab')
out = validate_solid_thermal_couette_sliding( ...
    'runs/couette_y_solid_thermal_long', ...
    'runs/couette_x_solid_thermal_long', ...
    'fitStartFraction', 0.5, ...
    'excludeWallCells', 2, ...
    'stationaryWindowFraction', 0.25);
```

See `docs/SOLID_THERMAL_COUETTE_SLIDING.md`.

## Active fluid domain

The code separates the fixed numerical box (`Lx`, `Ly`, `Nx`, `Ny`) from the active fluid domain used by solid-wall reflection and solid-thermal wall coupling. By default they coincide. The active-domain bounds are controlled by `fluidXMin0`, `fluidXMax0`, `fluidYMin0`, `fluidYMax0` and optional boundary velocities. The aliases `fluidYTop0` and `fluidYTopVelocity` are available for future top-piston/EOS tests. Runtime summaries record `fluidArea` and `meanPhysicalDensity`; detailed field analysis remains in MATLAB post-processing.

See `docs/ACTIVE_FLUID_DOMAIN.md`.

### Active-domain smoke tests

The active-domain refactor includes two smoke-test parameter files:

```text
examples/params_active_domain_y_top_static.kv
examples/params_active_domain_y_top_slow_motion.kv
```

They require a reduced-domain initial state, `initial_state_active_y095.smpcd`, generated from MATLAB with particles inside `0 <= y <= 0.95`. The helper `matlab/validate_active_fluid_domain_refactor.m` summarizes `fluidYMax`, `fluidArea`, mean physical density and thermal control from `summary_runtime.csv`.

See `docs/ACTIVE_FLUID_DOMAIN_SMOKE_TESTS.md`.

## Immersed analytic circle

The base solver now supports a first fixed immersed analytic circular solid via
`immersedCircleEnable=true`. It reuses the generic `solid_thermal` wall coupling
and adds only runtime control diagnostics (`hitsImmersed`,
`virtualMassImmersed`). See `docs/IMMERSED_ANALYTIC_CIRCLE.md` for parameters,
state generation and smoke-test commands.

## Recent immersed-circle validation example

- `examples/params_immersed_circle_rotating_64x64.kv`: fixed circular immersed solid with prescribed angular wall velocity.

### Translating immersed circle

A first slowly translating immersed circular solid is provided in
`examples/params_immersed_circle_translating_64x64.kv`. The moving center uses
`immersedCircleVx/Vy`; the local wall velocity used by reflection and
`solid_thermal` coupling is the rigid-body velocity of the moving circle. See
`docs/IMMERSED_CIRCLE_TRANSLATION.md`.

## Incompressible Q6/Q9 development branch

The incompressible development is carried on `feature/elliptic-q6-core`, while
`clean/src-mpcd-base` remains the validated compressible baseline. The
incompressible branch is built around a single generic elliptic projection core,
not separate Q6/Q9-specific solvers.

The core solves generic face-flux projection problems of the form:

```text
F_new = F_base - alpha grad(phi)
div(F_new) = target
```

The same module is used for periodic projection, channel projection,
Q9 mass-flux projection and elliptic low-pass filtering. This is intended to
remain close to the validated MATLAB `general_bc` / `relax_to_uniform_lowk`
method and to prepare later MPI/CUDA and surface-tension development.

Current validation documents:

- `docs/INCOMPRESSIBLE_Q6_Q9_STATUS.md`: current Q6/Q9 status and validation numbers.
- `docs/ELLIPTIC_PROJECTION_CORE.md`: generic elliptic projection core.
- `docs/Q6_PERIODIC_ADAPTER.md`: periodic Q6 adapter.
- `docs/Q6_CHANNEL_POISEUILLE_VALIDATION.md`: Q6 channel validation.
- `docs/Q9_PERIODIC_ADAPTER.md`: periodic Q9 mass-flux adapter.
- `docs/Q9_BETA_SWEEP_VALIDATION.md`: Q9 beta sweep and raw-vs-filtered behavior.
- `docs/TAYLOR_GREEN_Q9_FILTERED_VALIDATION.md`: filtered Q9 Taylor-Green validation.
- `docs/POISEUILLE_Q9_FILTERED_CHANNEL_VALIDATION.md`: filtered Q9 channel validation.
- `docs/Q9_LOWK_FILTERING_INCIDENT.md`: documented Q9 channel instability and low-k mismatch fix.

For MATLAB scripts in this branch, the intended workflow is to launch MATLAB
from the `matlab/` directory and use `../runs/...` paths, for example:

```matlab
addpath('.')
out = validate_poiseuille_q9_channel_long('makePlots', true);
```

# SRC/MPCD base executable

This branch starts from a minimal generic SRC/MPCD core. The first executable is
restricted to a 2-D rectangular box with either periodic face pairs or simple
specular/bounceback walls. It intentionally excludes the historical
incompressible redistribution, Q6/Q9 projections, virial EOS, liquid closure,
inlet/outlet flow handling, and case-specific diagnostics. The base branch now includes a mass-aware relative thermostat, but only as an optional runtime-control layer for forced validation runs.

## Runtime contract

The executable reads one parameter file:

```bash
./build/src_mpcd_base params.kv
```

The parameter file points to a single binary particle state:

```text
inputState = initial_state.smpcd
```

The `.smpcd` state contains only microscopic particle data:

```text
x, y, vx, vy, type, mass
```

Domain size, grid, timestep, boundary conditions and dump cadence are kept in
`params.kv`, not in the particle state.

## Implemented numerical step

For each step, the base executable performs:

```text
uniform body acceleration
streaming
boundary handling on each rectangular face
random shifted-grid SRC/MPCD collision
optional mass-aware relative thermostat
runtime summary / optional state dump
```

The collision is mass-aware and uses preallocated per-run work buffers, so the hot path does not reallocate particle/cell work arrays at every step:

```text
u_cell = sum_i(m_i v_i) / sum_i(m_i)
v_i'   = u_cell + R_alpha (v_i - u_cell)
```

The particle `type` field is preserved but not used yet to specialize the
collision physics.

## Implemented boundaries

Boundary modes are now specified per face:

```text
bcLeft   = periodic | specular | bounceback
bcRight  = periodic | specular | bounceback
bcBottom = periodic | specular | bounceback
bcTop    = periodic | specular | bounceback
```

The legacy pair aliases are still accepted:

```text
bcX = periodic | specular | bounceback
bcY = periodic | specular | bounceback
```

`bcX` sets both `bcLeft` and `bcRight`; `bcY` sets both `bcBottom` and
`bcTop`. Explicit per-face keys override the pair aliases. Periodic boundaries
must be paired along an axis, so `bcLeft=periodic` requires
`bcRight=periodic`, and `bcBottom=periodic` requires `bcTop=periodic`.

Implemented wall modes:

```text
specular   : reverse the normal velocity component only
bounceback : reverse both velocity components relative to a fixed wall
```

The modes `inlet`, `input`, `outlet`, `output` and `open` are reserved by the
parser for a future internal-flow boundary layer, but are deliberately rejected
by this executable for now. Wall virtual particles are also not implemented in
this patch.

## Build

```bash
./scripts/build_src_mpcd_base.sh
```

or directly:

```bash
g++ -std=c++17 -O2 -Wall -Wextra -fopenmp -Iinclude \
  src/main_src_mpcd_base.cpp \
  src/params_io_base.cpp \
  src/cell_grid.cpp \
  src/boundary_base.cpp \
  src/src_collision.cpp \
  src/thermostat.cpp \
  src/src_mpcd_base.cpp \
  src/runtime_summary.cpp \
  src/particle_state.cpp \
  src/state_smpcd_io.cpp \
  -o build/src_mpcd_base
```

## Minimal run

1. Generate a state in MATLAB, for example:

```matlab
state = generate_smpcd_state_uniform( ...
    'output', 'initial_state.smpcd', ...
    'Lx', 1.0, 'Ly', 1.0, ...
    'Nx', 32, 'Ny', 32, ...
    'gamma', 20, ...
    'kBT', 0.01, ...
    'mass', 1.0, ...
    'type', 0, ...
    'seed', 12345);
```

2. Copy `examples/params_periodic_base.kv` and set `inputState` to the generated file.

3. Run:

```bash
./build/src_mpcd_base params_periodic_base.kv
```

The output directory contains:

```text
params_used.kv
summary_runtime.csv
state_step_XXXXXXXX.smpcd   # if dumpStateEvery > 0
```


## Optional mass-aware thermostat

Forced channel runs can use a deterministic cell-relative rescaling thermostat:

```text
thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = 0.01
```

The thermostat rescales velocities relative to the real-particle mass-weighted
cell velocity, so it conserves real-particle cell momentum and remains valid for
heterogeneous particle masses. See `docs/MASS_AWARE_THERMOSTAT.md`.

## OpenMP notes

The base executable is compiled with OpenMP by the provided build script. The
parameter

```text
numThreads = 4
```

sets four OpenMP threads explicitly. Use `numThreads = 0` to keep the OpenMP runtime default, usually controlled by `OMP_NUM_THREADS`. A positive value calls `omp_set_num_threads(numThreads)` at startup. The executable reports `threadsActive` and `threadsMax` when the run starts, and `summary_runtime.csv` records `numThreadsUsed`.

The first parallelized kernels are:

```text
streaming/body acceleration
boundary handling
cell-id assignment
per-cell mass/momentum accumulation with per-thread buffers
particle-wise SRC/MPCD rotation
runtime reductions for mass/momentum/temperature
```

The step-0 summary uses unshifted cell counts with the configured boundary handling, so `minN`, `maxN` and
`stdN` are meaningful before the first collision. Later summaries use the
shifted collision-cell occupancy from the current step.

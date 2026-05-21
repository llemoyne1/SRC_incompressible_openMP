# SRC/MPCD base executable

This branch starts from a minimal generic SRC/MPCD core. The first executable is
restricted to a fully periodic 2-D box and intentionally excludes the historical
incompressible redistribution, Q6/Q9 projections, virial EOS, liquid closure,
and case-specific diagnostics.

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
periodic wrapping
random shifted-grid SRC/MPCD collision
runtime summary / optional state dump
```

The collision is mass-aware:

```text
u_cell = sum_i(m_i v_i) / sum_i(m_i)
v_i'   = u_cell + R_alpha (v_i - u_cell)
```

The particle `type` field is preserved but not used yet to specialize the
collision physics.

## Implemented boundaries

Only

```text
bcX = periodic
bcY = periodic
```

are supported in this first executable. Non-periodic walls, bounceback,
specular reflection and virtual particles are deliberately left for later
patches.

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

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

- wall virtual particles;
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
```

Run for example:

```bash
./build/src_mpcd_base examples/params_periodic_base.kv
./build/src_mpcd_base examples/params_channel_y_bounceback.kv
```

Make sure that `inputState` in the parameter file points to the generated
`.smpcd` state. Use `numThreads` in the parameter file or `OMP_NUM_THREADS` in
the shell to control OpenMP parallelism.

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

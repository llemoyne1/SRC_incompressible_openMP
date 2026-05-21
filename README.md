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
- first periodic 2-D SRC/MPCD base executable;
- mass-aware cell velocity in the SRC/MPCD collision;
- optional OpenMP parallel loops;
- minimal runtime summary CSV and optional `.smpcd` state dumps.

Not implemented yet in the base executable:

- non-periodic walls;
- bounceback/specular reflection;
- wall virtual particles;
- incompressible redistribution;
- Q6/Q9 pressure or mass-flux projection;
- virial/liquid EOS closure;
- case-specific physical diagnostics.

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
```

Run:

```bash
./build/src_mpcd_base examples/params_periodic_base.kv
```

Make sure that `inputState` in the parameter file points to the generated
`.smpcd` state.

## Documentation

- `docs/SRCMPCD_STATE_BIN_V1.md`: binary particle-state format.
- `docs/SRC_MPCD_BASE.md`: periodic base executable and runtime contract.

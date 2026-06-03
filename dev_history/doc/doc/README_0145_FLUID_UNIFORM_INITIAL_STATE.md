# 0145 — Full-fluid uniform initial state generator

This mini-patch adds a MATLAB state generator for injection/fill tests that should start from a fully wet domain instead of an inactive pool.

## Added file

```text
matlab/prepare_injection_fill_fluid_uniform_0145.m
```

## Purpose

`prepare_injection_fill_resampling_0139.m` was designed for an initially inactive reservoir/pool state. For tests where the initial tank is already filled, we need an explicit `.smpcd` V2 state with active `Fluid` particles everywhere.

The new generator writes exactly `gamma` active `Fluid` particles per cell, uniformly distributed inside each cell. It does **not** use the old `inactivePlacement = cell_uniform` path.

## Role convention

```text
role = 1  Fluid    active SRC/MPCD particle
role = 0  Inactive reserve/free pool slot
```

## Typical use

From the repository root:

```matlab
cd matlab
prepare_injection_fill_fluid_uniform_0145( ...
    'output', '../init/injection_fill_resampling_0145/initial_state_fluid_uniform_0145.smpcd', ...
    'Lx', 1.0, 'Ly', 1.0, ...
    'Nx', 48, 'Ny', 48, 'gamma', 20, ...
    'capacityMultiplier', 1.25, ...
    'kBT', 0.001, ...
    'seed', 1390145, ...
    'makePreview', true);
cd ..
```

Then run an existing validation script by overriding the initial state:

```bash
FILL_INITIAL_STATE=init/injection_fill_resampling_0145/initial_state_fluid_uniform_0145.smpcd \
RUN_ROOT=runs/injection_fill_resampling_0145_full_fluid_small \
bash scripts/run_injection_fill_resampling_validation_0139_small.sh
```

## Capacity multiplier

`gamma` always refers to the active initial fluid population per cell. `capacityMultiplier` only controls extra inactive reserve slots:

```text
nFluidInitial    = Nx * Ny * gamma
nTotalSlots      = round(capacityMultiplier * nFluidInitial)
nInactiveInitial = nTotalSlots - nFluidInitial
```

Use `capacityMultiplier = 1.0` for no inactive reserve. Use a value such as `1.25` if resampling should have free inactive slots available immediately.

# Minimal piston validation

This validation uses the active-fluid-domain geometry to compress a 2D channel
with a moving top solid wall. The goal is to prepare later EOS/liquid-closure
work without adding EOS-specific diagnostics to the C++ core.

The fixed numerical box remains `[0,Lx] x [0,Ly]`, while the active fluid domain
is `[0,Lx] x [0,yTop(t)]`. For the provided examples,

```text
yTop(t) = 0.95 - 0.001 t
```

with `dt = 0.001` and `nSteps = 50000`, so the final top position is `0.90`.
The expected density increase at conserved mass is

```text
rho(t) / rho(0) = area(0) / area(t).
```

## Generate the initial state

The initial state must be generated inside the initial active fluid domain:

```matlab
addpath('matlab')

generate_smpcd_state_uniform( ...
    'output', 'initial_state_active_y095.smpcd', ...
    'Lx', 1.0, ...
    'Ly', 0.95, ...
    'Nx', 32, ...
    'Ny', 32, ...
    'gamma', 80, ...
    'kBT', 0.01, ...
    'mass', 1.0, ...
    'type', 0, ...
    'seed', 12345);
```

## Run

```bash
./build/src_mpcd_base examples/params_piston_y_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_solid_thermal_unthermostatted.kv
```

The first case uses the mass-aware relative thermostat and should remain nearly
isothermal. The second case is useful as a control for compression-induced
thermal drift.

## Analyze

```matlab
addpath('matlab')

out = validate_minimal_piston({ ...
    'runs/piston_y_solid_thermal_isothermal', ...
    'runs/piston_y_solid_thermal_unthermostatted'}, ...
    'labels', {'isothermal', 'unthermostatted'}, ...
    'makePlots', true);
```

The MATLAB validator uses `summary_runtime.csv` only. It checks the quantities
that must be recorded at runtime for a moving domain: active bounds, active area,
mean physical density, conserved mass, thermal drift, and wall-hit counts.
Detailed fields remain available through the regular dump post-processing tools.

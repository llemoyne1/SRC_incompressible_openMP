# Periodic Taylor--Green validation for the Q6 adapter

This validation checks the first Q6 adapter on a smooth periodic incompressible
structure. The goal is not yet a calibrated viscosity measurement. The goal is
to verify that the generic elliptic projection can be used inside the SRC/MPCD
loop without destroying a coherent divergence-free periodic mode.

## Initial condition

Generate the same initial state for the classic and Q6 runs:

```matlab
addpath('matlab')

generate_smpcd_state_taylor_green( ...
    'output', 'initial_state_tg_64x64_g20_u0p05_kbt0p01.smpcd', ...
    'Lx', 1.0, ...
    'Ly', 1.0, ...
    'Nx', 64, ...
    'Ny', 64, ...
    'gamma', 20, ...
    'flowAmplitude', 0.05, ...
    'kxMode', 1, ...
    'kyMode', 1, ...
    'kBT', 0.01, ...
    'mass', 1.0, ...
    'type', 0, ...
    'seed', 12345);
```

The imposed mean field is

```text
u_x = U0 sin(2*pi*x/Lx) cos(2*pi*y/Ly)
u_y =-U0 cos(2*pi*x/Lx) sin(2*pi*y/Ly)
```

with `U0 = 0.05`.

## Runs

```bash
./build/src_mpcd_base examples/params_taylor_green_classic_64x64.kv
./build/src_mpcd_base examples/params_taylor_green_q6_64x64.kv
```

Both examples use the same thermal state and thermostat. The thermostat is the
cell-relative mass-aware thermostat, so it should preserve the local mean flow
while controlling microscopic thermal fluctuations.

## MATLAB analysis

```matlab
addpath('matlab')

out = validate_taylor_green_q6_periodic( ...
    'runs/taylor_green_classic_64x64', ...
    'runs/taylor_green_q6_64x64', ...
    'makePlots', true, ...
    'plotFinalFields', true);
```

The validator computes, from dumped particle states:

- Taylor--Green modal amplitude,
- correlation with the analytic Taylor--Green basis,
- cell-centered finite-difference divergence,
- vorticity RMS,
- thermal state from `summary_runtime.csv`,
- runtime Q6 divergence diagnostics.

## Expected first-level checks

The Q6 run should show:

```text
q6Applied = 1 on projected steps
q6Converged = 1 on projected steps
q6DivAfterProjectedFluxRms << q6DivBeforeRms
mass conserved
momentum corrected to roundoff
Taylor--Green modal correlation remains meaningful
```

The dumped-field divergence is computed from cell-centered velocities using a
simple central finite-difference diagnostic. It is not exactly the same discrete
operator as the face-field divergence used inside the Q6 adapter. The runtime
columns `q6DivBeforeRms` and `q6DivAfterProjectedFluxRms` are therefore the
primary diagnostics for the actual projection operator.

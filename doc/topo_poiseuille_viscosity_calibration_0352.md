# 0352-topo: Poiseuille viscosity calibration launcher

This patch adds a launcher for a quick Poiseuille calibration of the effective
kinematic viscosity before running higher-resolution NACA sweeps.

It does not modify the solver and does not add a new fitting routine.  The
existing MATLAB Poiseuille profile analysis scripts can be used on the generated
state dumps.

## Why this launcher

For the NACA sweep, a nominal high-Reynolds setup requires an estimate of

```text
nu_eff
```

with the same relevant numerical parameters:

```text
dt, kBT, gamma, thermostat, wall accommodation, Ny/cell size
```

The default launcher preserves the cell size of a prospective NACA grid

```text
Lx=1.5, Ly=0.4, Nx=600, Ny=160
```

but uses a shorter streamwise Poiseuille box:

```text
Poiseuille Nx=128, Ny=160
```

so that the transverse resolution is calibrated without paying for a long
streamwise domain.

## Run

```bash
BIN=build/src_mpcd_base_cuda_topo_0348a \
NACA_NX=600 \
NACA_NY=160 \
GAMMA=10 \
KBT=0.1 \
DT=0.0005 \
BODY_AX=0.002 \
STEPS=30000 \
DUMP_STATE_EVERY=1000 \
bash scripts/run_topo_poiseuille_viscosity_calibration_0352.sh
```

## Outputs

A typical run root is:

```text
runs/topo_poiseuille_viscosity_calibration_0352_nx128_ny160_g10/
```

Important files:

```text
params/topo_poiseuille_viscosity_calibration_0352.kv
logs/poiseuille_calibration_0352.env
logs/poiseuille_viscosity_fit_hint_0352.txt
output/summary_runtime.csv
output/state_step_*.smpcd
```

## Viscosity fit

For acceleration forcing `a_x = BODY_AX` and channel height `H = Ly`, fit the
steady profile as

```text
u(y) = A y (H-y) + B
```

then

```text
nu_eff = a_x / (2 A)
```

or equivalently

```text
nu_eff = a_x H^2 / (8 Umax)
```

after excluding a few cells near the walls and averaging over the steady final
window.

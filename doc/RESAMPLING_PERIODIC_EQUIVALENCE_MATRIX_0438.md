# 0438 — Periodic wall-free equivalence matrix for SRC/Q6/resampling paths

## Purpose

This step restricts physical path-equivalence validation to cases where the
paths are expected to remain comparable:

- periodic domain only;
- no wall boundary condition;
- no immersed solid;
- no Darcy/Brinkman `chi` field;
- no inlet/outlet;
- no geometrically forced poor-population zones.

This is deliberate.  Near walls and solid interfaces, the raw SRC path may
naturally deplete or overpopulate cells, while resampling actively counteracts
that population dynamics.  Wall/solid/channel cases therefore validate
robustness and applicability, not identity of the physical problem solved by the
four paths.

## Paths compared

The matrix compares the existing integration selectors:

```text
src
src-resampling
src-q6
src-q6-resampling
```

No new public solver flag or parameter is introduced in this step.

## Tier-1 cases introduced here

### 1. Periodic shear-wave decay

Initial condition:

```text
u_x(y,0) = U0 sin(2 pi y / Ly)
u_y(y,0) = 0
```

with fully periodic boundaries.  The expected modal decay is governed by an
effective viscosity estimate:

```text
A(t) / A(0) ~= exp(-nu_eff k^2 t),  k = 2 pi / Ly
```

This is the cleanest case for checking whether the resampling and Q6 paths
preserve a smooth hydrodynamic mode outside wall and solid artifacts.

Runner:

```bash
bash scripts/run_0438_periodic_shear_wave_path_matrix.sh
```

### 2. Periodic unforced Taylor-Green decay

Initial condition:

```text
u_x =  U0 sin(2 pi x / Lx) cos(2 pi y / Ly)
u_y = -U0 cos(2 pi x / Lx) sin(2 pi y / Ly)
```

with fully periodic boundaries and no Taylor-Green forcing.  This case retains a
vortical structure while avoiding walls and imposed solid/interface population
biases.

Runner:

```bash
bash scripts/run_0438_periodic_taylor_green_path_matrix.sh
```

## Default numerical settings

Defaults are intentionally moderate for a first execution:

```text
Nx = Ny = 64
gamma = 40
kBT = 0.001
U0 = 0.04
periodic shear steps = 2000
periodic TG steps = 1000
```

For quick plumbing smoke tests, use for example:

```bash
GAMMA=20 STEPS=100 SUMMARY_EVERY=20 \
RUN_MODES="src src-resampling src-q6 src-q6-resampling" \
bash scripts/run_0438_periodic_shear_wave_path_matrix.sh
```

For higher-SNR physical comparisons, use for example:

```bash
GAMMA=80 STEPS=5000 SUMMARY_EVERY=250 \
RUN_MODES="src src-resampling src-q6 src-q6-resampling" \
bash scripts/run_0438_periodic_shear_wave_path_matrix.sh
```

## Outputs

Each runner writes one root directory under `runs/` and produces:

```text
launch_status.csv
periodic_shear_wave_summary_0438.csv
periodic_shear_wave_report_0438.md
```

or:

```text
launch_status.csv
periodic_taylor_green_summary_0438.csv
periodic_taylor_green_report_0438.md
```

The CSV includes:

- final runtime summary values;
- final modal amplitude;
- amplitude ratio `A(t)/A(0)`;
- estimated `nu_eff`;
- relative deltas of resampling paths against their non-resampling references:
  - `src-resampling` vs `src`;
  - `src-q6-resampling` vs `src-q6`.

## Interpretation

This step is not a proof that all paths are physically identical in every case.
It is a controlled check that the paths remain close in wall-free, solid-free,
periodic hydrodynamic regimes where the population correction should be a weak
algorithmic stabilization rather than a change of boundary/interface physics.

Cases with walls, open boundaries, backward steps, Darcy/Brinkman `chi`, NACA,
obstacles, and injection-fill remain Tier-2 robustness/application cases and
must not be used as equivalence proofs.

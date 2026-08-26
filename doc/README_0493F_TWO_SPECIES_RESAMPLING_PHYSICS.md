# 0493f — two-species resampling physics smoke

## Scope

0493f is a validation-only extension of the 0493e mono-species physical smoke.
It does not modify `src/` or `include/`, and it does not require a rebuild.

The test isolates the current CUDA-resident multi-species resampling path on a
small periodic checkerboard state.  It is deliberately simpler than the
Rayleigh–Taylor and periodic shear-wave validations.

## Initial state

- grid: `16 x 8`
- target population: `gamma = 10`
- total checkerboard: `8 / 12` particles per cell
- composition in every cell: 50/50
- species checkerboards: `4 / 6` particles of type 1 and `4 / 6` of type 2
- equal particle masses
- different mean velocities for the two species
- no Q6, Darcy, walls, thermostat, random grid shift or SRC rotation
- very small `dt`, so the test measures resampling rather than transport

## Cases

1. `00_no_resampling`: `src` control.
2. `01_both_species`: both species enabled.
3. `02_type1_only`: only type 1 enabled.
4. `03_type2_only`: only type 2 enabled.
5. `04_no_species_enabled`: `src-resampling` with both species disabled.

## Blocking checks

- total mass, momentum and relative kinetic energy;
- mass and momentum of each species separately;
- relative kinetic energy of each species in this no-collision/no-thermostat case;
- two-species 50/50 composition when both species are enabled;
- exact per-cell immutability of a disabled species;
- exact complementary correction by the enabled species;
- no resampling activity when both species are disabled;
- no invalid operation, disabled-species mutation, donor-group underfill,
  invalid type or pool corruption;
- species mass-closure residual and guard mass/momentum budgets.

The test is macroscopic/local.  It does not require long trajectories to be
bitwise identical.

## Run

```bash
LIVE_PROGRESS=1 \
  bash scripts/run_0493f_two_species_resampling_physics_smoke.sh
```

Reports are written under:

```text
runs/0493f_two_species_resampling_physics/
```

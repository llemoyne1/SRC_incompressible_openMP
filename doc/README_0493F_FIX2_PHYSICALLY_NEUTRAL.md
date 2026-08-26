# 0493f-fix2 — physically neutral two-species resampling smoke

This validation-only correction replaces the original 0493f checkerboard by a
physically neutral population checkerboard.

## Initial state

- periodic 16 x 8 grid;
- total particle-count checkerboard: 8 / 12;
- per-species count checkerboard: 4 / 6 for types 1 and 2;
- total cell mass: 10 in every cell;
- mass of each species: 5 in every cell;
- poor-cell particle mass: 1.25;
- rich-cell particle mass: 5/6;
- uniform species momentum and thermal energy fields;
- no SRC rotation, thermostat, grid shift, forcing, Q6, Darcy, or walls.

Only the numerical representation is nonuniform.  The mass, momentum, energy,
and composition fields are initially uniform.

## Five cases

1. `00_no_resampling`: control in `src` mode;
2. `01_both_species`: both species enabled;
3. `02_type1_only`: type 1 enabled, type 2 frozen;
4. `03_type2_only`: type 2 enabled, type 1 frozen;
5. `04_no_species_enabled`: resampling mode with both species frozen.

## Expected population behavior

- both enabled: 5 + 5 particles in every cell;
- one enabled: enabled species reaches 5 everywhere, disabled species keeps its
  4 / 6 checkerboard, and total population becomes 9 / 11 (inside the guard
  band);
- none enabled: the 8 / 12 and 4 / 6 patterns remain unchanged.

## Physical invariants

The analyzer checks globally and cell-by-cell:

- total and per-species mass;
- total and per-species momentum;
- total and per-species kinetic/relative energy;
- total and per-species mass, momentum, and energy fields;
- absence of changes to disabled species;
- pool integrity and type validity.

Because the initial mass field is already at target, the population guard must
perform local split/merge operations.  The 0490k inter-cell mass-transfer plan
and the 0490m direct mass-transfer consumer are required to remain inactive.

## Installation

```bash
python3 apply_patch_0493f_fix2.py /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
```

No rebuild is required.

## Run

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
LIVE_PROGRESS=1 bash scripts/run_0493f_two_species_resampling_physics_smoke.sh
```

Outputs are written under:

```text
runs/0493f_fix2_two_species_neutral_physics/
```

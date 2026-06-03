# 0125 — Integrated resampling smoke: void + rich + latent

This milestone adds an integrated validator for the weighted-resampling core.
It does not change the physical algorithm.  It exercises, in a single
one-step run, the pieces introduced from 0112 to 0124:

- real-fluid weighted deposit, excluding dormant particles;
- active-domain wet/poor/rich classification;
- inactive pool persistence;
- local donor/receiver planning;
- mutating donor extraction (`Fluid -> Inactive`);
- mutating receiver insertion (`Inactive -> Fluid`);
- local mass/momentum remap;
- local thermal renormalisation;
- bounded particle-mass guard;
- latent wet-cell activation (`Latent -> Fluid`).

## Designed initial state

The smoke test builds an 8 x 4 periodic state with target cell mass `M*=4`:

- cell 0 is an empty wet void, seeded only through `Latent -> Fluid`;
- cell 1 is a poor cell with a very light particle, repaired through donor
  recycling and then the mass guard;
- cell 2 is a rich donor cell;
- all other cells are already at target mass;
- four latent particles are available for cell 0;
- two inactive slots persist as a dormant pool.

The run uses `alphaDeg=0`, no thermostat and no Q6 so the validator isolates
resampling bookkeeping and local conservative repairs.

## Expected result

After one step, the final summary must show:

- 4 latent particles activated into the empty wet cell;
- 4 donor particles extracted and reinserted into the remaining poor cell;
- local remap and thermal renormalisation applied;
- mass guard active, with no particle mass outside `[0.5, 2.0]` afterwards;
- no empty wet cells, no poor cells, no rich cells;
- `resampTotalMass = 128` and `resampMRelRms` at roundoff;
- final roles persisted in the V2 dump: 129 Fluid, 0 Latent, 2 Inactive.

Run:

```bash
./scripts/run_resampling_integrated_void_rich_latent_smoke_0125.sh
```

This validator is intentionally algebraic and deterministic.  It is the last
small smoke before moving to longer hydrodynamic cases such as void/rich pocket
dynamics, Taylor--Green and Poiseuille wallVP comparisons.

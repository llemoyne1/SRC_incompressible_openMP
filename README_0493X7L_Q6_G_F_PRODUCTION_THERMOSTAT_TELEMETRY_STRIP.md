# 0493x7l — Q6-g-f production thermostat/species telemetry strip

## Scope

0493x7l removes two remaining sources of production-only telemetry overhead
without changing Q6-g-f physics or the resident thermostat algorithm.

## Resident thermostat

For `speciesQ6Mode=free_surface_masked` only, the physical thermostat CUDA
sequence remains unchanged on every due step:

1. resident cell-moment deposit;
2. cell finalization;
3. thermal kinetic-energy deposit;
4. cell-relative scale computation;
5. particle velocity rescale.

The following 0491f observation work is now collected only on step 1 and on
`summaryEvery` steps, reusing the 0493x7k cadence:

- host reductions of pre-rescale and target thermal energy;
- O(Ncell) downloads of count, kinetic energy and scale;
- O(Ncell) host scan for cells/particles rescaled and scale min/mean/max;
- `cuda_species_q6_energy_0491f.csv` append.

No physical thermostat kernel is removed, reordered or modified.

The existing collision-cell-ID H2D handoff is deliberately retained. It is
not diagnostic work and must be treated separately if its residency is
optimized later.

## Dam-break runner

`run_ok_dambreak.sh` keeps generic `speciesDiagnostics` enabled for the
historical `src` and `src-q6` comparator modes but disables it for
`src-q6-g-f`.

No simulation parameter and no new runtime flag are added.

## Expected effect

With `SUMMARY_EVERY=100`, detailed Q6-g-f resident-thermostat telemetry is
collected at steps 1, 100, 200, ... instead of every thermostat step.
Production dynamics, thermostat cadence and thermostat target are unchanged.

## Validation sequence

1. apply and build 0486;
2. run a 100-step Q6-g-f dam-break smoke with `SUMMARY_EVERY=20`;
3. verify normal completion and unchanged Q6/physical summary values;
4. compare 500-step timing against 0493x7k if useful.

# 0493x8e — fresh Q6GF viscosity + Darcy stiffness

No C++/CUDA modification and no new runtime diagnostic.

## Viscosity

The exact x8d microscopic state is recalibrated with the existing path-selectable
0493x7n calibrator, Q6GF only, Taylor–Green only, four independent seeds:
493201, 593201, 693201, 793201.

State:
- a=1/256, .5x.5 box, 128^2
- gamma=20, dt=.002, kBT=.125, mass=1
- rotation=90°, random sign, grid shift
- cell_relative_rescale thermostat every step
- TG mode (2,2), amplitude .05, 2000 steps / 50 dumps
- production Q6GF tau=.25, gates 3/6, gain1, x7j, tolerance1e-5
- resampling off.

Each seed is analyzed by the canonical 0493w1 analyze_tg() via
analyze_0493x7n_tg_only.py. The x8e Python script only aggregates those fits.

## Darcy sweep

The fresh TG nuMean is used to dimension:
- ellB/a = 4
- ellB/a = 2
- ellB/a = 1
- ellB/a = 0.5
- alpha=4000 endpoint, i.e. alpha*dt=8.

For each resolved case alpha=nu/ellB^2. The body acceleration is recomputed from
the exact steady planar Brinkman solution so the analytical centerline speed
stays Uc=.1064.

The final alpha=4000 case is intentionally under-resolved and documents the
stiff penalized-wall limit; it must not be interpreted as a resolved Brinkman
penetration layer if the continuum-profile errors grow.

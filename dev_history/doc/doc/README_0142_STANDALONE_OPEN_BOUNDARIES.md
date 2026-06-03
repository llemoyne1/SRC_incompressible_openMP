# 0142 — Standalone inlet/outlet boundaries with solid opposite face

## Motivation

The resampling branch introduced particle roles (`Fluid`, `Latent`, `Inactive`) and a preallocated inactive pool.  The previous OpenMP inlet/outlet checks were still inherited from the earlier 0062/0063 open-channel work: an open boundary on an axis had to be paired with the opposite open boundary (`inlet/outlet` or `outlet/inlet`).  This was appropriate for through-flow channel validation, but it prevents filling-type cases such as

```text
bcLeft   = inlet
bcRight  = solid
bcBottom = solid
bcTop    = solid
```

where mass is injected from one side into a closed tank.

There is no longer a fundamental algorithmic reason for this limitation in the hard-reservoir/resampling path.  Exiting particles can be converted to `Inactive` slots and inlet reservoir particles can be activated from that pool.

## Code changes

### `src/params_io_base.cpp`

The validation logic now accepts one open axis containing any combination of wall and open faces:

- `solid/solid` remains valid;
- `inlet/outlet` and `outlet/inlet` remain valid;
- `inlet/solid`, `solid/inlet`, `outlet/solid`, and `solid/outlet` are now valid on a single axis.

Standalone open boundaries require

```text
inletReservoirMode = hard_cell_density
```

or an equivalent alias.  The older recycle mode is intentionally not used for standalone open faces, because recycle mode assumes a paired inlet face.

The previous one-open-axis limitation is kept: do not combine x-open and y-open boundaries in the same run yet.

### `src/boundary_base.cpp`

The hard-reservoir boundary path is now role-aware.

- Particles crossing an actual open face through its aperture are deactivated rather than physically removed from storage.
- Particles crossing a solid face on an axis that also has an open face are reflected as solid-wall particles, not accidentally treated as outlet particles.
- Hard-reservoir inlet insertion first reuses available `Inactive` slots, and only appends new particles if the inactive pool is exhausted.

This makes the boundary condition compatible with preallocated inactive-pool filling tests.

### `src/q6_projection_adapter.cpp`

Q6 open-boundary fluxes are now applied per face rather than only per inlet/outlet pair.

- An inlet face receives its prescribed ramped inlet flux.
- A solid opposite face keeps the wall/no-normal-flux value.
- An outlet face without paired inlet uses the local Neumann/base-face outlet policy.
- Historical paired `inlet/outlet` behaviour is preserved.

For closed-tank filling, the Q6 diagnostic `q6OpenBoundaryFluxBalance` is expected to be non-zero while the domain is being filled.  This is not a bug: a single inlet into a closed box represents net volume injection unless a free surface/latent region or an outlet absorbs it.

## Smoke test

The existing 0139 filling script can now be run without changing its boundary setup:

```bash
RUN_ROOT=runs/injection_fill_resampling_0139_0142 \
FILL_STEPS=500 \
FILL_SUMMARY_EVERY=25 \
FILL_DUMP_EVERY=100 \
FILL_THREADS=8 \
bash scripts/run_injection_fill_resampling_validation_0139.sh
```

For a quick parser/runtime smoke test:

```bash
RUN_ROOT=runs/smoke_injection_fill_0142 \
FILL_STEPS=5 \
FILL_SUMMARY_EVERY=1 \
FILL_DUMP_EVERY=0 \
FILL_THREADS=2 \
bash scripts/run_injection_fill_resampling_validation_0139.sh
```

Expected smoke-test behaviour:

- `bc=[L:inlet, R:solid, B:solid, T:solid]` is accepted;
- `Np` remains bounded by the inactive pool when enough inactive slots are available;
- `nFluidParticles` increases as the hard inlet activates particles;
- `nInactiveParticles` decreases correspondingly;
- `q6OpenBoundaryEnabled=1` in the Q6 case;
- `q6OpenBoundaryFluxXLow` is non-zero after the ramp begins;
- `q6OpenBoundaryFluxXHigh=0` for the solid right wall.

## Caveats

This patch enables the mechanically necessary boundary combinations for tank filling, but it does not by itself solve all filling physics.  The validation still has to check front propagation, wet/dry support, mass conservation, wall accumulation, temperature control and the effect of Q6 under net inflow.

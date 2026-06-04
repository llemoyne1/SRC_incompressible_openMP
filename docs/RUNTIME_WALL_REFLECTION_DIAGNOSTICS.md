# Runtime wall-reflection and particle-velocity diagnostics

This note documents the lightweight diagnostics added to debug rare wall
reflection failures in channel runs, especially filtered Q9 Poiseuille cases.

The change does not modify the SRC/MPCD, Q6, or Q9 algorithms. It only records
additional runtime quantities and improves the fatal error message emitted when
a particle requires an excessive number of wall reflections in one boundary
application.

## New runtime summary columns

The following particle-velocity diagnostics are written to `summary_runtime.csv`:

- `meanParticleSpeed`
- `maxParticleSpeed`
- `maxParticleAbsVx`
- `maxParticleAbsVy`

The following wall-reflection diagnostics are also written:

- `maxXWallReflectionsPerParticle`
- `maxYWallReflectionsPerParticle`

The existing hit counters remain unchanged:

- `hitsLeft`
- `hitsRight`
- `hitsBottom`
- `hitsTop`

For a stable Poiseuille channel run, `maxYWallReflectionsPerParticle` is expected
to remain small. A sudden increase usually indicates a rare high-velocity
particle or a non-finite particle state before wall handling.

## Improved fatal error message

If the wall-reflection guard triggers, the error now reports:

- step and physical time,
- particle index,
- attempted reflection count,
- particle position and velocity,
- predicted next position based on `dt`,
- active fluid-domain bounds.

This is intended to distinguish between:

1. a true high-velocity particle outlier,
2. a non-finite position or velocity,
3. a domain/geometry issue,
4. a wall-reflection problem,
5. an indirect Q9/channel interaction not visible in RMS diagnostics.

## MATLAB Poiseuille/Q9 validator

`validate_poiseuille_q9_channel_long.m` now reads the runtime column
`q9CorrectionVelocityMaxAbs` and reports it as `q9CorrectionVelocityMaxEnd`.
It also reports:

- `maxParticleAbsVyEnd`,
- `yWallReflectionMaxPerParticleEnd`.

The Q9 diagnostic plot also overlays `maxParticleAbsVy` when the column is
available.

# 0493o2-fix1 — Taylor–Green mono/dual species runner

This patch modifies only `scripts/run_0493o1_tg_split_guard.sh`.

## Modes

- `TG_SPECIES_MODE=mono` (default): preserves the existing mono-species configuration.
- `TG_SPECIES_MODE=dual`: converts the generated TG state into a locally balanced 50/50 mixture of two registered particle types.

The dual conversion rewrites only the stored particle `type` array. Positions, velocities, particle masses and roles are unchanged. Active particles are alternated by original order inside every geometric cell. Inactive and latent slots are assigned species 0 so all stored types are registered.

## Controls

- `TG_SPECIES0_TYPE` (default `1`)
- `TG_SPECIES1_TYPE` (default `2`)
- `SPECIES0_RESAMPLING_ENABLE` (default `true`)
- `SPECIES1_RESAMPLING_ENABLE` (default `true`)

Dual initialization requires distinct uint32 species types, even `GAMMA`, and even active occupancy in each generated cell.

Each species reference cell mass is `0.5 * GAMMA * PARTICLE_MASS`.

## Scope

No CUDA kernel, C++ source, physics operator, Q6 path or resampling algorithm is modified. No rebuild is required.

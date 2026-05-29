# 0111 — Particle roles and Fluid/Latent/Inactive masks

This milestone prepares the OpenMP SRC/Q6 branch for the weighted-resampling
core without activating recycling yet.

## Purpose

The code now separates two particle notions:

- `type`: physical/material species identifier, kept for future multi-species
  fluids;
- `role`: algorithmic resampling state.

The role convention is:

```cpp
ParticleRole::Inactive = 0; // free pool slot, ignored by fluid operators
ParticleRole::Fluid    = 1; // true active fluid particle
ParticleRole::Latent   = 2; // allocated particle not yet wetted/activated
```

Legacy in-memory states with an empty `role` vector are interpreted as all
`Fluid`. Legacy `.smpcd` V1 files are read with all particles normalized to the
`Fluid` role. New dumps are written as `.smpcd` V2 and include the role array.

## Implemented semantics

Only particles with `role == Fluid` participate in the fluid operators:

- body acceleration and streaming;
- boundary reflection / inlet-outlet processing;
- immersed-solid reflection;
- SRC collision deposit and rotation;
- Q6 projection deposit and velocity correction;
- cell-relative thermostat;
- keep-mean-flow correction;
- runtime mass, momentum, temperature and cell-count diagnostics.

`Latent` and `Inactive` particles remain stored and are preserved in V2 dumps,
but are dormant for the current dynamics.

## New helpers

The following helpers are available from `particle_state.h`:

```cpp
ParticleRoleCounts count_particle_roles(const ParticleState& state);
ParticleRoleMasks  build_particle_role_masks(const ParticleState& state);
bool is_fluid_particle(const ParticleState& state, std::size_t i);
bool is_latent_particle(const ParticleState& state, std::size_t i);
bool is_inactive_particle(const ParticleState& state, std::size_t i);
void set_particle_role(ParticleState& state, std::size_t i, ParticleRole role);
void ensure_particle_roles(ParticleState& state, ParticleRole defaultRole);
```

The masks are byte arrays, deliberately simple and OpenMP/GPU-friendly:

```cpp
masks.isFluid[i]
masks.isLatent[i]
masks.isInactive[i]
```

## Runtime diagnostics

`summary_runtime.csv` now includes role counts:

```text
nFluidParticles,nInactiveParticles,nLatentParticles
```

The existing `Np` column remains the total storage size, including dormant
slots. The mass/momentum/temperature diagnostics are fluid diagnostics and only
use active `Fluid` particles.

## Validation

Build and run the baseline smoke:

```bash
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
./scripts/run_resampling_minimal_src_q6_smoke_0110.sh
```

Run the role-specific smoke:

```bash
./scripts/run_particle_roles_smoke_0111.sh
```

The 0111 smoke builds a V2 `.smpcd` state with fluid, latent and inactive
particles, checks that the runtime counts are correct, verifies that total mass
and cell population use only fluid particles, and confirms that latent/inactive
slots are preserved unchanged in the output dump.

## Next milestone

The next patch can add the first resampling deposit workspace:

```text
WeightedRealFluidDeposit
M_c, P_c, U_c, N_c over Fluid particles only
MRelRMS / mass dispersion diagnostics
```

It should still not perform extraction/insertion. The purpose will be to measure
the real fluid mass field independently from the collision-effective deposit that
includes wallVP/immersedVP.

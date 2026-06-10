# 0315l active-prefix capacity-bound cleanup

This patch continues the global active/inactive layout migration:

- `ParticleState::Np` is storage capacity.
- `ParticleState::NactiveFluid` is the logical physical particle count.
- Hot physical loops, hot CUDA upload/download mirrors and hot metadata checks must use the active prefix.
- Full-capacity scans are reserved for explicit pool management, legacy restart/dump compatibility, allocation, and debug validation.

## Static cleanup performed

1. `validate_particle_state()` no longer scans `role[0:Np]` by default.  Full role-value validation is available with:

```bash
export MPCD_VALIDATE_PARTICLE_ROLES_FULLSCAN_0315L=1
```

2. `CudaParticleState::upload_kinematics_with_cached_metadata()` now uploads and hashes metadata only on `[0,NactiveFluid)`.  The previous metadata signature hashed `mass/type/role` over the full inactive reservoir.

3. `CudaParticleState::{upload_positions,upload_velocities,upload_roles,upload_masses_and_roles,download_velocities}` now transfers only `[0,NactiveFluid)` while preserving the full device allocation capacity.

4. Legacy CUDA SRC/thermostat helper role vectors are now active-prefix sized rather than `Np`-sized.

5. Streaming/immersed/inlet-outlet CUDA download mirrors now use `download_active_prefix()` rather than `download_all()` in their standard paths.  The existing wall-simple legacy full-download fallback remains available through its 0315k environment flag.

6. Persistent cell-workspace capacity requests in the SRC collision wrapper are now based on `active_fluid_count(state)`, not `state.Np`.

## Intentionally remaining full-capacity uses

Some `Np` uses are expected and should not be mechanically replaced:

- device allocation capacity (`ensure_capacity(state.Np)`);
- `.smpcd` full legacy read/write compatibility;
- explicit inactive-pool construction / reservoir scans;
- debug full validation paths;
- restart/full-dump legacy paths;
- bounds checks against storage capacity.

Future cleanup should focus on the remaining resampling CUDA pool-management files where `hostMirror.Np` still appears in particle-grid launches. Those are not classic-step hot paths but must eventually become active-prefix/pool-window aware for full Q6/resampling/virial performance.

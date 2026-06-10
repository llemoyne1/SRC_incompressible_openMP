# 0315m capacity-bound audit: hidden per-step scans

## Classification rule

- `PHYSICAL_STEP`: must use `NactiveFluid` / `view.nActiveFluid`.
- `REPEATED_METADATA`: must not scan `Np_total` in the production time loop.
- `POOL_MANAGEMENT`: may use capacity only when it explicitly allocates or finds inactive slots.
- `INIT_RESTART_DUMP`: may use capacity outside the time loop or behind an explicit legacy/debug mode.
- `DEBUG_VALIDATION`: may use capacity only behind an explicit environment flag.

## Finding fixed in 0315m

The remaining long-run scaling after 0315l was consistent with a repeated hidden
`O(Np_total)` metadata pass.  The most general one was:

```cpp
run_src_mpcd_base_step(...)
  validate_particle_state(...)
  ensure_particle_roles(state, ParticleRole::Fluid)
```

`ensure_particle_roles()` always called `refresh_active_fluid_count()`, which
called `compute_active_fluid_count()`, which scanned `role[0:Np_total]`.  This
happened once per step, including pure TG, where no inlet/outlet, wall reservoir,
resampling or virial path is active.

0315m changes `ensure_particle_roles()` into a metadata-only operation when
`role[]` already exists and `NactiveFluid <= Np`.  It only fills roles and sets
`NactiveFluid` when the role array is absent.  The exact full refresh remains
available with:

```bash
export MPCD_ENSURE_PARTICLE_ROLES_FULL_REFRESH_0315M=1
```

This keeps full debugging/recovery semantics available while removing the hidden
per-step scan in the production path.

## Occurrences intentionally not changed here

- `compute_active_fluid_count`, `refresh_active_fluid_count`,
  `has_active_fluid_prefix`, `count_particle_roles`, role masks, and full dump
  helpers remain capacity-based because their purpose is explicit counting,
  validation, filtering, or storage-format compatibility. They should not be in
  the hot production loop except behind debug/legacy options.
- Inlet/outlet inactive-pool scans in `cuda_classic_src_io_resident_0263.cu`
  remain classified as `POOL_MANAGEMENT`; they are still candidates for a later
  free-list/stack implementation, but they do not explain the pure TG residual.
- Resampling CUDA 0295/0296/0297/0304 files still contain capacity scans. They
  are gated diagnostics/experimental resampling paths and are not part of the
  classic scaling benchmark unless their environment flags are enabled.

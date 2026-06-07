# GPU patch 0273 — collision wrapper overhead reduction

## Scope

Patch 0273 keeps the validated classic SRC CUDA resident stack from 0272b and targets the remaining wall/periodic overhead around the collision phase.  The physical SRC collision kernels are unchanged.

The main benchmark remains `poiseuille_wall_full`, because it is the case where the CUDA resident path was still below the CPU reference after 0272b.  The change is nevertheless global to the resident classic collision wrapper and is validated through the full consolidated suite.

## Changes

### 1. Explicit-gamma role-count fast path

`src_collision.cpp` previously called `count_particle_roles(state)` while preparing the CUDA persistent collision configuration, even when `wallVpGamma` was explicitly provided by the validation configuration.  In the classic resident wall validators this host scan is unnecessary and expensive because the host particle state is intentionally not the active compute state.

0273 now infers gamma from host roles only when a virtual-wall/immersed contribution needs an inferred gamma, i.e. when `wallVpGamma <= 0`.  If `wallVpGamma > 0`, the explicit value is used directly.

Fallback/debug control:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_EXPLICIT_GAMMA_ROLE_FASTPATH_0273=1
```

This restores the old host role scan even with an explicit gamma.

### 2. Lazy kernel launch checks in the resident collision wrapper

The shared particle+cell collision path now supports a classic-resident fast mode that avoids a host `cudaGetLastError()` call after every small kernel launch.  It performs one launch-error check before the final synchronization instead.

Enabled by the 0273 runner:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1
```

Fallback:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_LAZY_KERNEL_CHECK_0273=1
```

### 3. Optional setup synchronization skip

The wrapper can also skip the explicit setup `cudaDeviceSynchronize()` after rotation-table setup and counter reset.  Default stream ordering still enforces execution before the subsequent collision kernels, and the final kernel synchronization remains active.

Enabled by the 0273 runner:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1
```

Fallback:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_SETUP_SYNC_0273=1
```

## Preserved constraints

The 0273 validator remains classic-only:

- Q6 disabled only for validation;
- resampling disabled only for validation;
- virial disabled only for validation;
- thermostat disabled only for validation.

The code changes do not prevent future reactivation of Q6 CPU, resampling, virial closure, or a future CUDA thermostat aware of wall/solid/piston/inlet-outlet conditions.  In particular, if future runs need inferred gamma with variable active particle roles, they can leave `wallVpGamma <= 0`, which keeps the old inference behavior.

## Validation

Apply and run:

```bash
bash scripts/run_cuda_classic_src_resident_perf_0273.sh
```

Expected output files:

```text
dev_history/artifacts/gpu_cuda_classic_src_resident_perf_0273/
  cuda_classic_src_resident_perf_validation_0273.csv
  cuda_classic_src_resident_perf_summary_0273.csv
  cuda_classic_src_resident_perf_phases_0273.csv
```

Expected verdict:

```text
periodic_0260             PASS
wall_simple_0261          PASS
solid_rectangle_0262      PASS
piston_mobile_wall_0255   PASS
io_fullface_0263d         PASS
io_segmented_0264         PASS
```

The primary signal to inspect is the wall-simple case, especially `collision_s`, `wall_s`, and the difference between `collision_s` and `collision_total_s`.

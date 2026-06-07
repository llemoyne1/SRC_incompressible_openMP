# GPU patch 0272b — safe collision workspace skip for wall validation

Patch 0272 introduced a classic-resident collision fast path that skipped the host downloads of the post-collision workspace arrays.  The first validation run showed that this was too aggressive for `wall_simple_0261`: the runtime summary still needs the per-cell population vector `cellCountOut` to compute `meanN`, `stdN`, `minN`, and `maxN`.

The failing pattern was:

```text
periodic_0260 PASS
wall_simple_0261 FAIL on resident rows
```

The failure is not a CUDA build failure and not necessarily a collision-physics failure.  It is caused by empty host cell-count diagnostics in the resident wall path.

## Change

When

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
```

is enabled, 0272b now keeps only the lightweight count download:

```text
cellCountOut <- cv.count
```

and still skips the heavier arrays:

```text
cellIdOut
cellMassOut
cellUxOut
cellUyOut
```

This preserves validation summaries while retaining most of the intended 0272 reduction in host-side collision downloads.

## Scope

No SRC collision equation is changed.  No streaming, wall, solid, piston, inlet/outlet, Q6, resampling, virial or thermostat logic is changed.

The fast path remains intended only for classic-only resident performance validation.  For future Q6 CPU, resampling, virial, CPU thermostat, or generalized CUDA thermostat reactivation, leave the 0272 workspace skip disabled unless a dedicated synchronization bridge is implemented.

## Validation

Apply on top of 0272 and rerun:

```bash
bash scripts/run_cuda_classic_src_resident_perf_0272.sh
```

Expected signal:

```text
periodic_0260 PASS
wall_simple_0261 PASS
```

If later suites expose a similar summary dependency, the same safe-count rule should cover them because runtime summary population diagnostics all consume `cellCountOut`.

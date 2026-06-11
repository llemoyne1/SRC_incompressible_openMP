# GPU patch 0322 — shared collision+thermostat rotation/setup reduction

## Objective

Patch 0322 targets the next measured bottleneck after 0321 on the VK-like
periodic wall/circle benchmark.  In the 0321 profile, the CUDA persistent
collision+thermostat block was reduced to approximately:

- upload/setup: about 1.90 s / 10000 steps;
- kernels: about 2.67 s / 10000 steps;
- download/diagnostics: about 1.19 s / 10000 steps.

The remaining upload/setup block was not a float/atomicAdd bottleneck.  The
shared collision+thermostat path still built cos/sin rotation tables on the host,
copied them to the device every step, and forced a setup synchronization.

## Change

The patch ports the already validated 0272/0273 collision-wrapper reductions to
the shared collision+thermostat path:

- `MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1` now generates
  rotation tables on the device in the collision+thermostat path.
- `MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1` avoids per-kernel
  launch-error polling in this path and relies on the final synchronization.
- `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1` avoids the setup
  synchronization before the main kernel batch.

The VK runner enables these flags by default and prints:

```text
[0322-demo] DEVICE_ROTATION_0322=1 LAZY_KERNEL_CHECK_0322=1 SKIP_SETUP_SYNC_0322=1
```

## Files

- `src/cuda_persistent_mpcd_step.cu`
- `scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh`
- `doc/GPU_PATCH_0322_SHARED_THERMOSTAT_ROTATION_SETUP.md`

## Expected validation

Run the same 0317d profiling harness after rebuilding SRC.  Compare against the
0321 profile:

- `srcPersistentUpload_s` should drop from about 1.90 s.
- `srcPersistentTotal_s` should drop from about 5.76 s if the setup reduction is effective.
- `exitCode` must remain 0.
- The wall/circle resident rows should remain active.

If kernel time rises while upload drops, the result should be evaluated on total
`elapsed_s` and `src_collision`, not on `upload_s` alone.

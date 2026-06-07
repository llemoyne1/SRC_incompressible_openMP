# GPU patch 0274 — fused stream+deposit for periodic/wall resident classic SRC

## Scope

Patch 0274 targets the remaining fixed overhead visible after 0273 in the
`force_stream` phase for the validated CUDA resident classic SRC path.

The patch is intentionally narrow:

- periodic resident classic SRC (`MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260`),
- wall-simple resident classic SRC (`MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261`).

It does not modify inlet/outlet, segmented inlet/outlet, immersed solids, piston,
Q6, resampling, virial closure, or the future wall/solid/piston/IO-aware CUDA
thermostat work.

## Main idea

Before 0274, periodic and wall-simple resident cases launched a dedicated
CUDA force/stream kernel, then launched the persistent collision deposit kernel.
The streaming kernel itself was already cheap, but the extra particle traversal
and launch/driver overhead remained visible in the global `force_stream_s`
measurement.

0274 adds an opt-in fused path:

```text
stream + deposit + cell moments -> SRC rotation
```

The force/stream operation is applied inside the collision deposit kernel, before
cell indexing and accumulation.  This preserves the physical order

```text
force/stream -> boundary wrapping/reflection -> deposit -> SRC collision
```

while removing the separate force/stream kernel launch for the two validated
simple cases.

## Environment variables

Enabled by the 0274 performance runner:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
```

Fallback to the pre-0274 separate streaming kernel:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_FUSED_STREAM_DEPOSIT_0274=1
```

0274 keeps the previous validated performance flags active:

```bash
MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM=1
MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1
```

## Safety guards

The fused path is enabled only for classic-only validation runs:

```text
projectionEnable=false
resamplingEnable=false
closedCapacityResponseEnable=false
thermostatEnable=false
```

This is deliberate.  Q6 CPU, resampling, virial/closed-capacity logic and the
future generalized CUDA thermostat may require explicit synchronization points
between force/stream and later operators.  Those paths remain architecturally
preserved by leaving the fused fast path disabled until a dedicated bridge is
implemented.

The immersed-solid resident path is explicitly not fused because its geometry
kernel sits between streaming and collision in the validated stack.

## Validation command

```bash
bash scripts/run_cuda_classic_src_resident_perf_0274.sh
```

Expected manifest:

```text
periodic_0260             PASS
wall_simple_0261          PASS
solid_rectangle_0262      PASS
piston_mobile_wall_0255   PASS
io_fullface_0263d         PASS
io_segmented_0264         PASS
```

## Performance signal to inspect

Primary target:

```text
force_stream_s
```

especially for:

```text
periodic_0260
wall_simple_0261
```

The fused stream work will move into the collision phase, so the expected
successful pattern is:

```text
force_stream_s decreases strongly
collision_s may increase mildly
total wall_s decreases or stays neutral
validation remains PASS
```

# GPU patch 0327 — skip host cellId sentinel fill in classic resident fast path

## Objective

Patch 0327 targets the measured post-0322 residual in the classic SRC CUDA resident Von Karman benchmark.  After 0318b--0322, the remaining `srcPersistentDownload_s` is no longer dominated by large device-to-host physical state downloads.  One visible residual is host-side churn in the `FAST_THERMOSTAT_DIAG_0321` path, where `cellIdOut.assign(n, -1)` still fills one integer per active particle every step although the strict classic resident path has no CPU Q6/resampling/virial continuation after the fused GPU collision+thermostat step.

The patch adds a guarded fast path:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
```

When this flag is active, and only when the existing classic resident + fast thermostat diagnostics guards are also active, the code clears `cellIdOut` instead of filling it with `n` sentinel values.

## Safety boundary

The shortcut is deliberately restricted to:

- classic resident CUDA families;
- `FAST_THERMOSTAT_DIAG_0321=1`;
- the runner path where Q6/resampling/virial/closed-capacity are not executed after the fused GPU collision+thermostat step.

Hybrid validation remains handled by the 0326d architecture:

```text
CUDA persistent collision only -> CPU Q6 / resampling / virial -> CPU thermostat
```

That path uses `srcClassicCudaModeEnable=false` and does not rely on this classic fused collision+thermostat shortcut.

## Runtime controls

Default in the VK demo runner:

```bash
SRC_GPU_SKIP_HOST_CELLID_FILL_0327=1
```

Disable for debugging or conservative host-vector shape:

```bash
SRC_GPU_SKIP_HOST_CELLID_FILL_0327=0
```

Low-level disable flag:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_HOST_CELLID_FILL_0327=1
```

## Expected validation

Primary benchmark:

```bash
SRC_BUILD=1 VKKH_BUILD=0 \
WARMUP=0 STEPS=10000 REPEATS=1 INACTIVE_SLOTS=100000 \
RUN_SRC_PERIODIC=1 RUN_SRC_IO=0 RUN_VKKH=1 \
bash scripts/run_gpu_phase_profile_0317d.sh
```

Expected log line:

```text
[0327-demo] SKIP_HOST_CELLID_FILL_0327=1
```

Primary measured criterion:

```text
srcPersistentDownload_s should decrease relative to the clean 0322/0325b baseline (~1.2 s / 10000 steps).
```

Strict non-regression check after performance validation:

```bash
SRC_BUILD=0 \
NX=32 NY=32 STEPS=80 GAMMA=20 INACTIVE_SLOTS=100000 \
bash scripts/run_gpu_nonregression_q6_resampling_virial_0326d.sh
```

Expected strict result:

```text
strict_fail=0
working tree OK: no 0325
```

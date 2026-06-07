# GPU patch 0271 — wall/periodic resident fixed-overhead reduction

## Scope

Patch 0271 is a performance-only pass for the validated CUDA resident classic SRC path.
It targets the fixed per-step overhead observed after 0270 on the periodic and wall-simple
resident streaming phases.

The patch does **not** change the physical validation scope:

- Q6 remains CPU and is disabled only in the classic-only validators.
- Resampling remains disabled only in the classic-only validators and must remain reactivable.
- Virial closure is not modified.
- The CUDA thermostat generalization for wall/solid/piston/inlet-outlet cases remains a separate future chantier.

## Changes

### 1. Opt-in asynchronous resident streaming

The periodic 0245 and wall-simple 0246 resident streaming functions now support an opt-in 0271 mode:

```bash
MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM=1
```

When this mode is active and the run is resident without an immediate full download, the streaming kernel launch is checked with `cudaGetLastError()` but the explicit `cudaDeviceSynchronize()` is skipped. Ordering is preserved by the legacy default stream: the following CUDA work in the collision path remains ordered after the streaming kernel.

Fallback:

```bash
MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_DISABLE_ASYNC_STREAM=1
```

### 2. Lightweight wall diagnostics

Wall-simple streaming previously allocated, zeroed, copied and freed four device diagnostics buffers at each step. In 0271, the performance runner enables:

```bash
MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS=1
```

In that mode the wall streaming kernel accepts null diagnostic pointers and skips the per-step hit/max-reflection/failure counters. This is compatible with the 0270 resident wall path because the generic host boundary pass is already skipped and `BoundaryDiagnostics` is intentionally zero for this validated subset.

Fallback:

```bash
MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_DISABLE_FAST_DIAGNOSTICS=1
```

## Validation runner

Use:

```bash
bash scripts/run_cuda_classic_src_resident_perf_0271.sh
```

Outputs:

```text
dev_history/artifacts/gpu_cuda_classic_src_resident_perf_0271/
  cuda_classic_src_resident_perf_validation_0271.csv
  cuda_classic_src_resident_perf_summary_0271.csv
  cuda_classic_src_resident_perf_phases_0271.csv
```

Expected signal:

- all consolidated suites remain `PASS`;
- `poiseuille_wall_full` total resident time decreases;
- `force_stream_s` decreases for periodic/wall, with some time possibly shifting into the following CUDA collision phase because the explicit stream synchronization is removed.

## Non-goals

- No Q6 CUDA implementation.
- No resampling reactivation.
- No virial or thermostat changes.
- No change to inlet/outlet reservoir pool logic from 0268/0269a.

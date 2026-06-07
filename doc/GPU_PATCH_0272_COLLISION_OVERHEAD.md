# GPU patch 0272 — collision-side overhead reduction for CUDA resident classic SRC

## Scope

Patch 0272 is a performance-only continuation of the validated classic SRC CUDA resident stack through 0271.  It does not change the SRC collision equations, the streaming/boundary stack, the inlet/outlet reservoir logic, or any validation tolerances.

The patch targets residual overheads visible in the 0271 performance profile, especially in `collision_s`, `collision_upload_s` and `collision_download_s` for the resident classic-only validators.

## New opt-in controls

The 0272 performance runner enables three new collision-side switches:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=1
```

Fallbacks are available independently:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_DEVICE_ROTATION_0272=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_WORKSPACE_DOWNLOAD_0272=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_FINAL_SYNC_0272=1
```

## Device-side rotation tables

The shared persistent collision path previously built `cosA` and `sinA` on the CPU every step and uploaded both arrays.  In 0272, when enabled, `fill_rotation_tables_persistent_0272_kernel` constructs the same per-cell random sign table on the GPU using the same SplitMix64 rule as the host path:

```cpp
splitmix64(rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^ cell)
```

This reduces host work and host-to-device traffic without changing the per-cell rotation signs.

## Classic-only workspace download skip

The validated resident classic SRC performance cases have Q6, resampling, virial and thermostat disabled.  In those cases the CPU collision workspace arrays are not consumed between collision and the final summary synchronization.  Patch 0272 can therefore skip the large host downloads of:

```text
cellId, cellCount, cellMass, cellUx, cellUy
```

while retaining the scalar collision counters:

```text
fluidCounter, rotatedCounter, invalidCounter
```

This keeps strict invalid-cell checking active.  The CPU collision workspace vectors are cleared in the fast path so that accidental downstream CPU consumers fail fast rather than reading stale arrays.

## Architecture constraints preserved

The 0272 fast workspace skip is intentionally activated only by the performance runner for classic-only validation.  It is not a general replacement for the CPU continuation path.

For future reactivation of Q6 CPU, resampling, CPU thermostat or other host-side consumers, leave `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272` disabled unless a dedicated synchronization bridge has been implemented.

The following remain explicitly preserved as future work:

- Q6 CPU reactivation after resident CUDA classic SRC;
- resampling reactivation after resident CUDA classic SRC;
- virial path reactivation;
- CUDA thermostat wall/solid/piston/inlet-outlet aware, as a separate chantier.

## Validation runner

Run:

```bash
bash scripts/run_cuda_classic_src_resident_perf_0272.sh
```

Expected outputs:

```text
dev_history/artifacts/gpu_cuda_classic_src_resident_perf_0272/
  cuda_classic_src_resident_perf_validation_0272.csv
  cuda_classic_src_resident_perf_summary_0272.csv
  cuda_classic_src_resident_perf_phases_0272.csv
```

Expected signal:

- all suites remain `PASS`;
- `collision_download_s` decreases in resident cases;
- `collision_upload_s` may decrease if the device rotation table path dominates over the previous CPU build/upload path;
- physical summaries remain unchanged within existing validator tolerances.

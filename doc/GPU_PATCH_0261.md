# GPU patch 0261 — wall-simple classic SRC CUDA resident mode

## Goal

Patch 0261 extends the resident classic SRC CUDA idea from 0260 to the static wall-simple Poiseuille subset.

The scope is deliberately narrower than the final production target because the fused CUDA thermostat is not yet wall-aware.  Therefore, 0261 validates a resident wall-simple classic SRC chain **without thermostat**:

```text
wall-simple streaming CUDA
→ persistent cell deposit + SRC collision CUDA
→ no Q6/Q9
→ no virial closed-capacity kick
→ no resampling
→ no thermostat for this first wall-resident benchmark
→ host download only at summaries/final diagnostics
```

This isolates the performance effect of eliminating per-step host/device transfers for streaming + collision in the wall-simple case, without mixing in the known unresolved thermostat-wall issue.

## Runtime switches

```bash
MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=1
MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
SRC_CLASSIC_CUDA_MODE_ENABLE=true
PROJECTION_ENABLE=false
RESAMPLING_ENABLE=false
THERMOSTAT_ENABLE=false
```

## Files changed

```text
src/cuda_streaming_wall_simple_0246.cu
src/cuda_persistent_mpcd_step.cu
src/src_mpcd_base.cpp
src/main_src_mpcd_base.cpp
scripts/build_src_mpcd_cuda_0261.sh
scripts/run_cuda_classic_src_wall_resident_0261.sh
doc/GPU_PATCH_0261.md
```

## Validation

Run:

```bash
bash scripts/run_cuda_classic_src_wall_resident_0261.sh
```

Default validation:

```text
poiseuille_wall_full
64x64_s300
128x128_s300
```

Modes compared:

```text
cpu_classic_wall_no_thermostat
0257_wall_cuda_download_each_step_no_thermostat
0261_wall_resident_classic_cuda_no_thermostat
```

Expected result:

```text
verdict=PASS
failed_metrics=0
```

The output CSV is:

```text
dev_history/artifacts/gpu_cuda_classic_src_0261/cuda_classic_src_wall_resident_0261.csv
```

## Important limitation

0261 intentionally does **not** claim to solve the wall-aware CUDA thermostat.  That remains a separate future work item.  Once the thermostat CUDA path is made wall/solid/piston/inlet-outlet aware, it can be reintroduced into this resident wall chain.

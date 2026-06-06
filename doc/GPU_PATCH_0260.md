# GPU patch 0260 — periodic classic SRC CUDA resident mode

## Goal

Patch 0260 adds a deliberately narrow performance mode for the classic, compressible SRC/MPCD stack with periodic boundary conditions only.

The validated 0259 classic mode had the right physics switch:

```text
projectionEnable=false
resamplingEnable=false
srcClassicCudaModeEnable=true
```

but it still used a hybrid CUDA path with host/device transfers after the periodic streaming and after collision/thermostat. Patch 0260 keeps the same physical operator order while making the periodic classic CUDA path resident over a time step sequence:

```text
periodic streaming CUDA
→ persistent cell deposit + SRC collision CUDA
→ deterministic cell-relative thermostat CUDA
→ no Q6/Q9
→ no virial closed-capacity kick
→ no resampling
→ host download only at summaries/dumps
```

## Scope

Supported in 0260:

- `tg_periodic_full`
- periodic x/y boundaries
- classic SRC mode
- deterministic `cell_relative_rescale` thermostat
- no Q6/Q9
- no resampling
- no virial/capacity kick

Explicitly out of scope:

- walls
- immersed solids
- piston/mobile wall
- full-face or segmented inlet/outlet
- Q6/Q9 GPU
- resampling in classic mode

Those families remain available through earlier validated hybrid paths, but not through the new resident 0260 path.

## New runtime switches

```bash
MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
```

`MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1` activates the resident behavior. The code also checks that the simulation is a true periodic classic case before preserving the shared CUDA state across steps.

## Files changed

```text
include/cuda_shared_particle_state_0251.h
src/cuda_shared_particle_state_0251.cpp
src/cuda_streaming_periodic_0245.cu
src/cuda_persistent_mpcd_step.cu
src/src_collision.cpp
src/src_mpcd_base.cpp
src/main_src_mpcd_base.cpp
scripts/build_src_mpcd_cuda_0260.sh
scripts/run_cuda_classic_src_periodic_resident_0260.sh
doc/GPU_PATCH_0260.md
```

## Validation

Run:

```bash
bash scripts/run_cuda_classic_src_periodic_resident_0260.sh
```

Default cases:

```text
tg_periodic_full
64x64_s300
128x128_s300
```

Modes compared:

```text
cpu_classic
0259_periodic_fused_download_each_step
0260_periodic_resident_classic_cuda
```

Expected result:

```text
verdict=PASS
failed_metrics=0
```

The CSV is written to:

```text
dev_history/artifacts/gpu_cuda_classic_src_0260/cuda_classic_src_periodic_resident_0260.csv
```

## Performance interpretation

The expected improvement should be visible primarily in:

```text
collisionUploadSeconds
collisionDownloadSeconds
collisionTotalSeconds
```

The global wall-time may still be affected by validation overhead and summary downloads, but 0260 is the first mode where the classic periodic CUDA step is genuinely resident between summaries.

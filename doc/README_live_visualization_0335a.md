# 0335a — Optional live visualization for SRC/MPCD CUDA runs

This patch adds an optional in-situ live visualization path for qualitative physical inspection of SRC/MPCD simulations.  It is designed for the `SRC_GPU-VIZ` workflow and is disabled by default.

## Build

The normal CUDA build still works without OpenGL/GLFW and compiles a no-op visualization module.  To enable the actual windowed renderer:

```bash
MPCD_ENABLE_LIVE_VIS=1 \
OUT=build/src_mpcd_base_cuda_livevis_0335a \
bash scripts/build_src_mpcd_cuda_0315b.sh
```

The live renderer uses GLFW/OpenGL.  On Ubuntu/WSL this may require:

```bash
sudo apt install libglfw3-dev libgl1-mesa-dev
```

## Runtime controls

The renderer is enabled by environment variables, not by `.kv` parameters, so it does not change existing simulation configurations.

```bash
SRC_LIVE_VIS_ENABLE=1
SRC_LIVE_VIS_FIELD=ux              # ux, uy, speed, vorticity, mass, density
SRC_LIVE_VIS_EVERY=10
SRC_LIVE_VIS_NX=600
SRC_LIVE_VIS_NY=160
SRC_LIVE_VIS_ALPHA=1.0
SRC_LIVE_VIS_CLIP=-1               # auto scale if <= 0
SRC_LIVE_VIS_SMOOTH_PASSES=0
SRC_LIVE_VIS_WINDOW_SCALE=1
SRC_LIVE_VIS_VSYNC=0
```

The visualization downloads only a role-filtered active-fluid host mirror when the CUDA shared particle state is fresh.  This keeps the inactive reservoir out of the visualization path.

## Example

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-VIZ

MPCD_ENABLE_LIVE_VIS=1 \
OUT=build/src_mpcd_base_cuda_livevis_0335a \
bash scripts/build_src_mpcd_cuda_0315b.sh

SRC_BIN=build/src_mpcd_base_cuda_livevis_0335a \
MODE=classic \
STEPS=20000 \
SRC_LIVE_VIS_FIELD=ux \
SRC_LIVE_VIS_EVERY=10 \
bash scripts/run_vk_full_periodic_livevis_0335a.sh
```

For resampling inspection:

```bash
SRC_BIN=build/src_mpcd_base_cuda_livevis_0335a \
MODE=resampling \
INACTIVE_SLOTS=750000 \
SRC_LIVE_VIS_FIELD=vorticity \
SRC_LIVE_VIS_EVERY=20 \
bash scripts/run_vk_full_periodic_livevis_0335a.sh
```

## Scope

This is deliberately a first robust CPU-fallback live visualization layer.  It avoids CUDA/OpenGL interop and therefore works across the existing resident CUDA families by synchronizing a compact active-fluid host mirror only at visualization frames.  A later 0335b patch can move the accumulation/rendering to CUDA/OpenGL interop if needed.


## 0335c notes: field readability

For particle-noise dominated MPCD fields, use a coarse visualization grid and temporal smoothing.  Good starting points are:

```bash
SRC_LIVE_VIS_NX=300
SRC_LIVE_VIS_NY=80
SRC_LIVE_VIS_ALPHA=0.08
SRC_LIVE_VIS_SMOOTH_PASSES=1
SRC_LIVE_VIS_QUANTILE=0.995
```

For stronger color contrast, set `SRC_LIVE_VIS_GAIN=2` or use an explicit clip, for example `SRC_LIVE_VIS_CLIP=0.2` for `ux`.

For resampling runs, the script defaults to `SRC_LIVE_VIS_FORCE_HOST_MIRROR=1`, which is slower but helps keep the host mirror moving when resampling invalidates the shared CUDA resident state.


## 0335d notes: resampling host-mirror visualization

If a resampling run logs `source=host_state_fallback` and the image is frozen, the CUDA resampling path has invalidated the shared 0251 compact-fluid mirror used by the live renderer.  The script therefore enables a slower visual-inspection mode by default for `MODE=resampling`:

```bash
SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=1
```

This disables the fully-resident shared particle path for that visual run and forces host-visible updates.  It is intended only for qualitative visual inspection, not for performance measurement.  Set `SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=0` to return to the fastest resident configuration.

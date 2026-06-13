# 0337a — CUDA field renderer for live visualization

This patch adds a compromise renderer between the CPU fallback and a full CUDA/OpenGL PBO path. CUDA accumulates the selected field directly from resident device particle arrays into a small visualization grid, produces an RGBA image on device, and downloads only that RGBA image to the host for OpenGL display.

For a 300x80 visualization this transfers about 96 kB per frame instead of downloading the full particle state.

Default in `MODE=resampling`:

```bash
SRC_LIVE_VIS_CUDA_FIELD=1
SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=0
SRC_LIVE_VIS_CUDA_SNAPSHOT=0
```

Expected log with `SRC_LIVE_VIS_LOG_SOURCE=1`:

```text
[livevis0335] step=... source=cuda_field_0337 particles=... activeFluid=... total_s=...
```

Fallbacks remain available:

```bash
SRC_LIVE_VIS_CUDA_FIELD=0 SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=1
```

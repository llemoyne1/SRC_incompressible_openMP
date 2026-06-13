# 0336a — CUDA snapshot for live visualization after resampling

This patch adds a visualization/debug download path that ignores the 0251 fresh flag and downloads a compact active-fluid snapshot directly from the process-local shared `CudaParticleState`.

The intent is to make `MODE=resampling` live visualization move without enabling the slow permanent host mirror.

Default in `scripts/run_vk_full_periodic_livevis_0335a.sh` for resampling:

```bash
SRC_LIVE_VIS_CUDA_SNAPSHOT=1
SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=0
```

Expected log:

```text
[livevis0335] step=... source=cuda_snapshot_fluid_0336 Np=... NactiveFluid=...
```

Fallback remains available:

```bash
SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=1
```

That fallback is slower because it forces host-visible updates.

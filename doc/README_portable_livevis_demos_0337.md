# 0337 portable live-visualization demo scripts

This archive refreshes the five portable demo scripts for the SRC_GPU-VIZ live-visualization branch.

Common changes:

- default binary: `build/src_mpcd_base_cuda_livevis_0337d`;
- build helper priority: `scripts/build_src_mpcd_cuda_0315b.sh`;
- build uses `MPCD_ENABLE_LIVE_VIS=1` by default;
- live visualization is enabled by default through explicit `LIVE_VIS_*` variables;
- runtime exports the corresponding `SRC_LIVE_VIS_*` variables;
- CUDA field renderer is enabled by default: `SRC_LIVE_VIS_CUDA_FIELD=1`;
- resampling host mirror is disabled by default: `SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=0`;
- logging is quiet by default: `SRC_LIVE_VIS_LOG_SOURCE=0`.

Per-case default fields:

- Taylor--Green hole: `vorticity`;
- Von Karman cylinder: `vorticity`;
- Poiseuille: `ux`;
- backward step: `speed`;
- segmented box x=0: `speed`.

Override example:

```bash
LIVE_VIS_FIELD=ux LIVE_VIS_GAIN=0.5 LIVE_VIS_CLIP=0.5 \
  bash scripts/run_portable_von_karman_resampling_0337_livevis.sh
```

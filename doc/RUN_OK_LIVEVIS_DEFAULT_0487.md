# 0487 — run_ok livevis binary selection

## Purpose

After 0485, the `run_ok_*.sh` scripts defaulted to the latest production resident binary (`..._0484`). That binary is intentionally not guaranteed to be linked with GLFW/OpenGL live visualization support. Therefore `LIVE_VIS_ENABLE=1` could be exported while no window was opened because the launched executable was not the livevis build.

## Change

The common runner now selects the default binary according to the visualization intent:

- `LIVE_VIS_ENABLE=1` selects `SRC_MPCD_LIVEVIS_BIN_0434`, defaulting to `build/src_mpcd_base_cuda_q6_resident_livevis_0486`.
- `LIVE_VIS_ENABLE=0` selects `SRC_MPCD_DEFAULT_BIN_0434`, defaulting to `build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0484`.

If auto-build is enabled and a livevis binary is missing/stale, the runner prefers `scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh` when present.

## Manual overrides

```bash
BIN=build/custom_binary bash scripts/run_ok_tg.sh
SRC_MPCD_LIVEVIS_BIN_0434=build/src_mpcd_base_cuda_q6_resident_livevis_0486 bash scripts/run_ok_tg.sh
LIVE_VIS_ENABLE=0 SRC_MPCD_DEFAULT_BIN_0434=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0484 bash scripts/run_ok_tg.sh
```

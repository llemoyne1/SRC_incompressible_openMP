# SRC_GPU 0487 — run_ok livevis default binary

This patch makes the `run_ok_*.sh` suite select the livevis-capable resident binary when `LIVE_VIS_ENABLE=1`.

Expected default behavior after 0487:

- visual runs launch `build/src_mpcd_base_cuda_q6_resident_livevis_0486`;
- non-visual runs launch `build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0484`;
- `BIN=...` still overrides everything.

Smoke command:

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_livevis_0486 \
LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=1 \
RUN_MODES='src-resampling' NX=64 NY=64 GAMMA=40 STEPS=100 SUMMARY_EVERY=20 LIVE_PROGRESS=1 \
bash scripts/run_ok_tg.sh
```

Then check the log for livevis initialization, or confirm a GLFW/OpenGL error if the display stack is the issue rather than the binary.

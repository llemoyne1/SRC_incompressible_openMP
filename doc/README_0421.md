# 0421 files-only patch

Adds optional livevis hold-on-exit.

Run with:

```bash
SRC_LIVE_VIS_HOLD_ON_EXIT=1 bash scripts/your_run_script.sh
```

At the end of the run, the livevis window stays open until the user closes it or presses `Esc`/`Q`.  Default behavior is unchanged when the flag is not set.

Build:

```bash
MPCD_ENABLE_LIVE_VIS=1 OUT=build/src_mpcd_base_cuda_q6_resident_0400_livevis bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```

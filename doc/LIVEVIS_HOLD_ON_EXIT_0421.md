# 0421 — Livevis hold-on-exit

This patch adds an optional run-end hold for the live visualization window.

## Usage

```bash
SRC_LIVE_VIS_HOLD_ON_EXIT=1 bash scripts/your_run_script.sh
```

or equivalently:

```bash
MPCD_LIVE_VIS_HOLD_ON_EXIT=1 bash scripts/your_run_script.sh
```

Default behavior is unchanged: if neither environment variable is set, the window closes when the binary exits.

## Behavior

At the end of `main_src_mpcd_base`, after printing:

```text
[src_mpcd_base] done
```

if livevis is active and the hold flag is true, the code keeps the GLFW window open and continues processing window events.  Exit by closing the window or pressing `Esc` or `Q`.

The last rendered frame remains visible.  No simulation work is performed during the hold.

## Files changed

- `src/live_visualization_0335.h`
- `src/live_visualization_0335.cpp`
- `src/main_src_mpcd_base.cpp`

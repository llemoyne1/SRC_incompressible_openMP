# Livevis runtime controls 0341b — portable scripts

This script-only update propagates the 0341a `livevis_control.kv` mechanism to the portable live visualization scripts.

Each script now supports:

```bash
LIVE_VIS_CONTROL_ENABLE=1
LIVE_VIS_CONTROL_FILE=/optional/custom/path/livevis_control.kv
LIVE_VIS_CONTROL_EVERY=1
LIVE_VIS_CONTROL_LOG=1
```

If `LIVE_VIS_CONTROL_FILE` is empty, the script creates a mode-local file:

```text
<run_root>/livevis_control.kv
```

with:

```text
field = ${LIVE_VIS_FIELD}
clip = ${LIVE_VIS_CLIP}
gain = ${LIVE_VIS_GAIN}
smoothPasses = ${LIVE_VIS_SMOOTH_PASSES}
```

The binaire 0341a consumes this file at runtime. The script changes are visualization-only and do not modify solver parameters, Q6, resampling, virial closure, or host/device authority.


## 0341c clarification

The scripts now explicitly export the user-facing control variables (`LIVE_VIS_CONTROL_ENABLE`, `LIVE_VIS_CONTROL_FILE`, `LIVE_VIS_CONTROL_EVERY`, `LIVE_VIS_CONTROL_LOG`) and the resolved per-mode path (`LIVE_VIS_CONTROL_FILE_EFFECTIVE`). The binary still consumes `SRC_LIVE_VIS_CONTROL_FILE`, exported from the effective path.


## 0341d path controls

`LIVE_VIS_CONTROL_FILE_EFFECTIVE` is an internal resolved path and should not be set manually. To choose the file location, use one of the user-facing options:

```bash
LIVE_VIS_CONTROL_FILE=./livevis_control.kv
```

or:

```bash
LIVE_VIS_CONTROL_DIR=./livevis_controls
LIVE_VIS_CONTROL_BASENAME=vk_io.kv
```

Resolution order is:

1. `LIVE_VIS_CONTROL_FILE` if non-empty;
2. `LIVE_VIS_CONTROL_DIR` + `LIVE_VIS_CONTROL_BASENAME` if `LIVE_VIS_CONTROL_DIR` is non-empty;
3. `<run_root>/<LIVE_VIS_CONTROL_BASENAME>` otherwise.

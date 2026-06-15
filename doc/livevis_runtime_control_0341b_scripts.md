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

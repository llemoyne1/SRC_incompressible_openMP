# Live visualization colormap control 0342a

This VIZ-only update adds runtime colormap control to the live visualization path.

Supported values in `livevis_control.kv`:

```text
colormap = blue_red
colormap = gray
colormap = thermal
```

Aliases:

- `gray`, `grey`, `grayscale`, `greyscale` -> `gray`
- `thermal`, `heat`, `hot` -> `thermal`
- all other values fall back to `blue_red`

Example:

```text
field = speed
colormap = thermal
clip = 0.5
gain = 2.0
smoothPasses = 4
```

The CUDA field renderer reads `SRC_LIVE_VIS_COLORMAP` at render time. The 0341 runtime control parser updates this environment variable inside the process when the control file is reloaded, so colormap changes can be applied without restarting the simulation.

This feature affects only scalar-to-RGBA mapping. It does not modify solver state, particle state, Q6, resampling, virial terms, or host/device authority.

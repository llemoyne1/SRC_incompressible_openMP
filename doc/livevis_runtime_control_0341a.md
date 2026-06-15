# Live visualization runtime controls 0341a

This VIZ-only helper adds a low-risk runtime control file for the live visualization layer. It does not modify the solver state and must remain read-only with respect to particle data.

## Control file

The portable VK livevis classic script creates a default control file when `LIVE_VIS_CONTROL_ENABLE=1`:

```text
runs/VK_classic_small_time/<mode>/classic/livevis_control.kv
```

or a custom path can be supplied with:

```bash
LIVE_VIS_CONTROL_FILE=/path/to/livevis_control.kv
```

Supported keys are:

```text
field = vorticity
clip = -20
gain = 0.5
smoothPasses = 10
```

The file is reloaded on live draw opportunities. `LIVE_VIS_CONTROL_EVERY` controls the reload stride, and `LIVE_VIS_CONTROL_LOG=1` logs changes.

## Scope

The CUDA field path consumes the current controls before calling `cuda_live_field_render_shared_0337`. The CPU fallback path also consumes the same controls before rendering.

No solver arrays, particle state, Q6, resampling, thermostat or virial quantities are modified by this feature. Physics validation should still compare final dumps bit-by-bit when changing livevis code.

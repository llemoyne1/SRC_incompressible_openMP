# 0432a — strict livevis-driven filtered field recording

This patch adds an observation-only filtered field recorder to the strict `feature/cuda-resident-q6` code path.
It does not unlock any solver combination: existing guards for Q6, chi, resampling, Brinkman/Darcy and resident CUDA paths remain unchanged.

## Activation

The recorder is inert unless one of these environment flags is enabled:

```bash
export MPCD_FILTERED_FIELD_RECORDING_0432=1
# or
export SRC_FILTERED_FIELD_RECORDING_0432=1
```

When disabled, no additional host-state download is requested and the validated strict execution path is unchanged.

The recorder is driven by the same control file used by livevis:

```bash
export SRC_LIVE_VIS_CONTROL_FILE=./livevis_control.kv
```

## Control keys

Example `livevis_control.kv`:

```kv
field = Y1
colormap = thermal
clip = -1
gain = 1.0
smoothPasses = 2

liveGridNx = 384
liveGridNy = 96

filterMode = ema
filterTau = 0.002
filterSampleEvery = 1

recordEnable = true
recordSession = injection_front_Y1_384x96
recordFields = current,rho1,rho2,Y1,ux,uy
recordEvery = 25
recordFormat = f32
```

Supported recording fields in 0432a:

```text
rho, density, mass
rho1, rho2
Y1, Y2
ux, uy, speed
N, N1, N2
current
```

`current` is resolved when recording starts and is replaced by the currently selected livevis field.
Unsupported fields abort session start with a clear error.

## Session locking rule

Before recording starts, `liveGridNx/liveGridNy`, `field`, `smoothPasses`, `filterTau`, `filterSampleEvery`, `recordFields`, and `recordEvery` can be edited through `livevis_control.kv`.

At the transition `recordEnable = false -> true`, the recorder locks:

```text
liveGridNx/liveGridNy
recordFields
recordEvery
recordFormat
filterMode/filterTau/filterSampleEvery
smoothPasses
recordSession
```

During a recording session, changes to grid, fields, cadence or filter are ignored and a warning is printed. To change them, set:

```kv
recordEnable = false
```

then edit the controls and start a new session with `recordEnable = true`.

## Outputs

For a session named `injection_front_Y1_384x96`, outputs are written under:

```text
<outputDir>/recordings/injection_front_Y1_384x96/
```

Files:

```text
manifest.kv
session_end.kv
timeline.csv
step_0000012000_field_y1.f32
step_0000012000_field_rho1.f32
...
```

The field files are raw `float32`, row-major, one file per field and per recorded step. The grid size and field order are recorded in `manifest.kv`.

## Conservative filtering rule

The recorder deposits conservative quantities on the live observation grid:

```text
rho, rho1, rho2, px, py, N, N1, N2
```

The EMA filter is applied to these conservative fields. Derived fields are then reconstructed:

```text
Y1 = rho1 / rho
Y2 = rho2 / rho
ux = px / rho
uy = py / rho
speed = sqrt(ux^2 + uy^2)
```

This is required for unequal particle masses: velocities are barycentric, not number-averaged.

## Live grid resizing

`liveGridNx` and `liveGridNy` can be changed from `livevis_control.kv` during preview. The livevis buffers are reallocated and the live display filter is reset.

If `recordEnable = true`, live grid changes are ignored until recording is stopped.

## Modified files

```text
include/filtered_field_recorder_0432.h
src/filtered_field_recorder_0432.cpp
src/live_visualization_0335.h
src/live_visualization_0335.cpp
src/main_src_mpcd_base.cpp
scripts/build_src_mpcd_cuda_q6_resident_0400.sh
scripts/build_src_mpcd_cuda_0315b.sh
```

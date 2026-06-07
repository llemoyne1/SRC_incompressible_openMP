# GPU patch 0264 — classic SRC CUDA resident segmented inlet/outlet

## Scope

Patch 0264 extends the correctness-first classic SRC CUDA resident path from 0263d
(full-face inlet/outlet) to the conservative segmented inlet/outlet validation subset:

- validation case: `segmented_u_turn_full`;
- topology: inlet and outlet segments on the left face, with wall-like uncovered
  portions of the same face;
- hard-cell inlet reservoir remains resident on the shared CUDA particle state;
- dynamic GPU append remains disabled: the validator preallocates inactive slots;
- Q6, resampling, virial/capacity response, and thermostat are disabled in this
  validator only.

The point of 0264 is to validate residence and numerical equivalence for segmented
open boundaries before optimizing the reservoir kernel.

## New runtime flag

```bash
MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
```

The strict freshness guard is enabled by the runner:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
```

## Architecture constraints preserved

0264 deliberately does **not** make Q6 or resampling structurally impossible.  The
support guard rejects them only for this validation subset because the current
validated path is classic-only.  The host/GPU freshness protocol remains the same:
future patches can insert explicit synchronization points for

```text
GPU classic resident stream/boundary/collision
→ minimal host download for Q6 CPU and/or resampling CPU
→ Q6/resampling CPU continuation
→ upload/refresh shared CUDA state for the next resident CUDA phase
```

The thermostat is also left as a separate future chantier.  The periodic fused
thermostat from 0259 is not generalized here to wall/solid/piston/inlet-outlet
cases.

## Implementation notes

- `src/cuda_classic_src_io_resident_0263.cu` now carries both 0263 full-face and
  0264 segmented resident entry points.
- The segmented hard reservoir uses the compact relative segment declarations
  already parsed in `SimulationParams`.
- Particles crossing a segmented interval are removed according to the segment
  mode (`inlet` backflow or `outlet`).
- Particles crossing uncovered portions of the segmented face are reflected as
  wall-like boundaries on GPU, so the CPU boundary pass is skipped in resident
  mode.
- Reservoir cells are inserted only for inlet segments, using each segment's
  prescribed velocity, particle type, and particle mass.
- `src/src_collision.cpp` admits the 0264 static all-wall segmented box as a
  persistent CUDA collision subset when the 0264 resident flag is active.

## Validation command

```bash
bash scripts/run_cuda_classic_src_io_segmented_resident_0264.sh
```

Expected criterion:

```text
verdict=PASS
failed_metrics=0
```

The runner defaults to:

```text
64:64:300 and 128:128:300
CASE=segmented_u_turn_full
PROJECTION_ENABLE=false
RESAMPLING_ENABLE=false
THERMOSTAT_ENABLE=false
INLET_THERMAL_NOISE=0
```

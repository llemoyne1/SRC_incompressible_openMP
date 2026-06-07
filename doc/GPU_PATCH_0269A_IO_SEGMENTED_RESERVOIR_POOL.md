# GPU patch 0269a — segmented inlet/outlet resident reservoir pool

## Scope

Patch 0269a finalizes the inlet/outlet resident performance sequence by applying
the inactive-slot pool strategy introduced in 0268 to the segmented inlet/outlet
hard-cell reservoir path.

The patch does not change the physical model or the validation scope. The
classic-only performance validators still disable Q6, resampling, virial and the
CUDA thermostat. This is only a validation choice: the code path must remain
compatible with future reactivation of Q6 on CPU, resampling, virial closure and
a wall/solid/piston/inlet-outlet-aware CUDA thermostat.

## Main change

Before 0269a, the segmented resident path used:

- a parallel particle boundary scan from 0267;
- a serial hard-cell reservoir insertion kernel from 0267.

Patch 0269a keeps the parallel particle boundary scan and replaces the segmented
reservoir insertion with:

1. a parallel marking pass of inactive particle slots;
2. a Thrust exclusive scan;
3. a compact inactive-slot index pool;
4. a segmented reservoir insertion kernel with one CUDA thread per active
   segmented reservoir cell.

The full-face 0268 pool path is left unchanged and remains a non-regression case.

## New CUDA pieces

In `src/cuda_classic_src_io_resident_0263.cu`:

- `segmented_reservoir_cell_count_host_0269`
- `map_segmented_reservoir_cell_device_0269`
- `io_segmented_hard_reservoir_insert_pool_kernel_0269`

The shared pool insertion helper from 0268 now also accepts a segment index. This
allows segment-specific inlet velocity, mass and particle type to be preserved.

## Fallbacks

The complete pre-0267 serial path remains available with:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY=1
```

The 0269a segmented pool can be disabled independently with:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_DISABLE_SEGMENTED_POOL=1
```

When this variable is set, segmented inlet/outlet falls back to the 0267 serial
reservoir insertion while keeping the 0267 parallel boundary particle scan.

The full-face 0268 pool fallback remains:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_DISABLE_POOL=1
```

## Validation / profiling

Build:

```bash
bash scripts/build_src_mpcd_cuda_0269a.sh
```

Performance validation:

```bash
bash scripts/run_cuda_classic_src_resident_perf_0269a.sh
```

Default cases:

```text
PERF_GRID_CASES="64:64:220 128:128:140"
PERF_PISTON_GRID_CASES="64:64:160"
```

Expected output root:

```text
dev_history/artifacts/gpu_cuda_classic_src_resident_perf_0269a/
```

Expected summary files:

```text
cuda_classic_src_resident_perf_validation_0269a.csv
cuda_classic_src_resident_perf_summary_0269a.csv
cuda_classic_src_resident_perf_phases_0269a.csv
```

Primary performance signal:

- `io_segmented_0264` should remain PASS;
- `resident_boundary_kernel_s` for `segmented_u_turn_full` should drop relative
  to 0268/0267;
- `io_fullface_0263d` should remain close to the 0268 level.

## Architectural constraints preserved

- Q6 remains CPU for now, but the CUDA resident classic SRC path must not block a
  future CPU Q6 synchronization point.
- Resampling remains disabled only in the classic-only validators, not by
  architecture.
- Virial closure remains outside this performance patch.
- The generalized CUDA thermostat for wall/solid/piston/inlet-outlet conditions
  remains a separate future chantier.
- No dynamic GPU append is introduced; the path still uses preallocated inactive
  slots.

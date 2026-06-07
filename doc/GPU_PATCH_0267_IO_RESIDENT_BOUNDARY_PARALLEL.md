# GPU patch 0267 — CUDA resident inlet/outlet boundary parallel pass

## Purpose

Patch 0267 is a performance-only follow-up to the validated 0263d/0264
classic SRC CUDA resident inlet/outlet path.  Patch 0266 showed that the
inlet/outlet cases were dominated by `boundary_conditions`, because the first
resident implementation deliberately used a single CUDA thread for the whole
hard-cell reservoir boundary pass.

0267 keeps the validated classic-only physics and replaces the expensive global
serial particle boundary scan by a parallel per-particle CUDA pass.

## Scope

Modified/added files:

- `src/cuda_classic_src_io_resident_0263.cu`
- `scripts/build_src_mpcd_cuda_0267.sh`
- `scripts/run_cuda_classic_src_resident_perf_0267.sh`
- `scripts/summarize_cuda_resident_perf_0267.py`
- `doc/GPU_PATCH_0267_IO_RESIDENT_BOUNDARY_PARALLEL.md`

## Main change

The previous 0263d/0264 boundary kernel did two jobs in a single serial CUDA
thread:

1. scan all particles to apply open-boundary deletion / wall reflection /
   inlet-reservoir deletion;
2. insert the hard-cell inlet reservoir particles into inactive slots.

0267 splits these two operations:

1. `io_fullface_boundary_particles_kernel_0267` runs one CUDA thread per
   particle for the boundary/deletion/reflection pass and accumulates counters
   with atomics;
2. `io_fullface_hard_reservoir_insert_kernel_0267` keeps the hard-cell
   reservoir insertion serial and deterministic, reusing the same MT19937-64
   cell seeding and the same inactive-slot scan order as the validated path.

The serial 0263d/0264 kernel is intentionally kept as a fallback:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY=1
```

Default boundary thread count:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_BOUNDARY_THREADS=256
```

If unset, the old full-face/segmented thread-count environment variables are
used as fallbacks.

## What is deliberately not changed

- Q6 remains CPU and reactivable later.
- Resampling remains reactivable later.
- Virial remains disabled only in the classic-only validators.
- The CUDA thermostat remains a separate future wall/solid/piston/inlet-outlet
  aware chantier.
- GPU append remains disabled for inlet reservoir insertion; inactive slots
  must still be preallocated as in 0263d.
- The reservoir insertion is not yet converted to a compacted inactive-slot
  allocator.  This patch first removes the dominant serial all-particle scan
  while preserving a deterministic insertion order.

## Validation

Apply on top of 0266:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o /path/to/SRC_GPU_0267_io_resident_boundary_parallel_files_only.zip
```

Run the short performance validation:

```bash
bash scripts/run_cuda_classic_src_resident_perf_0267.sh
```

Outputs:

```text
dev_history/artifacts/gpu_cuda_classic_src_resident_perf_0267/
  cuda_classic_src_resident_perf_validation_0267.csv
  cuda_classic_src_resident_perf_summary_0267.csv
  cuda_classic_src_resident_perf_phases_0267.csv
```

For a deeper performance check:

```bash
PERF_GRID_CASES="64:64:300 128:128:240 256:128:120" \
PERF_PISTON_GRID_CASES="64:64:220" \
bash scripts/run_cuda_classic_src_resident_perf_0267.sh
```

Expected effect: the `boundary_conditions` / `resident_boundary_kernel_s` cost
for `open_rect_obstacle_full` and `segmented_u_turn_full` should drop
substantially compared with 0266.  If a discrepancy appears, rerun with the
serial fallback variable above to confirm that the failure is isolated to the
parallel boundary split.

# GPU patch 0266 — performance instrumentation for CUDA resident classic SRC

## Goal

Patch 0266 adds a non-intrusive performance instrumentation layer for the
validated CUDA resident classic SRC stack:

- 0260 periodic resident;
- 0261 wall-simple resident;
- 0262 immersed rectangle / solid obstacle resident;
- 0255 piston/mobile-wall legacy resident collision;
- 0263d full-face inlet/outlet resident;
- 0264 segmented inlet/outlet resident.

It does **not** add new physics and does **not** change validation criteria.
The purpose is to identify whether the next optimization should target
streaming, boundary/reservoir kernels, collision/cell moments, host/device
transfers, or CPU driver overhead.

## Permanent architectural constraints

The 0266 performance validators keep the classic-only validation choices from
0260--0264:

- Q6 disabled;
- resampling disabled;
- virial disabled;
- thermostat disabled except in already validated periodic-specific contexts.

These are validation constraints only.  The code must continue to preserve the
future reactivation path for:

1. CPU Q6 after an explicit host/GPU synchronization point;
2. resampling after an explicit host/GPU synchronization point;
3. a future wall/solid/piston/inlet-outlet-aware CUDA thermostat.

The 0259 fused CUDA thermostat remains validated only for the periodic subset
and must not be generalized implicitly by this patch.

## New files

```text
scripts/build_src_mpcd_cuda_0266.sh
scripts/run_cuda_classic_src_resident_perf_0266.sh
scripts/summarize_cuda_resident_perf_0266.py
doc/GPU_PATCH_0266_RESIDENT_PERFORMANCE_INSTRUMENTATION.md
```

## Modified file

```text
src/src_mpcd_base.cpp
```

The modification adds a resident CUDA phase accumulator enabled by either:

```bash
MPCD_CUDA_RESIDENT_PROFILE_0266=1
```

or by the existing:

```bash
MPCD_INTERNAL_PROFILES=1
```

When enabled, each run writes:

```text
cuda_resident_phase_profile_0266.csv
```

inside the run output directory.

## Main runner

```bash
bash scripts/run_cuda_classic_src_resident_perf_0266.sh
```

Default grids are intentionally moderate:

```bash
PERF_GRID_CASES="64:64:220 128:128:140"
PERF_PISTON_GRID_CASES="64:64:160"
```

For a deeper run:

```bash
PERF_GRID_CASES="64:64:300 128:128:240 256:128:120" \
PERF_PISTON_GRID_CASES="64:64:220" \
bash scripts/run_cuda_classic_src_resident_perf_0266.sh
```

## Outputs

The runner writes under:

```text
dev_history/artifacts/gpu_cuda_classic_src_resident_perf_0266/
```

Key output files:

```text
cuda_classic_src_resident_perf_validation_0266.csv
cuda_classic_src_resident_perf_summary_0266.csv
cuda_classic_src_resident_perf_phases_0266.csv
```

Per-run output directories also contain the usual files:

```text
summary_runtime.csv
phase_profile_0163.csv
q6_cg_profile_0163.csv
resampling_guard_profile_0169.csv
cuda_persistent_src_collision_thermostat_0215.csv
cuda_resident_phase_profile_0266.csv
```

For classic-only validation cases, Q6/resampling profile files may be empty or
near-zero; their presence is mainly useful to confirm that the profiling path is
consistent and that future Q6/resampling reactivation points remain visible.

## Interpretation

Use the summary columns as follows:

- `wall_s`: total wall time from the runtime summary;
- `force_stream_s`, `boundary_s`, `immersed_s`, `collision_s`: high-level phase
  timings from `phase_profile_0163.csv`;
- `resident_stream_total_s`, `resident_boundary_total_s`,
  `resident_immersed_total_s`: CUDA resident subphase timings recorded by 0266;
- `collision_kernel_s`, `collision_upload_s`, `collision_download_s`: persistent
  collision timing from the existing collision CSV;
- `resident_upload_s`, `resident_download_s`: residual transfers inside
  resident streaming/boundary phases;
- `resident_inlet_inserted_total`, `resident_outlet_deleted_total`: reservoir
  activity in full-face and segmented inlet/outlet cases.

If `boundary_s` is large but `resident_boundary_kernel_s` is small, the next
bottleneck is likely host-side orchestration/synchronization rather than the
hard-reservoir kernel itself.  If `resident_boundary_kernel_s` dominates for
inlet/outlet cases, the next target should be the reservoir insertion algorithm.

## Expected validation

The runner still uses the 0265c consolidated validation logic.  The expected
final result is PASS for all suites before performance summaries are considered
meaningful.

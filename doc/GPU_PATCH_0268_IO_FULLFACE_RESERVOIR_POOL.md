# GPU patch 0268 — CUDA resident full-face hard-cell reservoir pool

## Scope

Patch 0268 targets the remaining performance bottleneck seen after 0267 in
classic SRC CUDA resident inlet/outlet runs: the full-face hard-cell inlet
reservoir insertion.  The segmented resident path remains on the validated 0267
implementation and is used as a non-regression case by the performance runner.

The validation scope remains classic-only:

- Q6/projection disabled in the short validators, but the host/GPU freshness
  protocol is not removed and Q6 CPU reactivation remains possible later.
- resampling disabled in the short validators, but no architectural assumption
  prevents reintroducing it after an explicit synchronization point.
- virial disabled.
- thermostat disabled.  The CUDA thermostat wall/solid/piston/inlet-outlet-aware
  chantier remains separate.
- no dynamic GPU append; the reservoir still consumes preallocated Inactive slots.

## Implementation

The 0267 full-face resident boundary path was already split into:

1. a parallel particle boundary/delete kernel;
2. a deterministic but serial hard-cell reservoir insertion kernel.

0268 keeps step 1 and replaces step 2, for non-segmented full-face inlet/outlet,
with an inactive-slot pool:

1. mark all currently Inactive slots in parallel;
2. run an exclusive prefix scan with Thrust;
3. compact ascending inactive indices into a device-side pool;
4. launch one CUDA thread per reservoir cell;
5. each cell fills its `targetN` slots from a deterministic slice of the compact
   pool.

The reservoir cell RNG still uses the same per-cell `mt19937_64` seeding formula
as 0267/0263.  The compacted pool is ascending, so the slot ordering remains as
close as possible to the previous serial cursor while avoiding the repeated
full-array scan.

## New controls

Default optimized mode:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
```

Fallback to the 0267 serial insertion path:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_DISABLE_POOL=1
```

Optional tuning:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_POOL_THREADS=256
MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_INSERT_THREADS=128
```

The older full serial fallback is still available:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY=1
```

## Runner

Build:

```bash
bash scripts/build_src_mpcd_cuda_0268.sh
```

Validation/performance profile:

```bash
bash scripts/run_cuda_classic_src_resident_perf_0268.sh
```

Default outputs:

```text
dev_history/artifacts/gpu_cuda_classic_src_resident_perf_0268/
  cuda_classic_src_resident_perf_validation_0268.csv
  cuda_classic_src_resident_perf_summary_0268.csv
  cuda_classic_src_resident_perf_phases_0268.csv
```

For a stronger profile:

```bash
PERF_GRID_CASES="64:64:300 128:128:240 256:128:120" \
PERF_PISTON_GRID_CASES="64:64:220" \
bash scripts/run_cuda_classic_src_resident_perf_0268.sh
```

## Expected signal

The main metric to inspect is still:

```text
resident_boundary_kernel_s
```

on:

- `open_rect_obstacle_full` / full-face inlet/outlet;
- `segmented_u_turn_full` / segmented inlet/outlet, as non-regression.

0268 should mainly reduce the full-face case.  The segmented case was already
largely corrected by 0267 and should remain close to its 0267 timing.

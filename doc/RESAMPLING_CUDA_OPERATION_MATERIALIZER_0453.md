# 0453 — CUDA resampling operation materializer

## Scope

0453 adds an experimental CUDA donor-particle operation materializer for the clean periodic resampling path.

The validated chain before this patch was:

- 0451/0452: CUDA upstream apply-gate for deposit/classification/poor-rich compaction/planner;
- 0448/0449: CUDA apply backend for extraction/insertion + remap + thermal.

The remaining legacy dependency was the host-side donor-particle materializer that converts a transfer plan into compact passive extraction/insertion operations. 0453 moves this selection/materialization step to CUDA under a strict CPU/GPU gate.

## New flag

```bash
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=1
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_EVERY_0453=1
```

It is intended to be used with:

```bash
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1
MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1
```

## Implementation notes

0453 performs the following inside the real solver, after the upstream plan has been accepted and before extraction/insertion is applied:

1. upload the active particle arrays and the accepted transfer plan;
2. scan active fluid particles on CUDA in deterministic increasing particle-index order;
3. materialize the passive extraction/insertion operation list for each donor->receiver plan entry;
4. compare CUDA operations to the legacy CPU operation list;
5. if the operation gate passes, replace `workspace.resampling.passiveExtractionOperations` by the CUDA-materialized compact vector;
6. let the existing 0448 CUDA apply backend consume that vector.

The first 0453 implementation is intentionally serial on the device for semantic lock. It is not yet a performance kernel.

## Restrictions

0453 is currently restricted to the same validation envelope as 0450/0451:

- periodic wall-free cases;
- no immersed solids / chi / Darcy;
- no inlet/outlet;
- clean resampling path, no mass guard in the CUDA apply backend.

The host still orchestrates the run and the compact operation vector is downloaded after CUDA materialization because 0448 currently consumes host-side operation vectors. However, the donor-particle selection and operation materialization itself are no longer produced by the legacy host scanner when the 0453 gate passes.

## Diagnostics

0453 writes:

```text
cuda_resampling_operation_materialize_0453.csv
```

Important columns:

- `handled`, `applied`, `pass`, `skipped`;
- `planEntries`;
- `cpuOps`, `gpuOps`;
- `invalidOps`;
- `opMismatch`;
- `duplicateParticleMismatch`;
- `maxMassAbs`, `maxPxAbs`, `maxPyAbs`;
- `cpuMass/gpuMass`, `cpuPx/gpuPx`, `cpuPy/gpuPy`, `cpuKe/gpuKe`.

## Smoke runner

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0453 \
BASE_MATERIALIZE_ROOT=runs/0453_operation_materializer_smoke \
STEPS=20 \
SUMMARY_EVERY=1 \
RUN_MODES="src-resampling src-q6-resampling" \
LIVE_VIS_ENABLE=0 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0453_operation_materializer_smoke.sh
```

Then inspect:

```bash
cat runs/0453_operation_materializer_smoke/operation_materializer_report_0453.md
```

## PASS criteria

Expected smoke result:

```text
PASS-like modes = 2/2
handled = applied = pass
skipped = 0
planEntries > 0
cpuOps = gpuOps > 0
invalidOps = 0
opMismatch = 0
duplicateParticleMismatch = 0
maxMassAbs / maxPxAbs / maxPyAbs at roundoff
CPU baseline vs CUDA materialized+apply final summary delta <= 1e-9
```

## Next step

After 0453 PASS, the remaining work toward a fully resident resampling path is to remove the compact operation-vector download/host carrier and let the 0448 particle-edit kernels consume the device-materialized operations directly.

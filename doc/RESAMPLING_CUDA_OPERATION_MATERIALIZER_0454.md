# 0454 — CUDA resampling operation materializer stress

## Scope

0454 is a validation-only step for the CUDA donor-particle operation materializer introduced in 0453.
It adds no solver-side mutation path and does not change the production logic.

The stress runner repeatedly invokes the 0453 smoke over several seeds and step counts, then aggregates the flat summaries into one report.

## Validated chain

The tested path is:

1. CUDA upstream apply-gate for deposit, classification, poor/rich compaction, and transfer planning.
2. CUDA donor-particle materialization of passive extraction/insertion operations.
3. CPU/GPU strict gate for the compact operation vector.
4. Replacement of the compact operation carrier by the CUDA-materialized vector after PASS.
5. CUDA apply backend for extraction/insertion, remap, and thermal renormalization.
6. Final summary comparison against the CPU baseline.

## Non-goals

0454 does not yet remove the compact host carrier used by the current apply backend.
It is a stress validation step before removing that carrier.

## Default run

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0453 \
BASE_STRESS_ROOT=runs/0454_operation_materializer_stress \
STEPS_LIST="20 100" \
SEEDS="1628638 1628639 1628640" \
RUN_MODES="src-resampling src-q6-resampling" \
SUMMARY_EVERY=1 \
LIVE_VIS_ENABLE=0 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0454_operation_materializer_stress.sh
```

## PASS criteria

The run is considered valid when:

- PASS-like rows cover all rows.
- `maxSummaryDelta <= 1e-9`.
- CPU/GPU operation counts match and are nonzero.
- `maxInvalidOps = 0`.
- `maxOpMismatch = 0`.
- `maxDuplicateMismatch = 0`.
- mass and momentum operation differences are zero or roundoff.
- CUDA apply reports no invalid operations.

## Output files

The runner writes:

- `operation_materializer_stress_report_0454.md`
- `operation_materializer_stress_summary_0454.csv`

under `BASE_STRESS_ROOT`.

# 0456 — CUDA resampling device-carrier stress

0456 is a stress runner for the 0455 device-carrier path.

## Scope

- Periodic nonzero-plan cases only.
- No walls, no chi/Darcy, no inlet/outlet.
- No solver code change.
- CUDA upstream apply-gate remains enabled.
- CUDA operation materialization remains enabled.
- The device-carrier particle-edit backend consumes the materialized device operations directly.
- A host mirror remains only for strict gate diagnostics.

## Default coverage

The runner sweeps:

- `STEPS_LIST="20 100"`
- `SEEDS="1628638 1628639 1628640"`
- `RUN_MODES="src-resampling src-q6-resampling"`

This yields 12 summary rows.

## Expected pass criteria

The generated report should show:

- `PASS-like rows = 12/12`
- `maxSummaryDelta <= 1e-9`
- `maxCpuOps = maxGpuOps > 0`
- `maxExtractionApplied = maxInsertionApplied = maxGpuOps`
- `maxInvalidMaterializeOps = 0`
- `maxInvalidApplyOps = 0`
- `maxOpMismatch = 0`
- `maxDuplicateMismatch = 0`
- `maxMassAbs = maxPxAbs = maxPyAbs = 0`
- `maxMassDelta = maxPxDelta = maxPyDelta = 0`
- `applyInvalidOps = 0`

## Performance note

0456 is still a validation stress, not a production performance run. It intentionally runs CPU baselines, strict gates, diagnostic mirror downloads, and detailed CSV aggregation.

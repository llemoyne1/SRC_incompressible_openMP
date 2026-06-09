# 0308 strict completion runner fix

This update makes the 0308 split-safety consolidation runner stricter and more informative.

## Problem addressed

The 0308 consolidation runner reused the 0306 diagnostic-only fallback. That fallback can accept a run when diagnostic CSVs and dumps exist, even if the simulation stopped before the requested final step. In the observed backward-step resampling case, the full-face hard inlet reservoir exhausted at step 2084 because the CUDA append path is disabled and the inactive-slot reservoir was too small for a long hard-inlet plus resampling run.

## Changes

- Adds a safer default `INACTIVE_SLOTS=250000` for the 0308 validation runner.
- Passes `INACTIVE_SLOTS` through to the underlying demo scripts.
- Adds strict completion checking after the 0306 diagnostic run.
- Writes `cuda_resampling_split_safety_consolidated_0308_strict_completion.csv`.
- Fails the runner when a run is partial, rather than silently accepting diagnostic-only partial data.
- Tracks `requestedSteps`, `lastDiagnosticStep`, wrapper return code, outlier counts, and a final `PASS | PARTIAL | FAIL` verdict per case/mode.

## Main controls

```bash
STRICT_COMPLETION=1
STRICT_REQUIRE_WRAPPER_RC0=0
STRICT_REQUIRE_NO_OUTLIERS=1
INACTIVE_SLOTS=250000
```

## Expected usage

```bash
BIN=build/src_mpcd_base_cuda_0308 \
FORCE_REBUILD=0 \
bash scripts/run_cuda_resampling_split_safety_consolidated_0308.sh
```

A successful strict run should now reach the requested final step for each enabled case/mode.

# 0175 — strict post-guard deposit reuse of existing cell ids

This patch is a conservative post-guard optimization attempt. It does **not** implement the rejected 0174 local partial deposit. Instead it keeps the full deterministic post-guard deposit pipeline — role counts, full particle accumulation, cell reductions, classifications, candidate lists and mutation plans — but avoids recomputing particle cell ids during the post-guard deposit.

The population guard does not move particles. It only changes roles, masses and velocities. Therefore the existing `cellId` is still valid for all continuing fluid particles. The patch updates `cellId` locally for the two role mutations:

- overfull extraction: victim `Fluid -> Inactive`, so `cellId[victim] = -1`;
- underfull split: child `Inactive -> Fluid`, so `cellId[child] = affected cell`.

Then `deposit_weighted_real_fluid(..., PostGuard, reuseExistingCellIds=true)` performs the same full aggregation and planning as before, but uses the maintained `cellId` array instead of calling `cell_index_from_position(...)` for every fluid particle.

This is intentionally less aggressive than 0174. It is designed to preserve the exact resampling trajectory and pass the discriminant validation. If this conservative patch passes, a later patch can use the 0174d trace to attempt a stricter local affected-cell refresh.

## Expected effect

The gain should be smaller than a true local post-guard refresh, but safer. It should show primarily in:

- `resampling_post_guard_deposit`
- `deposit_profile`, context `post_guard`, phase `particle_loop_cell_accum`

## Validation required

Run the discriminant base-vs-optimized campaign before committing:

```bash
python3 scripts/compare_validation_mono_config_0162.py \
  --origin ../SRC_openMP_resampling/runs/validation_discriminant_0175_base \
  --optimized ../SRC_openMP_optimized/runs/validation_discriminant_0175_opt0175 \
  --out validation_compare_0175.csv \
  --summary-out validation_compare_summary_0175.csv
```

Accept only if all cases are `PASS` with zero failed metrics.

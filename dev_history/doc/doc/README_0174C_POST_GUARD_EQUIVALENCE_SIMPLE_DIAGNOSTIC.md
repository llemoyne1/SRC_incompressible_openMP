# 0174c — post-guard equivalence diagnostic, direct CSV version

This patch is diagnostic only. It does **not** replace the full
`post_guard` deposit and does not change the resampling trajectory.

Compared with 0174b, the diagnostic is deliberately simpler:

- snapshot the cell deposit workspace immediately before the full
  `ResamplingPostGuardDeposit`;
- run the existing full `deposit_weighted_real_fluid(..., PostGuard)` path;
- compare the pre/post cell arrays and candidate lists;
- write aggregate CSV files directly on every update, so that files are not
  empty even if process teardown/destructors are not reached as expected.

New/expected files:

- `post_guard_profile_0174c.csv`
- `post_guard_equivalence_profile_0174c.csv`

The most important equivalence metrics are:

- `count_changed_cells_total`
- `mass_changed_cells_total`
- `momentum_changed_cells_total`
- `classification_changed_cells_total`
- `non_count_changed_mass_momentum_cells_total`
- `non_count_changed_classification_cells_total`
- `candidate_list_size_changed_calls`
- `candidate_list_content_changed_calls`
- `full_to_scanned_ref_ratio`

A future local post-guard refresh is safer if differences are confined to the
small set of population-guard affected cells and if candidate-list changes can
be reproduced by a deterministic global cell-order rebuild.

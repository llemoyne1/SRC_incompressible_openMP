# 0174d — direct post-guard equivalence trace

Diagnostic-only correction after 0174b/0174c produced empty aggregate files.

This patch keeps the full `post_guard` deposit as the active algorithm and adds a direct per-call trace written immediately from the `ResamplingPostGuardDeposit` block:

- `post_guard_equivalence_trace_0174d.csv`

The trace is appended directly in each case output directory and aggregated by `scripts/run_performance_profile_0174d.sh`. It does not rely on destructors or delayed accumulators.

Key columns:

- `affected_cells`, `candidate_cells`
- `scanned_particle_refs`, `full_deposit_particles_visited`
- `count_changed_cells`, `mass_changed_cells`, `momentum_changed_cells`, `classification_changed_cells`
- `non_count_changed_mass_momentum_cells`, `non_count_changed_classification_cells`
- `candidate_list_size_changed`, `candidate_list_content_changed`
- `full_to_scanned_ref_ratio`

The algorithmic path is unchanged: full post-guard deposit remains in use.

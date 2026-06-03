# 0170 — Population-guard local role-write optimization

This differential patch follows the 0169 mutation-level profile.  The profile showed
that almost all of the `population_guard` mutation cost was attributed to
`OverfullMutationRoleInactivate` and `UnderfullMutationRoleActivate`.  Those paths
were using the public `set_particle_role(...)` helper, which calls
`ensure_particle_roles(...)` and therefore performs global validation work for each
single role write.

## Change

Inside `src/weighted_resampling.cpp` only, this patch adds a private helper:

```cpp
set_particle_role_preconditioned(state, i, role)
```

It directly writes `state.role[i]` after relying on preconditions already established
by `apply_resampling_population_support_guard(...)`:

- particle roles are initialized once at the start of the guard;
- the particle index was selected from validated particle/index data;
- pool/list bookkeeping is still performed exactly as before.

Only the two role writes inside the population-guard mutations are changed:

- overfull victim: `Fluid -> Inactive`;
- underfull child: `Inactive -> Fluid`.

## Not changed

The patch does not change:

- candidate-cell selection;
- particle selection order;
- split/extraction budgets;
- pool push/pop behavior;
- diagnostics counters;
- mass guard;
- Q6/CG;
- virial/capacity;
- particle-cell deposits.

## Validation

Run the profiling probe:

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh

RUN_ROOT=runs/performance_profile_0170_population_role_write \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0170.sh
```

Compare against 0169, especially:

- `resampling_population_guard`;
- `overfull_mutation_role_inactivate`;
- `underfull_mutation_role_activate`;
- `q6_iterations`;
- `resamp_m_rel_rms`;
- `resamp_transfer_pairs`;
- `resamp_selected_particles`.

If the gain is significant, run the discriminating validation matrix before commit,
because this patch optimizes a low-level mutation primitive.

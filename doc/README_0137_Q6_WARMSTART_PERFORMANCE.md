# 0137 — Q6 warm-start and lightweight divergence diagnostics

This patch is a performance-only pass for the Q6 projection path.
It does not change the intended Q6 operator, boundary conditions, immersed-solid
masking, resampling logic, or particle update sequence.

## Motivation

The backward-step validation showed that Q6 itself is now a significant part of
runtime.  The expensive part is the elliptic CG solve and some redundant Q6
post-solve diagnostics.  The projection problem changes smoothly from one SRC
step to the next, so the previous elliptic potential is a useful initial guess.

## New parameters

```kv
q6WarmStartEnable = true
q6ReuseProjectedDivergenceDiagnostics = true
```

`q6WarmStartEnable=true` stores the last elliptic potential in the persistent
elliptic workspace and uses it as the next CG initial guess.  The first Q6 step,
and any step after a grid-size change, still starts from zero.

`q6ReuseProjectedDivergenceDiagnostics=true` keeps the historical runtime columns
`q6DivAfterProjectedFlux*` and `q6DivAfterCellVelocity*`, but avoids rebuilding a
second corrected-cell face field.  In the current Q6 adapter convention these two
fields are algebraically the same, so the cell-velocity divergence diagnostic can
reuse the projected-flux divergence.

Set either switch to `false` to recover the previous path for debugging.

## Scripts updated

The validation launchers now expose these controls:

```bash
BSTEP_Q6_WARM_START=true
BSTEP_Q6_REUSE_PROJECTED_DIV_DIAG=true

POIS_Q6_WARM_START=true
POIS_Q6_REUSE_PROJECTED_DIV_DIAG=true

CCYL_Q6_WARM_START=true
CCYL_Q6_REUSE_PROJECTED_DIV_DIAG=true
```

For the backward-step timing test:

```bash
BSTEP_STEPS=3000 \
BSTEP_DUMP_EVERY=1000000 \
BSTEP_SUMMARY_EVERY=25 \
BSTEP_THREADS=8 \
./scripts/run_backward_step_resampling_validation_0136.sh
```

To disable the new Q6 path:

```bash
BSTEP_Q6_WARM_START=false \
BSTEP_Q6_REUSE_PROJECTED_DIV_DIAG=false \
./scripts/run_backward_step_resampling_validation_0136.sh
```

## Expected effect

The main expected gain is a lower number of CG iterations after the first few
steps, especially on steady or slowly evolving cases.  The diagnostic shortcut
saves an additional full-grid divergence reconstruction each Q6 step.

Validation should compare:

- wall time for `q6` and `q6_resampling`,
- `q6Iterations`,
- `q6ResidualRel`,
- `q6DivAfterProjectedFluxRms`,
- physical post-processing fields.

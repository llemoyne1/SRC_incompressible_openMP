# 0137B — Revert Q6 warm-start performance experiment

This rollback restores the Q6 projection path to the validated 0136B state, before the 0137 warm-start experiment.

## Motivation

The 0137 warm-start test did not improve the backward-step performance. On the reference 0136 backward-step run, the measured wall times increased relative to the pre-0137 code:

- classic remained essentially unchanged;
- q6 became slower;
- q6_resampling became slower.

The optimization is therefore deferred to a separate performance-focused branch/chapter. The current validation branch returns to the validated Q6 behavior used for the Poiseuille, periodic cylinder, channel-cylinder, and backward-step validations.

## Reverted behavior

The rollback removes the active Q6 warm-start plumbing introduced in 0137:

- no `q6WarmStartEnable` parameter;
- no `q6ReuseProjectedDivergenceDiagnostics` parameter;
- no persistent previous-potential initial guess in the elliptic projection interface;
- run scripts no longer emit Q6 warm-start parameters.

Q6 is again solved through the pre-0137 elliptic projection path.

## Files restored

- `README.md`
- `include/simulation_params.h`
- `include/elliptic_projection.h`
- `src/params_io_base.cpp`
- `src/elliptic_projection.cpp`
- `src/q6_projection_adapter.cpp`
- `scripts/run_poiseuille_wallvp_resampling_validation_0131.sh`
- `scripts/run_channel_cylinder_resampling_validation_0135.sh`
- `scripts/run_backward_step_resampling_validation_0136.sh`

If the 0137 documentation file exists in the working tree, remove it manually with:

```bash
git rm doc/README_0137_Q6_WARMSTART_PERFORMANCE.md
```

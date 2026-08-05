# 0493x3 — experimental force kick projected by Q6 before streaming

## Purpose

0493x2 showed that common Q6 holds a fully occupied liquid almost motionless
under gravity, while the historical kick-and-drift still moves every particle by
approximately `g*dt^2` before the post-collision projection can react.  The
resulting deterministic displacement accumulates at the lower wall.

0493x3 is a test-only, opt-in ordering experiment.  It does not replace the
historical path and does not claim a production integration scheme.

## Runtime switch

```
q6ForceProjectionMode = legacy | prestream
```

`legacy` is the default and preserves every existing run.

When `prestream` is selected and a non-zero uniform or Taylor–Green force is
present, one step becomes:

1. apply the force kick to the resident particle velocities;
2. apply CUDA Q6 to that tentative velocity;
3. stream with the already-projected velocity and with the force disabled in
   the streaming kernel;
4. apply boundaries and SRC collision;
5. retain the existing post-collision Q6;
6. retain the existing thermostat and subsequent operators.

When the force is identically zero, the extra kick and projection are skipped.
This makes the null-force `legacy`/`prestream` pair a bitwise identity control.

## Deliberate restrictions

The experimental mode accepts only:

- CUDA Q6;
- a fully periodic box or a static closed box made of `solid`/`specular` faces;
- no resampling;
- no open boundaries;
- no Darcy/Brinkman term;
- no immersed solid or projection mask;
- no closed-capacity or virial response;
- `speciesQ6Mode=common` when species Q6 is enabled.

The normal post-collision Q6 CSV remains authoritative.  The prestream solve
uses an empty `outputDir` copy so it does not duplicate the established Q6 audit
rows.

## Qualification runners

### Taylor–Green matrix

```
LIVE_PROGRESS=1 bash scripts/run_0493x3_q6_force_projection_tg.sh
```

The matrix runs:

- `null_legacy`;
- `null_prestream`;
- `forced_legacy`;
- `forced_prestream`.

Defaults are `64x64`, `gamma=40`, `dt=0.001`, 500 steps, thermostat and
resampling off, Taylor–Green forcing amplitude `0.02`, dumps every 20 steps.
The analyzer requires bitwise equality for the null pair and reports, without a
premature physical threshold, modal and particle-state differences for the
forced pair.

### Fully occupied liquid under gravity

This runner requires the already-applied 0493x2 `--liquid-only` generator
extension:

```
LIVE_PROGRESS=1 bash scripts/run_0493x3_liquid_only_q6_force_prestream.sh
```

It uses common Q6, two projections per step, `gY=-0.5`, `dt=0.005`, active
visualization and dumps every 100 steps.  Momentum correction is disabled so the
closed walls may transmit the hydrostatic pressure reaction.

## Expected decision

- Null TG mismatch: reject the implementation.
- Forced TG amplitude systematically attenuated: investigate the discrete
  force/projection compatibility before generalization.
- Forced TG agreement with suppression of closed-box `g*dt^2` sedimentation:
  proceed to temporal refinement and then study a production-quality ordering.

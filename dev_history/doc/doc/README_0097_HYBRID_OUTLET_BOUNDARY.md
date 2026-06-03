# 0097 — Hybrid outlet boundary for Q6/Q9 inlet/outlet cases

This patch adds a third Q6/Q9 open-outlet projection mode:

```text
openBoundaryOutletMode = hybrid
```

It is intended for violent segmented inlet/outlet tests, especially slit/nozzle
injection where a pure Neumann outlet can allow transient mass accumulation, but
a fully prescribed balanced-flux outlet is too constraining.

## Existing modes preserved

The validated default remains unchanged:

```text
openBoundaryOutletMode = balanced_flux
```

Available modes are now:

- `balanced_flux`: outlet Q6/Q9 projection flux is prescribed from the ramped
  inlet flux. This is the validated full-channel policy.
- `neumann`: inlet remains prescribed, outlet uses the current local base face
  flux. This gives zero normal correction on the open outlet segment.
- `hybrid`: outlet starts from the local Neumann profile, can be blended weakly
  toward the balanced-flux profile, then receives a weak outlet-only global
  flux-balance feedback.

Aliases accepted for `hybrid` are `neumann_feedback` and `hybrid_feedback`.

## Hybrid parameters

```text
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
```

Both parameters are in `[0,1]`.

`openBoundaryOutletHybridBlend` controls the local profile before feedback:

```text
0 : pure local Neumann outlet profile
1 : fully balanced-flux outlet profile
```

`openBoundaryOutletFeedbackGain` applies a uniform correction only over open
outlet aperture cells. It reduces the current open-boundary flux imbalance by
`gain * imbalance` while leaving inlet faces prescribed and aperture complements
impermeable.

For a left-inlet/right-outlet case, the correction acts on the right outlet as:

```text
F_out <- F_out - gain * balance / outlet_open_length
balance = integral(F_right) - integral(F_left)
```

The same sign convention is applied to left, bottom and top outlets.

## Nominal slit/nozzle debug setting

`scripts/run_open_channel_jet.sh` now defaults to:

```text
openBoundaryOutletMode = hybrid
openBoundaryOutletHybridBlend = 0.10
openBoundaryOutletFeedbackGain = 0.50
```

Override examples:

```bash
OUTLET_MODE=neumann bash scripts/run_open_channel_jet.sh
OUTLET_MODE=balanced_flux bash scripts/run_open_channel_jet.sh
OUTLET_MODE=hybrid OUTLET_HYBRID_BLEND=0.0 OUTLET_FEEDBACK_GAIN=0.25 bash scripts/run_open_channel_jet.sh
OUTLET_MODE=hybrid OUTLET_HYBRID_BLEND=0.25 OUTLET_FEEDBACK_GAIN=0.75 bash scripts/run_open_channel_jet.sh
```

## Scope

This patch does not add a new elliptic solver and does not add any FFT path. It
only changes how the already-existing generic elliptic boundary flux profiles are
built for open outlets.

The mode `classic` is unaffected. Q6/Q9 periodic and channel validations are
unaffected unless the new hybrid outlet mode is explicitly selected.

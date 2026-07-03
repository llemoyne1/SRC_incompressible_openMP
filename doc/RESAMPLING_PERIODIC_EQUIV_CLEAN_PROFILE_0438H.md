# 0438H — Clean periodic path-equivalence profile

This profile formalizes the wall-free periodic validation used after 0438B/0438C.
It is intended only for cases where the four paths should be physically identical
up to roundoff:

- `src`
- `src-resampling`
- `src-q6`
- `src-q6-resampling`

## Scope

The profile is restricted to:

- periodic domains,
- no wall boundary condition,
- no solid/chi/Darcy/Brinkman/Vp field,
- no inlet/outlet,
- no geometrically forced poor/rich population regions.

Wall and solid cases are deliberately excluded from path-equivalence validation.
They are robustness/application tests, because resampling modifies exactly the
near-wall population dynamics that plain SRC naturally leaves depleted or
overpopulated.

## Clean profile

The clean profile keeps the weighted CPU resampling reference phases that are
part of the historical path:

- extraction/insertion enabled,
- remap enabled,
- thermal renormalization enabled.

It disables or neutralizes corrective mechanisms that are not part of the clean
identity comparison:

- CUDA-local resampling auxiliaries,
- empty-refill / local guard mechanisms,
- CPU mass guard,
- CPU population guard, made inert through permissive thresholds,
- stale role-tail effects, repaired through existing 0315H/0315K controls.

No new solver parameter is introduced by 0438H.

## Expected result

For the validated shear-wave and Taylor--Green sweeps at `gamma=40`, the clean
profile produced roundoff-level differences:

- matching comparison `src-resampling` vs `src`,
- matching comparison `src-q6-resampling` vs `src-q6`,
- `max resampPairs = 0`.

This means that the finite differences observed in the initial 0438B sweeps came
from auxiliary corrective mechanisms, not from the weighted CPU remap/thermal
reference path in the clean periodic regime.

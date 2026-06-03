# 0099 — Virial kick near immersed solids: face-normal clipping

## Goal

Patch 0098 made Q6/Q9 use the immersed-solid face/cell mask directly: active fluid cells remain active up to the solid, while fluid-solid and cut faces are closed to normal flux. Patch 0099 applies the same principle to the optional virial/liquid kick.

The virial kick remains active in fluid cells adjacent to an immersed solid, but the component that would push particles through a closed immersed-solid face is removed.

## Numerical rule

For an active fluid cell adjacent to the immersed solid:

- if the east face is a closed immersed-solid face and `dux > 0`, set `dux = 0`;
- if the west face is a closed immersed-solid face and `dux < 0`, set `dux = 0`;
- if the north face is a closed immersed-solid face and `duy > 0`, set `duy = 0`;
- if the south face is a closed immersed-solid face and `duy < 0`, set `duy = 0`.

Tangential components are preserved. Cells that are not adjacent to the immersed solid are not touched by this clipping step.

The test for a closed immersed-solid face uses the existing mask:

- inactive neighbor cell, or
- face closed by cut geometry.

Domain boundary faces are not treated as immersed-solid faces by this patch.

## New diagnostics

The runtime summary gains four columns:

```text
virialImmersedSolidNormalKickClippedCells
virialImmersedSolidNormalKickClippedComponents
virialImmersedSolidNormalKickClippedRms
virialImmersedSolidNormalKickClippedMaxAbs
```

Interpretation:

- `Cells`: number of active fluid cells where at least one virial kick component was removed;
- `Components`: number of scalar components removed (`dux` and/or `duy`);
- `Rms`: RMS magnitude of the removed scalar components;
- `MaxAbs`: maximum absolute removed scalar component.

A zero value is acceptable when the virial gradient does not point into the solid. A non-zero value indicates that the solid-normal protection is active.

## Smoke test

A short 100-step test is provided:

```bash
bash scripts/run_backward_step_q9_virial_mask_smoke_0099.sh
```

It writes to:

```text
runs/backward_step_q9_virial_mask_smoke_96x48
```

Recommended quick checks:

```bash
head -1 runs/backward_step_q9_virial_mask_smoke_96x48/summary_runtime.csv | tr ',' '\n' | grep 'virialImmersedSolidNormalKick'
tail -1 runs/backward_step_q9_virial_mask_smoke_96x48/summary_runtime.csv
find runs/backward_step_q9_virial_mask_smoke_96x48 -name '*.q9bin' -print | head
```

This is only a runtime/diagnostic smoke test. It is intentionally short and should not be used as a physical validation.

## Expected status after this patch

The nominal immersed-solid treatment is now:

```text
q9ImmersedSolidHaloCells = 0
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidCloseCutFaces = true
fluid cells adjacent to the solid active
Q6/Q9 normal flux through solid faces zero
virial kick active adjacent to the solid, but clipped when directed into closed solid faces
```

The next validation step should remain short: first smoke Q9+virial diagnostics, then a modest obstacle/channel run only if no runtime or mask anomaly appears.

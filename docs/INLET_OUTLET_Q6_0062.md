# 0062 — Minimal Q6 inlet/outlet via elliptic prescribed normal flux

This patch lifts the 0061 classic-only restriction for the first Q6 open-channel
case. It does not enable Q9 or virial open-boundary operation.

## Scope

Supported in 0062:

- one open axis only;
- one inlet face paired with one outlet face;
- the other axis periodic or solid-wall according to the existing validation
  rules, with the intended first test being x-open/y-solid;
- `method = classic` unchanged;
- `method = q6` with `projectionEnable = true`;
- no immersed solid for Q6 open boundaries;
- no Q9 mass-flux projection and no virial kick/diagnostics with open
  boundaries.

## Elliptic boundary policy

The particle boundary remains the 0061b CUDA-like recycling mechanism. Q6 now
passes compatible external face fluxes to the generic matrix-free elliptic core.

For a left-inlet/right-outlet channel, the Q6 boundary stores the x-component
of velocity on the low and high external x-faces as

```text
xLowFlux  = inletUxLeft
xHighFlux = inletUxLeft
```

For a right-inlet/left-outlet channel:

```text
xLowFlux  = inletUxRight
xHighFlux = inletUxRight
```

The same convention is used in y. These are component fluxes in the compact
finite-volume face-field convention, not outward-normal fluxes. Equal low/high
component values make the global open-boundary flux balance zero, so the Q6
projection remains compatible with a zero target divergence.

Solid walls keep the existing no-normal-flux/moving-wall values from the active
fluid domain.

## Added diagnostics

The runtime summary receives appended Q6 open-boundary columns:

```text
q6OpenBoundaryEnabled
q6OpenBoundaryFluxXLow
q6OpenBoundaryFluxXHigh
q6OpenBoundaryFluxYLow
q6OpenBoundaryFluxYHigh
q6OpenBoundaryFluxBalance
q6OpenBoundaryMeanDivergence
```

For the first x-open smoke case, the expected values are approximately:

```text
q6OpenBoundaryEnabled = 1
q6OpenBoundaryFluxXLow = 0.05
q6OpenBoundaryFluxXHigh = 0.05
q6OpenBoundaryFluxBalance = 0
q6OpenBoundaryMeanDivergence = 0
```

## Smoke test

Generate the initial state from MATLAB:

```matlab
cd matlab
generate_open_channel_classic_state('output','../initial_state_open_channel_64x32_g20_kbt0p01.smpcd');
cd ..
```

Build and run:

```bash
./scripts/run_open_channel_q6_inlet_outlet_smoke.sh
```

The smoke case is a short open-channel/Poiseuille-style diagnostic with
`keepMeanFlowEnable = true`. This follows the CUDA-like validation logic: the
mean flow is kept at the inlet target value so that the outlet and Q6 projection
are exercised over a short run. It is not yet a final physical validation of a
self-sustained open boundary.

Minimum expected checks:

- `Np` and `totalMass` remain constant;
- `meanVx` remains near `0.05` because `keepMeanFlowEnable=true`;
- `q6Applied = 1`;
- `q6OpenBoundaryEnabled = 1`;
- `q6Converged = 1` on most/all output frames;
- `q6DivAfterProjectedFluxRms` is lower than `q6DivBeforeRms`;
- Q9/virial with inlet/outlet are still rejected.

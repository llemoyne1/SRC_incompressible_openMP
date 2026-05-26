# Immersed-solid mask for Q6/Q9

This patch extends the generic matrix-free elliptic core to support an optional active-cell mask.  The purpose is to make Q6 velocity projection and Q9 filtered mass-flux projection aware of analytic immersed solids such as the circle and the new rectangular backward-step block.

## Discrete model

The particle dynamics already see the immersed solid through reflection and virtual particles.  Without an elliptic mask, however, the projection operator still sees the full rectangular grid and can communicate pressure/flux corrections through the solid.  The new masked path instead uses:

- active cells: cells whose fluid fraction is above `projectionImmersedSolidFluidFractionThreshold`;
- inactive cells: solid cells excluded from the physical solve;
- open faces: faces connecting two active cells;
- closed faces: faces touching at least one inactive cell.

The elliptic operator remains the same finite-volume operator, but with zero coupling across closed faces.  Inactive rows are set to identity to keep the matrix well posed for CG.

## New parameters

```text
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidFluidFractionThreshold = 0.5
projectionAllowUnmaskedImmersedSolid = false
```

Safety rule: if `immersedSolidEnable=true` and Q6/Q9 is requested, the run now requires `projectionImmersedSolidMaskEnable=true`, unless `projectionAllowUnmaskedImmersedSolid=true` is explicitly set for a negative-control/debug run.

The first masked implementation supports fixed immersed solids only.  Non-zero `immersedSolidVx`, `immersedSolidVy`, or `immersedSolidOmega` with masked Q6/Q9 is rejected until the internal moving-wall fluxes are implemented.

## Diagnostics

The runtime summary now records the mask size and solid-face leakage diagnostics:

```text
q6ImmersedSolidFluidCells
q6ImmersedSolidSolidCells
q6ImmersedSolidClosedXFaces
q6ImmersedSolidClosedYFaces
q6ImmersedSolidLeakProjectedFluxRms
q6ImmersedSolidLeakProjectedFluxMaxAbs
q9ImmersedSolidFluidCells
q9ImmersedSolidSolidCells
q9ImmersedSolidClosedXFaces
q9ImmersedSolidClosedYFaces
q9ImmersedSolidLeakMassFluxRms
q9ImmersedSolidLeakMassFluxMaxAbs
```

For a correctly masked run, the leak diagnostics should remain close to zero.

## Smoke cases

Generate the backward-step initial state if needed:

```matlab
cd matlab
generate_backward_step_state('output','../initial_state_backward_step_96x48_g20.smpcd');
cd ..
```

Run both masked smoke cases:

```bash
./scripts/run_backward_step_q6_q9_mask_smoke.sh
```

or individually:

```bash
./build/src_mpcd_base examples/params_backward_step_q6_mask_smoke_96x48.kv
./build/src_mpcd_base examples/params_backward_step_q9_mask_smoke_96x48.kv
```

These are still periodic-x, body-forced, backward-step-like tests.  They are not yet inlet/outlet academic backward-facing-step benchmarks.

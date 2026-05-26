# 0066 — Q9 safety for open boundaries with a fixed immersed rectangle

This patch is a guarded follow-up to the stable 0065b open-channel validation.
It does **not** claim that Q9 + inlet/outlet + immersed solids is fully
validated.  It adds the missing safety layer exposed by the first backward-step
attempt: Q9 mass-flux corrections must not act directly in reservoir strips,
in the immediate immersed-solid halo, in low-population cells, or with unbounded
cell velocity increments.

## Scope

Allowed with inlet/outlet and an immersed solid:

- `method=q6` with a fixed `immersedSolidShape=rectangle|rect|box|step` and
  `projectionImmersedSolidMaskEnable=true`;
- `method=q9` / `method=q9_virial` only when all Q9 safeguards below are
  explicitly active.

Still intentionally out of scope:

- moving immersed solids with inlet/outlet;
- circular immersed solids as strict validations;
- unmasked immersed-solid Q6/Q9;
- Q9/virial backward-step validation without safety limiters.

## New Q9 parameters

```kv
q9OpenBoundaryExclusionCells = 3
q9ImmersedSolidHaloCells = 3
q9MinCellMassForCorrection = 6.0
q9CorrectionVelocityLimiter = 0.01
```

Meaning:

- `q9OpenBoundaryExclusionCells`: excludes reservoir strips near inlet/outlet
  from the Q9 solve/kick.
- `q9ImmersedSolidHaloCells`: excludes a Manhattan-cell halo around immersed
  solid cells from Q9.
- `q9MinCellMassForCorrection`: suppresses Q9 kicks in low-mass cells.
- `q9CorrectionVelocityLimiter`: limits the actually applied per-cell Q9
  velocity increment `|dU|`.

For the default backward-step safety smoke with `kBT=0.0025`, the thermal scale
is `sqrt(kBT)=0.05`; `q9CorrectionVelocityLimiter=0.01` therefore limits Q9
increments to roughly 20% of the thermal velocity.

## New runtime diagnostics

The runtime CSV gains:

```text
q9SafetyActiveCells
q9SafetyExcludedCells
q9OpenBoundaryExcludedCells
q9ImmersedHaloExcludedCells
q9LowMassSuppressedCells
q9VelocityLimitedCells
q9CorrectionVelocityRawRms
q9CorrectionVelocityRawMaxAbs
q9CorrectionVelocityLimiter
q9MinCellMassForCorrection
```

`q9CorrectionVelocityRaw*` is measured before safety clipping.  The existing
`q9CorrectionVelocityRms/MaxAbs` fields now refer to the actually applied Q9
kick after low-mass suppression and limiting.

## Quick smoke

```bash
./scripts/build_src_mpcd_base.sh
chmod +x scripts/run_backward_step_q9_safety_smoke_0066.sh
CASE_STEPS=1000 ./scripts/run_backward_step_q9_safety_smoke_0066.sh
```

Generate the initial condition if needed:

```matlab
cd matlab
generate_backward_step_state( ...
    'output','../initial_state_backward_step_96x48_g20_kbt0p0025.smpcd', ...
    'kBT',0.0025);
cd ..
```

Analyze:

```matlab
cd matlab
S = analyze_backward_step_q9_safety_smoke_0066('root','..');
cd ..
```

The first objective is boundedness and diagnostics, not a final physical
validation.  Expected pass conditions are conservative:

- `Np` and `totalMass` constant;
- `kBTMeanLate/kBTTarget` not catastrophically large;
- Q6/Q9 converged;
- `q9CorrectionVelocityMaxAbs <= q9CorrectionVelocityLimiter` for Q9 cases;
- non-zero safety exclusions near reservoir/solid for Q9 cases.

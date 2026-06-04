# 0149 — closed-capacity remap target follows global overfill

## Objective

Patch 0147 introduced a continuous closed-capacity response for a full, rigid, closed domain fed by an inlet: Q6 is weakened, the virial stiffness is increased, and the local incompressible mass remap is weakened when the total real-fluid mass exceeds the nominal domain capacity.

The first closed-capacity run showed that this was not sufficient: the mass remap still targeted the nominal cell mass `gamma`, so the global overfill remained close to zero. The Q6 weakening and virial response were therefore activated only weakly and the run stabilized near the incompressible state.

Patch 0149 changes the mass-remap target used under closed-capacity overfill. The remap no longer erases the global excess mass. Instead, it homogenizes it over the active/wet reference cells.

## Behaviour preserved by default

If

```text
closedCapacityResponseEnable = false
```

nothing changes. The local mass remap still uses the existing target from the weighted-resampling deposit, normally

```text
resamplingTargetCellMass = gamma
```

or the inferred equivalent. This preserves the previous Taylor--Green, Poiseuille, inlet/outlet, immersed-solid, and standard resampling validations.

## New closed-capacity rule

When

```text
closedCapacityResponseEnable = true
```

and the measured total mass exceeds the nominal capacity,

```text
M_ref = referenceCells * closedCapacityReferenceCellMass
M_over = max(0, M_total - M_ref)
```

the effective target cell mass passed to the local mass-remap stage becomes

```text
M_target_eff = closedCapacityReferenceCellMass + M_over / referenceCells
```

rather than the nominal fixed value alone.

This means:

- the population guard still maintains particle support;
- the remap still reduces cell-to-cell mass heterogeneity;
- the remap no longer removes the global compression imposed by a positive inlet mass flux;
- the virial pressure can now grow from the actual accumulated overfill.

The remap strength modulation from 0147 remains active:

```text
M_after_cell = M_before_cell
             + capacityMassRemapFactor * (M_target_eff - M_before_cell)
```

with

```text
capacityMassRemapFactor = exp(-(overfill / closedCapacityMassRemapEta)^closedCapacityMassRemapPower)
```

Thus the target moves with global overfill, while the strength of local correction can still decay as the system moves away from the incompressible regime.

## New diagnostics

Three CSV diagnostics are appended to `summary_runtime.csv` near the other closed-capacity columns:

```text
capacityMassRemapTargetCellMassNominal
capacityMassRemapOverfillPerCell
capacityMassRemapTargetCellMassEffective
```

The existing column

```text
resampRemapTargetCellMass
```

now reports the effective target actually used by the remap. Under standard runs it remains the historical value. Under closed-capacity overfill it rises above the nominal reference value.

## Expected effect on `run_closed_capacity_inlet_only_0147.sh`

For a full closed vessel with inlet only and additive inlet mass flux enabled, the expected qualitative changes are:

- `totalMass` and `capacityOverfillRatio` should grow rather than remain pinned near zero;
- `capacityMassRemapTargetCellMassEffective` should rise above `closedCapacityReferenceCellMass`;
- `resampRemapTargetCellMass` should match the effective target on remap steps;
- `capacityQ6ProjectionFactor` should decrease more clearly;
- `capacityVirialPressureMean` and `capacityVirialKEffective` should grow with compression;
- if the inlet flux is maintained, the run may eventually become numerically unstable, which is an acceptable outcome for this stress test.

## Parallelization impact

The patch adds no new global communication pattern beyond the reductions already used in the closed-capacity diagnostics. The effective remap target is a scalar computed from the existing total-mass reduction and then passed into the already parallel local remap loop. The cost is negligible relative to deposit, collision, Q6, and resampling operations.

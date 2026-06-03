# Patch 0147 — closed-capacity virial response for a full closed tank with inlet-only forcing

## Objective

This patch adds a continuous closed-domain capacity response for the specific case where a fluid domain is already full, has rigid walls, and receives a net positive inlet flux without an outlet.  Such a case is not compatible with strict incompressibility.  The new response lets overfilling progressively weaken Q6, strengthen a virial pressure response, and weaken the incompressible mass-remap stage.

The feature is disabled by default.  Existing Taylor--Green, Poiseuille, segmented inlet/outlet, immersed-solid and population-guard validations are unchanged unless `closedCapacityResponseEnable=true` is added explicitly.

## Capacity measure

The nominal mass contained by the closed active fluid domain is

```text
M_ref = N_ref_cells * closedCapacityReferenceCellMass
```

where `closedCapacityReferenceCellMass` should normally be `gamma`.  If it is not supplied, the code can infer it from `resamplingTargetCellMass`, then from `inletTargetOccupancy * closedCapacityReferenceParticleMass`.

The continuous overfill variable is

```text
eta = max(0, (M_total - M_ref) / M_ref)
```

No threshold is used.  If `eta=0`, the old behaviour is recovered exactly.

## Q6 modulation

The projection itself is unchanged.  Only the effective projection strength is modified:

```text
q6ProjectionStrengthEff = q6ProjectionStrength * exp(-(eta / closedCapacityQ6Eta)^closedCapacityQ6Power)
```

Thus the existing `q6ProjectionStrength` machinery is reused.  Immersed-solid closed faces remain hard no-flux, as in the previous Q6 implementation.

## Virial pressure kick

When `closedCapacityVirialKickEnable=true`, a cell virial pressure is reconstructed as

```text
Pvir_c = K_eff * (M_c / M_ref_cell - 1)
K_eff  = closedCapacityVirialBaseK * (1 + closedCapacityVirialGain * (eta / closedCapacityVirialEta)^closedCapacityVirialPower)
```

A cell-uniform velocity kick is then applied from `-grad(Pvir)/rho`.  The kick has an optional exact global momentum correction controlled by `closedCapacityVirialMomentumCorrectionEnable=true`.

## Resampling interaction

The population guard remains active.  This is deliberate: it protects the particle support near walls and prevents the old empty-cell failure.

The incompressible mass remap is weakened continuously:

```text
remapStrength = exp(-(eta / closedCapacityMassRemapEta)^closedCapacityMassRemapPower)
M_after,c     = M_before,c + remapStrength * (M_target - M_before,c)
```

When `closedCapacityMassGuardDisableOnOverfill=true`, the mass guard is skipped once `eta>0`, because otherwise it would still enforce the incompressible target mass and erase the desired compression.  For explosive compression tests, use a loose `resamplingParticleMassMax` or disable the mass guard.

## Additive inlet option

The historical hard-cell inlet reservoir rebuilds the inlet band and therefore mostly replaces particles locally.  For pressurisation in a closed full tank, the patch adds:

```text
closedCapacityInletMassFluxEnable = true
closedCapacityInletMassFluxMultiplier = 1.0
```

When enabled together with `closedCapacityResponseEnable=true`, existing particles in the inlet reservoir are not deleted.  Instead, each inlet reservoir cell receives a stochastic number of new particles consistent with the imposed normal inlet velocity:

```text
E[N_added per cell per step] = inletTargetOccupancy * |u_n| * dt / h_n
```

where `h_n` is the normal cell size.  A maintained positive inlet flux can therefore increase total mass and drive the virial response.

## Recommended inlet-only full-tank test

Generate a full fluid state with patch 0145, then run:

```bash
bash scripts/run_closed_capacity_inlet_only_0147.sh
```

Key diagnostics in `summary_runtime.csv`:

```text
capacityOverfillRatio
q6ProjectionStrength
capacityQ6ProjectionFactor
capacityVirialKEffective
capacityVirialPressureMean
capacityVirialKickVelocityRms
resampRemapMassCorrectionStrength
totalMass
```

## Parallelisation impact

The new computations are local reductions and cell-wise loops:

- capacity mass sum: OpenMP reduction over cells;
- virial pressure and gradient: OpenMP loops over cells;
- particle kick: OpenMP loop over particles with a global momentum-reduction correction;
- Q6 modulation: scalar factor computed before scaling the already-computed Q6 correction flux;
- remap attenuation: scalar factor used inside the existing remap pass.

There is no new global elliptic solve, no new neighbour communication pattern, and no new race-prone particle insertion beyond the existing hard-inlet insertion path.  The cost is O(Np + Nc) per step when the response is enabled, and zero except for parameter checks when it is disabled.

## Validity of previous cases

Previous cases remain valid because all new mechanisms are opt-in:

```text
closedCapacityResponseEnable = false   # default
closedCapacityVirialKickEnable = false # default
closedCapacityInletMassFluxEnable = false # default
```

Therefore Q6 strength, resampling remap, mass guard and hard inlet reservoir behaviour remain unchanged for existing runs.  The only case intentionally changing interpretation is the full closed tank with inlet and no outlet, where strict incompressibility is physically inappropriate.

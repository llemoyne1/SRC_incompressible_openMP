# 0067 — Hard inlet reservoir with cell-by-cell density control

This patch separates periodic/recycling boundary semantics from inlet reservoir semantics.

Periodic wrapping and the legacy CUDA-like inlet mode keep a particle identity/recycling logic. That is useful for periodic or visual stress-test cases, but it is not a thermodynamic inlet. For Q9, the mass-flux correction assumes a coherent reservoir flux `J = N u`; therefore the inlet population must be prescribed cell-by-cell.

## New hard inlet mode

Activate with:

```kv
bcLeft = inlet
bcRight = outlet
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = 5
inletTargetOccupancy = 20
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
```

At each boundary update:

1. particles crossing the outlet are deleted;
2. particles backflowing through the inlet are deleted;
3. all particles currently in the inlet reservoir band are deleted;
4. every active reservoir cell is rebuilt with exactly `inletTargetOccupancy` particles;
5. positions are sampled uniformly in each reservoir cell;
6. velocities are sampled around the prescribed inlet velocity;
7. when enabled, each cell is corrected to have the exact prescribed velocity mean and inlet thermal energy.

Consequently, `Np` is no longer expected to be constant. The open domain exchanges particles with the inlet/outlet reservoirs.

## Diagnostics

`summary_runtime.csv` now contains:

```text
inletHardReservoirEnabled
inletReservoirCells
inletReservoirTargetParticles
inletReservoirDeleted
inletBackflowDeleted
outletParticlesDeleted
inletParticlesInserted
inletNetParticleDelta
inletReservoirMeanN
inletReservoirStdN
inletReservoirMinN
inletReservoirMaxN
inletReservoirEmptyFraction
inletMeanUx
inletMeanUy
inletKBT
```

For a clean hard inlet one expects, on active reservoir cells:

```text
inletReservoirStdN = 0
inletReservoirMinN = inletReservoirMaxN = inletTargetOccupancy
inletMeanUx = prescribed inlet Ux
inletKBT = inletKBT or kBT
```

## Backward-step application

The validation launcher is:

```bash
CASE_STEPS=1000 ./scripts/run_backward_step_hard_inlet_validation_0067.sh
```

It runs:

- Q6 hard-inlet backward step;
- Q9 hard-inlet backward step with `q9MassFluxProjectionStrength=1.0`;
- Q9 hard-inlet backward step with `q9MassFluxProjectionStrength=0.25`;
- Q9+virial hard-inlet backward step with `q9MassFluxProjectionStrength=0.25`.

Analyze with:

```matlab
cd matlab
S = analyze_backward_step_hard_inlet_validation_0067('root','..');
```

This patch deliberately tests whether a physically consistent inlet density removes the need for very strong Q9 limiters near the step. If Q9 remains too aggressive, the next step should combine hard inlet with the local Q9 immersed-solid safety limiter, but the inlet density itself should remain hard-imposed.

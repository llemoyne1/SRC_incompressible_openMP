# 0490b — dense species-cell deposit scaffold

This patch adds an opt-in deterministic CPU reference deposit on the physical,
unshifted grid. It does not change Q6, resampling, collision or thermostat.

For each registered species and cell it reconstructs count, mass and momentum,
then derives an occupancy-fraction proxy from
`mass / referenceCellMassDeclared`.

The species declaration accepts an optional sixth field:

```text
speciesK = type name phaseFamily q6StrengthDeclared massClosureStrengthDeclared referenceCellMassDeclared
```

Five-field 0490a declarations remain valid and default to reference mass 1.

Enable the CSV with:

```text
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490b.csv
```

The file contains one row per registered species and cell at step 0 and each
summary step. This CPU path is a future comparison reference for the resident
CUDA deposit and should remain off in production runs.

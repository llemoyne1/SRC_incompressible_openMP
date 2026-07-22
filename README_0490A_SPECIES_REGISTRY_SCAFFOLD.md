# 0490a — Species registry and diagnostics scaffold

## Scope

This patch is deliberately non-physical. It does **not** change SRC collision,
Q6 projection, thermostat, resampling, CUDA kernels or boundary equations.

It adds:

- an opt-in registry mapping particle `type` values to names and phase families;
- declared future Q6 and mass-closure strengths, parsed and reported but unused;
- strict validation of transported Fluid/Latent types when requested;
- validation of segmented inlet species;
- `species_runtime_0490a.csv`, one row per registered/observed species and summary step;
- a small type-1-liquid into type-2-gas smoke test.

Inactive pool slots are intentionally excluded from strict registration because
their `type` is not transported physical mass.

## Parameter syntax

```text
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 water liquid 1.0 1.0
species1 = 2 air gas 0.0 0.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490a.csv
```

Each declaration is:

```text
speciesK = type name phaseFamily q6StrengthDeclared massClosureStrengthDeclared
```

The two strengths are metadata only in 0490a.

## Expected regression property

With `speciesRegistryEnable=false` and `speciesDiagnosticsEnable=false` (the
defaults), legacy parameter files and numerical paths are unchanged except for
the extra compiled source unit, which is not called.

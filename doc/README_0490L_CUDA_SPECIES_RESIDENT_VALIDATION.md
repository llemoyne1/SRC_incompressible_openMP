# 0490l — strict resident CUDA validation for species-aware resampling

## Scope

Patch 0490l closes the correctness-gate phase of the species-aware CUDA
resampling work. It does not add a new physical model. It adds an opt-in strict
validation mode and an integrated smoke suite.

When `speciesResamplingCudaResidentValidationEnable=true`:

- the CPU 0490g species donor/receiver plan is skipped;
- the native 0490k CUDA plan is authoritative;
- the CPU passive extraction-operation mirror is skipped;
- the CUDA 0453 materializer is authoritative after internal validity checks;
- the CUDA 0448 extraction/insertion apply backend is required;
- any path that would fall back to CPU extraction/insertion throws a fatal error.

Legacy behavior is unchanged when the option is disabled.

## Remaining host activity

This gate validates CUDA authority for the species-specific decisions and
particle mutations. The solver still uses host orchestration and downloads
compact diagnostics/state where the existing architecture requires them. The
patch therefore does not claim a zero-host solver loop or deferred final state
download. Those are separate performance milestones.

## Integrated validation

`scripts/run_0490l_cuda_species_resident_validation.sh` reruns the validated
0490h, 0490i, 0490j and 0490f smoke cases with the final binary, then runs a
strict transfer case that requires:

1. zero CPU transfer-plan entries;
2. one accepted native GPU transfer entry;
3. zero CPU passive-operation entries;
4. CUDA operation materialization;
5. CUDA extraction and insertion application;
6. separate liquid/gas mass conservation;
7. rejection of a nearer donor carrying the wrong species;
8. resident species and transfer-plan workspace reuse.

The next milestone after 0490l is a longer multi-seed stability and
non-regression campaign before introducing species-dependent Q6.

# 0490h — resident CUDA species-cell deposit

This patch introduces the first production-facing CUDA field shared by the
species-aware resampling and Q6 roadmaps.

## Resident fields

The `CudaSpeciesCellWorkspace0490h` owns species-major device arrays

- `N_{c,s}` (`count`),
- `M_{c,s}` (`mass`),
- `P_{x,c,s}` and `P_{y,c,s}`,
- raw mass fractions `M_{c,s}/M_c`,
- occupancy fractions based on `M_{c,s}/referenceCellMass_s`,
- liquid and gas occupancy fractions per cell.

The low-level function
`cuda_deposit_species_cell_fields_resident_0490h(...)` consumes an existing
`CudaParticleDeviceView` and leaves all fields on device. Host download exists
only for the 0490h equivalence diagnostic. Later resampling and Q6 patches must
consume `workspace.device_view()` directly.

## Safety and compatibility

- Disabled by default.
- Requires a strict species registry.
- Fluid particles with an unregistered type increment a device counter and fail
  the CPU/CUDA equivalence check.
- Inactive reservoir slots are excluded by role.
- The physical, unshifted grid is used, matching the 0490b CPU reference.
- Existing single-fluid cell moments and Q6 workspaces are unchanged.

## Validation

Enable:

```text
speciesCellCudaDepositEnable = true
speciesCellCudaComparisonFilename = species_cell_cuda_equivalence_0490h.csv
speciesCellCudaComparisonTolerance = 1.0e-12
```

The smoke test compares all resident fields against the deterministic 0490b CPU
deposit at steps 0 and 1, and verifies that the CUDA allocation is reused.

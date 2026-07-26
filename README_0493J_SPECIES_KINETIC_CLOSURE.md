# 0493j — resident species kinetic-energy closure

## Defect

0493i enabled the resident mass/momentum closure for one species and removed the
real momentum drift. The 0493h periodic shear-wave test then isolated a remaining
kinetic-energy drift of about 5.8e-3 over 80 steps.

The cause was structural: 0490i scaled particle masses and applied a momentum
correction, but it did not run the historical remap thermal correction. Reusing
0448 directly is not valid because that backend repeats the old remap, is not
species-local, and downloads masses/velocities to the host.

## Correction

0493j extends the existing 0490h species-cell deposit with total kinetic energy:

    K[c,s] = 1/2 sum_i m_i |v_i|^2

No additional full particle scan is added. The production resident deposit now
accumulates `M`, `Px`, `Py`, and `K` in the same CUDA kernel.

For every mutable species `s` in every cell `c`, 0490i applies the mass factor
`f[c,s]` and an affine velocity transform

    v' = u' + alpha (v - u)

where

    u  = P / M
    u' = P / (f M)

and `alpha` is chosen so that the post-closure total kinetic energy equals the
pre-closure value. Therefore the local species moments satisfy, to roundoff,

    M' = f M
    P' = P
    K' = K

while the matrix balance continues to preserve the global mass of every enabled
species. Disabled species are unchanged.

If the requested local constraints are mathematically incompatible (the kinetic
energy of the preserved momentum at the new mass already exceeds the complete
pre-closure kinetic budget), the resident state is not invalidated. The minimum
compatible kinetic state is used and the event is reported through
`infeasibleKineticCells` and `maxKineticEnergyRelResidual`.

## Diagnostics

`cuda_species_mass_closure_0490i.csv` gains:

- `speciesKineticConservativeBalance`
- `kineticCellsRestored`
- `infeasibleKineticCells`
- `maxKineticEnergyRelResidual`
- `maxKineticScaleDeviation`

The 0493h and 0493g analyzers require an active kinetic closure, zero infeasible
cells, and a kinetic residual below the strict mass tolerance.

## Files changed

- `include/species_cell_fields_0490b.h`
- `src/species_cell_fields_0490b.cpp`
- `include/cuda_species_cell_fields_0490h.h`
- `src/cuda_species_cell_fields_0490h.cu`
- `include/cuda_species_mass_closure_0490i.h`
- `src/cuda_species_mass_closure_0490i.cu`
- `scripts/run_0493g_two_species_moment_restore.sh`
- `scripts/analyze_0493g_two_species_moment_restore.py`
- `scripts/run_0493h_periodic_shear_wave_physics.sh`
- `scripts/analyze_0493h_periodic_shear_wave_physics.py`

## Validation

Build:

```bash
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

Short mono-species dynamic validation:

```bash
RUN_ROOT=runs/0493j_periodic_shear_wave_80 \
CLEAN_RUN_ROOT=1 STEPS=80 DUMP_EVERY=5 SEEDS=493081 LIVE_PROGRESS=1 \
bash scripts/run_0493h_periodic_shear_wave_physics.sh
```

Two-species non-regression:

```bash
RUN_ROOT=runs/0493j_two_species SHORT_STEPS=10 CLEAN_RUN_ROOT=1 LIVE_PROGRESS=1 \
bash scripts/run_0493g_two_species_moment_restore.sh
```

Then rerun the 0493c resident qualification matrix.

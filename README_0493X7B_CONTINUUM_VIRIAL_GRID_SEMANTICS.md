# 0493x7b — continuum virial stiffness and grid diagnostics

0493x7b consolidates the 0493x7a CUDA-resident virial density kick after the K32 three-seed qualification. It is intentionally a **semantic/diagnostic patch**: with an explicit `kVirial` and `betaEOS`, the numerical virial update is unchanged.

## Continuum convention

The production closure is

`Pvir/rhoRef = kVirial * (rawFill - 1)`

`duVir = -betaEOS * dt * grad(Pvir/rhoRef)`

where the finite-volume gradient uses physical `1/dx` and `1/dy` factors. Therefore:

- `kVirial` has code units of velocity squared (`L^2/T^2`);
- `betaEOS` is dimensionless;
- `kVirial` is a material/EOS parameter and **must not be multiplied by dx or dy when the grid is refined at fixed physical domain**;
- explicit temporal stability/resolution is tracked separately through the virial Courant numbers.

The historical `K=0.5` was calibrated with a cell-unit spatial difference and is not the same quantity as the continuum `kVirial` used here. The K32 candidate selected in 0493x7a is `kVirial=0.10666666666666667`, `betaEOS=0.05`. The virial remains disabled by default.

## Diagnostics

Define

`cVir = sqrt(betaEOS * kVirial)`

`Cvir,x = cVir * dt / dx`

`Cvir,y = cVir * dt / dy`.

The x5a/x5b runners print these values and the sparse `cuda_virial_density_0493x7a.csv` gains the columns `effectiveVirialSpeed`, `dx`, `dy`, `virialCFLx`, `virialCFLy`, `gradientDefinition`, and `stiffnessUnits`. The filename is retained deliberately so existing analysis workflows continue to work.

For the reference dam-break (`Lx=2`, `Ly=1`, `Nx=300`, `Ny=150`, `dt=0.005`, K32), `dx=dy=1/150`, `cVir≈0.07303`, and `Cvir≈0.05477`. Refining to `600x300` with `dt=0.0025` keeps the same K, beta and virial Courant number.

## Default behavior

`virialDensityKickEnable=false` remains the default, so pre-virial cases are unchanged. If the virial is enabled without an explicit `kVirial`, the runner/parameter default is now the qualified K32 continuum candidate rather than the historical cell-unit value.

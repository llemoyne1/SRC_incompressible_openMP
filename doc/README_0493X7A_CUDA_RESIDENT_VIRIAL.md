# 0493x7a — CUDA-resident weak virial density kick

This stage ports the historical weak virial/EOS density-restoring mechanism to the validated free-surface Q6-G path after 0493x6h A+B1.

## Scope

- `speciesQ6Mode=free_surface_masked`
- `q6ForceProjectionMode=prestream_single_fused`
- exactly one projected liquid species and one liquid phase
- x6c resident raw liquid fill and x6f pressure domain required
- B1 face-to-particle mapping required
- no gas virial coupling, surface tension, Darcy/chi, immersed solid or open-boundary virial coupling in this first stage

The disabled path is unchanged.

## Closure

The first port isolates the virial part of the historical pressure closure:

`Pvir/rhoRef = Kvirial * (rawFill - 1)`

`duVir = -betaEOS * dt * grad(Pvir/rhoRef)`

`rawFill` is the unbounded x6c liquid mass divided by the declared liquid reference cell mass. The kinetic SRC pressure is *not* explicitly kicked in x7a: classic SRC already carries it, and keeping x7a virial-only makes `Kvirial=0` or `betaEOS=0` an exact no-op for validation.

The kick is bulk-only. A pressure-domain cell touching a phase-pressure exterior neighbour is excluded; physical closed-box boundaries are retained and use the historical one-sided gradient. This avoids applying tensile/pressure forcing directly in gas/interface cells.

## Momentum and CUDA residency

The cell kernel accumulates active liquid mass and raw virial momentum on device. A uniform mass-weighted correction is subtracted from the active liquid bulk when requested, reproducing the historical exact zero-net virial momentum convention.

No host value is needed by the algorithm. `dux/duy` and the temporary species mask are reused for the virial field, so no O(numCells) virial allocation is added. The virial particle update is fused into the already-required final Q6 cell-moment redeposit, so no extra O(Np) particle pass is introduced.

## Parameters

- `virialDensityKickEnable = false` (default)
- `kVirial = 0.50`
- `betaEOS = 0.05`
- `virialMomentumCorrectionEnable = true`

The x5a/x5b runners expose the matching environment variables `VIRIAL_DENSITY_KICK_ENABLE`, `K_VIRIAL`, `BETA_EOS`, and `VIRIAL_MOMENTUM_CORRECTION_ENABLE`.

Sparse diagnostics are written to `cuda_virial_density_0493x7a.csv` at step 1 and `summaryEvery` only.

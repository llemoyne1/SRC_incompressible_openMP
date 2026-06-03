# 0122 — Resampling local thermal renormalization

Patch 0122 completes the first local `M, U, E_th` renormalization stage for the
OpenMP weighted-resampling branch.

It remains opt-in:

```text
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingThermalRenormalizationEnable = true
```

The previous patch 0121 scaled particle masses inside each non-empty wet cell so
that

```text
M_c -> M_target
```

while leaving velocities unchanged.  This preserves the cell velocity `U_c`, but
it also scales the relative thermal energy in cells whose masses were changed.
Patch 0122 records each remapped cell's pre-mass-remap relative thermal energy

```text
E_th,c = 1/2 sum_p m_p |v_p - U_c|^2
```

then, after mass scaling, rescales particle velocities relative to the same cell
velocity:

```text
v_p <- U_c + lambda_c (v_p - U_c)
lambda_c = sqrt(E_th,target / E_th,current)
```

This keeps the remapped cell momentum unchanged while restoring the pre-remap
relative thermal energy.  It does not yet implement mass bounds, mass smoothing,
latent-cell wetting, or species-aware composition constraints.

## Validation

Run:

```bash
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
./scripts/run_resampling_thermal_renormalization_smoke_0122.sh
```

Expected smoke output is of the form:

```text
thermal renorm: cells=... particles=125 Etarget=... Ebefore=... Eafter=... vscaleMin=... vscaleMax=...
[0122 resampling thermal renormalization smoke] OK: local M,U,E_th renormalization restores thermal energy after mass remap.
```

Key checks:

- `resampMRelRms` remains at roundoff after the mass remap;
- `resampThermalRenormEnergyAfter` equals `resampThermalRenormTargetEnergy`;
- thermal-energy residuals are at roundoff;
- momentum residuals are at roundoff;
- `velocityScaleMin < 1` and `velocityScaleMax > 1` in the constructed smoke.

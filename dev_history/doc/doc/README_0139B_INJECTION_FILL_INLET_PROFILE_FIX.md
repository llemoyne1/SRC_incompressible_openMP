# 0139B — Injection/fill inlet profile fix

The first 0139 injection/fill launcher used:

```text
FILL_INLET_PROFILE=flat
```

but the current OpenMP parser accepts only:

```text
uniform, poiseuille_y, poiseuille_y_mean, poiseuille_y_max,
flat_taper_y, flat_taper_y_mean
```

This small corrective patch changes the default to:

```text
FILL_INLET_PROFILE=uniform
```

This keeps the intended one-cell inlet aperture because the aperture itself is controlled separately by:

```text
openBoundaryApertureEnable = true
leftOpenYMin / leftOpenYMax
```

The run can still be overridden from bash, for example:

```bash
FILL_INLET_PROFILE=flat_taper_y \
FILL_INLET_TAPER_CELLS=1.0 \
./scripts/run_injection_fill_resampling_validation_0139.sh
```

No C++ code is modified.

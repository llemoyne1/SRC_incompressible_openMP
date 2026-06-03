# 0154 — canonical static mass-factor tags for wall-load validation

This small cleanup fixes a filename mismatch between the MATLAB state generator
and the shell validation runner used by the closed-capacity wall-load test.

`prepare_closed_capacity_uniform_overfill_suite_0152.m` writes compact numeric
factor tags, for example:

```text
massFactor = 1.00 -> static_mf1.smpcd
massFactor = 1.02 -> static_mf1p02.smpcd
massFactor = 1.05 -> static_mf1p05.smpcd
massFactor = 1.10 -> static_mf1p1.smpcd
```

The previous shell helper converted the literal shell strings directly, so the
default list `1.00 1.02 1.05 1.10` expected `static_mf1p00.smpcd` and
`static_mf1p10.smpcd`.  The runner now canonicalizes each numeric factor with
`awk` using `%.15g` before replacing `.` by `p`, so the expected filenames match
MATLAB's generated names.

No simulation parameter is changed.  This patch only affects state-file lookup,
run labels and generated `params_*.kv` filenames.

## Apply

From the repository root:

```bash
unzip -o SRC_openMP_resampling_0154_files_only.zip
chmod +x scripts/*.sh
```

Then rerun:

```bash
bash scripts/run_closed_capacity_wall_load_validation_0152.sh
```

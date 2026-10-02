# 0493x21k — sigma=1000, n=3, amplitude=4h pilot

Purpose: test whether the failed x21i/x21j sigma=1000 qualification is caused by insufficient signal-to-noise rather than incorrect capillary scaling.

The solver and analyzer are unchanged.  Relative to x21i, only the initial wave amplitude changes:

- sigmaDeclared = 1000
- mode n = 3
- amplitudeCells = 4 (previously 2)
- seeds = 4932501, 4933501, 4934501
- same binary SHA-256, x13h physical chain, viscosity, thermostat, fit window and x12cal thresholds.

For n=3, wavelength = 85.333 cells, hence a/lambda = 0.046875 and k a = 0.294524.  This is used only as a diagnostic pilot; n=2/n=4 are deliberately not launched automatically even after PASS.  First inspect both the unchanged x12cal gate and the same-seed amplitude-linearity diagnostic against x21i (2h).

Outputs:
- `runs/0493x21k_article_capillary_sigma1000_n3_amp4_ensemble/analysis/ensemble_gate_0493x21k_sigma1000_n3_amp4_3seeds.txt`
- `runs/0493x21k_article_capillary_sigma1000_n3_amp4_ensemble/analysis/amplitude_linearity_0493x21k.txt`
- standard x12cal CSVs/traces in the same analysis directory.

No code compilation and no solver source modification are permitted or performed.

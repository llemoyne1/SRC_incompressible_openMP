# GPU patch 0265c — consolidated runner verdict-column filter

## Scope

Patch 0265c fixes only the consolidated validation runner introduced in 0265. It
modifies no CUDA kernel, physical model, boundary-condition implementation, Q6,
resampling, virial, or thermostat code.

## Diagnosis

The periodic child CSV reported after 0265b contains two genuine validation rows:

- `0259_periodic_fused_download_each_step` with `verdict=PASS`;
- `0260_periodic_resident_classic_cuda` with `verdict=PASS`.

It also contains two continuation rows whose first field is a
`*_compare_summary.csv` path and whose `verdict` column is empty. The old
consolidated parser still counted those rows as failures, giving `rows=4 pass=2
fail=2` even though all explicit validation verdicts were `PASS`.

## Fix

The 0265c runner now summarizes child CSVs by the explicit `verdict` column:

- rows with `verdict=PASS` or `verdict=FAIL` are validation rows;
- rows with empty or missing `verdict` are ignored as CSV/path continuation rows;
- if a child process returns a non-zero code, the suite is still forced to
  `FAIL`;
- if no explicit validation row exists, the suite is `FAIL`.

The runner prints a visible banner:

```text
[0265c-consolidated] runner version=0265c_csv_verdict_filter
```

and reports ignored rows in each suite summary.

## Usage

Apply on top of 0265/0265b:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o /path/to/SRC_GPU_0265c_consolidated_verdict_filter_files_only.zip
bash scripts/run_cuda_classic_src_resident_consolidated_0265c.sh
```

For compatibility, `scripts/run_cuda_classic_src_resident_consolidated_0265.sh`
is now a thin wrapper around the 0265c runner.

The patch keeps the validation classic-only, while preserving the future
reactivation path for CPU Q6, resampling, virial, and the separate CUDA
wall/solid/piston/inlet-outlet-aware thermostat chantier.

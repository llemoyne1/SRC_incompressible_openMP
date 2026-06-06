# GPU patch 0251 runner fix

The first 0251 runner invoked `build/src_mpcd_base_cuda_0251` directly. That
binary expects a generated `params.kv` argument, so the run stopped immediately
with:

```text
Usage: build/src_mpcd_base_cuda_0251 params.kv
```

The CSV therefore contained only the header.

This fix makes the 0251 runner use `scripts/run_validation_mono_config_0162.sh`,
as done by the validated 0248--0250 runners. The validation harness generates
the per-case parameter files, runs the grouped case list, writes
`validation_summary_0162.csv`, and then the 0251 runner compares the upload and
persistent modes against the CPU baseline.

Run:

```bash
bash scripts/run_cuda_persistent_cell_state_0251.sh
```

Expected modes:

- `cpu_baseline`
- `0250_upload`
- `0251_persistent`

Expected correctness criterion:

```text
verdict=PASS
failed_metrics=0
```

Primary performance diagnostic:

```text
cellUploadSeconds
```

It should decrease in `0251_persistent` only for cases where the shared CUDA
particle state is still fresh before the cell-moment deposit. CPU-side inlet
injection/reservoir edits can still force the conservative upload fallback.

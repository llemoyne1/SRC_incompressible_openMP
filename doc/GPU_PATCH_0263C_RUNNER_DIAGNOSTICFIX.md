# GPU patch 0263c — runner diagnostic fix for empty CSV

## Purpose

Patch 0263c fixes the validation runner, not the CUDA physics path.

The 0263 runner used `set -euo pipefail` and called `run_validation_logged` as a plain command. When either the baseline validation or the resident validation returned a non-zero status, Bash exited immediately before the script could append a diagnostic row to `cuda_classic_src_io_fullface_resident_0263.csv`.

The symptom is a CSV containing only the header row.

## Change

`run_cuda_classic_src_io_fullface_resident_0263.sh` now captures validation return codes with guarded calls:

```bash
base_rc=0
run_validation_logged ... || base_rc=$?

rc=0
run_validation_logged ... || rc=$?
```

The script then continues far enough to:

- write the CSV row,
- report baseline and resident return codes in the terminal,
- preserve stdout/stderr log paths in the CSV,
- stop afterward when `STOP_ON_FAIL=1`, as before.

## Scope

Modified file:

- `scripts/run_cuda_classic_src_io_fullface_resident_0263.sh`

No CUDA source, C++ source, or physical model logic is changed.

## Expected use

Apply this patch on top of 0263b, then rerun:

```bash
bash scripts/run_cuda_classic_src_io_fullface_resident_0263.sh
```

If the validation still fails, the CSV should now contain one diagnostic row with the failing log paths and return codes printed in the terminal.

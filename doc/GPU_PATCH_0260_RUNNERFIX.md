# GPU patch 0260 runner fix

This fixes `scripts/run_cuda_classic_src_periodic_resident_0260.sh` when run with `set -u`.

## Issue

The runner wrote `summary_every` to the output CSV outside `run_validation_logged()`, where that variable was local. Bash therefore stopped with:

```text
summary_every: unbound variable
```

## Fix

The runner now computes `summary_every_for_grid` in the outer grid loop and writes that value to the CSV. No C++/CUDA source is changed.

## Usage

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o gpu_patch_0260_runnerfix_files_only.zip
bash scripts/run_cuda_classic_src_periodic_resident_0260.sh
```

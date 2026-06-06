# GPU patch 0257 force-rebuild runner fix

This corrective differential updates `scripts/run_cuda_persistent_src_collision_min_download_0257.sh` so the CUDA binary is rebuilt by default before running the 0257 minimal-download validation.

The previous runner only rebuilt when `build/src_mpcd_base_cuda_0257` did not already exist. After applying a source-only corrective zip, this could reuse a stale binary and reproduce the old 4/76 failure.

Default behavior:

```bash
bash scripts/run_cuda_persistent_src_collision_min_download_0257.sh
```

rebuilds `build/src_mpcd_base_cuda_0257` first. To deliberately reuse an already rebuilt binary:

```bash
FORCE_REBUILD=0 bash scripts/run_cuda_persistent_src_collision_min_download_0257.sh
```

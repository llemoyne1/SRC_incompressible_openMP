# 0237 — CUDA resampling active extraction + insertion

This patch extends the resampling CUDA chantier from the active insertion path
(0236) to the extraction role-transition stage.

## Scope

The CPU path remains the default.  The weighted resampling classifier, transfer
plan, donor selection and pool bookkeeping remain host-side and authoritative.
CUDA can now be used for:

- extraction role change: `Fluid -> Inactive` for prevalidated extraction
  particles;
- insertion write-back: inactive slot -> fluid particle in the receiver cell.

This is an intermediate step before moving the whole resampling mutation to
`CudaParticleState`.

## Runtime flags

```bash
MPCD_CUDA_RESAMPLING_EXTRACTION_USE=1
MPCD_CUDA_RESAMPLING_INSERTION_USE=1
```

Strict mode is enabled by default:

```bash
MPCD_CUDA_RESAMPLING_EXTRACTION_STRICT=1
MPCD_CUDA_RESAMPLING_INSERTION_STRICT=1
```

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_resampling_extraction_insertion_active_0237.sh
```

The harness compares:

- `cpu_baseline`
- `cuda_resampling_extraction`
- `cuda_resampling_insertion`
- `cuda_resampling_extract_insert`

Expected acceptance:

- `failed_metrics = 0`
- 0162 comparison `PASS` for all CUDA modes
- no change in physical summaries relative to CPU baseline.

## Notes

The extraction CUDA primitive intentionally updates only roles and downloads the
role array back to the CPU-authoritative state.  This is not yet the final
performance implementation; it is a correctness bridge towards the persistent
GPU particle-state resampling path.

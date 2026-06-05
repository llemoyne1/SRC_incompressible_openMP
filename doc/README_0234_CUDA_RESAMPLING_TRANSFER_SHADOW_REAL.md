# 0234 — CUDA resampling transfer shadow on real deposits

This patch advances the CUDA resampling work from synthetic shadow-transfer tests to the real resampling deposit path.

## Scope

The simulation dynamics remain CPU-authoritative.  When enabled, the CUDA path:

1. uses the real `WeightedRealFluidDepositWorkspace` built by `deposit_weighted_real_fluid`,
2. consumes the real CPU donor-particle selection diagnostics,
3. builds a conservative bounded shadow-transfer problem on temporary particle arrays,
4. applies the CUDA mutation primitive from 0233 on those temporary arrays,
5. compares against an equivalent CPU shadow mutation,
6. writes conservation and mismatch diagnostics.

No production particle state is modified by CUDA in this patch.

## Runtime flags

Enable the existing guard shadow and the new transfer shadow with:

```bash
MPCD_CUDA_RESAMPLING_SHADOW=1
MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW=1
```

The transfer shadow writes to:

```bash
MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_CSV=<path>
```

Use non-strict mode for diagnostic sweeps:

```bash
MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_STRICT=0
```

A conservative limit avoids turning the validation into a very heavy run:

```bash
MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_MAX_TRANSFERS=4096
```

`0` means no cap.

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_resampling_transfer_shadow_0234.sh
```

The consolidated CSV is:

```text
dev_history/artifacts/gpu_cuda_resampling_0234/cuda_resampling_transfer_shadow_0234.csv
```

A passing run should satisfy:

```text
verdict = PASS
failed_metrics = 0
transferRows > 0
transferCellMismatch = 0
transferRoleMismatch = 0
transferMassMaxAbs <= roundoff
transferMassConservationMaxAbs <= roundoff
transferPxConservationMaxAbs <= roundoff
transferPyConservationMaxAbs <= roundoff
```

## Interpretation

This is still a shadow/copy stage.  It validates that the CUDA mutation primitive can consume real resampling selection data and conserve mass/momentum on copied particle arrays.  The next step is a GPU shadow closer to the production insertion/extraction semantics, then a controlled active path.

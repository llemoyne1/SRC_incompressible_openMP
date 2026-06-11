# GPU patch 0330b — immersed circle fast diagnostics compile fix

This is a script/code-only correction to patch 0330.

## Change

`src/cuda_immersed_circle_0284.cu` now defines the helper:

```cpp
bool cuda_immersed_circle_0330_fast_diagnostics_requested();
```

inside the anonymous namespace before it is used in `try_apply_cuda_immersed_circle_0284`.

The runtime behavior remains the same as intended by 0330:

```bash
MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330=1
```

skips the immersed-circle hit-counter diagnostic allocation/memset/copy/free while keeping the CUDA reflection kernel active.

## Expected runner marker

```text
[0330b-demo] IMMERSED_CIRCLE_FAST_DIAG_0330=1
```

# GPU patch 0241 compile fix — CUDA double atomic compatibility

## Problem

`src/cuda_cell_moments.cu` used `atomicAdd(double*, double)` directly.
That overload is available natively only for CUDA device architectures `sm_60`
and newer.  When `scripts/build_src_mpcd_cuda_0241.sh` left
`CUDA_ARCH_FLAGS` empty, `nvcc` could select an older default target and reject
the double-precision overload during compilation.

## Fix

This corrective archive changes two files:

- `src/cuda_cell_moments.cu`
  - adds `atomic_add_double_compat()`;
  - uses native `atomicAdd(double*, double)` for `__CUDA_ARCH__ >= 600`;
  - uses a standard `atomicCAS` fallback below `sm_60`.

- `scripts/build_src_mpcd_cuda_0241.sh`
  - gives `CUDA_ARCH_FLAGS` a safe default:
    `compute_60/sm_60 + compute_60 PTX`;
  - still allows full override, for example:
    `CUDA_ARCH_FLAGS="--arch=sm_89" bash scripts/build_src_mpcd_cuda_0241.sh`.

## Recommended validation

```bash
bash scripts/run_cuda_resampling_persistent_active_path_0241.sh
```

For an Ada/RTX 40xx class GPU, this faster architecture-specific build is also
valid:

```bash
CUDA_ARCH_FLAGS="--arch=sm_89"   bash scripts/run_cuda_resampling_persistent_active_path_0241.sh
```

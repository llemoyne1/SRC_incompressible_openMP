# 0307 build fix — adaptive flag object linkage

The 0307 build script must link the CUDA adaptive support-flag diagnostic module
introduced earlier as `src/cuda_resampling_adaptive_flag_0304.cu`.

When `src_mpcd_base.cpp` contains calls to
`cuda_resampling_adaptive_flag_0304_requested(...)` and
`try_run_cuda_resampling_adaptive_flag_0304(...)`, omitting that translation
unit from the `nvcc` link line produces undefined references at link time.

This fix only updates `scripts/build_src_mpcd_cuda_0307.sh` by adding:

```bash
src/cuda_resampling_adaptive_flag_0304.cu \
```

to the existing CUDA source list. It does not change the C++/CUDA runtime logic.

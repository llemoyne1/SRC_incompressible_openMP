# 0234b — CUDA resampling transfer shadow compile fix

This micro-patch fixes the compilation error introduced in patch 0234 in `src/weighted_resampling.cpp`.

The 0234 implementation uses `std::unordered_set` to enforce unique donor/receiver selection in the CUDA transfer-shadow construction, but the corresponding standard header was missing.

Change:

```cpp
#include <unordered_set>
```

No numerical logic is changed.

## Validation

Rebuild and relaunch the 0234 harness:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_resampling_transfer_shadow_0234.sh
```

Expected result: compilation succeeds; validation can then proceed to the runtime shadow-transfer checks.

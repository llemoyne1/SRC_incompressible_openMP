# GPU patch 0285b — build fix for CUDA circle + inlet/outlet

Patch 0285 introduced the circular immersed solid into the full-face
inlet/outlet CUDA resident SRC classic path, reusing the circle module created
by patch 0284.

The first 0285 build script accidentally referenced a non-existing source file:

```text
src/cuda_immersed_circle_0285.cu
```

The circle implementation is intentionally still the 0284 module:

```text
include/cuda_immersed_circle_0284.h
src/cuda_immersed_circle_0284.cu
```

This corrective patch updates only the 0285 build script so that it compiles the
existing 0284 circle module and defines the matching feature macro:

```text
-DMPCD_ENABLE_CUDA_IMMERSED_CIRCLE_0284
src/cuda_immersed_circle_0284.cu
```

No CUDA kernel, runtime path, validation script, Q6, resampling or virial code is
changed. The intended 0285 execution path remains:

```text
full-face inlet/outlet CUDA resident
+ circular immersed-solid CUDA reflection/deposit support from 0284
+ persistent SRC classic CUDA collision
+ fused CUDA thermostat
```

Apply after 0284 and 0285:

```bash
unzip -o SRC_GPU_0285b_cuda_circle_io_buildfix_files_only.zip
bash scripts/build_src_mpcd_cuda_0285.sh
```

Then rerun the 0285 smoke:

```bash
GRID_CASES="64:64:120" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_circle_io_0285.sh
```

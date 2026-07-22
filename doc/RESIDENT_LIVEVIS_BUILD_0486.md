# 0486 — livevis-enabled CUDA resident builder

Purpose: build the current resident CUDA/Q6/resampling binary with live visualization actually compiled in.

The generic 0400 builder only enables livevis when `MPCD_ENABLE_LIVE_VIS=1` is passed. Binaries compiled without that macro will run, but livevis remains a stub and prints a warning when `SRC_LIVE_VIS_ENABLE=1` is requested.

This builder forces:

- `-DMPCD_ENABLE_LIVE_VIS`
- the resident Q6/resampling macro set through 0484/0485
- GLFW/OpenGL link flags

Default output:

```bash
build/src_mpcd_base_cuda_q6_resident_livevis_0486
```

Build:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

If GLFW is installed in a non-standard prefix:

```bash
MPCD_LIVEVIS_CFLAGS='-I/path/to/glfw/include' \
MPCD_LIVEVIS_LIBS='-L/path/to/glfw/lib -lglfw -lGL -ldl -lpthread' \
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

Smoke:

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_livevis_0486 \
LIVE_VIS_ENABLE=1 \
RUN_MODES='src-resampling' \
bash scripts/run_0486_livevis_tg_smoke.sh
```

Expected solveur runs: 1.

Runtime distinction:

- `live visualization requested but binary was not built with MPCD_ENABLE_LIVE_VIS=1`: wrong binary.
- `glfwInit() failed` or `glfwCreateWindow() failed`: binary is livevis-capable, but display/OpenGL/WSLg is not available.

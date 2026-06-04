# 0186 — CUDA-only backend start for `SRC_GPU`

This patch records the backend decision for the `SRC_GPU` branch: the prototype
will use CUDA first.  The objective is to demonstrate numerical value on the
current NVIDIA workstation before investing in portability layers such as
Kokkos, SYCL, HIP or OpenCL.

## Scope

Patch 0186 is intentionally narrow:

- keep the validated CPU/OpenMP path as the default for full simulations;
- remove OpenMP-target from the accepted production backend list;
- keep `projectionBackend=auto` as an explicit CPU fallback;
- keep `projectionBackend=cuda` rejected in the full Q6 path until a complete
  CUDA CG path is actually wired;
- add a first CUDA numerical primitive for the Q6/elliptic solve:
  application of an `EllipticOperatorPlan` plus the associated `pAp` dot
  product;
- add a dedicated CUDA smoke validator that compares this primitive against a
  CPU reference on a periodic grid.

This avoids a dangerous intermediate state where a run says `cuda` but silently
executes only a partial GPU path.

## New files

```text
include/cuda_q6_backend.h
src/cuda_q6_backend.cu
src/main_validate_cuda_q6_backend_0186.cpp
scripts/build_cuda_q6_backend_0186.sh
scripts/run_cuda_q6_backend_smoke_0186.sh
doc/README_0186_CUDA_ONLY_BACKEND_START.md
dev_history/artifacts/gpu_cuda_backend_0186/cuda_backend_manifest_0186.csv
dev_history/artifacts/gpu_cuda_backend_0186/cuda_backend_scope_0186.csv
```

The patch also updates:

```text
src/params_io_base.cpp
src/q6_projection_adapter.cpp
scripts/run_gpu_projection_backend_scaffold_0184.sh
```

## Build and smoke test

From the dedicated worktree:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
bash scripts/run_cuda_q6_backend_smoke_0186.sh
```

Useful overrides:

```bash
NX=128 NY=96 TOLERANCE=1e-10 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/run_cuda_q6_backend_smoke_0186.sh
```

If CUDA is available, the validator should print a line of the form:

```text
CUDA_Q6_BACKEND_0186 PASS nx=64 ny=48 ... relPApDiff=... maxAbsAphiDiff=...
```

The script writes:

```text
dev_history/artifacts/gpu_cuda_backend_0186/cuda_q6_backend_smoke_0186.log
dev_history/artifacts/gpu_cuda_backend_0186/cuda_q6_backend_smoke_0186.csv
```

## Full simulation behavior after 0186

Full simulations remain CPU/OpenMP by default:

```text
projectionBackend = cpu
```

or:

```text
projectionBackend = auto
```

`projectionBackend=cuda` still fails explicitly in the full Q6 path.  This is
intentional: patch 0186 validates the first CUDA primitive but does not yet make
CG iterations, residual updates, mean removal and correction-flux construction a
complete CUDA implementation.

## Next numerical step

The natural next patch is to add a CUDA CG micro-solver around this primitive,
still outside full SRC/MPCD runs.  The safe sequence is:

1. CUDA operator + pAp dot product — done in 0186;
2. CUDA vector updates for `phi`, `r`, `p`, `Ap` and residual dot products;
3. CUDA mean-removal/gauge handling;
4. standalone CPU/GPU comparison of `project_face_field` on periodic and
   channel grids;
5. only then allow `projectionBackend=cuda` inside full Q6 simulations.

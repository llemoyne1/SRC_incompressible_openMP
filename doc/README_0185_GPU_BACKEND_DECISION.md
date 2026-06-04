# Patch 0185 — GPU backend decision and local toolchain audit

## Scope

This patch does not change the numerical solver. It adds a local GPU/toolchain inventory script and records the backend decision logic for the `SRC_GPU` branch.

Expected working tree convention:

```text
root:   /mnt/e/SRC_MPCD_dev/SRC_GPU
branch: SRC_GPU
base:   clean/openmp-light + patches 0183/0184
```

## Why this patch comes before a real GPU kernel

Patch 0184 introduced the runtime contract:

```text
projectionBackend = cpu | auto | openmp_target | cuda
```

The validation output of 0184 should show that `cpu` and `auto` are physically identical on the four short validation cases. The next risk is not numerical yet; it is architectural: choosing a GPU programming model too early can force a costly rewrite of the memory layout, build system and reduction strategy.

This patch therefore makes the backend choice explicit before implementing kernels.

## Backend options for this project

### 1. OpenMP target

Advantages:

- smallest conceptual jump from the existing OpenMP code;
- potentially low source-code disruption;
- compatible with the current idea of `projectionBackend=openmp_target`;
- useful for a first Q6/elliptic proof of concept.

Risks:

- compiler flags and runtime configuration differ strongly between GCC, LLVM/Clang, NVIDIA and AMD systems;
- reductions in CG may need careful treatment;
- performance portability is not guaranteed;
- debugging failed offload can be less transparent than explicit CUDA/HIP.

Recommended role: first experimental backend only if the local toolchain smoke test succeeds.

### 2. CUDA

Advantages:

- most direct and mature route for NVIDIA GPUs;
- best control over reductions, memory layout, streams and later particle kernels;
- natural fit for Q6/CG sparse-stencil operations and future particle binning.

Risks:

- NVIDIA-specific;
- introduces `.cu` compilation and a distinct compiler path;
- more intrusive build-system changes than OpenMP target.

Recommended role: best performance backend if the target machine is NVIDIA and portability is secondary.

### 3. HIP/ROCm

Advantages:

- natural route for AMD GPUs;
- CUDA-like programming model;
- can become useful if the target cluster is AMD-based.

Risks:

- not useful unless AMD GPU/ROCm is actually available;
- still vendor-oriented;
- would duplicate much of the CUDA backend unless abstracted carefully.

Recommended role: defer unless AMD hardware is confirmed as a primary target.

### 4. Kokkos

Advantages:

- strong long-term portability layer;
- can target CUDA, HIP, SYCL and OpenMP-like backends;
- suitable if the code is expected to run on heterogeneous HPC platforms.

Risks:

- significant dependency and programming-model shift;
- likely requires restructuring arrays and kernels around Kokkos views/execution spaces;
- too heavy for the very first Q6 backend prototype.

Recommended role: strong candidate after the first backend boundary is proven; not the first patch.

### 5. SYCL / oneAPI

Advantages:

- portability-oriented C++ model;
- possible route to Intel, NVIDIA and AMD through oneAPI ecosystem/toolchains.

Risks:

- heavier toolchain decision;
- runtime/device support must be checked locally;
- less aligned with the existing OpenMP code than OpenMP target.

Recommended role: keep under observation; do not make it the first dependency.

## Project recommendation after 0184

The next numerical backend should still target Q6/elliptic projection first, because this part of the code is regular, cell-based and easier to compare against CPU than particle resampling or collision.

Recommended decision sequence:

1. run the 0185 toolchain audit locally;
2. archive the generated CSV/Markdown with the validation results;
3. if OpenMP target smoke works, implement a very small `openmp_target` Q6 vector/stencil kernel first;
4. if OpenMP target is unavailable or unstable but CUDA is cleanly available, implement a CUDA backend for the same Q6 operator boundary;
5. keep CPU OpenMP as reference and keep `projectionBackend=cpu` as default until a full CPU/GPU validation suite passes.

## Usage

From the dedicated GPU branch:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
bash scripts/detect_gpu_toolchain_0185.sh
```

Optional compile probes:

```bash
bash scripts/detect_gpu_toolchain_0185.sh --try-compile
```

For OpenMP target, flags are intentionally not guessed. Provide them explicitly, for example:

```bash
OPENMP_TARGET_CXX=clang++ \
OPENMP_TARGET_FLAGS='-fopenmp -fopenmp-targets=nvptx64-nvidia-cuda' \
bash scripts/detect_gpu_toolchain_0185.sh --try-compile
```

Outputs:

```text
dev_history/artifacts/gpu_backend_decision_0185/gpu_toolchain_inventory_0185.csv
dev_history/artifacts/gpu_backend_decision_0185/gpu_toolchain_summary_0185.md
```

## Non-goals

This patch does not:

- add a GPU kernel;
- change Q6 projection numerics;
- change collision, thermostat or resampling;
- add Kokkos, CUDA, HIP or SYCL as mandatory dependencies;
- modify the production stripped branch.

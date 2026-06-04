# Patch 0187 — CUDA-only standalone Q6/elliptic CG

This patch advances the CUDA-only branch from the 0186 primitive

```text
Aphi = A p,    pAp = <p, A p>
```

to a complete **standalone conjugate-gradient loop** operating on an already-built
`EllipticOperatorPlan`.

The full SRC/MPCD simulation path is still not wired to CUDA in this patch.
`projectionBackend=cpu` remains the validated default path. `projectionBackend=auto`
continues to fall back to CPU. `projectionBackend=cuda` must still fail explicitly in
full simulations until a later patch routes the real Q6 projection through the CUDA CG.

## Scope

Added/extended files:

```text
include/cuda_q6_backend.h
src/cuda_q6_backend.cu
src/main_validate_cuda_q6_cg_0187.cpp
scripts/build_cuda_q6_cg_0187.sh
scripts/run_cuda_q6_cg_smoke_0187.sh
doc/README_0187_CUDA_Q6_STANDALONE_CG.md
dev_history/artifacts/gpu_cuda_cg_0187/cuda_q6_cg_scope_0187.csv
dev_history/artifacts/gpu_cuda_cg_0187/cuda_q6_cg_manifest_0187.csv
```

## New CUDA API

```cpp
bool cuda_q6_solve_cg_operator_plan(
    const EllipticOperatorPlan& plan,
    const std::vector<double>& rhs,
    std::vector<double>& phi,
    const CudaQ6CgParams& params,
    CudaQ6CgDiagnostics* diagnostics = nullptr);
```

The function allocates the operator plan and CG vectors on the GPU once, then keeps
`phi`, `r`, `p` and `Ap` device-resident through the iteration loop. Host/device traffic
inside the loop is currently limited to scalar block reductions (`pAp`, `rrNew`). This is
not yet the final performance design, but it validates the numerical algebra before
simulation coupling.

## Build

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
bash scripts/build_cuda_q6_cg_0187.sh
```

For the NVIDIA RTX 4000 Ada generation used in the local audit, an explicit architecture
flag can be supplied:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' bash scripts/build_cuda_q6_cg_0187.sh
```

## Smoke test

```bash
bash scripts/run_cuda_q6_cg_smoke_0187.sh
```

Larger test:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
NX=128 NY=96 MAX_IT=1500 TOLERANCE=1e-11 PHI_TOLERANCE=1e-8 \
bash scripts/run_cuda_q6_cg_smoke_0187.sh
```

The script writes:

```text
dev_history/artifacts/gpu_cuda_cg_0187/cuda_q6_cg_smoke_0187.log
dev_history/artifacts/gpu_cuda_cg_0187/cuda_q6_cg_smoke_0187.csv
```

## Expected behavior

A successful run prints a line beginning with:

```text
CUDA_Q6_CG_0187 PASS
```

The smoke test compares:

- a CPU reference CG on the same finite-volume operator plan;
- the CUDA standalone CG;
- both reconstructions against a manufactured mean-free periodic scalar field.

The final check intentionally verifies that a full simulation with
`projectionBackend=cuda` still fails explicitly. This prevents a misleading state where
only the standalone CG exists but the full Q6 projection silently reverts to CPU.

## Next step after 0187

Patch 0188 should wire this standalone CG into `project_face_field()` behind an explicit
CUDA compile/runtime guard, but only for the safest first subset:

```text
projectionBackend=cuda
periodic or simple active-cell plan
Q6 projection path
CPU comparison scripts preserved
```

The CPU/OpenMP path must remain the default and the reference.

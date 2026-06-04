# 0188 — First integrated CUDA Q6 projection path: periodic Taylor--Green subset

This patch is the first simulation-level CUDA integration on the `SRC_GPU`
branch.  It follows the CUDA-only decision made after the 0185/0186 toolchain
checks and the 0187 standalone CG validation.

## Scope

Patch 0188 wires the existing standalone CUDA CG solver into the generic
elliptic projection core used by Q6, but only for the first low-risk subset:

- `projectionBackend = cuda`;
- CUDA-enabled executable built with `MPCD_ENABLE_CUDA_Q6`;
- fully periodic elliptic boundary conditions in x and y;
- no projection mask / no immersed-solid active subset;
- all cells active in the operator plan.

This is the Taylor--Green periodic validation target.  Non-periodic channel,
open-boundary, immersed-solid, obstacle, piston and Von Karman cases remain on
CPU/OpenMP for now and fail explicitly if `projectionBackend=cuda` is requested.

## Why this limited subset

The 0187 standalone solver showed that the CUDA CG algebra matches the CPU CG on
an already-built `EllipticOperatorPlan`.  The next risk is not the algebra but
simulation coupling: runtime parameters, Q6 projection call path, executable
build, diagnostics, and CPU/CUDA comparison.  A periodic unmasked target isolates
that coupling while avoiding boundary/mask complexity.

## Build

The historical CPU build is unchanged:

```bash
bash scripts/build_src_mpcd_base.sh
```

The CUDA integration build is separate:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
  bash scripts/build_src_mpcd_cuda_0188.sh
```

It creates:

```text
build/src_mpcd_base_cuda_0188
```

The CPU/OpenMP path remains the default runtime backend even in this CUDA-linked
binary.

## Validation

Run the integrated Taylor--Green comparison:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
NX=64 NY=64 GAMMA=20 STEPS=1000 THREADS=8 \
bash scripts/run_cuda_q6_tg_integration_0188.sh
```

The script performs:

1. a CPU reference run using the CUDA-enabled executable with
   `projectionBackend=cpu`;
2. a CUDA run with `projectionBackend=cuda`;
3. a final-row metric comparison using `compare_validation_mono_config_0162.py`;
4. an expected-failure guard showing that a non-periodic Poiseuille case is still
   rejected by the CUDA backend.

Outputs are written under:

```text
runs/cuda_q6_tg_cpu_ref_0188/
runs/cuda_q6_tg_cuda_0188/
dev_history/artifacts/gpu_cuda_integration_0188/
```

The comparison files are:

```text
dev_history/artifacts/gpu_cuda_integration_0188/cuda_q6_tg_compare_0188.csv
dev_history/artifacts/gpu_cuda_integration_0188/cuda_q6_tg_compare_summary_0188.csv
```

## Runtime semantics

`projectionBackend=cpu` always uses the validated CPU/OpenMP path.

`projectionBackend=auto` remains an explicit CPU fallback.

`projectionBackend=cuda` now enters the CUDA CG path only in a CUDA-enabled
binary and only for the fully periodic, unmasked subset.  Otherwise it throws a
clear runtime error.  Silent fallback is intentionally avoided.

## Next step

If this periodic TG integration passes, the next extension should be either:

1. support periodic-x / wall-y Poiseuille in the same CUDA CG path; or
2. add CUDA-vs-CPU phase timing for the Q6 projection block before broadening the
   geometry support.

The safest physical sequence is TG first, then Poiseuille wall, then obstacle or
backward step, then piston/virial, then Von Karman.

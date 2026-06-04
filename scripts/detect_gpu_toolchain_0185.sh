#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="dev_history/artifacts/gpu_backend_decision_0185"
TRY_COMPILE=0

usage() {
  cat <<'USAGE'
Usage: scripts/detect_gpu_toolchain_0185.sh [--out DIR] [--try-compile]

Read-only GPU/backend inventory for SRC_GPU.
It detects available GPU hardware, compilers and runtime stacks relevant to
OpenMP target, CUDA, HIP/ROCm, SYCL/oneAPI and Kokkos decisions.

Outputs:
  gpu_toolchain_inventory_0185.csv
  gpu_toolchain_summary_0185.md

Optional compile probes are deliberately conservative:
  --try-compile
      tries only local smoke compilations when the corresponding compiler is found.
      OpenMP-target compilation is attempted only if OPENMP_TARGET_CXX and
      OPENMP_TARGET_FLAGS are set, because flags are platform/compiler dependent.

Examples:
  bash scripts/detect_gpu_toolchain_0185.sh
  bash scripts/detect_gpu_toolchain_0185.sh --try-compile
  OPENMP_TARGET_CXX=clang++ \
  OPENMP_TARGET_FLAGS='-fopenmp -fopenmp-targets=nvptx64-nvidia-cuda' \
  bash scripts/detect_gpu_toolchain_0185.sh --try-compile
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_DIR="$2"; shift 2;;
    --try-compile)
      TRY_COMPILE=1; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2;;
  esac
done

mkdir -p "$OUT_DIR"
CSV="$OUT_DIR/gpu_toolchain_inventory_0185.csv"
MD="$OUT_DIR/gpu_toolchain_summary_0185.md"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

csv_escape() {
  local s="${1:-}"
  s="${s//$'\r'/ }"
  s="${s//$'\n'/ ; }"
  s="${s//\"/\"\"}"
  printf '"%s"' "$s"
}

emit() {
  local category="$1" name="$2" status="$3" detail="$4" recommendation="$5"
  {
    csv_escape "$category"; printf ','
    csv_escape "$name"; printf ','
    csv_escape "$status"; printf ','
    csv_escape "$detail"; printf ','
    csv_escape "$recommendation"; printf '\n'
  } >> "$CSV"
}

cmd_path() {
  command -v "$1" 2>/dev/null || true
}

cmd_first_line() {
  local cmd="$1"
  shift || true
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" "$@" 2>&1 | head -n 1 || true
  fi
}

cmd_all() {
  local cmd="$1"
  shift || true
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" "$@" 2>&1 || true
  fi
}

try_compile_cuda() {
  local nvcc_path
  nvcc_path="$(cmd_path nvcc)"
  if [[ -z "$nvcc_path" ]]; then
    emit "compile" "cuda_smoke" "skipped" "nvcc not found" "Install CUDA toolkit or use another backend."
    return
  fi
  cat > "$TMP_DIR/cuda_smoke.cu" <<'CU'
#include <cstdio>
__global__ void set_one(double* x) { x[0] = 1.0; }
int main() {
  double *d = nullptr;
  cudaError_t err = cudaMalloc(&d, sizeof(double));
  if (err != cudaSuccess) return 2;
  set_one<<<1,1>>>(d);
  err = cudaDeviceSynchronize();
  cudaFree(d);
  return err == cudaSuccess ? 0 : 3;
}
CU
  if nvcc "$TMP_DIR/cuda_smoke.cu" -o "$TMP_DIR/cuda_smoke" >/tmp/src_gpu_cuda_smoke_0185.log 2>&1; then
    if "$TMP_DIR/cuda_smoke" >/tmp/src_gpu_cuda_smoke_run_0185.log 2>&1; then
      emit "compile" "cuda_smoke" "pass" "nvcc compile and runtime launch succeeded" "CUDA is viable for a real NVIDIA backend."
    else
      emit "compile" "cuda_smoke" "compile_pass_run_fail" "compile OK; runtime failed; see /tmp/src_gpu_cuda_smoke_run_0185.log" "Check driver/GPU access before implementing CUDA kernels."
    fi
  else
    emit "compile" "cuda_smoke" "fail" "see /tmp/src_gpu_cuda_smoke_0185.log" "CUDA compiler present but unusable for this smoke test."
  fi
}

try_compile_hip() {
  local hipcc_path
  hipcc_path="$(cmd_path hipcc)"
  if [[ -z "$hipcc_path" ]]; then
    emit "compile" "hip_smoke" "skipped" "hipcc not found" "HIP is not currently available."
    return
  fi
  cat > "$TMP_DIR/hip_smoke.cpp" <<'HIP'
#include <hip/hip_runtime.h>
__global__ void set_one(double* x) { x[0] = 1.0; }
int main() {
  double *d = nullptr;
  hipError_t err = hipMalloc(&d, sizeof(double));
  if (err != hipSuccess) return 2;
  set_one<<<1,1>>>(d);
  err = hipDeviceSynchronize();
  hipFree(d);
  return err == hipSuccess ? 0 : 3;
}
HIP
  if hipcc "$TMP_DIR/hip_smoke.cpp" -o "$TMP_DIR/hip_smoke" >/tmp/src_gpu_hip_smoke_0185.log 2>&1; then
    if "$TMP_DIR/hip_smoke" >/tmp/src_gpu_hip_smoke_run_0185.log 2>&1; then
      emit "compile" "hip_smoke" "pass" "hipcc compile and runtime launch succeeded" "HIP is viable for AMD-oriented kernels."
    else
      emit "compile" "hip_smoke" "compile_pass_run_fail" "compile OK; runtime failed; see /tmp/src_gpu_hip_smoke_run_0185.log" "Check ROCm runtime/GPU access before implementing HIP kernels."
    fi
  else
    emit "compile" "hip_smoke" "fail" "see /tmp/src_gpu_hip_smoke_0185.log" "HIP compiler present but unusable for this smoke test."
  fi
}

try_compile_openmp_target() {
  if [[ -z "${OPENMP_TARGET_CXX:-}" || -z "${OPENMP_TARGET_FLAGS:-}" ]]; then
    emit "compile" "openmp_target_smoke" "skipped" "Set OPENMP_TARGET_CXX and OPENMP_TARGET_FLAGS to attempt target offload." "Use this only after identifying the local compiler/GPU stack."
    return
  fi
  cat > "$TMP_DIR/omp_target_smoke.cpp" <<'OMP'
#include <cstdio>
int main() {
  double x = 0.0;
  #pragma omp target map(tofrom:x)
  { x = 1.0; }
  return (x == 1.0) ? 0 : 4;
}
OMP
  # shellcheck disable=SC2086
  if ${OPENMP_TARGET_CXX} ${OPENMP_TARGET_FLAGS} "$TMP_DIR/omp_target_smoke.cpp" -o "$TMP_DIR/omp_target_smoke" >/tmp/src_gpu_omp_target_smoke_0185.log 2>&1; then
    if "$TMP_DIR/omp_target_smoke" >/tmp/src_gpu_omp_target_smoke_run_0185.log 2>&1; then
      emit "compile" "openmp_target_smoke" "pass" "compile and run succeeded with ${OPENMP_TARGET_CXX} ${OPENMP_TARGET_FLAGS}" "OpenMP target is viable for the first Q6 backend prototype."
    else
      emit "compile" "openmp_target_smoke" "compile_pass_run_fail" "compile OK; runtime failed; see /tmp/src_gpu_omp_target_smoke_run_0185.log" "Offload toolchain exists but runtime access/configuration needs repair."
    fi
  else
    emit "compile" "openmp_target_smoke" "fail" "see /tmp/src_gpu_omp_target_smoke_0185.log" "Compiler/flags are not sufficient for OpenMP target on this machine."
  fi
}

printf 'category,name,status,detail,recommendation\n' > "$CSV"

emit "context" "pwd" "info" "$(pwd)" "Expected root is /mnt/e/SRC_MPCD_dev/SRC_GPU."
emit "context" "git_branch" "info" "$(git branch --show-current 2>/dev/null || echo unknown)" "Expected branch is SRC_GPU."
emit "context" "git_head" "info" "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" "Keep this value with validation outputs."

for c in nvidia-smi nvcc clang++ g++ hipcc rocm-smi rocminfo icpx dpcpp sycl-ls cmake make python3; do
  p="$(cmd_path "$c")"
  if [[ -n "$p" ]]; then
    case "$c" in
      nvidia-smi) v="$(cmd_first_line nvidia-smi --version)";;
      nvcc) v="$(cmd_first_line nvcc --version)";;
      clang++) v="$(cmd_first_line clang++ --version)";;
      g++) v="$(cmd_first_line g++ --version)";;
      hipcc) v="$(cmd_first_line hipcc --version)";;
      rocm-smi) v="$(cmd_first_line rocm-smi --version)";;
      rocminfo) v="$(cmd_first_line rocminfo)";;
      icpx) v="$(cmd_first_line icpx --version)";;
      dpcpp) v="$(cmd_first_line dpcpp --version)";;
      sycl-ls) v="$(cmd_first_line sycl-ls)";;
      *) v="$(cmd_first_line "$c" --version)";;
    esac
    emit "command" "$c" "present" "$p ; $v" "Available for backend/toolchain decisions."
  else
    emit "command" "$c" "missing" "not found in PATH" "Not available in the current shell."
  fi
done

if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_info="$(nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv,noheader 2>&1 || true)"
  emit "hardware" "nvidia_gpu" "info" "$gpu_info" "CUDA or OpenMP target to NVIDIA may be relevant."
else
  emit "hardware" "nvidia_gpu" "unknown" "nvidia-smi unavailable" "No NVIDIA runtime detected from PATH."
fi

if command -v rocm-smi >/dev/null 2>&1; then
  rocm_info="$(rocm-smi --showproductname --showdriverversion 2>&1 | head -n 20 || true)"
  emit "hardware" "amd_gpu_rocm" "info" "$rocm_info" "HIP, OpenMP target AMDGPU or Kokkos/HIP may be relevant."
else
  emit "hardware" "amd_gpu_rocm" "unknown" "rocm-smi unavailable" "No ROCm runtime detected from PATH."
fi

for e in CUDA_HOME CUDA_PATH HIP_PATH ROCM_PATH ONEAPI_ROOT OMP_TARGET_OFFLOAD LD_LIBRARY_PATH PATH; do
  emit "environment" "$e" "info" "${!e:-}" "Recorded for reproducibility."
done

if [[ "$TRY_COMPILE" -eq 1 ]]; then
  try_compile_cuda
  try_compile_hip
  try_compile_openmp_target
else
  emit "compile" "compile_probes" "skipped" "Run with --try-compile to test CUDA/HIP/OpenMP-target smoke programs." "Do this before starting a real backend implementation."
fi

cat > "$MD" <<MD
# GPU backend/toolchain inventory 0185

Generated by:

\`\`\`bash
bash scripts/detect_gpu_toolchain_0185.sh${TRY_COMPILE:+ --try-compile}
\`\`\`

Main CSV output:

\`\`\`text
$CSV
\`\`\`

Recommended interpretation for SRC_GPU:

1. If CUDA hardware/toolchain is clearly available and portability is secondary, CUDA is the most direct high-performance backend for Q6/CG reductions and later particle kernels.
2. If the objective is first to minimize source-code disruption, test OpenMP target first, but only after a successful smoke compile/run with explicit local flags.
3. If AMD portability becomes mandatory, evaluate HIP directly or Kokkos/HIP; do not mix HIP into the numerical core before the Q6 backend interface is stable.
4. If long-term portability across NVIDIA/AMD/Intel is required, Kokkos is the strongest candidate, but it should be introduced only after the first backend boundary is proven.
5. SYCL/oneAPI is a credible portability route, but it is a heavier toolchain decision and should not be the first dependency added to the current OpenMP-light code.

The current numerical recommendation remains: keep CPU OpenMP as reference, keep \`projectionBackend=cpu\` as default, and add real GPU kernels behind the existing \`projectionBackend\` switch only after this inventory is archived with validation outputs.
MD

printf 'Wrote %s\n' "$CSV"
printf 'Wrote %s\n' "$MD"

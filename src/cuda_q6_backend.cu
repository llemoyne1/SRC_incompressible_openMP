#include "cuda_q6_backend.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <iostream>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

namespace mpcd {
namespace {

void cuda_check(cudaError_t status, const char* what) {
    if (status != cudaSuccess) {
        std::ostringstream oss;
        oss << what << ": " << cudaGetErrorString(status);
        throw std::runtime_error(oss.str());
    }
}


bool cuda_q6_debug_sync_enabled() {
    const char* value = std::getenv("MPCD_CUDA_Q6_DEBUG_SYNC");
    if (value == nullptr) {
        return false;
    }
    const std::string text(value);
    return !(text.empty() || text == "0" || text == "false" || text == "FALSE" || text == "off" || text == "OFF");
}

void cuda_q6_optional_synchronize(const char* what) {
    if (cuda_q6_debug_sync_enabled()) {
        cuda_check(cudaDeviceSynchronize(), what);
    }
}

using CudaQ6Clock = std::chrono::steady_clock;

bool cuda_q6_timing_enabled_0192() {
    static const bool enabled = []() {
        const char* value = std::getenv("MPCD_CUDA_Q6_TIMING");
        if (value == nullptr) {
            return false;
        }
        const std::string text(value);
        return !(text.empty() || text == "0" || text == "false" || text == "FALSE" ||
                 text == "off" || text == "OFF" || text == "no" || text == "NO");
    }();
    return enabled;
}

double seconds_since_0192(const CudaQ6Clock::time_point& t0) {
    return std::chrono::duration<double>(CudaQ6Clock::now() - t0).count();
}

struct CudaQ6TimingAccum0192 {
    long long solves = 0;
    long long iterations = 0;
    long long reductionDownloads = 0;
    long long operatorApplications = 0;
    long long residualNormShortcuts = 0;
    double totalSeconds = 0.0;
    double uploadRhsSeconds = 0.0;
    double initializeSeconds = 0.0;
    double zeroInactiveSeconds = 0.0;
    double applyOperatorSeconds = 0.0;
    double hostReductionSeconds = 0.0;
    double axpyResidualSeconds = 0.0;
    double meanRemovalSeconds = 0.0;
    double updateDirectionSeconds = 0.0;
    double downloadPhiSeconds = 0.0;
    double finalMeanRemovalSeconds = 0.0;
    double deviceScalarReductionSeconds = 0.0;
    long long deviceScalarCgIterations = 0;
    long long deviceScalarCgBatches = 0;
    long long deviceScalarCgConvergenceDownloads = 0;
    int deviceScalarCgMaxBatchSize = 1;
};

std::mutex& cuda_q6_timing_mutex_0192() {
    // Intentionally leaked to remain valid during std::atexit timing printout.
    static std::mutex* m = new std::mutex();
    return *m;
}

CudaQ6TimingAccum0192& cuda_q6_timing_accum_0192() {
    // Intentionally leaked to remain valid during std::atexit timing printout.
    static CudaQ6TimingAccum0192* accum = new CudaQ6TimingAccum0192();
    return *accum;
}

void cuda_q6_print_timing_summary_0192() {
    if (!cuda_q6_timing_enabled_0192()) {
        return;
    }
    std::lock_guard<std::mutex> lock(cuda_q6_timing_mutex_0192());
    const CudaQ6TimingAccum0192& a = cuda_q6_timing_accum_0192();
    if (a.solves <= 0) {
        return;
    }
    const double avgSolve = a.totalSeconds / static_cast<double>(a.solves);
    const double avgIter = a.iterations > 0 ? a.totalSeconds / static_cast<double>(a.iterations) : 0.0;
    std::cerr
        << "[cuda_q6_timing_0192]"
        << " solves=" << a.solves
        << " iterations=" << a.iterations
        << " reductions=" << a.reductionDownloads
        << " operatorApplications=" << a.operatorApplications
        << " residualNormShortcuts=" << a.residualNormShortcuts
        << " totalSeconds=" << a.totalSeconds
        << " avgSolveSeconds=" << avgSolve
        << " avgIterationSeconds=" << avgIter
        << " uploadRhsSeconds=" << a.uploadRhsSeconds
        << " initializeSeconds=" << a.initializeSeconds
        << " zeroInactiveSeconds=" << a.zeroInactiveSeconds
        << " applyOperatorSeconds=" << a.applyOperatorSeconds
        << " hostReductionSeconds=" << a.hostReductionSeconds
        << " axpyResidualSeconds=" << a.axpyResidualSeconds
        << " meanRemovalSeconds=" << a.meanRemovalSeconds
        << " updateDirectionSeconds=" << a.updateDirectionSeconds
        << " finalMeanRemovalSeconds=" << a.finalMeanRemovalSeconds
        << " deviceScalarReductionSeconds=" << a.deviceScalarReductionSeconds
        << " deviceScalarCgIterations=" << a.deviceScalarCgIterations
        << " deviceScalarCgBatches=" << a.deviceScalarCgBatches
        << " deviceScalarCgConvergenceDownloads=" << a.deviceScalarCgConvergenceDownloads
        << " deviceScalarCgMaxBatchSize=" << a.deviceScalarCgMaxBatchSize
        << " downloadPhiSeconds=" << a.downloadPhiSeconds
        << "\n";
}

void cuda_q6_register_timing_atexit_0192() {
    static std::once_flag once;
    std::call_once(once, []() { std::atexit(cuda_q6_print_timing_summary_0192); });
}

void cuda_q6_accumulate_timing_0192(const CudaQ6CgDiagnostics& d) {
    if (!cuda_q6_timing_enabled_0192()) {
        return;
    }
    cuda_q6_register_timing_atexit_0192();
    std::lock_guard<std::mutex> lock(cuda_q6_timing_mutex_0192());
    CudaQ6TimingAccum0192& a = cuda_q6_timing_accum_0192();
    a.solves += 1;
    a.iterations += d.iterations;
    a.reductionDownloads += d.reductionDownloads;
    a.operatorApplications += d.operatorApplications;
    a.residualNormShortcuts += d.residualNormFromMeanRemovalShortcuts;
    a.totalSeconds += d.totalSeconds;
    a.uploadRhsSeconds += d.uploadRhsSeconds;
    a.initializeSeconds += d.initializeSeconds;
    a.zeroInactiveSeconds += d.zeroInactiveSeconds;
    a.applyOperatorSeconds += d.applyOperatorSeconds;
    a.hostReductionSeconds += d.hostReductionSeconds;
    a.axpyResidualSeconds += d.axpyResidualSeconds;
    a.meanRemovalSeconds += d.meanRemovalSeconds;
    a.updateDirectionSeconds += d.updateDirectionSeconds;
    a.downloadPhiSeconds += d.downloadPhiSeconds;
    a.finalMeanRemovalSeconds += d.finalMeanRemovalSeconds;
    a.deviceScalarReductionSeconds += d.deviceScalarReductionSeconds;
    a.deviceScalarCgIterations += d.deviceScalarCgIterations;
    a.deviceScalarCgBatches += d.deviceScalarCgBatches;
    a.deviceScalarCgConvergenceDownloads += d.deviceScalarCgConvergenceDownloads;
    a.deviceScalarCgMaxBatchSize = std::max(a.deviceScalarCgMaxBatchSize, d.deviceScalarCgBatchSize);
}

template <typename T>
class DeviceBuffer {
public:
    DeviceBuffer() = default;
    explicit DeviceBuffer(const std::size_t count) { allocate(count); }

    DeviceBuffer(const DeviceBuffer&) = delete;
    DeviceBuffer& operator=(const DeviceBuffer&) = delete;

    DeviceBuffer(DeviceBuffer&& other) noexcept
        : ptr_(other.ptr_), count_(other.count_) {
        other.ptr_ = nullptr;
        other.count_ = 0u;
    }

    DeviceBuffer& operator=(DeviceBuffer&& other) noexcept {
        if (this != &other) {
            release();
            ptr_ = other.ptr_;
            count_ = other.count_;
            other.ptr_ = nullptr;
            other.count_ = 0u;
        }
        return *this;
    }

    ~DeviceBuffer() { release(); }

    void allocate(const std::size_t count) {
        release();
        count_ = count;
        if (count_ > 0u) {
            cuda_check(cudaMalloc(reinterpret_cast<void**>(&ptr_), count_ * sizeof(T)), "cudaMalloc");
        }
    }

    void allocate_if_needed(const std::size_t count) {
        if (count_ != count) {
            allocate(count);
        }
    }

    void upload(const std::vector<T>& host, const char* name) {
        if (host.size() != count_) {
            std::ostringstream oss;
            oss << "DeviceBuffer::upload size mismatch for " << name
                << ": host=" << host.size() << " device=" << count_;
            throw std::runtime_error(oss.str());
        }
        if (count_ > 0u) {
            cuda_check(cudaMemcpy(ptr_, host.data(), count_ * sizeof(T), cudaMemcpyHostToDevice), name);
        }
    }

    void download(std::vector<T>& host, const char* name) const {
        host.resize(count_);
        if (count_ > 0u) {
            cuda_check(cudaMemcpy(host.data(), ptr_, count_ * sizeof(T), cudaMemcpyDeviceToHost), name);
        }
    }

    T* data() { return ptr_; }
    const T* data() const { return ptr_; }
    std::size_t size() const { return count_; }

private:
    void release() noexcept {
        if (ptr_ != nullptr) {
            cudaFree(ptr_);
            ptr_ = nullptr;
        }
        count_ = 0u;
    }

    T* ptr_ = nullptr;
    std::size_t count_ = 0u;
};

void require_plan_vector_size(const std::vector<int>& v,
                              const int expected,
                              const char* owner,
                              const char* name) {
    if (static_cast<int>(v.size()) != expected) {
        std::ostringstream oss;
        oss << owner << ": " << name
            << " size mismatch, expected " << expected << ", got " << v.size();
        throw std::runtime_error(oss.str());
    }
}

void require_plan_vector_size(const std::vector<double>& v,
                              const int expected,
                              const char* owner,
                              const char* name) {
    if (static_cast<int>(v.size()) != expected) {
        std::ostringstream oss;
        oss << owner << ": " << name
            << " size mismatch, expected " << expected << ", got " << v.size();
        throw std::runtime_error(oss.str());
    }
}

void validate_plan(const EllipticOperatorPlan& plan, const char* owner) {
    if (plan.numCells < 0) {
        std::ostringstream oss;
        oss << owner << ": negative numCells";
        throw std::runtime_error(oss.str());
    }
    const int nc = plan.numCells;
    require_plan_vector_size(plan.east, nc, owner, "plan.east");
    require_plan_vector_size(plan.west, nc, owner, "plan.west");
    require_plan_vector_size(plan.north, nc, owner, "plan.north");
    require_plan_vector_size(plan.south, nc, owner, "plan.south");
    require_plan_vector_size(plan.coeffEast, nc, owner, "plan.coeffEast");
    require_plan_vector_size(plan.coeffWest, nc, owner, "plan.coeffWest");
    require_plan_vector_size(plan.coeffNorth, nc, owner, "plan.coeffNorth");
    require_plan_vector_size(plan.coeffSouth, nc, owner, "plan.coeffSouth");
}

int choose_blocks(const int nActive, const int threadsPerBlock) {
    if (nActive <= 0) {
        return 0;
    }
    const int natural = (nActive + threadsPerBlock - 1) / threadsPerBlock;
    return std::max(1, std::min(1024, natural));
}

double host_sum_blocks(const DeviceBuffer<double>& dBlockSums,
                       double* elapsedSeconds = nullptr,
                       int* downloadCount = nullptr) {
    const auto t0 = CudaQ6Clock::now();
    std::vector<double> blockSums;
    dBlockSums.download(blockSums, "copy block sums back");
    double sum = 0.0;
    for (const double v : blockSums) {
        sum += v;
    }
    if (elapsedSeconds != nullptr) {
        *elapsedSeconds += seconds_since_0192(t0);
    }
    if (downloadCount != nullptr) {
        *downloadCount += 1;
    }
    return sum;
}


bool cuda_q6_plan_cache_disabled() {
    const char* value = std::getenv("MPCD_CUDA_Q6_DISABLE_PLAN_CACHE");
    if (value == nullptr) {
        return false;
    }
    const std::string text(value);
    return !(text.empty() || text == "0" || text == "false" || text == "FALSE" || text == "off" || text == "OFF");
}

bool cuda_q6_env_truthy_0194(const char* name) {
    const char* value = std::getenv(name);
    if (value == nullptr) {
        return false;
    }
    const std::string text(value);
    return !(text.empty() || text == "0" || text == "false" || text == "FALSE" ||
             text == "off" || text == "OFF" || text == "no" || text == "NO");
}

bool cuda_q6_device_scalar_reduction_enabled_0194() {
    // 0193 showed that the extra device-side scalar reduction kernel is slower
    // than downloading the small blockSums array for the current CG granularity
    // (64^2 and 128^2 TG).  Keep it as an explicit ablation mode only.
    return cuda_q6_env_truthy_0194("MPCD_CUDA_Q6_DEVICE_SCALAR_REDUCTION");
}

bool cuda_q6_legacy_host_block_sum_enabled_0193() {
    // Backward-compatible override.  In 0194 this is again the default path.
    if (cuda_q6_env_truthy_0194("MPCD_CUDA_Q6_HOST_BLOCK_SUM")) {
        return true;
    }
    return !cuda_q6_device_scalar_reduction_enabled_0194();
}


bool cuda_q6_residual_norm_shortcut_enabled_0195() {
    // 0195 showed that the residual norm shortcut is locally faster for the
    // mean-removal substep but not globally faster on the current CUDA CG path.
    // In 0196 it is therefore kept as an explicit ablation only.
    if (cuda_q6_env_truthy_0194("MPCD_CUDA_Q6_LEGACY_MEAN_REMOVAL_RESIDUAL_NORM")) {
        return false;
    }
    return cuda_q6_env_truthy_0194("MPCD_CUDA_Q6_RESIDUAL_NORM_SHORTCUT");
}

bool cuda_q6_device_scalar_cg_enabled_0196() {
    // 0196 serious reduction path: keep pAp on device, compute alpha on device,
    // and download only rrNew once per CG iteration for convergence control.
    // This roughly halves the mandatory host synchronization count in the main
    // CG loop.  Use MPCD_CUDA_Q6_DEVICE_SCALAR_CG=0 or
    // MPCD_CUDA_Q6_LEGACY_HOST_SCALAR_CG=1 to restore the previous path.
    if (cuda_q6_env_truthy_0194("MPCD_CUDA_Q6_LEGACY_HOST_SCALAR_CG")) {
        return false;
    }
    const char* value = std::getenv("MPCD_CUDA_Q6_DEVICE_SCALAR_CG");
    if (value == nullptr) {
        return true;
    }
    const std::string text(value);
    return !(text.empty() || text == "0" || text == "false" || text == "FALSE" ||
             text == "off" || text == "OFF" || text == "no" || text == "NO");
}

int cuda_q6_device_scalar_cg_batch_size_0197(const CudaQ6CgParams& params) {
    int batchSize = std::max(1, params.deviceIterationBatchSize);
    if (const char* value = std::getenv("MPCD_CUDA_Q6_DEVICE_SCALAR_BATCH")) {
        try {
            batchSize = std::max(1, std::stoi(std::string(value)));
        } catch (...) {
            batchSize = std::max(1, params.deviceIterationBatchSize);
        }
    }
    // Keep this experimental path bounded: large batches delay host-side failure
    // visibility and may overrun useful work when the device convergence flag is
    // not tripped because of a breakdown.  The scripts sweep 1/5/10/20.
    return std::min(batchSize, 64);
}

uint64_t fnv1a_mix_u64(uint64_t h, const uint64_t v) {
    constexpr uint64_t prime = 1099511628211ull;
    h ^= v;
    h *= prime;
    return h;
}

uint64_t fnv1a_mix_i32(uint64_t h, const int v) {
    return fnv1a_mix_u64(h, static_cast<uint64_t>(static_cast<int64_t>(v)));
}

uint64_t fnv1a_mix_double(uint64_t h, const double v) {
    uint64_t bits = 0u;
    static_assert(sizeof(bits) == sizeof(v), "unexpected double size");
    std::memcpy(&bits, &v, sizeof(bits));
    return fnv1a_mix_u64(h, bits);
}

template <typename T>
uint64_t fnv1a_mix_vector(uint64_t h, const std::vector<T>& v) {
    h = fnv1a_mix_u64(h, static_cast<uint64_t>(v.size()));
    for (const T& x : v) {
        if constexpr (std::is_same<T, double>::value) {
            h = fnv1a_mix_double(h, x);
        } else {
            h = fnv1a_mix_i32(h, static_cast<int>(x));
        }
    }
    return h;
}

uint64_t elliptic_plan_signature_0191(const EllipticOperatorPlan& plan) {
    uint64_t h = 1469598103934665603ull;
    h = fnv1a_mix_i32(h, plan.Nx);
    h = fnv1a_mix_i32(h, plan.Ny);
    h = fnv1a_mix_i32(h, plan.numCells);
    h = fnv1a_mix_double(h, plan.dx);
    h = fnv1a_mix_double(h, plan.dy);
    h = fnv1a_mix_i32(h, static_cast<int>(plan.bcX));
    h = fnv1a_mix_i32(h, static_cast<int>(plan.bcY));
    h = fnv1a_mix_vector(h, plan.activeCells);
    h = fnv1a_mix_vector(h, plan.inactiveCells);
    h = fnv1a_mix_vector(h, plan.east);
    h = fnv1a_mix_vector(h, plan.west);
    h = fnv1a_mix_vector(h, plan.north);
    h = fnv1a_mix_vector(h, plan.south);
    h = fnv1a_mix_vector(h, plan.coeffEast);
    h = fnv1a_mix_vector(h, plan.coeffWest);
    h = fnv1a_mix_vector(h, plan.coeffNorth);
    h = fnv1a_mix_vector(h, plan.coeffSouth);
    return h;
}

class CudaQ6CgDeviceWorkspace {
public:
    void prepare_for_plan(const EllipticOperatorPlan& plan,
                          const int device,
                          const int blocks,
                          const int inactiveBlocks,
                          const bool forcePlanReload) {
        const int nc = plan.numCells;
        const int nActive = static_cast<int>(plan.activeCells.size());
        const int nInactive = static_cast<int>(plan.inactiveCells.size());
        const uint64_t sig = elliptic_plan_signature_0191(plan);
        const bool reloadPlan = forcePlanReload ||
                                !planValid_ ||
                                device_ != device ||
                                numCells_ != nc ||
                                activeCells_ != nActive ||
                                inactiveCells_ != nInactive ||
                                planSignature_ != sig;

        if (reloadPlan) {
            dActive.allocate_if_needed(static_cast<std::size_t>(nActive));
            dInactive.allocate_if_needed(static_cast<std::size_t>(std::max(1, nInactive)));
            dEast.allocate_if_needed(static_cast<std::size_t>(nc));
            dWest.allocate_if_needed(static_cast<std::size_t>(nc));
            dNorth.allocate_if_needed(static_cast<std::size_t>(nc));
            dSouth.allocate_if_needed(static_cast<std::size_t>(nc));
            dCoeffEast.allocate_if_needed(static_cast<std::size_t>(nc));
            dCoeffWest.allocate_if_needed(static_cast<std::size_t>(nc));
            dCoeffNorth.allocate_if_needed(static_cast<std::size_t>(nc));
            dCoeffSouth.allocate_if_needed(static_cast<std::size_t>(nc));

            dActive.upload(plan.activeCells, "copy activeCells cached");
            if (nInactive > 0) {
                dInactive.upload(plan.inactiveCells, "copy inactiveCells cached");
            }
            dEast.upload(plan.east, "copy east cached");
            dWest.upload(plan.west, "copy west cached");
            dNorth.upload(plan.north, "copy north cached");
            dSouth.upload(plan.south, "copy south cached");
            dCoeffEast.upload(plan.coeffEast, "copy coeffEast cached");
            dCoeffWest.upload(plan.coeffWest, "copy coeffWest cached");
            dCoeffNorth.upload(plan.coeffNorth, "copy coeffNorth cached");
            dCoeffSouth.upload(plan.coeffSouth, "copy coeffSouth cached");

            device_ = device;
            numCells_ = nc;
            activeCells_ = nActive;
            inactiveCells_ = nInactive;
            planSignature_ = sig;
            planValid_ = true;
        }

        dRhs.allocate_if_needed(static_cast<std::size_t>(nc));
        dPhi.allocate_if_needed(static_cast<std::size_t>(nc));
        dR.allocate_if_needed(static_cast<std::size_t>(nc));
        dP.allocate_if_needed(static_cast<std::size_t>(nc));
        dAp.allocate_if_needed(static_cast<std::size_t>(nc));
        dBlockSums.allocate_if_needed(static_cast<std::size_t>(std::max(1, blocks)));
        dScalarSum.allocate_if_needed(1u);
        dRr.allocate_if_needed(1u);
        dPAp.allocate_if_needed(1u);
        dRrNew.allocate_if_needed(1u);
        dConvergedAt.allocate_if_needed(1u);
        dBreakdownAt.allocate_if_needed(1u);
        if (inactiveBlocks > 0) {
            dInactiveScratchBlocks.allocate_if_needed(static_cast<std::size_t>(inactiveBlocks));
        }
    }

    DeviceBuffer<int> dActive;
    DeviceBuffer<int> dInactive;
    DeviceBuffer<int> dEast;
    DeviceBuffer<int> dWest;
    DeviceBuffer<int> dNorth;
    DeviceBuffer<int> dSouth;
    DeviceBuffer<double> dCoeffEast;
    DeviceBuffer<double> dCoeffWest;
    DeviceBuffer<double> dCoeffNorth;
    DeviceBuffer<double> dCoeffSouth;
    DeviceBuffer<double> dRhs;
    DeviceBuffer<double> dPhi;
    DeviceBuffer<double> dR;
    DeviceBuffer<double> dP;
    DeviceBuffer<double> dAp;
    DeviceBuffer<double> dBlockSums;
    DeviceBuffer<double> dScalarSum;
    DeviceBuffer<double> dRr;
    DeviceBuffer<double> dPAp;
    DeviceBuffer<double> dRrNew;
    DeviceBuffer<int> dConvergedAt;
    DeviceBuffer<int> dBreakdownAt;
    DeviceBuffer<double> dInactiveScratchBlocks;

private:
    bool planValid_ = false;
    int device_ = -1;
    int numCells_ = -1;
    int activeCells_ = -1;
    int inactiveCells_ = -1;
    uint64_t planSignature_ = 0u;
};

CudaQ6CgDeviceWorkspace& cuda_q6_thread_local_cg_workspace() {
    thread_local CudaQ6CgDeviceWorkspace workspace;
    return workspace;
}

__global__ void q6_apply_operator_plan_kernel(const int nActive,
                                              const int* __restrict__ activeCells,
                                              const int* __restrict__ east,
                                              const int* __restrict__ west,
                                              const int* __restrict__ north,
                                              const int* __restrict__ south,
                                              const double* __restrict__ coeffEast,
                                              const double* __restrict__ coeffWest,
                                              const double* __restrict__ coeffNorth,
                                              const double* __restrict__ coeffSouth,
                                              const double* __restrict__ phi,
                                              double* __restrict__ Aphi,
                                              double* __restrict__ blockSums) {
    extern __shared__ double shared[];
    const int tid = threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    int idx = blockIdx.x * blockDim.x + tid;
    double local = 0.0;

    while (idx < nActive) {
        const int c = activeCells[idx];
        const double pc = phi[c];
        const double v =
            coeffEast[c]  * (pc - phi[east[c]]) +
            coeffWest[c]  * (pc - phi[west[c]]) +
            coeffNorth[c] * (pc - phi[north[c]]) +
            coeffSouth[c] * (pc - phi[south[c]]);
        Aphi[c] = v;
        local += pc * v;
        idx += stride;
    }

    shared[tid] = local;
    __syncthreads();

    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shared[tid] += shared[tid + offset];
        }
        __syncthreads();
    }

    if (tid == 0) {
        blockSums[blockIdx.x] = shared[0];
    }
}

__global__ void q6_initialize_cg_kernel(const int nActive,
                                        const int* __restrict__ activeCells,
                                        const double* __restrict__ rhs,
                                        double* __restrict__ phi,
                                        double* __restrict__ r,
                                        double* __restrict__ p,
                                        double* __restrict__ Ap,
                                        double* __restrict__ blockSums) {
    extern __shared__ double shared[];
    const int tid = threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    int idx = blockIdx.x * blockDim.x + tid;
    double local = 0.0;

    while (idx < nActive) {
        const int c = activeCells[idx];
        const double b = rhs[c];
        phi[c] = 0.0;
        r[c] = b;
        p[c] = b;
        Ap[c] = 0.0;
        local += b * b;
        idx += stride;
    }

    shared[tid] = local;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shared[tid] += shared[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        blockSums[blockIdx.x] = shared[0];
    }
}

__global__ void q6_zero_inactive_kernel(const int nInactive,
                                        const int* __restrict__ inactiveCells,
                                        double* __restrict__ phi,
                                        double* __restrict__ r,
                                        double* __restrict__ p,
                                        double* __restrict__ Ap) {
    const int stride = blockDim.x * gridDim.x;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    while (idx < nInactive) {
        const int c = inactiveCells[idx];
        phi[c] = 0.0;
        r[c] = 0.0;
        p[c] = 0.0;
        Ap[c] = 0.0;
        idx += stride;
    }
}

__global__ void q6_axpy_residual_kernel(const int nActive,
                                        const int* __restrict__ activeCells,
                                        const double alpha,
                                        const double* __restrict__ p,
                                        const double* __restrict__ Ap,
                                        double* __restrict__ phi,
                                        double* __restrict__ r,
                                        double* __restrict__ blockSums) {
    extern __shared__ double shared[];
    const int tid = threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    int idx = blockIdx.x * blockDim.x + tid;
    double local = 0.0;

    while (idx < nActive) {
        const int c = activeCells[idx];
        phi[c] += alpha * p[c];
        const double rc = r[c] - alpha * Ap[c];
        r[c] = rc;
        local += rc * rc;
        idx += stride;
    }

    shared[tid] = local;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shared[tid] += shared[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        blockSums[blockIdx.x] = shared[0];
    }
}


__global__ void q6_axpy_residual_device_alpha_kernel(const int nActive,
                                                     const int* __restrict__ activeCells,
                                                     const double* __restrict__ rrOld,
                                                     const double* __restrict__ pApScalar,
                                                     const double* __restrict__ p,
                                                     const double* __restrict__ Ap,
                                                     double* __restrict__ phi,
                                                     double* __restrict__ r,
                                                     double* __restrict__ blockSums) {
    extern __shared__ double shared[];
    const int tid = threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    const double denom = pApScalar[0];
    const double alpha = rrOld[0] / denom;
    int idx = blockIdx.x * blockDim.x + tid;
    double local = 0.0;

    while (idx < nActive) {
        const int c = activeCells[idx];
        phi[c] += alpha * p[c];
        const double rc = r[c] - alpha * Ap[c];
        r[c] = rc;
        local += rc * rc;
        idx += stride;
    }

    shared[tid] = local;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shared[tid] += shared[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        blockSums[blockIdx.x] = shared[0];
    }
}

__global__ void q6_update_direction_kernel(const int nActive,
                                           const int* __restrict__ activeCells,
                                           const double beta,
                                           const double* __restrict__ r,
                                           double* __restrict__ p) {
    const int stride = blockDim.x * gridDim.x;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    while (idx < nActive) {
        const int c = activeCells[idx];
        p[c] = r[c] + beta * p[c];
        idx += stride;
    }
}


__global__ void q6_update_direction_device_beta_kernel(const int nActive,
                                                       const int* __restrict__ activeCells,
                                                       const double* __restrict__ rrNew,
                                                       const double* __restrict__ rrOld,
                                                       const double* __restrict__ r,
                                                       double* __restrict__ p) {
    const int stride = blockDim.x * gridDim.x;
    const double beta = rrNew[0] / rrOld[0];
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    while (idx < nActive) {
        const int c = activeCells[idx];
        p[c] = r[c] + beta * p[c];
        idx += stride;
    }
}


__global__ void q6_apply_operator_plan_batch_kernel(const int nActive,
                                                    const int* __restrict__ activeCells,
                                                    const int* __restrict__ east,
                                                    const int* __restrict__ west,
                                                    const int* __restrict__ north,
                                                    const int* __restrict__ south,
                                                    const double* __restrict__ coeffEast,
                                                    const double* __restrict__ coeffWest,
                                                    const double* __restrict__ coeffNorth,
                                                    const double* __restrict__ coeffSouth,
                                                    const double* __restrict__ phi,
                                                    double* __restrict__ Aphi,
                                                    double* __restrict__ blockSums,
                                                    const int* __restrict__ convergedAt,
                                                    const int* __restrict__ breakdownAt) {
    extern __shared__ double shared[];
    const int tid = threadIdx.x;
    if (convergedAt[0] > 0 || breakdownAt[0] > 0) {
        return;
    }

    const int stride = blockDim.x * gridDim.x;
    int idx = blockIdx.x * blockDim.x + tid;
    double local = 0.0;

    while (idx < nActive) {
        const int c = activeCells[idx];
        const double pc = phi[c];
        const double v =
            coeffEast[c]  * (pc - phi[east[c]]) +
            coeffWest[c]  * (pc - phi[west[c]]) +
            coeffNorth[c] * (pc - phi[north[c]]) +
            coeffSouth[c] * (pc - phi[south[c]]);
        Aphi[c] = v;
        local += pc * v;
        idx += stride;
    }

    shared[tid] = local;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shared[tid] += shared[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        blockSums[blockIdx.x] = shared[0];
    }
}

__global__ void q6_axpy_residual_device_alpha_batch_kernel(const int nActive,
                                                           const int* __restrict__ activeCells,
                                                           const double* __restrict__ rrOld,
                                                           const double* __restrict__ pApScalar,
                                                           const double* __restrict__ p,
                                                           const double* __restrict__ Ap,
                                                           double* __restrict__ phi,
                                                           double* __restrict__ r,
                                                           double* __restrict__ blockSums,
                                                           int* __restrict__ convergedAt,
                                                           int* __restrict__ breakdownAt,
                                                           const int iterationNumber) {
    extern __shared__ double shared[];
    const int tid = threadIdx.x;
    if (convergedAt[0] > 0 || breakdownAt[0] > 0) {
        return;
    }

    const double denom = pApScalar[0];
    if (!(denom > 0.0) || !isfinite(denom)) {
        if (blockIdx.x == 0 && tid == 0) {
            breakdownAt[0] = iterationNumber;
        }
        if (tid == 0) {
            blockSums[blockIdx.x] = 0.0;
        }
        return;
    }

    const int stride = blockDim.x * gridDim.x;
    const double alpha = rrOld[0] / denom;
    int idx = blockIdx.x * blockDim.x + tid;
    double local = 0.0;

    while (idx < nActive) {
        const int c = activeCells[idx];
        phi[c] += alpha * p[c];
        const double rc = r[c] - alpha * Ap[c];
        r[c] = rc;
        local += rc * rc;
        idx += stride;
    }

    shared[tid] = local;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shared[tid] += shared[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        blockSums[blockIdx.x] = shared[0];
    }
}

__global__ void q6_update_direction_device_beta_batch_kernel(const int nActive,
                                                             const int* __restrict__ activeCells,
                                                             double* __restrict__ rrOld,
                                                             const double* __restrict__ rrNew,
                                                             const double* __restrict__ r,
                                                             double* __restrict__ p,
                                                             const double absTolSq,
                                                             int* __restrict__ convergedAt,
                                                             int* __restrict__ breakdownAt,
                                                             const int iterationNumber) {
    if (convergedAt[0] > 0 || breakdownAt[0] > 0) {
        return;
    }
    const double newValue = rrNew[0];
    if (!isfinite(newValue) || newValue < 0.0) {
        if (blockIdx.x == 0 && threadIdx.x == 0) {
            breakdownAt[0] = iterationNumber;
        }
        return;
    }
    if (newValue <= absTolSq) {
        if (blockIdx.x == 0 && threadIdx.x == 0) {
            convergedAt[0] = iterationNumber;
        }
        return;
    }
    const double oldValue = rrOld[0];
    if (!(oldValue > 0.0) || !isfinite(oldValue)) {
        if (blockIdx.x == 0 && threadIdx.x == 0) {
            breakdownAt[0] = iterationNumber;
        }
        return;
    }

    const int stride = blockDim.x * gridDim.x;
    const double beta = newValue / oldValue;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    while (idx < nActive) {
        const int c = activeCells[idx];
        p[c] = r[c] + beta * p[c];
        idx += stride;
    }
}

__global__ void q6_check_convergence_no_update_batch_kernel(const double* __restrict__ rrNew,
                                                            const double absTolSq,
                                                            int* __restrict__ convergedAt,
                                                            int* __restrict__ breakdownAt,
                                                            const int iterationNumber) {
    if (threadIdx.x != 0 || blockIdx.x != 0) {
        return;
    }
    if (convergedAt[0] > 0 || breakdownAt[0] > 0) {
        return;
    }
    const double newValue = rrNew[0];
    if (!isfinite(newValue) || newValue < 0.0) {
        breakdownAt[0] = iterationNumber;
        return;
    }
    if (newValue <= absTolSq) {
        convergedAt[0] = iterationNumber;
    }
}

__global__ void q6_sum_active_kernel(const int nActive,
                                     const int* __restrict__ activeCells,
                                     const double* __restrict__ values,
                                     double* __restrict__ blockSums) {
    extern __shared__ double shared[];
    const int tid = threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    int idx = blockIdx.x * blockDim.x + tid;
    double local = 0.0;
    while (idx < nActive) {
        local += values[activeCells[idx]];
        idx += stride;
    }
    shared[tid] = local;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shared[tid] += shared[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        blockSums[blockIdx.x] = shared[0];
    }
}

__global__ void q6_sum_active_squares_kernel(const int nActive,
                                             const int* __restrict__ activeCells,
                                             const double* __restrict__ values,
                                             double* __restrict__ blockSums) {
    extern __shared__ double shared[];
    const int tid = threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    int idx = blockIdx.x * blockDim.x + tid;
    double local = 0.0;
    while (idx < nActive) {
        const double v = values[activeCells[idx]];
        local += v * v;
        idx += stride;
    }
    shared[tid] = local;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shared[tid] += shared[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        blockSums[blockIdx.x] = shared[0];
    }
}

__global__ void q6_subtract_mean_active_kernel(const int nActive,
                                               const int* __restrict__ activeCells,
                                               const double mean,
                                               double* __restrict__ values) {
    const int stride = blockDim.x * gridDim.x;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    while (idx < nActive) {
        values[activeCells[idx]] -= mean;
        idx += stride;
    }
}

__global__ void q6_reduce_block_sums_to_scalar_kernel(const int nBlocks,
                                                        const double* __restrict__ blockSums,
                                                        double* __restrict__ scalarSum) {
    extern __shared__ double shared[];
    const int tid = threadIdx.x;
    double local = 0.0;
    for (int idx = tid; idx < nBlocks; idx += blockDim.x) {
        local += blockSums[idx];
    }

    shared[tid] = local;
    __syncthreads();

    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shared[tid] += shared[tid + offset];
        }
        __syncthreads();
    }

    if (tid == 0) {
        scalarSum[0] = shared[0];
    }
}

double host_sum_blocks_reduced_0193(const DeviceBuffer<double>& dBlockSums,
                                    const int blocks,
                                    DeviceBuffer<double>& dScalarSum,
                                    double* elapsedSeconds = nullptr,
                                    int* downloadCount = nullptr) {
    if (blocks <= 0) {
        return 0.0;
    }
    if (cuda_q6_legacy_host_block_sum_enabled_0193()) {
        return host_sum_blocks(dBlockSums, elapsedSeconds, downloadCount);
    }

    const auto t0 = CudaQ6Clock::now();
    constexpr int reductionThreads = 256;
    q6_reduce_block_sums_to_scalar_kernel<<<1, reductionThreads, reductionThreads * sizeof(double)>>>(
        blocks, dBlockSums.data(), dScalarSum.data());
    cuda_check(cudaGetLastError(), "q6_reduce_block_sums_to_scalar_kernel launch (explicit device scalar reduction mode)");
    cuda_q6_optional_synchronize("q6_reduce_block_sums_to_scalar_kernel debug synchronize");

    double sum = 0.0;
    cuda_check(cudaMemcpy(&sum, dScalarSum.data(), sizeof(double), cudaMemcpyDeviceToHost),
               "copy reduced scalar sum back");
    if (elapsedSeconds != nullptr) {
        *elapsedSeconds += seconds_since_0192(t0);
    }
    if (downloadCount != nullptr) {
        *downloadCount += 1;
    }
    return sum;
}


void reduce_block_sums_to_device_scalar_0196(const DeviceBuffer<double>& dBlockSums,
                                             const int blocks,
                                             DeviceBuffer<double>& dScalarSum,
                                             const char* what,
                                             double* elapsedSeconds = nullptr) {
    if (blocks <= 0) {
        const double zero = 0.0;
        cuda_check(cudaMemcpy(dScalarSum.data(), &zero, sizeof(double), cudaMemcpyHostToDevice), what);
        return;
    }
    const auto t0 = CudaQ6Clock::now();
    constexpr int reductionThreads = 256;
    q6_reduce_block_sums_to_scalar_kernel<<<1, reductionThreads, reductionThreads * sizeof(double)>>>(
        blocks, dBlockSums.data(), dScalarSum.data());
    cuda_check(cudaGetLastError(), what);
    cuda_q6_optional_synchronize("reduce_block_sums_to_device_scalar_0196 debug synchronize");
    if (elapsedSeconds != nullptr) {
        *elapsedSeconds += seconds_since_0192(t0);
    }
}

double download_device_scalar_0196(const DeviceBuffer<double>& dScalar,
                                   const char* what,
                                   double* elapsedSeconds = nullptr,
                                   int* downloadCount = nullptr) {
    const auto t0 = CudaQ6Clock::now();
    double value = 0.0;
    cuda_check(cudaMemcpy(&value, dScalar.data(), sizeof(double), cudaMemcpyDeviceToHost), what);
    if (elapsedSeconds != nullptr) {
        *elapsedSeconds += seconds_since_0192(t0);
    }
    if (downloadCount != nullptr) {
        *downloadCount += 1;
    }
    return value;
}

void upload_device_scalar_0196(DeviceBuffer<double>& dScalar,
                               const double value,
                               const char* what) {
    cuda_check(cudaMemcpy(dScalar.data(), &value, sizeof(double), cudaMemcpyHostToDevice), what);
}

void copy_device_scalar_0196(DeviceBuffer<double>& dst,
                             const DeviceBuffer<double>& src,
                             const char* what) {
    cuda_check(cudaMemcpy(dst.data(), src.data(), sizeof(double), cudaMemcpyDeviceToDevice), what);
}

double subtract_active_mean(const int nActive,
                            const int blocks,
                            const int threadsPerBlock,
                            const DeviceBuffer<int>& dActive,
                            DeviceBuffer<double>& dValues,
                            DeviceBuffer<double>& dBlockSums,
                            DeviceBuffer<double>& dScalarSum,
                            double* reductionSeconds = nullptr,
                            int* reductionDownloads = nullptr) {
    if (nActive <= 0) {
        return 0.0;
    }
    q6_sum_active_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
        nActive, dActive.data(), dValues.data(), dBlockSums.data());
    cuda_check(cudaGetLastError(), "q6_sum_active_kernel launch");
    cuda_q6_optional_synchronize("q6_sum_active_kernel debug synchronize");
    const double sum = host_sum_blocks_reduced_0193(dBlockSums, blocks, dScalarSum, reductionSeconds, reductionDownloads);
    const double mean = sum / static_cast<double>(nActive);
    q6_subtract_mean_active_kernel<<<blocks, threadsPerBlock>>>(
        nActive, dActive.data(), mean, dValues.data());
    cuda_check(cudaGetLastError(), "q6_subtract_mean_active_kernel launch");
    cuda_q6_optional_synchronize("q6_subtract_mean_active_kernel debug synchronize");
    return sum;
}

} // namespace

bool cuda_q6_backend_runtime_available() {
    int count = 0;
    const cudaError_t status = cudaGetDeviceCount(&count);
    if (status != cudaSuccess) {
        cudaGetLastError();
        return false;
    }
    return count > 0;
}

double cuda_q6_apply_elliptic_operator_plan_and_dot(
    const EllipticOperatorPlan& plan,
    const std::vector<double>& phi,
    std::vector<double>& Aphi,
    CudaQ6ApplyDiagnostics* diagnostics) {

    validate_plan(plan, "cuda_q6_apply_elliptic_operator_plan_and_dot");
    const int nc = plan.numCells;
    require_plan_vector_size(phi, nc, "cuda_q6_apply_elliptic_operator_plan_and_dot", "phi");

    int device = -1;
    cuda_check(cudaGetDevice(&device), "cudaGetDevice");

    Aphi.assign(static_cast<std::size_t>(nc), 0.0);
    const int nActive = static_cast<int>(plan.activeCells.size());
    const int nInactive = static_cast<int>(plan.inactiveCells.size());
    if (nActive == 0 || nc == 0) {
        if (diagnostics != nullptr) {
            diagnostics->usedCuda = true;
            diagnostics->device = device;
            diagnostics->numCells = nc;
            diagnostics->activeCells = nActive;
            diagnostics->inactiveCells = nInactive;
            diagnostics->blocks = 0;
            diagnostics->threadsPerBlock = 0;
            diagnostics->pAp = 0.0;
        }
        return 0.0;
    }

    DeviceBuffer<int> dActive(static_cast<std::size_t>(nActive));
    DeviceBuffer<int> dEast(static_cast<std::size_t>(nc));
    DeviceBuffer<int> dWest(static_cast<std::size_t>(nc));
    DeviceBuffer<int> dNorth(static_cast<std::size_t>(nc));
    DeviceBuffer<int> dSouth(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dCoeffEast(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dCoeffWest(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dCoeffNorth(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dCoeffSouth(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dPhi(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dAphi(static_cast<std::size_t>(nc));

    dActive.upload(plan.activeCells, "copy activeCells");
    dEast.upload(plan.east, "copy east");
    dWest.upload(plan.west, "copy west");
    dNorth.upload(plan.north, "copy north");
    dSouth.upload(plan.south, "copy south");
    dCoeffEast.upload(plan.coeffEast, "copy coeffEast");
    dCoeffWest.upload(plan.coeffWest, "copy coeffWest");
    dCoeffNorth.upload(plan.coeffNorth, "copy coeffNorth");
    dCoeffSouth.upload(plan.coeffSouth, "copy coeffSouth");
    dPhi.upload(phi, "copy phi");
    cuda_check(cudaMemset(dAphi.data(), 0, static_cast<std::size_t>(nc) * sizeof(double)), "cudaMemset Aphi");

    constexpr int threadsPerBlock = 256;
    const int blocks = choose_blocks(nActive, threadsPerBlock);
    DeviceBuffer<double> dBlockSums(static_cast<std::size_t>(blocks));
    DeviceBuffer<double> dScalarSum(1u);
    q6_apply_operator_plan_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
        nActive,
        dActive.data(),
        dEast.data(), dWest.data(), dNorth.data(), dSouth.data(),
        dCoeffEast.data(), dCoeffWest.data(), dCoeffNorth.data(), dCoeffSouth.data(),
        dPhi.data(), dAphi.data(), dBlockSums.data());
    cuda_check(cudaGetLastError(), "q6_apply_operator_plan_kernel launch");
    cuda_q6_optional_synchronize("q6_apply_operator_plan_kernel debug synchronize");

    dAphi.download(Aphi, "copy Aphi back");
    const double pAp = host_sum_blocks_reduced_0193(dBlockSums, blocks, dScalarSum);

    if (diagnostics != nullptr) {
        diagnostics->usedCuda = true;
        diagnostics->device = device;
        diagnostics->numCells = nc;
        diagnostics->activeCells = nActive;
        diagnostics->inactiveCells = nInactive;
        diagnostics->blocks = blocks;
        diagnostics->threadsPerBlock = threadsPerBlock;
        diagnostics->pAp = pAp;
    }
    return pAp;
}

bool cuda_q6_solve_cg_operator_plan(
    const EllipticOperatorPlan& plan,
    const std::vector<double>& rhs,
    std::vector<double>& phi,
    const CudaQ6CgParams& params,
    CudaQ6CgDiagnostics* diagnostics) {

    validate_plan(plan, "cuda_q6_solve_cg_operator_plan");
    const int nc = plan.numCells;
    require_plan_vector_size(rhs, nc, "cuda_q6_solve_cg_operator_plan", "rhs");

    int device = -1;
    cuda_check(cudaGetDevice(&device), "cudaGetDevice");

    phi.assign(static_cast<std::size_t>(nc), 0.0);
    const int nActive = static_cast<int>(plan.activeCells.size());
    const int nInactive = static_cast<int>(plan.inactiveCells.size());
    CudaQ6CgDiagnostics localDiag{};
    const bool timingEnabled0192 = cuda_q6_timing_enabled_0192();
    const auto totalT0 = CudaQ6Clock::now();
    if (timingEnabled0192) {
        cuda_q6_register_timing_atexit_0192();
    }
    localDiag.usedCuda = true;
    localDiag.device = device;
    localDiag.numCells = nc;
    localDiag.activeCells = nActive;
    localDiag.inactiveCells = nInactive;

    if (nActive == 0 || nc == 0) {
        localDiag.totalSeconds = seconds_since_0192(totalT0);
        cuda_q6_accumulate_timing_0192(localDiag);
        localDiag.converged = true;
        if (diagnostics != nullptr) {
            *diagnostics = localDiag;
        }
        return true;
    }

    constexpr int threadsPerBlock = 256;
    const int blocks = choose_blocks(nActive, threadsPerBlock);
    const int inactiveBlocks = choose_blocks(nInactive, threadsPerBlock);
    const bool disablePlanCache = cuda_q6_plan_cache_disabled();
    CudaQ6CgDeviceWorkspace uncachedWorkspace;
    CudaQ6CgDeviceWorkspace& cgWorkspace = disablePlanCache
        ? uncachedWorkspace
        : cuda_q6_thread_local_cg_workspace();
    cgWorkspace.prepare_for_plan(plan, device, blocks, inactiveBlocks, disablePlanCache);
    {
        const auto t0 = CudaQ6Clock::now();
        cgWorkspace.dRhs.upload(rhs, "copy rhs cached");
        if (timingEnabled0192) {
            localDiag.uploadRhsSeconds += seconds_since_0192(t0);
        }
    }

    localDiag.blocks = blocks;
    localDiag.threadsPerBlock = threadsPerBlock;

    {
        const auto t0 = CudaQ6Clock::now();
        q6_initialize_cg_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
            nActive, cgWorkspace.dActive.data(), cgWorkspace.dRhs.data(), cgWorkspace.dPhi.data(), cgWorkspace.dR.data(), cgWorkspace.dP.data(), cgWorkspace.dAp.data(), cgWorkspace.dBlockSums.data());
        cuda_check(cudaGetLastError(), "q6_initialize_cg_kernel launch");
        cuda_q6_optional_synchronize("q6_initialize_cg_kernel debug synchronize");
        if (timingEnabled0192) {
            localDiag.initializeSeconds += seconds_since_0192(t0);
        }
    }

    if (nInactive > 0) {
        const auto t0 = CudaQ6Clock::now();
        q6_zero_inactive_kernel<<<inactiveBlocks, threadsPerBlock>>>(
            nInactive, cgWorkspace.dInactive.data(), cgWorkspace.dPhi.data(), cgWorkspace.dR.data(), cgWorkspace.dP.data(), cgWorkspace.dAp.data());
        cuda_check(cudaGetLastError(), "q6_zero_inactive_kernel launch");
        cuda_q6_optional_synchronize("q6_zero_inactive_kernel debug synchronize");
        if (timingEnabled0192) {
            localDiag.zeroInactiveSeconds += seconds_since_0192(t0);
        }
    }

    double rr = host_sum_blocks_reduced_0193(cgWorkspace.dBlockSums, blocks, cgWorkspace.dScalarSum,
                                             timingEnabled0192 ? &localDiag.hostReductionSeconds : nullptr,
                                             timingEnabled0192 ? &localDiag.reductionDownloads : nullptr);
    const double rhsNorm = std::sqrt(std::max(0.0, rr));
    localDiag.rhsNorm = rhsNorm;
    if (rhsNorm <= std::numeric_limits<double>::epsilon()) {
        localDiag.converged = true;
        localDiag.iterations = 0;
        localDiag.residualAbs = 0.0;
        localDiag.residualRel = 0.0;
        {
            const auto t0 = CudaQ6Clock::now();
            cgWorkspace.dPhi.download(phi, "copy phi back");
            if (timingEnabled0192) {
                localDiag.downloadPhiSeconds += seconds_since_0192(t0);
            }
        }
        localDiag.totalSeconds = seconds_since_0192(totalT0);
        cuda_q6_accumulate_timing_0192(localDiag);
        if (diagnostics != nullptr) {
            *diagnostics = localDiag;
        }
        return true;
    }

    const double absTol = std::max(0.0, params.tolerance) * rhsNorm;
    const int maxIt = std::max(0, params.maxIterations);
    bool converged = false;

    const bool deviceScalarCg0196 = cuda_q6_device_scalar_cg_enabled_0196();
    const int requestedBatchSize0197 = deviceScalarCg0196 ? cuda_q6_device_scalar_cg_batch_size_0197(params) : 1;
    const int deviceBatchSize0197 = std::max(1, requestedBatchSize0197);
    localDiag.deviceScalarCgBatchSize = deviceBatchSize0197;

    if (deviceScalarCg0196) {
        upload_device_scalar_0196(cgWorkspace.dRr, rr, "copy initial rr to device scalar");
        const double absTolSq = absTol * absTol;
        int it = 0;
        while (it < maxIt) {
            int batchLimit = std::min(maxIt, it + deviceBatchSize0197);
            if (params.removePhiMeanFinal && params.meanRemovalPeriod > 0) {
                const int nextMeanRemoval = ((it / params.meanRemovalPeriod) + 1) * params.meanRemovalPeriod;
                batchLimit = std::min(batchLimit, nextMeanRemoval);
            }
            const int batchStart = it;
            const int batchIters = std::max(1, batchLimit - batchStart);

            cuda_check(cudaMemset(cgWorkspace.dConvergedAt.data(), 0, sizeof(int)),
                       "cudaMemset dConvergedAt batch");
            cuda_check(cudaMemset(cgWorkspace.dBreakdownAt.data(), 0, sizeof(int)),
                       "cudaMemset dBreakdownAt batch");

            for (; it < batchLimit; ++it) {
                const int iterationNumber = it + 1;
                {
                    const auto t0 = CudaQ6Clock::now();
                    if (deviceBatchSize0197 > 1) {
                        q6_apply_operator_plan_batch_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
                            nActive,
                            cgWorkspace.dActive.data(),
                            cgWorkspace.dEast.data(), cgWorkspace.dWest.data(), cgWorkspace.dNorth.data(), cgWorkspace.dSouth.data(),
                            cgWorkspace.dCoeffEast.data(), cgWorkspace.dCoeffWest.data(), cgWorkspace.dCoeffNorth.data(), cgWorkspace.dCoeffSouth.data(),
                            cgWorkspace.dP.data(), cgWorkspace.dAp.data(), cgWorkspace.dBlockSums.data(),
                            cgWorkspace.dConvergedAt.data(), cgWorkspace.dBreakdownAt.data());
                        cuda_check(cudaGetLastError(), "q6_apply_operator_plan_batch_kernel cg launch (0197)");
                        cuda_q6_optional_synchronize("q6_apply_operator_plan_batch_kernel debug synchronize (0197)");
                    } else {
                        q6_apply_operator_plan_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
                            nActive,
                            cgWorkspace.dActive.data(),
                            cgWorkspace.dEast.data(), cgWorkspace.dWest.data(), cgWorkspace.dNorth.data(), cgWorkspace.dSouth.data(),
                            cgWorkspace.dCoeffEast.data(), cgWorkspace.dCoeffWest.data(), cgWorkspace.dCoeffNorth.data(), cgWorkspace.dCoeffSouth.data(),
                            cgWorkspace.dP.data(), cgWorkspace.dAp.data(), cgWorkspace.dBlockSums.data());
                        cuda_check(cudaGetLastError(), "q6_apply_operator_plan_kernel cg launch (device scalar mode)");
                        cuda_q6_optional_synchronize("q6_apply_operator_plan_kernel cg debug synchronize (device scalar mode)");
                    }
                    if (timingEnabled0192) {
                        localDiag.applyOperatorSeconds += seconds_since_0192(t0);
                        localDiag.operatorApplications += 1;
                    }
                }
                reduce_block_sums_to_device_scalar_0196(cgWorkspace.dBlockSums, blocks, cgWorkspace.dPAp,
                                                        "reduce pAp to device scalar (0197)",
                                                        timingEnabled0192 ? &localDiag.deviceScalarReductionSeconds : nullptr);
                {
                    const auto t0 = CudaQ6Clock::now();
                    if (deviceBatchSize0197 > 1) {
                        q6_axpy_residual_device_alpha_batch_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
                            nActive, cgWorkspace.dActive.data(), cgWorkspace.dRr.data(), cgWorkspace.dPAp.data(),
                            cgWorkspace.dP.data(), cgWorkspace.dAp.data(), cgWorkspace.dPhi.data(), cgWorkspace.dR.data(),
                            cgWorkspace.dBlockSums.data(), cgWorkspace.dConvergedAt.data(), cgWorkspace.dBreakdownAt.data(), iterationNumber);
                        cuda_check(cudaGetLastError(), "q6_axpy_residual_device_alpha_batch_kernel launch (0197)");
                        cuda_q6_optional_synchronize("q6_axpy_residual_device_alpha_batch_kernel debug synchronize (0197)");
                    } else {
                        q6_axpy_residual_device_alpha_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
                            nActive, cgWorkspace.dActive.data(), cgWorkspace.dRr.data(), cgWorkspace.dPAp.data(),
                            cgWorkspace.dP.data(), cgWorkspace.dAp.data(), cgWorkspace.dPhi.data(), cgWorkspace.dR.data(),
                            cgWorkspace.dBlockSums.data());
                        cuda_check(cudaGetLastError(), "q6_axpy_residual_device_alpha_kernel launch");
                        cuda_q6_optional_synchronize("q6_axpy_residual_device_alpha_kernel debug synchronize");
                    }
                    if (timingEnabled0192) {
                        localDiag.axpyResidualSeconds += seconds_since_0192(t0);
                    }
                }
                reduce_block_sums_to_device_scalar_0196(cgWorkspace.dBlockSums, blocks, cgWorkspace.dRrNew,
                                                        "reduce rrNew to device scalar (0197)",
                                                        timingEnabled0192 ? &localDiag.deviceScalarReductionSeconds : nullptr);

                const bool endOfBatch = (iterationNumber == batchLimit);
                const bool removeMeanThisIteration =
                    params.removePhiMeanFinal &&
                    params.meanRemovalPeriod > 0 &&
                    ((iterationNumber) % params.meanRemovalPeriod == 0);
                if (removeMeanThisIteration) {
                    q6_check_convergence_no_update_batch_kernel<<<1, 1>>>(
                        cgWorkspace.dRrNew.data(), absTolSq,
                        cgWorkspace.dConvergedAt.data(), cgWorkspace.dBreakdownAt.data(), iterationNumber);
                    cuda_check(cudaGetLastError(), "q6_check_convergence_no_update_batch_kernel launch (0197)");
                    cuda_q6_optional_synchronize("q6_check_convergence_no_update_batch_kernel debug synchronize (0197)");
                } else {
                    const auto t0 = CudaQ6Clock::now();
                    q6_update_direction_device_beta_batch_kernel<<<blocks, threadsPerBlock>>>(
                        nActive, cgWorkspace.dActive.data(), cgWorkspace.dRr.data(), cgWorkspace.dRrNew.data(),
                        cgWorkspace.dR.data(), cgWorkspace.dP.data(), absTolSq,
                        cgWorkspace.dConvergedAt.data(), cgWorkspace.dBreakdownAt.data(), iterationNumber);
                    cuda_check(cudaGetLastError(), "q6_update_direction_device_beta_batch_kernel launch (0197)");
                    cuda_q6_optional_synchronize("q6_update_direction_device_beta_batch_kernel debug synchronize (0197)");
                    if (timingEnabled0192) {
                        localDiag.updateDirectionSeconds += seconds_since_0192(t0);
                    }
                }
                // 0198 fix: at a mean-removal boundary, keep dRr equal to the
                // pre-update residual norm until the gauge-fixed residual norm has
                // been computed.  0197 copied dRr <- dRrNew unconditionally here;
                // the post-mean-removal beta was then formed with the wrong
                // denominator, breaking CG conjugacy even for batchSize=1.
                if (!removeMeanThisIteration) {
                    copy_device_scalar_0196(cgWorkspace.dRr, cgWorkspace.dRrNew,
                                            "copy batched rrNew to rrOld device scalar (0198)");
                }
                (void)endOfBatch;
            }

            int convergedAt = 0;
            int breakdownAt = 0;
            const auto downloadT0 = CudaQ6Clock::now();
            cuda_check(cudaMemcpy(&convergedAt, cgWorkspace.dConvergedAt.data(), sizeof(int), cudaMemcpyDeviceToHost),
                       "copy convergedAt scalar back (0197)");
            cuda_check(cudaMemcpy(&breakdownAt, cgWorkspace.dBreakdownAt.data(), sizeof(int), cudaMemcpyDeviceToHost),
                       "copy breakdownAt scalar back (0197)");
            double rrNew = download_device_scalar_0196(cgWorkspace.dRrNew, "copy batched rrNew scalar back (0197)",
                                                       nullptr, nullptr);
            if (timingEnabled0192) {
                localDiag.hostReductionSeconds += seconds_since_0192(downloadT0);
                localDiag.reductionDownloads += 1;
                localDiag.deviceScalarCgConvergenceDownloads += 1;
            }

            const int batchEndIteration = batchLimit;
            const bool removeMeanAtBatchEnd =
                params.removePhiMeanFinal &&
                params.meanRemovalPeriod > 0 &&
                (batchEndIteration % params.meanRemovalPeriod == 0);

            if (breakdownAt > 0) {
                localDiag.iterations = breakdownAt;
                rr = rrNew;
                break;
            }

            if (convergedAt > 0 && !(removeMeanAtBatchEnd && convergedAt == batchEndIteration)) {
                localDiag.iterations = convergedAt;
                localDiag.deviceScalarCgIterations += std::max(0, convergedAt - batchStart);
                localDiag.deviceScalarCgBatches += 1;
                rr = rrNew;
                localDiag.residualAbs = std::sqrt(std::max(0.0, rrNew));
                localDiag.residualRel = localDiag.residualAbs / rhsNorm;
                converged = true;
                break;
            }

            localDiag.deviceScalarCgIterations += batchIters;
            localDiag.deviceScalarCgBatches += 1;

            if (removeMeanAtBatchEnd) {
                const auto t0 = CudaQ6Clock::now();
                subtract_active_mean(nActive, blocks, threadsPerBlock, cgWorkspace.dActive, cgWorkspace.dPhi, cgWorkspace.dBlockSums, cgWorkspace.dScalarSum,
                                     timingEnabled0192 ? &localDiag.hostReductionSeconds : nullptr,
                                     timingEnabled0192 ? &localDiag.reductionDownloads : nullptr);
                const double residualSumBeforeMean = subtract_active_mean(
                    nActive, blocks, threadsPerBlock, cgWorkspace.dActive, cgWorkspace.dR, cgWorkspace.dBlockSums, cgWorkspace.dScalarSum,
                    timingEnabled0192 ? &localDiag.hostReductionSeconds : nullptr,
                    timingEnabled0192 ? &localDiag.reductionDownloads : nullptr);
                if (cuda_q6_residual_norm_shortcut_enabled_0195()) {
                    const double correction = (residualSumBeforeMean * residualSumBeforeMean) / static_cast<double>(nActive);
                    rrNew = std::max(0.0, rrNew - correction);
                    localDiag.residualNormFromMeanRemovalShortcuts += 1;
                } else {
                    q6_sum_active_squares_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
                        nActive, cgWorkspace.dActive.data(), cgWorkspace.dR.data(), cgWorkspace.dBlockSums.data());
                    cuda_check(cudaGetLastError(), "q6_sum_active_squares_kernel residual after mean removal launch (0197)");
                    cuda_q6_optional_synchronize("q6_sum_active_squares_kernel residual after mean removal debug synchronize (0197)");
                    rrNew = host_sum_blocks_reduced_0193(cgWorkspace.dBlockSums, blocks, cgWorkspace.dScalarSum,
                                                         timingEnabled0192 ? &localDiag.hostReductionSeconds : nullptr,
                                                         timingEnabled0192 ? &localDiag.reductionDownloads : nullptr);
                }
                upload_device_scalar_0196(cgWorkspace.dRrNew, rrNew, "copy mean-corrected rrNew to device scalar (0198)");
                if (timingEnabled0192) {
                    localDiag.meanRemovalSeconds += seconds_since_0192(t0);
                }

                localDiag.iterations = batchEndIteration;
                localDiag.residualAbs = std::sqrt(std::max(0.0, rrNew));
                localDiag.residualRel = localDiag.residualAbs / rhsNorm;
                if (localDiag.residualAbs <= absTol) {
                    rr = rrNew;
                    converged = true;
                    break;
                }

                {
                    const auto t0 = CudaQ6Clock::now();
                    q6_update_direction_device_beta_kernel<<<blocks, threadsPerBlock>>>(
                        nActive, cgWorkspace.dActive.data(), cgWorkspace.dRrNew.data(), cgWorkspace.dRr.data(),
                        cgWorkspace.dR.data(), cgWorkspace.dP.data());
                    cuda_check(cudaGetLastError(), "q6_update_direction_device_beta_kernel mean-removal launch (0198)");
                    cuda_q6_optional_synchronize("q6_update_direction_device_beta_kernel mean-removal debug synchronize (0198)");
                    if (timingEnabled0192) {
                        localDiag.updateDirectionSeconds += seconds_since_0192(t0);
                    }
                }
                copy_device_scalar_0196(cgWorkspace.dRr, cgWorkspace.dRrNew, "copy mean-corrected rrNew to rrOld device scalar (0198)");
            }

            rr = rrNew;
            localDiag.iterations = batchEndIteration;
            localDiag.residualAbs = std::sqrt(std::max(0.0, rr));
            localDiag.residualRel = localDiag.residualAbs / rhsNorm;
        }
    } else {
    for (int it = 0; it < maxIt; ++it) {
        {
            const auto t0 = CudaQ6Clock::now();
            q6_apply_operator_plan_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
                nActive,
                cgWorkspace.dActive.data(),
                cgWorkspace.dEast.data(), cgWorkspace.dWest.data(), cgWorkspace.dNorth.data(), cgWorkspace.dSouth.data(),
                cgWorkspace.dCoeffEast.data(), cgWorkspace.dCoeffWest.data(), cgWorkspace.dCoeffNorth.data(), cgWorkspace.dCoeffSouth.data(),
                cgWorkspace.dP.data(), cgWorkspace.dAp.data(), cgWorkspace.dBlockSums.data());
            cuda_check(cudaGetLastError(), "q6_apply_operator_plan_kernel cg launch");
            cuda_q6_optional_synchronize("q6_apply_operator_plan_kernel cg debug synchronize");
            if (timingEnabled0192) {
                localDiag.applyOperatorSeconds += seconds_since_0192(t0);
                localDiag.operatorApplications += 1;
            }
        }
        const double pAp = host_sum_blocks_reduced_0193(cgWorkspace.dBlockSums, blocks, cgWorkspace.dScalarSum,
                                                        timingEnabled0192 ? &localDiag.hostReductionSeconds : nullptr,
                                                        timingEnabled0192 ? &localDiag.reductionDownloads : nullptr);
        localDiag.lastPAp = pAp;
        if (!(pAp > 0.0) || !std::isfinite(pAp)) {
            break;
        }

        const double alpha = rr / pAp;
        {
            const auto t0 = CudaQ6Clock::now();
            q6_axpy_residual_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
                nActive, cgWorkspace.dActive.data(), alpha, cgWorkspace.dP.data(), cgWorkspace.dAp.data(), cgWorkspace.dPhi.data(), cgWorkspace.dR.data(), cgWorkspace.dBlockSums.data());
            cuda_check(cudaGetLastError(), "q6_axpy_residual_kernel launch");
            cuda_q6_optional_synchronize("q6_axpy_residual_kernel debug synchronize");
            if (timingEnabled0192) {
                localDiag.axpyResidualSeconds += seconds_since_0192(t0);
            }
        }
        double rrNew = host_sum_blocks_reduced_0193(cgWorkspace.dBlockSums, blocks, cgWorkspace.dScalarSum,
                                                    timingEnabled0192 ? &localDiag.hostReductionSeconds : nullptr,
                                                    timingEnabled0192 ? &localDiag.reductionDownloads : nullptr);

        const bool removeMeanThisIteration =
            params.removePhiMeanFinal &&
            params.meanRemovalPeriod > 0 &&
            ((it + 1) % params.meanRemovalPeriod == 0);
        if (removeMeanThisIteration) {
            const auto t0 = CudaQ6Clock::now();
            subtract_active_mean(nActive, blocks, threadsPerBlock, cgWorkspace.dActive, cgWorkspace.dPhi, cgWorkspace.dBlockSums, cgWorkspace.dScalarSum,
                                 timingEnabled0192 ? &localDiag.hostReductionSeconds : nullptr,
                                 timingEnabled0192 ? &localDiag.reductionDownloads : nullptr);
            const double residualSumBeforeMean = subtract_active_mean(
                nActive, blocks, threadsPerBlock, cgWorkspace.dActive, cgWorkspace.dR, cgWorkspace.dBlockSums, cgWorkspace.dScalarSum,
                timingEnabled0192 ? &localDiag.hostReductionSeconds : nullptr,
                timingEnabled0192 ? &localDiag.reductionDownloads : nullptr);
            if (cuda_q6_residual_norm_shortcut_enabled_0195()) {
                const double correction = (residualSumBeforeMean * residualSumBeforeMean) / static_cast<double>(nActive);
                rrNew = std::max(0.0, rrNew - correction);
                localDiag.residualNormFromMeanRemovalShortcuts += 1;
            } else {
                q6_sum_active_squares_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
                    nActive, cgWorkspace.dActive.data(), cgWorkspace.dR.data(), cgWorkspace.dBlockSums.data());
                cuda_check(cudaGetLastError(), "q6_sum_active_squares_kernel residual after mean removal launch");
                cuda_q6_optional_synchronize("q6_sum_active_squares_kernel residual after mean removal debug synchronize");
                rrNew = host_sum_blocks_reduced_0193(cgWorkspace.dBlockSums, blocks, cgWorkspace.dScalarSum,
                                                     timingEnabled0192 ? &localDiag.hostReductionSeconds : nullptr,
                                                     timingEnabled0192 ? &localDiag.reductionDownloads : nullptr);
            }
            if (timingEnabled0192) {
                localDiag.meanRemovalSeconds += seconds_since_0192(t0);
            }
        }

        localDiag.iterations = it + 1;
        localDiag.residualAbs = std::sqrt(std::max(0.0, rrNew));
        localDiag.residualRel = localDiag.residualAbs / rhsNorm;
        if (localDiag.residualAbs <= absTol) {
            rr = rrNew;
            converged = true;
            break;
        }

        const double beta = rrNew / rr;
        {
            const auto t0 = CudaQ6Clock::now();
            q6_update_direction_kernel<<<blocks, threadsPerBlock>>>(
                nActive, cgWorkspace.dActive.data(), beta, cgWorkspace.dR.data(), cgWorkspace.dP.data());
            cuda_check(cudaGetLastError(), "q6_update_direction_kernel launch");
            cuda_q6_optional_synchronize("q6_update_direction_kernel debug synchronize");
            if (timingEnabled0192) {
                localDiag.updateDirectionSeconds += seconds_since_0192(t0);
            }
        }
        rr = rrNew;
    }
    }

    if (params.removePhiMeanFinal) {
        const auto t0 = CudaQ6Clock::now();
        subtract_active_mean(nActive, blocks, threadsPerBlock, cgWorkspace.dActive, cgWorkspace.dPhi, cgWorkspace.dBlockSums, cgWorkspace.dScalarSum,
                             timingEnabled0192 ? &localDiag.hostReductionSeconds : nullptr,
                             timingEnabled0192 ? &localDiag.reductionDownloads : nullptr);
        if (timingEnabled0192) {
            localDiag.finalMeanRemovalSeconds += seconds_since_0192(t0);
        }
    }

    {
        const auto t0 = CudaQ6Clock::now();
        cgWorkspace.dPhi.download(phi, "copy phi back");
        if (timingEnabled0192) {
            localDiag.downloadPhiSeconds += seconds_since_0192(t0);
        }
    }
    localDiag.totalSeconds = seconds_since_0192(totalT0);
    cuda_q6_accumulate_timing_0192(localDiag);
    localDiag.converged = converged;
    if (!converged && localDiag.iterations == 0) {
        localDiag.residualAbs = rhsNorm;
        localDiag.residualRel = 1.0;
    }
    if (diagnostics != nullptr) {
        *diagnostics = localDiag;
    }
    return converged;
}

} // namespace mpcd

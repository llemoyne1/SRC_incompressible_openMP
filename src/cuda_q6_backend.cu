#include "cuda_q6_backend.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
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

double host_sum_blocks(const DeviceBuffer<double>& dBlockSums) {
    std::vector<double> blockSums;
    dBlockSums.download(blockSums, "copy block sums back");
    double sum = 0.0;
    for (const double v : blockSums) {
        sum += v;
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

void subtract_active_mean(const int nActive,
                          const int blocks,
                          const int threadsPerBlock,
                          const DeviceBuffer<int>& dActive,
                          DeviceBuffer<double>& dValues,
                          DeviceBuffer<double>& dBlockSums) {
    if (nActive <= 0) {
        return;
    }
    q6_sum_active_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
        nActive, dActive.data(), dValues.data(), dBlockSums.data());
    cuda_check(cudaGetLastError(), "q6_sum_active_kernel launch");
    cuda_q6_optional_synchronize("q6_sum_active_kernel debug synchronize");
    const double mean = host_sum_blocks(dBlockSums) / static_cast<double>(nActive);
    q6_subtract_mean_active_kernel<<<blocks, threadsPerBlock>>>(
        nActive, dActive.data(), mean, dValues.data());
    cuda_check(cudaGetLastError(), "q6_subtract_mean_active_kernel launch");
    cuda_q6_optional_synchronize("q6_subtract_mean_active_kernel debug synchronize");
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
    q6_apply_operator_plan_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
        nActive,
        dActive.data(),
        dEast.data(), dWest.data(), dNorth.data(), dSouth.data(),
        dCoeffEast.data(), dCoeffWest.data(), dCoeffNorth.data(), dCoeffSouth.data(),
        dPhi.data(), dAphi.data(), dBlockSums.data());
    cuda_check(cudaGetLastError(), "q6_apply_operator_plan_kernel launch");
    cuda_q6_optional_synchronize("q6_apply_operator_plan_kernel debug synchronize");

    dAphi.download(Aphi, "copy Aphi back");
    const double pAp = host_sum_blocks(dBlockSums);

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
    localDiag.usedCuda = true;
    localDiag.device = device;
    localDiag.numCells = nc;
    localDiag.activeCells = nActive;
    localDiag.inactiveCells = nInactive;

    if (nActive == 0 || nc == 0) {
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
    cgWorkspace.dRhs.upload(rhs, "copy rhs cached");

    localDiag.blocks = blocks;
    localDiag.threadsPerBlock = threadsPerBlock;

    q6_initialize_cg_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
        nActive, cgWorkspace.dActive.data(), cgWorkspace.dRhs.data(), cgWorkspace.dPhi.data(), cgWorkspace.dR.data(), cgWorkspace.dP.data(), cgWorkspace.dAp.data(), cgWorkspace.dBlockSums.data());
    cuda_check(cudaGetLastError(), "q6_initialize_cg_kernel launch");
    cuda_q6_optional_synchronize("q6_initialize_cg_kernel debug synchronize");

    if (nInactive > 0) {
        q6_zero_inactive_kernel<<<inactiveBlocks, threadsPerBlock>>>(
            nInactive, cgWorkspace.dInactive.data(), cgWorkspace.dPhi.data(), cgWorkspace.dR.data(), cgWorkspace.dP.data(), cgWorkspace.dAp.data());
        cuda_check(cudaGetLastError(), "q6_zero_inactive_kernel launch");
        cuda_q6_optional_synchronize("q6_zero_inactive_kernel debug synchronize");
    }

    double rr = host_sum_blocks(cgWorkspace.dBlockSums);
    const double rhsNorm = std::sqrt(std::max(0.0, rr));
    localDiag.rhsNorm = rhsNorm;
    if (rhsNorm <= std::numeric_limits<double>::epsilon()) {
        localDiag.converged = true;
        localDiag.iterations = 0;
        localDiag.residualAbs = 0.0;
        localDiag.residualRel = 0.0;
        cgWorkspace.dPhi.download(phi, "copy phi back");
        if (diagnostics != nullptr) {
            *diagnostics = localDiag;
        }
        return true;
    }

    const double absTol = std::max(0.0, params.tolerance) * rhsNorm;
    const int maxIt = std::max(0, params.maxIterations);
    bool converged = false;

    for (int it = 0; it < maxIt; ++it) {
        q6_apply_operator_plan_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
            nActive,
            cgWorkspace.dActive.data(),
            cgWorkspace.dEast.data(), cgWorkspace.dWest.data(), cgWorkspace.dNorth.data(), cgWorkspace.dSouth.data(),
            cgWorkspace.dCoeffEast.data(), cgWorkspace.dCoeffWest.data(), cgWorkspace.dCoeffNorth.data(), cgWorkspace.dCoeffSouth.data(),
            cgWorkspace.dP.data(), cgWorkspace.dAp.data(), cgWorkspace.dBlockSums.data());
        cuda_check(cudaGetLastError(), "q6_apply_operator_plan_kernel cg launch");
        cuda_q6_optional_synchronize("q6_apply_operator_plan_kernel cg debug synchronize");
        const double pAp = host_sum_blocks(cgWorkspace.dBlockSums);
        localDiag.lastPAp = pAp;
        if (!(pAp > 0.0) || !std::isfinite(pAp)) {
            break;
        }

        const double alpha = rr / pAp;
        q6_axpy_residual_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
            nActive, cgWorkspace.dActive.data(), alpha, cgWorkspace.dP.data(), cgWorkspace.dAp.data(), cgWorkspace.dPhi.data(), cgWorkspace.dR.data(), cgWorkspace.dBlockSums.data());
        cuda_check(cudaGetLastError(), "q6_axpy_residual_kernel launch");
        cuda_q6_optional_synchronize("q6_axpy_residual_kernel debug synchronize");
        double rrNew = host_sum_blocks(cgWorkspace.dBlockSums);

        const bool removeMeanThisIteration =
            params.removePhiMeanFinal &&
            params.meanRemovalPeriod > 0 &&
            ((it + 1) % params.meanRemovalPeriod == 0);
        if (removeMeanThisIteration) {
            subtract_active_mean(nActive, blocks, threadsPerBlock, cgWorkspace.dActive, cgWorkspace.dPhi, cgWorkspace.dBlockSums);
            subtract_active_mean(nActive, blocks, threadsPerBlock, cgWorkspace.dActive, cgWorkspace.dR, cgWorkspace.dBlockSums);
            q6_sum_active_squares_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
                nActive, cgWorkspace.dActive.data(), cgWorkspace.dR.data(), cgWorkspace.dBlockSums.data());
            cuda_check(cudaGetLastError(), "q6_sum_active_squares_kernel residual after mean removal launch");
            cuda_q6_optional_synchronize("q6_sum_active_squares_kernel residual after mean removal debug synchronize");
            rrNew = host_sum_blocks(cgWorkspace.dBlockSums);
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
        q6_update_direction_kernel<<<blocks, threadsPerBlock>>>(
            nActive, cgWorkspace.dActive.data(), beta, cgWorkspace.dR.data(), cgWorkspace.dP.data());
        cuda_check(cudaGetLastError(), "q6_update_direction_kernel launch");
        cuda_q6_optional_synchronize("q6_update_direction_kernel debug synchronize");
        rr = rrNew;
    }

    if (params.removePhiMeanFinal) {
        subtract_active_mean(nActive, blocks, threadsPerBlock, cgWorkspace.dActive, cgWorkspace.dPhi, cgWorkspace.dBlockSums);
    }

    cgWorkspace.dPhi.download(phi, "copy phi back");
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

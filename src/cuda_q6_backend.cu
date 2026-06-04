#include "cuda_q6_backend.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
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

    DeviceBuffer<int> dActive(static_cast<std::size_t>(nActive));
    DeviceBuffer<int> dInactive(static_cast<std::size_t>(std::max(1, nInactive)));
    DeviceBuffer<int> dEast(static_cast<std::size_t>(nc));
    DeviceBuffer<int> dWest(static_cast<std::size_t>(nc));
    DeviceBuffer<int> dNorth(static_cast<std::size_t>(nc));
    DeviceBuffer<int> dSouth(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dCoeffEast(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dCoeffWest(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dCoeffNorth(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dCoeffSouth(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dRhs(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dPhi(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dR(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dP(static_cast<std::size_t>(nc));
    DeviceBuffer<double> dAp(static_cast<std::size_t>(nc));

    dActive.upload(plan.activeCells, "copy activeCells");
    if (nInactive > 0) {
        dInactive.upload(plan.inactiveCells, "copy inactiveCells");
    }
    dEast.upload(plan.east, "copy east");
    dWest.upload(plan.west, "copy west");
    dNorth.upload(plan.north, "copy north");
    dSouth.upload(plan.south, "copy south");
    dCoeffEast.upload(plan.coeffEast, "copy coeffEast");
    dCoeffWest.upload(plan.coeffWest, "copy coeffWest");
    dCoeffNorth.upload(plan.coeffNorth, "copy coeffNorth");
    dCoeffSouth.upload(plan.coeffSouth, "copy coeffSouth");
    dRhs.upload(rhs, "copy rhs");

    cuda_check(cudaMemset(dPhi.data(), 0, static_cast<std::size_t>(nc) * sizeof(double)), "cudaMemset phi");
    cuda_check(cudaMemset(dR.data(), 0, static_cast<std::size_t>(nc) * sizeof(double)), "cudaMemset r");
    cuda_check(cudaMemset(dP.data(), 0, static_cast<std::size_t>(nc) * sizeof(double)), "cudaMemset p");
    cuda_check(cudaMemset(dAp.data(), 0, static_cast<std::size_t>(nc) * sizeof(double)), "cudaMemset Ap");

    constexpr int threadsPerBlock = 256;
    const int blocks = choose_blocks(nActive, threadsPerBlock);
    const int inactiveBlocks = choose_blocks(nInactive, threadsPerBlock);
    DeviceBuffer<double> dBlockSums(static_cast<std::size_t>(blocks));
    localDiag.blocks = blocks;
    localDiag.threadsPerBlock = threadsPerBlock;

    q6_initialize_cg_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
        nActive, dActive.data(), dRhs.data(), dPhi.data(), dR.data(), dP.data(), dAp.data(), dBlockSums.data());
    cuda_check(cudaGetLastError(), "q6_initialize_cg_kernel launch");
    cuda_q6_optional_synchronize("q6_initialize_cg_kernel debug synchronize");

    if (nInactive > 0) {
        q6_zero_inactive_kernel<<<inactiveBlocks, threadsPerBlock>>>(
            nInactive, dInactive.data(), dPhi.data(), dR.data(), dP.data(), dAp.data());
        cuda_check(cudaGetLastError(), "q6_zero_inactive_kernel launch");
        cuda_q6_optional_synchronize("q6_zero_inactive_kernel debug synchronize");
    }

    double rr = host_sum_blocks(dBlockSums);
    const double rhsNorm = std::sqrt(std::max(0.0, rr));
    localDiag.rhsNorm = rhsNorm;
    if (rhsNorm <= std::numeric_limits<double>::epsilon()) {
        localDiag.converged = true;
        localDiag.iterations = 0;
        localDiag.residualAbs = 0.0;
        localDiag.residualRel = 0.0;
        dPhi.download(phi, "copy phi back");
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
            dActive.data(),
            dEast.data(), dWest.data(), dNorth.data(), dSouth.data(),
            dCoeffEast.data(), dCoeffWest.data(), dCoeffNorth.data(), dCoeffSouth.data(),
            dP.data(), dAp.data(), dBlockSums.data());
        cuda_check(cudaGetLastError(), "q6_apply_operator_plan_kernel cg launch");
        cuda_q6_optional_synchronize("q6_apply_operator_plan_kernel cg debug synchronize");
        const double pAp = host_sum_blocks(dBlockSums);
        localDiag.lastPAp = pAp;
        if (!(pAp > 0.0) || !std::isfinite(pAp)) {
            break;
        }

        const double alpha = rr / pAp;
        q6_axpy_residual_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
            nActive, dActive.data(), alpha, dP.data(), dAp.data(), dPhi.data(), dR.data(), dBlockSums.data());
        cuda_check(cudaGetLastError(), "q6_axpy_residual_kernel launch");
        cuda_q6_optional_synchronize("q6_axpy_residual_kernel debug synchronize");
        double rrNew = host_sum_blocks(dBlockSums);

        const bool removeMeanThisIteration =
            params.removePhiMeanFinal &&
            params.meanRemovalPeriod > 0 &&
            ((it + 1) % params.meanRemovalPeriod == 0);
        if (removeMeanThisIteration) {
            subtract_active_mean(nActive, blocks, threadsPerBlock, dActive, dPhi, dBlockSums);
            subtract_active_mean(nActive, blocks, threadsPerBlock, dActive, dR, dBlockSums);
            q6_sum_active_squares_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
                nActive, dActive.data(), dR.data(), dBlockSums.data());
            cuda_check(cudaGetLastError(), "q6_sum_active_squares_kernel residual after mean removal launch");
            cuda_q6_optional_synchronize("q6_sum_active_squares_kernel residual after mean removal debug synchronize");
            rrNew = host_sum_blocks(dBlockSums);
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
            nActive, dActive.data(), beta, dR.data(), dP.data());
        cuda_check(cudaGetLastError(), "q6_update_direction_kernel launch");
        cuda_q6_optional_synchronize("q6_update_direction_kernel debug synchronize");
        rr = rrNew;
    }

    if (params.removePhiMeanFinal) {
        subtract_active_mean(nActive, blocks, threadsPerBlock, dActive, dPhi, dBlockSums);
    }

    dPhi.download(phi, "copy phi back");
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

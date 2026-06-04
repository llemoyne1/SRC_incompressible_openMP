#include "cuda_q6_backend.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <cstddef>
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
                              const char* name) {
    if (static_cast<int>(v.size()) != expected) {
        std::ostringstream oss;
        oss << "cuda_q6_apply_elliptic_operator_plan_and_dot: " << name
            << " size mismatch, expected " << expected << ", got " << v.size();
        throw std::runtime_error(oss.str());
    }
}

void require_plan_vector_size(const std::vector<double>& v,
                              const int expected,
                              const char* name) {
    if (static_cast<int>(v.size()) != expected) {
        std::ostringstream oss;
        oss << "cuda_q6_apply_elliptic_operator_plan_and_dot: " << name
            << " size mismatch, expected " << expected << ", got " << v.size();
        throw std::runtime_error(oss.str());
    }
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

int choose_blocks(const int nActive, const int threadsPerBlock) {
    if (nActive <= 0) {
        return 0;
    }
    const int natural = (nActive + threadsPerBlock - 1) / threadsPerBlock;
    return std::max(1, std::min(1024, natural));
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

    if (plan.numCells < 0) {
        throw std::runtime_error("cuda_q6_apply_elliptic_operator_plan_and_dot: negative numCells");
    }
    const int nc = plan.numCells;
    require_plan_vector_size(phi, nc, "phi");
    require_plan_vector_size(plan.east, nc, "plan.east");
    require_plan_vector_size(plan.west, nc, "plan.west");
    require_plan_vector_size(plan.north, nc, "plan.north");
    require_plan_vector_size(plan.south, nc, "plan.south");
    require_plan_vector_size(plan.coeffEast, nc, "plan.coeffEast");
    require_plan_vector_size(plan.coeffWest, nc, "plan.coeffWest");
    require_plan_vector_size(plan.coeffNorth, nc, "plan.coeffNorth");
    require_plan_vector_size(plan.coeffSouth, nc, "plan.coeffSouth");

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
    cuda_check(cudaMemset(dBlockSums.data(), 0, static_cast<std::size_t>(blocks) * sizeof(double)),
               "cudaMemset block sums");

    q6_apply_operator_plan_kernel<<<blocks, threadsPerBlock, threadsPerBlock * sizeof(double)>>>(
        nActive,
        dActive.data(),
        dEast.data(), dWest.data(), dNorth.data(), dSouth.data(),
        dCoeffEast.data(), dCoeffWest.data(), dCoeffNorth.data(), dCoeffSouth.data(),
        dPhi.data(), dAphi.data(), dBlockSums.data());
    cuda_check(cudaGetLastError(), "q6_apply_operator_plan_kernel launch");
    cuda_check(cudaDeviceSynchronize(), "q6_apply_operator_plan_kernel synchronize");

    dAphi.download(Aphi, "copy Aphi back");
    std::vector<double> blockSums;
    dBlockSums.download(blockSums, "copy block sums back");
    double pAp = 0.0;
    for (const double v : blockSums) {
        pAp += v;
    }

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

} // namespace mpcd

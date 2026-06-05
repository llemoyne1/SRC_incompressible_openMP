#include "cuda_cell_workspace.h"

#include <chrono>
#include <stdexcept>
#include <string>

#ifdef MPCD_ENABLE_CUDA_CELL_WORKSPACE
#include <cuda_runtime.h>
#endif

namespace mpcd {
namespace {

using Clock = std::chrono::steady_clock;

double seconds_since_cw(const Clock::time_point& t0) {
    return std::chrono::duration<double>(Clock::now() - t0).count();
}

#ifdef MPCD_ENABLE_CUDA_CELL_WORKSPACE
#define MPCD_CUDA_CW_CHECK(call) do { \
    cudaError_t err__ = (call); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("CUDA error in ") + #call + ": " + cudaGetErrorString(err__)); \
    } \
} while (0)

template <typename T>
void cuda_cw_free(T*& ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}
#endif

} // namespace

struct CudaCellWorkspace::Impl {
    std::uint64_t particleCapacity = 0u;
    int cellCapacity = 0;
    std::uint64_t allocatedBytes = 0u;

    int* cellId = nullptr;
    unsigned int* count = nullptr;
    double* cellMass = nullptr;
    double* cellPx = nullptr;
    double* cellPy = nullptr;
    double* cellUx = nullptr;
    double* cellUy = nullptr;
    double* cosA = nullptr;
    double* sinA = nullptr;
    double* cellKinetic = nullptr;
    double* cellScale = nullptr;
    unsigned long long* fluidCounter = nullptr;
    unsigned long long* rotatedCounter = nullptr;
    unsigned long long* invalidCounter = nullptr;
};

bool cuda_cell_workspace_available() {
#ifdef MPCD_ENABLE_CUDA_CELL_WORKSPACE
    return true;
#else
    return false;
#endif
}

CudaCellWorkspace::CudaCellWorkspace() : impl_(new Impl()) {}

CudaCellWorkspace::~CudaCellWorkspace() { release(); delete impl_; impl_ = nullptr; }

CudaCellWorkspace::CudaCellWorkspace(CudaCellWorkspace&& other) noexcept : impl_(other.impl_) {
    other.impl_ = new Impl();
}

CudaCellWorkspace& CudaCellWorkspace::operator=(CudaCellWorkspace&& other) noexcept {
    if (this != &other) {
        release();
        delete impl_;
        impl_ = other.impl_;
        other.impl_ = new Impl();
    }
    return *this;
}

void CudaCellWorkspace::release() {
#ifdef MPCD_ENABLE_CUDA_CELL_WORKSPACE
    if (impl_ != nullptr) {
        cuda_cw_free(impl_->cellId);
        cuda_cw_free(impl_->count);
        cuda_cw_free(impl_->cellMass);
        cuda_cw_free(impl_->cellPx);
        cuda_cw_free(impl_->cellPy);
        cuda_cw_free(impl_->cellUx);
        cuda_cw_free(impl_->cellUy);
        cuda_cw_free(impl_->cosA);
        cuda_cw_free(impl_->sinA);
        cuda_cw_free(impl_->cellKinetic);
        cuda_cw_free(impl_->cellScale);
        cuda_cw_free(impl_->fluidCounter);
        cuda_cw_free(impl_->rotatedCounter);
        cuda_cw_free(impl_->invalidCounter);
        impl_->particleCapacity = 0u;
        impl_->cellCapacity = 0;
        impl_->allocatedBytes = 0u;
    }
#else
    if (impl_ != nullptr) {
        impl_->particleCapacity = 0u;
        impl_->cellCapacity = 0;
        impl_->allocatedBytes = 0u;
    }
#endif
}

void CudaCellWorkspace::ensure_capacity(std::uint64_t particleCapacity,
                                        int numCells,
                                        CudaCellWorkspaceDiagnostics* diag) {
#ifndef MPCD_ENABLE_CUDA_CELL_WORKSPACE
    (void)particleCapacity; (void)numCells; (void)diag;
    throw std::runtime_error("CudaCellWorkspace::ensure_capacity called without MPCD_ENABLE_CUDA_CELL_WORKSPACE");
#else
    if (impl_ == nullptr) throw std::runtime_error("CudaCellWorkspace::ensure_capacity: null impl");
    if (numCells <= 0) throw std::runtime_error("CudaCellWorkspace::ensure_capacity: invalid numCells");
    const auto tTotal0 = Clock::now();
    const bool reusable = impl_->particleCapacity >= particleCapacity && impl_->cellCapacity >= numCells && impl_->cellId != nullptr;
    if (reusable) {
        if (diag != nullptr) {
            diag->particleCapacity = impl_->particleCapacity;
            diag->numCells = impl_->cellCapacity;
            diag->allocatedBytes = impl_->allocatedBytes;
            diag->reusedAllocation = 1;
            diag->totalSeconds += seconds_since_cw(tTotal0);
        }
        return;
    }

    release();
    const auto t0 = Clock::now();
    const std::size_t n = static_cast<std::size_t>(particleCapacity);
    const std::size_t nc = static_cast<std::size_t>(numCells);
    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t cBytesD = nc * sizeof(double);
    const std::size_t cBytesU = nc * sizeof(unsigned int);

    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->cellId, nBytesI));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->count, cBytesU));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->cellMass, cBytesD));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->cellPx, cBytesD));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->cellPy, cBytesD));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->cellUx, cBytesD));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->cellUy, cBytesD));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->cosA, cBytesD));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->sinA, cBytesD));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->cellKinetic, cBytesD));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->cellScale, cBytesD));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->fluidCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->rotatedCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CW_CHECK(cudaMalloc(&impl_->invalidCounter, sizeof(unsigned long long)));

    impl_->particleCapacity = particleCapacity;
    impl_->cellCapacity = numCells;
    impl_->allocatedBytes = nBytesI + cBytesU + 9u * cBytesD + 3u * sizeof(unsigned long long);

    if (diag != nullptr) {
        diag->particleCapacity = impl_->particleCapacity;
        diag->numCells = impl_->cellCapacity;
        diag->allocatedBytes = impl_->allocatedBytes;
        diag->allocationCalls += 1u;
        diag->reusedAllocation = 0;
        diag->allocateSeconds += seconds_since_cw(t0);
        diag->totalSeconds += seconds_since_cw(tTotal0);
    }
#endif
}

CudaCellWorkspaceDeviceView CudaCellWorkspace::device_view() {
    return static_cast<const CudaCellWorkspace*>(this)->device_view();
}

CudaCellWorkspaceDeviceView CudaCellWorkspace::device_view() const {
    CudaCellWorkspaceDeviceView v{};
    if (impl_ == nullptr) return v;
    v.particleCapacity = impl_->particleCapacity;
    v.numCells = impl_->cellCapacity;
    v.cellId = impl_->cellId;
    v.count = impl_->count;
    v.cellMass = impl_->cellMass;
    v.cellPx = impl_->cellPx;
    v.cellPy = impl_->cellPy;
    v.cellUx = impl_->cellUx;
    v.cellUy = impl_->cellUy;
    v.cosA = impl_->cosA;
    v.sinA = impl_->sinA;
    v.cellKinetic = impl_->cellKinetic;
    v.cellScale = impl_->cellScale;
    v.fluidCounter = impl_->fluidCounter;
    v.rotatedCounter = impl_->rotatedCounter;
    v.invalidCounter = impl_->invalidCounter;
    return v;
}

std::uint64_t CudaCellWorkspace::particle_capacity() const { return impl_ ? impl_->particleCapacity : 0u; }
int CudaCellWorkspace::cell_capacity() const { return impl_ ? impl_->cellCapacity : 0; }
std::uint64_t CudaCellWorkspace::allocated_bytes() const { return impl_ ? impl_->allocatedBytes : 0u; }

} // namespace mpcd

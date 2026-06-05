#pragma once

#include <cstddef>
#include <cstdint>

namespace mpcd {

// 0224: persistent GPU cell workspace shared by CUDA deposit/collision/
// thermostat kernels. It owns all per-particle cellId storage and per-cell
// moment/thermostat scratch arrays used by the current TG periodic persistent
// prototype. The first integration keeps full CPU workspace download for
// diagnostics and downstream CPU stages; the performance win is allocation
// reuse and eliminating duplicated transient cell-buffer ownership.
struct CudaCellWorkspaceDeviceView {
    std::uint64_t particleCapacity = 0u;
    int numCells = 0;
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

struct CudaCellWorkspaceDiagnostics {
    std::uint64_t particleCapacity = 0u;
    int numCells = 0;
    std::uint64_t allocatedBytes = 0u;
    std::uint64_t allocationCalls = 0u;
    int reusedAllocation = 0;
    double allocateSeconds = 0.0;
    double totalSeconds = 0.0;
};

bool cuda_cell_workspace_available();

class CudaCellWorkspace {
public:
    CudaCellWorkspace();
    ~CudaCellWorkspace();

    CudaCellWorkspace(const CudaCellWorkspace&) = delete;
    CudaCellWorkspace& operator=(const CudaCellWorkspace&) = delete;
    CudaCellWorkspace(CudaCellWorkspace&&) noexcept;
    CudaCellWorkspace& operator=(CudaCellWorkspace&&) noexcept;

    void release();
    void ensure_capacity(std::uint64_t particleCapacity,
                         int numCells,
                         CudaCellWorkspaceDiagnostics* diag = nullptr);

    CudaCellWorkspaceDeviceView device_view();
    CudaCellWorkspaceDeviceView device_view() const;

    std::uint64_t particle_capacity() const;
    int cell_capacity() const;
    std::uint64_t allocated_bytes() const;

private:
    struct Impl;
    Impl* impl_ = nullptr;
};

} // namespace mpcd

#!/usr/bin/env python3
from pathlib import Path

root = Path('.')
src = root / 'src' / 'cuda_resampling_pipeline_shadow_0445.cu'
text = src.read_text()

def rep(old, new, label):
    global text
    if old not in text:
        raise SystemExit(f'[0473] failed to locate {label}')
    text = text.replace(old, new, 1)

# Small device-prefix copy helper for op-sized host patchback downloads.
rep('''    void copy_to_host(std::vector<T>& v) const {
        v.resize(n);
        if (n > 0u) CUDA_CHECK_0445(cudaMemcpy(v.data(), ptr, n * sizeof(T), cudaMemcpyDeviceToHost));
    }
    void memset_zero() {
''', '''    void copy_to_host(std::vector<T>& v) const {
        v.resize(n);
        if (n > 0u) CUDA_CHECK_0445(cudaMemcpy(v.data(), ptr, n * sizeof(T), cudaMemcpyDeviceToHost));
    }
    void memset_zero() {
''', 'DeviceBuffer copy_to_host anchor')
# Add helper after DeviceBuffer struct, not inside it.
rep('''    void memset_zero() {
        if (n > 0u) CUDA_CHECK_0445(cudaMemset(ptr, 0, n * sizeof(T)));
    }
};

struct GpuState0445 {
''', '''    void memset_zero() {
        if (n > 0u) CUDA_CHECK_0445(cudaMemset(ptr, 0, n * sizeof(T)));
    }
};

template <typename T>
void copy_device_prefix_to_host_0473(const T* ptr, std::size_t count, std::vector<T>& out) {
    out.resize(count);
    if (count > 0u) CUDA_CHECK_0445(cudaMemcpy(out.data(), ptr, count * sizeof(T), cudaMemcpyDeviceToHost));
}

struct GpuState0445 {
''', '0473 device-prefix copy helper')

# Early env helper before resident core uses it.
rep('''std::uint64_t cuda_resampling_sparse_device_carrier_gate_every_0461()
{
    const char* env = std::getenv("MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_GATE_EVERY_0461");
    if (!env) return 1u;
    try {
        const unsigned long long v = std::stoull(std::string(env));
        return v > 0ull ? static_cast<std::uint64_t>(v) : 1u;
    } catch (...) {
        return 1u;
    }
}

struct GpuDeviceCarrier0455 {
''', '''std::uint64_t cuda_resampling_sparse_device_carrier_gate_every_0461()
{
    const char* env = std::getenv("MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_GATE_EVERY_0461");
    if (!env) return 1u;
    try {
        const unsigned long long v = std::stoull(std::string(env));
        return v > 0ull ? static_cast<std::uint64_t>(v) : 1u;
    } catch (...) {
        return 1u;
    }
}

bool cuda_resampling_host_patchback_0473_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473");
}

struct GpuDeviceCarrier0455 {
''', '0473 early env helper')

# Extend diagnostics struct with patchback fields and host op vectors.
rep('''    std::uint64_t residentSharedState0472 = 0u;
    std::uint64_t residentSharedUploadSkipped0472 = 0u;
    std::uint64_t residentActivePrefixDownload0472 = 0u;
    std::uint64_t sparseGate0461 = 0u;
''', '''    std::uint64_t residentSharedState0472 = 0u;
    std::uint64_t residentSharedUploadSkipped0472 = 0u;
    std::uint64_t residentActivePrefixDownload0472 = 0u;
    std::uint64_t residentHostPatchback0473 = 0u;
    std::uint64_t hostPatchbackOps0473 = 0u;
    std::uint64_t sparseGate0461 = 0u;
''', '0473 diagnostic flags')

rep('''    double stateDownloadSeconds = 0.0;
    double totalSeconds = 0.0;
    bool pass = false;
};
''', '''    double stateDownloadSeconds = 0.0;
    double hostPatchbackSeconds = 0.0;
    double totalSeconds = 0.0;
    bool pass = false;

    std::vector<unsigned int> hostPatchParticle0473;
    std::vector<int> hostPatchReceiver0473;
    std::vector<std::uint32_t> hostPatchType0473;
    std::vector<double> hostPatchMass0473;
    std::vector<double> hostPatchPx0473;
    std::vector<double> hostPatchPy0473;
};
''', '0473 host patch vectors')

# Add host patchback function after insertion kernel.
rep('''__global__ void apply_device_carrier_insertion_kernel_0455(
    int nOps,
    const unsigned int* particleIndex,
    const int* receiverCell,
    const std::uint32_t* particleType,
    const double* particleMass,
    const double* momentumX,
    const double* momentumY,
    std::uint32_t Nx,
    std::uint32_t Ny,
    double dx,
    double dy,
    std::uint64_t nParticles,
    std::uint8_t inactiveRole,
    std::uint8_t fluidRole,
    unsigned int invalidParticle,
    unsigned int* applied,
    double* x,
    double* y,
    double* vx,
    double* vy,
    double* mass,
    std::uint32_t* type,
    std::uint8_t* role) {
    const int op = blockIdx.x * blockDim.x + threadIdx.x;
    if (op >= nOps) return;
    const unsigned int p = particleIndex[op];
    unsigned int ok = 0u;
    if (p != invalidParticle && static_cast<std::uint64_t>(p) < nParticles && role[p] == inactiveRole) {
        const std::uint32_t c = static_cast<std::uint32_t>(receiverCell[op]);
        const std::uint32_t nCells = Nx * Ny;
        const double m = particleMass[op];
        if (c < nCells && m > 0.0) {
            const std::uint32_t ix = c % Nx;
            const std::uint32_t iy = c / Nx;
            const std::uint32_t q = static_cast<std::uint32_t>(op) & 15u;
            const double fx = 0.2 + 0.2 * static_cast<double>(q & 3u);
            const double fy = 0.2 + 0.2 * static_cast<double>(q >> 2u);
            x[p] = (static_cast<double>(ix) + fx) * dx;
            y[p] = (static_cast<double>(iy) + fy) * dy;
            mass[p] = m;
            type[p] = particleType[op];
            vx[p] = momentumX[op] / m;
            vy[p] = momentumY[op] / m;
            role[p] = fluidRole;
            ok = 1u;
        }
    }
    applied[op] = ok;
}

int cell_id_from_position_host_0459(double x, double y,
''', '''__global__ void apply_device_carrier_insertion_kernel_0455(
    int nOps,
    const unsigned int* particleIndex,
    const int* receiverCell,
    const std::uint32_t* particleType,
    const double* particleMass,
    const double* momentumX,
    const double* momentumY,
    std::uint32_t Nx,
    std::uint32_t Ny,
    double dx,
    double dy,
    std::uint64_t nParticles,
    std::uint8_t inactiveRole,
    std::uint8_t fluidRole,
    unsigned int invalidParticle,
    unsigned int* applied,
    double* x,
    double* y,
    double* vx,
    double* vy,
    double* mass,
    std::uint32_t* type,
    std::uint8_t* role) {
    const int op = blockIdx.x * blockDim.x + threadIdx.x;
    if (op >= nOps) return;
    const unsigned int p = particleIndex[op];
    unsigned int ok = 0u;
    if (p != invalidParticle && static_cast<std::uint64_t>(p) < nParticles && role[p] == inactiveRole) {
        const std::uint32_t c = static_cast<std::uint32_t>(receiverCell[op]);
        const std::uint32_t nCells = Nx * Ny;
        const double m = particleMass[op];
        if (c < nCells && m > 0.0) {
            const std::uint32_t ix = c % Nx;
            const std::uint32_t iy = c / Nx;
            const std::uint32_t q = static_cast<std::uint32_t>(op) & 15u;
            const double fx = 0.2 + 0.2 * static_cast<double>(q & 3u);
            const double fy = 0.2 + 0.2 * static_cast<double>(q >> 2u);
            x[p] = (static_cast<double>(ix) + fx) * dx;
            y[p] = (static_cast<double>(iy) + fy) * dy;
            mass[p] = m;
            type[p] = particleType[op];
            vx[p] = momentumX[op] / m;
            vy[p] = momentumY[op] / m;
            role[p] = fluidRole;
            ok = 1u;
        }
    }
    applied[op] = ok;
}

void apply_host_patchback_0473(ParticleState& state,
                               const GpuDeviceCarrier0455& dc,
                               const CellGrid& grid) {
    const std::size_t n = static_cast<std::size_t>(dc.gpuOps);
    if (dc.hostPatchParticle0473.size() < n || dc.hostPatchReceiver0473.size() < n ||
        dc.hostPatchType0473.size() < n || dc.hostPatchMass0473.size() < n ||
        dc.hostPatchPx0473.size() < n || dc.hostPatchPy0473.size() < n) {
        throw std::runtime_error("0473 host patchback missing compact operation payload");
    }
    const std::size_t np = static_cast<std::size_t>(state.Np);
    for (std::size_t op = 0; op < n; ++op) {
        const unsigned int p32 = dc.hostPatchParticle0473[op];
        const std::size_t p = static_cast<std::size_t>(p32);
        const int cSigned = dc.hostPatchReceiver0473[op];
        const double m = dc.hostPatchMass0473[op];
        if (p >= np || cSigned < 0 || !(m > 0.0)) {
            throw std::runtime_error("0473 host patchback invalid compact operation");
        }
        const std::uint32_t c = static_cast<std::uint32_t>(cSigned);
        const std::uint32_t nCells = static_cast<std::uint32_t>(grid.Nx * grid.Ny);
        if (c >= nCells) throw std::runtime_error("0473 host patchback invalid receiver cell");
        const std::uint32_t ix = c % static_cast<std::uint32_t>(grid.Nx);
        const std::uint32_t iy = c / static_cast<std::uint32_t>(grid.Nx);
        const std::uint32_t q = static_cast<std::uint32_t>(op) & 15u;
        const double fx = 0.2 + 0.2 * static_cast<double>(q & 3u);
        const double fy = 0.2 + 0.2 * static_cast<double>(q >> 2u);
        state.x[p] = (static_cast<double>(ix) + fx) * grid.dx;
        state.y[p] = (static_cast<double>(iy) + fy) * grid.dy;
        state.mass[p] = m;
        state.type[p] = dc.hostPatchType0473[op];
        state.vx[p] = dc.hostPatchPx0473[op] / m;
        state.vy[p] = dc.hostPatchPy0473[op] / m;
        if (!state.role.empty()) state.role[p] = static_cast<std::uint8_t>(ParticleRole::Fluid);
    }
}

int cell_id_from_position_host_0459(double x, double y,
''', '0473 host patchback function')

# Core copies compact op payload when patchback is requested and apply succeeded.
rep('''    out.invalidApplyOps = (static_cast<std::uint64_t>(nOps) - out.extractionApplied) +
                          (static_cast<std::uint64_t>(nOps) - out.insertionApplied);
    if (out.invalidApplyOps == 0u) {
        if (downloadState) {
            const auto dl0 = std::chrono::steady_clock::now();
            CudaParticleStateDiagnostics downloadDiag{};
            gpuState.download_all(state, &downloadDiag);
            out.stateDownloadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - dl0).count() + downloadDiag.downloadSeconds;
        } else {
            out.stateDownloadSeconds = 0.0;
        }
        out.pass = true;
    }
''', '''    out.invalidApplyOps = (static_cast<std::uint64_t>(nOps) - out.extractionApplied) +
                          (static_cast<std::uint64_t>(nOps) - out.insertionApplied);
    if (out.invalidApplyOps == 0u) {
        if (cuda_resampling_host_patchback_0473_requested()) {
            const auto patch0 = std::chrono::steady_clock::now();
            copy_device_prefix_to_host_0473(dOutParticle.ptr, nOps, out.hostPatchParticle0473);
            copy_device_prefix_to_host_0473(dOutReceiver.ptr, nOps, out.hostPatchReceiver0473);
            copy_device_prefix_to_host_0473(dOutType.ptr, nOps, out.hostPatchType0473);
            copy_device_prefix_to_host_0473(dOutMass.ptr, nOps, out.hostPatchMass0473);
            copy_device_prefix_to_host_0473(dOutPx.ptr, nOps, out.hostPatchPx0473);
            copy_device_prefix_to_host_0473(dOutPy.ptr, nOps, out.hostPatchPy0473);
            out.residentHostPatchback0473 = 1u;
            out.hostPatchbackOps0473 = static_cast<std::uint64_t>(nOps);
            out.hostPatchbackSeconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - patch0).count();
        }
        if (downloadState) {
            const auto dl0 = std::chrono::steady_clock::now();
            CudaParticleStateDiagnostics downloadDiag{};
            gpuState.download_all(state, &downloadDiag);
            out.stateDownloadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - dl0).count() + downloadDiag.downloadSeconds;
        } else {
            out.stateDownloadSeconds = 0.0;
        }
        out.pass = true;
    }
''', '0473 core patchback payload copy')

# Extend CSV header and row.
rep('''               "uploadSeconds,materializeKernelSeconds,cpuOpCarrier0458,donorSliceMaterializer0459,thrustCellListMaterializer0460,residentCore0467,residentExternal0467B,residentDeferredDownload0468,residentDirectCommit0471,residentSharedState0472,residentSharedUploadSkipped0472,residentActivePrefixDownload0472,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\\n";
''', '''               "uploadSeconds,materializeKernelSeconds,cpuOpCarrier0458,donorSliceMaterializer0459,thrustCellListMaterializer0460,residentCore0467,residentExternal0467B,residentDeferredDownload0468,residentDirectCommit0471,residentSharedState0472,residentSharedUploadSkipped0472,residentActivePrefixDownload0472,residentHostPatchback0473,hostPatchbackOps0473,sparseGate0461,fullGate0461,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,hostPatchbackSeconds,totalSeconds\\n";
''', '0473 device carrier CSV header')

rep('''        << d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.residentCore0467 << ',' << d.residentExternal0467B << ',' << d.residentDeferredDownload0468 << ',' << d.residentDirectCommit0471 << ',' << d.residentSharedState0472 << ',' << d.residentSharedUploadSkipped0472 << ',' << d.residentActivePrefixDownload0472 << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','
        << d.applyKernelSeconds << ',' << d.stateDownloadSeconds << ',' << d.totalSeconds << '\\n';
''', '''        << d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.residentCore0467 << ',' << d.residentExternal0467B << ',' << d.residentDeferredDownload0468 << ',' << d.residentDirectCommit0471 << ',' << d.residentSharedState0472 << ',' << d.residentSharedUploadSkipped0472 << ',' << d.residentActivePrefixDownload0472 << ',' << d.residentHostPatchback0473 << ',' << d.hostPatchbackOps0473 << ',' << d.sparseGate0461 << ',' << d.fullGate0461 << ',' << d.gateDownloadSeconds << ','
        << d.applyKernelSeconds << ',' << d.stateDownloadSeconds << ',' << d.hostPatchbackSeconds << ',' << d.totalSeconds << '\\n';
''', '0473 device carrier CSV row')

# Caller direct fast path: choose host patchback instead of active-prefix/full state download.
rep('''                const bool useSharedState0472 = cuda_resampling_shared_state_direct_commit_0472_requested();
                const bool activePrefixDownload0472 = cuda_resampling_active_prefix_download_0472_requested();
''', '''                const bool useSharedState0472 = cuda_resampling_shared_state_direct_commit_0472_requested();
                const bool activePrefixDownload0472 = cuda_resampling_active_prefix_download_0472_requested();
                const bool hostPatchback0473 = cuda_resampling_host_patchback_0473_requested();
''', '0473 caller flag')

rep('''                if (ok) {
                    const auto txDownload0 = std::chrono::steady_clock::now();
                    CudaParticleStateDiagnostics downloadDiag{};
                    if (activePrefixDownload0472) {
                        gpuStatePtr->download_active_prefix(state, &downloadDiag);
                    } else {
                        gpuStatePtr->download_all(state, &downloadDiag);
                    }
                    const double externalStateDownloadSeconds =
                        std::chrono::duration<double>(std::chrono::steady_clock::now() - txDownload0).count() + downloadDiag.downloadSeconds;
                    dc.stateDownloadSeconds += externalStateDownloadSeconds;
                    dc.totalSeconds += externalStateDownloadSeconds;
                    if (useSharedState0472) {
                        cuda_shared_particle_state_0251_mark_fresh("resampling_direct_commit_0472");
                    }
                } else if (useSharedState0472) {
                    cuda_shared_particle_state_0251_invalidate("resampling_direct_commit_0472_failed");
                }
''', '''                if (ok) {
                    if (hostPatchback0473 && dc.residentHostPatchback0473 != 0u) {
                        const auto txPatch0 = std::chrono::steady_clock::now();
                        apply_host_patchback_0473(state, dc, grid);
                        const double externalPatchbackSeconds =
                            std::chrono::duration<double>(std::chrono::steady_clock::now() - txPatch0).count();
                        dc.hostPatchbackSeconds += externalPatchbackSeconds;
                        dc.totalSeconds += externalPatchbackSeconds;
                    } else {
                        const auto txDownload0 = std::chrono::steady_clock::now();
                        CudaParticleStateDiagnostics downloadDiag{};
                        if (activePrefixDownload0472) {
                            gpuStatePtr->download_active_prefix(state, &downloadDiag);
                        } else {
                            gpuStatePtr->download_all(state, &downloadDiag);
                        }
                        const double externalStateDownloadSeconds =
                            std::chrono::duration<double>(std::chrono::steady_clock::now() - txDownload0).count() + downloadDiag.downloadSeconds;
                        dc.stateDownloadSeconds += externalStateDownloadSeconds;
                        dc.totalSeconds += externalStateDownloadSeconds;
                    }
                    if (useSharedState0472) {
                        cuda_shared_particle_state_0251_mark_fresh(hostPatchback0473 ? "resampling_host_patchback_0473" : "resampling_direct_commit_0472");
                    }
                } else if (useSharedState0472) {
                    cuda_shared_particle_state_0251_invalidate("resampling_direct_commit_0472_failed");
                }
''', '0473 caller host patchback commit')

src.write_text(text)
print('[0473] patched host patchback fast commit path')

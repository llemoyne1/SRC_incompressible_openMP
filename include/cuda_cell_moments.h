#pragma once

#include <cstdint>
#include <vector>

#include "cell_grid.h"
#include "cuda_particle_state.h"
#include "cuda_cell_workspace.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct CudaCellMomentsOptions {
    int threadsPerBlock = 256;

    // 0202: keep device allocations across calls. This is intended for the
    // active in-step path where particle counts and grid sizes remain stable
    // for many consecutive collision steps.
    bool reuseDeviceBuffers = false;

    // Active collision deposit only needs cellId/count/mass/px/py. Shadow
    // validation may keep velocities enabled for direct CPU/CUDA comparison.
    bool computeCellVelocities = true;
    bool downloadCellVelocities = true;

    // Conservative automatic fast paths. They are enabled by default because
    // they are guarded by exact host-side checks performed in the deposit call.
    bool enableAllFluidFastPath = true;
    bool enableUniformMassFastPath = true;
};

struct CudaCellMomentsDiagnostics {
    std::uint64_t particlesVisited = 0u;
    std::uint64_t fluidParticles = 0u;
    int numCells = 0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
    int reusedDeviceBuffers = 0;
    int allFluidFastPath = 0;
    int uniformMassFastPath = 0;
    int downloadedCellVelocities = 1;
};

struct CudaCellMoments {
    std::vector<int> cellId;
    std::vector<std::uint32_t> cellCount;
    std::vector<double> cellMass;
    std::vector<double> cellPx;
    std::vector<double> cellPy;
    std::vector<double> cellUx;
    std::vector<double> cellUy;
};

bool cuda_cell_moments_available();

void cuda_deposit_cell_moments_atomic(const ParticleState& state,
                                      const CellGrid& grid,
                                      const GridShift& shift,
                                      const SimulationParams& params,
                                      CudaCellMoments& out,
                                      CudaCellMomentsDiagnostics* diagnostics = nullptr,
                                      CudaCellMomentsOptions options = CudaCellMomentsOptions{});

// 0251: deposit directly from an already-current persistent CudaParticleState
// into a persistent CudaCellWorkspace. This skips the particle H2D upload in
// cuda_deposit_cell_moments_atomic(); only the cell arrays required by the
// still-CPU collision/Q6 stages are downloaded. The caller is responsible for
// proving that gpuState matches the current host ParticleState.
void cuda_deposit_cell_moments_atomic_from_persistent_state(
    const ParticleState& hostMirror,
    CudaParticleState& gpuState,
    CudaCellWorkspace& cellWorkspace,
    const CellGrid& grid,
    const GridShift& shift,
    const SimulationParams& params,
    CudaCellMoments& out,
    CudaCellMomentsDiagnostics* diagnostics = nullptr,
    CudaCellMomentsOptions options = CudaCellMomentsOptions{});

} // namespace mpcd

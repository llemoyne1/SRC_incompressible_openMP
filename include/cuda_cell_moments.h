#pragma once

#include <cstdint>
#include <vector>

#include "cell_grid.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct CudaCellMomentsOptions {
    int threadsPerBlock = 256;
};

struct CudaCellMomentsDiagnostics {
    std::uint64_t particlesVisited = 0u;
    std::uint64_t fluidParticles = 0u;
    int numCells = 0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
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

} // namespace mpcd

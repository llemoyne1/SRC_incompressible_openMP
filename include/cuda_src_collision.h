#pragma once

#include "particle_state.h"

#include <cstdint>
#include <vector>

namespace mpcd {

struct CudaSrcCollisionOptions {
    int threadsPerBlock = 256;
};

struct CudaSrcCollisionDiagnostics {
    std::uint64_t particlesVisited = 0u;
    std::uint64_t particlesRotated = 0u;
    std::uint64_t invalidCellParticles = 0u;
    int numCells = 0;

    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

bool cuda_src_collision_available();

CudaSrcCollisionDiagnostics cuda_apply_src_collision_from_cell_moments(
    ParticleState& state,
    int numCells,
    const std::vector<int>& cellId,
    const std::vector<double>& cellUx,
    const std::vector<double>& cellUy,
    const std::vector<double>& cosA,
    const std::vector<double>& sinA,
    CudaSrcCollisionOptions options = {});

} // namespace mpcd

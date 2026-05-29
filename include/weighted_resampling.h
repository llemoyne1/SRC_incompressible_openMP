#pragma once

#include <cstdint>
#include <vector>

#include "cell_grid.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

// Real-fluid weighted deposit used by the resampling branch.
//
// This deposit is deliberately distinct from CollisionWorkspace:
//   - it includes only true active particles with role=Fluid;
//   - it excludes wall virtual particles and immersed-solid virtual particles;
//   - it is intended for future resampling/pool/wet-dry decisions and for
//     diagnostics of the transported fluid mass.
struct WeightedRealFluidDepositWorkspace {
    std::uint64_t allocatedParticles = 0;
    int allocatedCells = 0;
    int allocatedThreads = 0;

    std::vector<int> cellId;

    std::vector<std::uint32_t> count;
    std::vector<double> mass;
    std::vector<double> px;
    std::vector<double> py;
    std::vector<double> ux;
    std::vector<double> uy;

    std::vector<std::uint32_t> localCount;
    std::vector<double> localMass;
    std::vector<double> localPx;
    std::vector<double> localPy;
};

struct WeightedResamplingDiagnostics {
    bool computed = false;

    std::uint64_t nFluid = 0;
    std::uint64_t nLatent = 0;
    std::uint64_t nInactive = 0;
    std::uint64_t nCells = 0;
    std::uint64_t nNonEmptyCells = 0;
    std::uint64_t nEmptyCells = 0;

    std::uint32_t minN = 0;
    std::uint32_t maxN = 0;
    double meanN = 0.0;
    double stdN = 0.0;

    double totalMass = 0.0;
    double totalPx = 0.0;
    double totalPy = 0.0;
    double meanMass = 0.0;
    double stdMass = 0.0;
    double minMass = 0.0;
    double maxMass = 0.0;

    double targetCellMass = 0.0;
    double mRelRms = 0.0;
    double mRelMaxAbs = 0.0;

    double meanUx = 0.0;
    double meanUy = 0.0;
    double cellUxRms = 0.0;
    double cellUyRms = 0.0;

    double particleMassMean = 0.0;
    double particleMassStd = 0.0;
    double particleMassRelStd = 0.0;
    double particleMassMin = 0.0;
    double particleMassMax = 0.0;
};

void resize_weighted_real_fluid_deposit(WeightedRealFluidDepositWorkspace& ws,
                                        std::uint64_t numParticles,
                                        int numCells,
                                        int numThreads);

WeightedResamplingDiagnostics deposit_weighted_real_fluid(const ParticleState& state,
                                                          const SimulationParams& params,
                                                          const CellGrid& grid,
                                                          const GridShift& shift,
                                                          WeightedRealFluidDepositWorkspace& ws);

} // namespace mpcd

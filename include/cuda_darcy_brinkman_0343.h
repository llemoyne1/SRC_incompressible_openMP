#pragma once

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>
#include <string>

namespace mpcd {

struct CudaDarcyBrinkman0343Diagnostics {
    bool requested = false;
    bool supported = false;
    bool handled = false;
    bool applied = false;
    std::uint64_t particles = 0u;
    std::uint64_t activeFluid = 0u;
    int numCells = 0;
    double mass = 0.0;
    double fluidVolumeFraction = 0.0;
    double meanChi = 0.0;
    double meanAlpha = 0.0;
    double darcyPower = 0.0;
    double darcyPowerPerMass = 0.0;
    double meanSpeedRms = 0.0;
    double solidLeakRms = 0.0;
    double darcyForceX = 0.0;
    double darcyForceY = 0.0;
    double dragProxy = 0.0;
    double liftProxy = 0.0;
    double resetSeconds = 0.0;
    double depositSeconds = 0.0;
    double diagnosticsSeconds = 0.0;
    double applySeconds = 0.0;
    double totalSeconds = 0.0;
    std::string csvPath;
};

#if defined(MPCD_ENABLE_CUDA_DARCY_BRINKMAN_0343) && defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
CudaDarcyBrinkman0343Diagnostics try_apply_cuda_darcy_brinkman_0343(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time);

bool cuda_darcy_brinkman_0343_device_chi_field(
    const SimulationParams& params,
    const float** deviceChi,
    int* nx,
    int* ny);
#else
inline CudaDarcyBrinkman0343Diagnostics try_apply_cuda_darcy_brinkman_0343(
    ParticleState&, const SimulationParams& params, const CellGrid&, const FluidDomainBounds&, std::uint64_t, double) {
    CudaDarcyBrinkman0343Diagnostics d{};
    d.requested = params.darcyBrinkmanEnable;
    return d;
}

inline bool cuda_darcy_brinkman_0343_device_chi_field(
    const SimulationParams&, const float** deviceChi, int* nx, int* ny) {
    if (deviceChi) *deviceChi = nullptr;
    if (nx) *nx = 0;
    if (ny) *ny = 0;
    return false;
}
#endif

} // namespace mpcd

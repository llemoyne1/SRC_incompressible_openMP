#pragma once

#include <cstdint>
#include <vector>

namespace mpcd {

struct CudaResamplingParticleSelectParams {
    std::uint8_t fluidRole = 0u;
    std::uint32_t invalidParticle = 0xffffffffu;
};

struct CudaResamplingParticleSelectDiagnostics {
    bool attempted = false;
    bool applied = false;
    std::uint64_t particles = 0;
    std::uint64_t cells = 0;
    std::uint64_t transfers = 0;
    std::uint64_t selectedTransfers = 0;
    std::uint64_t missingDonorParticleTransfers = 0;
    std::uint64_t donorCellsWithEligibleParticles = 0;
    double totalTransferMass = 0.0;
    double maxTransferMass = 0.0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

// CUDA donor-particle selection primitive for the resampling chantier.
//
// The function does not mutate particle arrays.  It answers the first question
// needed before extraction/insertion: for each planned transfer, is there at
// least one eligible fluid particle in the donor cell, and which deterministic
// representative would be selected by the same first-index rule on CPU/GPU?
//
// Inputs:
//   particleCell[i]     cell index of particle i
//   particleRole[i]     role of particle i; params.fluidRole is eligible
//   particleMass[i]     particle mass, returned for the selected representative
//   donorCell[t]        donor cell of transfer t
//   transferMass[t]     planned transfer mass of transfer t
//   nCells              number of cells in the deposit grid
//
// Outputs:
//   selectedParticle[t] deterministic first eligible particle in donorCell[t]
//                       or params.invalidParticle if none exists
//   selectedMass[t]     mass of selectedParticle[t], or zero if missing
//   eligibleCountByCell optional count of eligible donor particles per cell
bool cuda_resampling_select_donor_particles_0232(
    const std::vector<std::uint32_t>& particleCell,
    const std::vector<std::uint8_t>& particleRole,
    const std::vector<double>& particleMass,
    std::uint32_t nCells,
    const std::vector<std::uint32_t>& donorCell,
    const std::vector<double>& transferMass,
    const CudaResamplingParticleSelectParams& params,
    std::vector<std::uint32_t>& selectedParticle,
    std::vector<double>& selectedMass,
    std::vector<std::uint32_t>* eligibleCountByCell = nullptr,
    CudaResamplingParticleSelectDiagnostics* diagnostics = nullptr);

} // namespace mpcd

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


struct CudaResamplingShadowTransferParams {
    std::uint8_t fluidRole = 0u;
    std::uint8_t insertionRole = 1u;
    std::uint32_t invalidParticle = 0xffffffffu;
    double maxExtractFractionOfDonor = 0.50;
    double minDonorMassAfterExtract = 1.0e-12;
};

struct CudaResamplingShadowTransferDiagnostics {
    bool attempted = false;
    bool applied = false;
    std::uint64_t particles = 0;
    std::uint64_t transfers = 0;
    std::uint64_t appliedTransfers = 0;
    std::uint64_t skippedTransfers = 0;
    std::uint64_t invalidDonorTransfers = 0;
    std::uint64_t invalidInsertionTransfers = 0;
    std::uint64_t donorRoleMismatchTransfers = 0;
    std::uint64_t insertionRoleMismatchTransfers = 0;
    std::uint64_t duplicateDonorParticles = 0;
    std::uint64_t duplicateInsertionParticles = 0;
    double requestedTransferMass = 0.0;
    double actualTransferMass = 0.0;
    double totalMassBefore = 0.0;
    double totalMassAfter = 0.0;
    double totalPxBefore = 0.0;
    double totalPyBefore = 0.0;
    double totalPxAfter = 0.0;
    double totalPyAfter = 0.0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

// First mutating CUDA resampling primitive, deliberately scoped to a shadow/copy
// operation.  For every planned transfer, a selected donor particle p is split:
// a bounded mass dm is removed from p, and an already allocated insertion particle
// q is activated in the receiver cell with velocity copied from p.  This preserves
// global mass and momentum exactly up to floating-point roundoff when donor and
// insertion particles are unique.  The function mutates output copies only and is
// not yet the full production resampling algorithm.
bool cuda_resampling_apply_shadow_transfers_0233(
    const std::vector<std::uint32_t>& particleCell,
    const std::vector<std::uint8_t>& particleRole,
    const std::vector<double>& particleMass,
    const std::vector<double>& particleVx,
    const std::vector<double>& particleVy,
    const std::vector<std::uint32_t>& receiverCell,
    const std::vector<double>& requestedTransferMass,
    const std::vector<std::uint32_t>& selectedDonorParticle,
    const std::vector<std::uint32_t>& insertionParticle,
    const CudaResamplingShadowTransferParams& params,
    std::vector<std::uint32_t>& outParticleCell,
    std::vector<std::uint8_t>& outParticleRole,
    std::vector<double>& outParticleMass,
    std::vector<double>& outParticleVx,
    std::vector<double>& outParticleVy,
    std::vector<double>* actualTransferMass = nullptr,
    CudaResamplingShadowTransferDiagnostics* diagnostics = nullptr);




struct CudaResamplingExtractionApplyParams {
    std::uint8_t fluidRole = 1u;
    std::uint8_t inactiveRole = 0u;
    std::uint32_t invalidParticle = 0xffffffffu;
};

struct CudaResamplingExtractionApplyDiagnostics {
    bool attempted = false;
    bool applied = false;
    std::uint64_t particles = 0;
    std::uint64_t operations = 0;
    std::uint64_t operationsApplied = 0;
    std::uint64_t invalidOperations = 0;
    double extractedMass = 0.0;
    double extractedMomentumX = 0.0;
    double extractedMomentumY = 0.0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

// Active CUDA extraction primitive for the resampling chantier.
//
// The host still builds and validates the extraction operation list, including
// duplicate filtering and particle-pool bookkeeping.  This primitive applies the
// device-side role transition Fluid -> Inactive for those prevalidated particle
// indices, then downloads the updated role array so the current CPU-authoritative
// ParticleState remains coherent.  This is an intermediate step before the same
// mutation is performed directly on CudaParticleState.
bool cuda_resampling_apply_extraction_operations_0237(
    std::vector<std::uint8_t>& role,
    const std::vector<std::uint32_t>& particleIndex,
    const std::vector<double>& particleMass,
    const std::vector<double>& momentumX,
    const std::vector<double>& momentumY,
    const CudaResamplingExtractionApplyParams& params,
    CudaResamplingExtractionApplyDiagnostics* diagnostics = nullptr);

struct CudaResamplingInsertionApplyParams {
    std::uint8_t inactiveRole = 0u;
    std::uint8_t fluidRole = 1u;
    std::uint32_t invalidParticle = 0xffffffffu;
};

struct CudaResamplingInsertionApplyDiagnostics {
    bool attempted = false;
    bool applied = false;
    std::uint64_t particles = 0;
    std::uint64_t operations = 0;
    std::uint64_t operationsApplied = 0;
    std::uint64_t invalidOperations = 0;
    double insertedMass = 0.0;
    double insertedMomentumX = 0.0;
    double insertedMomentumY = 0.0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

// Active CUDA insertion primitive for the resampling chantier.
//
// This function applies the same net state update as the CPU extraction+insertion
// pair after extraction has marked selected particles inactive and pushed them
// into the free pool: the same storage slot is reactivated in its receiver cell
// with deterministic in-cell coordinates, prescribed mass/type and prescribed
// momentum.  Pool bookkeeping and diagnostics remain host-side.
bool cuda_resampling_apply_insertion_operations_0236(
    std::vector<double>& x,
    std::vector<double>& y,
    std::vector<double>& vx,
    std::vector<double>& vy,
    std::vector<double>& mass,
    std::vector<std::uint32_t>& type,
    std::vector<std::uint8_t>& role,
    const std::vector<std::uint32_t>& particleIndex,
    const std::vector<std::uint32_t>& receiverCell,
    const std::vector<std::uint32_t>& particleType,
    const std::vector<double>& particleMass,
    const std::vector<double>& momentumX,
    const std::vector<double>& momentumY,
    const std::vector<std::uint32_t>& insertionOrdinal,
    std::uint32_t Nx,
    std::uint32_t Ny,
    double dx,
    double dy,
    const CudaResamplingInsertionApplyParams& params,
    CudaResamplingInsertionApplyDiagnostics* diagnostics = nullptr);

} // namespace mpcd

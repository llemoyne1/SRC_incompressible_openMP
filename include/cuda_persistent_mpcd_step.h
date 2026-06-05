#pragma once

#include "particle_state.h"

#include <cstdint>
#include <vector>

namespace mpcd {

struct CudaPersistentMpcdStepConfig {
    int Nx = 0;
    int Ny = 0;
    double Lx = 1.0;
    double Ly = 1.0;
    // Optional collision-grid shift, matching GridShift in the CPU collision path.
    double shiftX = 0.0;
    double shiftY = 0.0;
    // Absolute SRC/MPCD step used for random rotation signs.
    std::uint64_t step = 0u;
    double rotationAngle = 2.0943951023931954923; // 120 degrees
    int randomRotationSign = 1;
    std::uint64_t rngSeed = 1u;
    double targetKBT = 1.0e-3;
    int thermostatMinParticles = 2;
    double thermostatEpsilon = 1.0e-30;
    int cycles = 1;
    int threadsPerBlock = 256;
};

struct CudaPersistentMpcdStepDiagnostics {
    std::uint64_t particlesVisited = 0u;
    std::uint64_t fluidParticles = 0u;
    std::uint64_t particlesRotated = 0u;
    std::uint64_t invalidCellParticles = 0u;
    int numCells = 0;
    int cycles = 0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

bool cuda_persistent_mpcd_step_available();

// 0212 persistent-particle prototype for the periodic Taylor--Green subset.
// The particle arrays are uploaded once, then deposit -> SRC rotation ->
// cell-relative thermostat are run for config.cycles without intermediate
// host transfers. Only final vx/vy are downloaded back to state.
CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_thermostat(
    ParticleState& state,
    const CudaPersistentMpcdStepConfig& config);

// 0213 active-collision entry point for the real SRC/MPCD step.
// It uploads particles once, performs deposit -> cell velocity finalization -> SRC rotation
// on the GPU, downloads vx/vy plus the real-particle cellId/count/mass/mean-velocity
// arrays, and leaves the CPU thermostat/Q6/resampling stages unchanged. The caller is responsible for
// restricting this to the currently supported periodic, no-wallVP/no-solid subset.
CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision(
    ParticleState& state,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config);

} // namespace mpcd

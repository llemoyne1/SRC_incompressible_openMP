#pragma once

#include <cstdint>
#include <vector>

#include "particle_state.h"
#include "thermostat.h"

namespace mpcd {

class CudaParticleState;
class CudaCellWorkspace;

struct CudaCellThermostatOptions {
    int threadsPerBlock = 256;
};

struct CudaCellThermostatDiagnostics {
    bool applied = false;
    std::uint64_t particlesVisited = 0u;
    std::uint64_t fluidParticles = 0u;
    int numCells = 0;

    std::uint64_t cellsRescaled = 0u;
    std::uint64_t particlesRescaled = 0u;
    double kBTBefore = 0.0;
    double kBTAfter = 0.0;
    double scaleMean = 1.0;
    double scaleMin = 1.0;
    double scaleMax = 1.0;

    double uploadSeconds = 0.0;
    double kineticKernelSeconds = 0.0;
    double scaleKernelSeconds = 0.0;
    double applyKernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;

    // 0258 persistent active thermostat path: these are included in upload/total
    // seconds by the caller, but are kept separately when available.
    double particleStateUploadSeconds = 0.0;
    double cellWorkspaceAllocateSeconds = 0.0;
};

bool cuda_cell_thermostat_available();

// 0205 standalone CUDA thermostat primitive. The cell moments are intentionally
// passed in from the already validated particle->cell deposit path so this
// function validates only the cell-relative rescale stage. It modifies state.vx
// and state.vy in-place and mirrors ThermostatDiagnostics semantics.
ThermostatDiagnostics cuda_apply_cell_relative_rescale_thermostat_from_moments(
    ParticleState& state,
    int numCells,
    const std::vector<int>& cellId,
    const std::vector<std::uint32_t>& cellCount,
    const std::vector<double>& cellUx,
    const std::vector<double>& cellUy,
    double targetKBT,
    int minParticles,
    double epsilon,
    CudaCellThermostatDiagnostics* cudaDiag = nullptr,
    CudaCellThermostatOptions options = CudaCellThermostatOptions{});

// 0258 persistent active thermostat primitive. The particle arrays are already
// owned by a CudaParticleState and the cell scratch arrays are reused from a
// CudaCellWorkspace. The caller is still responsible for uploading current
// host velocities after any CPU Q6/capacity kick and for providing current CPU
// cell moments. This function uploads only the per-particle cellId and per-cell
// thermostat inputs, applies the cell-relative rescale on device, downloads
// vx/vy and thermostat diagnostic scratch, and mirrors ThermostatDiagnostics
// semantics.
ThermostatDiagnostics cuda_apply_cell_relative_rescale_thermostat_from_shared_state_0258(
    CudaParticleState& gpuState,
    CudaCellWorkspace& cellWorkspace,
    ParticleState& downloadTarget,
    int numCells,
    const std::vector<int>& cellId,
    const std::vector<std::uint32_t>& cellCount,
    const std::vector<double>& cellUx,
    const std::vector<double>& cellUy,
    double targetKBT,
    int minParticles,
    double epsilon,
    CudaCellThermostatDiagnostics* cudaDiag = nullptr,
    CudaCellThermostatOptions options = CudaCellThermostatOptions{});

} // namespace mpcd

#pragma once

#include "particle_state.h"
#include "thermostat.h"
#include "cuda_particle_state.h"
#include "cuda_cell_workspace.h"

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
    // 0253: bounded wall-simple collision support.  The historical
    // persistent collision path assumed periodic indexing in both
    // directions.  These flags let the same backend reproduce the CPU
    // bounded cell-indexing and deterministic virtual-wall momentum
    // contribution for the Poiseuille wall-simple subset.
    int periodicX = 1;
    int periodicY = 1;
    double domainXMin = 0.0;
    double domainXMax = 1.0;
    double domainYMin = 0.0;
    double domainYMax = 1.0;
    int wallLeftEnabled = 0;
    int wallRightEnabled = 0;
    int wallBottomEnabled = 0;
    int wallTopEnabled = 0;
    double wallAccommodation = 0.0;
    double wallGamma = 0.0;
    double wallVpMass = 1.0;
    double wallUxLeft = 0.0;
    double wallUyLeft = 0.0;
    double wallUxRight = 0.0;
    double wallUyRight = 0.0;
    double wallUxBottom = 0.0;
    double wallUyBottom = 0.0;
    double wallUxTop = 0.0;
    double wallUyTop = 0.0;

    // 0254: deterministic immersed-rectangle virtual-wall contribution for
    // the SRC collision. This mirrors the CPU collision's
    // immersed_solid_fraction_in_cell() term for the static rectangle subset
    // used by open_rect_obstacle_full. Thermal noise, moving solids and
    // circular/rotating solids remain CPU-only until dedicated validation.
    int immersedRectangleEnabled = 0;
    int immersedFractionSamples = 4;
    double immersedXMin = 0.0;
    double immersedXMax = 0.0;
    double immersedYMin = 0.0;
    double immersedYMax = 0.0;
    double immersedWallUx = 0.0;
    double immersedWallUy = 0.0;

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

    // 0215: optional persistent collision+thermostat substep diagnostics.
    // These are populated only when the persistent path applies the
    // cell-relative thermostat on GPU after SRC rotation.
    std::uint64_t thermostatCellsRescaled = 0u;
    std::uint64_t thermostatParticlesRescaled = 0u;
    double thermostatKBTBefore = 0.0;
    double thermostatKBTAfter = 0.0;
    double thermostatScaleMean = 1.0;
    double thermostatScaleMin = 1.0;
    double thermostatScaleMax = 1.0;
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

// 0226 shared-state collision-only overload. Particle arrays are already resident
// in CudaParticleState. This is the algorithmically correct bridge for
// collision -> Q6 -> CPU thermostat, because it does not apply the thermostat
// before Q6.
CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision(
    CudaParticleState& gpuState,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config);

// 0226 shared particle+cell collision-only overload. It reuses both the
// persistent particle arrays and the persistent cell workspace, while still
// restoring the CPU workspace so downstream diagnostics/Q6/resampling remain
// unchanged.
CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision(
    CudaParticleState& gpuState,
    CudaCellWorkspace& cellWorkspace,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config);

// 0215 active persistent substep: deposit -> SRC collision -> cell-relative
// thermostat on the GPU, with a single final download of vx/vy and CPU
// workspace cell moments. This entry point is deliberately for subsets where
// no CPU velocity operator is interposed between collision and thermostat
// (for example projectionEnable=false).
CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision_thermostat(
    ParticleState& state,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    ThermostatDiagnostics* thermostatDiagOut = nullptr);


// 0219 shared-state overload: the particle arrays are already resident in a
// CudaParticleState. This avoids re-uploading x/y/vx/vy/mass/role for each
// persistent CUDA substep. The function still downloads final vx/vy and CPU
// workspace cell moments so the current host-side step can continue unchanged.
CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision_thermostat(
    CudaParticleState& gpuState,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    ThermostatDiagnostics* thermostatDiagOut = nullptr);

// 0224 shared particle+cell workspace overload. Particle arrays are resident in
// CudaParticleState and cell/moment scratch arrays are resident in
// CudaCellWorkspace. This removes the remaining per-call cell-buffer
// allocations from the persistent deposit -> SRC collision -> thermostat path.
CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision_thermostat(
    CudaParticleState& gpuState,
    CudaCellWorkspace& cellWorkspace,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    ThermostatDiagnostics* thermostatDiagOut = nullptr);

// When the 0215 persistent collision+thermostat path has already applied the
// thermostat inside src_collision_step(), the later thermostat phase consumes
// the stored diagnostics and returns without applying a second thermostat.
void cuda_persistent_record_consumed_thermostat(std::uint64_t step, const ThermostatDiagnostics& diag);
bool cuda_persistent_take_consumed_thermostat(std::uint64_t step, ThermostatDiagnostics& diag);

} // namespace mpcd

#pragma once

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>
#include <string>
#include <vector>

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

    // 0493x15a: canonical chi-solid momentum exchange diagnostics.
    // Sign convention: *FluidImpulse is the momentum increment applied to the
    // real fluid.  *SolidReactionImpulse is the opposite reaction on the
    // chi-solid.  The deterministic term is the exact finite-dt Brinkman
    // mean-kick; the stochastic term is the exact particle-wise bath impulse.
    // Collision/chiVP exchange is intentionally not folded in yet; when chiVP
    // is enabled chiSolidImpulseComplete remains false until that contribution
    // is instrumented by the following qualification step.
    std::uint64_t chiGeometryVersion = 0u;
    bool chiSolidImpulseDiagnostic = false;
    bool chiSolidImpulseComplete = false;
    double chiSolidDeterministicFluidImpulseX = 0.0;
    double chiSolidDeterministicFluidImpulseY = 0.0;
    double chiSolidStochasticFluidImpulseX = 0.0;
    double chiSolidStochasticFluidImpulseY = 0.0;
    double chiSolidFluidImpulseX = 0.0;
    double chiSolidFluidImpulseY = 0.0;
    double chiSolidReactionImpulseX = 0.0;
    double chiSolidReactionImpulseY = 0.0;
    double chiSolidReactionForceX = 0.0;
    double chiSolidReactionForceY = 0.0;

    // 0493x16b: exact deterministic+bath fluid impulse resolved on the physical
    // cell grid. This is populated only for dynamic chi-solid coupling; the
    // solid module consumes its opposite as an Eulerian reaction field.
    std::vector<double> chiSolidCellFluidImpulseX0493x16b;
    std::vector<double> chiSolidCellFluidImpulseY0493x16b;

    // 0493x16c: post-coupling fictitious-domain fluid inventory. The solid
    // fraction weight is (1-chi) on the physical grid. These are diagnostics
    // only: no particle role, momentum, or solid dynamics is modified.
    bool fictitiousFluidDiagnostic0493x16c = false;
    double fictitiousFluidMass0493x16c = 0.0;
    double fictitiousFluidMomentumX0493x16c = 0.0;
    double fictitiousFluidMomentumY0493x16c = 0.0;
    double fictitiousLockedMomentumX0493x16c = 0.0;
    double fictitiousLockedMomentumY0493x16c = 0.0;
    double fictitiousRelativeMomentumX0493x16c = 0.0;
    double fictitiousRelativeMomentumY0493x16c = 0.0;
    double fictitiousRelativeVelocityRms0493x16c = 0.0;

    // 0493x16g diagnostic ablation: after the historical outward bath has
    // acted on particles in cells newly swallowed by the moving binary mask,
    // remove only that captured population's collective x bath velocity shift
    // along the slab translation DOF. The per-particle bath fluctuations and
    // transverse bath component are retained. Static/no-shift steps
    // have zero captured mass and are bitwise on the historical path.
    bool captureBathMeanNeutralization0493x16g = false;
    double captureBathMass0493x16g = 0.0;
    double captureBathRawFluidImpulseX0493x16g = 0.0;
    double captureBathRawFluidImpulseY0493x16g = 0.0;
    double captureBathCorrectionFluidImpulseX0493x16g = 0.0;
    double captureBathCorrectionFluidImpulseY0493x16g = 0.0;
    double captureBathResidualFluidImpulseX0493x16g = 0.0;
    double captureBathResidualFluidImpulseY0493x16g = 0.0;

    // 0493x16h diagnostic ablation: particles found in cells newly swallowed
    // by the moving historical binary mask are remapped locally across the
    // outward binary cell face before the outward bath. Position only is
    // changed; particle momentum is untouched by the remap. This gate is
    // dedicated to the common-translation test and is not a production law.
    bool captureSpatialReinjection0493x16h = false;
    double captureCellParticles0493x16h = 0.0;
    double captureReinjectedParticles0493x16h = 0.0;
    double captureReinjectedMass0493x16h = 0.0;
    double captureReinjectedAbsDxSum0493x16h = 0.0;

    // 0493x16i prescribed-deformable impermeable exclusion comparison.
    // mode=1: binary cell-transition remap; mode=2: continuous swept-geometry
    // remap using the analytical moving/deforming interface. The historical
    // Darcy chi/alpha operator remains binary and unchanged in both modes.
    bool deformableExclusion0493x16i = false;
    int deformableExclusionMode0493x16i = 0;
    double exclusionCandidateParticles0493x16i = 0.0;
    double exclusionReinjectedParticles0493x16i = 0.0;
    double exclusionReinjectedMass0493x16i = 0.0;
    double exclusionReinjectedAbsDxSum0493x16i = 0.0;

    double dragProxy = 0.0;
    double liftProxy = 0.0;
    double resetSeconds = 0.0;
    double depositSeconds = 0.0;
    double diagnosticsSeconds = 0.0;
    double applySeconds = 0.0;
    double totalSeconds = 0.0;
    int speciesQ6Enable = 0;
    int q6ResidentInputFresh = 0;
    int particleUploadSkipped = 0;
    // 0493x7g: true when Darcy is the deterministic pre-transport source
    // immediately upstream of the Q6-g-f projection.  This is an audit bit,
    // not a new runtime control.
    int q6GfPrestream = 0;
    std::string csvPath;
};

#if defined(MPCD_ENABLE_CUDA_DARCY_BRINKMAN_0343) && defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
CudaDarcyBrinkman0343Diagnostics try_apply_cuda_darcy_brinkman_0343(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time,
    bool q6GfPrestream0493x7g = false);

bool cuda_darcy_brinkman_0343_device_chi_field(
    const SimulationParams& params,
    const float** deviceChi,
    int* nx,
    int* ny);

// 0493x16a: publish solver-generated dynamic solid fields. This is the
// generic coupling boundary between a SolidGeometry provider and the CUDA
// fluid operators. The arrays are cell-centered, row-major, Nx*Ny.
bool cuda_darcy_brinkman_0343_upload_external_solid_fields(
    const float* hostChi,
    const float* hostUSolidX,
    const float* hostUSolidY,
    int nx,
    int ny,
    std::uint64_t geometryVersion);

// 0493x16e: reserve/publish the same coupling fields without a host upload.
// A CUDA SolidGeometry rasterizer writes directly into these device arrays.
bool cuda_darcy_brinkman_0343_resident_solid_field_storage_0493x16e(
    int nx, int ny, std::uint64_t geometryVersion,
    float** deviceChi, float** deviceUSolidX, float** deviceUSolidY);

// Exact Darcy+bath cell impulse remains resident for device-side solid load
// projection. The returned pointers are valid until the next Darcy call.
bool cuda_darcy_brinkman_0343_device_cell_fluid_impulse_0493x16e(
    const double** deviceImpulseX, const double** deviceImpulseY, int* nx, int* ny);

bool cuda_darcy_brinkman_0343_device_solid_velocity_fields(
    const SimulationParams& params,
    const float** deviceUSolidX,
    const float** deviceUSolidY,
    int* nx,
    int* ny);

// 0493x15a architecture hook: chi is a solver geometry state, not merely a
// startup parameter.  A future membrane/topology controller can update the
// backing chi source then invalidate derived alpha/lambda/normal fields without
// changing the physical Darcy operator.  The current x15a runner keeps chi
// fixed and therefore never calls this function.
void cuda_darcy_brinkman_0343_mark_chi_dirty();
std::uint64_t cuda_darcy_brinkman_0343_chi_geometry_version();
#else
inline CudaDarcyBrinkman0343Diagnostics try_apply_cuda_darcy_brinkman_0343(
    ParticleState&, const SimulationParams& params, const CellGrid&, const FluidDomainBounds&, std::uint64_t, double, bool q6GfPrestream0493x7g = false) {
    CudaDarcyBrinkman0343Diagnostics d{};
    d.requested = params.darcyBrinkmanEnable;
    d.q6GfPrestream = q6GfPrestream0493x7g ? 1 : 0;
    return d;
}

inline bool cuda_darcy_brinkman_0343_device_chi_field(
    const SimulationParams&, const float** deviceChi, int* nx, int* ny) {
    if (deviceChi) *deviceChi = nullptr;
    if (nx) *nx = 0;
    if (ny) *ny = 0;
    return false;
}
inline bool cuda_darcy_brinkman_0343_upload_external_solid_fields(
    const float*, const float*, const float*, int, int, std::uint64_t) { return false; }
inline bool cuda_darcy_brinkman_0343_resident_solid_field_storage_0493x16e(
    int, int, std::uint64_t, float** chi, float** ux, float** uy) {
    if (chi) *chi = nullptr; if (ux) *ux = nullptr; if (uy) *uy = nullptr;
    return false;
}
inline bool cuda_darcy_brinkman_0343_device_cell_fluid_impulse_0493x16e(
    const double** x, const double** y, int* nx, int* ny) {
    if (x) *x = nullptr; if (y) *y = nullptr;
    if (nx) *nx = 0; if (ny) *ny = 0;
    return false;
}
inline bool cuda_darcy_brinkman_0343_device_solid_velocity_fields(
    const SimulationParams&, const float** ux, const float** uy, int* nx, int* ny) {
    if (ux) *ux = nullptr;
    if (uy) *uy = nullptr;
    if (nx) *nx = 0;
    if (ny) *ny = 0;
    return false;
}
inline void cuda_darcy_brinkman_0343_mark_chi_dirty() {}
inline std::uint64_t cuda_darcy_brinkman_0343_chi_geometry_version() { return 0u; }
#endif

} // namespace mpcd

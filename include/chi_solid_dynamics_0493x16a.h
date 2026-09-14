#pragma once

#include <cstdint>
#include <memory>
#include <vector>

namespace mpcd {

struct CellGrid;
struct SimulationParams;

// 0493x16a: solver-facing diagnostics for a dynamic chi-solid model.
// The solver only sees geometry/velocity fields plus exchanged impulse; the
// constitutive/mechanical state remains owned by the solid module.
struct ChiSolidDynamicsDiagnostics0493x16a {
    bool enabled = false;
    bool prepared = false;
    bool advanced = false;
    std::uint64_t geometryVersion = 0u;
    double centerXBefore = 0.0;
    double centerXAfter = 0.0;
    double velocityXBefore = 0.0;
    double velocityXAfter = 0.0;
    double mass = 0.0;
    double brinkmanFluidImpulseX = 0.0;
    double brinkmanFluidImpulseY = 0.0;
    double bathFluidImpulseX = 0.0;
    double bathFluidImpulseY = 0.0;
    double chiVpFluidImpulseX = 0.0;
    double chiVpFluidImpulseY = 0.0;
    double chiKineticFluidImpulseX0493x16j = 0.0;
    double chiKineticFluidImpulseY0493x16j = 0.0;
    double totalFluidImpulseX = 0.0;
    double totalFluidImpulseY = 0.0;
    double solidReactionImpulseX = 0.0;
    double solidReactionImpulseY = 0.0;
    double solidMomentumBeforeX = 0.0;
    double solidMomentumAfterX = 0.0;
    double actionReactionResidualX = 0.0;
    double actionReactionResidualY = 0.0;

    // 0493x16b: spatial Eulerian load contract diagnostics. The cell field is
    // the exact opposite of Darcy/bath/chiVP fluid impulse, resolved on the
    // physical grid before SolidGeometry projects it onto generalized DOFs.
    bool spatialLoadAvailable0493x16b = false;
    double cellReactionSumX0493x16b = 0.0;
    double cellReactionSumY0493x16b = 0.0;
    double cellLoadClosureResidualX0493x16b = 0.0;
    double cellLoadClosureResidualY0493x16b = 0.0;
    double primaryProjectionResidual0493x16b = 0.0;

    // 0493x16c: quantify the numerical fluid retained in the fictitious solid
    // domain. This is diagnostic only; no inertial correction is applied yet.
    bool fictitiousFluidDiagnostic0493x16c = false;
    double fictitiousFluidMass0493x16c = 0.0;
    double fictitiousFluidMomentumX0493x16c = 0.0;
    double fictitiousFluidMomentumY0493x16c = 0.0;
    double fictitiousLockedMomentumX0493x16c = 0.0;
    double fictitiousLockedMomentumY0493x16c = 0.0;
    double fictitiousRelativeMomentumX0493x16c = 0.0;
    double fictitiousRelativeMomentumY0493x16c = 0.0;
    double fictitiousRelativeVelocityRms0493x16c = 0.0;

    // 0493x16e infrastructure: the rigid-slab model can remain fully CUDA-resident.
    // x16f keeps that residency but restores the historical sharp cell-center chi;
    // the spatial load and q/qdot remain on device. Only scalar qualification
    // diagnostics are copied to the host.
    bool cudaResidentSolid0493x16e = false;
    bool subcellRaster0493x16e = false;
    double sampledSolidVolume0493x16e = 0.0;
    double expectedSolidVolume0493x16e = 0.0;
    double sampledSolidVolumeRelativeError0493x16e = 0.0;
    std::uint64_t hostGeometryFieldUploadBytes0493x16e = 0u;
    std::uint64_t hostLoadFieldDownloadBytes0493x16e = 0u;

    // 0493x16f: historical binary chi is kept unchanged. The only physics
    // experiment is a post-stream drift of the solid geometry before the
    // collision/Darcy consumers, followed by a kick-only solid update.
    bool historicalBinaryMask0493x16f = false;
    bool poststreamTemporalSync0493x16f = false;
    double poststreamDriftX0493x16f = 0.0;

    // 0493x16i prescribed deformable-wall comparison. The geometric solid
    // fraction is diagnostic/exclusion geometry only and never reinterprets
    // the historical Darcy porosity field.
    bool prescribedDeformable0493x16i = false;
    double deformAmplitude0493x16i = 0.0;
    double deformOmega0493x16i = 0.0;
    double positiveSolidFractionChange0493x16i = 0.0;
    double negativeSolidFractionChange0493x16i = 0.0;
    double maxAbsSolidFractionChange0493x16i = 0.0;
};

struct ChiSolidDynamicsWorkspace0493x16a {
    ChiSolidDynamicsWorkspace0493x16a();
    ~ChiSolidDynamicsWorkspace0493x16a();
    ChiSolidDynamicsWorkspace0493x16a(ChiSolidDynamicsWorkspace0493x16a&&) noexcept;
    ChiSolidDynamicsWorkspace0493x16a& operator=(ChiSolidDynamicsWorkspace0493x16a&&) noexcept;
    ChiSolidDynamicsWorkspace0493x16a(const ChiSolidDynamicsWorkspace0493x16a&) = delete;
    ChiSolidDynamicsWorkspace0493x16a& operator=(const ChiSolidDynamicsWorkspace0493x16a&) = delete;

    struct Impl;
    std::unique_ptr<Impl> impl;
};

// Prepare chi(x,t) and u_s(x,t) for the current solid state and publish them to
// the CUDA chi/Darcy coupling backend. No fluid or solid momentum is changed.
ChiSolidDynamicsDiagnostics0493x16a prepare_chi_solid_dynamics_0493x16a(
    ChiSolidDynamicsWorkspace0493x16a& workspace,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    double time);

// 0493x16f: after particle streaming/boundary handling and before SRC
// collision/Darcy, drift the resident solid with its pre-kick velocity and
// republish the historical binary chi/u_s fields at the same time level as
// the streamed particles. No momentum is changed by this operation.
ChiSolidDynamicsDiagnostics0493x16a synchronize_chi_solid_dynamics_poststream_0493x16f(
    ChiSolidDynamicsWorkspace0493x16a& workspace,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    double time);

// Apply exact opposite reaction of the already measured fluid impulse, advance
// the solid model, and write the x16a diagnostic row. In the resident x16f
// path the positional drift was already done post-stream, so this is kick-only.
ChiSolidDynamicsDiagnostics0493x16a advance_chi_solid_dynamics_0493x16a(
    ChiSolidDynamicsWorkspace0493x16a& workspace,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    double time,
    double brinkmanFluidImpulseX,
    double brinkmanFluidImpulseY,
    double bathFluidImpulseX,
    double bathFluidImpulseY,
    double chiVpFluidImpulseX,
    double chiVpFluidImpulseY,
    const std::vector<double>& darcyCellFluidImpulseX0493x16b,
    const std::vector<double>& darcyCellFluidImpulseY0493x16b,
    const std::vector<double>& chiVpCellFluidImpulseX0493x16b,
    const std::vector<double>& chiVpCellFluidImpulseY0493x16b,
    bool fictitiousFluidDiagnostic0493x16c,
    double fictitiousFluidMass0493x16c,
    double fictitiousFluidMomentumX0493x16c,
    double fictitiousFluidMomentumY0493x16c,
    double fictitiousLockedMomentumX0493x16c,
    double fictitiousLockedMomentumY0493x16c,
    double fictitiousRelativeMomentumX0493x16c,
    double fictitiousRelativeMomentumY0493x16c,
    double fictitiousRelativeVelocityRms0493x16c);

} // namespace mpcd

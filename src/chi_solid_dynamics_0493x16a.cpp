#include "chi_solid_dynamics_0493x16a.h"

#include "cell_grid.h"
#include "cuda_darcy_brinkman_0343.h"
#include "cuda_persistent_mpcd_step.h"
#include "cuda_q6_resident_0400.h"
#include "simulation_params.h"
#include "solid_model_0493x16a.h"

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <stdexcept>
#include <string>
#include <utility>

namespace mpcd {
namespace {

std::string diagnostic_path_0493x16a(const SimulationParams& params) {
    return (std::filesystem::path(params.outputDir) / "chi_solid_dynamics_0493x16a.csv").string();
}

void append_diagnostic_0493x16a(const SimulationParams& params,
                                std::uint64_t step,
                                double time,
                                const char* model,
                                const ChiSolidDynamicsDiagnostics0493x16a& d) {
    if (params.outputDir.empty()) return;
    std::filesystem::create_directories(params.outputDir);
    const std::string path = diagnostic_path_0493x16a(params);
    const bool exists = std::filesystem::exists(path);
    std::ofstream out(path, std::ios::app);
    if (!out) throw std::runtime_error("0493x16a cannot open solid dynamics diagnostics: " + path);
    out << std::setprecision(17);
    if (!exists) {
        out << "step,time,model,geometryVersion,centerXBefore,centerXAfter,velocityXBefore,velocityXAfter,mass,"
               "brinkmanFluidImpulseX,brinkmanFluidImpulseY,bathFluidImpulseX,bathFluidImpulseY,chiVpFluidImpulseX,chiVpFluidImpulseY,"
               "chiKineticFluidImpulseX0493x16j,chiKineticFluidImpulseY0493x16j,"
               "totalFluidImpulseX,totalFluidImpulseY,solidReactionImpulseX,solidReactionImpulseY,"
               "solidMomentumBeforeX,solidMomentumAfterX,actionReactionResidualX,actionReactionResidualY,"
               "spatialLoadAvailable0493x16b,cellReactionSumX0493x16b,cellReactionSumY0493x16b,"
               "cellLoadClosureResidualX0493x16b,cellLoadClosureResidualY0493x16b,primaryProjectionResidual0493x16b,"
               "fictitiousFluidDiagnostic0493x16c,fictitiousFluidMass0493x16c,"
               "fictitiousFluidMomentumX0493x16c,fictitiousFluidMomentumY0493x16c,"
               "fictitiousLockedMomentumX0493x16c,fictitiousLockedMomentumY0493x16c,"
               "fictitiousRelativeMomentumX0493x16c,fictitiousRelativeMomentumY0493x16c,"
               "fictitiousRelativeVelocityRms0493x16c,"
               "cudaResidentSolid0493x16e,subcellRaster0493x16e,"
               "sampledSolidVolume0493x16e,expectedSolidVolume0493x16e,sampledSolidVolumeRelativeError0493x16e,"
               "hostGeometryFieldUploadBytes0493x16e,hostLoadFieldDownloadBytes0493x16e,"
               "historicalBinaryMask0493x16f,poststreamTemporalSync0493x16f,poststreamDriftX0493x16f,"
               "prescribedDeformable0493x16i,deformAmplitude0493x16i,deformOmega0493x16i,"
               "positiveSolidFractionChange0493x16i,negativeSolidFractionChange0493x16i,maxAbsSolidFractionChange0493x16i\n";
    }
    out << step << ',' << time << ',' << model << ',' << d.geometryVersion << ','
        << d.centerXBefore << ',' << d.centerXAfter << ','
        << d.velocityXBefore << ',' << d.velocityXAfter << ',' << d.mass << ','
        << d.brinkmanFluidImpulseX << ',' << d.brinkmanFluidImpulseY << ','
        << d.bathFluidImpulseX << ',' << d.bathFluidImpulseY << ','
        << d.chiVpFluidImpulseX << ',' << d.chiVpFluidImpulseY << ','
        << d.chiKineticFluidImpulseX0493x16j << ',' << d.chiKineticFluidImpulseY0493x16j << ','
        << d.totalFluidImpulseX << ',' << d.totalFluidImpulseY << ','
        << d.solidReactionImpulseX << ',' << d.solidReactionImpulseY << ','
        << d.solidMomentumBeforeX << ',' << d.solidMomentumAfterX << ','
        << d.actionReactionResidualX << ',' << d.actionReactionResidualY << ','
        << (d.spatialLoadAvailable0493x16b ? 1 : 0) << ','
        << d.cellReactionSumX0493x16b << ',' << d.cellReactionSumY0493x16b << ','
        << d.cellLoadClosureResidualX0493x16b << ',' << d.cellLoadClosureResidualY0493x16b << ','
        << d.primaryProjectionResidual0493x16b << ','
        << (d.fictitiousFluidDiagnostic0493x16c ? 1 : 0) << ','
        << d.fictitiousFluidMass0493x16c << ','
        << d.fictitiousFluidMomentumX0493x16c << ',' << d.fictitiousFluidMomentumY0493x16c << ','
        << d.fictitiousLockedMomentumX0493x16c << ',' << d.fictitiousLockedMomentumY0493x16c << ','
        << d.fictitiousRelativeMomentumX0493x16c << ',' << d.fictitiousRelativeMomentumY0493x16c << ','
        << d.fictitiousRelativeVelocityRms0493x16c << ','
        << (d.cudaResidentSolid0493x16e ? 1 : 0) << ','
        << (d.subcellRaster0493x16e ? 1 : 0) << ','
        << d.sampledSolidVolume0493x16e << ',' << d.expectedSolidVolume0493x16e << ','
        << d.sampledSolidVolumeRelativeError0493x16e << ','
        << d.hostGeometryFieldUploadBytes0493x16e << ','
        << d.hostLoadFieldDownloadBytes0493x16e << ','
        << (d.historicalBinaryMask0493x16f ? 1 : 0) << ','
        << (d.poststreamTemporalSync0493x16f ? 1 : 0) << ','
        << d.poststreamDriftX0493x16f << ','
        << (d.prescribedDeformable0493x16i ? 1 : 0) << ','
        << d.deformAmplitude0493x16i << ',' << d.deformOmega0493x16i << ','
        << d.positiveSolidFractionChange0493x16i << ','
        << d.negativeSolidFractionChange0493x16i << ','
        << d.maxAbsSolidFractionChange0493x16i << '\n';
}

void append_state_result_0493x18d(const SimulationParams& params,
                                  std::uint64_t step,
                                  double time,
                                  const char* model,
                                  const ChiSolidDynamicsDiagnostics0493x16a& d) {
    if (params.outputDir.empty()) return;
    const int every = std::max(1, params.summaryEvery);
    if (!(step == 0u || ((step + 1u) % static_cast<std::uint64_t>(every)) == 0u)) return;
    std::filesystem::create_directories(params.outputDir);
    const std::filesystem::path path =
        std::filesystem::path(params.outputDir) / "chi_solid_state_0493x18d.csv";
    const bool exists = std::filesystem::exists(path);
    std::ofstream out(path, std::ios::app);
    if (!out) throw std::runtime_error("0493x18d cannot open solid state result CSV");
    out << std::setprecision(17);
    if (!exists) {
        out << "step,time,model,geometryVersion,centerX,velocityX,mass,"
               "solidMomentumX,reactionImpulseX,reactionImpulseY\n";
    }
    out << step << ',' << time << ',' << model << ',' << d.geometryVersion << ','
        << d.centerXAfter << ',' << d.velocityXAfter << ',' << d.mass << ','
        << d.solidMomentumAfterX << ',' << d.solidReactionImpulseX << ','
        << d.solidReactionImpulseY << '\n';
}

void copy_common_fluid_diagnostics_0493x16e(
    ChiSolidDynamicsDiagnostics0493x16a& d,
    double brinkmanFluidImpulseX,
    double brinkmanFluidImpulseY,
    double bathFluidImpulseX,
    double bathFluidImpulseY,
    double chiVpFluidImpulseX,
    double chiVpFluidImpulseY,
    bool fictitiousFluidDiagnostic0493x16c,
    double fictitiousFluidMass0493x16c,
    double fictitiousFluidMomentumX0493x16c,
    double fictitiousFluidMomentumY0493x16c,
    double fictitiousLockedMomentumX0493x16c,
    double fictitiousLockedMomentumY0493x16c,
    double fictitiousRelativeMomentumX0493x16c,
    double fictitiousRelativeMomentumY0493x16c,
    double fictitiousRelativeVelocityRms0493x16c) {
    d.brinkmanFluidImpulseX = brinkmanFluidImpulseX;
    d.brinkmanFluidImpulseY = brinkmanFluidImpulseY;
    d.bathFluidImpulseX = bathFluidImpulseX;
    d.bathFluidImpulseY = bathFluidImpulseY;
    d.chiVpFluidImpulseX = chiVpFluidImpulseX;
    d.chiVpFluidImpulseY = chiVpFluidImpulseY;
    d.totalFluidImpulseX = brinkmanFluidImpulseX + bathFluidImpulseX + chiVpFluidImpulseX;
    d.totalFluidImpulseY = brinkmanFluidImpulseY + bathFluidImpulseY + chiVpFluidImpulseY;
    d.fictitiousFluidDiagnostic0493x16c = fictitiousFluidDiagnostic0493x16c;
    d.fictitiousFluidMass0493x16c = fictitiousFluidMass0493x16c;
    d.fictitiousFluidMomentumX0493x16c = fictitiousFluidMomentumX0493x16c;
    d.fictitiousFluidMomentumY0493x16c = fictitiousFluidMomentumY0493x16c;
    d.fictitiousLockedMomentumX0493x16c = fictitiousLockedMomentumX0493x16c;
    d.fictitiousLockedMomentumY0493x16c = fictitiousLockedMomentumY0493x16c;
    d.fictitiousRelativeMomentumX0493x16c = fictitiousRelativeMomentumX0493x16c;
    d.fictitiousRelativeMomentumY0493x16c = fictitiousRelativeMomentumY0493x16c;
    d.fictitiousRelativeVelocityRms0493x16c = fictitiousRelativeVelocityRms0493x16c;
}

} // namespace

struct ChiSolidDynamicsWorkspace0493x16a::Impl {
    bool initialized = false;
    bool cudaResident0493x16e = false;
    std::string modelName;
    std::uint64_t geometryVersion = 0u;
    SolidModelBundle0493x16a model;
    SolidCouplingFields0493x16a fields;
    std::vector<double> cellSolidReactionImpulseX0493x16b;
    std::vector<double> cellSolidReactionImpulseY0493x16b;
    SolidCudaDiagnostics0493x16e residentPrepareDiag0493x16e;
    SolidCudaDiagnostics0493x16e residentPoststreamDiag0493x16f;
};

ChiSolidDynamicsWorkspace0493x16a::ChiSolidDynamicsWorkspace0493x16a()
    : impl(std::make_unique<Impl>()) {}
ChiSolidDynamicsWorkspace0493x16a::~ChiSolidDynamicsWorkspace0493x16a() = default;
ChiSolidDynamicsWorkspace0493x16a::ChiSolidDynamicsWorkspace0493x16a(ChiSolidDynamicsWorkspace0493x16a&&) noexcept = default;
ChiSolidDynamicsWorkspace0493x16a& ChiSolidDynamicsWorkspace0493x16a::operator=(ChiSolidDynamicsWorkspace0493x16a&&) noexcept = default;

ChiSolidDynamicsDiagnostics0493x16a prepare_chi_solid_dynamics_0493x16a(
    ChiSolidDynamicsWorkspace0493x16a& workspace,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t,
    double) {
    ChiSolidDynamicsDiagnostics0493x16a d{};
    d.enabled = params.chiSolidDynamicsEnable;
    if (!params.chiSolidDynamicsEnable) return d;
    auto& w = *workspace.impl;

    if (!w.initialized) {
        if (params.chiSolidModel == "membrane_2d" ||
            params.chiSolidModel == "hinged_plate_2d") {
            // x17c/x18a: the persistent x17 Lagrangian contour is the geometry
            // authority. Do not instantiate/rasterize the legacy Eulerian solid
            // provider: q6 initializes the closed nodal loop from initial chi.
            w.modelName = params.chiSolidModel;
            w.cudaResident0493x16e = false;
            w.initialized = true;
        } else {
            w.model = make_solid_model_0493x16a(params);
            const bool hostComplete = w.model.dynamics && w.model.geometry;
            const bool residentComplete =
                w.model.resident0493x16e && w.model.resident0493x16e->available();
            if (!hostComplete && !residentComplete) {
                throw std::runtime_error("0493x16a solid model factory returned no usable host or resident backend");
            }
            w.cudaResident0493x16e = residentComplete;
            w.modelName = residentComplete
                ? w.model.resident0493x16e->model_name()
                : w.model.dynamics->model_name();
            w.initialized = true;
        }
    }

    ++w.geometryVersion;
    if (w.geometryVersion == 0u) w.geometryVersion = 1u;
    w.residentPoststreamDiag0493x16f = SolidCudaDiagnostics0493x16e{};

    if (params.chiSolidModel == "membrane_2d" ||
        params.chiSolidModel == "hinged_plate_2d") {
        d.prepared = true;
        d.geometryVersion = w.geometryVersion;
        d.velocityXBefore = params.darcyUSolidX;
        d.velocityXAfter = params.darcyUSolidX;
        d.mass = params.chiSolidMass;
        d.solidMomentumBeforeX = d.mass * d.velocityXBefore;
        d.solidMomentumAfterX = d.solidMomentumBeforeX;
        // Geometry is intentionally not republished through x16e. The initial
        // Darcy chi remains available for one-time contour extraction, after
        // which x17c Lagrangian nodes are authoritative.
        return d;
    }

    if (w.cudaResident0493x16e) {
        float* dChi = nullptr;
        float* dUSolidX = nullptr;
        float* dUSolidY = nullptr;
        if (!cuda_darcy_brinkman_0343_resident_solid_field_storage_0493x16e(
                grid.Nx, grid.Ny, w.geometryVersion, &dChi, &dUSolidX, &dUSolidY)) {
            throw std::runtime_error("0493x16e failed to reserve resident chi/u_s fields");
        }
        SolidCudaCouplingFields0493x16e fields{};
        fields.chi = dChi;
        fields.uSolidX = dUSolidX;
        fields.uSolidY = dUSolidY;
        fields.nx = grid.Nx;
        fields.ny = grid.Ny;
        SolidCudaDiagnostics0493x16e rd{};
        w.model.resident0493x16e->prepare_device_fields(
            params, grid, w.geometryVersion, fields, rd);
        w.residentPrepareDiag0493x16e = rd;
        d.prepared = true;
        d.geometryVersion = w.geometryVersion;
        d.centerXBefore = rd.centerXBefore;
        d.centerXAfter = rd.centerXBefore;
        d.velocityXBefore = rd.velocityXBefore;
        d.velocityXAfter = rd.velocityXBefore;
        d.mass = rd.mass;
        d.solidMomentumBeforeX = d.mass * d.velocityXBefore;
        d.solidMomentumAfterX = d.solidMomentumBeforeX;
        d.cudaResidentSolid0493x16e = true;
        d.subcellRaster0493x16e = rd.rasterized;
        d.historicalBinaryMask0493x16f = rd.binaryHistorical0493x16f;
        d.poststreamTemporalSync0493x16f = false;
        d.poststreamDriftX0493x16f = 0.0;
        d.prescribedDeformable0493x16i = rd.prescribedDeformable0493x16i;
        d.deformAmplitude0493x16i = rd.deformAmplitude0493x16i;
        d.deformOmega0493x16i = rd.deformOmega0493x16i;
        d.positiveSolidFractionChange0493x16i = rd.positiveSolidFractionChange0493x16i;
        d.negativeSolidFractionChange0493x16i = rd.negativeSolidFractionChange0493x16i;
        d.maxAbsSolidFractionChange0493x16i = rd.maxAbsSolidFractionChange0493x16i;
        d.sampledSolidVolume0493x16e = rd.sampledSolidVolume;
        d.expectedSolidVolume0493x16e = rd.expectedSolidVolume;
        d.sampledSolidVolumeRelativeError0493x16e = rd.sampledSolidVolumeRelativeError;
        d.hostGeometryFieldUploadBytes0493x16e = rd.hostGeometryFieldUploadBytes;
        d.hostLoadFieldDownloadBytes0493x16e = rd.hostLoadFieldDownloadBytes;
        return d;
    }

    // Pre-x16e / non-CUDA fallback: retain the generic host geometry contract.
    w.model.geometry->build_fields(*w.model.dynamics, params, grid, w.fields);
    if (w.fields.nx != grid.Nx || w.fields.ny != grid.Ny ||
        w.fields.chi.size() != static_cast<std::size_t>(grid.Nx * grid.Ny) ||
        w.fields.signedDistance.size() != w.fields.chi.size() ||
        w.fields.uSolidX.size() != w.fields.chi.size() ||
        w.fields.uSolidY.size() != w.fields.chi.size()) {
        throw std::runtime_error("0493x16a SolidGeometry returned inconsistent coupling-field dimensions");
    }
    if (!cuda_darcy_brinkman_0343_upload_external_solid_fields(
            w.fields.chi.data(), w.fields.uSolidX.data(), w.fields.uSolidY.data(),
            grid.Nx, grid.Ny, w.geometryVersion)) {
        throw std::runtime_error("0493x16a failed to publish dynamic chi/u_s fields to CUDA Darcy backend");
    }
    d.prepared = true;
    d.geometryVersion = w.geometryVersion;
    const auto& q = w.model.dynamics->generalized_coordinates();
    const auto& qdot = w.model.dynamics->generalized_velocities();
    if (q.empty() || qdot.empty()) {
        throw std::runtime_error("0493x16a dynamic solid exposes no primary diagnostic DOF");
    }
    d.centerXBefore = q[0];
    d.centerXAfter = d.centerXBefore;
    d.velocityXBefore = qdot[0];
    d.velocityXAfter = d.velocityXBefore;
    d.mass = w.model.dynamics->mass_diagnostic();
    d.solidMomentumBeforeX = d.mass * d.velocityXBefore;
    d.solidMomentumAfterX = d.solidMomentumBeforeX;
    return d;
}

ChiSolidDynamicsDiagnostics0493x16a synchronize_chi_solid_dynamics_poststream_0493x16f(
    ChiSolidDynamicsWorkspace0493x16a& workspace,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t,
    double) {
    ChiSolidDynamicsDiagnostics0493x16a d{};
    d.enabled = params.chiSolidDynamicsEnable;
    if (!params.chiSolidDynamicsEnable) return d;
    auto& w = *workspace.impl;
    if (!w.initialized) {
        throw std::runtime_error("0493x16f poststream solid synchronization before prepare");
    }
    if (params.chiSolidModel == "membrane_2d" ||
        params.chiSolidModel == "hinged_plate_2d") {
        // x17c/x18a drift is performed directly on the persistent nodal geometry in
        // the pre-stream kinetic pass. No Eulerian chi/u_s synchronization is
        // required (or allowed) after streaming.
        d.prepared = true;
        d.geometryVersion = w.geometryVersion;
        d.mass = params.chiSolidMass;
        return d;
    }
    if (!w.cudaResident0493x16e || !w.model.resident0493x16e) {
        // x16f is deliberately a CUDA-resident timing experiment. Keep the
        // pre-x16e host fallback untouched rather than silently changing its
        // integration scheme.
        return d;
    }

    float* dChi = nullptr;
    float* dUSolidX = nullptr;
    float* dUSolidY = nullptr;
    // Re-publishing the resident storage clears Darcy derived-field signatures
    // even though geometryVersion remains one-per-step. This is essential when
    // a prestream consumer has already built fields from q^n.
    if (!cuda_darcy_brinkman_0343_resident_solid_field_storage_0493x16e(
            grid.Nx, grid.Ny, w.geometryVersion, &dChi, &dUSolidX, &dUSolidY)) {
        throw std::runtime_error("0493x16f failed to reserve poststream resident chi/u_s fields");
    }
    SolidCudaCouplingFields0493x16e fields{};
    fields.chi = dChi;
    fields.uSolidX = dUSolidX;
    fields.uSolidY = dUSolidY;
    fields.nx = grid.Nx;
    fields.ny = grid.Ny;
    SolidCudaDiagnostics0493x16e rd{};
    w.model.resident0493x16e->synchronize_poststream_device_fields(
        params, grid, w.geometryVersion, fields, rd);
    w.residentPoststreamDiag0493x16f = rd;

    d.prepared = true;
    d.geometryVersion = w.geometryVersion;
    d.centerXBefore = rd.centerXBefore;
    d.centerXAfter = rd.centerXAfter;
    d.velocityXBefore = rd.velocityXBefore;
    d.velocityXAfter = rd.velocityXAfter;
    d.mass = rd.mass;
    d.solidMomentumBeforeX = d.mass * d.velocityXBefore;
    d.solidMomentumAfterX = d.solidMomentumBeforeX;
    d.cudaResidentSolid0493x16e = true;
    d.subcellRaster0493x16e = rd.rasterized;
    d.sampledSolidVolume0493x16e = rd.sampledSolidVolume;
    d.expectedSolidVolume0493x16e = rd.expectedSolidVolume;
    d.sampledSolidVolumeRelativeError0493x16e = rd.sampledSolidVolumeRelativeError;
    d.hostGeometryFieldUploadBytes0493x16e = rd.hostGeometryFieldUploadBytes;
    d.hostLoadFieldDownloadBytes0493x16e = rd.hostLoadFieldDownloadBytes;
    d.historicalBinaryMask0493x16f = rd.binaryHistorical0493x16f;
    d.poststreamTemporalSync0493x16f = rd.temporalSync0493x16f;
    d.poststreamDriftX0493x16f = rd.poststreamDriftX0493x16f;
    d.prescribedDeformable0493x16i = rd.prescribedDeformable0493x16i;
    d.deformAmplitude0493x16i = rd.deformAmplitude0493x16i;
    d.deformOmega0493x16i = rd.deformOmega0493x16i;
    d.positiveSolidFractionChange0493x16i = rd.positiveSolidFractionChange0493x16i;
    d.negativeSolidFractionChange0493x16i = rd.negativeSolidFractionChange0493x16i;
    d.maxAbsSolidFractionChange0493x16i = rd.maxAbsSolidFractionChange0493x16i;
    return d;
}

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
    double fictitiousRelativeVelocityRms0493x16c) {
    ChiSolidDynamicsDiagnostics0493x16a d{};
    d.enabled = params.chiSolidDynamicsEnable;
    if (!params.chiSolidDynamicsEnable) return d;
    auto& w = *workspace.impl;
    if (!w.initialized) {
        throw std::runtime_error("0493x16a solid advance before prepare");
    }
    d.prepared = true;
    d.geometryVersion = w.geometryVersion;
    const bool qualification0493x18d = params.chiSolidQualificationDiagnosticsEnable;
    copy_common_fluid_diagnostics_0493x16e(
        d,
        brinkmanFluidImpulseX, brinkmanFluidImpulseY,
        bathFluidImpulseX, bathFluidImpulseY,
        chiVpFluidImpulseX, chiVpFluidImpulseY,
        fictitiousFluidDiagnostic0493x16c,
        fictitiousFluidMass0493x16c,
        fictitiousFluidMomentumX0493x16c,
        fictitiousFluidMomentumY0493x16c,
        fictitiousLockedMomentumX0493x16c,
        fictitiousLockedMomentumY0493x16c,
        fictitiousRelativeMomentumX0493x16c,
        fictitiousRelativeMomentumY0493x16c,
        fictitiousRelativeVelocityRms0493x16c);

    if (params.chiSolidModel == "hinged_plate_2d") {
        CudaChiHingedPlateDiagnostics0493x18a hd{};
        if (!cuda_q6_advance_chi_hinged_plate_0493x18a(
                params, grid, static_cast<int>(step), time, &hd) ||
            !hd.available || !hd.advanced) {
            throw std::runtime_error("0493x18a failed to advance hinged plate mechanics");
        }

        if (!qualification0493x18d) {
            d.centerXBefore = hd.centerX;
            d.centerXAfter = hd.centerX;
            d.velocityXBefore = hd.mass > 0.0 ? hd.momentumBeforeX / hd.mass : 0.0;
            d.velocityXAfter = hd.mass > 0.0 ? hd.momentumAfterX / hd.mass : 0.0;
            d.mass = hd.mass;
            d.solidMomentumBeforeX = hd.momentumBeforeX;
            d.solidMomentumAfterX = hd.momentumAfterX;
            d.solidReactionImpulseX = hd.nodeReactionImpulseX;
            d.solidReactionImpulseY = hd.nodeReactionImpulseY;
            d.advanced = true;
            return d;
        }

        const double legacyAbs =
            std::abs(d.totalFluidImpulseX) + std::abs(d.totalFluidImpulseY);
        const double reactionScale = 1.0 +
            std::abs(hd.nodeReactionImpulseX) + std::abs(hd.nodeReactionImpulseY);
        if (legacyAbs > 1.0e-11 * reactionScale) {
            throw std::runtime_error(
                "0493x18a hinged_plate_2d received non-kinetic Darcy/bath/chiVP impulse; kinetic-only coupling is required");
        }

        d.centerXBefore = hd.centerX;
        d.centerXAfter = hd.centerX;
        d.velocityXBefore = hd.momentumBeforeX / hd.mass;
        d.velocityXAfter = hd.momentumAfterX / hd.mass;
        d.mass = hd.mass;
        d.solidMomentumBeforeX = hd.momentumBeforeX;
        d.solidMomentumAfterX = hd.momentumAfterX;
        d.chiKineticFluidImpulseX0493x16j = -hd.nodeReactionImpulseX;
        d.chiKineticFluidImpulseY0493x16j = -hd.nodeReactionImpulseY;
        d.totalFluidImpulseX += d.chiKineticFluidImpulseX0493x16j;
        d.totalFluidImpulseY += d.chiKineticFluidImpulseY0493x16j;
        d.solidReactionImpulseX = hd.nodeReactionImpulseX;
        d.solidReactionImpulseY = hd.nodeReactionImpulseY;
        d.spatialLoadAvailable0493x16b = true;
        d.cellReactionSumX0493x16b = hd.cellReactionImpulseX;
        d.cellReactionSumY0493x16b = hd.cellReactionImpulseY;
        d.cellLoadClosureResidualX0493x16b =
            d.cellReactionSumX0493x16b + d.totalFluidImpulseX;
        d.cellLoadClosureResidualY0493x16b =
            d.cellReactionSumY0493x16b + d.totalFluidImpulseY;
        d.primaryProjectionResidual0493x16b = std::max(
            std::abs(hd.loadProjectionResidualX), std::abs(hd.loadProjectionResidualY));
        d.actionReactionResidualX =
            (hd.momentumAfterX-hd.momentumBeforeX) + d.totalFluidImpulseX
            - hd.hingeReactionImpulseX;
        d.actionReactionResidualY =
            (hd.momentumAfterY-hd.momentumBeforeY) + d.totalFluidImpulseY
            - hd.hingeReactionImpulseY - hd.gravityImpulseY;
        d.cudaResidentSolid0493x16e = false;
        d.subcellRaster0493x16e = false;
        d.poststreamTemporalSync0493x16f = false;
        d.poststreamDriftX0493x16f = 0.0;
        d.advanced = true;
        append_diagnostic_0493x16a(params, step, time, w.modelName.c_str(), d);
        return d;
    }

    if (params.chiSolidModel == "membrane_2d") {
        CudaChiMembraneDiagnostics0493x17c md{};
        if (!cuda_q6_advance_chi_membrane_0493x17c(
                params, grid, static_cast<int>(step), time, &md) ||
            !md.available || !md.advanced) {
            throw std::runtime_error("0493x17c failed to advance resident Lagrangian membrane mechanics");
        }

        if (!qualification0493x18d) {
            d.mass = md.mass;
            d.advanced = true;
            return d;
        }

        // The first membrane qualification is deliberately kinetic-only.  Keep
        // the old Darcy/bath/chiVP channels visible as diagnostics and fail if
        // they unexpectedly contribute instead of silently double-coupling.
        const double legacyAbs =
            std::abs(d.totalFluidImpulseX) + std::abs(d.totalFluidImpulseY);
        const double reactionScale = 1.0 +
            std::abs(md.nodeReactionImpulseX) + std::abs(md.nodeReactionImpulseY);
        if (legacyAbs > 1.0e-11 * reactionScale) {
            throw std::runtime_error(
                "0493x17c membrane_2d received non-kinetic Darcy/bath/chiVP impulse; first qualification requires kinetic-only coupling");
        }

        d.centerXBefore = md.centerX - params.dt * md.meanVelocityXBefore;
        d.centerXAfter = md.centerX;
        d.velocityXBefore = md.meanVelocityXBefore;
        d.velocityXAfter = md.meanVelocityXAfter;
        d.mass = md.mass;
        d.solidMomentumBeforeX = md.momentumBeforeX;
        d.solidMomentumAfterX = md.momentumAfterX;
        d.chiKineticFluidImpulseX0493x16j = -md.nodeReactionImpulseX;
        d.chiKineticFluidImpulseY0493x16j = -md.nodeReactionImpulseY;
        d.totalFluidImpulseX += d.chiKineticFluidImpulseX0493x16j;
        d.totalFluidImpulseY += d.chiKineticFluidImpulseY0493x16j;
        d.solidReactionImpulseX = md.nodeReactionImpulseX;
        d.solidReactionImpulseY = md.nodeReactionImpulseY;
        d.spatialLoadAvailable0493x16b = true;
        d.cellReactionSumX0493x16b = md.cellReactionImpulseX;
        d.cellReactionSumY0493x16b = md.cellReactionImpulseY;
        d.cellLoadClosureResidualX0493x16b =
            d.cellReactionSumX0493x16b + d.totalFluidImpulseX;
        d.cellLoadClosureResidualY0493x16b =
            d.cellReactionSumY0493x16b + d.totalFluidImpulseY;
        d.primaryProjectionResidual0493x16b = std::max(
            std::abs(md.loadProjectionResidualX), std::abs(md.loadProjectionResidualY));
        // x17d: for pinned membrane nodes the external support carries an
        // explicit constraint impulse.  Closed fluid+free-solid momentum is
        // recovered when that external impulse is removed from the balance.
        d.actionReactionResidualX =
            (md.momentumAfterX - md.momentumBeforeX) + d.totalFluidImpulseX
            - md.supportConstraintImpulseX;
        d.actionReactionResidualY =
            (md.momentumAfterY - md.momentumBeforeY) + d.totalFluidImpulseY
            - md.supportConstraintImpulseY;
        // x17c is CUDA-resident, but it deliberately bypasses the x16e
        // Eulerian solid rasterizer; keep the legacy x16e/x16f flags truthful.
        d.cudaResidentSolid0493x16e = false;
        d.subcellRaster0493x16e = false;
        d.poststreamTemporalSync0493x16f = false;
        d.poststreamDriftX0493x16f = 0.0;
        d.advanced = true;
        append_diagnostic_0493x16a(params, step, time, w.modelName.c_str(), d);
        return d;
    }

    if (w.cudaResident0493x16e) {
        const double* dDarcyX = nullptr;
        const double* dDarcyY = nullptr;
        int darcyNx = 0, darcyNy = 0;
        if (!cuda_darcy_brinkman_0343_device_cell_fluid_impulse_0493x16e(
                &dDarcyX, &dDarcyY, &darcyNx, &darcyNy) ||
            darcyNx != grid.Nx || darcyNy != grid.Ny) {
            throw std::runtime_error("0493x16e missing resident Darcy/bath cell impulse field");
        }

        const double* dChiVpX = nullptr;
        const double* dChiVpY = nullptr;
        int chiVpCells = 0;
        const bool haveChiVp = cuda_persistent_mpcd_step_chi_vp_cell_impulse_device_0493x16e(
            &dChiVpX, &dChiVpY, &chiVpCells);
        if (params.darcyChiCollisionVpEnable &&
            (!haveChiVp || chiVpCells != grid.Nx * grid.Ny)) {
            throw std::runtime_error("0493x16e missing resident chiVP cell impulse field");
        }
        if (!params.darcyChiCollisionVpEnable) {
            dChiVpX = nullptr;
            dChiVpY = nullptr;
        }

        const double* dChiKineticReactionX0493x16j = nullptr;
        const double* dChiKineticReactionY0493x16j = nullptr;
        int chiKineticNx0493x16j = 0, chiKineticNy0493x16j = 0;
        if ((params.chiKineticBoundaryMode == "specular" || params.chiKineticBoundaryMode == "bounceback")) {
            if (!cuda_q6_chi_kinetic_wall_reaction_device_0493x16j(
                    &dChiKineticReactionX0493x16j, &dChiKineticReactionY0493x16j,
                    &chiKineticNx0493x16j, &chiKineticNy0493x16j) ||
                chiKineticNx0493x16j != grid.Nx || chiKineticNy0493x16j != grid.Ny) {
                throw std::runtime_error("0493x16j missing resident chi kinetic wall-reaction field");
            }
        }

        SolidCudaFluidLoad0493x16e load{};
        load.darcyFluidImpulseX = dDarcyX;
        load.darcyFluidImpulseY = dDarcyY;
        load.chiVpFluidImpulseX = dChiVpX;
        load.chiVpFluidImpulseY = dChiVpY;
        load.chiKineticWallReactionImpulseX0493x16j = dChiKineticReactionX0493x16j;
        load.chiKineticWallReactionImpulseY0493x16j = dChiKineticReactionY0493x16j;
        load.nx = grid.Nx;
        load.ny = grid.Ny;
        SolidCudaDiagnostics0493x16e rd{};
        w.model.resident0493x16e->project_load_and_advance(params, grid, load, rd);

        d.centerXBefore = rd.centerXBefore;
        d.centerXAfter = rd.centerXAfter;
        d.velocityXBefore = rd.velocityXBefore;
        d.velocityXAfter = rd.velocityXAfter;
        d.mass = rd.mass;
        d.solidMomentumBeforeX = d.mass * d.velocityXBefore;
        d.solidMomentumAfterX = d.mass * d.velocityXAfter;
        d.spatialLoadAvailable0493x16b = true;
        d.cellReactionSumX0493x16b = rd.cellReactionSumX;
        d.cellReactionSumY0493x16b = rd.cellReactionSumY;
        if ((params.chiKineticBoundaryMode == "specular" || params.chiKineticBoundaryMode == "bounceback")) {
            // rd.cellReactionSum is the exact total reaction on the solid.
            // Existing D+B+VP values are fluid impulses, so recover the kinetic
            // fluid impulse by exact action/reaction without another device reduction.
            d.chiKineticFluidImpulseX0493x16j =
                -(d.cellReactionSumX0493x16b + d.totalFluidImpulseX);
            d.chiKineticFluidImpulseY0493x16j =
                -(d.cellReactionSumY0493x16b + d.totalFluidImpulseY);
            d.totalFluidImpulseX += d.chiKineticFluidImpulseX0493x16j;
            d.totalFluidImpulseY += d.chiKineticFluidImpulseY0493x16j;
        }
        d.cellLoadClosureResidualX0493x16b = d.cellReactionSumX0493x16b + d.totalFluidImpulseX;
        d.cellLoadClosureResidualY0493x16b = d.cellReactionSumY0493x16b + d.totalFluidImpulseY;
        d.primaryProjectionResidual0493x16b = rd.primaryProjectionResidual;
        d.solidReactionImpulseX = rd.generalizedImpulseX;
        d.solidReactionImpulseY = rd.cellReactionSumY;
        d.actionReactionResidualX =
            (d.solidMomentumAfterX - d.solidMomentumBeforeX) + d.totalFluidImpulseX;
        d.actionReactionResidualY = d.solidReactionImpulseY + d.totalFluidImpulseY;
        d.cudaResidentSolid0493x16e = true;
        d.subcellRaster0493x16e = false;
        d.historicalBinaryMask0493x16f = rd.binaryHistorical0493x16f &&
            w.residentPoststreamDiag0493x16f.binaryHistorical0493x16f;
        d.poststreamTemporalSync0493x16f =
            w.residentPoststreamDiag0493x16f.temporalSync0493x16f;
        d.poststreamDriftX0493x16f =
            w.residentPoststreamDiag0493x16f.poststreamDriftX0493x16f;
        d.prescribedDeformable0493x16i =
            w.residentPoststreamDiag0493x16f.prescribedDeformable0493x16i;
        d.deformAmplitude0493x16i = w.residentPoststreamDiag0493x16f.deformAmplitude0493x16i;
        d.deformOmega0493x16i = w.residentPoststreamDiag0493x16f.deformOmega0493x16i;
        d.positiveSolidFractionChange0493x16i =
            w.residentPoststreamDiag0493x16f.positiveSolidFractionChange0493x16i;
        d.negativeSolidFractionChange0493x16i =
            w.residentPoststreamDiag0493x16f.negativeSolidFractionChange0493x16i;
        d.maxAbsSolidFractionChange0493x16i =
            w.residentPoststreamDiag0493x16f.maxAbsSolidFractionChange0493x16i;
        d.sampledSolidVolume0493x16e = w.residentPoststreamDiag0493x16f.sampledSolidVolume;
        d.expectedSolidVolume0493x16e = w.residentPoststreamDiag0493x16f.expectedSolidVolume;
        d.sampledSolidVolumeRelativeError0493x16e =
            w.residentPoststreamDiag0493x16f.sampledSolidVolumeRelativeError;
        d.hostGeometryFieldUploadBytes0493x16e = rd.hostGeometryFieldUploadBytes;
        d.hostLoadFieldDownloadBytes0493x16e = rd.hostLoadFieldDownloadBytes;
        d.advanced = true;
        if (qualification0493x18d) {
            append_diagnostic_0493x16a(params, step, time, w.modelName.c_str(), d);
        } else {
            append_state_result_0493x18d(params, step, time, w.modelName.c_str(), d);
        }
        return d;
    }

    // Pre-x16e / non-CUDA fallback path.
    if (!w.model.dynamics || !w.model.geometry) {
        throw std::runtime_error("0493x16a host solid model missing during advance");
    }
    const auto& qBefore = w.model.dynamics->generalized_coordinates();
    const auto& qdotBefore = w.model.dynamics->generalized_velocities();
    if (qBefore.empty() || qdotBefore.empty()) {
        throw std::runtime_error("0493x16a dynamic solid exposes no primary diagnostic DOF");
    }
    d.centerXBefore = qBefore[0];
    d.velocityXBefore = qdotBefore[0];
    d.mass = w.model.dynamics->mass_diagnostic();
    d.solidMomentumBeforeX = d.mass * d.velocityXBefore;

    SolidFluidLoad0493x16a load{};
    load.brinkmanFluidImpulseX = brinkmanFluidImpulseX;
    load.brinkmanFluidImpulseY = brinkmanFluidImpulseY;
    load.bathFluidImpulseX = bathFluidImpulseX;
    load.bathFluidImpulseY = bathFluidImpulseY;
    load.chiVpFluidImpulseX = chiVpFluidImpulseX;
    load.chiVpFluidImpulseY = chiVpFluidImpulseY;

    const std::size_t ncell0493x16b = static_cast<std::size_t>(grid.Nx) *
                                      static_cast<std::size_t>(grid.Ny);
    const bool darcyFieldOk0493x16b =
        darcyCellFluidImpulseX0493x16b.size() == ncell0493x16b &&
        darcyCellFluidImpulseY0493x16b.size() == ncell0493x16b;
    const bool chiVpFieldOk0493x16b =
        (chiVpCellFluidImpulseX0493x16b.empty() && chiVpCellFluidImpulseY0493x16b.empty()) ||
        (chiVpCellFluidImpulseX0493x16b.size() == ncell0493x16b &&
         chiVpCellFluidImpulseY0493x16b.size() == ncell0493x16b);
    if (darcyFieldOk0493x16b && chiVpFieldOk0493x16b) {
        w.cellSolidReactionImpulseX0493x16b.assign(ncell0493x16b, 0.0);
        w.cellSolidReactionImpulseY0493x16b.assign(ncell0493x16b, 0.0);
        const bool haveChiVp0493x16b = chiVpCellFluidImpulseX0493x16b.size() == ncell0493x16b;
        for (std::size_t c = 0; c < ncell0493x16b; ++c) {
            const double chiX = haveChiVp0493x16b ? chiVpCellFluidImpulseX0493x16b[c] : 0.0;
            const double chiY = haveChiVp0493x16b ? chiVpCellFluidImpulseY0493x16b[c] : 0.0;
            const double sx = -(darcyCellFluidImpulseX0493x16b[c] + chiX);
            const double sy = -(darcyCellFluidImpulseY0493x16b[c] + chiY);
            w.cellSolidReactionImpulseX0493x16b[c] = sx;
            w.cellSolidReactionImpulseY0493x16b[c] = sy;
            d.cellReactionSumX0493x16b += sx;
            d.cellReactionSumY0493x16b += sy;
        }
        load.cellSolidReactionImpulseX = w.cellSolidReactionImpulseX0493x16b.data();
        load.cellSolidReactionImpulseY = w.cellSolidReactionImpulseY0493x16b.data();
        load.cellNx = grid.Nx;
        load.cellNy = grid.Ny;
        d.spatialLoadAvailable0493x16b = true;
        d.cellLoadClosureResidualX0493x16b = d.cellReactionSumX0493x16b + d.totalFluidImpulseX;
        d.cellLoadClosureResidualY0493x16b = d.cellReactionSumY0493x16b + d.totalFluidImpulseY;
    } else {
        w.cellSolidReactionImpulseX0493x16b.clear();
        w.cellSolidReactionImpulseY0493x16b.clear();
    }

    std::vector<double> generalizedImpulse;
    w.model.geometry->project_fluid_load(
        *w.model.dynamics, params, grid, w.fields, load, generalizedImpulse);
    if (generalizedImpulse.empty()) {
        throw std::runtime_error("0493x16a SolidGeometry produced no generalized fluid impulse");
    }
    if (d.spatialLoadAvailable0493x16b) {
        d.primaryProjectionResidual0493x16b = generalizedImpulse[0] - d.cellReactionSumX0493x16b;
    }
    d.solidReactionImpulseX = generalizedImpulse[0];
    d.solidReactionImpulseY = -d.totalFluidImpulseY;
    w.model.dynamics->advance_generalized_impulse(params.dt, generalizedImpulse);

    const auto& qAfter = w.model.dynamics->generalized_coordinates();
    const auto& qdotAfter = w.model.dynamics->generalized_velocities();
    d.centerXAfter = qAfter[0];
    d.velocityXAfter = qdotAfter[0];
    d.solidMomentumAfterX = d.mass * d.velocityXAfter;
    d.actionReactionResidualX = (d.solidMomentumAfterX - d.solidMomentumBeforeX) + d.totalFluidImpulseX;
    d.actionReactionResidualY = d.solidReactionImpulseY + d.totalFluidImpulseY;
    d.advanced = true;
    if (qualification0493x18d) {
        append_diagnostic_0493x16a(params, step, time, w.modelName.c_str(), d);
    } else {
        append_state_result_0493x18d(params, step, time, w.modelName.c_str(), d);
    }
    return d;
}

} // namespace mpcd

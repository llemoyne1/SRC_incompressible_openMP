#include "solid_model_rigid_slab_0493x16a.h"

#include "cell_grid.h"
#include "cuda_chi_solid_0493x16e.h"
#include "simulation_params.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <stdexcept>
#include <vector>

namespace mpcd {
namespace {

double wrap_periodic(double x, double L) {
    if (!(L > 0.0)) return x;
    x -= std::floor(x / L) * L;
    if (x >= L) x -= L;
    if (x < 0.0) x += L;
    return x;
}

double periodic_delta(double x, double c, double L) {
    double d = x - c;
    if (L > 0.0) d -= std::round(d / L) * L;
    return d;
}

double smoothstep01(double t) {
    t = std::min(1.0, std::max(0.0, t));
    return t * t * (3.0 - 2.0 * t);
}

class RigidSlab1DDynamics final : public SolidDynamicsModel0493x16a {
public:
    RigidSlab1DDynamics(double centerX, double velocityX, double mass, double Lx)
        : q_{wrap_periodic(centerX, Lx)}, qdot_{velocityX}, mass_(mass), Lx_(Lx) {}

    const char* model_name() const override { return "rigid_slab_1d"; }
    const std::vector<double>& generalized_coordinates() const override { return q_; }
    const std::vector<double>& generalized_velocities() const override { return qdot_; }
    double mass_diagnostic() const override { return mass_; }

    void advance_generalized_impulse(
        double dt, const std::vector<double>& generalizedImpulse) override {
        if (generalizedImpulse.size() != 1u) {
            throw std::runtime_error("0493x16a RigidSlab1D expects one generalized impulse");
        }
        qdot_[0] += generalizedImpulse[0] / mass_;
        q_[0] = wrap_periodic(q_[0] + dt * qdot_[0], Lx_);
    }

private:
    // q=[Xs], qdot=[Us]. There are no deformation DOFs, hence slab rigidity is
    // exact by representation rather than approximated by a large stiffness.
    std::vector<double> q_;
    std::vector<double> qdot_;
    double mass_ = 1.0;
    double Lx_ = 1.0;
};

class RigidSlab1DGeometry final : public SolidGeometryProvider0493x16a {
public:
    explicit RigidSlab1DGeometry(double thickness) : thickness_(thickness) {}

    void build_fields(const SolidDynamicsModel0493x16a& dynamics,
                      const SimulationParams& params,
                      const CellGrid& grid,
                      SolidCouplingFields0493x16a& fields) const override {
        const auto& q = dynamics.generalized_coordinates();
        const auto& qdot = dynamics.generalized_velocities();
        if (q.size() != 1u || qdot.size() != 1u) {
            throw std::runtime_error("0493x16a RigidSlab1D geometry received incompatible DOFs");
        }
        const int nx = grid.Nx;
        const int ny = grid.Ny;
        const std::size_t n = static_cast<std::size_t>(nx) * static_cast<std::size_t>(ny);
        fields.nx = nx;
        fields.ny = ny;
        fields.signedDistance.assign(n, 0.0f);
        fields.chi.assign(n, 1.0f);
        fields.uSolidX.assign(n, static_cast<float>(qdot[0]));
        fields.uSolidY.assign(n, 0.0f);
        const double dx = params.Lx / static_cast<double>(std::max(1, nx));
        const double half = 0.5 * thickness_;
        const double transition = std::max(0.0, params.darcyInterfaceWidth);
        for (int iy = 0; iy < ny; ++iy) {
            for (int ix = 0; ix < nx; ++ix) {
                const double x = (static_cast<double>(ix) + 0.5) * dx;
                const double sd = std::abs(periodic_delta(x, q[0], params.Lx)) - half;
                double chi = 1.0;
                if (transition > 0.0) {
                    chi = sd <= 0.0 ? 0.0 : smoothstep01(sd / transition);
                } else {
                    chi = sd <= 0.0 ? 0.0 : 1.0;
                }
                const std::size_t c = static_cast<std::size_t>(iy) * static_cast<std::size_t>(nx)
                                    + static_cast<std::size_t>(ix);
                fields.signedDistance[c] = static_cast<float>(sd);
                fields.chi[c] = static_cast<float>(chi);
            }
        }
    }

    void project_fluid_load(
        const SolidDynamicsModel0493x16a& dynamics,
        const SimulationParams&,
        const CellGrid&,
        const SolidCouplingFields0493x16a&,
        const SolidFluidLoad0493x16a& load,
        std::vector<double>& generalizedImpulse) const override {
        if (dynamics.generalized_coordinates().size() != 1u) {
            throw std::runtime_error("0493x16a RigidSlab1D load projection received incompatible DOFs");
        }
        // The only free DOF is translation in x. x16b deliberately consumes
        // the cell-resolved solid-reaction field when available; summing it is
        // the RigidSlab1D projection operator. A future membrane replaces this
        // sum by shape-function/generalized-force projection without changing
        // the MPCD core. The y reaction remains an ideal constraint reaction.
        if (load.cellSolidReactionImpulseX && load.cellNx > 0 && load.cellNy > 0) {
            const std::size_t n = static_cast<std::size_t>(load.cellNx) *
                                  static_cast<std::size_t>(load.cellNy);
            double qx = 0.0;
            for (std::size_t c = 0; c < n; ++c) qx += load.cellSolidReactionImpulseX[c];
            generalizedImpulse.assign(1u, qx);
        } else {
            generalizedImpulse.assign(1u, -(load.brinkmanFluidImpulseX +
                                             load.bathFluidImpulseX +
                                             load.chiVpFluidImpulseX));
        }
    }

private:
    double thickness_ = 0.0;
};

class RigidSlab1DCudaResident0493x16e final : public SolidCudaResidentProvider0493x16e {
public:
    RigidSlab1DCudaResident0493x16e(double centerX, double velocityX, double mass, double thickness)
        : initialCenterX_(centerX), initialVelocityX_(velocityX), mass_(mass), thickness_(thickness) {}

    const char* model_name() const override { return "rigid_slab_1d"; }
    bool available() const override { return cuda_chi_solid_0493x16e_available(); }

    void prepare_device_fields(
        const SimulationParams& params,
        const CellGrid& grid,
        std::uint64_t geometryVersion,
        const SolidCudaCouplingFields0493x16e& fields,
        SolidCudaDiagnostics0493x16e& diagnostics) override {
        if (!available()) {
            throw std::runtime_error("0493x16e RigidSlab1D CUDA resident backend unavailable");
        }
        if (fields.nx != grid.Nx || fields.ny != grid.Ny ||
            !fields.chi || !fields.uSolidX || !fields.uSolidY) {
            throw std::runtime_error("0493x16e RigidSlab1D received invalid device coupling fields");
        }
        if (std::abs(params.darcyInterfaceWidth) > 1.0e-15) {
            throw std::runtime_error("0493x16f temporal-sync qualification requires darcyInterfaceWidth=0 historical binary mask");
        }
        CudaChiSolidDiagnostics0493x16e d{};
        if (!cuda_chi_solid_0493x16f_prepare_rigid_slab_binary(
                fields.chi, fields.uSolidX, fields.uSolidY,
                grid.Nx, grid.Ny, params.Lx, params.Ly,
                initialCenterX_, initialVelocityX_, mass_, thickness_, params.dt,
                geometryVersion, (params.chiKineticBoundaryMode == "specular" || params.chiKineticBoundaryMode == "bounceback") ? 1 : 0, &d)) {
            throw std::runtime_error("0493x16f RigidSlab1D historical-binary prepare failed");
        }
        diagnostics = SolidCudaDiagnostics0493x16e{};
        diagnostics.available = d.available;
        diagnostics.rasterized = d.rasterized;
        diagnostics.binaryHistorical0493x16f = d.binaryHistorical0493x16f;
        diagnostics.temporalSync0493x16f = d.temporalSync0493x16f;
        diagnostics.geometryVersion = d.geometryVersion;
        diagnostics.centerXBefore = d.centerXBefore;
        diagnostics.centerXAfter = d.centerXAfter;
        diagnostics.velocityXBefore = d.velocityXBefore;
        diagnostics.velocityXAfter = d.velocityXAfter;
        diagnostics.mass = d.mass;
        diagnostics.sampledSolidVolume = d.sampledSolidVolume;
        diagnostics.expectedSolidVolume = d.expectedSolidVolume;
        diagnostics.sampledSolidVolumeRelativeError = d.sampledSolidVolumeRelativeError;
        diagnostics.poststreamDriftX0493x16f = d.poststreamDriftX0493x16f;
        diagnostics.prescribedDeformable0493x16i = d.prescribedDeformable0493x16i;
        diagnostics.deformAmplitude0493x16i = d.deformAmplitude0493x16i;
        diagnostics.deformOmega0493x16i = d.deformOmega0493x16i;
        diagnostics.positiveSolidFractionChange0493x16i = d.positiveSolidFractionChange0493x16i;
        diagnostics.negativeSolidFractionChange0493x16i = d.negativeSolidFractionChange0493x16i;
        diagnostics.maxAbsSolidFractionChange0493x16i = d.maxAbsSolidFractionChange0493x16i;
        diagnostics.hostGeometryFieldUploadBytes = d.hostGeometryFieldUploadBytes;
        diagnostics.hostLoadFieldDownloadBytes = d.hostLoadFieldDownloadBytes;
    }

    void synchronize_poststream_device_fields(
        const SimulationParams& params,
        const CellGrid& grid,
        std::uint64_t geometryVersion,
        const SolidCudaCouplingFields0493x16e& fields,
        SolidCudaDiagnostics0493x16e& diagnostics) override {
        if (!available()) {
            throw std::runtime_error("0493x16f RigidSlab1D CUDA resident backend unavailable");
        }
        if (fields.nx != grid.Nx || fields.ny != grid.Ny ||
            !fields.chi || !fields.uSolidX || !fields.uSolidY) {
            throw std::runtime_error("0493x16f RigidSlab1D received invalid poststream coupling fields");
        }
        CudaChiSolidDiagnostics0493x16e d{};
        if (!cuda_chi_solid_0493x16f_poststream_sync_rigid_slab(
                fields.chi, fields.uSolidX, fields.uSolidY,
                grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt,
                geometryVersion, (params.chiKineticBoundaryMode == "specular" || params.chiKineticBoundaryMode == "bounceback") ? 1 : 0, &d)) {
            throw std::runtime_error("0493x16f RigidSlab1D poststream geometry synchronization failed");
        }
        diagnostics = SolidCudaDiagnostics0493x16e{};
        diagnostics.available = d.available;
        diagnostics.rasterized = d.rasterized;
        diagnostics.binaryHistorical0493x16f = d.binaryHistorical0493x16f;
        diagnostics.temporalSync0493x16f = d.temporalSync0493x16f;
        diagnostics.geometryVersion = d.geometryVersion;
        diagnostics.centerXBefore = d.centerXBefore;
        diagnostics.centerXAfter = d.centerXAfter;
        diagnostics.velocityXBefore = d.velocityXBefore;
        diagnostics.velocityXAfter = d.velocityXAfter;
        diagnostics.mass = d.mass;
        diagnostics.sampledSolidVolume = d.sampledSolidVolume;
        diagnostics.expectedSolidVolume = d.expectedSolidVolume;
        diagnostics.sampledSolidVolumeRelativeError = d.sampledSolidVolumeRelativeError;
        diagnostics.poststreamDriftX0493x16f = d.poststreamDriftX0493x16f;
        diagnostics.prescribedDeformable0493x16i = d.prescribedDeformable0493x16i;
        diagnostics.deformAmplitude0493x16i = d.deformAmplitude0493x16i;
        diagnostics.deformOmega0493x16i = d.deformOmega0493x16i;
        diagnostics.positiveSolidFractionChange0493x16i = d.positiveSolidFractionChange0493x16i;
        diagnostics.negativeSolidFractionChange0493x16i = d.negativeSolidFractionChange0493x16i;
        diagnostics.maxAbsSolidFractionChange0493x16i = d.maxAbsSolidFractionChange0493x16i;
        diagnostics.hostGeometryFieldUploadBytes = d.hostGeometryFieldUploadBytes;
        diagnostics.hostLoadFieldDownloadBytes = d.hostLoadFieldDownloadBytes;
    }

    void project_load_and_advance(
        const SimulationParams& params,
        const CellGrid& grid,
        const SolidCudaFluidLoad0493x16e& load,
        SolidCudaDiagnostics0493x16e& diagnostics) override {
        if (!available()) {
            throw std::runtime_error("0493x16e RigidSlab1D CUDA resident backend unavailable");
        }
        if (load.nx != grid.Nx || load.ny != grid.Ny ||
            !load.darcyFluidImpulseX || !load.darcyFluidImpulseY) {
            throw std::runtime_error("0493x16e RigidSlab1D received invalid resident fluid load");
        }
        CudaChiSolidDiagnostics0493x16e d{};
        if (!cuda_chi_solid_0493x16f_apply_rigid_slab_impulse(
                load.darcyFluidImpulseX, load.darcyFluidImpulseY,
                load.chiVpFluidImpulseX, load.chiVpFluidImpulseY,
                load.chiKineticWallReactionImpulseX0493x16j,
                load.chiKineticWallReactionImpulseY0493x16j,
                grid.Nx, grid.Ny, params.dt, params.Lx, &d)) {
            throw std::runtime_error("0493x16f RigidSlab1D resident load projection/kick failed");
        }
        diagnostics = SolidCudaDiagnostics0493x16e{};
        diagnostics.available = d.available;
        diagnostics.advanced = d.advanced;
        diagnostics.binaryHistorical0493x16f = d.binaryHistorical0493x16f;
        diagnostics.temporalSync0493x16f = d.temporalSync0493x16f;
        diagnostics.geometryVersion = d.geometryVersion;
        diagnostics.centerXBefore = d.centerXBefore;
        diagnostics.centerXAfter = d.centerXAfter;
        diagnostics.velocityXBefore = d.velocityXBefore;
        diagnostics.velocityXAfter = d.velocityXAfter;
        diagnostics.mass = d.mass;
        diagnostics.cellReactionSumX = d.cellReactionSumX;
        diagnostics.cellReactionSumY = d.cellReactionSumY;
        diagnostics.generalizedImpulseX = d.generalizedImpulseX;
        diagnostics.primaryProjectionResidual = d.primaryProjectionResidual;
        diagnostics.hostGeometryFieldUploadBytes = d.hostGeometryFieldUploadBytes;
        diagnostics.hostLoadFieldDownloadBytes = d.hostLoadFieldDownloadBytes;
    }

private:
    double initialCenterX_ = 0.0;
    double initialVelocityX_ = 0.0;
    double mass_ = 1.0;
    double thickness_ = 0.0;
};

} // namespace

SolidModelBundle0493x16a make_rigid_slab_1d_0493x16a(const SimulationParams& params) {
    const double thickness = params.darcyBoxXMax - params.darcyBoxXMin;
    if (!(thickness > 0.0)) {
        throw std::runtime_error("0493x16a rigid slab requires positive darcy box thickness");
    }
    const double center = 0.5 * (params.darcyBoxXMin + params.darcyBoxXMax);
    SolidModelBundle0493x16a b;
    b.dynamics = std::make_unique<RigidSlab1DDynamics>(
        center, params.darcyUSolidX, params.chiSolidMass, params.Lx);
    b.geometry = std::make_unique<RigidSlab1DGeometry>(thickness);
    b.resident0493x16e = std::make_unique<RigidSlab1DCudaResident0493x16e>(
        center, params.darcyUSolidX, params.chiSolidMass, thickness);
    return b;
}

} // namespace mpcd

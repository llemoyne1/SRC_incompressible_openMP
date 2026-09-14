#pragma once

#include <cstdint>
#include <memory>
#include <vector>

namespace mpcd {

struct CellGrid;
struct SimulationParams;

// Fluid -> solid load contract. x16a established exact globally integrated
// Darcy/bath/chiVP action-reaction; x16b now also fills the cell-wise total
// solid-reaction field on the physical Eulerian grid. A deformable geometry can
// project this distribution onto nodal/generalized DOFs without changing MPCD.
struct SolidFluidLoad0493x16a {
    // Keep the x15 mechanisms distinct inside the coupling contract even when
    // a particular solid model only needs their sum.  This preserves physical
    // attribution (Brinkman / outward bath / chiVP) while presenting one
    // user-facing solid model.
    double brinkmanFluidImpulseX = 0.0;
    double brinkmanFluidImpulseY = 0.0;
    double bathFluidImpulseX = 0.0;
    double bathFluidImpulseY = 0.0;
    double chiVpFluidImpulseX = 0.0;
    double chiVpFluidImpulseY = 0.0;
    const double* cellSolidReactionImpulseX = nullptr;
    const double* cellSolidReactionImpulseY = nullptr;
    int cellNx = 0;
    int cellNy = 0;
};

// SolidGeometry -> fluid coupling contract.  chi is a derived Eulerian field,
// never the mechanical state.  signedDistance remains explicit even though the
// x16a fluid operators consume chi/u_s only; deformable-solid geometry can use
// it later for normals, interface reconstruction and load projection.
struct SolidCouplingFields0493x16a {
    int nx = 0;
    int ny = 0;
    std::vector<float> signedDistance;
    std::vector<float> chi;
    std::vector<float> uSolidX;
    std::vector<float> uSolidY;
};

// Mechanical/constitutive module.  The solver never interprets q or qdot.
// Their meaning belongs to the selected solid model: [Xs] for RigidSlab1D,
// [X,Y,theta] for a rigid body, nodal displacements for a membrane, etc.
class SolidDynamicsModel0493x16a {
public:
    virtual ~SolidDynamicsModel0493x16a() = default;
    virtual const char* model_name() const = 0;
    virtual const std::vector<double>& generalized_coordinates() const = 0;
    virtual const std::vector<double>& generalized_velocities() const = 0;
    virtual double mass_diagnostic() const = 0;

    // generalizedImpulse has exactly the model DOF count and is produced by
    // SolidGeometryProvider::project_fluid_load().  Internal elastic/damping
    // forces remain a responsibility of the dynamics model.
    virtual void advance_generalized_impulse(
        double dt, const std::vector<double>& generalizedImpulse) = 0;
};

// Geometry/load-transfer module.  It interprets q/qdot for one solid family,
// builds Eulerian coupling fields, and performs the reverse map from Eulerian
// fluid reaction to generalized impulses.  This is the key separation needed
// for later deformable membranes: the MPCD core stays unchanged.
class SolidGeometryProvider0493x16a {
public:
    virtual ~SolidGeometryProvider0493x16a() = default;
    virtual void build_fields(const SolidDynamicsModel0493x16a& dynamics,
                              const SimulationParams& params,
                              const CellGrid& grid,
                              SolidCouplingFields0493x16a& fields) const = 0;
    virtual void project_fluid_load(
        const SolidDynamicsModel0493x16a& dynamics,
        const SimulationParams& params,
        const CellGrid& grid,
        const SolidCouplingFields0493x16a& fields,
        const SolidFluidLoad0493x16a& load,
        std::vector<double>& generalizedImpulse) const = 0;
};

// 0493x16e CUDA-resident counterpart of the host SolidGeometry/Dynamics
// contract. The core only passes generic device fields and loads; model-
// specific rasterization, generalized-force projection and time integration
// remain implemented inside the selected solid module. This preserves the
// same extension point for future rigid bodies and deformable membranes.
struct SolidCudaCouplingFields0493x16e {
    float* chi = nullptr;
    float* uSolidX = nullptr;
    float* uSolidY = nullptr;
    int nx = 0;
    int ny = 0;
};

struct SolidCudaFluidLoad0493x16e {
    const double* darcyFluidImpulseX = nullptr;
    const double* darcyFluidImpulseY = nullptr;
    const double* chiVpFluidImpulseX = nullptr;
    const double* chiVpFluidImpulseY = nullptr;
    // 0493x16j is already a SOLID reaction impulse (opposite fluid impulse).
    const double* chiKineticWallReactionImpulseX0493x16j = nullptr;
    const double* chiKineticWallReactionImpulseY0493x16j = nullptr;
    int nx = 0;
    int ny = 0;
};

struct SolidCudaDiagnostics0493x16e {
    bool available = false;
    bool rasterized = false;
    bool advanced = false;
    bool binaryHistorical0493x16f = false;
    bool temporalSync0493x16f = false;
    std::uint64_t geometryVersion = 0u;
    double centerXBefore = 0.0;
    double centerXAfter = 0.0;
    double velocityXBefore = 0.0;
    double velocityXAfter = 0.0;
    double mass = 0.0;
    double sampledSolidVolume = 0.0;
    double expectedSolidVolume = 0.0;
    double sampledSolidVolumeRelativeError = 0.0;
    double poststreamDriftX0493x16f = 0.0;
    bool prescribedDeformable0493x16i = false;
    double deformAmplitude0493x16i = 0.0;
    double deformOmega0493x16i = 0.0;
    double positiveSolidFractionChange0493x16i = 0.0;
    double negativeSolidFractionChange0493x16i = 0.0;
    double maxAbsSolidFractionChange0493x16i = 0.0;
    double cellReactionSumX = 0.0;
    double cellReactionSumY = 0.0;
    double generalizedImpulseX = 0.0;
    double primaryProjectionResidual = 0.0;
    std::uint64_t hostGeometryFieldUploadBytes = 0u;
    std::uint64_t hostLoadFieldDownloadBytes = 0u;
};

class SolidCudaResidentProvider0493x16e {
public:
    virtual ~SolidCudaResidentProvider0493x16e() = default;
    virtual const char* model_name() const = 0;
    virtual bool available() const = 0;
    virtual void prepare_device_fields(
        const SimulationParams& params,
        const CellGrid& grid,
        std::uint64_t geometryVersion,
        const SolidCudaCouplingFields0493x16e& fields,
        SolidCudaDiagnostics0493x16e& diagnostics) = 0;
    // 0493x16f: after the particle streaming/boundary stage, drift q with the
    // pre-kick velocity and republish geometry before collision/Darcy.  This
    // aligns x_i^{n+1} with geometry at t_{n+1} without changing any fluid
    // closure law.
    virtual void synchronize_poststream_device_fields(
        const SimulationParams& params,
        const CellGrid& grid,
        std::uint64_t geometryVersion,
        const SolidCudaCouplingFields0493x16e& fields,
        SolidCudaDiagnostics0493x16e& diagnostics) = 0;

    virtual void project_load_and_advance(
        const SimulationParams& params,
        const CellGrid& grid,
        const SolidCudaFluidLoad0493x16e& load,
        SolidCudaDiagnostics0493x16e& diagnostics) = 0;
};

struct SolidModelBundle0493x16a {
    std::unique_ptr<SolidDynamicsModel0493x16a> dynamics;
    std::unique_ptr<SolidGeometryProvider0493x16a> geometry;
    std::unique_ptr<SolidCudaResidentProvider0493x16e> resident0493x16e;
};

// Central factory: adding a new solid adds a dynamics implementation, a
// geometry/load-transfer implementation, and one dispatch entry here.  The
// MPCD timestep must not acquire model-specific geometry or constitutive code.
SolidModelBundle0493x16a make_solid_model_0493x16a(const SimulationParams& params);

} // namespace mpcd

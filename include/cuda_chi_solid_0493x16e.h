#pragma once

#include <cstdint>

namespace mpcd {

// 0493x16e/x16f: CUDA-resident dynamic chi-solid state, geometry publication
// and solid-side spatial load. x16f reuses this resident infrastructure while
// restoring the historical sharp cell-center chi representation.
// Fluid operators remain in their existing CUDA modules and exchange device
// pointers with this module; no full-grid host upload/download is required.
struct CudaChiSolidDiagnostics0493x16e {
    bool available = false;
    bool initialized = false;
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
    double thickness = 0.0;

    // Exact cell-volume rasterization diagnostic. sampledSolidVolume is
    // obtained from the dedicated geometric solid-fraction field.  In x16j/x16k
    // kinetic mode chi is a level field for wall reconstruction, so 1-chi is
    // intentionally NOT used as a volume measure.
    double sampledSolidVolume = 0.0;
    double expectedSolidVolume = 0.0;
    double sampledSolidVolumeRelativeError = 0.0;
    double poststreamDriftX0493x16f = 0.0;

    // 0493x16i prescribed-deformable qualification. The historical binary
    // chi/Darcy path remains the fluid operator; a separate geometric solid
    // fraction is rasterized only to characterize swept/excluded volume.
    bool prescribedDeformable0493x16i = false;
    double deformAmplitude0493x16i = 0.0;
    double deformOmega0493x16i = 0.0;
    double positiveSolidFractionChange0493x16i = 0.0;
    double negativeSolidFractionChange0493x16i = 0.0;
    double maxAbsSolidFractionChange0493x16i = 0.0;

    // Device-resident spatial load reduction / generalized projection.
    double cellReactionSumX = 0.0;
    double cellReactionSumY = 0.0;
    double generalizedImpulseX = 0.0;
    double primaryProjectionResidual = 0.0;

    // Full-grid host traffic intentionally eliminated in the resident path.
    std::uint64_t hostGeometryFieldUploadBytes = 0u;
    std::uint64_t hostLoadFieldDownloadBytes = 0u;
};

// 0493x16i: expose the resident prescribed-deformable geometry needed by the
// local exclusion/remap experiment without downloading grid fields. The
// global translation DOF remains in deviceState=[centerX,velocityX,mass,thickness].
struct CudaPrescribedDeformableGeometry0493x16i {
    bool enabled = false;
    const double* deviceState = nullptr;
    double amplitude = 0.0;
    double omega = 0.0;
    double Lx = 0.0;
    double Ly = 0.0;
    double dt = 0.0;
};

#if defined(MPCD_ENABLE_CUDA_CHI_SOLID_0493X16E)

bool cuda_chi_solid_0493x16e_available();

// 0493x16f: keep the historical binary chi representation, but make the
// solid geometry time-consistent with post-stream particle positions. The
// prepare call publishes q^n without advancing it; poststream_sync performs
// X^{n+1,*}=X^n+dt U^n and republishes the SAME binary cell-center mask.
// No Darcy/bath/chiVP closure law is changed.
bool cuda_chi_solid_0493x16f_prepare_rigid_slab_binary(
    float* deviceChi,
    float* deviceUSolidX,
    float* deviceUSolidY,
    int nx,
    int ny,
    double Lx,
    double Ly,
    double initialCenterX,
    double initialVelocityX,
    double mass,
    double thickness,
    double dt,
    std::uint64_t geometryVersion,
    int continuousChiGeometry0493x16j,
    CudaChiSolidDiagnostics0493x16e* diagnostics);

bool cuda_chi_solid_0493x16f_poststream_sync_rigid_slab(
    float* deviceChi,
    float* deviceUSolidX,
    float* deviceUSolidY,
    int nx,
    int ny,
    double Lx,
    double Ly,
    double dt,
    std::uint64_t geometryVersion,
    int continuousChiGeometry0493x16j,
    CudaChiSolidDiagnostics0493x16e* diagnostics);

// 0493x16g diagnostic ablation: device-resident mask of cells that changed
// from fluid (chi=1) to solid (chi=0) during the x16f post-stream geometry
// update. Static solids and steps without a mask shift expose an all-zero mask.
bool cuda_chi_solid_0493x16g_device_newly_solid_mask(
    const unsigned char** deviceMask, int* nx, int* ny);

// 0493x16k: expose the already-resident exact cell solid fraction for
// diagnostics that need physical occupied volume while chi serves as a
// translation-covariant kinetic level field. No new buffer is allocated.
bool cuda_chi_solid_0493x16k_device_solid_fraction(
    const float** deviceSolidFraction, int* nx, int* ny);

bool cuda_chi_solid_0493x16i_prescribed_geometry(
    CudaPrescribedDeformableGeometry0493x16i* geometry);

// Apply the exact reaction impulse after fluid coupling, but do not drift the
// solid position again: x16f already performed the drift before collision.
bool cuda_chi_solid_0493x16f_apply_rigid_slab_impulse(
    const double* deviceDarcyFluidImpulseX,
    const double* deviceDarcyFluidImpulseY,
    const double* deviceChiVpFluidImpulseX,
    const double* deviceChiVpFluidImpulseY,
    const double* deviceChiKineticWallReactionX0493x16j,
    const double* deviceChiKineticWallReactionY0493x16j,
    int nx,
    int ny,
    double dt,
    double Lx,
    CudaChiSolidDiagnostics0493x16e* diagnostics);

// Initialize the RigidSlab1D device state once, then rasterize it directly into
// Darcy-owned device fields. chi uses exact cell/solid interval intersection:
// Convention remains chi=1 fluid, chi=0 solid, hence
// chi = 1 - solid cell-volume fraction.
bool cuda_chi_solid_0493x16e_prepare_rigid_slab(
    float* deviceChi,
    float* deviceUSolidX,
    float* deviceUSolidY,
    int nx,
    int ny,
    double Lx,
    double Ly,
    double initialCenterX,
    double initialVelocityX,
    double mass,
    double thickness,
    std::uint64_t geometryVersion,
    CudaChiSolidDiagnostics0493x16e* diagnostics);

// Assemble the exact cell-resolved solid reaction from the already-resident
// Darcy/bath and chiVP fluid-impulse fields, project it to the slab translation
// DOF on device, and advance q,qdot on device. chiVP pointers may be null when
// chiVP is disabled.
bool cuda_chi_solid_0493x16e_advance_rigid_slab(
    const double* deviceDarcyFluidImpulseX,
    const double* deviceDarcyFluidImpulseY,
    const double* deviceChiVpFluidImpulseX,
    const double* deviceChiVpFluidImpulseY,
    int nx,
    int ny,
    double dt,
    double Lx,
    CudaChiSolidDiagnostics0493x16e* diagnostics);

// Resident reaction field retained for future deformable-solid projection.
bool cuda_chi_solid_0493x16e_device_reaction_field(
    const double** deviceReactionX,
    const double** deviceReactionY,
    int* nx,
    int* ny);

#else

inline bool cuda_chi_solid_0493x16e_available() { return false; }
inline bool cuda_chi_solid_0493x16f_prepare_rigid_slab_binary(
    float*, float*, float*, int, int, double, double, double, double, double,
    double, double, std::uint64_t, int, CudaChiSolidDiagnostics0493x16e*) { return false; }
inline bool cuda_chi_solid_0493x16f_poststream_sync_rigid_slab(
    float*, float*, float*, int, int, double, double, double, std::uint64_t, int,
    CudaChiSolidDiagnostics0493x16e*) { return false; }
inline bool cuda_chi_solid_0493x16g_device_newly_solid_mask(
    const unsigned char** mask, int* nx, int* ny) {
    if (mask) *mask = nullptr; if (nx) *nx = 0; if (ny) *ny = 0; return false;
}
inline bool cuda_chi_solid_0493x16k_device_solid_fraction(
    const float** solidFraction, int* nx, int* ny) {
    if (solidFraction) *solidFraction = nullptr;
    if (nx) *nx = 0; if (ny) *ny = 0; return false;
}
inline bool cuda_chi_solid_0493x16i_prescribed_geometry(
    CudaPrescribedDeformableGeometry0493x16i* geometry) {
    if (geometry) *geometry = CudaPrescribedDeformableGeometry0493x16i{};
    return false;
}
inline bool cuda_chi_solid_0493x16f_apply_rigid_slab_impulse(
    const double*, const double*, const double*, const double*,
    const double*, const double*, int, int,
    double, double, CudaChiSolidDiagnostics0493x16e*) { return false; }
inline bool cuda_chi_solid_0493x16e_prepare_rigid_slab(
    float*, float*, float*, int, int, double, double, double, double, double,
    double, std::uint64_t, CudaChiSolidDiagnostics0493x16e*) { return false; }
inline bool cuda_chi_solid_0493x16e_advance_rigid_slab(
    const double*, const double*, const double*, const double*, int, int,
    double, double, CudaChiSolidDiagnostics0493x16e*) { return false; }
inline bool cuda_chi_solid_0493x16e_device_reaction_field(
    const double** x, const double** y, int* nx, int* ny) {
    if (x) *x = nullptr; if (y) *y = nullptr;
    if (nx) *nx = 0; if (ny) *ny = 0;
    return false;
}

#endif

} // namespace mpcd

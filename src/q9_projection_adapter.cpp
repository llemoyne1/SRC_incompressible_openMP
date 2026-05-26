#include "q9_projection_adapter.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <limits>
#include <vector>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <string>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace mpcd {
namespace {

int thread_count() {
#ifdef _OPENMP
    return omp_get_max_threads();
#else
    return 1;
#endif
}

int thread_id() {
#ifdef _OPENMP
    return omp_get_thread_num();
#else
    return 0;
#endif
}

void resize_q9_workspace(Q9ProjectionWorkspace& ws,
                         std::uint64_t numParticles,
                         int numCells,
                         int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_q9_workspace: invalid number of cells");
    }
    if (numThreads <= 0) {
        numThreads = 1;
    }

    const bool sameSize = ws.allocatedCells == numCells &&
                          ws.allocatedParticles == numParticles &&
                          static_cast<int>(ws.localMass.size()) == numThreads * numCells;
    if (sameSize) {
        return;
    }

    ws.allocatedCells = numCells;
    ws.allocatedParticles = numParticles;
    const std::size_t np = static_cast<std::size_t>(numParticles);
    const std::size_t nc = static_cast<std::size_t>(numCells);
    const std::size_t nLocal = static_cast<std::size_t>(numThreads * numCells);

    ws.cellId.assign(np, 0);
    ws.cellMass.assign(nc, 0.0);
    ws.cellPx.assign(nc, 0.0);
    ws.cellPy.assign(nc, 0.0);
    ws.cellDUx.assign(nc, 0.0);
    ws.cellDUy.assign(nc, 0.0);
    ws.cellDUxRaw.assign(nc, 0.0);
    ws.cellDUyRaw.assign(nc, 0.0);
    ws.cellCorrectionRawMag.assign(nc, 0.0);
    ws.cellCorrectionAppliedMag.assign(nc, 0.0);
    ws.cellCorrectionLimiterRatio.assign(nc, 0.0);
    ws.cellCorrectionLimiterActive.assign(nc, 0u);
    ws.cellLowMassSuppressed.assign(nc, 0u);
    ws.cellLowMassRamped.assign(nc, 0u);
    ws.cellMassFloorApplied.assign(nc, 0u);
    ws.cellSafetyActive.assign(nc, 0u);
    ws.localMass.assign(nLocal, 0.0);
    ws.localPx.assign(nLocal, 0.0);
    ws.localPy.assign(nLocal, 0.0);
    ws.targetDivergence.assign(nc, 0.0);
    ws.massAfterEstimate.assign(nc, 0.0);
    resize_periodic_face_field(ws.baseMassFlux, numCells);
    resize_periodic_face_field(ws.alpha, numCells);
    resize_periodic_face_field(ws.appliedCorrectionFlux, numCells);
    resize_periodic_face_field(ws.projectedMassFlux, numCells);
    resize_elliptic_projection_workspace(ws.elliptic, numCells);
}

EllipticProjectionBC q9_bc_from_particle_boundaries(const SimulationParams& params) {
    EllipticProjectionBC bc{};
    bc.x = is_x_periodic(params) ? EllipticBoundaryType::Periodic
                                 : EllipticBoundaryType::WallNoNormalFlux;
    bc.y = is_y_periodic(params) ? EllipticBoundaryType::Periodic
                                 : EllipticBoundaryType::WallNoNormalFlux;
    return bc;
}

int active_domain_cell_index(double x,
                             double y,
                             const FluidDomainBounds& domain,
                             const SimulationParams& params) {
    const double width = fluid_domain_width(domain);
    const double height = fluid_domain_height(domain);
    double xr = x - domain.xMin;
    double yr = y - domain.yMin;
    if (is_x_periodic(params)) {
        xr = std::fmod(xr, width);
        if (xr < 0.0) xr += width;
    } else {
        xr = std::clamp(xr, 0.0, width);
    }
    if (is_y_periodic(params)) {
        yr = std::fmod(yr, height);
        if (yr < 0.0) yr += height;
    } else {
        yr = std::clamp(yr, 0.0, height);
    }
    int ix = static_cast<int>(std::floor(xr / (width / static_cast<double>(params.Nx))));
    int iy = static_cast<int>(std::floor(yr / (height / static_cast<double>(params.Ny))));
    ix = std::clamp(ix, 0, params.Nx - 1);
    iy = std::clamp(iy, 0, params.Ny - 1);
    return ix + params.Nx * iy;
}

double active_domain_divergence_rate(const FluidDomainBounds& domain) {
    const double width = fluid_domain_width(domain);
    const double height = fluid_domain_height(domain);
    double rate = 0.0;
    if (width > 0.0) {
        rate += (domain.vxMax - domain.vxMin) / width;
    }
    if (height > 0.0) {
        rate += (domain.vyMax - domain.vyMin) / height;
    }
    return rate;
}

bool has_x_io_pair(const SimulationParams& params) {
    return (is_inlet_boundary_mode(params.bcLeft) && is_outlet_boundary_mode(params.bcRight)) ||
           (is_outlet_boundary_mode(params.bcLeft) && is_inlet_boundary_mode(params.bcRight));
}

bool has_y_io_pair(const SimulationParams& params) {
    return (is_inlet_boundary_mode(params.bcBottom) && is_outlet_boundary_mode(params.bcTop)) ||
           (is_outlet_boundary_mode(params.bcBottom) && is_inlet_boundary_mode(params.bcTop));
}

double inlet_velocity_ramp_factor(const SimulationParams& params, double time) {
    if (!params.inletVelocityRampEnable) return 1.0;
    const double t0 = params.inletVelocityRampStartTime;
    const double t1 = params.inletVelocityRampEndTime;
    if (!(t1 > t0)) return params.inletVelocityRampFinalFactor;
    double a = 0.0;
    if (time <= t0) a = 0.0;
    else if (time >= t1) a = 1.0;
    else a = (time - t0) / (t1 - t0);
    if (params.inletVelocityRampProfile == "smoothstep") {
        a = a * a * (3.0 - 2.0 * a);
    }
    return (1.0 - a) * params.inletVelocityRampInitialFactor +
           a * params.inletVelocityRampFinalFactor;
}

double q9_open_x_velocity_component(const SimulationParams& params, double time) {
    const double f = inlet_velocity_ramp_factor(params, time);
    if (is_inlet_boundary_mode(params.bcLeft) && is_outlet_boundary_mode(params.bcRight)) {
        return f * params.inletUxLeft;
    }
    if (is_inlet_boundary_mode(params.bcRight) && is_outlet_boundary_mode(params.bcLeft)) {
        return f * params.inletUxRight;
    }
    return 0.0;
}

double q9_open_y_velocity_component(const SimulationParams& params, double time) {
    const double f = inlet_velocity_ramp_factor(params, time);
    if (is_inlet_boundary_mode(params.bcBottom) && is_outlet_boundary_mode(params.bcTop)) {
        return f * params.inletUyBottom;
    }
    if (is_inlet_boundary_mode(params.bcTop) && is_outlet_boundary_mode(params.bcBottom)) {
        return f * params.inletUyTop;
    }
    return 0.0;
}

double smoothstep01(double x) {
    x = std::clamp(x, 0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);
}

double flat_taper_y_base_factor(const SimulationParams& params,
                                const FluidDomainBounds& domain,
                                double y) {
    if (!(params.inletVelocityWallTaperCells > 0.0)) return 1.0;
    const double h = domain.yMax - domain.yMin;
    if (!(h > 0.0)) return 1.0;
    const double dy = h / static_cast<double>(std::max(1, params.Ny));
    const double taperWidth = params.inletVelocityWallTaperCells * dy;
    if (!(taperWidth > 0.0)) return 1.0;
    const double dist = std::min(y - domain.yMin, domain.yMax - y);
    return smoothstep01(dist / taperWidth);
}

double flat_taper_y_mean_factor(const SimulationParams& params,
                                const FluidDomainBounds& domain,
                                double y) {
    const double base = flat_taper_y_base_factor(params, domain, y);
    const int Ny = std::max(1, params.Ny);
    const double h = domain.yMax - domain.yMin;
    if (!(h > 0.0)) return base;
    const double dy = h / static_cast<double>(Ny);
    double meanBase = 0.0;
    for (int j = 0; j < Ny; ++j) {
        const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
        meanBase += flat_taper_y_base_factor(params, domain, yc);
    }
    meanBase /= static_cast<double>(Ny);
    if (!(meanBase > 0.0)) return base;
    return base / meanBase;
}

double inlet_y_profile_factor(const SimulationParams& params,
                              const FluidDomainBounds& domain,
                              double y) {
    const std::string profile = params.inletVelocitySpatialProfile;
    const double h = domain.yMax - domain.yMin;
    if (!(h > 0.0)) return 1.0;
    if (profile == "poiseuille_y" || profile == "poiseuille_y_mean" || profile == "poiseuille_y_max") {
        const double eta = std::clamp((y - domain.yMin) / h, 0.0, 1.0);
        const double shape = eta * (1.0 - eta);
        return profile == "poiseuille_y_max" ? 4.0 * shape : 6.0 * shape;
    }
    if (profile == "flat_taper_y" || profile == "flat_taper_y_mean") {
        return flat_taper_y_mean_factor(params, domain, y);
    }
    return 1.0;
}

struct ApertureInterval { double lo = 0.0; double hi = 0.0; };

ApertureInterval normalize_aperture_interval(double requestedLo, double requestedHi, double domainLo, double domainHi) {
    ApertureInterval a{};
    a.lo = std::clamp(requestedLo, domainLo, domainHi);
    const double hiRaw = requestedHi < 0.0 ? domainHi : requestedHi;
    a.hi = std::clamp(hiRaw, domainLo, domainHi);
    if (a.hi < a.lo) a.hi = a.lo;
    return a;
}

ApertureInterval x_face_aperture_y(const SimulationParams& params, const FluidDomainBounds& domain, const char* face) {
    if (!params.openBoundaryApertureEnable) return {domain.yMin, domain.yMax};
    const std::string f(face);
    if (f == "left") return normalize_aperture_interval(params.leftOpenYMin, params.leftOpenYMax, domain.yMin, domain.yMax);
    if (f == "right") return normalize_aperture_interval(params.rightOpenYMin, params.rightOpenYMax, domain.yMin, domain.yMax);
    return {domain.yMin, domain.yMax};
}

ApertureInterval y_face_aperture_x(const SimulationParams& params, const FluidDomainBounds& domain, const char* face) {
    if (!params.openBoundaryApertureEnable) return {domain.xMin, domain.xMax};
    const std::string f(face);
    if (f == "bottom") return normalize_aperture_interval(params.bottomOpenXMin, params.bottomOpenXMax, domain.xMin, domain.xMax);
    if (f == "top") return normalize_aperture_interval(params.topOpenXMin, params.topOpenXMax, domain.xMin, domain.xMax);
    return {domain.xMin, domain.xMax};
}

bool cell_center_in_interval(double center, const ApertureInterval& a) {
    return center >= a.lo && center <= a.hi;
}

void set_x_boundary_flux_profile(std::vector<double>& profile,
                                 const SimulationParams& params,
                                 const FluidDomainBounds& domain,
                                 double value,
                                 const ApertureInterval& a) {
    profile.assign(static_cast<std::size_t>(params.Ny), 0.0);
    const double dy = (domain.yMax - domain.yMin) / static_cast<double>(std::max(1, params.Ny));
    for (int j = 0; j < params.Ny; ++j) {
        const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
        if (cell_center_in_interval(yc, a)) {
            profile[static_cast<std::size_t>(j)] = value * inlet_y_profile_factor(params, domain, yc);
        }
    }
}

void set_y_boundary_flux_profile(std::vector<double>& profile, int Nx, double xMin, double xMax, double value, const ApertureInterval& a) {
    profile.assign(static_cast<std::size_t>(Nx), 0.0);
    const double dx = (xMax - xMin) / static_cast<double>(std::max(1, Nx));
    for (int i = 0; i < Nx; ++i) {
        const double xc = xMin + (static_cast<double>(i) + 0.5) * dx;
        if (cell_center_in_interval(xc, a)) profile[static_cast<std::size_t>(i)] = value;
    }
}

double mean_profile_value(const std::vector<double>& v, double fallback) {
    if (v.empty()) return fallback;
    double s = 0.0;
    for (const double x : v) s += x;
    return s / static_cast<double>(v.size());
}

std::string normalized_open_boundary_outlet_mode(const SimulationParams& params) {
    std::string m = params.openBoundaryOutletMode;
    std::replace(m.begin(), m.end(), '-', '_');
    return m;
}

bool open_boundary_outlet_mode_is_neumann(const SimulationParams& params) {
    const std::string m = normalized_open_boundary_outlet_mode(params);
    return m == "neumann" || m == "free" ||
           m == "zero_gradient" || m == "zero_normal_gradient";
}

bool open_boundary_outlet_mode_is_hybrid(const SimulationParams& params) {
    const std::string m = normalized_open_boundary_outlet_mode(params);
    return m == "hybrid" || m == "neumann_feedback" || m == "hybrid_feedback";
}

bool open_boundary_outlet_uses_local_base(const SimulationParams& params) {
    return open_boundary_outlet_mode_is_neumann(params) || open_boundary_outlet_mode_is_hybrid(params);
}

double outlet_hybrid_blend(const SimulationParams& params) {
    if (!open_boundary_outlet_mode_is_hybrid(params)) return 0.0;
    return std::max(0.0, std::min(1.0, params.openBoundaryOutletHybridBlend));
}

double outlet_feedback_gain(const SimulationParams& params) {
    if (!open_boundary_outlet_mode_is_hybrid(params)) return 0.0;
    return std::max(0.0, std::min(1.0, params.openBoundaryOutletFeedbackGain));
}

void blend_boundary_profiles(std::vector<double>& localProfile,
                             const std::vector<double>& balancedProfile,
                             double blend) {
    if (blend <= 0.0 || localProfile.empty() || balancedProfile.size() != localProfile.size()) return;
    const double a = std::max(0.0, std::min(1.0, blend));
    for (std::size_t i = 0; i < localProfile.size(); ++i) {
        localProfile[i] = (1.0 - a) * localProfile[i] + a * balancedProfile[i];
    }
}

double x_profile_integral(const std::vector<double>& profile, const SimulationParams& params, const FluidDomainBounds& domain, double fallback) {
    const double height = fluid_domain_height(domain);
    if (profile.empty()) return fallback * height;
    const double dy = height / static_cast<double>(std::max(1, params.Ny));
    return std::accumulate(profile.begin(), profile.end(), 0.0) * dy;
}

double y_profile_integral(const std::vector<double>& profile, const SimulationParams& params, const FluidDomainBounds& domain, double fallback) {
    const double width = fluid_domain_width(domain);
    if (profile.empty()) return fallback * width;
    const double dx = width / static_cast<double>(std::max(1, params.Nx));
    return std::accumulate(profile.begin(), profile.end(), 0.0) * dx;
}

double x_aperture_length(const SimulationParams& params, const FluidDomainBounds& domain, const ApertureInterval& a) {
    const double dy = fluid_domain_height(domain) / static_cast<double>(std::max(1, params.Ny));
    double length = 0.0;
    for (int j = 0; j < params.Ny; ++j) {
        const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
        if (cell_center_in_interval(yc, a)) length += dy;
    }
    return length;
}

double y_aperture_length(const SimulationParams& params, const FluidDomainBounds& domain, const ApertureInterval& a) {
    const double dx = fluid_domain_width(domain) / static_cast<double>(std::max(1, params.Nx));
    double length = 0.0;
    for (int i = 0; i < params.Nx; ++i) {
        const double xc = domain.xMin + (static_cast<double>(i) + 0.5) * dx;
        if (cell_center_in_interval(xc, a)) length += dx;
    }
    return length;
}

void add_uniform_to_x_aperture_profile(std::vector<double>& profile,
                                       const SimulationParams& params,
                                       const FluidDomainBounds& domain,
                                       const ApertureInterval& a,
                                       double delta) {
    if (profile.empty() || delta == 0.0) return;
    const double dy = fluid_domain_height(domain) / static_cast<double>(std::max(1, params.Ny));
    for (int j = 0; j < params.Ny; ++j) {
        const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
        if (cell_center_in_interval(yc, a)) profile[static_cast<std::size_t>(j)] += delta;
    }
}

void add_uniform_to_y_aperture_profile(std::vector<double>& profile,
                                       const SimulationParams& params,
                                       const FluidDomainBounds& domain,
                                       const ApertureInterval& a,
                                       double delta) {
    if (profile.empty() || delta == 0.0) return;
    const double dx = fluid_domain_width(domain) / static_cast<double>(std::max(1, params.Nx));
    for (int i = 0; i < params.Nx; ++i) {
        const double xc = domain.xMin + (static_cast<double>(i) + 0.5) * dx;
        if (cell_center_in_interval(xc, a)) profile[static_cast<std::size_t>(i)] += delta;
    }
}

void set_x_boundary_flux_profile_from_base(std::vector<double>& profile,
                                           const SimulationParams& params,
                                           const FluidDomainBounds& domain,
                                           const PeriodicFaceField& baseFlux,
                                           bool highFace,
                                           const ApertureInterval& a) {
    profile.assign(static_cast<std::size_t>(params.Ny), 0.0);
    const int i = highFace ? (params.Nx - 1) : 0;
    const double dy = (domain.yMax - domain.yMin) / static_cast<double>(std::max(1, params.Ny));
    for (int j = 0; j < params.Ny; ++j) {
        const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
        if (cell_center_in_interval(yc, a)) {
            const int c = i + params.Nx * j;
            profile[static_cast<std::size_t>(j)] = baseFlux.x[static_cast<std::size_t>(c)];
        }
    }
}

void set_y_boundary_flux_profile_from_base(std::vector<double>& profile,
                                           const SimulationParams& params,
                                           const FluidDomainBounds& domain,
                                           const PeriodicFaceField& baseFlux,
                                           bool highFace,
                                           const ApertureInterval& a) {
    profile.assign(static_cast<std::size_t>(params.Nx), 0.0);
    const int j = highFace ? (params.Ny - 1) : 0;
    const double dx = (domain.xMax - domain.xMin) / static_cast<double>(std::max(1, params.Nx));
    for (int i = 0; i < params.Nx; ++i) {
        const double xc = domain.xMin + (static_cast<double>(i) + 0.5) * dx;
        if (cell_center_in_interval(xc, a)) {
            const int c = i + params.Nx * j;
            profile[static_cast<std::size_t>(i)] = baseFlux.y[static_cast<std::size_t>(c)];
        }
    }
}

void apply_hybrid_feedback_to_q9_open_boundaries(EllipticProjectionBC& bc,
                                                  const SimulationParams& params,
                                                  const FluidDomainBounds& domain,
                                                  const ApertureInterval& leftA,
                                                  const ApertureInterval& rightA,
                                                  const ApertureInterval& bottomA,
                                                  const ApertureInterval& topA) {
    const double gain = outlet_feedback_gain(params);
    if (gain <= 0.0) return;

    const bool leftOutlet = is_outlet_boundary_mode(params.bcLeft);
    const bool rightOutlet = is_outlet_boundary_mode(params.bcRight);
    const bool bottomOutlet = is_outlet_boundary_mode(params.bcBottom);
    const bool topOutlet = is_outlet_boundary_mode(params.bcTop);

    const double xLowIntegral = x_profile_integral(bc.xLowFluxProfile, params, domain, bc.xLowFlux);
    const double xHighIntegral = x_profile_integral(bc.xHighFluxProfile, params, domain, bc.xHighFlux);
    const double yLowIntegral = y_profile_integral(bc.yLowFluxProfile, params, domain, bc.yLowFlux);
    const double yHighIntegral = y_profile_integral(bc.yHighFluxProfile, params, domain, bc.yHighFlux);
    const double balance = (xHighIntegral - xLowIntegral) + (yHighIntegral - yLowIntegral);
    if (balance == 0.0) return;

    double outletLength = 0.0;
    if (leftOutlet) outletLength += x_aperture_length(params, domain, leftA);
    if (rightOutlet) outletLength += x_aperture_length(params, domain, rightA);
    if (bottomOutlet) outletLength += y_aperture_length(params, domain, bottomA);
    if (topOutlet) outletLength += y_aperture_length(params, domain, topA);
    if (outletLength <= 0.0) return;

    // Positive balance means net mass flux is leaving the domain in the
    // elliptic sign convention.  The outlet-only correction below reduces this
    // balance by gain*balance while preserving the local Neumann profile up to
    // a weak uniform feedback over all open outlet cells.
    const double perLength = gain * balance / outletLength;
    if (leftOutlet) add_uniform_to_x_aperture_profile(bc.xLowFluxProfile, params, domain, leftA, +perLength);
    if (rightOutlet) add_uniform_to_x_aperture_profile(bc.xHighFluxProfile, params, domain, rightA, -perLength);
    if (bottomOutlet) add_uniform_to_y_aperture_profile(bc.yLowFluxProfile, params, domain, bottomA, +perLength);
    if (topOutlet) add_uniform_to_y_aperture_profile(bc.yHighFluxProfile, params, domain, topA, -perLength);

    bc.xLowFlux = mean_profile_value(bc.xLowFluxProfile, bc.xLowFlux);
    bc.xHighFlux = mean_profile_value(bc.xHighFluxProfile, bc.xHighFlux);
    bc.yLowFlux = mean_profile_value(bc.yLowFluxProfile, bc.yLowFlux);
    bc.yHighFlux = mean_profile_value(bc.yHighFluxProfile, bc.yHighFlux);
}

void add_boundary_mass_fluxes_to_q9_bc(EllipticProjectionBC& bc,
                                       const PeriodicFaceField& baseMassFlux,
                                       const SimulationParams& params,
                                       const FluidDomainBounds& domain,
                                       double time,
                                       double meanCellMass,
                                       Q9ProjectionDiagnostics& diag) {
    if (!is_x_periodic(params)) {
        bc.xLowFlux = meanCellMass * domain.vxMin;
        bc.xHighFlux = meanCellMass * domain.vxMax;
    }
    if (!is_y_periodic(params)) {
        bc.yLowFlux = meanCellMass * domain.vyMin;
        bc.yHighFlux = meanCellMass * domain.vyMax;
    }

    // Open-boundary mass-flux policy.  The validated default
    // openBoundaryOutletMode=balanced_flux prescribes the ramped inlet velocity
    // times the current mean cell mass on both open faces.  Neumann samples the
    // outlet mass flux from the current base face field.  Hybrid starts from
    // Neumann, optionally blends toward balanced_flux, then applies an
    // outlet-only weak feedback that reduces the global open-boundary mass-flux
    // imbalance.
    ApertureInterval leftA{0.0, 0.0};
    ApertureInterval rightA{0.0, 0.0};
    ApertureInterval bottomA{0.0, 0.0};
    ApertureInterval topA{0.0, 0.0};

    if (has_x_io_pair(params)) {
        const double jx = meanCellMass * q9_open_x_velocity_component(params, time);
        const bool localOutlet = open_boundary_outlet_uses_local_base(params);
        const bool hybridOutlet = open_boundary_outlet_mode_is_hybrid(params);
        const double blend = outlet_hybrid_blend(params);
        const bool leftInlet = is_inlet_boundary_mode(params.bcLeft);
        const bool rightInlet = is_inlet_boundary_mode(params.bcRight);
        leftA = x_face_aperture_y(params, domain, "left");
        rightA = x_face_aperture_y(params, domain, "right");

        if (leftInlet || !localOutlet) {
            bc.xLowFlux = jx;
            if (params.openBoundaryApertureEnable || params.inletVelocitySpatialProfile != "uniform") {
                set_x_boundary_flux_profile(bc.xLowFluxProfile, params, domain, jx, leftA);
                bc.xLowFlux = mean_profile_value(bc.xLowFluxProfile, jx);
            }
        } else {
            set_x_boundary_flux_profile_from_base(bc.xLowFluxProfile, params, domain, baseMassFlux, false, leftA);
            if (hybridOutlet && blend > 0.0) {
                std::vector<double> balanced;
                set_x_boundary_flux_profile(balanced, params, domain, jx, leftA);
                blend_boundary_profiles(bc.xLowFluxProfile, balanced, blend);
            }
            bc.xLowFlux = mean_profile_value(bc.xLowFluxProfile, 0.0);
        }

        if (rightInlet || !localOutlet) {
            bc.xHighFlux = jx;
            if (params.openBoundaryApertureEnable || params.inletVelocitySpatialProfile != "uniform") {
                set_x_boundary_flux_profile(bc.xHighFluxProfile, params, domain, jx, rightA);
                bc.xHighFlux = mean_profile_value(bc.xHighFluxProfile, jx);
            }
        } else {
            set_x_boundary_flux_profile_from_base(bc.xHighFluxProfile, params, domain, baseMassFlux, true, rightA);
            if (hybridOutlet && blend > 0.0) {
                std::vector<double> balanced;
                set_x_boundary_flux_profile(balanced, params, domain, jx, rightA);
                blend_boundary_profiles(bc.xHighFluxProfile, balanced, blend);
            }
            bc.xHighFlux = mean_profile_value(bc.xHighFluxProfile, 0.0);
        }

        diag.openBoundaryEnabled = true;
    }
    if (has_y_io_pair(params)) {
        const double jy = meanCellMass * q9_open_y_velocity_component(params, time);
        const bool localOutlet = open_boundary_outlet_uses_local_base(params);
        const bool hybridOutlet = open_boundary_outlet_mode_is_hybrid(params);
        const double blend = outlet_hybrid_blend(params);
        const bool bottomInlet = is_inlet_boundary_mode(params.bcBottom);
        const bool topInlet = is_inlet_boundary_mode(params.bcTop);
        bottomA = y_face_aperture_x(params, domain, "bottom");
        topA = y_face_aperture_x(params, domain, "top");

        if (bottomInlet || !localOutlet) {
            bc.yLowFlux = jy;
            if (params.openBoundaryApertureEnable) {
                set_y_boundary_flux_profile(bc.yLowFluxProfile, params.Nx, domain.xMin, domain.xMax, jy, bottomA);
                bc.yLowFlux = mean_profile_value(bc.yLowFluxProfile, jy);
            }
        } else {
            set_y_boundary_flux_profile_from_base(bc.yLowFluxProfile, params, domain, baseMassFlux, false, bottomA);
            if (hybridOutlet && blend > 0.0) {
                std::vector<double> balanced;
                set_y_boundary_flux_profile(balanced, params.Nx, domain.xMin, domain.xMax, jy, bottomA);
                blend_boundary_profiles(bc.yLowFluxProfile, balanced, blend);
            }
            bc.yLowFlux = mean_profile_value(bc.yLowFluxProfile, 0.0);
        }

        if (topInlet || !localOutlet) {
            bc.yHighFlux = jy;
            if (params.openBoundaryApertureEnable) {
                set_y_boundary_flux_profile(bc.yHighFluxProfile, params.Nx, domain.xMin, domain.xMax, jy, topA);
                bc.yHighFlux = mean_profile_value(bc.yHighFluxProfile, jy);
            }
        } else {
            set_y_boundary_flux_profile_from_base(bc.yHighFluxProfile, params, domain, baseMassFlux, true, topA);
            if (hybridOutlet && blend > 0.0) {
                std::vector<double> balanced;
                set_y_boundary_flux_profile(balanced, params.Nx, domain.xMin, domain.xMax, jy, topA);
                blend_boundary_profiles(bc.yHighFluxProfile, balanced, blend);
            }
            bc.yHighFlux = mean_profile_value(bc.yHighFluxProfile, 0.0);
        }

        diag.openBoundaryEnabled = true;
    }

    if (open_boundary_outlet_mode_is_hybrid(params)) {
        apply_hybrid_feedback_to_q9_open_boundaries(bc, params, domain, leftA, rightA, bottomA, topA);
    }

    diag.openBoundaryMassFluxXLow = bc.xLowFlux;
    diag.openBoundaryMassFluxXHigh = bc.xHighFlux;
    diag.openBoundaryMassFluxYLow = bc.yLowFlux;
    diag.openBoundaryMassFluxYHigh = bc.yHighFlux;

    const double width = fluid_domain_width(domain);
    const double height = fluid_domain_height(domain);
    const double xLowIntegral = bc.xLowFluxProfile.empty() ? bc.xLowFlux * height :
        std::accumulate(bc.xLowFluxProfile.begin(), bc.xLowFluxProfile.end(), 0.0) * (height / static_cast<double>(params.Ny));
    const double xHighIntegral = bc.xHighFluxProfile.empty() ? bc.xHighFlux * height :
        std::accumulate(bc.xHighFluxProfile.begin(), bc.xHighFluxProfile.end(), 0.0) * (height / static_cast<double>(params.Ny));
    const double yLowIntegral = bc.yLowFluxProfile.empty() ? bc.yLowFlux * width :
        std::accumulate(bc.yLowFluxProfile.begin(), bc.yLowFluxProfile.end(), 0.0) * (width / static_cast<double>(params.Nx));
    const double yHighIntegral = bc.yHighFluxProfile.empty() ? bc.yHighFlux * width :
        std::accumulate(bc.yHighFluxProfile.begin(), bc.yHighFluxProfile.end(), 0.0) * (width / static_cast<double>(params.Nx));
    diag.openBoundaryMassFluxBalance = (xHighIntegral - xLowIntegral) + (yHighIntegral - yLowIntegral);
    const double area = width * height;
    diag.openBoundaryMeanDivergence = area > 0.0 ? diag.openBoundaryMassFluxBalance / area : 0.0;
}

void deposit_cell_mass_momentum(const ParticleState& state,
                                const SimulationParams& params,
                                const CellGrid& grid,
                                const FluidDomainBounds& domain,
                                Q9ProjectionWorkspace& ws,
                                Q9ProjectionDiagnostics& diag) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());

    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.cellPx.begin(), ws.cellPx.end(), 0.0);
    std::fill(ws.cellPy.begin(), ws.cellPy.end(), 0.0);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.localPx.begin(), ws.localPx.end(), 0.0);
    std::fill(ws.localPy.begin(), ws.localPy.end(), 0.0);

#pragma omp parallel
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);

#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            const int c = active_domain_cell_index(state.x[i], state.y[i], domain, params);
            ws.cellId[i] = c;
            const std::size_t k = offset + static_cast<std::size_t>(c);
            const double m = state.mass[i];
            ws.localMass[k] += m;
            ws.localPx[k] += m * state.vx[i];
            ws.localPy[k] += m * state.vy[i];
        }
    }

    std::uint64_t empty = 0u;
#pragma omp parallel for reduction(+:empty) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        double m = 0.0;
        double px = 0.0;
        double py = 0.0;
        for (int t = 0; t < nt; ++t) {
            const std::size_t k = static_cast<std::size_t>(t * nc + c);
            m += ws.localMass[k];
            px += ws.localPx[k];
            py += ws.localPy[k];
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        ws.cellMass[kk] = m;
        ws.cellPx[kk] = px;
        ws.cellPy[kk] = py;
        if (!(m > 0.0)) {
            ++empty;
        }
    }
    diag.emptyCells = empty;
}

void build_mass_flux_from_cell_momentum(const CellGrid& grid,
                                        const std::vector<double>& px,
                                        const std::vector<double>& py,
                                        PeriodicFaceField& flux) {
    const int nc = grid.numCells;
    if (static_cast<int>(px.size()) != nc || static_cast<int>(py.size()) != nc) {
        throw std::runtime_error("build_mass_flux_from_cell_momentum: invalid array size");
    }
    resize_periodic_face_field(flux, nc);
#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        flux.x[k] = px[k];
        flux.y[k] = py[k];
    }
}

void fill_alpha(PeriodicFaceField& alpha, int numCells, double value) {
    resize_periodic_face_field(alpha, numCells);
    std::fill(alpha.x.begin(), alpha.x.end(), value);
    std::fill(alpha.y.begin(), alpha.y.end(), value);
}

int q9_cell_index(int i, int j, int Nx) {
    return i + Nx * j;
}

void initialize_all_active_mask(EllipticProjectionMask& mask, int nc) {
    mask.activeCell.assign(static_cast<std::size_t>(nc), 1u);
    mask.activeCells = static_cast<std::uint64_t>(std::max(0, nc));
    mask.inactiveCells = 0u;
}

bool deactivate_q9_cell(EllipticProjectionMask& mask, int c) {
    const std::size_t k = static_cast<std::size_t>(c);
    if (mask.activeCell[k] == 0u) {
        return false;
    }
    mask.activeCell[k] = 0u;
    return true;
}

void recount_q9_mask(EllipticProjectionMask& mask) {
    std::uint64_t active = 0u;
    for (const std::uint8_t v : mask.activeCell) {
        if (v != 0u) ++active;
    }
    mask.activeCells = active;
    mask.inactiveCells = static_cast<std::uint64_t>(mask.activeCell.size()) - active;
}

bool q9_safety_mask_requested(const SimulationParams& params) {
    return params.q9OpenBoundaryExclusionCells > 0 || params.q9ImmersedSolidHaloCells > 0;
}

void apply_q9_open_boundary_exclusion(const SimulationParams& params,
                                      const CellGrid& grid,
                                      const FluidDomainBounds& domain,
                                      EllipticProjectionMask& mask,
                                      Q9ProjectionDiagnostics& diag) {
    const int n = std::max(0, params.q9OpenBoundaryExclusionCells);
    if (n <= 0) return;

    std::uint64_t changed = 0u;
    if (has_x_io_pair(params)) {
        const int w = std::min(n, grid.Nx);
        const double dy = fluid_domain_height(domain) / static_cast<double>(std::max(1, grid.Ny));
        for (int j = 0; j < grid.Ny; ++j) {
            const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
            const bool leftOpen = cell_center_in_interval(yc, x_face_aperture_y(params, domain, "left"));
            const bool rightOpen = cell_center_in_interval(yc, x_face_aperture_y(params, domain, "right"));
            if (leftOpen) {
                for (int i = 0; i < w; ++i) {
                    if (deactivate_q9_cell(mask, q9_cell_index(i, j, grid.Nx))) ++changed;
                }
            }
            if (rightOpen) {
                for (int i = std::max(0, grid.Nx - w); i < grid.Nx; ++i) {
                    if (deactivate_q9_cell(mask, q9_cell_index(i, j, grid.Nx))) ++changed;
                }
            }
        }
    }
    if (has_y_io_pair(params)) {
        const int w = std::min(n, grid.Ny);
        const double dx = fluid_domain_width(domain) / static_cast<double>(std::max(1, grid.Nx));
        for (int i = 0; i < grid.Nx; ++i) {
            const double xc = domain.xMin + (static_cast<double>(i) + 0.5) * dx;
            const bool bottomOpen = cell_center_in_interval(xc, y_face_aperture_x(params, domain, "bottom"));
            const bool topOpen = cell_center_in_interval(xc, y_face_aperture_x(params, domain, "top"));
            if (bottomOpen) {
                for (int j = 0; j < w; ++j) {
                    if (deactivate_q9_cell(mask, q9_cell_index(i, j, grid.Nx))) ++changed;
                }
            }
            if (topOpen) {
                for (int j = std::max(0, grid.Ny - w); j < grid.Ny; ++j) {
                    if (deactivate_q9_cell(mask, q9_cell_index(i, j, grid.Nx))) ++changed;
                }
            }
        }
    }
    diag.openBoundaryExcludedCells = changed;
}

void apply_q9_immersed_halo_exclusion(const SimulationParams& params,
                                      const CellGrid& grid,
                                      Q9ProjectionWorkspace& ws,
                                      Q9ProjectionDiagnostics& diag) {
    const int halo = std::max(0, params.q9ImmersedSolidHaloCells);
    if (halo <= 0 || ws.immersedMask.activeCell.empty()) return;

    const int nc = grid.numCells;
    std::vector<std::uint8_t> blocked(static_cast<std::size_t>(nc), 0u);
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        blocked[k] = ws.immersedMask.activeCell[k] == 0u ? 1u : 0u;
    }

    std::vector<std::uint8_t> next = blocked;
    for (int pass = 0; pass < halo; ++pass) {
        next = blocked;
        for (int j = 0; j < grid.Ny; ++j) {
            for (int i = 0; i < grid.Nx; ++i) {
                const int c = q9_cell_index(i, j, grid.Nx);
                const std::size_t k = static_cast<std::size_t>(c);
                if (blocked[k] != 0u) continue;
                bool nearBlocked = false;
                if (i > 0 && blocked[static_cast<std::size_t>(q9_cell_index(i - 1, j, grid.Nx))] != 0u) nearBlocked = true;
                if (i + 1 < grid.Nx && blocked[static_cast<std::size_t>(q9_cell_index(i + 1, j, grid.Nx))] != 0u) nearBlocked = true;
                if (j > 0 && blocked[static_cast<std::size_t>(q9_cell_index(i, j - 1, grid.Nx))] != 0u) nearBlocked = true;
                if (j + 1 < grid.Ny && blocked[static_cast<std::size_t>(q9_cell_index(i, j + 1, grid.Nx))] != 0u) nearBlocked = true;
                if (nearBlocked) next[k] = 1u;
            }
        }
        blocked.swap(next);
    }

    std::uint64_t changed = 0u;
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (blocked[k] != 0u && ws.immersedMask.activeCell[k] != 0u) {
            if (deactivate_q9_cell(ws.ellipticMask, c)) ++changed;
        }
    }
    diag.immersedHaloExcludedCells = changed;
}

const EllipticProjectionMask* prepare_q9_projection_mask(const SimulationParams& params,
                                                         const CellGrid& grid,
                                                         const FluidDomainBounds& domain,
                                                         double time,
                                                         Q9ProjectionWorkspace& ws,
                                                         Q9ProjectionDiagnostics& diag) {
    const bool hasImmersedMask = params.immersedSolidEnable && params.projectionImmersedSolidMaskEnable;
    const bool hasSafetyMask = q9_safety_mask_requested(params);
    if (!hasImmersedMask && !hasSafetyMask) {
        return nullptr;
    }

    if (hasImmersedMask) {
        ws.immersedMask = build_immersed_solid_projection_mask(
            params, grid, domain, time, params.projectionImmersedSolidFluidFractionThreshold);
        ws.ellipticMask.activeCell = ws.immersedMask.activeCell;
        ws.ellipticMask.activeCells = ws.immersedMask.fluidCells;
        ws.ellipticMask.inactiveCells = ws.immersedMask.solidCells;
        diag.immersedSolidFluidCells = ws.immersedMask.fluidCells;
        diag.immersedSolidSolidCells = ws.immersedMask.solidCells;
        diag.immersedSolidCutCells = ws.immersedMask.cutCells;
        diag.immersedSolidActiveCutCells = ws.immersedMask.activeCutCells;
        diag.immersedSolidActiveAdjacentCells = ws.immersedMask.activeSolidAdjacentCells;
        diag.immersedSolidClosedXFaces = ws.immersedMask.closedXFaces;
        diag.immersedSolidClosedYFaces = ws.immersedMask.closedYFaces;
        diag.immersedSolidCellClosedXFaces = ws.immersedMask.cellClosedXFaces;
        diag.immersedSolidCellClosedYFaces = ws.immersedMask.cellClosedYFaces;
        diag.immersedSolidCutClosedXFaces = ws.immersedMask.cutClosedXFaces;
        diag.immersedSolidCutClosedYFaces = ws.immersedMask.cutClosedYFaces;
    } else {
        initialize_all_active_mask(ws.ellipticMask, grid.numCells);
    }

    apply_q9_open_boundary_exclusion(params, grid, domain, ws.ellipticMask, diag);
    apply_q9_immersed_halo_exclusion(params, grid, ws, diag);
    recount_q9_mask(ws.ellipticMask);
    diag.safetyActiveCells = ws.ellipticMask.activeCells;
    diag.safetyExcludedCells = ws.ellipticMask.inactiveCells;
    return &ws.ellipticMask;
}

void apply_immersed_face_alpha(const ImmersedSolidProjectionMask& mask,
                               PeriodicFaceField& alpha) {
    if (mask.activeCell.empty()) return;
    const std::size_t n = mask.activeCell.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        alpha.x[k] *= mask.faceOpen.x[k];
        alpha.y[k] *= mask.faceOpen.y[k];
    }
}

bool mask_active(const EllipticProjectionMask* mask, std::size_t k) {
    return !mask || mask->activeCell[k] != 0u;
}

struct Q9SolidLeakStats {
    std::uint64_t faceCount = 0u;
    double sum2 = 0.0;
    double maxAbs = 0.0;
    std::uint64_t cellFaceCount = 0u;
    double cellSum2 = 0.0;
    double cellMaxAbs = 0.0;
    std::uint64_t cutFaceCount = 0u;
    double cutSum2 = 0.0;
    double cutMaxAbs = 0.0;
};

inline bool q9_face_is_immersed_boundary(const ImmersedSolidProjectionMask& mask,
                                         int owner,
                                         int neighbour,
                                         bool xFace) {
    const std::size_t k = static_cast<std::size_t>(owner);
    const bool cutClosed = xFace ? (!mask.faceClosedByCutX.empty() && mask.faceClosedByCutX[k] != 0u)
                                 : (!mask.faceClosedByCutY.empty() && mask.faceClosedByCutY[k] != 0u);
    if (cutClosed) {
        return true;
    }
    const bool cellClosed = xFace ? (!mask.faceClosedByCellX.empty() && mask.faceClosedByCellX[k] != 0u)
                                  : (!mask.faceClosedByCellY.empty() && mask.faceClosedByCellY[k] != 0u);
    if (!cellClosed) {
        return false;
    }
    const bool a = mask.activeCell[static_cast<std::size_t>(owner)] != 0u;
    const bool b = mask.activeCell[static_cast<std::size_t>(neighbour)] != 0u;
    return a != b;
}

void accumulate_q9_solid_leak_value(Q9SolidLeakStats& stats,
                                    double value,
                                    bool cutClosed) {
    const double a = std::abs(value);
    stats.sum2 += a * a;
    stats.maxAbs = std::max(stats.maxAbs, a);
    stats.faceCount += 1u;
    if (cutClosed) {
        stats.cutSum2 += a * a;
        stats.cutMaxAbs = std::max(stats.cutMaxAbs, a);
        stats.cutFaceCount += 1u;
    } else {
        stats.cellSum2 += a * a;
        stats.cellMaxAbs = std::max(stats.cellMaxAbs, a);
        stats.cellFaceCount += 1u;
    }
}

Q9SolidLeakStats measure_q9_solid_boundary_leak(const PeriodicFaceField& projectedMassFlux,
                                                const ImmersedSolidProjectionMask& mask,
                                                const SimulationParams& params) {
    Q9SolidLeakStats stats{};
    if (mask.activeCell.empty()) return stats;
    const int Nx = std::max(1, params.Nx);
    const int Ny = std::max(1, params.Ny);
    const bool periodicX = is_x_periodic(params);
    const bool periodicY = is_y_periodic(params);

    double sum2 = 0.0;
    double maxAbs = 0.0;
    double cellSum2 = 0.0;
    double cellMaxAbs = 0.0;
    double cutSum2 = 0.0;
    double cutMaxAbs = 0.0;
    std::uint64_t count = 0u;
    std::uint64_t cellCount = 0u;
    std::uint64_t cutCount = 0u;
#pragma omp parallel for reduction(+:sum2,count,cellSum2,cellCount,cutSum2,cutCount) reduction(max:maxAbs,cellMaxAbs,cutMaxAbs) if(Nx * Ny > 4096)
    for (int j = 0; j < Ny; ++j) {
        for (int i = 0; i < Nx; ++i) {
            const int c = q9_cell_index(i, j, Nx);
            const std::size_t k = static_cast<std::size_t>(c);

            if (periodicX || i < Nx - 1) {
                const int ip = periodicX ? ((i + 1) % Nx) : (i + 1);
                const int e = q9_cell_index(ip, j, Nx);
                if (q9_face_is_immersed_boundary(mask, c, e, true)) {
                    const bool cutClosed = !mask.faceClosedByCutX.empty() && mask.faceClosedByCutX[k] != 0u;
                    const double a = std::abs(projectedMassFlux.x[k]);
                    sum2 += a * a;
                    maxAbs = std::max(maxAbs, a);
                    count += 1u;
                    if (cutClosed) {
                        cutSum2 += a * a;
                        cutMaxAbs = std::max(cutMaxAbs, a);
                        cutCount += 1u;
                    } else {
                        cellSum2 += a * a;
                        cellMaxAbs = std::max(cellMaxAbs, a);
                        cellCount += 1u;
                    }
                }
            }

            if (periodicY || j < Ny - 1) {
                const int jp = periodicY ? ((j + 1) % Ny) : (j + 1);
                const int n = q9_cell_index(i, jp, Nx);
                if (q9_face_is_immersed_boundary(mask, c, n, false)) {
                    const bool cutClosed = !mask.faceClosedByCutY.empty() && mask.faceClosedByCutY[k] != 0u;
                    const double a = std::abs(projectedMassFlux.y[k]);
                    sum2 += a * a;
                    maxAbs = std::max(maxAbs, a);
                    count += 1u;
                    if (cutClosed) {
                        cutSum2 += a * a;
                        cutMaxAbs = std::max(cutMaxAbs, a);
                        cutCount += 1u;
                    } else {
                        cellSum2 += a * a;
                        cellMaxAbs = std::max(cellMaxAbs, a);
                        cellCount += 1u;
                    }
                }
            }
        }
    }
    stats.faceCount = count;
    stats.sum2 = sum2;
    stats.maxAbs = maxAbs;
    stats.cellFaceCount = cellCount;
    stats.cellSum2 = cellSum2;
    stats.cellMaxAbs = cellMaxAbs;
    stats.cutFaceCount = cutCount;
    stats.cutSum2 = cutSum2;
    stats.cutMaxAbs = cutMaxAbs;
    return stats;
}

void store_q9_solid_leak_stats(const Q9SolidLeakStats& stats,
                               Q9ProjectionDiagnostics& diag) {
    diag.immersedSolidLeakFaceCount = stats.faceCount;
    diag.immersedSolidLeakMassFluxRms = stats.faceCount > 0u ?
        std::sqrt(stats.sum2 / static_cast<double>(stats.faceCount)) : 0.0;
    diag.immersedSolidLeakMassFluxMaxAbs = stats.maxAbs;
    diag.immersedSolidLeakCellClosedMassFluxRms = stats.cellFaceCount > 0u ?
        std::sqrt(stats.cellSum2 / static_cast<double>(stats.cellFaceCount)) : 0.0;
    diag.immersedSolidLeakCellClosedMassFluxMaxAbs = stats.cellMaxAbs;
    diag.immersedSolidLeakCutMassFluxRms = stats.cutFaceCount > 0u ?
        std::sqrt(stats.cutSum2 / static_cast<double>(stats.cutFaceCount)) : 0.0;
    diag.immersedSolidLeakCutMassFluxMaxAbs = stats.cutMaxAbs;
}

void compute_q9_solid_leak(const PeriodicFaceField& projectedMassFlux,
                           const ImmersedSolidProjectionMask& mask,
                           const SimulationParams& params,
                           Q9ProjectionDiagnostics& diag) {
    store_q9_solid_leak_stats(measure_q9_solid_boundary_leak(projectedMassFlux, mask, params), diag);
}

void enforce_q9_immersed_closed_face_flux(const SimulationParams& params,
                                          Q9ProjectionWorkspace& ws,
                                          Q9ProjectionDiagnostics& diag) {
    const ImmersedSolidProjectionMask& mask = ws.immersedMask;
    if (mask.activeCell.empty()) return;
    const int Nx = std::max(1, params.Nx);
    const int Ny = std::max(1, params.Ny);
    const bool periodicX = is_x_periodic(params);
    const bool periodicY = is_y_periodic(params);

    const Q9SolidLeakStats before = measure_q9_solid_boundary_leak(ws.projectedMassFlux, mask, params);
    diag.immersedSolidAppliedLeakBeforeClosureRms = before.faceCount > 0u ?
        std::sqrt(before.sum2 / static_cast<double>(before.faceCount)) : 0.0;
    diag.immersedSolidAppliedLeakBeforeClosureMaxAbs = before.maxAbs;

    double sum2 = 0.0;
    double maxAbs = 0.0;
    std::uint64_t count = 0u;
#pragma omp parallel for reduction(+:sum2,count) reduction(max:maxAbs) if(Nx * Ny > 4096)
    for (int j = 0; j < Ny; ++j) {
        for (int i = 0; i < Nx; ++i) {
            const int c = q9_cell_index(i, j, Nx);
            const std::size_t k = static_cast<std::size_t>(c);
            if (periodicX || i < Nx - 1) {
                const int ip = periodicX ? ((i + 1) % Nx) : (i + 1);
                const int e = q9_cell_index(ip, j, Nx);
                if (q9_face_is_immersed_boundary(mask, c, e, true)) {
                    const double a = std::abs(ws.projectedMassFlux.x[k]);
                    sum2 += a * a;
                    maxAbs = std::max(maxAbs, a);
                    count += 1u;
                    ws.appliedCorrectionFlux.x[k] = -ws.baseMassFlux.x[k];
                    ws.projectedMassFlux.x[k] = 0.0;
                }
            }
            if (periodicY || j < Ny - 1) {
                const int jp = periodicY ? ((j + 1) % Ny) : (j + 1);
                const int n = q9_cell_index(i, jp, Nx);
                if (q9_face_is_immersed_boundary(mask, c, n, false)) {
                    const double a = std::abs(ws.projectedMassFlux.y[k]);
                    sum2 += a * a;
                    maxAbs = std::max(maxAbs, a);
                    count += 1u;
                    ws.appliedCorrectionFlux.y[k] = -ws.baseMassFlux.y[k];
                    ws.projectedMassFlux.y[k] = 0.0;
                }
            }
        }
    }
    diag.immersedSolidClosedFaceFluxEnforcedFaces = count;
    diag.immersedSolidClosedFaceFluxEnforcedRms = count > 0u ?
        std::sqrt(sum2 / static_cast<double>(count)) : 0.0;
    diag.immersedSolidClosedFaceFluxEnforcedMaxAbs = maxAbs;
}


std::string canonical_filter_name(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    std::replace(s.begin(), s.end(), '-', '_');
    return s;
}

bool q9_target_filter_is_none(const SimulationParams& params) {
    const std::string f = canonical_filter_name(params.q9TargetFilter);
    return f == "none" || f == "off" || f == "identity" || f == "raw";
}

bool q9_target_filter_is_elliptic_lowpass(const SimulationParams& params) {
    const std::string f = canonical_filter_name(params.q9TargetFilter);
    return f == "elliptic_lowpass" || f == "operator_lowpass" ||
           f == "lowpass_operator" || f == "lowpass_elliptic" ||
           f == "lowk_elliptic";
}

double vector_mean(const std::vector<double>& v, const EllipticProjectionMask* mask = nullptr) {
    if (v.empty()) return 0.0;
    double sum = 0.0;
    std::uint64_t count = 0u;
    const std::size_t n = v.size();
#pragma omp parallel for reduction(+:sum,count) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        if (!mask_active(mask, k)) continue;
        sum += v[k];
        count += 1u;
    }
    return count > 0u ? sum / static_cast<double>(count) : 0.0;
}

void subtract_vector_mean(std::vector<double>& v, const EllipticProjectionMask* mask = nullptr) {
    const double m = vector_mean(v, mask);
    const std::size_t n = v.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        if (mask_active(mask, k)) v[k] -= m;
        else v[k] = 0.0;
    }
}

double vector_rms(const std::vector<double>& v, const EllipticProjectionMask* mask = nullptr) {
    if (v.empty()) return 0.0;
    double sum2 = 0.0;
    std::uint64_t count = 0u;
    const std::size_t n = v.size();
#pragma omp parallel for reduction(+:sum2,count) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        if (!mask_active(mask, k)) continue;
        const double a = v[k];
        sum2 += a * a;
        count += 1u;
    }
    return count > 0u ? std::sqrt(sum2 / static_cast<double>(count)) : 0.0;
}


EllipticLowPassParams make_q9_lowpass_params(const SimulationParams& params,
                                             const EllipticProjectionGrid& egrid) {
    const int nc = egrid.numCells;
    const double nApprox = std::sqrt(static_cast<double>(std::max(1, nc)));
    const double denom = std::max(1.0, 2.0 * static_cast<double>(params.q9LowKMaxIndex) + 1.0);
    const double lenCells = params.q9EllipticLowPassLengthCells > 0.0
        ? params.q9EllipticLowPassLengthCells
        : std::max(1.0, nApprox / denom);
    const double ell = lenCells * 0.5 * (egrid.dx + egrid.dy);

    EllipticLowPassParams filterParams{};
    filterParams.passes = std::max(0, params.q9EllipticLowPassPasses);
    filterParams.length = ell;
    filterParams.maxIterations = std::max(1, params.projectionMaxIterations);
    filterParams.tolerance = std::max(0.0, params.projectionTolerance);
    filterParams.removeMeanEachPass = true;
    return filterParams;
}

bool q9_lowk_correction_only(const SimulationParams& params) {
    return !q9_target_filter_is_none(params) && params.q9EllipticLowPassPasses != 0;
}

void apply_q9_target_filter(const SimulationParams& params,
                            const EllipticProjectionGrid& egrid,
                            const EllipticProjectionBC& bc,
                            const PeriodicFaceField& alpha,
                            const EllipticProjectionMask* mask,
                            std::vector<double>& target,
                            Q9ProjectionWorkspace& ws,
                            Q9ProjectionDiagnostics& diag) {
    subtract_vector_mean(target, mask);
    diag.targetDivergenceRawRms = vector_rms(target, mask);
    if (q9_target_filter_is_none(params) || params.q9EllipticLowPassPasses == 0) {
        diag.targetDivergenceRms = diag.targetDivergenceRawRms;
        diag.targetDivergenceFilterRatio = 1.0;
        return;
    }
    if (!q9_target_filter_is_elliptic_lowpass(params)) {
        throw std::runtime_error("Unsupported q9TargetFilter in Q9 adapter: " + params.q9TargetFilter);
    }

    const EllipticLowPassParams filterParams = make_q9_lowpass_params(params, egrid);

    EllipticLowPassDiagnostics filterDiag{};
    target = elliptic_lowpass_cell_field(egrid, target, alpha, filterParams, bc, ws.elliptic, &filterDiag, mask);

    diag.targetDivergenceRms = filterDiag.outputRms;
    diag.targetDivergenceFilterRatio = filterDiag.filterRatio;
}

void build_uniform_density_relaxation_target(const SimulationParams& params,
                                             const FluidDomainBounds& domain,
                                             const std::vector<double>& cellMass,
                                             const EllipticProjectionMask* mask,
                                             std::vector<double>& target,
                                             Q9ProjectionDiagnostics& diag) {
    const int nc = static_cast<int>(cellMass.size());
    target.assign(static_cast<std::size_t>(nc), 0.0);
    if (nc <= 0) {
        return;
    }

    double sum = 0.0;
    double sum2 = 0.0;
    std::uint64_t count = 0u;
#pragma omp parallel for reduction(+:sum,sum2,count) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (!mask_active(mask, k)) continue;
        const double m = cellMass[k];
        sum += m;
        sum2 += m * m;
        count += 1u;
    }
    const double mean = count > 0u ? sum / static_cast<double>(count) : 0.0;
    const double var = count > 0u ? std::max(0.0, sum2 / static_cast<double>(count) - mean * mean) : 0.0;
    diag.densityMean = mean;
    diag.densityStdBefore = std::sqrt(var);

    const double beta = params.q9DensityRelaxationBeta;
    const double invDt = 1.0 / params.dt;
    const double domainRate = active_domain_divergence_rate(domain);
#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        // Positive target divergence lowers cell mass in the continuity estimate
        // M_new = M - dt div(J). The uniform moving-domain term preserves the
        // expected mean compression/expansion induced by moving active-domain walls.
        target[k] = mask_active(mask, k) ? (mean * domainRate + beta * invDt * (cellMass[k] - mean)) : 0.0;
    }
    diag.targetDivergenceRawRms = vector_rms(target, mask);
    diag.targetDivergenceRms = diag.targetDivergenceRawRms;
    diag.targetDivergenceFilterRatio = 1.0;
}

double face_strength_for_q9(double requestedStrength,
                            const ImmersedSolidProjectionMask* immersedMask,
                            bool xFace,
                            std::size_t k) {
    if (immersedMask != nullptr && !immersedMask->faceOpen.x.empty()) {
        const double open = xFace ? immersedMask->faceOpen.x[k] : immersedMask->faceOpen.y[k];
        if (open == 0.0) {
            return 1.0;
        }
    }
    return requestedStrength;
}

double q9_reference_gamma_for_thresholds(const SimulationParams& params) {
    if (params.q9ReferenceGamma > 0.0) {
        return params.q9ReferenceGamma;
    }
    if (params.inletTargetOccupancy > 0) {
        return static_cast<double>(params.inletTargetOccupancy);
    }
    return 0.0;
}

double q9_effective_mass_threshold(double absoluteValue,
                                   double overGammaValue,
                                   const SimulationParams& params,
                                   const char* keyName) {
    if (overGammaValue < 0.0) {
        return std::max(0.0, absoluteValue);
    }
    const double gammaRef = q9_reference_gamma_for_thresholds(params);
    if (!(gammaRef > 0.0)) {
        throw std::runtime_error(std::string(keyName) +
                                 " requires q9ReferenceGamma>0 or inletTargetOccupancy>0");
    }
    return overGammaValue * gammaRef;
}

struct Q9VelocityLimiterConfig {
    std::string mode = "absolute";
    double limit = 0.0;
    bool soft = false;
};

double q9_reference_kbt_for_velocity_limiter(const SimulationParams& params) {
    if (params.q9CorrectionLimiterThermalKBT > 0.0) {
        return params.q9CorrectionLimiterThermalKBT;
    }
    if (params.thermostatTargetKBT > 0.0) {
        return params.thermostatTargetKBT;
    }
    return params.kBT;
}

Q9VelocityLimiterConfig q9_velocity_limiter_config(const SimulationParams& params) {
    Q9VelocityLimiterConfig cfg;
    cfg.mode = canonical_filter_name(params.q9CorrectionLimiterMode);
    if (cfg.mode == "off") {
        cfg.mode = "none";
    }
    if (cfg.mode == "absolute_hard") {
        cfg.mode = "absolute";
    }

    if (cfg.mode == "none") {
        cfg.limit = 0.0;
        cfg.soft = false;
        return cfg;
    }

    if (cfg.mode == "thermal_soft" || cfg.mode == "thermal_hard") {
        const double kBTRef = q9_reference_kbt_for_velocity_limiter(params);
        if (!(kBTRef > 0.0)) {
            throw std::runtime_error("thermal Q9 limiter requires q9CorrectionLimiterThermalKBT>0, thermostatTargetKBT>0, or kBT>0");
        }
        cfg.limit = std::max(0.0, params.q9CorrectionVelocityLimiterOverThermal) * std::sqrt(kBTRef);
        cfg.soft = (cfg.mode == "thermal_soft");
        return cfg;
    }

    // Legacy absolute hard cap.  A zero value means no limiter, preserving old
    // behaviour for parameter files that set q9CorrectionVelocityLimiter=0.
    cfg.mode = "absolute";
    cfg.limit = std::max(0.0, params.q9CorrectionVelocityLimiter);
    cfg.soft = false;
    return cfg;
}

void correction_flux_to_velocity_kick(const PeriodicFaceField& correctionFlux,
                                      const EllipticProjectionMask* mask,
                                      const ImmersedSolidProjectionMask* immersedMask,
                                      const SimulationParams& params,
                                      Q9ProjectionWorkspace& ws,
                                      Q9ProjectionDiagnostics& diag) {
    const int nc = static_cast<int>(ws.cellMass.size());
    ws.cellDUx.assign(static_cast<std::size_t>(nc), 0.0);
    ws.cellDUy.assign(static_cast<std::size_t>(nc), 0.0);
    ws.cellDUxRaw.assign(static_cast<std::size_t>(nc), 0.0);
    ws.cellDUyRaw.assign(static_cast<std::size_t>(nc), 0.0);
    ws.cellCorrectionRawMag.assign(static_cast<std::size_t>(nc), 0.0);
    ws.cellCorrectionAppliedMag.assign(static_cast<std::size_t>(nc), 0.0);
    ws.cellCorrectionLimiterRatio.assign(static_cast<std::size_t>(nc), 0.0);
    ws.cellCorrectionLimiterActive.assign(static_cast<std::size_t>(nc), 0u);
    ws.cellLowMassSuppressed.assign(static_cast<std::size_t>(nc), 0u);
    ws.cellLowMassRamped.assign(static_cast<std::size_t>(nc), 0u);
    ws.cellMassFloorApplied.assign(static_cast<std::size_t>(nc), 0u);
    ws.cellSafetyActive.assign(static_cast<std::size_t>(nc), 0u);
    resize_periodic_face_field(ws.appliedCorrectionFlux, nc);

    const double strength = params.q9MassFluxProjectionStrength;
    const double minMass = q9_effective_mass_threshold(
        params.q9MinCellMassForCorrection,
        params.q9MinCellMassForCorrectionOverGamma,
        params,
        "q9MinCellMassForCorrectionOverGamma");
    const Q9VelocityLimiterConfig limiter = q9_velocity_limiter_config(params);
    const std::string lowMassTreatment = canonical_filter_name(params.q9LowMassTreatment);
    const bool useRampFloor = lowMassTreatment == "ramp_floor" || lowMassTreatment == "floor_ramp";

    double massFloor = q9_effective_mass_threshold(
        params.q9MassFloorForCorrection,
        params.q9MassFloorForCorrectionOverGamma,
        params,
        "q9MassFloorForCorrectionOverGamma");
    double rampStart = q9_effective_mass_threshold(
        params.q9LowMassRampStart,
        params.q9LowMassRampStartOverGamma,
        params,
        "q9LowMassRampStartOverGamma");
    double rampEnd = q9_effective_mass_threshold(
        params.q9LowMassRampEnd,
        params.q9LowMassRampEndOverGamma,
        params,
        "q9LowMassRampEndOverGamma");
    if (useRampFloor) {
        // Keep legacy parameter files usable: if a ramp/floor run only provides
        // q9MinCellMassForCorrection, use it as both ramp end and mass floor.
        if (!(massFloor > 0.0)) {
            massFloor = minMass;
        }
        if (!(rampEnd > rampStart)) {
            rampStart = 0.0;
            rampEnd = minMass > 0.0 ? minMass : massFloor;
        }
        if (!(rampEnd > rampStart)) {
            rampStart = 0.0;
            rampEnd = 0.0;
        }
    }

    diag.minCellMassForCorrection = minMass;
    diag.massFloorForCorrection = massFloor;
    diag.lowMassRampStart = rampStart;
    diag.lowMassRampEnd = rampEnd;
    diag.correctionVelocityLimiter = limiter.limit;

    double rawSum2 = 0.0;
    double appliedSum2 = 0.0;
    double rawMaxAbs = 0.0;
    double appliedMaxAbs = 0.0;
    std::uint64_t activeCount = 0u;
    std::uint64_t lowMass = 0u;
    std::uint64_t ramped = 0u;
    std::uint64_t floored = 0u;
    std::uint64_t limited = 0u;
#pragma omp parallel for reduction(+:rawSum2,appliedSum2,activeCount,lowMass,ramped,floored,limited) reduction(max:rawMaxAbs,appliedMaxAbs) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        ws.appliedCorrectionFlux.x[k] = 0.0;
        ws.appliedCorrectionFlux.y[k] = 0.0;
        if (!mask_active(mask, k)) {
            continue;
        }
        activeCount += 1u;
        ws.cellSafetyActive[k] = 1u;

        const double m = ws.cellMass[k];
        double rampWeight = 1.0;
        double massDenom = m;
        if (useRampFloor) {
            if (!(m > 0.0)) {
                lowMass += 1u;
                ws.cellLowMassSuppressed[k] = 1u;
                continue;
            }
            if (rampEnd > rampStart) {
                if (!(m > rampStart)) {
                    lowMass += 1u;
                    ws.cellLowMassSuppressed[k] = 1u;
                    continue;
                }
                if (m < rampEnd) {
                    rampWeight = (m - rampStart) / (rampEnd - rampStart);
                    ramped += 1u;
                    ws.cellLowMassRamped[k] = 1u;
                }
            }
            massDenom = std::max(m, massFloor);
            if (massFloor > 0.0 && m < massFloor) {
                floored += 1u;
                ws.cellMassFloorApplied[k] = 1u;
            }
        } else {
            if (!(m > minMass)) {
                lowMass += 1u;
                ws.cellLowMassSuppressed[k] = 1u;
                continue;
            }
        }

        const double sx = face_strength_for_q9(strength, immersedMask, true, k);
        const double sy = face_strength_for_q9(strength, immersedMask, false, k);
        const double dcx = rampWeight * sx * correctionFlux.x[k];
        const double dcy = rampWeight * sy * correctionFlux.y[k];

        double ux = dcx / massDenom;
        double uy = dcy / massDenom;
        const double rawMag = std::sqrt(ux * ux + uy * uy);
        rawSum2 += ux * ux + uy * uy;
        rawMaxAbs = std::max(rawMaxAbs, rawMag);
        ws.cellDUxRaw[k] = ux;
        ws.cellDUyRaw[k] = uy;
        ws.cellCorrectionRawMag[k] = rawMag;
        ws.cellCorrectionLimiterRatio[k] = limiter.limit > 0.0 ? rawMag / limiter.limit : 0.0;
        ws.cellCorrectionLimiterActive[k] = (limiter.limit > 0.0 && rawMag > limiter.limit) ? 1u : 0u;

        if (limiter.limit > 0.0 && rawMag > 0.0) {
            double scale = 1.0;
            if (limiter.soft) {
                const double z = rawMag / limiter.limit;
                scale = std::tanh(z) / z;
            } else if (rawMag > limiter.limit) {
                scale = limiter.limit / rawMag;
            }
            if (scale < 1.0) {
                ux *= scale;
                uy *= scale;
                if (rawMag > limiter.limit) {
                    limited += 1u;
                }
            }
        }

        ws.cellDUx[k] = ux;
        ws.cellDUy[k] = uy;
        ws.appliedCorrectionFlux.x[k] = ux * m;
        ws.appliedCorrectionFlux.y[k] = uy * m;

        const double appliedMag = std::sqrt(ux * ux + uy * uy);
        ws.cellCorrectionAppliedMag[k] = appliedMag;
        appliedSum2 += ux * ux + uy * uy;
        appliedMaxAbs = std::max(appliedMaxAbs, appliedMag);
    }
    diag.lowMassSuppressedCells = lowMass;
    diag.lowMassRampedCells = ramped;
    diag.massFloorAppliedCells = floored;
    diag.velocityLimitedCells = limited;
    diag.correctionVelocityRawRms = activeCount > 0u ? std::sqrt(rawSum2 / static_cast<double>(activeCount)) : 0.0;
    diag.correctionVelocityRawMaxAbs = rawMaxAbs;
    diag.correctionVelocityRms = activeCount > 0u ? std::sqrt(appliedSum2 / static_cast<double>(activeCount)) : 0.0;
    diag.correctionVelocityMaxAbs = appliedMaxAbs;
}

std::vector<double> build_q9_projection_target(const SimulationParams& params,
                                                const EllipticProjectionGrid& egrid,
                                                const EllipticProjectionBC& bc,
                                                const PeriodicFaceField& baseFlux,
                                                const PeriodicFaceField& alpha,
                                                const EllipticProjectionMask* mask,
                                                const std::vector<double>& densityTarget,
                                                Q9ProjectionWorkspace& ws) {
    if (!q9_lowk_correction_only(params)) {
        return densityTarget;
    }

    const std::vector<double> divBefore = compute_face_divergence(egrid, baseFlux, bc, mask);
    std::vector<double> rhs(divBefore.size(), 0.0);
    const std::size_t n = divBefore.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        rhs[k] = densityTarget[k] - divBefore[k];
    }
    subtract_vector_mean(rhs, mask);

    const EllipticLowPassParams filterParams = make_q9_lowpass_params(params, egrid);
    rhs = elliptic_lowpass_cell_field(egrid, rhs, alpha, filterParams, bc, ws.elliptic, nullptr, mask);
    subtract_vector_mean(rhs, mask);

    std::vector<double> projectionTarget(n, 0.0);
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        projectionTarget[k] = mask_active(mask, k) ? (divBefore[k] + rhs[k]) : 0.0;
    }
    return projectionTarget;
}

void compute_estimated_density_after(const SimulationParams& params,
                                     const std::vector<double>& cellMass,
                                     const std::vector<double>& divAfter,
                                     const EllipticProjectionMask* mask,
                                     std::vector<double>& massAfter,
                                     Q9ProjectionDiagnostics& diag) {
    const int nc = static_cast<int>(cellMass.size());
    massAfter.assign(static_cast<std::size_t>(nc), 0.0);
    if (nc <= 0) {
        return;
    }
    double sum = 0.0;
    double sum2 = 0.0;
    std::uint64_t count = 0u;
#pragma omp parallel for reduction(+:sum,sum2,count) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = cellMass[k] - params.dt * divAfter[k];
        massAfter[k] = m;
        if (!mask_active(mask, k)) continue;
        sum += m;
        sum2 += m * m;
        count += 1u;
    }
    const double mean = count > 0u ? sum / static_cast<double>(count) : 0.0;
    const double var = count > 0u ? std::max(0.0, sum2 / static_cast<double>(count) - mean * mean) : 0.0;
    diag.densityStdAfterEstimate = std::sqrt(var);
    diag.densityStdRatioEstimate = diag.densityStdBefore > 0.0
        ? diag.densityStdAfterEstimate / diag.densityStdBefore
        : 0.0;
}

void apply_cell_velocity_kick(ParticleState& state,
                              const Q9ProjectionWorkspace& ws,
                              Q9ProjectionDiagnostics& diag,
                              bool momentumCorrectionEnable) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    double mass = 0.0;
    double dpx = 0.0;
    double dpy = 0.0;

#pragma omp parallel for reduction(+:mass,dpx,dpy) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const int c = ws.cellId[i];
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = state.mass[i];
        mass += m;
        dpx += m * ws.cellDUx[k];
        dpy += m * ws.cellDUy[k];
        state.vx[i] += ws.cellDUx[k];
        state.vy[i] += ws.cellDUy[k];
    }

    diag.momentumResidualBeforeCorrection = std::sqrt(dpx * dpx + dpy * dpy);
    if (momentumCorrectionEnable && mass > 0.0) {
        const double cvx = dpx / mass;
        const double cvy = dpy / mass;
        diag.momentumCorrectionVx = cvx;
        diag.momentumCorrectionVy = cvy;
#pragma omp parallel for if(n > 10000)
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            state.vx[i] -= cvx;
            state.vy[i] -= cvy;
        }
    }
}

} // namespace

bool q9_projection_requested(const SimulationParams& params) {
    return params.q9MassFluxProjectionEnable || params.method == "q9" || params.method == "q9_virial";
}

Q9ProjectionDiagnostics apply_q9_mass_flux_projection(ParticleState& state,
                                                      const SimulationParams& params,
                                                      const CellGrid& grid,
                                                      const FluidDomainBounds& domain,
                                                      double time,
                                                      Q9ProjectionWorkspace& workspace) {
    validate_particle_state(state, "apply_q9_mass_flux_projection");

    Q9ProjectionDiagnostics diag{};
    if (!q9_projection_requested(params)) {
        return diag;
    }

    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());
    resize_q9_workspace(workspace, state.Np, nc, nt);

    deposit_cell_mass_momentum(state, params, grid, domain, workspace, diag);
    build_mass_flux_from_cell_momentum(grid, workspace.cellPx, workspace.cellPy, workspace.baseMassFlux);
    fill_alpha(workspace.alpha, nc, 1.0);
    const EllipticProjectionMask* mask = prepare_q9_projection_mask(
        params, grid, domain, time, workspace, diag);
    if (mask != nullptr) {
        apply_immersed_face_alpha(workspace.immersedMask, workspace.alpha);
    }
    build_uniform_density_relaxation_target(params, domain, workspace.cellMass, mask, workspace.targetDivergence, diag);

    const EllipticProjectionGrid egrid = make_elliptic_projection_grid(
        params.Nx, params.Ny, fluid_domain_width(domain), fluid_domain_height(domain));
    EllipticProjectionBC bc = q9_bc_from_particle_boundaries(params);
    add_boundary_mass_fluxes_to_q9_bc(bc, workspace.baseMassFlux, params, domain, time, diag.densityMean, diag);
    apply_q9_target_filter(params, egrid, bc, workspace.alpha, mask, workspace.targetDivergence, workspace, diag);
    const std::vector<double> projectionTarget = build_q9_projection_target(
        params, egrid, bc, workspace.baseMassFlux, workspace.alpha, mask, workspace.targetDivergence, workspace);

    EllipticProjectionParams eparams{};
    eparams.maxIterations = params.projectionMaxIterations;
    eparams.tolerance = params.projectionTolerance;
    eparams.removeRhsMean = true;
    eparams.removePhiMean = true;

    EllipticProjectionResult result = project_face_field(
        egrid, workspace.baseMassFlux, workspace.alpha, projectionTarget, eparams, bc, workspace.elliptic, mask);

    diag.applied = true;
    diag.converged = result.diagnostics.converged;
    diag.iterations = result.diagnostics.iterations;
    diag.residualRel = result.diagnostics.residualRel;
    diag.massFluxDivBeforeRms = result.diagnostics.divBeforeRms;
    diag.massFluxDivBeforeMaxAbs = result.diagnostics.divBeforeMaxAbs;
    diag.massFluxDivAfterRms = result.diagnostics.divAfterRms;
    diag.massFluxDivAfterMaxAbs = result.diagnostics.divAfterMaxAbs;

    correction_flux_to_velocity_kick(result.correctionFlux,
                                     mask,
                                     params.immersedSolidEnable ? &workspace.immersedMask : nullptr,
                                     params,
                                     workspace,
                                     diag);

#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        workspace.projectedMassFlux.x[k] = workspace.baseMassFlux.x[k] + workspace.appliedCorrectionFlux.x[k];
        workspace.projectedMassFlux.y[k] = workspace.baseMassFlux.y[k] + workspace.appliedCorrectionFlux.y[k];
    }
    if (mask != nullptr && params.immersedSolidEnable) {
        enforce_q9_immersed_closed_face_flux(params, workspace, diag);
    }
    const std::vector<double> divApplied = compute_face_divergence(egrid, workspace.projectedMassFlux, bc, mask);
    double div2 = 0.0;
    double divMax = 0.0;
    std::uint64_t divCount = 0u;
#pragma omp parallel for reduction(+:div2,divCount) reduction(max:divMax) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (!mask_active(mask, k)) continue;
        const double d = divApplied[k];
        div2 += d * d;
        divMax = std::max(divMax, std::abs(d));
        divCount += 1u;
    }
    diag.massFluxDivAfterRms = divCount > 0u ? std::sqrt(div2 / static_cast<double>(divCount)) : 0.0;
    diag.massFluxDivAfterMaxAbs = divMax;
    compute_estimated_density_after(params, workspace.cellMass, divApplied, mask, workspace.massAfterEstimate, diag);

    if (mask != nullptr) {
        compute_q9_solid_leak(workspace.projectedMassFlux, workspace.immersedMask, params, diag);
    }

    apply_cell_velocity_kick(state, workspace, diag, params.q9MomentumCorrectionEnable);
    return diag;
}

void write_q9_diagnostic_field_dump(const std::string& outputDir,
                                    int step,
                                    const SimulationParams& params,
                                    const Q9ProjectionWorkspace& workspace) {
    if (!params.q9DiagnosticFieldDumpEnable || !q9_projection_requested(params)) {
        return;
    }

    const int expectedCells = params.Nx * params.Ny;
    if (expectedCells <= 0 || workspace.allocatedCells != expectedCells) {
        throw std::runtime_error("write_q9_diagnostic_field_dump: Q9 workspace is not allocated for the current grid");
    }
    const std::size_t nc = static_cast<std::size_t>(expectedCells);
    auto require_size = [nc](std::size_t got, const char* name) {
        if (got != nc) {
            throw std::runtime_error(std::string("write_q9_diagnostic_field_dump: invalid field size for ") + name);
        }
    };
    require_size(workspace.cellMass.size(), "cellMass");
    require_size(workspace.cellDUxRaw.size(), "cellDUxRaw");
    require_size(workspace.cellDUyRaw.size(), "cellDUyRaw");
    require_size(workspace.cellDUx.size(), "cellDUx");
    require_size(workspace.cellDUy.size(), "cellDUy");
    require_size(workspace.cellCorrectionRawMag.size(), "cellCorrectionRawMag");
    require_size(workspace.cellCorrectionAppliedMag.size(), "cellCorrectionAppliedMag");
    require_size(workspace.cellCorrectionLimiterRatio.size(), "cellCorrectionLimiterRatio");
    require_size(workspace.cellCorrectionLimiterActive.size(), "cellCorrectionLimiterActive");
    require_size(workspace.cellLowMassSuppressed.size(), "cellLowMassSuppressed");
    require_size(workspace.cellLowMassRamped.size(), "cellLowMassRamped");
    require_size(workspace.cellMassFloorApplied.size(), "cellMassFloorApplied");
    require_size(workspace.cellSafetyActive.size(), "cellSafetyActive");

    const bool hasImmersedFieldMask = workspace.immersedMask.activeCell.size() == nc;
    if (hasImmersedFieldMask) {
        require_size(workspace.immersedMask.activeCell.size(), "immersedMask.activeCell");
        require_size(workspace.immersedMask.cutCell.size(), "immersedMask.cutCell");
        require_size(workspace.immersedMask.activeSolidAdjacentCell.size(), "immersedMask.activeSolidAdjacentCell");
    }
    auto optional_flag_value = [hasImmersedFieldMask](const std::vector<std::uint8_t>& src, std::size_t k) -> int {
        return hasImmersedFieldMask && !src.empty() ? static_cast<int>(src[k]) : 0;
    };

    std::ostringstream base;
    base << outputDir << "/q9_diagnostics_step_"
         << std::setw(8) << std::setfill('0') << step;

    if (params.q9DiagnosticFieldDumpFormat == "csv") {
        const std::string path = base.str() + ".csv";
        std::ofstream out(path);
        if (!out) {
            throw std::runtime_error("Cannot open Q9 diagnostic field dump for writing: " + path);
        }
        out << std::setprecision(17);
        out << "ix,iy,cellIndex,cellMass,"
            << "q9CorrectionRawDUx,q9CorrectionRawDUy,"
            << "q9CorrectionAppliedDUx,q9CorrectionAppliedDUy,"
            << "q9CorrectionRawMag,q9CorrectionAppliedMag,"
            << "q9CorrectionLimiterRatio,q9LimiterActive,"
            << "q9LowMassSuppressed,q9LowMassRamped,q9MassFloorApplied,q9SafetyActive,"
            << "q9ImmersedSolidActive,q9ImmersedSolidCut,q9ImmersedSolidAdjacentActive\n";

        for (int iy = 0; iy < params.Ny; ++iy) {
            for (int ix = 0; ix < params.Nx; ++ix) {
                const int c = ix + params.Nx * iy;
                const std::size_t k = static_cast<std::size_t>(c);
                out << ix << ',' << iy << ',' << c << ','
                    << workspace.cellMass[k] << ','
                    << workspace.cellDUxRaw[k] << ',' << workspace.cellDUyRaw[k] << ','
                    << workspace.cellDUx[k] << ',' << workspace.cellDUy[k] << ','
                    << workspace.cellCorrectionRawMag[k] << ','
                    << workspace.cellCorrectionAppliedMag[k] << ','
                    << workspace.cellCorrectionLimiterRatio[k] << ','
                    << static_cast<int>(workspace.cellCorrectionLimiterActive[k]) << ','
                    << static_cast<int>(workspace.cellLowMassSuppressed[k]) << ','
                    << static_cast<int>(workspace.cellLowMassRamped[k]) << ','
                    << static_cast<int>(workspace.cellMassFloorApplied[k]) << ','
                    << static_cast<int>(workspace.cellSafetyActive[k]) << ','
                    << optional_flag_value(workspace.immersedMask.activeCell, k) << ','
                    << optional_flag_value(workspace.immersedMask.cutCell, k) << ','
                    << optional_flag_value(workspace.immersedMask.activeSolidAdjacentCell, k) << '\n';
            }
        }
        return;
    }

    const std::string path = base.str() + ".q9bin";
    std::ofstream out(path, std::ios::binary);
    if (!out) {
        throw std::runtime_error("Cannot open compact Q9 diagnostic field dump for writing: " + path);
    }

    const char magic[8] = {'Q','9','D','G','0','0','1','\0'};
    const std::int32_t version = 1;
    const std::int32_t nx = static_cast<std::int32_t>(params.Nx);
    const std::int32_t ny = static_cast<std::int32_t>(params.Ny);
    const std::int32_t st = static_cast<std::int32_t>(step);
    const std::int32_t nFloatFields = 8;
    const std::int32_t nFlagFields = 8;
    out.write(magic, sizeof(magic));
    out.write(reinterpret_cast<const char*>(&version), sizeof(version));
    out.write(reinterpret_cast<const char*>(&st), sizeof(st));
    out.write(reinterpret_cast<const char*>(&nx), sizeof(nx));
    out.write(reinterpret_cast<const char*>(&ny), sizeof(ny));
    out.write(reinterpret_cast<const char*>(&nFloatFields), sizeof(nFloatFields));
    out.write(reinterpret_cast<const char*>(&nFlagFields), sizeof(nFlagFields));

    std::vector<float> buffer(nc);
    auto write_float_field = [&out, &buffer, nc](const std::vector<double>& src) {
        for (std::size_t i = 0; i < nc; ++i) {
            buffer[i] = static_cast<float>(src[i]);
        }
        out.write(reinterpret_cast<const char*>(buffer.data()),
                  static_cast<std::streamsize>(buffer.size() * sizeof(float)));
    };
    std::vector<std::uint8_t> zeroFlagField(nc, 0u);
    auto write_flag_field = [&out](const std::vector<std::uint8_t>& src) {
        out.write(reinterpret_cast<const char*>(src.data()),
                  static_cast<std::streamsize>(src.size() * sizeof(std::uint8_t)));
    };
    auto write_optional_flag_field = [&write_flag_field, &zeroFlagField, hasImmersedFieldMask](const std::vector<std::uint8_t>& src) {
        if (hasImmersedFieldMask && !src.empty()) {
            write_flag_field(src);
        } else {
            write_flag_field(zeroFlagField);
        }
    };

    // Float fields, fixed order.  MATLAB reader maps this order to names.
    write_float_field(workspace.cellMass);
    write_float_field(workspace.cellDUxRaw);
    write_float_field(workspace.cellDUyRaw);
    write_float_field(workspace.cellDUx);
    write_float_field(workspace.cellDUy);
    write_float_field(workspace.cellCorrectionRawMag);
    write_float_field(workspace.cellCorrectionAppliedMag);
    write_float_field(workspace.cellCorrectionLimiterRatio);

    // Flag fields, fixed order.
    write_flag_field(workspace.cellCorrectionLimiterActive);
    write_flag_field(workspace.cellLowMassSuppressed);
    write_flag_field(workspace.cellLowMassRamped);
    write_flag_field(workspace.cellMassFloorApplied);
    write_flag_field(workspace.cellSafetyActive);
    write_optional_flag_field(workspace.immersedMask.activeCell);
    write_optional_flag_field(workspace.immersedMask.cutCell);
    write_optional_flag_field(workspace.immersedMask.activeSolidAdjacentCell);

    if (!out) {
        throw std::runtime_error("Error while writing compact Q9 diagnostic field dump: " + path);
    }
}
} // namespace mpcd

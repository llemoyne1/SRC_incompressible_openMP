#include "boundary_base.h"
#include "immersed_solid.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#include <utility>

namespace mpcd {
namespace {

double wrap_periodic(double x, double L) {
    x = std::fmod(x, L);
    if (x < 0.0) {
        x += L;
    }
    if (x >= L) {
        x -= L;
    }
    return x;
}

std::uint64_t splitmix64(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31U);
}

double uint64_to_unit_open(std::uint64_t x) {
    // Convert the top 53 random bits to a double in [0,1). Boundary-condition
    // callers subsequently clamp to a strictly interior coordinate.
    return static_cast<double>(x >> 11U) * (1.0 / 9007199254740992.0);
}

void wall_velocity_for_face(const SimulationParams& params,
                            const FluidDomainBounds& domain,
                            const std::string& face,
                            double& ux,
                            double& uy) {
    if (face == "left") {
        ux = domain.vxMin + params.wallVpUxLeft;
        uy = params.wallVpUyLeft;
    } else if (face == "right") {
        ux = domain.vxMax + params.wallVpUxRight;
        uy = params.wallVpUyRight;
    } else if (face == "bottom") {
        ux = params.wallVpUxBottom;
        uy = domain.vyMin + params.wallVpUyBottom;
    } else if (face == "top") {
        ux = params.wallVpUxTop;
        uy = domain.vyMax + params.wallVpUyTop;
    } else {
        ux = 0.0;
        uy = 0.0;
    }
}

struct ReflectionFailure {
    bool failed = false;
    std::string message;
};

std::string format_particle_wall_failure(const char* axis,
                                         std::size_t particleIndex,
                                         std::uint64_t step,
                                         double time,
                                         int attemptedReflections,
                                         double x,
                                         double y,
                                         double vx,
                                         double vy,
                                         const FluidDomainBounds& domain,
                                         double dt) {
    std::ostringstream oss;
    oss << "Too many " << axis << "-wall reflections in one step"
        << "; step=" << step
        << " time=" << time
        << " particle=" << particleIndex
        << " attemptedReflections=" << attemptedReflections
        << " x=" << x
        << " y=" << y
        << " vx=" << vx
        << " vy=" << vy
        << " predictedNextX=" << (x + vx * dt)
        << " predictedNextY=" << (y + vy * dt)
        << " dt=" << dt
        << " domain=[" << domain.xMin << "," << domain.xMax
        << "]x[" << domain.yMin << "," << domain.yMax << "]"
        << "; reduce dt or inspect particle/Q9/wall velocities";
    return oss.str();
}

std::string format_nonfinite_particle_failure(std::size_t particleIndex,
                                              std::uint64_t step,
                                              double time,
                                              double x,
                                              double y,
                                              double vx,
                                              double vy) {
    std::ostringstream oss;
    oss << "Non-finite particle state before boundary conditions"
        << "; step=" << step
        << " time=" << time
        << " particle=" << particleIndex
        << " x=" << x
        << " y=" << y
        << " vx=" << vx
        << " vy=" << vy;
    return oss.str();
}

void apply_wall_velocity_reflection(const std::string& mode,
                                    bool normalIsX,
                                    double wallUx,
                                    double wallUy,
                                    double& vx,
                                    double& vy) {
    // The generic solid wall uses a specular geometric reflection in the wall
    // frame to enforce impermeability. Tangential no-slip/thermal coupling is
    // supplied by aggregate wall momentum in collision-cell moments.
    if (mode == "solid" || mode == "specular") {
        if (normalIsX) {
            vx = 2.0 * wallUx - vx;
        } else {
            vy = 2.0 * wallUy - vy;
        }
    } else if (mode == "bounceback") {
        vx = 2.0 * wallUx - vx;
        vy = 2.0 * wallUy - vy;
    } else {
        throw std::runtime_error("Unsupported non-periodic wall mode during reflection: " + mode);
    }
}



double inlet_velocity_ramp_factor(const SimulationParams& params, double time) {
    if (!params.inletVelocityRampEnable) {
        return 1.0;
    }
    const double t0 = params.inletVelocityRampStartTime;
    const double t1 = params.inletVelocityRampEndTime;
    if (!(t1 > t0)) {
        return params.inletVelocityRampFinalFactor;
    }
    double a = 0.0;
    if (time <= t0) {
        a = 0.0;
    } else if (time >= t1) {
        a = 1.0;
    } else {
        a = (time - t0) / (t1 - t0);
    }
    if (params.inletVelocityRampProfile == "smoothstep") {
        a = a * a * (3.0 - 2.0 * a);
    }
    return (1.0 - a) * params.inletVelocityRampInitialFactor +
           a * params.inletVelocityRampFinalFactor;
}

void inlet_velocity_for_face(const SimulationParams& params,
                             const char* face,
                             double time,
                             double& ux,
                             double& uy) {
    const std::string f(face);
    if (f == "left") {
        ux = params.inletUxLeft;
        uy = params.inletUyLeft;
    } else if (f == "right") {
        ux = params.inletUxRight;
        uy = params.inletUyRight;
    } else if (f == "bottom") {
        ux = params.inletUxBottom;
        uy = params.inletUyBottom;
    } else if (f == "top") {
        ux = params.inletUxTop;
        uy = params.inletUyTop;
    } else {
        ux = 0.0;
        uy = 0.0;
    }
    const double fRamp = inlet_velocity_ramp_factor(params, time);
    ux *= fRamp;
    uy *= fRamp;
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
    const double eta = std::clamp((y - domain.yMin) / h, 0.0, 1.0);
    const double shape = eta * (1.0 - eta);
    if (profile == "poiseuille_y_max") {
        return 4.0 * shape;
    }
    if (profile == "poiseuille_y" || profile == "poiseuille_y_mean") {
        return 6.0 * shape;
    }
    if (profile == "flat_taper_y" || profile == "flat_taper_y_mean") {
        return flat_taper_y_mean_factor(params, domain, y);
    }
    return 1.0;
}

void inlet_velocity_for_face_at_position(const SimulationParams& params,
                                         const FluidDomainBounds& domain,
                                         const char* face,
                                         double x,
                                         double y,
                                         double time,
                                         double& ux,
                                         double& uy) {
    (void)x;
    inlet_velocity_for_face(params, face, time, ux, uy);
    const std::string f(face);
    const std::string profile = params.inletVelocitySpatialProfile;
    if (f == "left" || f == "right") {
        ux *= inlet_y_profile_factor(params, domain, y);
    }
}

std::uint64_t face_tag(const char* face) {
    const std::string f(face);
    if (f == "left") return 0x4c454654ULL;
    if (f == "right") return 0x5249474854ULL;
    if (f == "bottom") return 0x424f54544f4dULL;
    if (f == "top") return 0x544f50ULL;
    return 0x46414345ULL;
}

std::uint64_t inlet_seed(const SimulationParams& params,
                         const char* face,
                         std::size_t particleIndex,
                         std::uint64_t step,
                         std::uint64_t salt) {
    return splitmix64(params.rngSeed ^
                      (step * 0x9e3779b97f4a7c15ULL) ^
                      (static_cast<std::uint64_t>(particleIndex) * 0xbf58476d1ce4e5b9ULL) ^
                      face_tag(face) ^ salt);
}

double inlet_uniform01(const SimulationParams& params,
                       const char* face,
                       std::size_t particleIndex,
                       std::uint64_t step,
                       std::uint64_t salt) {
    return uint64_to_unit_open(inlet_seed(params, face, particleIndex, step, salt));
}

double clamp_strictly_inside(double x, double lo, double hi) {
    const double width = hi - lo;
    const double eps = 1.0e-12 * std::max(1.0, std::abs(width));
    return std::clamp(x, lo + eps, hi - eps);
}

struct ApertureInterval {
    double lo = 0.0;
    double hi = 0.0;
};

ApertureInterval normalize_aperture_interval(double requestedLo,
                                             double requestedHi,
                                             double domainLo,
                                             double domainHi) {
    ApertureInterval a{};
    a.lo = std::clamp(requestedLo, domainLo, domainHi);
    const double hiRaw = requestedHi < 0.0 ? domainHi : requestedHi;
    a.hi = std::clamp(hiRaw, domainLo, domainHi);
    if (a.hi < a.lo) {
        a.hi = a.lo;
    }
    return a;
}

ApertureInterval x_face_aperture_y(const SimulationParams& params,
                                   const FluidDomainBounds& domain,
                                   const char* face) {
    if (!params.openBoundaryApertureEnable) {
        return {domain.yMin, domain.yMax};
    }
    const std::string f(face);
    if (f == "left") {
        return normalize_aperture_interval(params.leftOpenYMin, params.leftOpenYMax, domain.yMin, domain.yMax);
    }
    if (f == "right") {
        return normalize_aperture_interval(params.rightOpenYMin, params.rightOpenYMax, domain.yMin, domain.yMax);
    }
    return {domain.yMin, domain.yMax};
}

ApertureInterval y_face_aperture_x(const SimulationParams& params,
                                   const FluidDomainBounds& domain,
                                   const char* face) {
    if (!params.openBoundaryApertureEnable) {
        return {domain.xMin, domain.xMax};
    }
    const std::string f(face);
    if (f == "bottom") {
        return normalize_aperture_interval(params.bottomOpenXMin, params.bottomOpenXMax, domain.xMin, domain.xMax);
    }
    if (f == "top") {
        return normalize_aperture_interval(params.topOpenXMin, params.topOpenXMax, domain.xMin, domain.xMax);
    }
    return {domain.xMin, domain.xMax};
}

bool point_in_x_face_aperture(const SimulationParams& params,
                              const FluidDomainBounds& domain,
                              const char* face,
                              double y) {
    const ApertureInterval a = x_face_aperture_y(params, domain, face);
    return y >= a.lo && y <= a.hi;
}

bool point_in_y_face_aperture(const SimulationParams& params,
                              const FluidDomainBounds& domain,
                              const char* face,
                              double x) {
    const ApertureInterval a = y_face_aperture_x(params, domain, face);
    return x >= a.lo && x <= a.hi;
}

void reflect_x_as_solid_face(double& x,
                             double& vx,
                             double& vy,
                             const SimulationParams& params,
                             const FluidDomainBounds& domain,
                             const char* face) {
    const std::string f(face);
    if (f == "left") {
        x = 2.0 * domain.xMin - x;
    } else {
        x = 2.0 * domain.xMax - x;
    }
    double wx = 0.0, wy = 0.0;
    wall_velocity_for_face(params, domain, f, wx, wy);
    apply_wall_velocity_reflection("solid", true, wx, wy, vx, vy);
    x = std::clamp(x, domain.xMin, domain.xMax);
}

void reflect_y_as_solid_face(double& y,
                             double& vx,
                             double& vy,
                             const SimulationParams& params,
                             const FluidDomainBounds& domain,
                             const char* face) {
    const std::string f(face);
    if (f == "bottom") {
        y = 2.0 * domain.yMin - y;
    } else {
        y = 2.0 * domain.yMax - y;
    }
    double wx = 0.0, wy = 0.0;
    wall_velocity_for_face(params, domain, f, wx, wy);
    apply_wall_velocity_reflection("solid", false, wx, wy, vx, vy);
    y = std::clamp(y, domain.yMin, domain.yMax);
}

double random_inside_interval(const SimulationParams& params,
                              const char* face,
                              std::size_t particleIndex,
                              std::uint64_t step,
                              std::uint64_t salt,
                              double lo,
                              double hi) {
    const double u = inlet_uniform01(params, face, particleIndex, step, salt);
    return clamp_strictly_inside(lo + u * (hi - lo), lo, hi);
}

void sample_inlet_velocity_at(const SimulationParams& params,
                              const FluidDomainBounds& domain,
                              const char* face,
                              double x,
                              double y,
                              std::size_t particleIndex,
                              std::uint64_t step,
                              double mass,
                              double& vx,
                              double& vy) {
    double ux = 0.0, uy = 0.0;
    inlet_velocity_for_face_at_position(params, domain, face, x, y,
                                        static_cast<double>(step) * params.dt, ux, uy);
    vx = ux;
    vy = uy;

    const double effectiveKBT = params.inletKBT > 0.0 ? params.inletKBT : params.kBT;
    if (params.inletThermalNoise > 0.0 && effectiveKBT > 0.0 && mass > 0.0) {
        std::mt19937_64 rng(inlet_seed(params, face, particleIndex, step, 0x7f4a7c159e3779b9ULL));
        std::normal_distribution<double> normal(0.0, 1.0);
        const double sigma = params.inletThermalNoise * std::sqrt(effectiveKBT / mass);
        vx += sigma * normal(rng);
        vy += sigma * normal(rng);
    }
}

double inlet_slab_width_x(const SimulationParams& params, const FluidDomainBounds& domain) {
    const double width = domain.xMax - domain.xMin;
    const double dx = width / static_cast<double>(std::max(1, params.Nx));
    const double requested = params.inletSlabCells * dx;
    const double eps = 1.0e-12 * std::max(1.0, width);
    return std::clamp(requested, eps, width);
}

double inlet_slab_width_y(const SimulationParams& params, const FluidDomainBounds& domain) {
    const double height = domain.yMax - domain.yMin;
    const double dy = height / static_cast<double>(std::max(1, params.Ny));
    const double requested = params.inletSlabCells * dy;
    const double eps = 1.0e-12 * std::max(1.0, height);
    return std::clamp(requested, eps, height);
}

void inject_from_x_inlet(double& x,
                         double& y,
                         double& vx,
                         double& vy,
                         const SimulationParams& params,
                         const FluidDomainBounds& domain,
                         const char* inletFace,
                         std::size_t particleIndex,
                         std::uint64_t step,
                         double mass) {
    const double slab = inlet_slab_width_x(params, domain);
    if (std::string(inletFace) == "left") {
        x = random_inside_interval(params, inletFace, particleIndex, step, 0xa511e9b3ULL,
                                   domain.xMin, domain.xMin + slab);
    } else {
        x = random_inside_interval(params, inletFace, particleIndex, step, 0xa511e9b3ULL,
                                   domain.xMax - slab, domain.xMax);
    }

    const ApertureInterval ay = x_face_aperture_y(params, domain, inletFace);
    if (params.inletRandomizeTangential) {
        y = random_inside_interval(params, inletFace, particleIndex, step, 0x9e3779b9ULL,
                                   ay.lo, ay.hi);
    } else {
        y = clamp_strictly_inside(y, ay.lo, ay.hi);
    }
    sample_inlet_velocity_at(params, domain, inletFace, x, y, particleIndex, step, mass, vx, vy);
}

void inject_from_y_inlet(double& x,
                         double& y,
                         double& vx,
                         double& vy,
                         const SimulationParams& params,
                         const FluidDomainBounds& domain,
                         const char* inletFace,
                         std::size_t particleIndex,
                         std::uint64_t step,
                         double mass) {
    const double slab = inlet_slab_width_y(params, domain);
    if (std::string(inletFace) == "bottom") {
        y = random_inside_interval(params, inletFace, particleIndex, step, 0xa511e9b3ULL,
                                   domain.yMin, domain.yMin + slab);
    } else {
        y = random_inside_interval(params, inletFace, particleIndex, step, 0xa511e9b3ULL,
                                   domain.yMax - slab, domain.yMax);
    }

    const ApertureInterval ax = y_face_aperture_x(params, domain, inletFace);
    if (params.inletRandomizeTangential) {
        x = random_inside_interval(params, inletFace, particleIndex, step, 0x9e3779b9ULL,
                                   ax.lo, ax.hi);
    } else {
        x = clamp_strictly_inside(x, ax.lo, ax.hi);
    }
    sample_inlet_velocity_at(params, domain, inletFace, x, y, particleIndex, step, mass, vx, vy);
}

void clamp_backflow_x(double& x, const FluidDomainBounds& domain, bool lowSide) {
    const double eps = 1.0e-12 * std::max(1.0, domain.xMax - domain.xMin);
    x = lowSide ? (domain.xMin + eps) : (domain.xMax - eps);
}

void clamp_backflow_y(double& y, const FluidDomainBounds& domain, bool lowSide) {
    const double eps = 1.0e-12 * std::max(1.0, domain.yMax - domain.yMin);
    y = lowSide ? (domain.yMin + eps) : (domain.yMax - eps);
}

int apply_io_x(double& x,
               double& y,
               double& vx,
               double& vy,
               const SimulationParams& params,
               const FluidDomainBounds& domain,
               std::uint64_t& leftHits,
               std::uint64_t& rightHits,
               std::size_t particleIndex,
               std::uint64_t step,
               double mass) {
    if (x >= domain.xMin && x <= domain.xMax) {
        return 0;
    }

    const bool leftInlet = is_inlet_boundary_mode(params.bcLeft);
    const bool rightInlet = is_inlet_boundary_mode(params.bcRight);

    if (x < domain.xMin) {
        ++leftHits;
        if (!point_in_x_face_aperture(params, domain, "left", y)) {
            reflect_x_as_solid_face(x, vx, vy, params, domain, "left");
            return 0;
        }
        if (leftInlet) {
            if (params.inletReinjectBackflow) {
                inject_from_x_inlet(x, y, vx, vy, params, domain, "left", particleIndex, step, mass);
                return 1;
            }
            clamp_backflow_x(x, domain, true);
            return 0;
        }
        if (rightInlet) {
            inject_from_x_inlet(x, y, vx, vy, params, domain, "right", particleIndex, step, mass);
            return 1;
        }
    } else {
        ++rightHits;
        if (!point_in_x_face_aperture(params, domain, "right", y)) {
            reflect_x_as_solid_face(x, vx, vy, params, domain, "right");
            return 0;
        }
        if (rightInlet) {
            if (params.inletReinjectBackflow) {
                inject_from_x_inlet(x, y, vx, vy, params, domain, "right", particleIndex, step, mass);
                return 1;
            }
            clamp_backflow_x(x, domain, false);
            return 0;
        }
        if (leftInlet) {
            inject_from_x_inlet(x, y, vx, vy, params, domain, "left", particleIndex, step, mass);
            return 1;
        }
    }

    throw std::runtime_error("Internal error: x inlet/outlet pair has no inlet face");
}

int apply_io_y(double& x,
               double& y,
               double& vx,
               double& vy,
               const SimulationParams& params,
               const FluidDomainBounds& domain,
               std::uint64_t& bottomHits,
               std::uint64_t& topHits,
               std::size_t particleIndex,
               std::uint64_t step,
               double mass) {
    if (y >= domain.yMin && y <= domain.yMax) {
        return 0;
    }

    const bool bottomInlet = is_inlet_boundary_mode(params.bcBottom);
    const bool topInlet = is_inlet_boundary_mode(params.bcTop);

    if (y < domain.yMin) {
        ++bottomHits;
        if (!point_in_y_face_aperture(params, domain, "bottom", x)) {
            reflect_y_as_solid_face(y, vx, vy, params, domain, "bottom");
            return 0;
        }
        if (bottomInlet) {
            if (params.inletReinjectBackflow) {
                inject_from_y_inlet(x, y, vx, vy, params, domain, "bottom", particleIndex, step, mass);
                return 1;
            }
            clamp_backflow_y(y, domain, true);
            return 0;
        }
        if (topInlet) {
            inject_from_y_inlet(x, y, vx, vy, params, domain, "top", particleIndex, step, mass);
            return 1;
        }
    } else {
        ++topHits;
        if (!point_in_y_face_aperture(params, domain, "top", x)) {
            reflect_y_as_solid_face(y, vx, vy, params, domain, "top");
            return 0;
        }
        if (topInlet) {
            if (params.inletReinjectBackflow) {
                inject_from_y_inlet(x, y, vx, vy, params, domain, "top", particleIndex, step, mass);
                return 1;
            }
            clamp_backflow_y(y, domain, false);
            return 0;
        }
        if (bottomInlet) {
            inject_from_y_inlet(x, y, vx, vy, params, domain, "bottom", particleIndex, step, mass);
            return 1;
        }
    }

    throw std::runtime_error("Internal error: y inlet/outlet pair has no inlet face");
}

int reflect_x(double& x,
              double y,
              double& vx,
              double& vy,
              const SimulationParams& params,
              const FluidDomainBounds& domain,
              std::uint64_t& leftHits,
              std::uint64_t& rightHits,
              std::size_t particleIndex,
              std::uint64_t step,
              double time,
              ReflectionFailure& failure) {
    int guard = 0;
    while (x < domain.xMin || x > domain.xMax) {
        if (++guard > 64) {
            failure.failed = true;
            failure.message = format_particle_wall_failure("x", particleIndex, step, time, guard,
                                                           x, y, vx, vy, domain, params.dt);
            return guard;
        }
        if (x < domain.xMin) {
            x = 2.0 * domain.xMin - x;
            ++leftHits;
            double wx = 0.0, wy = 0.0;
            wall_velocity_for_face(params, domain, "left", wx, wy);
            apply_wall_velocity_reflection(params.bcLeft, true, wx, wy, vx, vy);
        } else if (x > domain.xMax) {
            x = 2.0 * domain.xMax - x;
            ++rightHits;
            double wx = 0.0, wy = 0.0;
            wall_velocity_for_face(params, domain, "right", wx, wy);
            apply_wall_velocity_reflection(params.bcRight, true, wx, wy, vx, vy);
        }
    }
    x = std::clamp(x, domain.xMin, domain.xMax);
    return guard;
}

int reflect_y(double x,
              double& y,
              double& vx,
              double& vy,
              const SimulationParams& params,
              const FluidDomainBounds& domain,
              std::uint64_t& bottomHits,
              std::uint64_t& topHits,
              std::size_t particleIndex,
              std::uint64_t step,
              double time,
              ReflectionFailure& failure) {
    int guard = 0;
    while (y < domain.yMin || y > domain.yMax) {
        if (++guard > 64) {
            failure.failed = true;
            failure.message = format_particle_wall_failure("y", particleIndex, step, time, guard,
                                                           x, y, vx, vy, domain, params.dt);
            return guard;
        }
        if (y < domain.yMin) {
            y = 2.0 * domain.yMin - y;
            ++bottomHits;
            double wx = 0.0, wy = 0.0;
            wall_velocity_for_face(params, domain, "bottom", wx, wy);
            apply_wall_velocity_reflection(params.bcBottom, false, wx, wy, vx, vy);
        } else if (y > domain.yMax) {
            y = 2.0 * domain.yMax - y;
            ++topHits;
            double wx = 0.0, wy = 0.0;
            wall_velocity_for_face(params, domain, "top", wx, wy);
            apply_wall_velocity_reflection(params.bcTop, false, wx, wy, vx, vy);
        }
    }
    y = std::clamp(y, domain.yMin, domain.yMax);
    return guard;
}


std::string normalized_inlet_reservoir_mode(const SimulationParams& params) {
    std::string mode = params.inletReservoirMode;
    std::replace(mode.begin(), mode.end(), '-', '_');
    if (mode == "" || mode == "default") {
        mode = params.inletInjectionMode;
        std::replace(mode.begin(), mode.end(), '-', '_');
    }
    if (mode == "cuda_recycle" || mode == "thin_slab") return "recycle";
    return mode;
}

bool hard_inlet_reservoir_enabled(const SimulationParams& params) {
    const std::string mode = normalized_inlet_reservoir_mode(params);
    return mode == "hard_cell_density" || mode == "hard_density" || mode == "hard" || mode == "cell_density";
}

struct HardReservoirCell {
    int ix = 0;
    int iy = 0;
    double x0 = 0.0;
    double x1 = 0.0;
    double y0 = 0.0;
    double y1 = 0.0;
};

bool point_in_inlet_reservoir(double x,
                              double y,
                              const SimulationParams& params,
                              const FluidDomainBounds& domain) {
    if (!hard_inlet_reservoir_enabled(params)) return false;
    const int nx = std::max(1, params.Nx);
    const int ny = std::max(1, params.Ny);
    const int cellsX = std::clamp(params.inletReservoirCells, 1, nx);
    const int cellsY = std::clamp(params.inletReservoirCells, 1, ny);
    const double dx = (domain.xMax - domain.xMin) / static_cast<double>(nx);
    const double dy = (domain.yMax - domain.yMin) / static_cast<double>(ny);

    if (is_inlet_boundary_mode(params.bcLeft)) {
        return x >= domain.xMin && x < domain.xMin + static_cast<double>(cellsX) * dx &&
               point_in_x_face_aperture(params, domain, "left", y);
    }
    if (is_inlet_boundary_mode(params.bcRight)) {
        return x > domain.xMax - static_cast<double>(cellsX) * dx && x <= domain.xMax &&
               point_in_x_face_aperture(params, domain, "right", y);
    }
    if (is_inlet_boundary_mode(params.bcBottom)) {
        return y >= domain.yMin && y < domain.yMin + static_cast<double>(cellsY) * dy &&
               point_in_y_face_aperture(params, domain, "bottom", x);
    }
    if (is_inlet_boundary_mode(params.bcTop)) {
        return y > domain.yMax - static_cast<double>(cellsY) * dy && y <= domain.yMax &&
               point_in_y_face_aperture(params, domain, "top", x);
    }
    return false;
}

std::vector<HardReservoirCell> build_hard_reservoir_cells(const SimulationParams& params,
                                                          const FluidDomainBounds& domain,
                                                          double time) {
    std::vector<HardReservoirCell> cells;
    const int nx = std::max(1, params.Nx);
    const int ny = std::max(1, params.Ny);
    const int cellsX = std::clamp(params.inletReservoirCells, 1, nx);
    const int cellsY = std::clamp(params.inletReservoirCells, 1, ny);
    const double dx = (domain.xMax - domain.xMin) / static_cast<double>(nx);
    const double dy = (domain.yMax - domain.yMin) / static_cast<double>(ny);

    auto add_cell = [&](int ix, int iy) {
        HardReservoirCell c{};
        c.ix = ix;
        c.iy = iy;
        c.x0 = domain.xMin + static_cast<double>(ix) * dx;
        c.x1 = domain.xMin + static_cast<double>(ix + 1) * dx;
        c.y0 = domain.yMin + static_cast<double>(iy) * dy;
        c.y1 = domain.yMin + static_cast<double>(iy + 1) * dy;
        const double xc = 0.5 * (c.x0 + c.x1);
        const double yc = 0.5 * (c.y0 + c.y1);
        if (is_inlet_boundary_mode(params.bcLeft) && !point_in_x_face_aperture(params, domain, "left", yc)) return;
        if (is_inlet_boundary_mode(params.bcRight) && !point_in_x_face_aperture(params, domain, "right", yc)) return;
        if (is_inlet_boundary_mode(params.bcBottom) && !point_in_y_face_aperture(params, domain, "bottom", xc)) return;
        if (is_inlet_boundary_mode(params.bcTop) && !point_in_y_face_aperture(params, domain, "top", xc)) return;
        if (point_is_inside_immersed_solid(xc, yc, params, time)) {
            return;
        }
        cells.push_back(c);
    };

    if (is_inlet_boundary_mode(params.bcLeft)) {
        for (int ix = 0; ix < cellsX; ++ix) {
            for (int iy = 0; iy < ny; ++iy) add_cell(ix, iy);
        }
    } else if (is_inlet_boundary_mode(params.bcRight)) {
        for (int ix = nx - cellsX; ix < nx; ++ix) {
            for (int iy = 0; iy < ny; ++iy) add_cell(ix, iy);
        }
    } else if (is_inlet_boundary_mode(params.bcBottom)) {
        for (int iy = 0; iy < cellsY; ++iy) {
            for (int ix = 0; ix < nx; ++ix) add_cell(ix, iy);
        }
    } else if (is_inlet_boundary_mode(params.bcTop)) {
        for (int iy = ny - cellsY; iy < ny; ++iy) {
            for (int ix = 0; ix < nx; ++ix) add_cell(ix, iy);
        }
    }
    return cells;
}

void append_particle(ParticleState& state,
                     double x,
                     double y,
                     double vx,
                     double vy,
                     std::uint32_t type,
                     double mass) {
    state.x.push_back(x);
    state.y.push_back(y);
    state.vx.push_back(vx);
    state.vy.push_back(vy);
    state.type.push_back(type);
    state.mass.push_back(mass);
    state.Np = static_cast<std::uint64_t>(state.x.size());
}

void sample_hard_inlet_cell_particles(ParticleState& state,
                                      const SimulationParams& params,
                                      const FluidDomainBounds& domain,
                                      const HardReservoirCell& cell,
                                      const char* inletFace,
                                      std::uint64_t step,
                                      std::uint64_t cellOrdinal,
                                      std::uint32_t particleType,
                                      double particleMass,
                                      BoundaryDiagnostics& diag) {
    const int targetN = params.inletTargetOccupancy;
    if (targetN <= 0) return;

    const double effectiveKBT = params.inletKBT > 0.0 ? params.inletKBT : params.kBT;
    const double sigma = (effectiveKBT > 0.0 && particleMass > 0.0)
        ? params.inletThermalNoise * std::sqrt(effectiveKBT / particleMass)
        : 0.0;

    std::vector<double> xs(static_cast<std::size_t>(targetN));
    std::vector<double> ys(static_cast<std::size_t>(targetN));
    std::vector<double> vxs(static_cast<std::size_t>(targetN));
    std::vector<double> vys(static_cast<std::size_t>(targetN));
    std::vector<double> uxTarget(static_cast<std::size_t>(targetN));
    std::vector<double> uyTarget(static_cast<std::size_t>(targetN));

    std::mt19937_64 rng(splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^
                                   (cellOrdinal * 0xbf58476d1ce4e5b9ULL) ^ face_tag(inletFace)));
    std::uniform_real_distribution<double> uni(0.0, 1.0);
    std::normal_distribution<double> normal(0.0, 1.0);

    double meanFlucX = 0.0;
    double meanFlucY = 0.0;
    for (int n = 0; n < targetN; ++n) {
        const double rx = uni(rng);
        const double ry = uni(rng);
        const std::size_t k = static_cast<std::size_t>(n);
        xs[k] = clamp_strictly_inside(cell.x0 + rx * (cell.x1 - cell.x0), cell.x0, cell.x1);
        ys[k] = clamp_strictly_inside(cell.y0 + ry * (cell.y1 - cell.y0), cell.y0, cell.y1);
        inlet_velocity_for_face_at_position(params, domain, inletFace, xs[k], ys[k],
                                            static_cast<double>(step) * params.dt,
                                            uxTarget[k], uyTarget[k]);
        const double fx = sigma > 0.0 ? sigma * normal(rng) : 0.0;
        const double fy = sigma > 0.0 ? sigma * normal(rng) : 0.0;
        vxs[k] = uxTarget[k] + fx;
        vys[k] = uyTarget[k] + fy;
        meanFlucX += fx;
        meanFlucY += fy;
    }
    meanFlucX /= static_cast<double>(targetN);
    meanFlucY /= static_cast<double>(targetN);

    if (params.inletHardCellVelocityMean) {
        for (int n = 0; n < targetN; ++n) {
            const std::size_t k = static_cast<std::size_t>(n);
            vxs[k] -= meanFlucX;
            vys[k] -= meanFlucY;
        }
    }

    if (params.inletHardCellThermalRescale && effectiveKBT > 0.0 && particleMass > 0.0 && targetN > 1) {
        double thermal = 0.0;
        for (int n = 0; n < targetN; ++n) {
            const std::size_t k = static_cast<std::size_t>(n);
            const double dx = vxs[k] - uxTarget[k];
            const double dy = vys[k] - uyTarget[k];
            thermal += particleMass * (dx * dx + dy * dy);
        }
        const double desired = 2.0 * static_cast<double>(targetN) * effectiveKBT;
        if (thermal > 0.0 && desired > 0.0) {
            const double scale = std::sqrt(desired / thermal);
            for (int n = 0; n < targetN; ++n) {
                const std::size_t k = static_cast<std::size_t>(n);
                vxs[k] = uxTarget[k] + scale * (vxs[k] - uxTarget[k]);
                vys[k] = uyTarget[k] + scale * (vys[k] - uyTarget[k]);
            }
        }
    }

    for (int n = 0; n < targetN; ++n) {
        const std::size_t k = static_cast<std::size_t>(n);
        append_particle(state, xs[k], ys[k], vxs[k], vys[k], particleType, particleMass);
        diag.inletMeanUx += vxs[k];
        diag.inletMeanUy += vys[k];
        const double dvx = vxs[k] - uxTarget[k];
        const double dvy = vys[k] - uyTarget[k];
        diag.inletKBT += particleMass * (dvx * dvx + dvy * dvy);
    }
    diag.inletParticlesInserted += static_cast<std::uint64_t>(targetN);
}

BoundaryDiagnostics apply_hard_inlet_reservoir_boundary(ParticleState& state,
                                                        const SimulationParams& params,
                                                        const FluidDomainBounds& domain,
                                                        std::uint64_t step,
                                                        double time) {
    BoundaryDiagnostics diag{};
    diag.inletHardReservoirEnabled = 1;
    const bool periodicX = is_x_periodic(params);
    const bool periodicY = is_y_periodic(params);
    const bool ioX = is_io_boundary_mode(params.bcLeft) || is_io_boundary_mode(params.bcRight);
    const bool ioY = is_io_boundary_mode(params.bcBottom) || is_io_boundary_mode(params.bcTop);

    const char* inletFace = is_inlet_boundary_mode(params.bcLeft) ? "left" :
                            is_inlet_boundary_mode(params.bcRight) ? "right" :
                            is_inlet_boundary_mode(params.bcBottom) ? "bottom" : "top";

    const std::uint32_t refType = state.type.empty() ? 0u : state.type.front();
    const double refMass = state.mass.empty() ? 1.0 : state.mass.front();

    ParticleState kept{};
    kept.dim = state.dim;
    kept.x.reserve(state.x.size());
    kept.y.reserve(state.y.size());
    kept.vx.reserve(state.vx.size());
    kept.vy.reserve(state.vy.size());
    kept.type.reserve(state.type.size());
    kept.mass.reserve(state.mass.size());

    ReflectionFailure firstFailure{};
    int maxXReflections = 0;
    int maxYReflections = 0;

    const std::size_t n0 = static_cast<std::size_t>(state.Np);
    for (std::size_t i = 0; i < n0; ++i) {
        double x = state.x[i];
        double y = state.y[i];
        double vx = state.vx[i];
        double vy = state.vy[i];
        const std::uint32_t type = state.type[i];
        const double mass = state.mass[i];

        if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(vx) || !std::isfinite(vy)) {
            firstFailure.failed = true;
            firstFailure.message = format_nonfinite_particle_failure(i, step, time, x, y, vx, vy);
            break;
        }

        bool remove = false;

        if (periodicX) {
            x = wrap_periodic(x, params.Lx);
        } else if (ioX) {
            if (x < domain.xMin) {
                ++diag.hitsLeft;
                if (point_in_x_face_aperture(params, domain, "left", y)) {
                    if (is_inlet_boundary_mode(params.bcLeft)) ++diag.inletBackflowDeleted;
                    else ++diag.outletParticlesDeleted;
                    remove = true;
                } else {
                    reflect_x_as_solid_face(x, vx, vy, params, domain, "left");
                }
            } else if (x > domain.xMax) {
                ++diag.hitsRight;
                if (point_in_x_face_aperture(params, domain, "right", y)) {
                    if (is_inlet_boundary_mode(params.bcRight)) ++diag.inletBackflowDeleted;
                    else ++diag.outletParticlesDeleted;
                    remove = true;
                } else {
                    reflect_x_as_solid_face(x, vx, vy, params, domain, "right");
                }
            }
        } else {
            const int r = reflect_x(x, y, vx, vy, params, domain, diag.hitsLeft, diag.hitsRight,
                                    i, step, time, firstFailure);
            maxXReflections = std::max(maxXReflections, r);
        }

        if (!remove && !firstFailure.failed) {
            if (periodicY) {
                y = wrap_periodic(y, params.Ly);
            } else if (ioY) {
                if (y < domain.yMin) {
                    ++diag.hitsBottom;
                    if (point_in_y_face_aperture(params, domain, "bottom", x)) {
                        if (is_inlet_boundary_mode(params.bcBottom)) ++diag.inletBackflowDeleted;
                        else ++diag.outletParticlesDeleted;
                        remove = true;
                    } else {
                        reflect_y_as_solid_face(y, vx, vy, params, domain, "bottom");
                    }
                } else if (y > domain.yMax) {
                    ++diag.hitsTop;
                    if (point_in_y_face_aperture(params, domain, "top", x)) {
                        if (is_inlet_boundary_mode(params.bcTop)) ++diag.inletBackflowDeleted;
                        else ++diag.outletParticlesDeleted;
                        remove = true;
                    } else {
                        reflect_y_as_solid_face(y, vx, vy, params, domain, "top");
                    }
                }
            } else {
                const int r = reflect_y(x, y, vx, vy, params, domain, diag.hitsBottom, diag.hitsTop,
                                        i, step, time, firstFailure);
                maxYReflections = std::max(maxYReflections, r);
            }
        }

        if (!remove && !firstFailure.failed && point_in_inlet_reservoir(x, y, params, domain)) {
            ++diag.inletReservoirDeleted;
            remove = true;
        }

        if (!remove && !firstFailure.failed) {
            append_particle(kept, x, y, vx, vy, type, mass);
        }
    }

    if (firstFailure.failed) {
        throw std::runtime_error(firstFailure.message);
    }

    state = std::move(kept);

    const auto cells = build_hard_reservoir_cells(params, domain, time);
    diag.inletReservoirCells = static_cast<std::uint64_t>(cells.size());
    diag.inletReservoirTargetParticles = static_cast<std::uint64_t>(cells.size()) *
                                         static_cast<std::uint64_t>(std::max(0, params.inletTargetOccupancy));
    std::uint64_t ordinal = 0u;
    for (const auto& cell : cells) {
        sample_hard_inlet_cell_particles(state, params, domain, cell, inletFace, step, ordinal++,
                                         refType, refMass, diag);
    }

    diag.inletReservoirMeanN = cells.empty() ? 0.0 : static_cast<double>(params.inletTargetOccupancy);
    diag.inletReservoirStdN = 0.0;
    diag.inletReservoirMinN = cells.empty() ? 0u : static_cast<std::uint32_t>(params.inletTargetOccupancy);
    diag.inletReservoirMaxN = cells.empty() ? 0u : static_cast<std::uint32_t>(params.inletTargetOccupancy);
    diag.inletReservoirEmptyFraction = cells.empty() ? 0.0 : (params.inletTargetOccupancy == 0 ? 1.0 : 0.0);
    if (diag.inletParticlesInserted > 0u) {
        const double inserted = static_cast<double>(diag.inletParticlesInserted);
        diag.inletMeanUx /= inserted;
        diag.inletMeanUy /= inserted;
        diag.inletKBT /= (2.0 * inserted);
    }
    const std::int64_t deleted = static_cast<std::int64_t>(diag.inletReservoirDeleted +
                                                          diag.inletBackflowDeleted +
                                                          diag.outletParticlesDeleted);
    diag.inletNetParticleDelta = static_cast<std::int64_t>(diag.inletParticlesInserted) - deleted;
    diag.maxXWallReflectionsPerParticle = maxXReflections;
    diag.maxYWallReflectionsPerParticle = maxYReflections;
    validate_particle_state(state, "apply_hard_inlet_reservoir_boundary");
    return diag;
}

} // namespace

BoundaryDiagnostics apply_boundary_conditions(ParticleState& state,
                                              const SimulationParams& params,
                                              const FluidDomainBounds& domain,
                                              std::uint64_t step,
                                              double time) {
    validate_particle_state(state, "apply_boundary_conditions");
    if (hard_inlet_reservoir_enabled(params) &&
        (is_io_boundary_mode(params.bcLeft) || is_io_boundary_mode(params.bcRight) ||
         is_io_boundary_mode(params.bcBottom) || is_io_boundary_mode(params.bcTop))) {
        return apply_hard_inlet_reservoir_boundary(state, params, domain, step, time);
    }

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const bool periodicX = is_x_periodic(params);
    const bool periodicY = is_y_periodic(params);
    const bool ioX = is_io_boundary_mode(params.bcLeft) || is_io_boundary_mode(params.bcRight);
    const bool ioY = is_io_boundary_mode(params.bcBottom) || is_io_boundary_mode(params.bcTop);

    std::uint64_t hitsLeft = 0;
    std::uint64_t hitsRight = 0;
    std::uint64_t hitsBottom = 0;
    std::uint64_t hitsTop = 0;
    int maxXReflections = 0;
    int maxYReflections = 0;
    ReflectionFailure firstFailure{};

#pragma omp parallel for reduction(+:hitsLeft,hitsRight,hitsBottom,hitsTop) reduction(max:maxXReflections,maxYReflections) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        ReflectionFailure localFailure{};

        if (!std::isfinite(state.x[i]) || !std::isfinite(state.y[i]) ||
            !std::isfinite(state.vx[i]) || !std::isfinite(state.vy[i])) {
            localFailure.failed = true;
            localFailure.message = format_nonfinite_particle_failure(
                i, step, time, state.x[i], state.y[i], state.vx[i], state.vy[i]);
        }

        if (!localFailure.failed) {
            if (periodicX) {
                state.x[i] = wrap_periodic(state.x[i], params.Lx);
            } else if (ioX) {
                (void)apply_io_x(state.x[i], state.y[i], state.vx[i], state.vy[i],
                                 params, domain, hitsLeft, hitsRight,
                                 i, step, state.mass[i]);
            } else {
                const int r = reflect_x(state.x[i], state.y[i], state.vx[i], state.vy[i],
                                        params, domain, hitsLeft, hitsRight,
                                        i, step, time, localFailure);
                maxXReflections = std::max(maxXReflections, r);
            }
        }

        if (!localFailure.failed) {
            if (periodicY) {
                state.y[i] = wrap_periodic(state.y[i], params.Ly);
            } else if (ioY) {
                (void)apply_io_y(state.x[i], state.y[i], state.vx[i], state.vy[i],
                                 params, domain, hitsBottom, hitsTop,
                                 i, step, state.mass[i]);
            } else {
                const int r = reflect_y(state.x[i], state.y[i], state.vx[i], state.vy[i],
                                        params, domain, hitsBottom, hitsTop,
                                        i, step, time, localFailure);
                maxYReflections = std::max(maxYReflections, r);
            }
        }

        if (localFailure.failed) {
#pragma omp critical(boundary_first_failure)
            {
                if (!firstFailure.failed) {
                    firstFailure = localFailure;
                }
            }
        }
    }

    if (firstFailure.failed) {
        throw std::runtime_error(firstFailure.message);
    }

    BoundaryDiagnostics diag{};
    diag.hitsLeft = hitsLeft;
    diag.hitsRight = hitsRight;
    diag.hitsBottom = hitsBottom;
    diag.hitsTop = hitsTop;
    diag.maxXWallReflectionsPerParticle = maxXReflections;
    diag.maxYWallReflectionsPerParticle = maxYReflections;
    return diag;
}

} // namespace mpcd

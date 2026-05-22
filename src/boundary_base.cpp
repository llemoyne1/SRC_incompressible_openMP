#include "boundary_base.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <sstream>
#include <stdexcept>
#include <string>

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

} // namespace

BoundaryDiagnostics apply_boundary_conditions(ParticleState& state,
                                              const SimulationParams& params,
                                              const FluidDomainBounds& domain,
                                              std::uint64_t step,
                                              double time) {
    validate_particle_state(state, "apply_boundary_conditions");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const bool periodicX = is_x_periodic(params);
    const bool periodicY = is_y_periodic(params);

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

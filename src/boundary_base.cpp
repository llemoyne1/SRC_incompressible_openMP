#include "boundary_base.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
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

void apply_wall_velocity_reflection(const std::string& mode,
                                    bool normalIsX,
                                    double& vx,
                                    double& vy) {
    if (mode == "specular") {
        if (normalIsX) {
            vx = -vx;
        } else {
            vy = -vy;
        }
    } else if (mode == "bounceback") {
        vx = -vx;
        vy = -vy;
    } else {
        throw std::runtime_error("Unsupported non-periodic wall mode during reflection: " + mode);
    }
}

void reflect_x(double& x,
               double& vx,
               double& vy,
               double Lx,
               const std::string& leftMode,
               const std::string& rightMode,
               std::uint64_t& leftHits,
               std::uint64_t& rightHits) {
    int guard = 0;
    while (x < 0.0 || x > Lx) {
        if (++guard > 64) {
            throw std::runtime_error("Too many x-wall reflections in one step; reduce dt or check velocities");
        }
        if (x < 0.0) {
            x = -x;
            ++leftHits;
            apply_wall_velocity_reflection(leftMode, true, vx, vy);
        } else if (x > Lx) {
            x = 2.0 * Lx - x;
            ++rightHits;
            apply_wall_velocity_reflection(rightMode, true, vx, vy);
        }
    }
    x = std::clamp(x, 0.0, Lx);
}

void reflect_y(double& y,
               double& vx,
               double& vy,
               double Ly,
               const std::string& bottomMode,
               const std::string& topMode,
               std::uint64_t& bottomHits,
               std::uint64_t& topHits) {
    int guard = 0;
    while (y < 0.0 || y > Ly) {
        if (++guard > 64) {
            throw std::runtime_error("Too many y-wall reflections in one step; reduce dt or check velocities");
        }
        if (y < 0.0) {
            y = -y;
            ++bottomHits;
            apply_wall_velocity_reflection(bottomMode, false, vx, vy);
        } else if (y > Ly) {
            y = 2.0 * Ly - y;
            ++topHits;
            apply_wall_velocity_reflection(topMode, false, vx, vy);
        }
    }
    y = std::clamp(y, 0.0, Ly);
}

} // namespace

BoundaryDiagnostics apply_boundary_conditions(ParticleState& state,
                                              const SimulationParams& params) {
    validate_particle_state(state, "apply_boundary_conditions");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const bool periodicX = is_x_periodic(params);
    const bool periodicY = is_y_periodic(params);

    std::uint64_t hitsLeft = 0;
    std::uint64_t hitsRight = 0;
    std::uint64_t hitsBottom = 0;
    std::uint64_t hitsTop = 0;

#pragma omp parallel for reduction(+:hitsLeft,hitsRight,hitsBottom,hitsTop) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);

        if (periodicX) {
            state.x[i] = wrap_periodic(state.x[i], params.Lx);
        } else {
            reflect_x(state.x[i], state.vx[i], state.vy[i], params.Lx,
                      params.bcLeft, params.bcRight, hitsLeft, hitsRight);
        }

        if (periodicY) {
            state.y[i] = wrap_periodic(state.y[i], params.Ly);
        } else {
            reflect_y(state.y[i], state.vx[i], state.vy[i], params.Ly,
                      params.bcBottom, params.bcTop, hitsBottom, hitsTop);
        }
    }

    BoundaryDiagnostics diag{};
    diag.hitsLeft = hitsLeft;
    diag.hitsRight = hitsRight;
    diag.hitsBottom = hitsBottom;
    diag.hitsTop = hitsTop;
    return diag;
}

} // namespace mpcd

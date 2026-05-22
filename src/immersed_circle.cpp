#include "immersed_circle.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <stdexcept>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace mpcd {
namespace {

constexpr double kTiny = 1.0e-14;

inline double wrap_periodic(double x, double L) {
    x = std::fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

inline double squared_distance_to_circle_center(double x, double y, const SimulationParams& p) {
    const double dx = x - p.immersedCircleCx;
    const double dy = y - p.immersedCircleCy;
    return dx * dx + dy * dy;
}

} // namespace

bool immersed_circle_enabled(const SimulationParams& params) {
    return params.immersedCircleEnable && params.immersedCircleR > 0.0;
}

bool point_is_inside_immersed_circle(double x, double y, const SimulationParams& params) {
    if (!immersed_circle_enabled(params)) return false;
    return squared_distance_to_circle_center(x, y, params) < params.immersedCircleR * params.immersedCircleR;
}

double immersed_circle_signed_distance(double x, double y, const SimulationParams& params) {
    if (!immersed_circle_enabled(params)) {
        return 1.0e300;
    }
    const double dx = x - params.immersedCircleCx;
    const double dy = y - params.immersedCircleCy;
    return std::sqrt(dx * dx + dy * dy) - params.immersedCircleR;
}

ImmersedCircleDiagnostics apply_immersed_circle_reflection(ParticleState& state,
                                                           const SimulationParams& params,
                                                           const FluidDomainBounds& domain) {
    (void)domain;
    ImmersedCircleDiagnostics diag{};
    if (!immersed_circle_enabled(params)) {
        return diag;
    }

    validate_particle_state(state, "apply_immersed_circle_reflection");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const double cx = params.immersedCircleCx;
    const double cy = params.immersedCircleCy;
    const double R = params.immersedCircleR;
    const double R2 = R * R;
    const double eps = 1.0e-12 * std::max(1.0, R);
    // Local wall velocity is evaluated at the penetrated particle position.
    // For the present patch the circle center is fixed, but the wall can rotate
    // rigidly around that center.

    std::uint64_t hits = 0;
#pragma omp parallel for reduction(+:hits) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const double dx = state.x[i] - cx;
        const double dy = state.y[i] - cy;
        const double r2 = dx * dx + dy * dy;
        if (!(r2 < R2)) {
            continue;
        }

        double r = std::sqrt(std::max(r2, 0.0));
        double nx = 1.0;
        double ny = 0.0;
        if (r > kTiny) {
            nx = dx / r;
            ny = dy / r;
        } else {
            r = 0.0;
        }

        // Mirror the penetrated point through the circular boundary along the
        // local normal. For small dt this is the usual post-streaming solid
        // correction; robust swept intersection can be added later if needed.
        const double rMirror = std::max(R + eps, 2.0 * R - r + eps);
        state.x[i] = cx + rMirror * nx;
        state.y[i] = cy + rMirror * ny;

        // Specular reflection in the local wall frame. This includes the
        // prescribed tangential velocity of a rotating fixed circular wall.
        double wallUx = 0.0;
        double wallUy = 0.0;
        immersed_circle_wall_velocity(params, state.x[i], state.y[i], wallUx, wallUy);
        const double vrx = state.vx[i] - wallUx;
        const double vry = state.vy[i] - wallUy;
        const double vn = vrx * nx + vry * ny;
        state.vx[i] = wallUx + vrx - 2.0 * vn * nx;
        state.vy[i] = wallUy + vry - 2.0 * vn * ny;
        hits += 1u;
    }

    diag.hits = hits;
    return diag;
}

double immersed_circle_solid_fraction_in_cell(int ix,
                                              int iy,
                                              const CellGrid& grid,
                                              const GridShift& shift,
                                              const SimulationParams& params,
                                              const FluidDomainBounds& domain) {
    if (!immersed_circle_enabled(params)) {
        return 0.0;
    }
    const int ns = std::max(1, params.immersedCircleFractionSamples);
    const double x0 = static_cast<double>(ix) * grid.dx - shift.sx;
    const double y0 = static_cast<double>(iy) * grid.dy - shift.sy;

    int inside = 0;
    const int total = ns * ns;
    for (int sy = 0; sy < ns; ++sy) {
        const double yRaw = y0 + (static_cast<double>(sy) + 0.5) * grid.dy / static_cast<double>(ns);
        double y = yRaw;
        if (is_y_periodic(params)) {
            y = wrap_periodic(y, grid.Ly);
        }
        for (int sx = 0; sx < ns; ++sx) {
            const double xRaw = x0 + (static_cast<double>(sx) + 0.5) * grid.dx / static_cast<double>(ns);
            double x = xRaw;
            if (is_x_periodic(params)) {
                x = wrap_periodic(x, grid.Lx);
            }
            if (!point_is_inside_fluid_domain(x, y, domain)) {
                continue;
            }
            if (point_is_inside_immersed_circle(x, y, params)) {
                inside += 1;
            }
        }
    }
    return static_cast<double>(inside) / static_cast<double>(total);
}

void immersed_circle_wall_velocity(const SimulationParams& params,
                                   double x,
                                   double y,
                                   double& ux,
                                   double& uy) {
    const double dx = x - params.immersedCircleCx;
    const double dy = y - params.immersedCircleCy;

    // Rigid-body wall velocity for a fixed-center rotating circle:
    // U = U0 + omega ez x r = (Ux0 - omega dy, Uy0 + omega dx).
    // U0 is kept as a uniform wall-frame velocity hook. It should remain zero
    // for genuine fixed-center rotation tests; translating geometry will be
    // implemented separately because it changes phi(x,y,t).
    ux = params.immersedCircleWallUx - params.immersedCircleOmega * dy;
    uy = params.immersedCircleWallUy + params.immersedCircleOmega * dx;
}

} // namespace mpcd

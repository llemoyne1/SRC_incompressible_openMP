#include "obstacles.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace mpcd {

namespace {

int cell_id(int ix, int iy, int Nx) {
    return ix + Nx * iy;
}

} // namespace

bool obstacle_is_active_cylinder(const Params& p) {
    return p.obstacleEnable &&
           (p.obstacleType == "cylinder" || p.obstacleType == "Cylinder") &&
           p.obstacleRadius > 0.0;
}

double cylinder_signed_distance(const Params& p, double x, double y) {
    if (!obstacle_is_active_cylinder(p)) {
        return std::numeric_limits<double>::infinity();
    }

    const double dx = x - p.obstacleCx;
    const double dy = y - p.obstacleCy;
    const double r = std::sqrt(dx * dx + dy * dy);

    return r - p.obstacleRadius;
}

ObstacleHit cylinder_query(const Params& p, double x, double y) {
    ObstacleHit q{};

    if (!obstacle_is_active_cylinder(p)) {
        q.inside = false;
        q.signedDistance = std::numeric_limits<double>::infinity();
        q.nx = 1.0;
        q.ny = 0.0;
        return q;
    }

    const double dx = x - p.obstacleCx;
    const double dy = y - p.obstacleCy;
    const double r2 = dx * dx + dy * dy;
    const double r = std::sqrt(r2);

    q.signedDistance = r - p.obstacleRadius;
    q.inside = (q.signedDistance <= 0.0);

    if (r > 1e-30) {
        q.nx = dx / r;
        q.ny = dy / r;
    } else {
        q.nx = 1.0;
        q.ny = 0.0;
    }

    return q;
}

bool point_in_obstacle(const Params& p, double x, double y) {
    return obstacle_is_active_cylinder(p) &&
           cylinder_signed_distance(p, x, y) <= 0.0;
}

std::vector<std::uint8_t> build_solid_mask(const Params& p) {
    const int Nx = std::max(0, p.Nx);
    const int Ny = std::max(0, p.Ny);

    std::vector<std::uint8_t> mask(static_cast<std::size_t>(Nx * Ny), 0);

    if (!obstacle_is_active_cylinder(p) || Nx == 0 || Ny == 0) {
        return mask;
    }

    const double dx = p.Lx / static_cast<double>(std::max(1, Nx));
    const double dy = p.Ly / static_cast<double>(std::max(1, Ny));

    for (int iy = 0; iy < Ny; ++iy) {
        const double y = (static_cast<double>(iy) + 0.5) * dy;

        for (int ix = 0; ix < Nx; ++ix) {
            const double x = (static_cast<double>(ix) + 0.5) * dx;

            if (point_in_obstacle(p, x, y)) {
                mask[static_cast<std::size_t>(cell_id(ix, iy, Nx))] = 1;
            }
        }
    }

    return mask;
}

} // namespace mpcd

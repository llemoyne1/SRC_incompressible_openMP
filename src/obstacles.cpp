#include "obstacles.h"

#include <stdexcept>
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

std::vector<double> build_fluid_fraction_mask(const Params& params,
                                              int nSub,
                                              double shiftX,
                                              double shiftY) {
    const int Nx = params.Nx;
    const int Ny = params.Ny;

    if (Nx <= 0 || Ny <= 0) {
        throw std::runtime_error("build_fluid_fraction_mask: invalid grid size");
    }

    nSub = std::max(1, nSub);

    std::vector<double> phi(static_cast<std::size_t>(Nx) * static_cast<std::size_t>(Ny), 1.0);

    if (!obstacle_is_active_cylinder(params)) {
        return phi;
    }

    const double dx = params.Lx / static_cast<double>(Nx);
    const double dy = params.Ly / static_cast<double>(Ny);
    const double invSamples = 1.0 / static_cast<double>(nSub * nSub);

    auto wrap_periodic = [](double x, double L) {
        if (L <= 0.0) {
            return x;
        }
        x = std::fmod(x, L);
        if (x < 0.0) {
            x += L;
        }
        return x;
    };

    for (int iy = 0; iy < Ny; ++iy) {
        for (int ix = 0; ix < Nx; ++ix) {
            int nFluid = 0;

            for (int sy = 0; sy < nSub; ++sy) {
                const double fy = (static_cast<double>(sy) + 0.5) / static_cast<double>(nSub);
                double y = (static_cast<double>(iy) + fy) * dy + shiftY;

                // The physical y-domain is bounded. For the diagnostic shifted mask,
                // clamp sampling to the domain instead of wrapping across walls.
                y = std::min(std::max(y, 0.0), params.Ly);

                for (int sx = 0; sx < nSub; ++sx) {
                    const double fx = (static_cast<double>(sx) + 0.5) / static_cast<double>(nSub);
                    double x = (static_cast<double>(ix) + fx) * dx + shiftX;

                    // The streamwise direction is periodic in the current Poiseuille setup.
                    x = wrap_periodic(x, params.Lx);

                    if (!point_in_obstacle(params, x, y)) {
                        ++nFluid;
                    }
                }
            }

            phi[static_cast<std::size_t>(ix) + static_cast<std::size_t>(Nx) * static_cast<std::size_t>(iy)] =
                static_cast<double>(nFluid) * invSamples;
        }
    }

    return phi;
}

FluidFractionMaskSummary summarize_fluid_fraction_mask(const Params& params,
                                                       const std::vector<double>& phi,
                                                       double phiSolidTol,
                                                       double phiFullTol) {
    const int nExpected = params.Nx * params.Ny;
    if (static_cast<int>(phi.size()) != nExpected) {
        throw std::runtime_error("summarize_fluid_fraction_mask: mask size does not match grid");
    }

    FluidFractionMaskSummary s;
    s.nCells = nExpected;

    for (double p : phi) {
        s.sumFluidFraction += p;

        if (p <= phiSolidTol) {
            ++s.nSolidCells;
        } else if (p >= 1.0 - phiFullTol) {
            ++s.nFullFluidCells;
        } else {
            ++s.nPartialCells;
        }
    }

    if (s.sumFluidFraction > 0.0) {
        s.gammaFluidObstacle = static_cast<double>(params.n) / s.sumFluidFraction;
    }

    return s;
}


} // namespace mpcd

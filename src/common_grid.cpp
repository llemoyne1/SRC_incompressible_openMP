#include "common_grid.h"

#include <cmath>
#include <limits>
#include <stdexcept>

namespace mpcd {

int cell_id_from_position(double x, double y, const Params& params) {
    const double dx = params.Lx / static_cast<double>(params.Nx);
    const double dy = params.Ly / static_cast<double>(params.Ny);
    int ix = static_cast<int>(std::floor(x / dx));
    int iy = static_cast<int>(std::floor(y / dy));
    if (ix < 0) ix = 0;
    if (ix >= params.Nx) ix = params.Nx - 1;
    if (iy < 0) iy = 0;
    if (iy >= params.Ny) iy = params.Ny - 1;
    return iy + params.Ny * ix;
}

std::vector<int> build_cell_ids(const std::vector<double>& x, const Params& params) {
    if (x.size() != static_cast<std::size_t>(2 * params.n)) {
        throw std::runtime_error("build_cell_ids: unexpected x size");
    }
    std::vector<int> cid(static_cast<std::size_t>(params.n));
    for (int i = 0; i < params.n; ++i) {
        cid[static_cast<std::size_t>(i)] = cell_id_from_position(x[2 * i], x[2 * i + 1], params);
    }
    return cid;
}

CellFields compute_cell_fields(const std::vector<double>& x,
                               const std::vector<double>& v,
                               const Params& params,
                               double rhoTargetScalar) {
    if (x.size() != static_cast<std::size_t>(2 * params.n) ||
        v.size() != static_cast<std::size_t>(2 * params.n)) {
        throw std::runtime_error("compute_cell_fields: unexpected state size");
    }

    const int Nc = params.Nc;
    const double dx = params.Lx / static_cast<double>(params.Nx);
    const double dy = params.Ly / static_cast<double>(params.Ny);
    const double Vc = dx * dy;

    CellFields G{};
    G.Nx = params.Nx;
    G.Ny = params.Ny;
    G.N.assign(static_cast<std::size_t>(Nc), 0);
    G.Ux.assign(static_cast<std::size_t>(Nc), 0.0);
    G.Uy.assign(static_cast<std::size_t>(Nc), 0.0);
    G.Px.assign(static_cast<std::size_t>(Nc), 0.0);
    G.Py.assign(static_cast<std::size_t>(Nc), 0.0);
    G.T.assign(static_cast<std::size_t>(Nc), std::numeric_limits<double>::quiet_NaN());
    G.rho.assign(static_cast<std::size_t>(Nc), 0.0);
    G.Pkin.assign(static_cast<std::size_t>(Nc), 0.0);
    G.Pvir.assign(static_cast<std::size_t>(Nc), 0.0);
    G.P.assign(static_cast<std::size_t>(Nc), 0.0);
    G.rhoTarget.assign(static_cast<std::size_t>(Nc), rhoTargetScalar);

    std::vector<int> cid = build_cell_ids(x, params);
    for (int i = 0; i < params.n; ++i) {
        const int c = cid[static_cast<std::size_t>(i)];
        G.N[static_cast<std::size_t>(c)] += 1;
        G.Px[static_cast<std::size_t>(c)] += v[2 * i];
        G.Py[static_cast<std::size_t>(c)] += v[2 * i + 1];
    }

    for (int c = 0; c < Nc; ++c) {
        if (G.N[static_cast<std::size_t>(c)] > 0) {
            G.Ux[static_cast<std::size_t>(c)] = G.Px[static_cast<std::size_t>(c)] / static_cast<double>(G.N[static_cast<std::size_t>(c)]);
            G.Uy[static_cast<std::size_t>(c)] = G.Py[static_cast<std::size_t>(c)] / static_cast<double>(G.N[static_cast<std::size_t>(c)]);
        }
        G.rho[static_cast<std::size_t>(c)] = static_cast<double>(G.N[static_cast<std::size_t>(c)]) / Vc;
    }

    std::vector<double> sumRel2(static_cast<std::size_t>(Nc), 0.0);
    for (int i = 0; i < params.n; ++i) {
        const int c = cid[static_cast<std::size_t>(i)];
        const double dvx = v[2 * i] - G.Ux[static_cast<std::size_t>(c)];
        const double dvy = v[2 * i + 1] - G.Uy[static_cast<std::size_t>(c)];
        sumRel2[static_cast<std::size_t>(c)] += dvx * dvx + dvy * dvy;
    }

    for (int c = 0; c < Nc; ++c) {
        const int N = G.N[static_cast<std::size_t>(c)];
        const int dof = 2 * std::max(N - 1, 0);
        if (dof > 0) {
            G.T[static_cast<std::size_t>(c)] = sumRel2[static_cast<std::size_t>(c)] / static_cast<double>(dof);
            G.Pkin[static_cast<std::size_t>(c)] = G.rho[static_cast<std::size_t>(c)] * G.T[static_cast<std::size_t>(c)];
        } else {
            G.T[static_cast<std::size_t>(c)] = 0.0;
            G.Pkin[static_cast<std::size_t>(c)] = 0.0;
        }
        G.Pvir[static_cast<std::size_t>(c)] = params.Kvirial * (G.rho[static_cast<std::size_t>(c)] - G.rhoTarget[static_cast<std::size_t>(c)]);
        G.P[static_cast<std::size_t>(c)] = G.Pkin[static_cast<std::size_t>(c)] + G.Pvir[static_cast<std::size_t>(c)];
    }

    return G;
}

} // namespace mpcd

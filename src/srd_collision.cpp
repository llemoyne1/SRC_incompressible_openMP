#include "srd_collision.h"

#include <cmath>
#include <random>
#include <stdexcept>

namespace mpcd {

std::vector<int> srd_cell_id_with_random_shift(const std::vector<double>& x,
                                               const Params& params,
                                               std::uint64_t rng_seed) {
    std::mt19937_64 rng(rng_seed);
    std::uniform_real_distribution<double> unif(-0.5 * params.a0, 0.5 * params.a0);
    const double sx = unif(rng);
    const double sy = unif(rng);

    std::vector<int> cid(static_cast<std::size_t>(params.n));
    for (int i = 0; i < params.n; ++i) {
        double xs = x[2 * i] + sx;
        double ys = x[2 * i + 1] + sy;

        if (params.boundary_left == "periodic" && params.boundary_right == "periodic") {
            xs = xs - std::floor(xs / params.Lx) * params.Lx;
        } else {
            if (xs < 0.0) xs = 0.0;
            if (xs >= params.Lx) xs = std::nextafter(params.Lx, 0.0);
        }

        if (params.boundary_bottom == "periodic" && params.boundary_top == "periodic") {
            ys = ys - std::floor(ys / params.Ly) * params.Ly;
        } else {
            if (ys < 0.0) ys = 0.0;
            if (ys >= params.Ly) ys = std::nextafter(params.Ly, 0.0);
        }

        int ix = static_cast<int>(std::floor(xs / params.a0));
        int iy = static_cast<int>(std::floor(ys / params.a0));
        if (ix < 0) ix = 0;
        if (ix >= params.Nx) ix = params.Nx - 1;
        if (iy < 0) iy = 0;
        if (iy >= params.Ny) iy = params.Ny - 1;
        cid[static_cast<std::size_t>(i)] = iy + params.Ny * ix;
    }
    return cid;
}

void srd_collision_step(std::vector<double>& v,
                        const std::vector<int>& cid,
                        const Params& params,
                        std::uint64_t rng_seed) {
    if (cid.size() != static_cast<std::size_t>(params.n)) {
        throw std::runtime_error("srd_collision_step: unexpected cid size");
    }

    std::mt19937_64 rng(rng_seed);
    std::uniform_real_distribution<double> unif01(0.0, 1.0);

    std::vector<int> cnt(static_cast<std::size_t>(params.Nc), 0);
    std::vector<double> sumx(static_cast<std::size_t>(params.Nc), 0.0);
    std::vector<double> sumy(static_cast<std::size_t>(params.Nc), 0.0);
    for (int i = 0; i < params.n; ++i) {
        const int c = cid[static_cast<std::size_t>(i)];
        cnt[static_cast<std::size_t>(c)] += 1;
        sumx[static_cast<std::size_t>(c)] += v[2 * i];
        sumy[static_cast<std::size_t>(c)] += v[2 * i + 1];
    }

    std::vector<double> ux(static_cast<std::size_t>(params.Nc), 0.0);
    std::vector<double> uy(static_cast<std::size_t>(params.Nc), 0.0);
    for (int c = 0; c < params.Nc; ++c) {
        if (cnt[static_cast<std::size_t>(c)] > 0) {
            ux[static_cast<std::size_t>(c)] = sumx[static_cast<std::size_t>(c)] / static_cast<double>(cnt[static_cast<std::size_t>(c)]);
            uy[static_cast<std::size_t>(c)] = sumy[static_cast<std::size_t>(c)] / static_cast<double>(cnt[static_cast<std::size_t>(c)]);
        }
    }

    std::vector<double> theta(static_cast<std::size_t>(params.Nc), 0.0);
    for (int c = 0; c < params.Nc; ++c) {
        if (cnt[static_cast<std::size_t>(c)] >= 2) {
            const double sgn = (unif01(rng) < 0.5) ? -1.0 : 1.0;
            theta[static_cast<std::size_t>(c)] = params.alpha * sgn;
        }
    }

    std::vector<double> rel2(static_cast<std::size_t>(params.n), 0.0);
    std::vector<double> vxr2(static_cast<std::size_t>(params.n), 0.0);
    std::vector<double> vyr2(static_cast<std::size_t>(params.n), 0.0);

    for (int i = 0; i < params.n; ++i) {
        const int c = cid[static_cast<std::size_t>(i)];
        const double vxr = v[2 * i] - ux[static_cast<std::size_t>(c)];
        const double vyr = v[2 * i + 1] - uy[static_cast<std::size_t>(c)];
        const double ct = std::cos(theta[static_cast<std::size_t>(c)]);
        const double st = std::sin(theta[static_cast<std::size_t>(c)]);
        vxr2[static_cast<std::size_t>(i)] = ct * vxr - st * vyr;
        vyr2[static_cast<std::size_t>(i)] = st * vxr + ct * vyr;
        rel2[static_cast<std::size_t>(i)] = vxr2[static_cast<std::size_t>(i)] * vxr2[static_cast<std::size_t>(i)] + vyr2[static_cast<std::size_t>(i)] * vyr2[static_cast<std::size_t>(i)];
    }

    if (params.useThermostat) {
        std::vector<double> sumRel2(static_cast<std::size_t>(params.Nc), 0.0);
        for (int i = 0; i < params.n; ++i) {
            sumRel2[static_cast<std::size_t>(cid[static_cast<std::size_t>(i)])] += rel2[static_cast<std::size_t>(i)];
        }
        std::vector<double> lambda(static_cast<std::size_t>(params.Nc), 1.0);
        for (int c = 0; c < params.Nc; ++c) {
            const int dof = 2 * std::max(cnt[static_cast<std::size_t>(c)] - 1, 0);
            if (cnt[static_cast<std::size_t>(c)] > 1 && sumRel2[static_cast<std::size_t>(c)] > 0.0) {
                const double target = static_cast<double>(dof) * params.kBT;
                lambda[static_cast<std::size_t>(c)] = std::sqrt(target / sumRel2[static_cast<std::size_t>(c)]);
            }
        }
        for (int i = 0; i < params.n; ++i) {
            const double lam = lambda[static_cast<std::size_t>(cid[static_cast<std::size_t>(i)])];
            vxr2[static_cast<std::size_t>(i)] *= lam;
            vyr2[static_cast<std::size_t>(i)] *= lam;
        }
    }

    for (int i = 0; i < params.n; ++i) {
        const int c = cid[static_cast<std::size_t>(i)];
        v[2 * i] = ux[static_cast<std::size_t>(c)] + vxr2[static_cast<std::size_t>(i)];
        v[2 * i + 1] = uy[static_cast<std::size_t>(c)] + vyr2[static_cast<std::size_t>(i)];
    }

    if (params.keepMeanFlow) {
        double meanx = 0.0;
        double meany = 0.0;
        for (int i = 0; i < params.n; ++i) {
            meanx += v[2 * i];
            meany += v[2 * i + 1];
        }
        meanx /= static_cast<double>(params.n);
        meany /= static_cast<double>(params.n);
        for (int i = 0; i < params.n; ++i) {
            v[2 * i] -= meanx;
            v[2 * i + 1] -= meany;
        }
    }
}

} // namespace mpcd

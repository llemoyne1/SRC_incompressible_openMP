#include "zone_pass.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <limits>
#include <numeric>
#include <random>
#include <stdexcept>
#include <unordered_set>
#include <utility>

#include "common_grid.h"
#include "obstacles.h"

namespace mpcd {
namespace {

struct Zone {
    int id = 0;
    std::vector<int> cellIds;
    std::vector<char> maskVec;
};

struct Layout {
    std::string mode;
    std::vector<Zone> zones;
    std::vector<std::int32_t> ownerMap;
};

struct ThresholdMaps {
    std::vector<double> fMap;
    std::vector<double> gammaLocMap;
    std::vector<double> lowThrLocMap;
    std::vector<double> highThrLocMap;
};

struct CorrMasks {
    std::vector<char> recvMask;
    std::vector<char> momCorrBulkBulkMask;
    std::vector<char> momCorrSkipMask;
};

struct ZoneKernelResult {
    std::array<double,6> stats{};
    std::array<double,10> diag{};
    int movedDense = 0;
    int movedSparse = 0;
};

struct CandidateDense {
    int nb = 0;
    double deficitNeg = 0.0;
    double inwardNeg = 0.0;
    int cnt = 0;
    int cheb = 0;
    int dist2 = 0;
    double randTie = 0.0;
};

int wrap_index(int i, int n) {
    int r = i % n;
    return (r < 0) ? (r + n) : r;
}

bool periodic_x(const Params& p) {
    return p.boundary_left == "periodic" && p.boundary_right == "periodic";
}

bool periodic_y(const Params& p) {
    return p.boundary_bottom == "periodic" && p.boundary_top == "periodic";
}

int cell_id_from_iy_ix(int iy, int ix, const Params& p) {
    return iy + p.Ny * ix;
}

void iy_ix_from_cell_id(int cid, const Params& p, int& iy, int& ix) {
    ix = cid / p.Ny;
    iy = cid - ix * p.Ny;
}

std::vector<int> unique_stable(const std::vector<int>& in) {
    std::unordered_set<int> seen;
    std::vector<int> out;
    out.reserve(in.size());
    for (int v : in) {
        if (seen.insert(v).second) {
            out.push_back(v);
        }
    }
    return out;
}

std::vector<int> build_cell_ids_interleaved(const std::vector<double>& x, const Params& params) {
    std::vector<int> cid(static_cast<std::size_t>(params.n), 0);
    const double dx = params.Lx / static_cast<double>(params.Nx);
    const double dy = params.Ly / static_cast<double>(params.Ny);
    for (int i = 0; i < params.n; ++i) {
        int ix = static_cast<int>(std::floor(x[2 * i] / dx));
        int iy = static_cast<int>(std::floor(x[2 * i + 1] / dy));
        if (ix < 0) ix = 0;
        if (ix >= params.Nx) ix = params.Nx - 1;
        if (iy < 0) iy = 0;
        if (iy >= params.Ny) iy = params.Ny - 1;
        cid[static_cast<std::size_t>(i)] = cell_id_from_iy_ix(iy, ix, params);
    }
    return cid;
}

std::vector<std::vector<int>> build_parts_in_cell(const std::vector<int>& cellId, const Params& params) {
    std::vector<std::vector<int>> parts(static_cast<std::size_t>(params.Nc));
    for (int i = 0; i < params.n; ++i) {
        parts[static_cast<std::size_t>(cellId[static_cast<std::size_t>(i)])].push_back(i);
    }
    return parts;
}

std::vector<int> build_counts_from_parts(const std::vector<std::vector<int>>& parts, const Params& params) {
    std::vector<int> cnt(static_cast<std::size_t>(params.Nc), 0);
    for (int c = 0; c < params.Nc; ++c) {
        cnt[static_cast<std::size_t>(c)] = static_cast<int>(parts[static_cast<std::size_t>(c)].size());
    }
    return cnt;
}

std::vector<char> build_active_mask_vec(const Params& params) {
    return std::vector<char>(static_cast<std::size_t>(params.Nc), 1);
}

constexpr double kSolidPhiTol = 1e-12;
// Conservative threshold for redistribution activity.
// With this value, only cells that are effectively fully fluid act as
// donors/receivers. Partial cut-cells are left to the dynamics and wall
// reflection instead of being artificially filled by redistribution.
constexpr double kRedistributionPhiMin = 1.0 - 1e-12;

std::vector<double> canonical_fluid_fraction_mask(const Params& params,
                                                  const std::vector<double>& fluidFractionMask) {
    if (static_cast<int>(fluidFractionMask.size()) == params.Nc) {
        return fluidFractionMask;
    }

    if (obstacle_is_active_cylinder(params)) {
        return build_fluid_fraction_mask(params, 8, 0.0, 0.0);
    }

    return std::vector<double>(static_cast<std::size_t>(params.Nc), 1.0);
}

double gamma_from_fluid_fraction_mask(const Params& params,
                                      const std::vector<double>& phi) {
    double sumPhi = 0.0;
    for (double p : phi) {
        if (p > kSolidPhiTol) {
            sumPhi += p;
        }
    }

    if (sumPhi <= 0.0) {
        return params.gamma;
    }

    return static_cast<double>(params.n) / sumPhi;
}

void apply_solid_fluid_thresholds(const std::vector<double>& phi,
                                  double gammaFluid,
                                  const Params& params,
                                  const std::vector<char>& activeMaskVec,
                                  std::vector<int>& bulkMask,
                                  std::vector<double>& lowThrActiveMap,
                                  std::vector<double>& highThrActiveMap) {
    const double coef = params.coef;

    for (int c = 0; c < params.Nc; ++c) {
        const double phic = phi[static_cast<std::size_t>(c)];

        if (!activeMaskVec[static_cast<std::size_t>(c)] || phic < kRedistributionPhiMin) {
            bulkMask[static_cast<std::size_t>(c)] = 0;
            lowThrActiveMap[static_cast<std::size_t>(c)] = 0.0;
            highThrActiveMap[static_cast<std::size_t>(c)] = 0.0;
            continue;
        }

        const double target = gammaFluid * phic;

        if (params.lowMode == "1+coef") {
            lowThrActiveMap[static_cast<std::size_t>(c)] = target / (1.0 + coef);
        } else {
            lowThrActiveMap[static_cast<std::size_t>(c)] = target * (1.0 - coef);
        }

        if (params.highMode == "1+coef") {
            highThrActiveMap[static_cast<std::size_t>(c)] = target * (1.0 + coef);
        } else {
            highThrActiveMap[static_cast<std::size_t>(c)] = target + target * coef;
        }

        lowThrActiveMap[static_cast<std::size_t>(c)] =
            std::max(lowThrActiveMap[static_cast<std::size_t>(c)], 0.0);
        highThrActiveMap[static_cast<std::size_t>(c)] =
            std::max(highThrActiveMap[static_cast<std::size_t>(c)],
                     lowThrActiveMap[static_cast<std::size_t>(c)]);
    }
}


std::pair<double,double> total_momentum(const std::vector<double>& v, int n) {
    double px = 0.0, py = 0.0;
    for (int i = 0; i < n; ++i) {
        px += v[2 * i];
        py += v[2 * i + 1];
    }
    return {px, py};
}

void cell_total_momentum(const std::vector<std::vector<int>>& parts,
                         const std::vector<double>& v,
                         const Params& params,
                         std::vector<double>& Px,
                         std::vector<double>& Py) {
    Px.assign(static_cast<std::size_t>(params.Nc), 0.0);
    Py.assign(static_cast<std::size_t>(params.Nc), 0.0);
    for (int c = 0; c < params.Nc; ++c) {
        const auto& ids = parts[static_cast<std::size_t>(c)];
        double px = 0.0, py = 0.0;
        for (int id : ids) {
            px += v[2 * id];
            py += v[2 * id + 1];
        }
        Px[static_cast<std::size_t>(c)] = px;
        Py[static_cast<std::size_t>(c)] = py;
    }
}

std::vector<int> build_start_indices(int N, int tile, int offset) {
    std::vector<int> starts;
    starts.push_back(0);
    for (int s = offset; s < N; s += tile) {
        if (s > 0 && s < N) {
            starts.push_back(s);
        }
    }
    std::sort(starts.begin(), starts.end());
    starts.erase(std::unique(starts.begin(), starts.end()), starts.end());
    return starts;
}

Layout build_layout(const Params& params, const std::string& mode) {
    Layout L{};
    L.mode = mode;
    L.ownerMap.assign(static_cast<std::size_t>(params.Nc), 0);

    if (mode == "single_full" || params.zoneSingleFullDomainMode) {
        Zone z{};
        z.id = 1;
        z.cellIds.reserve(static_cast<std::size_t>(params.Nc));
        z.maskVec.assign(static_cast<std::size_t>(params.Nc), 1);
        for (int c = 0; c < params.Nc; ++c) {
            z.cellIds.push_back(c);
            L.ownerMap[static_cast<std::size_t>(c)] = 1;
        }
        L.zones.push_back(std::move(z));
        return L;
    }

    int offx = 0;
    int offy = 0;
    if (mode == "shifted") {
        offx = params.zoneTileNx / 2;
        offy = params.zoneTileNy / 2;
    }

    const auto xStarts = build_start_indices(params.Nx, params.zoneTileNx, offx);
    const auto yStarts = build_start_indices(params.Ny, params.zoneTileNy, offy);

    int id = 0;
    for (int ys : yStarts) {
        for (int xs : xStarts) {
            const int xe = std::min(xs + params.zoneTileNx, params.Nx);
            const int ye = std::min(ys + params.zoneTileNy, params.Ny);
            Zone z{};
            z.id = ++id;
            z.maskVec.assign(static_cast<std::size_t>(params.Nc), 0);
            for (int ix = xs; ix < xe; ++ix) {
                for (int iy = ys; iy < ye; ++iy) {
                    const int c = cell_id_from_iy_ix(iy, ix, params);
                    z.cellIds.push_back(c);
                    z.maskVec[static_cast<std::size_t>(c)] = 1;
                    L.ownerMap[static_cast<std::size_t>(c)] = z.id;
                }
            }
            L.zones.push_back(std::move(z));
        }
    }
    return L;
}

bool is_periodic_pair(const Params& params, char axis) {
    if (axis == 'x') return periodic_x(params);
    if (axis == 'y') return periodic_y(params);
    throw std::runtime_error("invalid axis");
}

std::pair<int,int> minimal_step(int srcCell, int dstCell, const Params& params) {
    int sy = 0, sx = 0, dy = 0, dx = 0;
    iy_ix_from_cell_id(srcCell, params, sy, sx);
    iy_ix_from_cell_id(dstCell, params, dy, dx);
    int ddx = dx - sx;
    int ddy = dy - sy;
    if (periodic_x(params)) {
        if (ddx > params.Nx / 2) ddx -= params.Nx;
        if (ddx < -params.Nx / 2) ddx += params.Nx;
    }
    if (periodic_y(params)) {
        if (ddy > params.Ny / 2) ddy -= params.Ny;
        if (ddy < -params.Ny / 2) ddy += params.Ny;
    }
    return {ddx, ddy};
}

bool shift_index(int iy, int ix, int dy, int dx, const Params& params, int& jy, int& jx) {
    jy = iy + dy;
    if (periodic_y(params)) {
        jy = wrap_index(jy, params.Ny);
    } else if (jy < 0 || jy >= params.Ny) {
        return false;
    }

    jx = ix + dx;
    if (periodic_x(params)) {
        jx = wrap_index(jx, params.Nx);
    } else if (jx < 0 || jx >= params.Nx) {
        return false;
    }
    return true;
}

std::vector<int> local_neighbors_in_zone(int cell, const Zone& zone, const Params& params, int rangeR) {
    int iy = 0, ix = 0;
    iy_ix_from_cell_id(cell, params, iy, ix);
    std::vector<int> neigh;
    neigh.reserve(static_cast<std::size_t>((2 * rangeR + 1) * (2 * rangeR + 1) - 1));
    for (int dy = -rangeR; dy <= rangeR; ++dy) {
        for (int dx = -rangeR; dx <= rangeR; ++dx) {
            if (dx == 0 && dy == 0) continue;
            int jy = 0, jx = 0;
            if (!shift_index(iy, ix, dy, dx, params, jy, jx)) continue;
            int c = cell_id_from_iy_ix(jy, jx, params);
            if (zone.maskVec[static_cast<std::size_t>(c)]) neigh.push_back(c);
        }
    }
    return unique_stable(neigh);
}

std::vector<double> sample_in_cell(int cell, int n, const Params& params, std::mt19937_64& rng) {
    std::uniform_real_distribution<double> U(0.0, 1.0);
    int iy = 0, ix = 0;
    iy_ix_from_cell_id(cell, params, iy, ix);
    const double dx = params.Lx / static_cast<double>(params.Nx);
    const double dy = params.Ly / static_cast<double>(params.Ny);
    const double x0 = static_cast<double>(ix) * dx;
    const double y0 = static_cast<double>(iy) * dy;

    std::vector<double> out(static_cast<std::size_t>(2 * n), 0.0);

    for (int k = 0; k < n; ++k) {
        bool accepted = false;

        for (int attempt = 0; attempt < 256; ++attempt) {
            const double xc = x0 + dx * U(rng);
            const double yc = y0 + dy * U(rng);

            if (!point_in_obstacle(params, xc, yc)) {
                out[2 * k] = xc;
                out[2 * k + 1] = yc;
                accepted = true;
                break;
            }
        }

        if (!accepted) {
            out[2 * k] = x0 + dx * U(rng);
            out[2 * k + 1] = y0 + dy * U(rng);
        }
    }

    return out;
}

std::vector<double> smooth_occupancy_field(const std::vector<int>& cntVec, const Params& params) {
    const std::array<double, 9> K{{1.0/16.0, 2.0/16.0, 1.0/16.0,
                                   2.0/16.0, 4.0/16.0, 2.0/16.0,
                                   1.0/16.0, 2.0/16.0, 1.0/16.0}};
    std::vector<double> out(static_cast<std::size_t>(params.Nc), 0.0);
    for (int ix = 0; ix < params.Nx; ++ix) {
        for (int iy = 0; iy < params.Ny; ++iy) {
            double acc = 0.0, wsum = 0.0;
            int kk = 0;
            for (int dy = -1; dy <= 1; ++dy) {
                for (int dx = -1; dx <= 1; ++dx, ++kk) {
                    int jy = iy + dy;
                    int jx = ix + dx;
                    if (jy < 0 || jy >= params.Ny || jx < 0 || jx >= params.Nx) continue;
                    const double w = K[static_cast<std::size_t>(kk)];
                    acc += w * static_cast<double>(cntVec[static_cast<std::size_t>(cell_id_from_iy_ix(jy, jx, params))]);
                    wsum += w;
                }
            }
            out[static_cast<std::size_t>(cell_id_from_iy_ix(iy, ix, params))] = acc / std::max(wsum, 1e-30);
        }
    }
    return out;
}

ThresholdMaps build_local_fluid_fraction_threshold_maps(const std::vector<double>& Nsm, const Params& params) {
    ThresholdMaps T{};
    T.fMap.assign(static_cast<std::size_t>(params.Nc), 0.0);
    T.gammaLocMap.assign(static_cast<std::size_t>(params.Nc), 0.0);
    T.lowThrLocMap.assign(static_cast<std::size_t>(params.Nc), 0.0);
    T.highThrLocMap.assign(static_cast<std::size_t>(params.Nc), 0.0);

    const double gamma = params.gamma;
    const double coef = params.coef;
    const double lowFrac = 1.0 / (1.0 + coef);
    const double highFrac = 1.0 + coef;

    for (int c = 0; c < params.Nc; ++c) {
        double f = 1.0;
        if (params.useLocalFluidFractionThresholds) {
            const double fRaw = Nsm[static_cast<std::size_t>(c)] / std::max(gamma, 1e-12);
            f = std::clamp(params.fluidFracGain * fRaw, 0.0, 1.0);
        }
        T.fMap[static_cast<std::size_t>(c)] = f;
        T.gammaLocMap[static_cast<std::size_t>(c)] = gamma * f;
        T.lowThrLocMap[static_cast<std::size_t>(c)] = std::max(lowFrac * T.gammaLocMap[static_cast<std::size_t>(c)], params.lowThrFloor);
        T.highThrLocMap[static_cast<std::size_t>(c)] = std::max(highFrac * T.gammaLocMap[static_cast<std::size_t>(c)], params.highThrFloor);
    }
    return T;
}

std::tuple<double,double,double> occupancy_thresholds(const Params& params) {
    const double gamma = params.gamma;
    const double coef = params.coef;
    double highThr = 0.0;
    if (params.highMode == "1+coef") {
        highThr = gamma * (1.0 + coef);
    } else {
        highThr = gamma + gamma * coef;
    }
    double lowThrBulk = 0.0;
    if (params.lowMode == "1+coef") {
        lowThrBulk = gamma / (1.0 + coef);
    } else {
        lowThrBulk = gamma - gamma * coef;
    }
    double lowThrInterface = std::max(0.0, lowThrBulk - 1.0);
    if (std::isfinite(params.lowThrBulkOverride)) lowThrBulk = params.lowThrBulkOverride;
    lowThrInterface = std::min(lowThrInterface, lowThrBulk);
    return {highThr, lowThrBulk, lowThrInterface};
}

std::vector<int> build_topological_bulk_mask(const std::vector<int>& cntVec, const Params& params) {
    // no-surface branch used in C++ V1: MATLAB immediately overrides with (cntVec>0)&activeMaskVec.
    std::vector<int> bulk(static_cast<std::size_t>(params.Nc), 0);
    for (int c = 0; c < params.Nc; ++c) bulk[static_cast<std::size_t>(c)] = (cntVec[static_cast<std::size_t>(c)] > 0) ? 1 : 0;
    return bulk;
}

std::pair<double,double> inward_direction_from_local_gradient(int cell, const std::vector<double>& Nsm, const Params& params) {
    int iy = 0, ix = 0;
    iy_ix_from_cell_id(cell, params, iy, ix);
    auto local_diff_x = [&](int iy0, int ix0) {
        if (is_periodic_pair(params, 'x')) {
            const int ixm = wrap_index(ix0 - 1, params.Nx);
            const int ixp = wrap_index(ix0 + 1, params.Nx);
            return 0.5 * (Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0, ixp, params))] -
                          Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0, ixm, params))]);
        }
        if (ix0 == 0) {
            return Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0, ix0 + 1, params))] - Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0, ix0, params))];
        }
        if (ix0 == params.Nx - 1) {
            return Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0, ix0, params))] - Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0, ix0 - 1, params))];
        }
        return 0.5 * (Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0, ix0 + 1, params))] -
                      Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0, ix0 - 1, params))]);
    };
    auto local_diff_y = [&](int iy0, int ix0) {
        if (is_periodic_pair(params, 'y')) {
            const int iym = wrap_index(iy0 - 1, params.Ny);
            const int iyp = wrap_index(iy0 + 1, params.Ny);
            return 0.5 * (Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iyp, ix0, params))] -
                          Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iym, ix0, params))]);
        }
        if (iy0 == 0) {
            return Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0 + 1, ix0, params))] - Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0, ix0, params))];
        }
        if (iy0 == params.Ny - 1) {
            return Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0, ix0, params))] - Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0 - 1, ix0, params))];
        }
        return 0.5 * (Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0 + 1, ix0, params))] -
                      Nsm[static_cast<std::size_t>(cell_id_from_iy_ix(iy0 - 1, ix0, params))]);
    };
    return {local_diff_x(iy, ix), local_diff_y(iy, ix)};
}

std::vector<int> admissible_dense_targets_rangeR(int cell,
                                                 const std::vector<int>& cntVec,
                                                 const std::vector<double>& targetMap,
                                                 const Params& params,
                                                 int rangeR) {
    int iy = 0, ix = 0;
    iy_ix_from_cell_id(cell, params, iy, ix);
    std::vector<int> lst;
    lst.reserve(static_cast<std::size_t>((2 * rangeR + 1) * (2 * rangeR + 1) - 1));
    for (int dy = -rangeR; dy <= rangeR; ++dy) {
        for (int dx = -rangeR; dx <= rangeR; ++dx) {
            if (dx == 0 && dy == 0) continue;
            int jy = 0, jx = 0;
            if (!shift_index(iy, ix, dy, dx, params, jy, jx)) continue;
            const int nb = cell_id_from_iy_ix(jy, jx, params);
            if (static_cast<double>(cntVec[static_cast<std::size_t>(nb)]) < targetMap[static_cast<std::size_t>(nb)]) {
                lst.push_back(nb);
            }
        }
    }
    return unique_stable(lst);
}

std::vector<int> rank_dense_targets_unified(int cell,
                                            std::vector<int> admiss,
                                            const std::vector<int>& cntVec,
                                            const std::vector<double>& targetMap,
                                            const std::pair<double,double>& nHat,
                                            double inwardWeight,
                                            const Params& params,
                                            std::mt19937_64& rng) {
    if (admiss.empty()) return {};
    constexpr int nBins = 8;
    std::array<std::vector<CandidateDense>, nBins> bins;
    std::uniform_real_distribution<double> U01(0.0, 1.0);
    std::uniform_int_distribution<int> UBin(1, nBins);
    const int startBin = UBin(rng) - 1;
    for (int nb : admiss) {
        auto [dx, dy] = minimal_step(cell, nb, params);
        const double ang = std::atan2(static_cast<double>(dy), static_cast<double>(dx));
        int ib = static_cast<int>(std::floor((ang + M_PI) / (2.0 * M_PI / static_cast<double>(nBins))));
        ib = ((ib % nBins) + nBins) % nBins;
        const double deficit = std::max(0.0, targetMap[static_cast<std::size_t>(nb)] - static_cast<double>(cntVec[static_cast<std::size_t>(nb)]));
        const int dist2 = dx * dx + dy * dy;
        const int cheb = std::max(std::abs(dx), std::abs(dy));
        double inward = 0.0;
        const double nstep = std::hypot(static_cast<double>(dx), static_cast<double>(dy));
        if (inwardWeight > 0.0 && nstep > 0.0) {
            inward = (static_cast<double>(dx) * nHat.first + static_cast<double>(dy) * nHat.second) / nstep;
        }
        bins[static_cast<std::size_t>(ib)].push_back(CandidateDense{nb, -deficit, -inwardWeight * inward,
                                                                    cntVec[static_cast<std::size_t>(nb)], cheb, dist2, U01(rng)});
    }
    auto cmp = [](const CandidateDense& a, const CandidateDense& b) {
        if (a.deficitNeg != b.deficitNeg) return a.deficitNeg < b.deficitNeg;
        if (a.inwardNeg != b.inwardNeg) return a.inwardNeg < b.inwardNeg;
        if (a.cnt != b.cnt) return a.cnt < b.cnt;
        if (a.cheb != b.cheb) return a.cheb < b.cheb;
        if (a.dist2 != b.dist2) return a.dist2 < b.dist2;
        return a.randTie < b.randTie;
    };
    for (auto& bin : bins) std::sort(bin.begin(), bin.end(), cmp);

    std::vector<int> ordered;
    bool keepGoing = true;
    while (keepGoing) {
        keepGoing = false;
        for (int s = 0; s < nBins; ++s) {
            int ib = (startBin + s) % nBins;
            auto& bin = bins[static_cast<std::size_t>(ib)];
            if (bin.empty()) continue;
            ordered.push_back(bin.front().nb);
            bin.erase(bin.begin());
            keepGoing = true;
        }
    }
    return ordered;
}

void update_transfer_correction_masks(std::vector<char>& bulkBulkMask,
                                      std::vector<char>& skipMask,
                                      int srcCell,
                                      const std::vector<int>& recvCells,
                                      const std::vector<int>& bulkMaskBefore,
                                      bool forceSkip) {
    std::vector<int> touched;
    touched.push_back(srcCell);
    touched.insert(touched.end(), recvCells.begin(), recvCells.end());
    touched = unique_stable(touched);
    if (touched.empty()) return;
    if (forceSkip) {
        for (int c : touched) {
            skipMask[static_cast<std::size_t>(c)] = 1;
            bulkBulkMask[static_cast<std::size_t>(c)] = 0;
        }
        return;
    }
    bool allBulk = true;
    for (int c : touched) {
        if (c < 0 || c >= static_cast<int>(bulkMaskBefore.size()) || !bulkMaskBefore[static_cast<std::size_t>(c)]) {
            allBulk = false;
            break;
        }
    }
    if (allBulk) {
        for (int c : touched) bulkBulkMask[static_cast<std::size_t>(c)] = 1;
    } else {
        for (int c : touched) {
            skipMask[static_cast<std::size_t>(c)] = 1;
            bulkBulkMask[static_cast<std::size_t>(c)] = 0;
        }
    }
}

std::vector<int> spread_particles_from_dense_source_round_robin(std::vector<double>& x,
                                                                std::vector<std::vector<int>>& partsInCell,
                                                                std::vector<int>& cntVec,
                                                                int srcCell,
                                                                const std::vector<int>& orderedTargets,
                                                                const std::vector<double>& targetMap,
                                                                int needOut,
                                                                const Params& params,
                                                                std::mt19937_64& rng,
                                                                int& movedCount) {
    movedCount = 0;
    std::vector<int> recvTargets;
    if (needOut <= 0 || orderedTargets.empty()) return recvTargets;

    auto idsAvail = partsInCell[static_cast<std::size_t>(srcCell)];
    if (idsAvail.empty()) return recvTargets;

    while (needOut > 0 && !idsAvail.empty()) {
        bool progressed = false;
        for (std::size_t kk = 0; kk < orderedTargets.size(); ++kk) {
            const int nb = orderedTargets[kk];
            const double targetLevel = targetMap[static_cast<std::size_t>(nb)];
            const int deficit = std::max(0, static_cast<int>(std::floor(targetLevel - static_cast<double>(cntVec[static_cast<std::size_t>(nb)]))));
            if (deficit <= 0) continue;

            int remainingTargets = 0;
            for (std::size_t jj = kk; jj < orderedTargets.size(); ++jj) {
                const int nbj = orderedTargets[jj];
                const int defj = std::max(0, static_cast<int>(std::floor(targetMap[static_cast<std::size_t>(nbj)] - static_cast<double>(cntVec[static_cast<std::size_t>(nbj)]))));
                if (defj > 0) ++remainingTargets;
            }
            const int quota = std::max(1, static_cast<int>(std::ceil(static_cast<double>(needOut) / std::max(1, remainingTargets))));
            const int nt = std::max(1, std::min({quota, deficit, needOut, static_cast<int>(idsAvail.size())}));
            if (nt <= 0) continue;

            std::vector<int> idsMove(idsAvail.begin(), idsAvail.begin() + nt);
            idsAvail.erase(idsAvail.begin(), idsAvail.begin() + nt);
            auto xy = sample_in_cell(nb, nt, params, rng);
            for (int q = 0; q < nt; ++q) {
                const int pid = idsMove[static_cast<std::size_t>(q)];
                x[2 * pid] = xy[2 * q];
                x[2 * pid + 1] = xy[2 * q + 1];
                partsInCell[static_cast<std::size_t>(nb)].push_back(pid);
            }
            cntVec[static_cast<std::size_t>(nb)] += nt;
            recvTargets.push_back(nb);
            movedCount += nt;
            needOut -= nt;
            progressed = true;
            if (needOut <= 0 || idsAvail.empty()) break;
        }
        if (!progressed) break;
    }

    if (movedCount > 0) {
        partsInCell[static_cast<std::size_t>(srcCell)] = idsAvail;
        cntVec[static_cast<std::size_t>(srcCell)] = static_cast<int>(idsAvail.size());
        recvTargets = unique_stable(recvTargets);
    } else {
        recvTargets.clear();
    }
    return recvTargets;
}

std::vector<int> redistribute_dense_cell_at_range_zone_local(std::vector<double>& x,
                                                             std::vector<std::vector<int>>& partsInCell,
                                                             std::vector<int>& cntVec,
                                                             int cell,
                                                             const std::vector<double>& lowThrActiveMap,
                                                             const std::vector<double>& highThrActiveMap,
                                                             double highThrLocal,
                                                             const std::pair<double,double>& nHat,
                                                             double inwardWeight,
                                                             const Params& params,
                                                             int rangeR,
                                                             const std::vector<char>& zoneMaskVec,
                                                             std::mt19937_64& rng,
                                                             int& movedCount) {
    movedCount = 0;
    std::vector<int> recvTargets;
    int needOut = std::max(0, static_cast<int>(std::ceil(static_cast<double>(cntVec[static_cast<std::size_t>(cell)]) - highThrLocal)));
    if (needOut <= 0) return recvTargets;

    auto poorTargets = admissible_dense_targets_rangeR(cell, cntVec, lowThrActiveMap, params, rangeR);
    poorTargets.erase(std::remove_if(poorTargets.begin(), poorTargets.end(), [&](int c){ return !zoneMaskVec[static_cast<std::size_t>(c)]; }), poorTargets.end());
    auto orderedPoor = rank_dense_targets_unified(cell, poorTargets, cntVec, lowThrActiveMap, nHat, inwardWeight, params, rng);
    int movedNow = 0;
    auto recvNow = spread_particles_from_dense_source_round_robin(x, partsInCell, cntVec, cell, orderedPoor, lowThrActiveMap, needOut, params, rng, movedNow);
    if (!recvNow.empty()) {
        recvTargets.insert(recvTargets.end(), recvNow.begin(), recvNow.end());
        recvTargets = unique_stable(recvTargets);
    }
    movedCount += movedNow;

    int remainingOut = std::max(0, static_cast<int>(std::ceil(static_cast<double>(cntVec[static_cast<std::size_t>(cell)]) - highThrLocal)));
    if (remainingOut <= 0) return recvTargets;

    auto reliefTargets = admissible_dense_targets_rangeR(cell, cntVec, highThrActiveMap, params, rangeR);
    reliefTargets.erase(std::remove_if(reliefTargets.begin(), reliefTargets.end(), [&](int c){ return !zoneMaskVec[static_cast<std::size_t>(c)]; }), reliefTargets.end());
    auto orderedRelief = rank_dense_targets_unified(cell, reliefTargets, cntVec, highThrActiveMap, nHat, inwardWeight, params, rng);
    recvNow = spread_particles_from_dense_source_round_robin(x, partsInCell, cntVec, cell, orderedRelief, highThrActiveMap, remainingOut, params, rng, movedNow);
    if (!recvNow.empty()) {
        recvTargets.insert(recvTargets.end(), recvNow.begin(), recvNow.end());
        recvTargets = unique_stable(recvTargets);
    }
    movedCount += movedNow;
    return recvTargets;
}

std::vector<int> rank_admissible_neighbors_inward(int cell,
                                                  std::vector<int> admiss,
                                                  const std::pair<double,double>& dir,
                                                  const std::vector<double>& Nsm,
                                                  const Params& params,
                                                  std::mt19937_64& rng) {
    if (admiss.empty()) return {};
    std::shuffle(admiss.begin(), admiss.end(), rng);
    const double ndir = std::hypot(dir.first, dir.second);
    struct Sc { int c; double align; double dense; double noise; };
    std::vector<Sc> scores;
    scores.reserve(admiss.size());
    std::normal_distribution<double> N01(0.0, 1.0);
    for (int cn : admiss) {
        auto [dx, dy] = minimal_step(cell, cn, params);
        const double nstep = std::hypot(static_cast<double>(dx), static_cast<double>(dy));
        double align = 0.0;
        if (ndir >= 1e-14 && nstep >= 1e-14) {
            align = (static_cast<double>(dx) * dir.first + static_cast<double>(dy) * dir.second) / (ndir * nstep);
        }
        scores.push_back(Sc{cn, align, Nsm[static_cast<std::size_t>(cn)], 1e-9 * N01(rng)});
    }
    std::sort(scores.begin(), scores.end(), [](const Sc& a, const Sc& b) {
        const double sa = 100.0 * a.align + a.dense + a.noise;
        const double sb = 100.0 * b.align + b.dense + b.noise;
        return sa > sb;
    });
    std::vector<int> ordered;
    ordered.reserve(scores.size());
    for (const auto& s : scores) ordered.push_back(s.c);
    return ordered;
}

ZoneKernelResult run_zone_kernel(std::vector<double>& x,
                                 std::vector<double>& v,
                                 const Params& params,
                                 const Zone& zone,
                                 std::uint64_t rngSeed,
                                 const std::vector<double>& fluidFractionMask) {
    ZoneKernelResult out{};
    const auto fluidPhi = canonical_fluid_fraction_mask(params, fluidFractionMask);
    const double gammaFluid = gamma_from_fluid_fraction_mask(params, fluidPhi);

    auto activeMaskVec = build_active_mask_vec(params);
    for (int c = 0; c < params.Nc; ++c) {
        if (fluidPhi[static_cast<std::size_t>(c)] < kRedistributionPhiMin) {
            activeMaskVec[static_cast<std::size_t>(c)] = 0;
        }
    }

    const auto zoneMaskVec = zone.maskVec;
    std::vector<char> zoneActiveMaskVec(static_cast<std::size_t>(params.Nc), 0);
    for (int c = 0; c < params.Nc; ++c) zoneActiveMaskVec[static_cast<std::size_t>(c)] = activeMaskVec[static_cast<std::size_t>(c)] && zoneMaskVec[static_cast<std::size_t>(c)];

    auto cellId = build_cell_ids_interleaved(x, params);
    auto partsInCell = build_parts_in_cell(cellId, params);
    auto cntVec = build_counts_from_parts(partsInCell, params);

    std::vector<double> PbeforeX, PbeforeY;
    cell_total_momentum(partsInCell, v, params, PbeforeX, PbeforeY);

    CorrMasks masks{};
    masks.recvMask.assign(static_cast<std::size_t>(params.Nc), 0);
    masks.momCorrBulkBulkMask.assign(static_cast<std::size_t>(params.Nc), 0);
    masks.momCorrSkipMask.assign(static_cast<std::size_t>(params.Nc), 0);

    const auto PglobBefore = total_momentum(v, params.n);
    const double Ebefore = [&]() {
        double e = 0.0;
        for (int i = 0; i < params.n; ++i) e += 0.5 * (v[2 * i] * v[2 * i] + v[2 * i + 1] * v[2 * i + 1]);
        return e;
    }();

    auto [highThr, lowThrBulk, lowThrInterface] = occupancy_thresholds(params);
    (void)lowThrInterface;
    std::mt19937_64 rng(rngSeed);

    int pass = 0;
    std::vector<double> lowThrActiveMap(static_cast<std::size_t>(params.Nc), 0.0);
    std::vector<double> highThrActiveMap(static_cast<std::size_t>(params.Nc), 0.0);
    std::vector<double> Nsm(static_cast<std::size_t>(params.Nc), 0.0);

    while (pass < params.maxRedistribPasses) {
        ++pass;
        int nHigh = 0, nLow = 0, movedOut = 0, movedIn = 0;

        Nsm = smooth_occupancy_field(cntVec, params);
        auto maps = build_local_fluid_fraction_threshold_maps(Nsm, params);
        std::vector<int> bulkMask = build_topological_bulk_mask(cntVec, params);
        for (int c = 0; c < params.Nc; ++c) {
            bulkMask[static_cast<std::size_t>(c)] = (cntVec[static_cast<std::size_t>(c)] > 0 && activeMaskVec[static_cast<std::size_t>(c)]) ? 1 : 0;
            lowThrActiveMap[static_cast<std::size_t>(c)] = maps.lowThrLocMap[static_cast<std::size_t>(c)];
            highThrActiveMap[static_cast<std::size_t>(c)] = maps.highThrLocMap[static_cast<std::size_t>(c)];
            if (!false) {
                if (bulkMask[static_cast<std::size_t>(c)]) {
                    lowThrActiveMap[static_cast<std::size_t>(c)] = lowThrBulk;
                    highThrActiveMap[static_cast<std::size_t>(c)] = highThr;
                }
            }
        }
        apply_solid_fluid_thresholds(fluidPhi, gammaFluid, params, activeMaskVec, bulkMask, lowThrActiveMap, highThrActiveMap);
        const auto bulkMaskDenseBefore = bulkMask;

        std::vector<int> denseList;
        for (int c = 0; c < params.Nc; ++c) {
            if (zoneActiveMaskVec[static_cast<std::size_t>(c)] && static_cast<double>(cntVec[static_cast<std::size_t>(c)]) > highThrActiveMap[static_cast<std::size_t>(c)]) denseList.push_back(c);
        }
        if (!denseList.empty()) std::shuffle(denseList.begin(), denseList.end(), rng);

        for (int c : denseList) {
            const int nc = cntVec[static_cast<std::size_t>(c)];
            if (nc <= 0) continue;
            const double highThrLocal = highThrActiveMap[static_cast<std::size_t>(c)];
            if (static_cast<double>(nc) <= highThrLocal) continue;
            ++nHigh;
            const std::pair<double,double> nHat{0.0, 0.0};
            const double inwardWeight = 0.0;
            int movedNow = 0;
            auto recvTargets = redistribute_dense_cell_at_range_zone_local(x, partsInCell, cntVec, c,
                                                                           lowThrActiveMap, highThrActiveMap,
                                                                           highThrLocal, nHat, inwardWeight,
                                                                           params, 2, zoneMaskVec, rng, movedNow);
            for (int r : recvTargets) masks.recvMask[static_cast<std::size_t>(r)] = 1;
            update_transfer_correction_masks(masks.momCorrBulkBulkMask, masks.momCorrSkipMask,
                                             c, recvTargets, bulkMaskDenseBefore, false);
            movedOut += movedNow;
            movedIn += movedNow;
            out.movedDense += movedNow;
        }

        Nsm = smooth_occupancy_field(cntVec, params);
        maps = build_local_fluid_fraction_threshold_maps(Nsm, params);
        bulkMask = build_topological_bulk_mask(cntVec, params);
        for (int c = 0; c < params.Nc; ++c) {
            bulkMask[static_cast<std::size_t>(c)] = (cntVec[static_cast<std::size_t>(c)] > 0 && activeMaskVec[static_cast<std::size_t>(c)]) ? 1 : 0;
            lowThrActiveMap[static_cast<std::size_t>(c)] = maps.lowThrLocMap[static_cast<std::size_t>(c)];
            highThrActiveMap[static_cast<std::size_t>(c)] = maps.highThrLocMap[static_cast<std::size_t>(c)];
            if (bulkMask[static_cast<std::size_t>(c)]) {
                lowThrActiveMap[static_cast<std::size_t>(c)] = lowThrBulk;
                highThrActiveMap[static_cast<std::size_t>(c)] = highThr;
            }
        }
        apply_solid_fluid_thresholds(fluidPhi, gammaFluid, params, activeMaskVec, bulkMask, lowThrActiveMap, highThrActiveMap);
        out.stats[0] += static_cast<double>(nHigh);
        out.stats[1] += static_cast<double>(nLow);
        out.stats[2] += static_cast<double>(movedOut);
        out.stats[3] += static_cast<double>(movedIn);

        Nsm = smooth_occupancy_field(cntVec, params);
        maps = build_local_fluid_fraction_threshold_maps(Nsm, params);
        for (int c = 0; c < params.Nc; ++c) {
            highThrActiveMap[static_cast<std::size_t>(c)] = maps.highThrLocMap[static_cast<std::size_t>(c)];
            if ((cntVec[static_cast<std::size_t>(c)] > 0) && activeMaskVec[static_cast<std::size_t>(c)]) {
                highThrActiveMap[static_cast<std::size_t>(c)] = highThr;
            }
        }
        apply_solid_fluid_thresholds(fluidPhi, gammaFluid, params, activeMaskVec, bulkMask, lowThrActiveMap, highThrActiveMap);
        // MATLAB keeps looping until max pass count without early break.
    }

    Nsm = smooth_occupancy_field(cntVec, params);
    auto maps = build_local_fluid_fraction_threshold_maps(Nsm, params);
    std::vector<int> bulkMask = build_topological_bulk_mask(cntVec, params);
    for (int c = 0; c < params.Nc; ++c) {
        bulkMask[static_cast<std::size_t>(c)] = (cntVec[static_cast<std::size_t>(c)] > 0 && activeMaskVec[static_cast<std::size_t>(c)]) ? 1 : 0;
        lowThrActiveMap[static_cast<std::size_t>(c)] = maps.lowThrLocMap[static_cast<std::size_t>(c)];
        highThrActiveMap[static_cast<std::size_t>(c)] = maps.highThrLocMap[static_cast<std::size_t>(c)];
        if (bulkMask[static_cast<std::size_t>(c)]) {
            lowThrActiveMap[static_cast<std::size_t>(c)] = lowThrBulk;
            highThrActiveMap[static_cast<std::size_t>(c)] = highThr;
        }
    }
    apply_solid_fluid_thresholds(fluidPhi, gammaFluid, params, activeMaskVec, bulkMask, lowThrActiveMap, highThrActiveMap);
    const auto bulkMaskLowBefore = bulkMask;

    std::vector<int> lowList;
    for (int c = 0; c < params.Nc; ++c) {
        if (zoneActiveMaskVec[static_cast<std::size_t>(c)] && cntVec[static_cast<std::size_t>(c)] > 0 && static_cast<double>(cntVec[static_cast<std::size_t>(c)]) < lowThrActiveMap[static_cast<std::size_t>(c)]) lowList.push_back(c);
    }
    if (!lowList.empty()) std::shuffle(lowList.begin(), lowList.end(), rng);

    int nHigh = 0, nLow = 0, movedOut = 0, movedIn = 0;
    for (int c : lowList) {
        const int nc = cntVec[static_cast<std::size_t>(c)];
        if (nc <= 0) continue;
        ++nLow;
        if (partsInCell[static_cast<std::size_t>(c)].empty()) continue;

        auto neigh = local_neighbors_in_zone(c, zone, params, 1);
        if (neigh.empty()) continue;

        const double lowThrLocal = lowThrActiveMap[static_cast<std::size_t>(c)];
        const int lowThrLocalInt = static_cast<int>(std::floor(std::max(0.0, lowThrLocal) + 1e-12));
        int need = std::max(0, lowThrLocalInt - nc);
        if (need <= 0) continue;

        std::vector<int> donors;
        for (int dtest : neigh) {
            const double reserveLowThr = lowThrActiveMap[static_cast<std::size_t>(dtest)];
            const int reserve = static_cast<int>(std::floor(std::max(0.0, reserveLowThr) + 1e-12));
            if (zoneActiveMaskVec[static_cast<std::size_t>(dtest)] && cntVec[static_cast<std::size_t>(dtest)] > reserve) donors.push_back(dtest);
        }
        if (donors.empty()) continue;

        const auto dir = inward_direction_from_local_gradient(c, Nsm, params);
        auto orderedDonors = rank_admissible_neighbors_inward(c, donors, dir, Nsm, params, rng);
        for (int d : orderedDonors) {
            auto idsDonor = partsInCell[static_cast<std::size_t>(d)];
            if (idsDonor.empty()) continue;
            const double donorReserveLowThr = lowThrActiveMap[static_cast<std::size_t>(d)];
            const int donorReserve = static_cast<int>(std::floor(std::max(0.0, donorReserveLowThr) + 1e-12));
            const int avail = cntVec[static_cast<std::size_t>(d)] - donorReserve;
            if (avail <= 0) continue;
            const int nt = std::min({need, avail, static_cast<int>(idsDonor.size())});
            if (nt <= 0) continue;
            std::shuffle(idsDonor.begin(), idsDonor.end(), rng);
            std::vector<int> idsMove(idsDonor.begin(), idsDonor.begin() + nt);
            std::vector<int> idsKeep(idsDonor.begin() + nt, idsDonor.end());
            auto xy = sample_in_cell(c, nt, params, rng);
            for (int q = 0; q < nt; ++q) {
                const int pid = idsMove[static_cast<std::size_t>(q)];
                x[2 * pid] = xy[2 * q];
                x[2 * pid + 1] = xy[2 * q + 1];
                partsInCell[static_cast<std::size_t>(c)].push_back(pid);
            }
            partsInCell[static_cast<std::size_t>(d)] = std::move(idsKeep);
            cntVec[static_cast<std::size_t>(d)] = static_cast<int>(partsInCell[static_cast<std::size_t>(d)].size());
            cntVec[static_cast<std::size_t>(c)] += nt;
            masks.recvMask[static_cast<std::size_t>(c)] = 1;
            update_transfer_correction_masks(masks.momCorrBulkBulkMask, masks.momCorrSkipMask,
                                             d, std::vector<int>{c}, bulkMaskLowBefore, false);
            movedOut += nt;
            movedIn += nt;
            out.movedSparse += nt;
            need -= nt;
            if (need <= 0) break;
        }
    }

    out.stats[0] += static_cast<double>(nHigh);
    out.stats[1] += static_cast<double>(nLow);
    out.stats[2] += static_cast<double>(movedOut);
    out.stats[3] += static_cast<double>(movedIn);

    Nsm = smooth_occupancy_field(cntVec, params);
    maps = build_local_fluid_fraction_threshold_maps(Nsm, params);
    bulkMask = build_topological_bulk_mask(cntVec, params);
    for (int c = 0; c < params.Nc; ++c) {
        bulkMask[static_cast<std::size_t>(c)] = (cntVec[static_cast<std::size_t>(c)] > 0 && activeMaskVec[static_cast<std::size_t>(c)]) ? 1 : 0;
        highThrActiveMap[static_cast<std::size_t>(c)] = maps.highThrLocMap[static_cast<std::size_t>(c)];
        if (bulkMask[static_cast<std::size_t>(c)]) highThrActiveMap[static_cast<std::size_t>(c)] = highThr;
    }
    apply_solid_fluid_thresholds(fluidPhi, gammaFluid, params, activeMaskVec, bulkMask, lowThrActiveMap, highThrActiveMap);

    std::vector<double> dU2(static_cast<std::size_t>(params.Nc), 0.0);
    double dUmax = 0.0;
    std::vector<double> pxErr2(static_cast<std::size_t>(params.Nc), 0.0);
    std::vector<double> pyErr2(static_cast<std::size_t>(params.Nc), 0.0);
    std::vector<double> uxNow(static_cast<std::size_t>(params.Nc), 0.0);
    std::vector<double> uyNow(static_cast<std::size_t>(params.Nc), 0.0);
    std::vector<char> zoneTouchedVec(static_cast<std::size_t>(params.Nc), 0);
    for (int c = 0; c < params.Nc; ++c) zoneTouchedVec[static_cast<std::size_t>(c)] = zoneMaskVec[static_cast<std::size_t>(c)] || masks.recvMask[static_cast<std::size_t>(c)];

    for (int c = 0; c < params.Nc; ++c) {
        if (!zoneTouchedVec[static_cast<std::size_t>(c)]) continue;
        const auto& ids = partsInCell[static_cast<std::size_t>(c)];
        const int nc = static_cast<int>(ids.size());
        if (nc == 0) continue;
        double pxAfter = 0.0, pyAfter = 0.0;
        for (int id : ids) {
            pxAfter += v[2 * id];
            pyAfter += v[2 * id + 1];
        }
        uxNow[static_cast<std::size_t>(c)] = pxAfter / static_cast<double>(nc);
        uyNow[static_cast<std::size_t>(c)] = pyAfter / static_cast<double>(nc);
        const double dPx = PbeforeX[static_cast<std::size_t>(c)] - pxAfter;
        const double dPy = PbeforeY[static_cast<std::size_t>(c)] - pyAfter;
        const double dux = dPx / static_cast<double>(nc);
        const double duy = dPy / static_cast<double>(nc);
        pxErr2[static_cast<std::size_t>(c)] = dPx * dPx;
        pyErr2[static_cast<std::size_t>(c)] = dPy * dPy;
        dU2[static_cast<std::size_t>(c)] = dux * dux + duy * duy;
        dUmax = std::max(dUmax, std::sqrt(dU2[static_cast<std::size_t>(c)]));

        bool doCellMomentumCorrection = params.enableMomentumCorrectionPostRedistribution;
        if (doCellMomentumCorrection && masks.momCorrSkipMask[static_cast<std::size_t>(c)]) doCellMomentumCorrection = false;
        if (doCellMomentumCorrection && masks.recvMask[static_cast<std::size_t>(c)] && !masks.momCorrBulkBulkMask[static_cast<std::size_t>(c)]) doCellMomentumCorrection = false;
        if (doCellMomentumCorrection && (dux != 0.0 || duy != 0.0)) {
            for (int id : ids) {
                v[2 * id] += dux;
                v[2 * id + 1] += duy;
            }
        }
    }

    double accDU = 0.0;
    int nDU = 0;
    for (double z : dU2) {
        if (z > 0.0) {
            accDU += z;
            ++nDU;
        }
    }
    if (nDU > 0) {
        out.stats[4] = std::sqrt(accDU / static_cast<double>(nDU));
        out.stats[5] = dUmax;
    }

    const auto PglobAfter = total_momentum(v, params.n);
    double Eafter = 0.0;
    for (int i = 0; i < params.n; ++i) Eafter += 0.5 * (v[2 * i] * v[2 * i] + v[2 * i + 1] * v[2 * i + 1]);

    const double gamma = params.gamma;
    std::vector<double> Nact;
    Nact.reserve(static_cast<std::size_t>(params.Nc));
    int nActive = 0, nOutBand = 0, nEmpty = 0;
    for (int c = 0; c < params.Nc; ++c) {
        if (!activeMaskVec[static_cast<std::size_t>(c)]) continue;
        ++nActive;
        Nact.push_back(static_cast<double>(cntVec[static_cast<std::size_t>(c)]));
        if (cntVec[static_cast<std::size_t>(c)] == 0) ++nEmpty;
        if (static_cast<double>(cntVec[static_cast<std::size_t>(c)]) > highThrActiveMap[static_cast<std::size_t>(c)] ||
            (static_cast<double>(cntVec[static_cast<std::size_t>(c)]) > 0.0 && static_cast<double>(cntVec[static_cast<std::size_t>(c)]) < lowThrActiveMap[static_cast<std::size_t>(c)])) {
            ++nOutBand;
        }
    }
    if (!Nact.empty()) {
        const double mean = std::accumulate(Nact.begin(), Nact.end(), 0.0) / static_cast<double>(Nact.size());
        double acc = 0.0;
        for (double a : Nact) { const double d = a - mean; acc += d * d; }
        out.diag[0] = std::sqrt(acc / static_cast<double>(Nact.size())) / std::max(gamma, 1e-30);
    }
    out.diag[1] = (nActive > 0) ? (static_cast<double>(nOutBand) / static_cast<double>(nActive)) : 0.0;
    const double dPglobX = PglobAfter.first - PglobBefore.first;
    const double dPglobY = PglobAfter.second - PglobBefore.second;
    out.diag[2] = std::sqrt(dPglobX * dPglobX + dPglobY * dPglobY);
    double accPx = 0.0, accPy = 0.0; int nPx = 0, nPy = 0;
    for (double z : pxErr2) if (z > 0.0) { accPx += z; ++nPx; }
    for (double z : pyErr2) if (z > 0.0) { accPy += z; ++nPy; }
    out.diag[3] = (nPx > 0) ? std::sqrt(accPx / static_cast<double>(nPx)) : 0.0;
    out.diag[4] = (nPy > 0) ? std::sqrt(accPy / static_cast<double>(nPy)) : 0.0;
    out.diag[5] = Eafter - Ebefore;
    out.diag[6] = std::numeric_limits<double>::quiet_NaN();
    double accUx = 0.0, accUy = 0.0; int nVel = 0;
    for (int c = 0; c < params.Nc; ++c) {
        if (cntVec[static_cast<std::size_t>(c)] > 0) {
            accUx += uxNow[static_cast<std::size_t>(c)] * uxNow[static_cast<std::size_t>(c)];
            accUy += uyNow[static_cast<std::size_t>(c)] * uyNow[static_cast<std::size_t>(c)];
            ++nVel;
        }
    }
    out.diag[7] = 0.0;
    out.diag[8] = (nVel > 0) ? std::sqrt(accUx / static_cast<double>(nVel)) : 0.0;
    out.diag[9] = (nVel > 0) ? std::sqrt(accUy / static_cast<double>(nVel)) : 0.0;
    out.diag[9] = (nVel > 0) ? std::sqrt(accUy / static_cast<double>(nVel)) : 0.0;
    // MATLAB diag(10) mapped to index 9 in zero-based arrays not used externally.
    return out;
}

double compute_occ_std_from_counts(const std::vector<int>& cnt, const Params& params) {
    const auto activeMaskVec = build_active_mask_vec(params);
    std::vector<double> Nact;
    Nact.reserve(static_cast<std::size_t>(params.Nc));
    for (int c = 0; c < params.Nc; ++c) if (activeMaskVec[static_cast<std::size_t>(c)]) Nact.push_back(static_cast<double>(cnt[static_cast<std::size_t>(c)]));
    if (Nact.empty()) return 0.0;
    const double mean = std::accumulate(Nact.begin(), Nact.end(), 0.0) / static_cast<double>(Nact.size());
    double acc = 0.0;
    for (double a : Nact) { const double d = a - mean; acc += d * d; }
    return std::sqrt(acc / static_cast<double>(Nact.size())) / std::max(params.gamma, 1e-30);
}

double compute_out_band_from_counts(const std::vector<int>& cnt, const Params& params) {
    const auto activeMaskVec = build_active_mask_vec(params);
    auto Nsm = smooth_occupancy_field(cnt, params);
    auto maps = build_local_fluid_fraction_threshold_maps(Nsm, params);
    auto [highThr, lowThrBulk, lowThrInterface] = occupancy_thresholds(params);
    (void)lowThrInterface;
    std::vector<int> bulkMask(static_cast<std::size_t>(params.Nc), 0);
    int nActive = 0, nOut = 0;
    for (int c = 0; c < params.Nc; ++c) {
        bulkMask[static_cast<std::size_t>(c)] = (cnt[static_cast<std::size_t>(c)] > 0 && activeMaskVec[static_cast<std::size_t>(c)]) ? 1 : 0;
        double lowThr = maps.lowThrLocMap[static_cast<std::size_t>(c)];
        double highThrCell = maps.highThrLocMap[static_cast<std::size_t>(c)];
        if (bulkMask[static_cast<std::size_t>(c)]) {
            lowThr = lowThrBulk;
            highThrCell = highThr;
        }
        if (activeMaskVec[static_cast<std::size_t>(c)]) {
            ++nActive;
            if (static_cast<double>(cnt[static_cast<std::size_t>(c)]) > highThrCell ||
                (cnt[static_cast<std::size_t>(c)] > 0 && static_cast<double>(cnt[static_cast<std::size_t>(c)]) < lowThr)) {
                ++nOut;
            }
        }
    }
    return (nActive > 0) ? (static_cast<double>(nOut) / static_cast<double>(nActive)) : 0.0;
}

int count_dense_from_counts(const std::vector<int>& cnt, const Params& params) {
    auto Nsm = smooth_occupancy_field(cnt, params);
    auto maps = build_local_fluid_fraction_threshold_maps(Nsm, params);
    auto [highThr, lowThrBulk, lowThrInterface] = occupancy_thresholds(params);
    (void)lowThrBulk; (void)lowThrInterface;
    int nDense = 0;
    for (int c = 0; c < params.Nc; ++c) {
        double thr = (cnt[static_cast<std::size_t>(c)] > 0) ? highThr : maps.highThrLocMap[static_cast<std::size_t>(c)];
        if (static_cast<double>(cnt[static_cast<std::size_t>(c)]) > thr) ++nDense;
    }
    return nDense;
}

int count_sparse_from_counts(const std::vector<int>& cnt, const Params& params) {
    auto Nsm = smooth_occupancy_field(cnt, params);
    auto maps = build_local_fluid_fraction_threshold_maps(Nsm, params);
    auto [highThr, lowThrBulk, lowThrInterface] = occupancy_thresholds(params);
    (void)highThr; (void)lowThrInterface;
    int nSparse = 0;
    for (int c = 0; c < params.Nc; ++c) {
        double lowThr = (cnt[static_cast<std::size_t>(c)] > 0) ? lowThrBulk : maps.lowThrLocMap[static_cast<std::size_t>(c)];
        if (cnt[static_cast<std::size_t>(c)] > 0 && static_cast<double>(cnt[static_cast<std::size_t>(c)]) < lowThr) ++nSparse;
    }
    return nSparse;
}

int count_empty_active(const std::vector<int>& cnt, const Params& params) {
    int nEmpty = 0;
    for (int c = 0; c < params.Nc; ++c) if (cnt[static_cast<std::size_t>(c)] == 0) ++nEmpty;
    return nEmpty;
}

} // namespace


ZoneLayout build_zone_layout(const Params& params, const std::string& mode) {
    const Layout L = build_layout(params, mode);
    ZoneLayout out{};
    out.mode = L.mode;
    out.ownerMap = L.ownerMap;
    out.zones.reserve(L.zones.size());
    for (const auto& z : L.zones) {
        ZoneDescriptor d{};
        d.id = z.id;
        d.cellIds = z.cellIds;
        d.maskVec = z.maskVec;
        out.zones.push_back(std::move(d));
    }
    return out;
}

ZoneKernelStats run_zone_kernel_inplace(std::vector<double>& x,
                                        std::vector<double>& v,
                                        const Params& params,
                                        const ZoneDescriptor& zone,
                                        std::uint64_t rngSeed,
                                        const std::vector<double>& fluidFractionMask) {
    Zone z{};
    z.id = zone.id;
    z.cellIds = zone.cellIds;
    z.maskVec.assign(zone.maskVec.begin(), zone.maskVec.end());
    const auto r = run_zone_kernel(x, v, params, z, rngSeed, fluidFractionMask);
    ZoneKernelStats out{};
    out.stats = r.stats;
    out.diag = r.diag;
    out.movedDense = r.movedDense;
    out.movedSparse = r.movedSparse;
    return out;
}

std::vector<int> build_particle_ids_in_zone(const std::vector<double>& x,
                                            const Params& params,
                                            const ZoneDescriptor& zone) {
    const auto cellId = build_cell_ids_interleaved(x, params);
    std::vector<int> ids;
    ids.reserve(static_cast<std::size_t>(params.n));
    for (int pid = 0; pid < params.n; ++pid) {
        const int c = cellId[static_cast<std::size_t>(pid)];
        if (zone.maskVec[static_cast<std::size_t>(c)]) ids.push_back(pid);
    }
    return ids;
}

ZonePassResult run_zone_pass(const State& stateIn,
                             const Params& params,
                             const std::string& layoutMode,
                             std::uint64_t rngSeedBase,
                             const std::vector<double>& fluidFractionMask) {
    if (!params.useIncompressibleRedistribution || !params.useZoneRedistribution) {
        throw std::runtime_error("run_zone_pass requires useIncompressibleRedistribution=true and useZoneRedistribution=true");
    }
    if (params.redistributionEnableSurfaceTopology || params.redistributionWallWettingEnabled || params.useInterfaceVelocityReorientation) {
        throw std::runtime_error("run_zone_pass is restricted to no surface / no wetting / no reorientation");
    }

    ZonePassResult out{};
    out.stateOut = stateIn;
    const Layout layout = build_layout(params, layoutMode);

    const double dx = params.Lx / static_cast<double>(params.Nx);
    const double dy = params.Ly / static_cast<double>(params.Ny);
    const double Vc = dx * dy;
    const double rhoTargetScalar = params.gamma / Vc;

    const auto cellBefore = build_cell_ids_interleaved(out.stateOut.x, params);
    const auto partsBefore = build_parts_in_cell(cellBefore, params);
    const auto cntBefore = build_counts_from_parts(partsBefore, params);
    out.beforeFields = compute_cell_fields(out.stateOut.x, out.stateOut.v, params, rhoTargetScalar);

    out.metrics.layoutMode = layout.mode;
    out.metrics.nZonesExecuted = static_cast<int>(layout.zones.size());
    out.metrics.occStdBefore = compute_occ_std_from_counts(cntBefore, params);
    out.metrics.outBandBefore = compute_out_band_from_counts(cntBefore, params);
    out.metrics.nDenseBefore = count_dense_from_counts(cntBefore, params);
    out.metrics.nSparseBefore = count_sparse_from_counts(cntBefore, params);
    out.metrics.nEmptyActiveBefore = count_empty_active(cntBefore, params);

    double corrAcc2 = 0.0;
    int corrCount = 0;
    double corrMax = 0.0;

    for (std::size_t iz = 0; iz < layout.zones.size(); ++iz) {
        auto zk = run_zone_kernel(out.stateOut.x, out.stateOut.v, params, layout.zones[iz], rngSeedBase + 104729ULL * static_cast<std::uint64_t>(iz + 1), fluidFractionMask);
        out.metrics.nParticlesMovedDense += zk.movedDense;
        out.metrics.nParticlesMovedSparse += zk.movedSparse;
        if (zk.stats[4] > 0.0) {
            corrAcc2 += zk.stats[4] * zk.stats[4];
            ++corrCount;
        }
        corrMax = std::max(corrMax, zk.stats[5]);
    }
    out.metrics.corrRmsDU = (corrCount > 0) ? std::sqrt(corrAcc2 / static_cast<double>(corrCount)) : 0.0;
    out.metrics.corrMaxDU = corrMax;

    const auto cellAfter = build_cell_ids_interleaved(out.stateOut.x, params);
    const auto partsAfter = build_parts_in_cell(cellAfter, params);
    const auto cntAfter = build_counts_from_parts(partsAfter, params);
    out.afterFields = compute_cell_fields(out.stateOut.x, out.stateOut.v, params, rhoTargetScalar);

    out.metrics.occStdAfter = compute_occ_std_from_counts(cntAfter, params);
    out.metrics.outBandAfter = compute_out_band_from_counts(cntAfter, params);
    out.metrics.nDenseAfter = count_dense_from_counts(cntAfter, params);
    out.metrics.nSparseAfter = count_sparse_from_counts(cntAfter, params);
    out.metrics.nEmptyActiveAfter = count_empty_active(cntAfter, params);

    const auto pBefore = total_momentum(stateIn.v, params.n);
    const auto pAfter = total_momentum(out.stateOut.v, params.n);
    out.metrics.momentumDeltaX = pAfter.first - pBefore.first;
    out.metrics.momentumDeltaY = pAfter.second - pBefore.second;
    out.zoneOwnerMap = layout.ownerMap;
    return out;
}

void write_i32_grid_bin(const std::string& filepath, int Nx, int Ny, const std::vector<std::int32_t>& data) {
    if (data.size() != static_cast<std::size_t>(Nx * Ny)) {
        throw std::runtime_error("write_i32_grid_bin: unexpected data size");
    }
    std::ofstream fout(filepath, std::ios::binary);
    if (!fout) {
        throw std::runtime_error("Cannot open i32 grid file for writing: " + filepath);
    }
    const std::int32_t Nx32 = static_cast<std::int32_t>(Nx);
    const std::int32_t Ny32 = static_cast<std::int32_t>(Ny);
    fout.write(reinterpret_cast<const char*>(&Nx32), sizeof(std::int32_t));
    fout.write(reinterpret_cast<const char*>(&Ny32), sizeof(std::int32_t));
    fout.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size() * sizeof(std::int32_t)));
    if (!fout) {
        throw std::runtime_error("Failed while writing i32 grid payload");
    }
}

} // namespace mpcd

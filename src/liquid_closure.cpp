#include "liquid_closure.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <limits>
#include <numeric>
#include <stdexcept>
#include <unordered_set>

#include "common_grid.h"

namespace mpcd {
namespace {

struct Zone {
    int id = 0;
    std::vector<int> cellIds;
};

struct Layout {
    std::vector<std::int32_t> ownerMap;
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
    L.ownerMap.assign(static_cast<std::size_t>(params.Nc), 0);

    if (mode == "single_full" || params.zoneSingleFullDomainMode) {
        for (int c = 0; c < params.Nc; ++c) {
            L.ownerMap[static_cast<std::size_t>(c)] = 1;
        }
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
            ++id;
            for (int ix = xs; ix < xe; ++ix) {
                for (int iy = ys; iy < ye; ++iy) {
                    const int c = cell_id_from_iy_ix(iy, ix, params);
                    L.ownerMap[static_cast<std::size_t>(c)] = id;
                }
            }
        }
    }
    return L;
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

double rho_target_scalar(const Params& params) {
    const double Vc = (params.Lx / static_cast<double>(params.Nx)) * (params.Ly / static_cast<double>(params.Ny));
    return params.gamma / Vc;
}

double mean_of_vec(const std::vector<double>& v) {
    if (v.empty()) return 0.0;
    double s = std::accumulate(v.begin(), v.end(), 0.0);
    return s / static_cast<double>(v.size());
}

std::pair<double,double> total_momentum(const std::vector<double>& v, int n) {
    double px = 0.0, py = 0.0;
    for (int i = 0; i < n; ++i) {
        px += v[2 * i];
        py += v[2 * i + 1];
    }
    return {px, py};
}

std::vector<std::int32_t> boundary_mask_from_owner(const std::vector<std::int32_t>& ownerMap, const Params& params) {
    std::vector<std::int32_t> mask(static_cast<std::size_t>(params.Nc), 0);
    for (int ix = 0; ix < params.Nx; ++ix) {
        for (int iy = 0; iy < params.Ny; ++iy) {
            const int c = cell_id_from_iy_ix(iy, ix, params);
            const auto owner = ownerMap[static_cast<std::size_t>(c)];
            bool isBoundary = false;
            const int right = (ix + 1 < params.Nx) ? cell_id_from_iy_ix(iy, ix + 1, params)
                                                   : (periodic_x(params) ? cell_id_from_iy_ix(iy, 0, params) : -1);
            const int up = (iy + 1 < params.Ny) ? cell_id_from_iy_ix(iy + 1, ix, params)
                                                : (periodic_y(params) ? cell_id_from_iy_ix(0, ix, params) : -1);
            if (right >= 0 && ownerMap[static_cast<std::size_t>(right)] != owner) isBoundary = true;
            if (up >= 0 && ownerMap[static_cast<std::size_t>(up)] != owner) isBoundary = true;
            if (isBoundary) mask[static_cast<std::size_t>(c)] = 1;
        }
    }
    return mask;
}

std::vector<std::int32_t> dilate_mask(const std::vector<std::int32_t>& maskIn, const Params& params, int widthCells) {
    if (widthCells <= 0) return maskIn;
    std::vector<std::int32_t> out(static_cast<std::size_t>(params.Nc), 0);
    for (int ix = 0; ix < params.Nx; ++ix) {
        for (int iy = 0; iy < params.Ny; ++iy) {
            bool on = false;
            for (int dx = -widthCells; dx <= widthCells && !on; ++dx) {
                for (int dy = -widthCells; dy <= widthCells; ++dy) {
                    int jx = ix + dx;
                    int jy = iy + dy;
                    if (periodic_x(params)) {
                        jx = wrap_index(jx, params.Nx);
                    } else if (jx < 0 || jx >= params.Nx) {
                        continue;
                    }
                    if (periodic_y(params)) {
                        jy = wrap_index(jy, params.Ny);
                    } else if (jy < 0 || jy >= params.Ny) {
                        continue;
                    }
                    const int jc = cell_id_from_iy_ix(jy, jx, params);
                    if (maskIn[static_cast<std::size_t>(jc)] != 0) {
                        on = true;
                        break;
                    }
                }
            }
            if (on) {
                out[static_cast<std::size_t>(cell_id_from_iy_ix(iy, ix, params))] = 1;
            }
        }
    }
    return out;
}

std::vector<std::int32_t> build_interzone_mask(const Params& params) {
    std::vector<std::int32_t> mask(static_cast<std::size_t>(params.Nc), 0);
    if (!params.smoothPdriveAtInterzone || !params.useZoneRedistribution || params.zonePassthroughMode || params.zoneSingleFullDomainMode) {
        return mask;
    }
    const auto baseLayout = build_layout(params, "base");
    auto baseMask = dilate_mask(boundary_mask_from_owner(baseLayout.ownerMap, params), params, params.smoothPdriveInterzoneWidthCells);
    mask = baseMask;
    if (params.smoothPdriveIncludeShiftedLayouts) {
        const auto shLayout = build_layout(params, "shifted");
        const auto shMask = dilate_mask(boundary_mask_from_owner(shLayout.ownerMap, params), params, params.smoothPdriveInterzoneWidthCells);
        for (int c = 0; c < params.Nc; ++c) {
            mask[static_cast<std::size_t>(c)] = (mask[static_cast<std::size_t>(c)] || shMask[static_cast<std::size_t>(c)]) ? 1 : 0;
        }
    }
    return mask;
}

std::vector<double> local_cross_smooth(const std::vector<double>& in, const Params& params) {
    std::vector<double> out(static_cast<std::size_t>(params.Nc), 0.0);
    for (int ix = 0; ix < params.Nx; ++ix) {
        for (int iy = 0; iy < params.Ny; ++iy) {
            double acc = in[static_cast<std::size_t>(cell_id_from_iy_ix(iy, ix, params))];
            int cnt = 1;
            const int jxL = ix - 1;
            const int jxR = ix + 1;
            const int jyD = iy - 1;
            const int jyU = iy + 1;
            auto add_if_valid = [&](int jy, int jx) {
                if (periodic_x(params)) jx = wrap_index(jx, params.Nx);
                else if (jx < 0 || jx >= params.Nx) return;
                if (periodic_y(params)) jy = wrap_index(jy, params.Ny);
                else if (jy < 0 || jy >= params.Ny) return;
                acc += in[static_cast<std::size_t>(cell_id_from_iy_ix(jy, jx, params))];
                ++cnt;
            };
            add_if_valid(iy, jxL);
            add_if_valid(iy, jxR);
            add_if_valid(jyD, ix);
            add_if_valid(jyU, ix);
            out[static_cast<std::size_t>(cell_id_from_iy_ix(iy, ix, params))] = acc / static_cast<double>(cnt);
        }
    }
    return out;
}

void gradient_boundary_aware(const std::vector<double>& p, const Params& params,
                             std::vector<double>& dPdx, std::vector<double>& dPdy) {
    const double dx = params.Lx / static_cast<double>(params.Nx);
    const double dy = params.Ly / static_cast<double>(params.Ny);
    dPdx.assign(static_cast<std::size_t>(params.Nc), 0.0);
    dPdy.assign(static_cast<std::size_t>(params.Nc), 0.0);
    for (int ix = 0; ix < params.Nx; ++ix) {
        for (int iy = 0; iy < params.Ny; ++iy) {
            const int c = cell_id_from_iy_ix(iy, ix, params);
            int ixm = ix - 1, ixp = ix + 1;
            int iym = iy - 1, iyp = iy + 1;
            if (periodic_x(params)) {
                ixm = wrap_index(ixm, params.Nx);
                ixp = wrap_index(ixp, params.Nx);
                const double pm = p[static_cast<std::size_t>(cell_id_from_iy_ix(iy, ixm, params))];
                const double pp = p[static_cast<std::size_t>(cell_id_from_iy_ix(iy, ixp, params))];
                dPdx[static_cast<std::size_t>(c)] = (pp - pm) / (2.0 * dx);
            } else if (ix == 0) {
                const double p0 = p[static_cast<std::size_t>(c)];
                const double p1 = p[static_cast<std::size_t>(cell_id_from_iy_ix(iy, ix + 1, params))];
                dPdx[static_cast<std::size_t>(c)] = (p1 - p0) / dx;
            } else if (ix == params.Nx - 1) {
                const double p0 = p[static_cast<std::size_t>(cell_id_from_iy_ix(iy, ix - 1, params))];
                const double p1 = p[static_cast<std::size_t>(c)];
                dPdx[static_cast<std::size_t>(c)] = (p1 - p0) / dx;
            } else {
                const double pm = p[static_cast<std::size_t>(cell_id_from_iy_ix(iy, ix - 1, params))];
                const double pp = p[static_cast<std::size_t>(cell_id_from_iy_ix(iy, ix + 1, params))];
                dPdx[static_cast<std::size_t>(c)] = (pp - pm) / (2.0 * dx);
            }

            if (periodic_y(params)) {
                iym = wrap_index(iym, params.Ny);
                iyp = wrap_index(iyp, params.Ny);
                const double pm = p[static_cast<std::size_t>(cell_id_from_iy_ix(iym, ix, params))];
                const double pp = p[static_cast<std::size_t>(cell_id_from_iy_ix(iyp, ix, params))];
                dPdy[static_cast<std::size_t>(c)] = (pp - pm) / (2.0 * dy);
            } else if (iy == 0) {
                const double p0 = p[static_cast<std::size_t>(c)];
                const double p1 = p[static_cast<std::size_t>(cell_id_from_iy_ix(iy + 1, ix, params))];
                dPdy[static_cast<std::size_t>(c)] = (p1 - p0) / dy;
            } else if (iy == params.Ny - 1) {
                const double p0 = p[static_cast<std::size_t>(cell_id_from_iy_ix(iy - 1, ix, params))];
                const double p1 = p[static_cast<std::size_t>(c)];
                dPdy[static_cast<std::size_t>(c)] = (p1 - p0) / dy;
            } else {
                const double pm = p[static_cast<std::size_t>(cell_id_from_iy_ix(iy - 1, ix, params))];
                const double pp = p[static_cast<std::size_t>(cell_id_from_iy_ix(iy + 1, ix, params))];
                dPdy[static_cast<std::size_t>(c)] = (pp - pm) / (2.0 * dy);
            }
        }
    }
}

struct KickInfo {
    double rms = 0.0;
    double maxv = 0.0;
};

KickInfo apply_cell_kick(std::vector<double>& v,
                         const std::vector<int>& cellId,
                         const std::vector<double>& dux,
                         const std::vector<double>& duy,
                         int n) {
    double acc = 0.0;
    double maxv = 0.0;
    for (int i = 0; i < n; ++i) {
        const int c = cellId[static_cast<std::size_t>(i)];
        const double kx = dux[static_cast<std::size_t>(c)];
        const double ky = duy[static_cast<std::size_t>(c)];
        v[2 * i] += kx;
        v[2 * i + 1] += ky;
        const double kn = std::sqrt(kx * kx + ky * ky);
        acc += kn * kn;
        if (kn > maxv) maxv = kn;
    }
    KickInfo info{};
    if (n > 0) {
        info.rms = std::sqrt(acc / static_cast<double>(n));
        info.maxv = maxv;
    }
    return info;
}

} // namespace

LiquidClosureResult run_liquid_closure(const State& stateRef,
                                       const State& stateRed,
                                       const Params& params) {
    if (!params.useLiquidClosure) {
        throw std::runtime_error("run_liquid_closure requires useLiquidClosure=true");
    }
    if (stateRef.x.size() != stateRed.x.size() || stateRef.v.size() != stateRed.v.size()) {
        throw std::runtime_error("run_liquid_closure requires ref/red states with matching sizes");
    }

    LiquidClosureResult out{};
    out.refFields = compute_cell_fields(stateRef.x, stateRef.v, params, rho_target_scalar(params));
    out.redFields = compute_cell_fields(stateRed.x, stateRed.v, params, rho_target_scalar(params));

    out.duRepairX.assign(static_cast<std::size_t>(params.Nc), 0.0);
    out.duRepairY.assign(static_cast<std::size_t>(params.Nc), 0.0);
    double num = 0.0;
    double den = 0.0;
    constexpr double kBetaRepairDenMin = 1e-20;
    constexpr double kBetaRepairMax = 2.0;
    for (int c = 0; c < params.Nc; ++c) {
        out.duRepairX[static_cast<std::size_t>(c)] =
            (out.refFields.Px[static_cast<std::size_t>(c)] - out.redFields.Px[static_cast<std::size_t>(c)]) / params.gamma;
        out.duRepairY[static_cast<std::size_t>(c)] =
            (out.refFields.Py[static_cast<std::size_t>(c)] - out.redFields.Py[static_cast<std::size_t>(c)]) / params.gamma;
        const double ex = out.redFields.Ux[static_cast<std::size_t>(c)] - out.refFields.Ux[static_cast<std::size_t>(c)];
        const double ey = out.redFields.Uy[static_cast<std::size_t>(c)] - out.refFields.Uy[static_cast<std::size_t>(c)];
        const double ax = out.duRepairX[static_cast<std::size_t>(c)];
        const double ay = out.duRepairY[static_cast<std::size_t>(c)];
        num += -(ex * ax + ey * ay);
        den += ax * ax + ay * ay;
    }
    out.metrics.betaRepairNum = num;
    out.metrics.betaRepairDen = den;

    double betaRepairOpt = 0.0;
    if (std::isfinite(num) && std::isfinite(den) && den > 0.0) {
        betaRepairOpt = std::max(num / den, 0.0);
    }
    out.metrics.betaRepairOpt = betaRepairOpt;

    if (!params.useOptimalBetaRepair) {
        out.metrics.betaRepairApplied = params.betaRepair;
    } else if (!std::isfinite(betaRepairOpt) || !std::isfinite(den) || den < kBetaRepairDenMin) {
        out.metrics.betaRepairApplied = params.betaRepair;
    } else {
        out.metrics.betaRepairApplied = std::clamp(betaRepairOpt, 0.0, kBetaRepairMax);
    }
    out.metrics.betaEOSApplied = params.betaEOS;

    out.stateRepaired = stateRed;
    const auto cellIdRed = build_cell_ids_interleaved(stateRed.x, params);
    std::vector<double> duRepairXApplied(static_cast<std::size_t>(params.Nc), 0.0);
    std::vector<double> duRepairYApplied(static_cast<std::size_t>(params.Nc), 0.0);
    for (int c = 0; c < params.Nc; ++c) {
        duRepairXApplied[static_cast<std::size_t>(c)] = out.metrics.betaRepairApplied * out.duRepairX[static_cast<std::size_t>(c)];
        duRepairYApplied[static_cast<std::size_t>(c)] = out.metrics.betaRepairApplied * out.duRepairY[static_cast<std::size_t>(c)];
    }
    const auto repairKick = apply_cell_kick(out.stateRepaired.v, cellIdRed, duRepairXApplied, duRepairYApplied, params.n);
    out.metrics.rmsRepairDU = repairKick.rms;
    out.metrics.maxRepairDU = repairKick.maxv;
    {
        double accAbs = 0.0;
        for (int c = 0; c < params.Nc; ++c) {
            const double dux = duRepairXApplied[static_cast<std::size_t>(c)];
            const double duy = duRepairYApplied[static_cast<std::size_t>(c)];
            accAbs += std::hypot(dux, duy);
        }
        out.metrics.meanAbsRepairDU = accAbs / static_cast<double>(std::max(params.Nc, 1));
    }
    out.repairedFields = compute_cell_fields(out.stateRepaired.x, out.stateRepaired.v, params, rho_target_scalar(params));

    out.pdriveRaw.assign(static_cast<std::size_t>(params.Nc), 0.0);
    for (int c = 0; c < params.Nc; ++c) {
        out.pdriveRaw[static_cast<std::size_t>(c)] = out.refFields.Pkin[static_cast<std::size_t>(c)] + out.refFields.Pvir[static_cast<std::size_t>(c)];
    }
    out.metrics.meanPdriveRaw = mean_of_vec(out.pdriveRaw);

    out.pdrive = out.pdriveRaw;
    out.interzoneMask = build_interzone_mask(params);
    out.metrics.nMaskedInterzoneCells = static_cast<int>(std::count(out.interzoneMask.begin(), out.interzoneMask.end(), static_cast<std::int32_t>(1)));
    if (out.metrics.nMaskedInterzoneCells > 0) {
        const auto ps = local_cross_smooth(out.pdriveRaw, params);
        for (int c = 0; c < params.Nc; ++c) {
            if (out.interzoneMask[static_cast<std::size_t>(c)] != 0) {
                out.pdrive[static_cast<std::size_t>(c)] =
                    (1.0 - params.smoothPdriveInterzoneBlend) * out.pdriveRaw[static_cast<std::size_t>(c)] +
                    params.smoothPdriveInterzoneBlend * ps[static_cast<std::size_t>(c)];
            }
        }
    }
    out.metrics.meanPdrive = mean_of_vec(out.pdrive);

    std::vector<double> dPdx, dPdy;
    gradient_boundary_aware(out.pdrive, params, dPdx, dPdy);
    out.duEOSX.assign(static_cast<std::size_t>(params.Nc), 0.0);
    out.duEOSY.assign(static_cast<std::size_t>(params.Nc), 0.0);
    const double rhoT = rho_target_scalar(params);
    for (int c = 0; c < params.Nc; ++c) {
        out.duEOSX[static_cast<std::size_t>(c)] = -(params.dt / rhoT) * dPdx[static_cast<std::size_t>(c)] * params.betaEOS;
        out.duEOSY[static_cast<std::size_t>(c)] = -(params.dt / rhoT) * dPdy[static_cast<std::size_t>(c)] * params.betaEOS;
    }

    out.stateOut = out.stateRepaired;
    const auto cellIdRepair = build_cell_ids_interleaved(out.stateRepaired.x, params);
    const auto eosKick = apply_cell_kick(out.stateOut.v, cellIdRepair, out.duEOSX, out.duEOSY, params.n);
    out.metrics.rmsEOSDU = eosKick.rms;
    out.metrics.maxEOSDU = eosKick.maxv;
    out.outFields = compute_cell_fields(out.stateOut.x, out.stateOut.v, params, rho_target_scalar(params));

    const auto pIn = total_momentum(stateRed.v, params.n);
    const auto pOut = total_momentum(out.stateOut.v, params.n);
    out.metrics.momentumDeltaX = pOut.first - pIn.first;
    out.metrics.momentumDeltaY = pOut.second - pIn.second;
    return out;
}

void write_f64_grid_bin(const std::string& filepath, int Nx, int Ny, const std::vector<double>& data) {
    if (data.size() != static_cast<std::size_t>(Nx * Ny)) {
        throw std::runtime_error("write_f64_grid_bin: unexpected data size");
    }
    std::ofstream fout(filepath, std::ios::binary);
    if (!fout) {
        throw std::runtime_error("Cannot open f64 grid file for writing: " + filepath);
    }
    const std::int32_t Nx32 = static_cast<std::int32_t>(Nx);
    const std::int32_t Ny32 = static_cast<std::int32_t>(Ny);
    fout.write(reinterpret_cast<const char*>(&Nx32), sizeof(std::int32_t));
    fout.write(reinterpret_cast<const char*>(&Ny32), sizeof(std::int32_t));
    fout.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size() * sizeof(double)));
    if (!fout) {
        throw std::runtime_error("Failed while writing f64 grid payload");
    }
}

void write_i32_grid_bin_lc(const std::string& filepath, int Nx, int Ny, const std::vector<std::int32_t>& data) {
    if (data.size() != static_cast<std::size_t>(Nx * Ny)) {
        throw std::runtime_error("write_i32_grid_bin_lc: unexpected data size");
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


#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <limits>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

#include "boundary_conditions.h"
#include "common_grid.h"
#include "dump_io.h"
#include "liquid_closure.h"
#include "obstacles.h"
#include "params_io.h"
#include "srd_collision.h"
#include "state_io.h"
#include "types.h"
#include "visualization.h"
#include "zone_pass_openmp.h"

namespace {
using namespace mpcd;
using Clock = std::chrono::steady_clock;

struct PhaseTimers {
    double totalLoop = 0.0;
    double refBuild = 0.0;
    double base = 0.0;
    double shifted = 0.0;
    double closure = 0.0;
    double diagnostics = 0.0;
    double dumps = 0.0;

    double baseLayout = 0.0;
    double baseExtract = 0.0;
    double baseSnapshot = 0.0;
    double baseAlloc = 0.0;
    double baseKernel = 0.0;
    double basePack = 0.0;
    double baseMerge = 0.0;

    double shiftedLayout = 0.0;
    double shiftedExtract = 0.0;
    double shiftedSnapshot = 0.0;
    double shiftedAlloc = 0.0;
    double shiftedKernel = 0.0;
    double shiftedPack = 0.0;
    double shiftedMerge = 0.0;
};

double elapsed_seconds(const Clock::time_point& t0, const Clock::time_point& t1) {
    return std::chrono::duration<double>(t1 - t0).count();
}

std::string trim(const std::string& s) {
    std::size_t b = 0;
    while (b < s.size() && std::isspace(static_cast<unsigned char>(s[b]))) ++b;
    std::size_t e = s.size();
    while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) --e;
    return s.substr(b, e - b);
}

std::unordered_map<std::string, std::string> read_kv_map(const std::string& filepath) {
    std::ifstream fin(filepath);
    if (!fin) throw std::runtime_error("Cannot open params file: " + filepath);
    std::unordered_map<std::string, std::string> kv;
    std::string line;
    while (std::getline(fin, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;
        const auto pos = line.find('=');
        if (pos == std::string::npos) throw std::runtime_error("Invalid key=value line: " + line);
        kv[trim(line.substr(0, pos))] = trim(line.substr(pos + 1));
    }
    return kv;
}

const std::string& require_key(const std::unordered_map<std::string, std::string>& kv, const std::string& key) {
    auto it = kv.find(key);
    if (it == kv.end()) throw std::runtime_error("Missing benchmark key: " + key);
    return it->second;
}

int parse_int(const std::string& s) { return std::stoi(s); }
std::vector<int> parse_steps_csv(const std::string& s) {
    std::vector<int> out;
    std::stringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, ',')) {
        tok = trim(tok);
        if (!tok.empty()) out.push_back(std::stoi(tok));
    }
    std::sort(out.begin(), out.end());
    out.erase(std::unique(out.begin(), out.end()), out.end());
    return out;
}
bool contains_step(const std::vector<int>& steps, int step) {
    return std::binary_search(steps.begin(), steps.end(), step);
}

double mean_component(const std::vector<double>& a, int comp, int n) {
    double s = 0.0;
    for (int i = 0; i < n; ++i) s += a[2 * i + comp];
    return s / static_cast<double>(std::max(n, 1));
}

double mean_kinetic(const std::vector<double>& v, int n) {
    double s = 0.0;
    for (int i = 0; i < n; ++i) s += 0.5 * (v[2*i]*v[2*i] + v[2*i+1]*v[2*i+1]);
    return s / static_cast<double>(std::max(n, 1));
}

double mean_field(const std::vector<double>& f) {
    if (f.empty()) return 0.0;
    double s = 0.0;
    for (double x : f) s += x;
    return s / static_cast<double>(f.size());
}

double flow_rate_qx(const CellFields& G, const Params& params) {
    return mean_field(G.Ux) * params.Ly;
}

std::pair<double,double> compute_occstd_outband(const CellFields& G, const Params& params) {
    std::vector<double> Nact;
    Nact.reserve(static_cast<std::size_t>(params.Nc));
    const double gamma = params.gamma;
    const double coef = params.coef;
    double highThr = (params.highMode == "1+coef") ? gamma * (1.0 + coef) : gamma + gamma * coef;
    double lowThr = (params.lowMode == "1+coef") ? gamma / (1.0 + coef) : gamma - gamma * coef;
    if (std::isfinite(params.lowThrBulkOverride)) lowThr = params.lowThrBulkOverride;
    int outBandCount = 0;
    int activeCount = 0;
    for (double n : G.N) {
        Nact.push_back(n);
        ++activeCount;
        if ((n > highThr) || (n > 0.0 && n < lowThr)) ++outBandCount;
    }
    double mean = 0.0;
    for (double n : Nact) mean += n;
    mean /= std::max(1, activeCount);
    double var = 0.0;
    for (double n : Nact) {
        double d = n - mean;
        var += d*d;
    }
    var /= std::max(1, activeCount);
    double occStd = std::sqrt(var) / std::max(gamma, 1e-12);
    double outBand = static_cast<double>(outBandCount) / std::max(1, activeCount);
    return {occStd, outBand};
}

double rho_target_scalar(const Params& params) {
    const double dx = params.Lx / static_cast<double>(params.Nx);
    const double dy = params.Ly / static_cast<double>(params.Ny);
    return params.gamma / (dx * dy);
}


struct ObstacleCounts {
  int inside = 0;
  int near = 0;
};

ObstacleCounts compute_obstacle_counts(const State& state, const Params& params) {
  ObstacleCounts out;

  if (!obstacle_is_active_cylinder(params)) {
    return out;
  }

  const double dxCell = params.Lx / static_cast<double>(std::max(1, params.Nx));
  const double dyCell = params.Ly / static_cast<double>(std::max(1, params.Ny));
  const double shell = std::max(dxCell, dyCell);

  for (int i = 0; i < params.n; ++i) {
    const double d = cylinder_signed_distance(
        params,
        state.x[2 * i],
        state.x[2 * i + 1]
    );

    if (d <= 0.0) {
      ++out.inside;
    } else if (d <= shell) {
      ++out.near;
    }
  }

  return out;
}


struct FluidAwareOccDiag {
    double occStd = 0.0;
    double outBand = 0.0;
    int nActiveFluidCells = 0;
};

FluidAwareOccDiag compute_occstd_outband_fluid_aware(const CellFields& fields,
                                                     const Params& params,
                                                     const std::vector<double>& phi) {
    if (static_cast<int>(phi.size()) != params.Nc ||
        static_cast<int>(fields.N.size()) != params.Nc) {
        throw std::runtime_error("compute_occstd_outband_fluid_aware: inconsistent cell count");
    }

    FluidAwareOccDiag out;

    double sumPhi = 0.0;
    for (double p : phi) {
        if (p > 1e-12) {
            sumPhi += p;
        }
    }

    if (sumPhi <= 0.0) {
        return out;
    }

    const double gammaFluid = static_cast<double>(params.n) / sumPhi;
    const double coef = params.coef;

    double acc = 0.0;
    int nOut = 0;

    for (int c = 0; c < params.Nc; ++c) {
        const double phic = phi[static_cast<std::size_t>(c)];
        if (phic <= 1e-12) {
            continue;
        }

        ++out.nActiveFluidCells;

        const double target = gammaFluid * phic;
        const double N = static_cast<double>(fields.N[static_cast<std::size_t>(c)]);
        const double d = N - target;
        acc += d * d;

        const double highThr = target * (1.0 + coef);
        double lowThr = 0.0;
        if (params.lowMode == "1+coef") {
            lowThr = target / (1.0 + coef);
        } else {
            lowThr = target * (1.0 - coef);
        }

        // Same convention as compute_occstd_outband(...): empty active cells
        // are not counted as sparse/out-of-band.
        if (N > highThr || (N > 0.0 && N < lowThr)) {
            ++nOut;
        }
    }

    if (out.nActiveFluidCells > 0) {
        out.occStd = std::sqrt(acc / static_cast<double>(out.nActiveFluidCells)) /
                     std::max(gammaFluid, 1e-30);
        out.outBand = static_cast<double>(nOut) /
                      static_cast<double>(out.nActiveFluidCells);
    }

    return out;
}


int wake_cell_id(int ix, int iy, const Params& params) {
    return iy + params.Ny * ix;
}

double wake_nan() {
    return std::numeric_limits<double>::quiet_NaN();
}

double wrap_periodic(double x, double L) {
    if (L <= 0.0) return x;
    double y = std::fmod(x, L);
    if (y < 0.0) y += L;
    return y;
}

double signed_periodic_delta(double x, double center, double L) {
    double d = x - center;
    if (L > 0.0) {
        d -= L * std::floor(d / L + 0.5);
    }
    return d;
}

double positive_periodic_delta(double x, double center, double L) {
    if (L <= 0.0) return x - center;
    double d = x - center;
    d = std::fmod(d, L);
    if (d < 0.0) d += L;
    return d;
}

bool x_in_periodic_interval(double x, double x0, double x1, double L) {
    if (L <= 0.0) return (x >= x0 && x <= x1);
    if (x1 < x0) std::swap(x0, x1);
    if ((x1 - x0) >= L) return true;

    const double xx = wrap_periodic(x, L);
    const double a = wrap_periodic(x0, L);
    const double b = wrap_periodic(x1, L);

    if (a <= b) {
        return (xx >= a && xx <= b);
    }
    return (xx >= a || xx <= b);
}

std::vector<double> compute_wake_vorticity(const CellFields& f, const Params& params) {
    const int Nx = params.Nx;
    const int Ny = params.Ny;
    const int Nc = Nx * Ny;
    std::vector<double> omega(static_cast<std::size_t>(Nc), 0.0);

    const double dx = params.Lx / static_cast<double>(std::max(1, Nx));
    const double dy = params.Ly / static_cast<double>(std::max(1, Ny));
    const bool perX = (params.boundary_left == "periodic" && params.boundary_right == "periodic");

    for (int ix = 0; ix < Nx; ++ix) {
        for (int iy = 0; iy < Ny; ++iy) {
            int ixm = ix - 1;
            int ixp = ix + 1;
            double ddx = 2.0 * dx;

            if (ix == 0) {
                if (perX) ixm = Nx - 1;
                else { ixm = ix; ddx = dx; }
            }
            if (ix == Nx - 1) {
                if (perX) ixp = 0;
                else { ixp = ix; ddx = dx; }
            }

            int iym = iy - 1;
            int iyp = iy + 1;
            double ddy = 2.0 * dy;

            if (iy == 0) { iym = iy; ddy = dy; }
            if (iy == Ny - 1) { iyp = iy; ddy = dy; }

            const int c = wake_cell_id(ix, iy, params);
            const double dUy_dx =
                (f.Uy[static_cast<std::size_t>(wake_cell_id(ixp, iy, params))] -
                 f.Uy[static_cast<std::size_t>(wake_cell_id(ixm, iy, params))]) / std::max(ddx, 1e-30);
            const double dUx_dy =
                (f.Ux[static_cast<std::size_t>(wake_cell_id(ix, iyp, params))] -
                 f.Ux[static_cast<std::size_t>(wake_cell_id(ix, iym, params))]) / std::max(ddy, 1e-30);

            omega[static_cast<std::size_t>(c)] = dUy_dx - dUx_dy;
        }
    }

    return omega;
}

struct WakeWindowStats {
    double Ux = 0.0;
    double Uy = 0.0;
    double speed = 0.0;
    double omega = 0.0;
    double N = 0.0;
    int nCells = 0;
    double nParticles = 0.0;
};

template <typename Selector>
WakeWindowStats compute_wake_window_stats(const CellFields& f,
                                          const std::vector<double>& omega,
                                          const Params& params,
                                          Selector select_cell) {
    WakeWindowStats out;

    const int Nx = params.Nx;
    const int Ny = params.Ny;
    const double dx = params.Lx / static_cast<double>(std::max(1, Nx));
    const double dy = params.Ly / static_cast<double>(std::max(1, Ny));

    double sumN = 0.0;
    double sumUx = 0.0;
    double sumUy = 0.0;
    double sumOmega = 0.0;

    for (int ix = 0; ix < Nx; ++ix) {
        for (int iy = 0; iy < Ny; ++iy) {
            const int c = wake_cell_id(ix, iy, params);
            const double xc = (static_cast<double>(ix) + 0.5) * dx;
            const double yc = (static_cast<double>(iy) + 0.5) * dy;

            if (!select_cell(xc, yc)) {
                continue;
            }
            if (point_in_obstacle(params, xc, yc)) {
                continue;
            }

            ++out.nCells;
            const double Nc = static_cast<double>(f.N[static_cast<std::size_t>(c)]);
            out.nParticles += Nc;
            out.N += Nc;

            if (Nc <= 0.0) {
                continue;
            }

            sumN += Nc;
            sumUx += Nc * f.Ux[static_cast<std::size_t>(c)];
            sumUy += Nc * f.Uy[static_cast<std::size_t>(c)];
            sumOmega += Nc * omega[static_cast<std::size_t>(c)];
        }
    }

    if (out.nCells > 0) {
        out.N /= static_cast<double>(out.nCells);
    } else {
        out.N = wake_nan();
    }

    if (sumN > 0.0) {
        out.Ux = sumUx / sumN;
        out.Uy = sumUy / sumN;
        out.speed = std::sqrt(out.Ux * out.Ux + out.Uy * out.Uy);
        out.omega = sumOmega / sumN;
    } else {
        out.Ux = wake_nan();
        out.Uy = wake_nan();
        out.speed = wake_nan();
        out.omega = wake_nan();
    }

    return out;
}

struct WakeProbeRow {
    double Uref = 0.0;
    double Nref = 0.0;
    std::array<double, 4> probeX{};
    std::array<WakeWindowStats, 4> probe{};
    double wakeUyAsym = 0.0;
    double recircLength = 0.0;
};

WakeProbeRow compute_wake_probe_row(const CellFields& fields, const Params& params) {
    WakeProbeRow row;
    row.Uref = wake_nan();
    row.Nref = wake_nan();
    row.wakeUyAsym = wake_nan();
    row.recircLength = 0.0;

    if (!obstacle_is_active_cylinder(params)) {
        return row;
    }

    const std::vector<double> omega = compute_wake_vorticity(fields, params);

    const double cx = params.obstacleCx;
    const double cy = params.obstacleCy;
    const double R = params.obstacleRadius;
    const double D = 2.0 * R;
    const double Lx = params.Lx;
    const double Ly = params.Ly;

    if (!(D > 0.0 && Lx > 0.0 && Ly > 0.0)) {
        return row;
    }

    const double probeHalfWidth = std::max(0.0, params.wakeProbeHalfWidthOverD) * D;
    const double probeHalfHeight = std::max(0.0, params.wakeProbeHalfHeightOverD) * D;
    const double refHalfHeight = std::max(0.0, params.wakeReferenceHalfHeightOverD) * D;

    const double xRef0 = cx + params.wakeReferenceXMinOverD * D;
    const double xRef1 = cx + params.wakeReferenceXMaxOverD * D;
    const WakeWindowStats ref = compute_wake_window_stats(
        fields, omega, params,
        [&](double x, double y) {
            return x_in_periodic_interval(x, xRef0, xRef1, Lx) &&
                   std::abs(y - cy) <= refHalfHeight;
        }
    );
    row.Uref = ref.Ux;
    row.Nref = ref.N;

    const std::array<double, 4> probeOverD = {{
        params.wakeProbe1XOverD,
        params.wakeProbe2XOverD,
        params.wakeProbe3XOverD,
        params.wakeProbe4XOverD
    }};

    for (int k = 0; k < 4; ++k) {
        const double xCenterRaw = cx + probeOverD[static_cast<std::size_t>(k)] * D;
        const double xCenter = wrap_periodic(xCenterRaw, Lx);
        row.probeX[static_cast<std::size_t>(k)] = xCenter;
        row.probe[static_cast<std::size_t>(k)] = compute_wake_window_stats(
            fields, omega, params,
            [&](double x, double y) {
                return std::abs(signed_periodic_delta(x, xCenter, Lx)) <= probeHalfWidth &&
                       std::abs(y - cy) <= probeHalfHeight;
            }
        );
    }

    const double xWake0 = cx + D;
    const double xWake1 = cx + 4.0 * D;
    const WakeWindowStats top = compute_wake_window_stats(
        fields, omega, params,
        [&](double x, double y) {
            return x_in_periodic_interval(x, xWake0, xWake1, Lx) &&
                   y > cy && y <= cy + probeHalfHeight;
        }
    );
    const WakeWindowStats bot = compute_wake_window_stats(
        fields, omega, params,
        [&](double x, double y) {
            return x_in_periodic_interval(x, xWake0, xWake1, Lx) &&
                   y < cy && y >= cy - probeHalfHeight;
        }
    );
    if (std::isfinite(top.Uy) && std::isfinite(bot.Uy)) {
        row.wakeUyAsym = top.Uy - bot.Uy;
    }

    const double centerlineHalfHeight = std::max(probeHalfHeight * 0.25,
                                                0.5 * Ly / static_cast<double>(std::max(1, params.Ny)));
    const double maxDownstream = std::min(8.0 * D, 0.5 * Lx);

    for (int ix = 0; ix < params.Nx; ++ix) {
        for (int iy = 0; iy < params.Ny; ++iy) {
            const int c = wake_cell_id(ix, iy, params);
            const double xc = (static_cast<double>(ix) + 0.5) * (params.Lx / static_cast<double>(std::max(1, params.Nx)));
            const double yc = (static_cast<double>(iy) + 0.5) * (params.Ly / static_cast<double>(std::max(1, params.Ny)));
            const double downstream = positive_periodic_delta(xc, cx, Lx);

            if (downstream <= R || downstream > maxDownstream) {
                continue;
            }
            if (std::abs(yc - cy) > centerlineHalfHeight) {
                continue;
            }
            if (point_in_obstacle(params, xc, yc)) {
                continue;
            }
            if (fields.N[static_cast<std::size_t>(c)] <= 0) {
                continue;
            }
            if (fields.Ux[static_cast<std::size_t>(c)] < 0.0) {
                row.recircLength = std::max(row.recircLength, downstream - R);
            }
        }
    }

    return row;
}

void write_wake_probe_header(std::ostream& out) {
    out << "step,t,Uref,Nref";
    for (int k = 1; k <= 4; ++k) {
        out << ",p" << k << "_x"
            << ",p" << k << "_Ux"
            << ",p" << k << "_Uy"
            << ",p" << k << "_speed"
            << ",p" << k << "_omega"
            << ",p" << k << "_N"
            << ",p" << k << "_nCells"
            << ",p" << k << "_nParticles";
    }
    out << ",wake_Uy_asym,recircLength\n";
}

void write_wake_probe_row(std::ostream& out,
                          int step,
                          double t,
                          const Params& params,
                          const CellFields& fields) {
    const WakeProbeRow row = compute_wake_probe_row(fields, params);

    out << step << ',' << t << ',' << row.Uref << ',' << row.Nref;
    for (int k = 0; k < 4; ++k) {
        const WakeWindowStats& p = row.probe[static_cast<std::size_t>(k)];
        out << ',' << row.probeX[static_cast<std::size_t>(k)]
            << ',' << p.Ux
            << ',' << p.Uy
            << ',' << p.speed
            << ',' << p.omega
            << ',' << p.N
            << ',' << p.nCells
            << ',' << p.nParticles;
    }
    out << ',' << row.wakeUyAsym << ',' << row.recircLength << '\n';
}

void dump_state_prefix(const std::string& prefix, const State& s, int n, bool has_type, bool has_r0) {
    write_xy_interleaved(prefix + "_x.bin", s.x, n);
    write_xy_interleaved(prefix + "_v.bin", s.v, n);
    if (has_type) write_u8(prefix + "_type.bin", s.type, n);
    if (has_r0) write_xy_interleaved(prefix + "_r0.bin", s.r0, n);
}

void dump_snapshot(const std::string& out_prefix,
                   int step,
                   const State& state,
                   const CellFields& G,
                   int n,
                   bool has_type,
                   bool has_r0) {
    std::ostringstream oss;
    oss << out_prefix << "_step" << std::setw(4) << std::setfill('0') << step;
    const std::string prefix = oss.str();
    dump_state_prefix(prefix, state, n, has_type, has_r0);
    write_cell_fields_bin(prefix + "_cellfields.bin", G);
}

} // namespace

int main(int argc, char** argv) {
    if (argc != 10) {
        std::cerr << "Usage: " << argv[0]
                  << " params.kv state_x.bin state_v.bin state_type.bin state_r0.bin out_prefix has_type has_r0 nthreads\n";
        return 2;
    }

    const std::string params_path = argv[1];
    const std::string x_path = argv[2];
    const std::string v_path = argv[3];
    const std::string type_path = argv[4];
    const std::string r0_path = argv[5];
    const std::string out_prefix = argv[6];
    const bool has_type = std::string(argv[7]) == "1";
    const bool has_r0 = std::string(argv[8]) == "1";
    const int nthreads = std::max(1, std::stoi(argv[9]));

    try {
        const Params params = read_params_kv(params_path);
        const auto kv = read_kv_map(params_path);
        const int nSteps = parse_int(require_key(kv, "benchmark_nSteps"));
        const int metricsEvery = parse_int(require_key(kv, "benchmark_metricsEvery"));
        const std::vector<int> dumpSteps = parse_steps_csv(require_key(kv, "benchmark_dumpSteps"));

        State state = read_state(x_path, v_path, type_path, r0_path, has_type, has_r0, params.n);
        const double rhoTarget = rho_target_scalar(params);
        const int obstacleMaskSubsamplesDiag = 8;
        const double dxMaskDiag = params.Lx / static_cast<double>(std::max(1, params.Nx));
        const double dyMaskDiag = params.Ly / static_cast<double>(std::max(1, params.Ny));
        const auto phiBaseDiag = build_fluid_fraction_mask(params, obstacleMaskSubsamplesDiag, 0.0, 0.0);
        const auto phiShiftedDiag = build_fluid_fraction_mask(params, obstacleMaskSubsamplesDiag, 0.5 * dxMaskDiag, 0.5 * dyMaskDiag);
        const auto fluidMaskBaseDiag = summarize_fluid_fraction_mask(params, phiBaseDiag);
        const auto fluidMaskShiftedDiag = summarize_fluid_fraction_mask(params, phiShiftedDiag);

  Visualizer visualizer;
  visualizer.init(params);
  
        std::ofstream metrics(out_prefix + "_metrics.csv");
        if (!metrics) throw std::runtime_error("Cannot open metrics CSV for writing");
        metrics << "step,occStd,outBand,meanKinetic,meanUx,meanUy,Qx,baseOccStd,baseOutBand,shiftedOccStd,shiftedOutBand,baseOccStdFluid,baseOutBandFluid,shiftedOccStdFluid,shiftedOutBandFluid,meanPdrive,meanPdriveRaw,meanVelocityX,meanVelocityY,particlesMovedDense,particlesMovedSparse,betaRepairOpt,betaRepairApplied,betaRepairNum,betaRepairDen,rmsRepairDU,maxRepairDU,meanAbsRepairDU,nMaskedInterzoneCells,momentumDeltaX,momentumDeltaY,nThreadsUsedBase,nThreadsUsedShifted,nInsideObstacle,nNearObstacle,timeStepTotal,timeRefBuild,timeBase,timeShifted,timeClosure,timeDiagnostics,timeDump\n";

        const bool wakeDiagnosticsActive = params.wakeDiagnosticsEnable && obstacle_is_active_cylinder(params);
        const int wakeEvery = (params.wakeDiagnosticsEvery > 0) ? params.wakeDiagnosticsEvery : metricsEvery;
        std::ofstream wakeProbes;
        if (wakeDiagnosticsActive) {
            if (wakeEvery <= 0) {
                throw std::runtime_error("wake diagnostics enabled but wakeDiagnosticsEvery and benchmark_metricsEvery are both <= 0");
            }
            wakeProbes.open(out_prefix + "_wake_probes.csv");
            if (!wakeProbes) throw std::runtime_error("Cannot open wake probes CSV for writing");
            wakeProbes << std::setprecision(17);
            write_wake_probe_header(wakeProbes);
        }

        std::ofstream manifest(out_prefix + "_runout.kv");
        if (!manifest) throw std::runtime_error("Cannot open benchmark runout file");
        manifest << "inputTag=" << x_path << "\n";
        manifest << "outputTag=" << out_prefix << "\n";
        manifest << "benchmark_nSteps=" << nSteps << "\n";
        manifest << "benchmark_metricsEvery=" << metricsEvery << "\n";
        manifest << "benchmark_dumpSteps=" << require_key(kv, "benchmark_dumpSteps") << "\n";
        manifest << "wakeDiagnosticsEnable=" << (wakeDiagnosticsActive ? 1 : 0) << "\n";
        manifest << "wakeDiagnosticsEvery=" << wakeEvery << "\n";
        manifest << "wakeProbeXOverD="
                 << params.wakeProbe1XOverD << ","
                 << params.wakeProbe2XOverD << ","
                 << params.wakeProbe3XOverD << ","
                 << params.wakeProbe4XOverD << "\n";
        manifest << "wakeProbeHalfWidthOverD=" << params.wakeProbeHalfWidthOverD << "\n";
        manifest << "wakeProbeHalfHeightOverD=" << params.wakeProbeHalfHeightOverD << "\n";
        manifest << "wakeReferenceXMinOverD=" << params.wakeReferenceXMinOverD << "\n";
        manifest << "wakeReferenceXMaxOverD=" << params.wakeReferenceXMaxOverD << "\n";
        manifest << "wakeReferenceHalfHeightOverD=" << params.wakeReferenceHalfHeightOverD << "\n";
        manifest << "nThreadsRequested=" << nthreads << "\n";

        PhaseTimers timers;
        const auto t_all_start = Clock::now();

        if (wakeDiagnosticsActive) {
            const auto tw0 = Clock::now();
            const CellFields G0wake = compute_cell_fields(state.x, state.v, params, rhoTarget);
            write_wake_probe_row(wakeProbes, 0, 0.0, params, G0wake);
            timers.diagnostics += elapsed_seconds(tw0, Clock::now());
        }

        if (contains_step(dumpSteps, 0)) {
            const auto td0 = Clock::now();
            const CellFields G0 = compute_cell_fields(state.x, state.v, params, rhoTarget);
  if (visualizer.should_draw(0)) {
    visualizer.update(0, 0.0, params, state, G0);
  }
  
            dump_snapshot(out_prefix, 0, state, G0, params.n, has_type, has_r0);
            timers.dumps += elapsed_seconds(td0, Clock::now());
        }

        int finalThreadsBase = 1, finalThreadsShifted = 1;
        for (int step = 1; step <= nSteps; ++step) {
            const auto t_step_start = Clock::now();

            const auto t_ref0 = Clock::now();
            State stateRef = state;
            const std::vector<double> xBeforeStream = stateRef.x; for (int i = 0; i < params.n; ++i) {
                stateRef.v[2 * i] += params.bodyForceX * params.dt;
                stateRef.v[2 * i + 1] += params.g * params.dt;
                stateRef.x[2 * i] += params.dt * stateRef.v[2 * i];
                stateRef.x[2 * i + 1] += params.dt * stateRef.v[2 * i + 1];
            }
            WallInfo wallInfo;
            apply_cylinder_specular_swept_bc(stateRef.x, stateRef.v, xBeforeStream, params); apply_bc_general(stateRef.x, stateRef.v, params, wallInfo, 104729ULL + 10007ULL * static_cast<std::uint64_t>(step));
            const auto cid = srd_cell_id_with_random_shift(stateRef.x, params, 130363ULL + 10007ULL * static_cast<std::uint64_t>(step));
            srd_collision_step(stateRef.v, cid, params, 433494437ULL + 10007ULL * static_cast<std::uint64_t>(step));
            timers.refBuild += elapsed_seconds(t_ref0, Clock::now());

            const auto t_base0 = Clock::now();
            const auto baseResult = run_zone_pass_openmp(stateRef, params, "base", 88172645463325252ULL + 10007ULL * static_cast<std::uint64_t>(step), nthreads, phiBaseDiag);
            timers.base += elapsed_seconds(t_base0, Clock::now());
            timers.baseLayout += baseResult.metrics.timeLayout;
            timers.baseExtract += baseResult.metrics.timeZoneExtract;
            timers.baseSnapshot += baseResult.metrics.timeSnapshot;
            timers.baseAlloc += baseResult.metrics.timeAlloc;
            timers.baseKernel += baseResult.metrics.timeKernel;
            timers.basePack += baseResult.metrics.timePack;
            timers.baseMerge += baseResult.metrics.timeMerge;

            const auto t_shift0 = Clock::now();
            const auto shiftedResult = run_zone_pass_openmp(baseResult.stateOut, params, "shifted", 88172645463325252ULL + 4099ULL + 10007ULL * static_cast<std::uint64_t>(step), nthreads, phiBaseDiag);
            timers.shifted += elapsed_seconds(t_shift0, Clock::now());
            timers.shiftedLayout += shiftedResult.metrics.timeLayout;
            timers.shiftedExtract += shiftedResult.metrics.timeZoneExtract;
            timers.shiftedSnapshot += shiftedResult.metrics.timeSnapshot;
            timers.shiftedAlloc += shiftedResult.metrics.timeAlloc;
            timers.shiftedKernel += shiftedResult.metrics.timeKernel;
            timers.shiftedPack += shiftedResult.metrics.timePack;
            timers.shiftedMerge += shiftedResult.metrics.timeMerge;

            const auto t_closure0 = Clock::now();
            State shiftedStateForClosure = shiftedResult.stateOut;
      apply_cylinder_specular_position_bc(shiftedStateForClosure.x, shiftedStateForClosure.v, params);
      const auto closureResult = run_liquid_closure(stateRef, shiftedStateForClosure, params);
            const auto t_closure1 = Clock::now();
            state = closureResult.stateOut;
            
  if (visualizer.should_draw(step)) {
    visualizer.update(step, step * params.dt, params, state, closureResult.outFields);
    if (visualizer.should_close()) {
      break;
    }
  }

            if (wakeDiagnosticsActive && (step % wakeEvery == 0 || step == nSteps)) {
                const auto twake0 = Clock::now();
                write_wake_probe_row(wakeProbes, step, step * params.dt, params, closureResult.outFields);
                timers.diagnostics += elapsed_seconds(twake0, Clock::now());
            }
            const double timeClosureStep = elapsed_seconds(t_closure0, t_closure1);
            timers.closure += timeClosureStep;

            finalThreadsBase = baseResult.metrics.nThreadsUsed;
            finalThreadsShifted = shiftedResult.metrics.nThreadsUsed;

            double baseOccStd = 0.0, baseOutBand = 0.0, shiftedOccStd = 0.0, shiftedOutBand = 0.0;
            double baseOccStdFluid = 0.0, baseOutBandFluid = 0.0, shiftedOccStdFluid = 0.0, shiftedOutBandFluid = 0.0;

            if (metricsEvery > 0 && (step % metricsEvery == 0 || step == nSteps)) {
                const auto t_diag0 = Clock::now();
                const CellFields baseFields = compute_cell_fields(baseResult.stateOut.x, baseResult.stateOut.v, params, rhoTarget);
                const CellFields shiftedFields = compute_cell_fields(shiftedStateForClosure.x, shiftedStateForClosure.v, params, rhoTarget);
                const auto basePair = compute_occstd_outband(baseFields, params);
                const auto shiftedPair = compute_occstd_outband(shiftedFields, params);
                const auto baseFluidPair = compute_occstd_outband_fluid_aware(baseFields, params, phiBaseDiag);
                const auto shiftedFluidPair = compute_occstd_outband_fluid_aware(shiftedFields, params, phiBaseDiag);
                baseOccStd = basePair.first;
                baseOutBand = basePair.second;
                shiftedOccStd = shiftedPair.first;
                shiftedOutBand = shiftedPair.second;
                baseOccStdFluid = baseFluidPair.occStd;
                baseOutBandFluid = baseFluidPair.outBand;
                shiftedOccStdFluid = shiftedFluidPair.occStd;
                shiftedOutBandFluid = shiftedFluidPair.outBand;
                timers.diagnostics += elapsed_seconds(t_diag0, Clock::now());
        const ObstacleCounts obsCounts = compute_obstacle_counts(state, params);

                const double timeStepTotal = elapsed_seconds(t_step_start, Clock::now());
                metrics << step << ','
                        << shiftedOccStd << ','
                        << shiftedOutBand << ','
                        << mean_kinetic(state.v, params.n) << ','
                        << mean_field(closureResult.outFields.Ux) << ','
                        << mean_field(closureResult.outFields.Uy) << ','
                        << flow_rate_qx(closureResult.outFields, params) << ','
                        << baseOccStd << ','
                        << baseOutBand << ','
                        << shiftedOccStd << ','
                        << shiftedOutBand << ','
                        << baseOccStdFluid << ','
                        << baseOutBandFluid << ','
                        << shiftedOccStdFluid << ','
                        << shiftedOutBandFluid << ','
                        << closureResult.metrics.meanPdrive << ','
                        << closureResult.metrics.meanPdriveRaw << ','
                        << mean_component(state.v, 0, params.n) << ','
                        << mean_component(state.v, 1, params.n) << ','
                        << (baseResult.metrics.nParticlesMovedDense + shiftedResult.metrics.nParticlesMovedDense) << ','
                        << (baseResult.metrics.nParticlesMovedSparse + shiftedResult.metrics.nParticlesMovedSparse) << ','
                        << closureResult.metrics.betaRepairOpt << ','
                        << closureResult.metrics.betaRepairApplied << ','
                        << closureResult.metrics.betaRepairNum << ','
                        << closureResult.metrics.betaRepairDen << ','
                        << closureResult.metrics.rmsRepairDU << ','
                        << closureResult.metrics.maxRepairDU << ','
                        << closureResult.metrics.meanAbsRepairDU << ','
                        << closureResult.metrics.nMaskedInterzoneCells << ','
                        << closureResult.metrics.momentumDeltaX << ','
                        << closureResult.metrics.momentumDeltaY << ','
                        << baseResult.metrics.nThreadsUsed << ',' << shiftedResult.metrics.nThreadsUsed << ',' << obsCounts.inside << ',' << obsCounts.near << ',' << timeStepTotal << ','
                        << elapsed_seconds(t_ref0, t_base0) << ','
                        << elapsed_seconds(t_base0, t_shift0) << ','
                        << elapsed_seconds(t_shift0, t_closure0) << ','
                        << timeClosureStep << ','
                        << elapsed_seconds(t_diag0, Clock::now()) << ','
                        << 0.0 << '\n';
            }

            if (contains_step(dumpSteps, step)) {
                const auto t_dump0 = Clock::now();
                dump_snapshot(out_prefix, step, state, closureResult.outFields, params.n, has_type, has_r0);
                timers.dumps += elapsed_seconds(t_dump0, Clock::now());
            }

            timers.totalLoop += elapsed_seconds(t_step_start, Clock::now());

            if (step == nSteps) {
                if (!(metricsEvery > 0 && (step % metricsEvery == 0 || step == nSteps))) {
                    const CellFields baseFields = compute_cell_fields(baseResult.stateOut.x, baseResult.stateOut.v, params, rhoTarget);
                    const CellFields shiftedFields = compute_cell_fields(shiftedStateForClosure.x, shiftedStateForClosure.v, params, rhoTarget);
                    const auto basePair = compute_occstd_outband(baseFields, params);
                    const auto shiftedPair = compute_occstd_outband(shiftedFields, params);
                    baseOccStd = basePair.first;
                    baseOutBand = basePair.second;
                    shiftedOccStd = shiftedPair.first;
                    shiftedOutBand = shiftedPair.second;
                }
                manifest << "finalOccStd=" << shiftedOccStd << "\n";
                manifest << "finalOutBand=" << shiftedOutBand << "\n";
                manifest << "finalOccStdFluid=" << shiftedOccStdFluid << "\n";
                manifest << "finalOutBandFluid=" << shiftedOutBandFluid << "\n";
                manifest << "finalBaseOccStdFluid=" << baseOccStdFluid << "\n";
                manifest << "finalBaseOutBandFluid=" << baseOutBandFluid << "\n";
                manifest << "finalMeanKinetic=" << mean_kinetic(state.v, params.n) << "\n";
                manifest << "finalMeanVelocityX=" << mean_component(state.v, 0, params.n) << "\n";
                manifest << "finalMeanVelocityY=" << mean_component(state.v, 1, params.n) << "\n";
        const ObstacleCounts finalObsCounts = compute_obstacle_counts(state, params);
        manifest << "finalInsideObstacle=" << finalObsCounts.inside << "\n";
        manifest << "finalNearObstacle=" << finalObsCounts.near << "\n";
        const int obstacleMaskSubsamples = 8;
        const double dxMask = params.Lx / static_cast<double>(std::max(1, params.Nx));
        const double dyMask = params.Ly / static_cast<double>(std::max(1, params.Ny));

        const auto phiBase = build_fluid_fraction_mask(
            params,
            obstacleMaskSubsamples,
            0.0,
            0.0
        );
        const auto phiShifted = build_fluid_fraction_mask(
            params,
            obstacleMaskSubsamples,
            0.5 * dxMask,
            0.5 * dyMask
        );

        const auto maskBase = summarize_fluid_fraction_mask(params, phiBase);
        const auto maskShifted = summarize_fluid_fraction_mask(params, phiShifted);

        manifest << "obstacleMaskSubsamples=" << obstacleMaskSubsamples << "\n";

        manifest << "fluidMaskBaseSum=" << maskBase.sumFluidFraction << "\n";
        manifest << "fluidMaskBaseSolidCells=" << maskBase.nSolidCells << "\n";
        manifest << "fluidMaskBasePartialCells=" << maskBase.nPartialCells << "\n";
        manifest << "fluidMaskBaseFullFluidCells=" << maskBase.nFullFluidCells << "\n";
        manifest << "fluidMaskBaseGammaFluid=" << maskBase.gammaFluidObstacle << "\n";

        manifest << "fluidMaskShiftedSum=" << maskShifted.sumFluidFraction << "\n";
        manifest << "fluidMaskShiftedSolidCells=" << maskShifted.nSolidCells << "\n";
        manifest << "fluidMaskShiftedPartialCells=" << maskShifted.nPartialCells << "\n";
        manifest << "fluidMaskShiftedFullFluidCells=" << maskShifted.nFullFluidCells << "\n";
        manifest << "fluidMaskShiftedGammaFluid=" << maskShifted.gammaFluidObstacle << "\n";
        manifest << "fluidMaskBaseDiagSum=" << fluidMaskBaseDiag.sumFluidFraction << "\n";
        manifest << "fluidMaskBaseDiagGammaFluid=" << fluidMaskBaseDiag.gammaFluidObstacle << "\n";
        manifest << "fluidMaskShiftedDiagSum=" << fluidMaskShiftedDiag.sumFluidFraction << "\n";
        manifest << "fluidMaskShiftedDiagGammaFluid=" << fluidMaskShiftedDiag.gammaFluidObstacle << "\n";
        manifest << "fluidMaskUsedForBaseRedistribution=baseCellMask\n";
        manifest << "fluidMaskUsedForShiftedRedistribution=baseCellMask\n";

                manifest << "finalQx=" << flow_rate_qx(closureResult.outFields, params) << "\n";
                manifest << "totalParticlesMovedDense=" << (baseResult.metrics.nParticlesMovedDense + shiftedResult.metrics.nParticlesMovedDense) << "\n";
                manifest << "totalParticlesMovedSparse=" << (baseResult.metrics.nParticlesMovedSparse + shiftedResult.metrics.nParticlesMovedSparse) << "\n";
                manifest << "finalBetaRepairOpt=" << closureResult.metrics.betaRepairOpt << "\n";
                manifest << "finalBetaRepairApplied=" << closureResult.metrics.betaRepairApplied << "\n";
                manifest << "finalBetaRepairNum=" << closureResult.metrics.betaRepairNum << "\n";
                manifest << "finalBetaRepairDen=" << closureResult.metrics.betaRepairDen << "\n";
                manifest << "finalRmsRepairDU=" << closureResult.metrics.rmsRepairDU << "\n";
                manifest << "finalMaxRepairDU=" << closureResult.metrics.maxRepairDU << "\n";
                manifest << "finalMeanAbsRepairDU=" << closureResult.metrics.meanAbsRepairDU << "\n";
                manifest << "finalMomentumDeltaX=" << closureResult.metrics.momentumDeltaX << "\n";
                manifest << "finalMomentumDeltaY=" << closureResult.metrics.momentumDeltaY << "\n";
                manifest << "nThreadsUsedBase=" << finalThreadsBase << "\n";
                manifest << "nThreadsUsedShifted=" << finalThreadsShifted << "\n";
            }
        }

        const double totalWall = elapsed_seconds(t_all_start, Clock::now());
        manifest << "timeTotalWall=" << totalWall << "\n";
        manifest << "timeLoopTotal=" << timers.totalLoop << "\n";
        manifest << "timeRefBuild=" << timers.refBuild << "\n";
        manifest << "timeBase=" << timers.base << "\n";
        manifest << "timeShifted=" << timers.shifted << "\n";
        manifest << "timeClosure=" << timers.closure << "\n";
        manifest << "timeDiagnostics=" << timers.diagnostics << "\n";
        manifest << "timeDumps=" << timers.dumps << "\n";
        manifest << "timePerStepMean=" << (timers.totalLoop / std::max(1, nSteps)) << "\n";
        manifest << "fracRefBuild=" << (timers.totalLoop > 0 ? timers.refBuild / timers.totalLoop : 0.0) << "\n";
        manifest << "fracBase=" << (timers.totalLoop > 0 ? timers.base / timers.totalLoop : 0.0) << "\n";
        manifest << "fracShifted=" << (timers.totalLoop > 0 ? timers.shifted / timers.totalLoop : 0.0) << "\n";
        manifest << "fracClosure=" << (timers.totalLoop > 0 ? timers.closure / timers.totalLoop : 0.0) << "\n";
        manifest << "fracDiagnostics=" << (timers.totalLoop > 0 ? timers.diagnostics / timers.totalLoop : 0.0) << "\n";
        manifest << "fracDumps=" << (timers.totalLoop > 0 ? timers.dumps / timers.totalLoop : 0.0) << "\n";
        manifest << "timeBaseLayout=" << timers.baseLayout << "\n";
        manifest << "timeBaseExtract=" << timers.baseExtract << "\n";
        manifest << "timeBaseSnapshot=" << timers.baseSnapshot << "\n";
        manifest << "timeBaseAlloc=" << timers.baseAlloc << "\n";
        manifest << "timeBaseKernel=" << timers.baseKernel << "\n";
        manifest << "timeBasePack=" << timers.basePack << "\n";
        manifest << "timeBaseMerge=" << timers.baseMerge << "\n";
        manifest << "timeShiftedLayout=" << timers.shiftedLayout << "\n";
        manifest << "timeShiftedExtract=" << timers.shiftedExtract << "\n";
        manifest << "timeShiftedSnapshot=" << timers.shiftedSnapshot << "\n";
        manifest << "timeShiftedAlloc=" << timers.shiftedAlloc << "\n";
        manifest << "timeShiftedKernel=" << timers.shiftedKernel << "\n";
        manifest << "timeShiftedPack=" << timers.shiftedPack << "\n";
        manifest << "timeShiftedMerge=" << timers.shiftedMerge << "\n";
        manifest << "fracBaseLayout=" << (timers.base > 0 ? timers.baseLayout / timers.base : 0.0) << "\n";
        manifest << "fracBaseExtract=" << (timers.base > 0 ? timers.baseExtract / timers.base : 0.0) << "\n";
        manifest << "fracBaseSnapshot=" << (timers.base > 0 ? timers.baseSnapshot / timers.base : 0.0) << "\n";
        manifest << "fracBaseAlloc=" << (timers.base > 0 ? timers.baseAlloc / timers.base : 0.0) << "\n";
        manifest << "fracBaseKernel=" << (timers.base > 0 ? timers.baseKernel / timers.base : 0.0) << "\n";
        manifest << "fracBasePack=" << (timers.base > 0 ? timers.basePack / timers.base : 0.0) << "\n";
        manifest << "fracBaseMerge=" << (timers.base > 0 ? timers.baseMerge / timers.base : 0.0) << "\n";
        manifest << "fracShiftedLayout=" << (timers.shifted > 0 ? timers.shiftedLayout / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedExtract=" << (timers.shifted > 0 ? timers.shiftedExtract / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedSnapshot=" << (timers.shifted > 0 ? timers.shiftedSnapshot / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedAlloc=" << (timers.shifted > 0 ? timers.shiftedAlloc / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedKernel=" << (timers.shifted > 0 ? timers.shiftedKernel / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedPack=" << (timers.shifted > 0 ? timers.shiftedPack / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedMerge=" << (timers.shifted > 0 ? timers.shiftedMerge / timers.shifted : 0.0) << "\n";
    visualizer.shutdown();
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}

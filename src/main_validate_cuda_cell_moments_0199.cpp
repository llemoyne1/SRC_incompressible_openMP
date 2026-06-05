#include "cuda_cell_moments.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

int parse_int_arg(int argc, char** argv, const std::string& name, int fallback) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (argv[i] == name) return std::stoi(argv[i + 1]);
    }
    return fallback;
}

double parse_double_arg(int argc, char** argv, const std::string& name, double fallback) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (argv[i] == name) return std::stod(argv[i + 1]);
    }
    return fallback;
}

std::string parse_string_arg(int argc, char** argv, const std::string& name, const std::string& fallback) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (argv[i] == name) return argv[i + 1];
    }
    return fallback;
}

bool parse_bool_arg(int argc, char** argv, const std::string& name, bool fallback) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            const std::string v = argv[i + 1];
            return v == "1" || v == "true" || v == "yes" || v == "on";
        }
    }
    return fallback;
}

double wrap_periodic(double x, const double L) {
    x = std::fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

int bounded_cell_index(double xs, const double L, const double dx, const int N) {
    xs = std::clamp(xs, 0.0, L);
    int i = static_cast<int>(std::floor(xs / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

int periodic_cell_index(double xs, const double L, const double dx, const int N) {
    xs = wrap_periodic(xs, L);
    int i = static_cast<int>(std::floor(xs / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

int cell_index_from_position_cpu(double x,
                                 double y,
                                 const mpcd::CellGrid& grid,
                                 const mpcd::GridShift& shift,
                                 const mpcd::SimulationParams& params) {
    const double xs = x + shift.sx;
    const double ys = y + shift.sy;
    const bool periodicX = params.bcLeft == "periodic" && params.bcRight == "periodic";
    const bool periodicY = params.bcBottom == "periodic" && params.bcTop == "periodic";
    const int ix = periodicX ? periodic_cell_index(xs, grid.Lx, grid.dx, grid.Nx)
                             : bounded_cell_index(xs, grid.Lx, grid.dx, grid.Nx);
    const int iy = periodicY ? periodic_cell_index(ys, grid.Ly, grid.dy, grid.Ny)
                             : bounded_cell_index(ys, grid.Ly, grid.dy, grid.Ny);
    return ix + grid.Nx * iy;
}

mpcd::CellGrid make_grid(const int nx, const int ny, const double lx, const double ly) {
    mpcd::CellGrid grid{};
    grid.Nx = nx;
    grid.Ny = ny;
    grid.numCells = nx * ny;
    grid.Lx = lx;
    grid.Ly = ly;
    grid.dx = lx / static_cast<double>(nx);
    grid.dy = ly / static_cast<double>(ny);
    return grid;
}

mpcd::ParticleState make_synthetic_state(const int nx, const int ny, const int gamma,
                                         const double lx, const double ly,
                                         const bool mixedRoles) {
    if (nx <= 0 || ny <= 0 || gamma <= 0) {
        throw std::runtime_error("make_synthetic_state: invalid dimensions/gamma");
    }
    const std::uint64_t n = static_cast<std::uint64_t>(nx) * static_cast<std::uint64_t>(ny) *
                            static_cast<std::uint64_t>(gamma);
    mpcd::ParticleState state{};
    state.Np = n;
    state.dim = 2u;
    const std::size_t ns = static_cast<std::size_t>(n);
    state.x.assign(ns, 0.0);
    state.y.assign(ns, 0.0);
    state.vx.assign(ns, 0.0);
    state.vy.assign(ns, 0.0);
    state.mass.assign(ns, 1.0);
    state.type.assign(ns, 1u);
    state.role.assign(ns, mpcd::kParticleRoleFluid);

    constexpr double pi = 3.141592653589793238462643383279502884;
    std::size_t p = 0;
    for (int j = 0; j < ny; ++j) {
        for (int i = 0; i < nx; ++i) {
            for (int g = 0; g < gamma; ++g, ++p) {
                const double fx = (static_cast<double>((37 * (g + 1) + 11 * i + 5 * j) % 997) + 0.5) / 997.0;
                const double fy = (static_cast<double>((53 * (g + 1) + 7 * i + 13 * j) % 991) + 0.5) / 991.0;
                state.x[p] = (static_cast<double>(i) + fx) * lx / static_cast<double>(nx);
                state.y[p] = (static_cast<double>(j) + fy) * ly / static_cast<double>(ny);
                const double xx = state.x[p] / lx;
                const double yy = state.y[p] / ly;
                state.vx[p] = std::sin(2.0 * pi * xx) * std::cos(2.0 * pi * yy) + 0.01 * static_cast<double>((g % 7) - 3);
                state.vy[p] = -std::cos(2.0 * pi * xx) * std::sin(2.0 * pi * yy) + 0.01 * static_cast<double>((g % 5) - 2);
                state.mass[p] = 1.0 + 0.001 * static_cast<double>((i + 3 * j + 5 * g) % 17);
                state.type[p] = static_cast<std::uint32_t>(1 + ((i + j + g) % 3));
                if (mixedRoles) {
                    if (((i + 2 * j + 3 * g) % 29) == 0) {
                        state.role[p] = mpcd::kParticleRoleInactive;
                    } else if (((3 * i + j + 5 * g) % 31) == 0) {
                        state.role[p] = mpcd::kParticleRoleLatent;
                    }
                }
            }
        }
    }
    return state;
}

mpcd::CudaCellMoments cpu_deposit(const mpcd::ParticleState& state,
                                  const mpcd::CellGrid& grid,
                                  const mpcd::GridShift& shift,
                                  const mpcd::SimulationParams& params) {
    mpcd::CudaCellMoments out{};
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    out.cellId.assign(n, -1);
    out.cellCount.assign(static_cast<std::size_t>(nc), 0u);
    out.cellMass.assign(static_cast<std::size_t>(nc), 0.0);
    out.cellPx.assign(static_cast<std::size_t>(nc), 0.0);
    out.cellPy.assign(static_cast<std::size_t>(nc), 0.0);
    out.cellUx.assign(static_cast<std::size_t>(nc), 0.0);
    out.cellUy.assign(static_cast<std::size_t>(nc), 0.0);

    for (std::size_t i = 0; i < n; ++i) {
        if (!mpcd::is_fluid_particle(state, i)) continue;
        const int c = cell_index_from_position_cpu(state.x[i], state.y[i], grid, shift, params);
        out.cellId[i] = c;
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = state.mass[i];
        out.cellCount[k] += 1u;
        out.cellMass[k] += m;
        out.cellPx[k] += m * state.vx[i];
        out.cellPy[k] += m * state.vy[i];
    }
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = out.cellMass[k];
        if (m > 0.0) {
            out.cellUx[k] = out.cellPx[k] / m;
            out.cellUy[k] = out.cellPy[k] / m;
        }
    }
    return out;
}

struct DiffStats {
    std::uint64_t cellIdMismatches = 0u;
    std::uint64_t countMismatches = 0u;
    double maxAbsMass = 0.0;
    double maxAbsPx = 0.0;
    double maxAbsPy = 0.0;
    double maxAbsUx = 0.0;
    double maxAbsUy = 0.0;
    double sumAbsMass = 0.0;
    double sumAbsPx = 0.0;
    double sumAbsPy = 0.0;
};

DiffStats compare(const mpcd::CudaCellMoments& ref, const mpcd::CudaCellMoments& got) {
    if (ref.cellId.size() != got.cellId.size() || ref.cellCount.size() != got.cellCount.size()) {
        throw std::runtime_error("compare: incompatible output sizes");
    }
    DiffStats d{};
    for (std::size_t i = 0; i < ref.cellId.size(); ++i) {
        if (ref.cellId[i] != got.cellId[i]) ++d.cellIdMismatches;
    }
    for (std::size_t k = 0; k < ref.cellCount.size(); ++k) {
        if (ref.cellCount[k] != got.cellCount[k]) ++d.countMismatches;
        const double dm = std::abs(ref.cellMass[k] - got.cellMass[k]);
        const double dpx = std::abs(ref.cellPx[k] - got.cellPx[k]);
        const double dpy = std::abs(ref.cellPy[k] - got.cellPy[k]);
        const double dux = std::abs(ref.cellUx[k] - got.cellUx[k]);
        const double duy = std::abs(ref.cellUy[k] - got.cellUy[k]);
        d.maxAbsMass = std::max(d.maxAbsMass, dm);
        d.maxAbsPx = std::max(d.maxAbsPx, dpx);
        d.maxAbsPy = std::max(d.maxAbsPy, dpy);
        d.maxAbsUx = std::max(d.maxAbsUx, dux);
        d.maxAbsUy = std::max(d.maxAbsUy, duy);
        d.sumAbsMass += dm;
        d.sumAbsPx += dpx;
        d.sumAbsPy += dpy;
    }
    return d;
}

} // namespace

int main(int argc, char** argv) {
    try {
        const int nx = parse_int_arg(argc, argv, "--Nx", 64);
        const int ny = parse_int_arg(argc, argv, "--Ny", nx);
        const int gamma = parse_int_arg(argc, argv, "--gamma", 20);
        const int repeats = parse_int_arg(argc, argv, "--repeats", 1);
        const bool mixedRoles = parse_bool_arg(argc, argv, "--mixedRoles", false);
        const double tol = parse_double_arg(argc, argv, "--tolerance", 1.0e-10);
        const std::string csvPath = parse_string_arg(argc, argv, "--csv", "");

        mpcd::SimulationParams params{};
        params.Nx = nx;
        params.Ny = ny;
        params.Lx = 1.0;
        params.Ly = 1.0;
        params.bcLeft = "periodic";
        params.bcRight = "periodic";
        params.bcBottom = "periodic";
        params.bcTop = "periodic";

        const mpcd::CellGrid grid = make_grid(nx, ny, params.Lx, params.Ly);
        mpcd::GridShift shift{};
        shift.sx = 0.37 * grid.dx;
        shift.sy = -0.23 * grid.dy;

        mpcd::ParticleState state = make_synthetic_state(nx, ny, gamma, params.Lx, params.Ly, mixedRoles);
        mpcd::validate_particle_state(state, "validate_cuda_cell_moments_0199");

        const mpcd::CudaCellMoments cpu = cpu_deposit(state, grid, shift, params);
        mpcd::CudaCellMoments gpu;
        mpcd::CudaCellMomentsDiagnostics diag{};
        for (int r = 0; r < std::max(1, repeats); ++r) {
            mpcd::cuda_deposit_cell_moments_atomic(state, grid, shift, params, gpu, &diag);
        }

        const DiffStats diff = compare(cpu, gpu);
        const bool pass = diff.cellIdMismatches == 0u && diff.countMismatches == 0u &&
                          diff.maxAbsMass <= tol && diff.maxAbsPx <= tol && diff.maxAbsPy <= tol &&
                          diff.maxAbsUx <= tol && diff.maxAbsUy <= tol;

        std::cout << std::setprecision(17)
                  << "CUDA_CELL_MOMENTS_0199 " << (pass ? "PASS" : "FAIL")
                  << " Nx=" << nx
                  << " Ny=" << ny
                  << " gamma=" << gamma
                  << " particles=" << state.Np
                  << " fluidParticles=" << diag.fluidParticles
                  << " totalSeconds=" << diag.totalSeconds
                  << " kernelSeconds=" << diag.kernelSeconds
                  << " maxAbsMass=" << diff.maxAbsMass
                  << " maxAbsPx=" << diff.maxAbsPx
                  << " maxAbsPy=" << diff.maxAbsPy
                  << " maxAbsUx=" << diff.maxAbsUx
                  << " maxAbsUy=" << diff.maxAbsUy
                  << " countMismatches=" << diff.countMismatches
                  << " cellIdMismatches=" << diff.cellIdMismatches
                  << "\n";

        if (!csvPath.empty()) {
            std::ofstream out(csvPath);
            if (!out) throw std::runtime_error("cannot open csv output: " + csvPath);
            out << "case,Nx,Ny,gamma,particles,fluidParticles,numCells,mixedRoles,repeats,verdict,"
                << "totalSeconds,uploadSeconds,kernelSeconds,downloadSeconds,"
                << "cellIdMismatches,countMismatches,maxAbsMass,maxAbsPx,maxAbsPy,maxAbsUx,maxAbsUy,"
                << "sumAbsMass,sumAbsPx,sumAbsPy\n";
            out << "cuda_cell_moments_0199,"
                << nx << ',' << ny << ',' << gamma << ',' << state.Np << ',' << diag.fluidParticles << ','
                << grid.numCells << ',' << (mixedRoles ? 1 : 0) << ',' << repeats << ',' << (pass ? "PASS" : "FAIL") << ','
                << std::setprecision(17)
                << diag.totalSeconds << ',' << diag.uploadSeconds << ',' << diag.kernelSeconds << ',' << diag.downloadSeconds << ','
                << diff.cellIdMismatches << ',' << diff.countMismatches << ','
                << diff.maxAbsMass << ',' << diff.maxAbsPx << ',' << diff.maxAbsPy << ','
                << diff.maxAbsUx << ',' << diff.maxAbsUy << ','
                << diff.sumAbsMass << ',' << diff.sumAbsPx << ',' << diff.sumAbsPy << "\n";
        }

        return pass ? 0 : 2;
    } catch (const std::exception& e) {
        std::cerr << "CUDA_CELL_MOMENTS_0199 ERROR: " << e.what() << "\n";
        return 1;
    }
}

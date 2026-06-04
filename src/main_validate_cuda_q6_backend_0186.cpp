#include "cuda_q6_backend.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

int parse_int_arg(int argc, char** argv, const std::string& name, int fallback) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            return std::stoi(argv[i + 1]);
        }
    }
    return fallback;
}

double parse_double_arg(int argc, char** argv, const std::string& name, double fallback) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            return std::stod(argv[i + 1]);
        }
    }
    return fallback;
}

int cell_index(const int i, const int j, const int nx) {
    return j * nx + i;
}

int wrap(const int i, const int n) {
    return (i % n + n) % n;
}

mpcd::EllipticOperatorPlan make_periodic_plan(const int nx, const int ny,
                                              const double lx, const double ly) {
    if (nx <= 0 || ny <= 0) {
        throw std::runtime_error("make_periodic_plan: grid dimensions must be positive");
    }
    mpcd::EllipticOperatorPlan plan{};
    plan.Nx = nx;
    plan.Ny = ny;
    plan.numCells = nx * ny;
    plan.dx = lx / static_cast<double>(nx);
    plan.dy = ly / static_cast<double>(ny);
    plan.bcX = mpcd::EllipticBoundaryType::Periodic;
    plan.bcY = mpcd::EllipticBoundaryType::Periodic;

    const int nc = plan.numCells;
    plan.activeCells.resize(static_cast<std::size_t>(nc));
    std::iota(plan.activeCells.begin(), plan.activeCells.end(), 0);
    plan.inactiveCells.clear();
    plan.east.assign(static_cast<std::size_t>(nc), 0);
    plan.west.assign(static_cast<std::size_t>(nc), 0);
    plan.north.assign(static_cast<std::size_t>(nc), 0);
    plan.south.assign(static_cast<std::size_t>(nc), 0);
    plan.coeffEast.assign(static_cast<std::size_t>(nc), 0.0);
    plan.coeffWest.assign(static_cast<std::size_t>(nc), 0.0);
    plan.coeffNorth.assign(static_cast<std::size_t>(nc), 0.0);
    plan.coeffSouth.assign(static_cast<std::size_t>(nc), 0.0);

    const double invDx2 = 1.0 / (plan.dx * plan.dx);
    const double invDy2 = 1.0 / (plan.dy * plan.dy);
    for (int j = 0; j < ny; ++j) {
        for (int i = 0; i < nx; ++i) {
            const int c = cell_index(i, j, nx);
            const std::size_t k = static_cast<std::size_t>(c);
            plan.east[k] = cell_index(wrap(i + 1, nx), j, nx);
            plan.west[k] = cell_index(wrap(i - 1, nx), j, nx);
            plan.north[k] = cell_index(i, wrap(j + 1, ny), nx);
            plan.south[k] = cell_index(i, wrap(j - 1, ny), nx);
            plan.coeffEast[k] = invDx2;
            plan.coeffWest[k] = invDx2;
            plan.coeffNorth[k] = invDy2;
            plan.coeffSouth[k] = invDy2;
        }
    }
    return plan;
}

double cpu_apply_plan_and_dot(const mpcd::EllipticOperatorPlan& plan,
                              const std::vector<double>& phi,
                              std::vector<double>& Aphi) {
    Aphi.assign(static_cast<std::size_t>(plan.numCells), 0.0);
    double pAp = 0.0;
    for (const int c : plan.activeCells) {
        const std::size_t k = static_cast<std::size_t>(c);
        const double pc = phi[k];
        const double v =
            plan.coeffEast[k]  * (pc - phi[static_cast<std::size_t>(plan.east[k])]) +
            plan.coeffWest[k]  * (pc - phi[static_cast<std::size_t>(plan.west[k])]) +
            plan.coeffNorth[k] * (pc - phi[static_cast<std::size_t>(plan.north[k])]) +
            plan.coeffSouth[k] * (pc - phi[static_cast<std::size_t>(plan.south[k])]);
        Aphi[k] = v;
        pAp += pc * v;
    }
    return pAp;
}

std::vector<double> make_test_phi(const int nx, const int ny) {
    constexpr double pi = 3.141592653589793238462643383279502884;
    std::vector<double> phi(static_cast<std::size_t>(nx * ny), 0.0);
    for (int j = 0; j < ny; ++j) {
        for (int i = 0; i < nx; ++i) {
            const double x = static_cast<double>(i) / static_cast<double>(nx);
            const double y = static_cast<double>(j) / static_cast<double>(ny);
            const double small = static_cast<double>((17 * i + 13 * j) % 11) * 1.0e-3;
            phi[static_cast<std::size_t>(cell_index(i, j, nx))] =
                std::sin(2.0 * pi * x) + 0.25 * std::cos(4.0 * pi * y) + small;
        }
    }
    return phi;
}

} // namespace

int main(int argc, char** argv) {
    try {
        const int nx = parse_int_arg(argc, argv, "--nx", 64);
        const int ny = parse_int_arg(argc, argv, "--ny", 48);
        const double tolerance = parse_double_arg(argc, argv, "--tolerance", 1.0e-10);

        if (!mpcd::cuda_q6_backend_runtime_available()) {
            std::cerr << "CUDA_Q6_BACKEND_0186 FAIL no CUDA runtime device available\n";
            return 2;
        }

        const mpcd::EllipticOperatorPlan plan = make_periodic_plan(nx, ny, 1.0, 1.0);
        const std::vector<double> phi = make_test_phi(nx, ny);

        std::vector<double> AphiCpu;
        std::vector<double> AphiCuda;
        const double pApCpu = cpu_apply_plan_and_dot(plan, phi, AphiCpu);
        mpcd::CudaQ6ApplyDiagnostics diag{};
        const double pApCuda = mpcd::cuda_q6_apply_elliptic_operator_plan_and_dot(plan, phi, AphiCuda, &diag);

        double maxAbsDiff = 0.0;
        double maxAbsRef = 0.0;
        double rmsDiff2 = 0.0;
        for (std::size_t k = 0; k < AphiCpu.size(); ++k) {
            const double d = std::abs(AphiCpu[k] - AphiCuda[k]);
            maxAbsDiff = std::max(maxAbsDiff, d);
            maxAbsRef = std::max(maxAbsRef, std::abs(AphiCpu[k]));
            rmsDiff2 += d * d;
        }
        const double rmsDiff = AphiCpu.empty() ? 0.0 : std::sqrt(rmsDiff2 / static_cast<double>(AphiCpu.size()));
        const double relPApDiff = std::abs(pApCpu - pApCuda) / std::max(1.0, std::abs(pApCpu));
        const bool pass = maxAbsDiff <= tolerance * std::max(1.0, maxAbsRef) &&
                          relPApDiff <= 10.0 * tolerance;

        std::cout << std::setprecision(17)
                  << "CUDA_Q6_BACKEND_0186 " << (pass ? "PASS" : "FAIL")
                  << " nx=" << nx
                  << " ny=" << ny
                  << " numCells=" << plan.numCells
                  << " device=" << diag.device
                  << " blocks=" << diag.blocks
                  << " threadsPerBlock=" << diag.threadsPerBlock
                  << " pApCpu=" << pApCpu
                  << " pApCuda=" << pApCuda
                  << " relPApDiff=" << relPApDiff
                  << " maxAbsAphiDiff=" << maxAbsDiff
                  << " rmsAphiDiff=" << rmsDiff
                  << " tolerance=" << tolerance
                  << '\n';
        return pass ? 0 : 1;
    } catch (const std::exception& e) {
        std::cerr << "CUDA_Q6_BACKEND_0186 FAIL exception: " << e.what() << '\n';
        return 3;
    }
}

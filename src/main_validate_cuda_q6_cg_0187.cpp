#include "cuda_q6_backend.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits>
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

double mean(const std::vector<double>& v) {
    if (v.empty()) {
        return 0.0;
    }
    return std::accumulate(v.begin(), v.end(), 0.0) / static_cast<double>(v.size());
}

void subtract_mean(std::vector<double>& v) {
    const double m = mean(v);
    for (double& x : v) {
        x -= m;
    }
}

std::vector<double> make_exact_phi(const int nx, const int ny) {
    constexpr double pi = 3.141592653589793238462643383279502884;
    std::vector<double> phi(static_cast<std::size_t>(nx * ny), 0.0);
    for (int j = 0; j < ny; ++j) {
        for (int i = 0; i < nx; ++i) {
            const double x = static_cast<double>(i) / static_cast<double>(nx);
            const double y = static_cast<double>(j) / static_cast<double>(ny);
            const double small = static_cast<double>((17 * i + 13 * j) % 11) * 1.0e-5;
            phi[static_cast<std::size_t>(cell_index(i, j, nx))] =
                std::sin(2.0 * pi * x) +
                0.25 * std::cos(4.0 * pi * y) +
                0.10 * std::sin(2.0 * pi * (x + y)) +
                small;
        }
    }
    subtract_mean(phi);
    return phi;
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

double dot_product(const std::vector<double>& a, const std::vector<double>& b) {
    if (a.size() != b.size()) {
        throw std::runtime_error("dot_product: size mismatch");
    }
    double s = 0.0;
    for (std::size_t i = 0; i < a.size(); ++i) {
        s += a[i] * b[i];
    }
    return s;
}

bool cpu_cg_solve_plan(const mpcd::EllipticOperatorPlan& plan,
                       const std::vector<double>& rhs,
                       std::vector<double>& phi,
                       const int maxIterations,
                       const double tolerance,
                       int& iterations,
                       double& residualRel) {
    const int nc = plan.numCells;
    phi.assign(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> r = rhs;
    std::vector<double> p = r;
    std::vector<double> Ap(static_cast<std::size_t>(nc), 0.0);
    double rr = dot_product(r, r);
    const double rhsNorm = std::sqrt(std::max(0.0, rr));
    if (rhsNorm <= std::numeric_limits<double>::epsilon()) {
        iterations = 0;
        residualRel = 0.0;
        return true;
    }
    const double absTol = tolerance * rhsNorm;
    iterations = 0;
    residualRel = 1.0;
    for (int it = 0; it < maxIterations; ++it) {
        const double pAp = cpu_apply_plan_and_dot(plan, p, Ap);
        if (!(pAp > 0.0) || !std::isfinite(pAp)) {
            break;
        }
        const double alpha = rr / pAp;
        double rrNew = 0.0;
        for (int c = 0; c < nc; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            phi[k] += alpha * p[k];
            r[k] -= alpha * Ap[k];
            rrNew += r[k] * r[k];
        }
        iterations = it + 1;
        const double residualAbs = std::sqrt(std::max(0.0, rrNew));
        residualRel = residualAbs / rhsNorm;
        if (residualAbs <= absTol) {
            subtract_mean(phi);
            return true;
        }
        const double beta = rrNew / rr;
        for (int c = 0; c < nc; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            p[k] = r[k] + beta * p[k];
        }
        rr = rrNew;
    }
    subtract_mean(phi);
    return false;
}

struct ErrorStats {
    double maxAbs = 0.0;
    double rms = 0.0;
    double relRms = 0.0;
};

ErrorStats compare_vectors(const std::vector<double>& ref, const std::vector<double>& got) {
    if (ref.size() != got.size()) {
        throw std::runtime_error("compare_vectors: size mismatch");
    }
    ErrorStats e{};
    double diff2 = 0.0;
    double ref2 = 0.0;
    for (std::size_t k = 0; k < ref.size(); ++k) {
        const double d = got[k] - ref[k];
        e.maxAbs = std::max(e.maxAbs, std::abs(d));
        diff2 += d * d;
        ref2 += ref[k] * ref[k];
    }
    if (!ref.empty()) {
        e.rms = std::sqrt(diff2 / static_cast<double>(ref.size()));
    }
    e.relRms = std::sqrt(diff2 / std::max(1.0e-300, ref2));
    return e;
}

} // namespace

int main(int argc, char** argv) {
    try {
        const int nx = parse_int_arg(argc, argv, "--nx", 64);
        const int ny = parse_int_arg(argc, argv, "--ny", 48);
        const int maxIterations = parse_int_arg(argc, argv, "--max-it", 1000);
        const double tolerance = parse_double_arg(argc, argv, "--tolerance", 1.0e-11);
        const double phiTolerance = parse_double_arg(argc, argv, "--phi-tolerance", 1.0e-8);

        if (!mpcd::cuda_q6_backend_runtime_available()) {
            std::cerr << "CUDA_Q6_CG_0187 FAIL no CUDA runtime device available\n";
            return 2;
        }

        const mpcd::EllipticOperatorPlan plan = make_periodic_plan(nx, ny, 1.0, 1.0);
        const std::vector<double> phiExact = make_exact_phi(nx, ny);
        std::vector<double> rhs;
        cpu_apply_plan_and_dot(plan, phiExact, rhs);
        subtract_mean(rhs);

        std::vector<double> phiCpu;
        int cpuIterations = 0;
        double cpuResidualRel = 1.0;
        const bool cpuConverged = cpu_cg_solve_plan(plan, rhs, phiCpu, maxIterations, tolerance,
                                                    cpuIterations, cpuResidualRel);

        std::vector<double> phiCuda;
        mpcd::CudaQ6CgParams params{};
        params.maxIterations = maxIterations;
        params.tolerance = tolerance;
        params.removePhiMeanFinal = true;
        mpcd::CudaQ6CgDiagnostics diag{};
        const bool cudaConverged = mpcd::cuda_q6_solve_cg_operator_plan(plan, rhs, phiCuda, params, &diag);

        const ErrorStats exactCpu = compare_vectors(phiExact, phiCpu);
        const ErrorStats exactCuda = compare_vectors(phiExact, phiCuda);
        const ErrorStats cpuCuda = compare_vectors(phiCpu, phiCuda);

        const bool pass = cpuConverged && cudaConverged &&
                          cpuCuda.maxAbs <= phiTolerance &&
                          cpuCuda.relRms <= 10.0 * phiTolerance &&
                          diag.residualRel <= 10.0 * tolerance;

        std::cout << std::setprecision(17)
                  << "CUDA_Q6_CG_0187 " << (pass ? "PASS" : "FAIL")
                  << " nx=" << nx
                  << " ny=" << ny
                  << " numCells=" << plan.numCells
                  << " device=" << diag.device
                  << " blocks=" << diag.blocks
                  << " threadsPerBlock=" << diag.threadsPerBlock
                  << " cpuConverged=" << (cpuConverged ? 1 : 0)
                  << " cudaConverged=" << (cudaConverged ? 1 : 0)
                  << " cpuIterations=" << cpuIterations
                  << " cudaIterations=" << diag.iterations
                  << " cpuResidualRel=" << cpuResidualRel
                  << " cudaResidualRel=" << diag.residualRel
                  << " exactCpuMaxAbs=" << exactCpu.maxAbs
                  << " exactCudaMaxAbs=" << exactCuda.maxAbs
                  << " cpuCudaMaxAbs=" << cpuCuda.maxAbs
                  << " cpuCudaRms=" << cpuCuda.rms
                  << " cpuCudaRelRms=" << cpuCuda.relRms
                  << " tolerance=" << tolerance
                  << " phiTolerance=" << phiTolerance
                  << '\n';
        return pass ? 0 : 1;
    } catch (const std::exception& e) {
        std::cerr << "CUDA_Q6_CG_0187 FAIL exception: " << e.what() << '\n';
        return 3;
    }
}

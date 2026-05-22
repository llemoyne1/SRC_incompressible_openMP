#include "elliptic_projection.h"

#include <cmath>
#include <cstdlib>
#include <exception>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

namespace {

constexpr double pi() { return 3.141592653589793238462643383279502884; }

int parse_int(int argc, char** argv, const std::string& key, int fallback) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (argv[i] == key) return std::atoi(argv[i + 1]);
    }
    return fallback;
}

double parse_double(int argc, char** argv, const std::string& key, double fallback) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (argv[i] == key) return std::atof(argv[i + 1]);
    }
    return fallback;
}

std::string parse_string(int argc, char** argv, const std::string& key, const std::string& fallback) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (argv[i] == key) return argv[i + 1];
    }
    return fallback;
}

bool has_flag(int argc, char** argv, const std::string& key) {
    for (int i = 1; i < argc; ++i) {
        if (argv[i] == key) return true;
    }
    return false;
}

void print_usage(const char* exe) {
    std::cout
        << "Usage: " << exe << " [options]\n"
        << "\n"
        << "Options:\n"
        << "  --Nx N                  grid cells in x (default 64)\n"
        << "  --Ny N                  grid cells in y (default 48)\n"
        << "  --kx K                  manufactured scalar mode in x (default 2)\n"
        << "  --ky K                  manufactured scalar mode in y (default 3)\n"
        << "  --alphaVariation A      periodic face-coefficient modulation, 0<=A<1 (default 0.25)\n"
        << "  --tol T                 CG relative tolerance (default 1e-12)\n"
        << "  --maxIt N               CG maximum iterations (default 2000)\n"
        << "  --csv FILE              write one-line validation CSV\n"
        << "  --help                  print this help\n";
}

double rms_difference_mean_free(const std::vector<double>& a, const std::vector<double>& b) {
    if (a.size() != b.size()) return std::numeric_limits<double>::quiet_NaN();
    const std::size_t n = a.size();
    double meanA = 0.0;
    double meanB = 0.0;
    for (std::size_t i = 0; i < n; ++i) {
        meanA += a[i];
        meanB += b[i];
    }
    meanA /= static_cast<double>(n);
    meanB /= static_cast<double>(n);
    double sum2 = 0.0;
    for (std::size_t i = 0; i < n; ++i) {
        const double d = (a[i] - meanA) - (b[i] - meanB);
        sum2 += d * d;
    }
    return std::sqrt(sum2 / static_cast<double>(n));
}

} // namespace

int main(int argc, char** argv) {
    try {
        if (has_flag(argc, argv, "--help")) {
            print_usage(argv[0]);
            return 0;
        }

        const int Nx = parse_int(argc, argv, "--Nx", 64);
        const int Ny = parse_int(argc, argv, "--Ny", 48);
        const int kx = parse_int(argc, argv, "--kx", 2);
        const int ky = parse_int(argc, argv, "--ky", 3);
        const double alphaVariation = parse_double(argc, argv, "--alphaVariation", 0.25);
        const double tol = parse_double(argc, argv, "--tol", 1.0e-12);
        const int maxIt = parse_int(argc, argv, "--maxIt", 2000);
        const std::string csv = parse_string(argc, argv, "--csv", "");

        if (!(alphaVariation >= 0.0 && alphaVariation < 1.0)) {
            throw std::runtime_error("--alphaVariation must satisfy 0 <= A < 1");
        }

        const mpcd::EllipticProjectionGrid grid = mpcd::make_elliptic_projection_grid(Nx, Ny, 1.0, 1.0);
        mpcd::PeriodicFaceField alpha;
        mpcd::PeriodicFaceField baseFlux;
        mpcd::resize_periodic_face_field(alpha, grid.numCells);
        mpcd::resize_periodic_face_field(baseFlux, grid.numCells);
        std::vector<double> phiTrue(static_cast<std::size_t>(grid.numCells), 0.0);
        std::vector<double> target(static_cast<std::size_t>(grid.numCells), 0.0);

        auto idx = [Nx](int i, int j) { return i + Nx * j; };
        auto wrap = [](int i, int n) {
            if (i < 0) return i + n;
            if (i >= n) return i - n;
            return i;
        };

        for (int j = 0; j < Ny; ++j) {
            for (int i = 0; i < Nx; ++i) {
                const double x = (static_cast<double>(i) + 0.5) / static_cast<double>(Nx);
                const double y = (static_cast<double>(j) + 0.5) / static_cast<double>(Ny);
                phiTrue[static_cast<std::size_t>(idx(i, j))] =
                    std::sin(2.0 * pi() * static_cast<double>(kx) * x) *
                    std::cos(2.0 * pi() * static_cast<double>(ky) * y) +
                    0.35 * std::cos(2.0 * pi() * static_cast<double>(kx + 1) * x +
                                     2.0 * pi() * static_cast<double>(ky - 1) * y);
            }
        }

        for (int j = 0; j < Ny; ++j) {
            const int jp = wrap(j + 1, Ny);
            for (int i = 0; i < Nx; ++i) {
                const int ip = wrap(i + 1, Nx);
                const int c = idx(i, j);
                const int e = idx(ip, j);
                const int n = idx(i, jp);
                const double xFace = (static_cast<double>(i) + 1.0) / static_cast<double>(Nx);
                const double yFace = (static_cast<double>(j) + 1.0) / static_cast<double>(Ny);
                const double xCell = (static_cast<double>(i) + 0.5) / static_cast<double>(Nx);
                const double yCell = (static_cast<double>(j) + 0.5) / static_cast<double>(Ny);
                const std::size_t k = static_cast<std::size_t>(c);

                alpha.x[k] = 1.0 + alphaVariation *
                    std::cos(2.0 * pi() * xFace) * std::cos(2.0 * pi() * yCell);
                alpha.y[k] = 1.0 + alphaVariation *
                    std::sin(2.0 * pi() * xCell) * std::sin(2.0 * pi() * yFace);

                baseFlux.x[k] = alpha.x[k] *
                    (phiTrue[static_cast<std::size_t>(e)] - phiTrue[k]) / grid.dx;
                baseFlux.y[k] = alpha.y[k] *
                    (phiTrue[static_cast<std::size_t>(n)] - phiTrue[k]) / grid.dy;
            }
        }

        mpcd::EllipticProjectionParams params{};
        params.maxIterations = maxIt;
        params.tolerance = tol;
        params.removeRhsMean = true;
        params.removePhiMean = true;

        mpcd::EllipticProjectionWorkspace workspace;
        const mpcd::EllipticProjectionResult result =
            mpcd::project_periodic_face_field(grid, baseFlux, alpha, target, params, workspace);

        const double phiError = rms_difference_mean_free(result.phi, phiTrue);
        const double reduction = result.diagnostics.divBeforeRms > 0.0
            ? result.diagnostics.divAfterRms / result.diagnostics.divBeforeRms
            : 0.0;

        std::cout << std::setprecision(12)
                  << "=== periodic elliptic projection manufactured validation ===\n"
                  << "grid                         : " << Nx << " x " << Ny << "\n"
                  << "alphaVariation               : " << alphaVariation << "\n"
                  << "converged                    : " << (result.diagnostics.converged ? "true" : "false") << "\n"
                  << "iterations                   : " << result.diagnostics.iterations << "\n"
                  << "residualRel                  : " << result.diagnostics.residualRel << "\n"
                  << "rhsMeanBeforeGauge           : " << result.diagnostics.rhsMeanBeforeGauge << "\n"
                  << "rhsMeanAfterGauge            : " << result.diagnostics.rhsMeanAfterGauge << "\n"
                  << "divBeforeRms                 : " << result.diagnostics.divBeforeRms << "\n"
                  << "divAfterRms                  : " << result.diagnostics.divAfterRms << "\n"
                  << "divAfter/divBefore           : " << reduction << "\n"
                  << "projectedFluxRms             : " << result.diagnostics.projectedFluxRms << "\n"
                  << "phiRmsErrorMeanFree          : " << phiError << "\n";

        if (!csv.empty()) {
            std::ofstream out(csv);
            if (!out) throw std::runtime_error("Cannot write CSV: " + csv);
            out << "Nx,Ny,kx,ky,alphaVariation,converged,iterations,residualRel,rhsMeanBeforeGauge,rhsMeanAfterGauge,divBeforeRms,divAfterRms,reduction,projectedFluxRms,phiRmsErrorMeanFree\n";
            out << Nx << ',' << Ny << ',' << kx << ',' << ky << ',' << std::setprecision(17)
                << alphaVariation << ',' << (result.diagnostics.converged ? 1 : 0) << ','
                << result.diagnostics.iterations << ',' << result.diagnostics.residualRel << ','
                << result.diagnostics.rhsMeanBeforeGauge << ',' << result.diagnostics.rhsMeanAfterGauge << ','
                << result.diagnostics.divBeforeRms << ',' << result.diagnostics.divAfterRms << ','
                << reduction << ',' << result.diagnostics.projectedFluxRms << ',' << phiError << '\n';
        }

        const bool ok = result.diagnostics.converged &&
                        result.diagnostics.residualRel < 1.0e-9 &&
                        reduction < 1.0e-8 &&
                        result.diagnostics.projectedFluxRms < 1.0e-8 &&
                        phiError < 1.0e-8;
        return ok ? 0 : 2;
    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << "\n";
        return 1;
    }
}

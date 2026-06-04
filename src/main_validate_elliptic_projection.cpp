#include "elliptic_projection.h"

#include <cmath>
#include <cstdlib>
#include <exception>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <stdexcept>
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
        << "  --bc periodic|channel   elliptic BC validation case (default periodic)\n"
        << "                           periodic: periodic x and y\n"
        << "                           channel : periodic x, no-normal-flux walls in y\n"
        << "  --alphaVariation A      face-coefficient modulation, 0<=A<1 (default 0.25)\n"
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

bool is_periodic(mpcd::EllipticBoundaryType bc) {
    return bc == mpcd::EllipticBoundaryType::Periodic;
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
        const std::string bcName = parse_string(argc, argv, "--bc", "periodic");
        const double alphaVariation = parse_double(argc, argv, "--alphaVariation", 0.25);
        const double tol = parse_double(argc, argv, "--tol", 1.0e-12);
        const int maxIt = parse_int(argc, argv, "--maxIt", 2000);
        const std::string csv = parse_string(argc, argv, "--csv", "");

        if (!(alphaVariation >= 0.0 && alphaVariation < 1.0)) {
            throw std::runtime_error("--alphaVariation must satisfy 0 <= A < 1");
        }

        mpcd::EllipticProjectionBC bc{};
        if (bcName == "periodic") {
            bc.x = mpcd::EllipticBoundaryType::Periodic;
            bc.y = mpcd::EllipticBoundaryType::Periodic;
        } else if (bcName == "channel") {
            bc.x = mpcd::EllipticBoundaryType::Periodic;
            bc.y = mpcd::EllipticBoundaryType::WallNoNormalFlux;
        } else {
            throw std::runtime_error("Unknown --bc value: " + bcName);
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
                if (bcName == "channel") {
                    // Compatible with no-normal-flux walls: dphi/dy = 0 at y=0,1.
                    phiTrue[static_cast<std::size_t>(idx(i, j))] =
                        std::sin(2.0 * pi() * static_cast<double>(kx) * x) *
                        std::cos(pi() * static_cast<double>(ky) * y) +
                        0.35 * std::cos(2.0 * pi() * static_cast<double>(kx + 1) * x) *
                        std::cos(pi() * static_cast<double>(ky + 1) * y);
                } else {
                    phiTrue[static_cast<std::size_t>(idx(i, j))] =
                        std::sin(2.0 * pi() * static_cast<double>(kx) * x) *
                        std::cos(2.0 * pi() * static_cast<double>(ky) * y) +
                        0.35 * std::cos(2.0 * pi() * static_cast<double>(kx + 1) * x +
                                         2.0 * pi() * static_cast<double>(ky - 1) * y);
                }
            }
        }

        const bool periodicX = is_periodic(bc.x);
        const bool periodicY = is_periodic(bc.y);
        for (int j = 0; j < Ny; ++j) {
            for (int i = 0; i < Nx; ++i) {
                const int c = idx(i, j);
                const double xFace = (static_cast<double>(i) + 1.0) / static_cast<double>(Nx);
                const double yFace = (static_cast<double>(j) + 1.0) / static_cast<double>(Ny);
                const double xCell = (static_cast<double>(i) + 0.5) / static_cast<double>(Nx);
                const double yCell = (static_cast<double>(j) + 0.5) / static_cast<double>(Ny);
                const std::size_t k = static_cast<std::size_t>(c);

                alpha.x[k] = 1.0 + alphaVariation *
                    std::cos(2.0 * pi() * xFace) * std::cos(2.0 * pi() * yCell);
                alpha.y[k] = 1.0 + alphaVariation *
                    std::sin(2.0 * pi() * xCell) * std::sin(2.0 * pi() * yFace);

                if (periodicX || i < Nx - 1) {
                    const int ip = periodicX ? wrap(i + 1, Nx) : (i + 1);
                    const int e = idx(ip, j);
                    baseFlux.x[k] = alpha.x[k] *
                        (phiTrue[static_cast<std::size_t>(e)] - phiTrue[k]) / grid.dx;
                } else {
                    baseFlux.x[k] = 0.0;
                }

                if (periodicY || j < Ny - 1) {
                    const int jp = periodicY ? wrap(j + 1, Ny) : (j + 1);
                    const int n = idx(i, jp);
                    baseFlux.y[k] = alpha.y[k] *
                        (phiTrue[static_cast<std::size_t>(n)] - phiTrue[k]) / grid.dy;
                } else {
                    baseFlux.y[k] = 0.0;
                }
            }
        }

        mpcd::EllipticProjectionParams params{};
        params.maxIterations = maxIt;
        params.tolerance = tol;
        params.removeRhsMean = true;
        params.removePhiMean = true;

        mpcd::EllipticProjectionWorkspace workspace;
        const mpcd::EllipticProjectionResult result =
            mpcd::project_face_field(grid, baseFlux, alpha, target, params, bc, workspace);

        const double phiError = rms_difference_mean_free(result.phi, phiTrue);
        const double reduction = result.diagnostics.divBeforeRms > 0.0
            ? result.diagnostics.divAfterRms / result.diagnostics.divBeforeRms
            : 0.0;

        std::cout << std::setprecision(12)
                  << "=== elliptic projection manufactured validation ===\n"
                  << "bc                           : " << bcName << "\n"
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
            out << "bc,Nx,Ny,kx,ky,alphaVariation,converged,iterations,residualRel,rhsMeanBeforeGauge,rhsMeanAfterGauge,divBeforeRms,divAfterRms,reduction,projectedFluxRms,phiRmsErrorMeanFree\n";
            out << bcName << ',' << Nx << ',' << Ny << ',' << kx << ',' << ky << ',' << std::setprecision(17)
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

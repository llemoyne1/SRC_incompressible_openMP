#pragma once

#include <cstdint>
#include <vector>

namespace mpcd {

// Generic finite-volume face-field projection core.
//
// Conventions for a periodic Nx x Ny cell grid:
//   - scalar fields are cell-centered, length Nx*Ny;
//   - face fields have one x-face and one y-face per cell, also length Nx*Ny;
//   - x[c] is the east face of cell (i,j), positive in +x;
//   - y[c] is the north face of cell (i,j), positive in +y;
//   - divergence(F) = (Fx_E - Fx_W)/dx + (Fy_N - Fy_S)/dy.
//
// The projection solves, on the mean-zero compatible periodic subspace,
//
//   A phi = targetDivergence - div(baseFlux),
//   A      = -div(alpha grad),
//
// then returns
//
//   correctionFlux = -alpha grad(phi),
//   projectedFlux  = baseFlux + correctionFlux.
//
// This core is deliberately independent of Q6/Q9/particle data. Q6 can pass a
// velocity face field, Q9 can pass a mass-flux face field, and future surface
// tension modules can reuse the same discrete div/grad/operator machinery.

struct EllipticProjectionGrid {
    int Nx = 0;
    int Ny = 0;
    int numCells = 0;
    double Lx = 1.0;
    double Ly = 1.0;
    double dx = 1.0;
    double dy = 1.0;
};

struct PeriodicFaceField {
    std::vector<double> x;
    std::vector<double> y;
};

// Boundary policy for the generic elliptic face-field core.
//
// Periodic keeps the original wrap-around topology. WallNoNormalFlux closes the
// corresponding direction with homogeneous normal flux at the low and high
// boundaries. With the compact face storage used here, the high boundary face is
// stored in the last cell of the direction and the low boundary face is implicit.
// This is sufficient for the periodic-x / wall-y channel operator and keeps the
// data layout identical for Q6, Q9 and future surface-tension adapters.
enum class EllipticBoundaryType {
    Periodic,
    WallNoNormalFlux
};

struct EllipticProjectionBC {
    EllipticBoundaryType x = EllipticBoundaryType::Periodic;
    EllipticBoundaryType y = EllipticBoundaryType::Periodic;

    // Prescribed normal fluxes on non-periodic domain boundaries. These are
    // zero for fixed solid walls. For moving active-domain walls they are the
    // wall normal velocity for Q6, or the corresponding mass flux for Q9.
    // The compact face storage keeps high-boundary faces explicitly in the
    // last cell row/column; low-boundary faces are implicit in divergence.
    double xLowFlux = 0.0;
    double xHighFlux = 0.0;
    double yLowFlux = 0.0;
    double yHighFlux = 0.0;
};

struct EllipticProjectionParams {
    int maxIterations = 500;
    double tolerance = 1.0e-12;
    bool removeRhsMean = true;
    bool removePhiMean = true;
};

struct EllipticProjectionDiagnostics {
    bool converged = false;
    int iterations = 0;
    double rhsMeanBeforeGauge = 0.0;
    double rhsMeanAfterGauge = 0.0;
    double rhsRms = 0.0;
    double rhsMaxAbs = 0.0;
    double residualAbs = 0.0;
    double residualRel = 0.0;
    double divBeforeRms = 0.0;
    double divBeforeMaxAbs = 0.0;
    double targetDivergenceRms = 0.0;
    double divAfterRms = 0.0;
    double divAfterMaxAbs = 0.0;
    double correctionFluxRms = 0.0;
    double correctionFluxMaxAbs = 0.0;
    double projectedFluxRms = 0.0;
    double projectedFluxMaxAbs = 0.0;
};

struct EllipticProjectionResult {
    std::vector<double> phi;
    PeriodicFaceField correctionFlux;
    PeriodicFaceField projectedFlux;
    std::vector<double> divBefore;
    std::vector<double> divAfter;
    EllipticProjectionDiagnostics diagnostics;
};


struct EllipticLowPassParams {
    int passes = 1;
    double length = 0.0;
    int maxIterations = 500;
    double tolerance = 1.0e-12;
    bool removeMeanEachPass = true;
};

struct EllipticLowPassDiagnostics {
    bool applied = false;
    bool converged = false;
    int passes = 0;
    int lastIterations = 0;
    double inputRms = 0.0;
    double outputRms = 0.0;
    double filterRatio = 1.0;
    double lastResidualRel = 0.0;
};

struct EllipticProjectionWorkspace {
    std::vector<double> rhs;
    std::vector<double> r;
    std::vector<double> p;
    std::vector<double> Ap;
};

EllipticProjectionGrid make_elliptic_projection_grid(int Nx, int Ny, double Lx, double Ly);

void resize_periodic_face_field(PeriodicFaceField& f, int numCells);
void resize_elliptic_projection_workspace(EllipticProjectionWorkspace& workspace, int numCells);

std::vector<double> compute_face_divergence(const EllipticProjectionGrid& grid,
                                            const PeriodicFaceField& flux,
                                            const EllipticProjectionBC& bc);

std::vector<double> compute_periodic_face_divergence(const EllipticProjectionGrid& grid,
                                                     const PeriodicFaceField& flux);

void apply_elliptic_operator(const EllipticProjectionGrid& grid,
                             const PeriodicFaceField& alpha,
                             const std::vector<double>& phi,
                             std::vector<double>& Aphi,
                             const EllipticProjectionBC& bc);

void apply_periodic_elliptic_operator(const EllipticProjectionGrid& grid,
                                      const PeriodicFaceField& alpha,
                                      const std::vector<double>& phi,
                                      std::vector<double>& Aphi);

EllipticProjectionResult project_face_field(const EllipticProjectionGrid& grid,
                                                const PeriodicFaceField& baseFlux,
                                                const PeriodicFaceField& alpha,
                                                const std::vector<double>& targetDivergence,
                                                const EllipticProjectionParams& params,
                                                const EllipticProjectionBC& bc,
                                                EllipticProjectionWorkspace& workspace);

EllipticProjectionResult project_periodic_face_field(const EllipticProjectionGrid& grid,
                                                     const PeriodicFaceField& baseFlux,
                                                     const PeriodicFaceField& alpha,
                                                     const std::vector<double>& targetDivergence,
                                                     const EllipticProjectionParams& params,
                                                     EllipticProjectionWorkspace& workspace);

// Generic elliptic/Helmholtz low-pass filter for cell-centered fields:
//
//   (I + length^2 A) f_filtered = f_input,
//   A = -div(alpha grad).
//
// This uses the same finite-volume div/grad/operator and boundary policy as the
// face-field projection core. It is intended for Q9 density-target filtering and
// future interface/surface-tension smoothing without adding a separate operator.
std::vector<double> elliptic_lowpass_cell_field(const EllipticProjectionGrid& grid,
                                                const std::vector<double>& input,
                                                const PeriodicFaceField& alpha,
                                                const EllipticLowPassParams& params,
                                                const EllipticProjectionBC& bc,
                                                EllipticProjectionWorkspace& workspace,
                                                EllipticLowPassDiagnostics* diagnostics = nullptr);

} // namespace mpcd

#pragma once

#include "elliptic_projection.h"

#include <vector>

namespace mpcd {

// Patch 0186/0187: CUDA-only numerical seed for the future Q6/elliptic backend.
//
// The full Q6 projection path still uses the validated CPU/OpenMP implementation
// unless a later patch explicitly wires the CUDA CG path into project_face_field().
// 0186 exposed the atomic primitive Ap=A*p and <p,Ap>. 0187 adds a standalone
// device-resident CG solver on an already-built EllipticOperatorPlan so that the
// complete iteration algebra can be validated before simulation coupling.
struct CudaQ6ApplyDiagnostics {
    bool usedCuda = false;
    int device = -1;
    int numCells = 0;
    int activeCells = 0;
    int inactiveCells = 0;
    int blocks = 0;
    int threadsPerBlock = 0;
    double pAp = 0.0;
};

struct CudaQ6CgParams {
    int maxIterations = 500;
    double tolerance = 1.0e-12;
    bool removePhiMeanFinal = true;

    // Keep the integrated CUDA CG close to the CPU CG: the CPU path removes
    // the active-cell mean from phi and r every 25 iterations, then again from
    // phi at the end.  A non-positive value disables periodic removal.
    int meanRemovalPeriod = 25;
};

struct CudaQ6CgDiagnostics {
    bool usedCuda = false;
    bool converged = false;
    int device = -1;
    int numCells = 0;
    int activeCells = 0;
    int inactiveCells = 0;
    int iterations = 0;
    int blocks = 0;
    int threadsPerBlock = 0;
    double rhsNorm = 0.0;
    double residualAbs = 0.0;
    double residualRel = 0.0;
    double lastPAp = 0.0;
};

bool cuda_q6_backend_runtime_available();

double cuda_q6_apply_elliptic_operator_plan_and_dot(
    const EllipticOperatorPlan& plan,
    const std::vector<double>& phi,
    std::vector<double>& Aphi,
    CudaQ6ApplyDiagnostics* diagnostics = nullptr);

bool cuda_q6_solve_cg_operator_plan(
    const EllipticOperatorPlan& plan,
    const std::vector<double>& rhs,
    std::vector<double>& phi,
    const CudaQ6CgParams& params,
    CudaQ6CgDiagnostics* diagnostics = nullptr);

} // namespace mpcd

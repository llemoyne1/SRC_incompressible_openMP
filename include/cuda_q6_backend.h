#pragma once

#include "elliptic_projection.h"

#include <vector>

namespace mpcd {

// Patch 0186: CUDA-only numerical seed for the future Q6/elliptic backend.
//
// This header deliberately exposes only a small, testable primitive.  The full
// Q6 projection path still uses the validated CPU/OpenMP implementation unless
// a later patch explicitly wires the CUDA CG path into project_face_field().
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

bool cuda_q6_backend_runtime_available();

double cuda_q6_apply_elliptic_operator_plan_and_dot(
    const EllipticOperatorPlan& plan,
    const std::vector<double>& phi,
    std::vector<double>& Aphi,
    CudaQ6ApplyDiagnostics* diagnostics = nullptr);

} // namespace mpcd

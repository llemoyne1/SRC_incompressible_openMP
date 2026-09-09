#!/usr/bin/env python3
from pathlib import Path
import re

TARGET = Path("src/cuda_q6_resident_0400.cu")
MARKER = "q6_apply_full_domain_periodic_rt0_0493x7q"

if not TARGET.is_file():
    raise SystemExit(f"ERROR: missing {TARGET}")

text = TARGET.read_text()
if MARKER in text:
    raise SystemExit("ERROR: 0493x7q already appears to be applied")
original = text

# 1) Extend the existing O(1) accumulator without depending on comments/line numbers.
pat = re.compile(
    r"(struct\s+Q6PeriodicMomentumAccumulator0493x7dv2fix2\s*\{)(.*?)(\n\};)",
    re.S,
)
matches = list(pat.finditer(text))
if len(matches) != 1:
    raise SystemExit(
        "ERROR: expected exactly one Q6PeriodicMomentumAccumulator0493x7dv2fix2 "
        f"definition, found {len(matches)}"
    )
m = matches[0]
body = m.group(2)
for required in ("double activeMass", "double momentumX", "double momentumY"):
    if required not in body:
        raise SystemExit(f"ERROR: x7q accumulator anchor missing: {required}")
body2, n = re.subn(
    r"(\n\s*double\s+momentumY\s*=\s*0\.0\s*;)",
    r"\1\n    // 0493x7q: exact particle-level residual closure, full-domain periodic B1 only.\n"
    r"    double appliedMass0493x7q = 0.0;\n"
    r"    double residualVelocityX0493x7q = 0.0;\n"
    r"    double residualVelocityY0493x7q = 0.0;",
    body,
    count=1,
)
if n != 1:
    raise SystemExit("ERROR: could not extend x7d-v2 periodic momentum accumulator")
text = text[:m.start()] + m.group(1) + body2 + m.group(3) + text[m.end():]

# 2) Add separate full-domain-periodic kernels; historical B1 kernel stays untouched.
KERNELS = '// 0493x7q: full-domain periodic specialization of B1.  Keep the historical\n// q6_apply_free_surface_force_and_rt0_correction_0493x6h_b1 kernel untouched\n// so partial-domain free-surface/dam-break runs retain exactly their qualified\n// GPU kernel.  This specialization additionally reduces the mass and the raw\n// RT0 correction actually sampled at particle locations.\n__global__ void q6_apply_full_domain_periodic_rt0_0493x7q(\n    CudaParticleDeviceView particles,\n    CudaCellWorkspaceDeviceView cells,\n    const unsigned char* mask,\n    const double* cellDUx,\n    const double* cellDUy,\n    const double* faceDUxEast,\n    const double* faceDUyNorth,\n    std::uint32_t projectedType,\n    std::uint64_t nParticles,\n    int nx,\n    int ny,\n    double lx,\n    double ly,\n    int periodicX,\n    int periodicY,\n    double dt,\n    double bodyAx,\n    double bodyAy,\n    int tgEnable,\n    double tgAmplitude,\n    int tgModeX,\n    int tgModeY,\n    double* partialPx,\n    double* partialPy,\n    double* partialMass,\n    unsigned long long* correctedCounter,\n    const Q6PeriodicMomentumAccumulator0493x7dv2fix2* periodicMomentumAccum,\n    int collectDiagnostics0493x7k) {\n    extern __shared__ double sh[];\n    double* shX = sh;\n    double* shY = sh + blockDim.x;\n    double* shM = shY + blockDim.x;\n    const int tid = threadIdx.x;\n    double px = 0.0;\n    double py = 0.0;\n    double pm = 0.0;\n    unsigned long long correctedLocal = 0ull;\n\n    double periodicCvx = 0.0;\n    double periodicCvy = 0.0;\n    if (periodicMomentumAccum != nullptr && periodicMomentumAccum->activeMass > 0.0) {\n        const double invMass = 1.0 / periodicMomentumAccum->activeMass;\n        if (periodicX) periodicCvx = periodicMomentumAccum->momentumX * invMass;\n        if (periodicY) periodicCvy = periodicMomentumAccum->momentumY * invMass;\n    }\n\n    const double invDx = static_cast<double>(nx) / lx;\n    const double invDy = static_cast<double>(ny) / ly;\n    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;\n    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;\n    for (std::uint64_t i = idx; i < nParticles; i += stride) {\n        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) continue;\n\n        double ax = 0.0;\n        double ay = 0.0;\n        q6_force_acceleration_0493x4b(\n            particles.x[i], particles.y[i], lx, ly, bodyAx, bodyAy,\n            tgEnable, tgAmplitude, tgModeX, tgModeY, &ax, &ay);\n        particles.vx[i] += ax * dt;\n        particles.vy[i] += ay * dt;\n\n        if (particles.type == nullptr || particles.type[i] != projectedType) continue;\n        const int c = cells.cellId[i];\n        if (c < 0 || c >= cells.numCells || mask[c] == 0u) continue;\n\n        const int ix = c % nx;\n        const int iy = c / nx;\n        double x = particles.x[i];\n        double y = particles.y[i];\n        if (periodicX) {\n            x -= floor(x / lx) * lx;\n        } else {\n            x = fmin(fmax(x, 0.0), nextafter(lx, 0.0));\n        }\n        if (periodicY) {\n            y -= floor(y / ly) * ly;\n        } else {\n            y = fmin(fmax(y, 0.0), nextafter(ly, 0.0));\n        }\n        const double xi = fmin(fmax(x * invDx - static_cast<double>(ix), 0.0), 1.0);\n        const double eta = fmin(fmax(y * invDy - static_cast<double>(iy), 0.0), 1.0);\n\n        const double cx = cellDUx[c];\n        const double cy = cellDUy[c];\n        const double dUe = faceDUxEast[c];\n        const double dVn = faceDUyNorth[c];\n        const double dvx = cx + (2.0 * xi - 1.0) * (dUe - cx);\n        const double dvy = cy + (2.0 * eta - 1.0) * (dVn - cy);\n        particles.vx[i] += dvx - periodicCvx;\n        particles.vy[i] += dvy - periodicCvy;\n\n        const double m = particles.mass ? particles.mass[i] : 1.0;\n        // Raw RT0 momentum only: do not include the physical force or the\n        // x7d-v2 uniform pre-closure.  This lets x7q compute the exact residual.\n        px += m * dvx;\n        py += m * dvy;\n        pm += m;\n        if (collectDiagnostics0493x7k) ++correctedLocal;\n    }\n\n    if (collectDiagnostics0493x7k && correctedLocal != 0ull) {\n        atomicAdd(correctedCounter, correctedLocal);\n    }\n    shX[tid] = px;\n    shY[tid] = py;\n    shM[tid] = pm;\n    __syncthreads();\n    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {\n        if (tid < offset) {\n            shX[tid] += shX[tid + offset];\n            shY[tid] += shY[tid + offset];\n            shM[tid] += shM[tid + offset];\n        }\n        __syncthreads();\n    }\n    if (tid == 0) {\n        partialPx[blockIdx.x] = shX[0];\n        partialPy[blockIdx.x] = shY[0];\n        partialMass[blockIdx.x] = shM[0];\n    }\n}\n\n// Collapse the per-block particle reduction on device.  The first B1 pass has\n// already removed the cell-centred x7d-v2 estimate.  Store only the remaining\n// uniform velocity required to make the applied Q6 correction exactly momentum\n// neutral in each periodic direction.\n__global__ void q6_finalize_exact_periodic_b1_closure_0493x7q(\n    const double* partialPx,\n    const double* partialPy,\n    const double* partialMass,\n    int blocks,\n    Q6PeriodicMomentumAccumulator0493x7dv2fix2* accum,\n    int correctX,\n    int correctY) {\n    extern __shared__ double sh[];\n    double* shX = sh;\n    double* shY = sh + blockDim.x;\n    double* shM = shY + blockDim.x;\n    const int tid = threadIdx.x;\n    double sx = 0.0;\n    double sy = 0.0;\n    double sm = 0.0;\n    for (int b = tid; b < blocks; b += blockDim.x) {\n        sx += partialPx[b];\n        sy += partialPy[b];\n        sm += partialMass[b];\n    }\n    shX[tid] = sx;\n    shY[tid] = sy;\n    shM[tid] = sm;\n    __syncthreads();\n    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {\n        if (tid < offset) {\n            shX[tid] += shX[tid + offset];\n            shY[tid] += shY[tid + offset];\n            shM[tid] += shM[tid + offset];\n        }\n        __syncthreads();\n    }\n    if (tid == 0) {\n        accum->appliedMass0493x7q = shM[0];\n        accum->residualVelocityX0493x7q = 0.0;\n        accum->residualVelocityY0493x7q = 0.0;\n        if (shM[0] > 0.0 && isfinite(shM[0])) {\n            const double preCvx = accum->activeMass > 0.0\n                ? accum->momentumX / accum->activeMass : 0.0;\n            const double preCvy = accum->activeMass > 0.0\n                ? accum->momentumY / accum->activeMass : 0.0;\n            if (correctX) accum->residualVelocityX0493x7q = shX[0] / shM[0] - preCvx;\n            if (correctY) accum->residualVelocityY0493x7q = shY[0] / shM[0] - preCvy;\n        }\n    }\n}\n\n// Second resident particle pass.  It is never launched for partial-domain\n// free-surface runs, so dam-break keeps the exact pre-x7q GPU path and cost.\n__global__ void q6_apply_exact_periodic_b1_closure_0493x7q(\n    CudaParticleDeviceView particles,\n    CudaCellWorkspaceDeviceView cells,\n    const unsigned char* mask,\n    std::uint32_t projectedType,\n    std::uint64_t nParticles,\n    const Q6PeriodicMomentumAccumulator0493x7dv2fix2* accum,\n    int correctX,\n    int correctY) {\n    const double cvx = correctX ? accum->residualVelocityX0493x7q : 0.0;\n    const double cvy = correctY ? accum->residualVelocityY0493x7q : 0.0;\n    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;\n    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;\n    for (std::uint64_t i = idx; i < nParticles; i += stride) {\n        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) continue;\n        if (particles.type == nullptr || particles.type[i] != projectedType) continue;\n        const int c = cells.cellId[i];\n        if (c < 0 || c >= cells.numCells || mask[c] == 0u) continue;\n        if (correctX) particles.vx[i] -= cvx;\n        if (correctY) particles.vy[i] -= cvy;\n    }\n}\n\n'
anchor = "__global__ void q6_apply_free_surface_force_and_correction_0493x5a("
if text.count(anchor) != 1:
    raise SystemExit(
        "ERROR: expected exactly one x5a kernel anchor after B1, found "
        f"{text.count(anchor)}"
    )
text = text.replace(anchor, KERNELS + anchor, 1)

# 3) Wrap the unique host B1 launch and preserve its local body verbatim in else.
outer = "        if (faceToParticleRt00493x6hB1) {"
next_branch = "        } else if (freeSurfaceMode0493x5a && fuseForceKick0493x4b) {"
if text.count(outer) != 1:
    raise SystemExit(
        "ERROR: expected exactly one host B1 apply branch, found "
        f"{text.count(outer)}"
    )
start = text.index(outer)
end = text.find(next_branch, start)
if end < 0:
    raise SystemExit("ERROR: could not locate end of host B1 apply branch")
line_end = text.index("\n", start) + 1
historical_body = text[line_end:end]
if "q6_apply_free_surface_force_and_rt0_correction_0493x6h_b1<<<" not in historical_body:
    raise SystemExit("ERROR: host B1 branch does not contain the qualified B1 launch")
indented_historical = "".join(
    ("    " + line if line.strip() else line)
    for line in historical_body.splitlines(keepends=True)
)
SPECIAL = '            if (periodicProjectedMomentumCorrection0493x7dv2fix2) {\n                // 0493x7q: exact particle-level k=0 closure only for the\n                // monophase full-domain B1 path.  Partial-domain free-surface\n                // runs, including dam-break, execute the historical branch below.\n                q6_apply_full_domain_periodic_rt0_0493x7q<<<\n                    particleBlocks, threads, tripleShared>>>(\n                    particles, cells, denseMask, denseDUx, denseDUy,\n                    ws.r.data(), ws.p.data(), audit.type, nParticles,\n                    grid.Nx, grid.Ny, params.Lx, params.Ly, periodicX, periodicY,\n                    params.dt, params.bodyAccelerationX, params.bodyAccelerationY,\n                    tgForceActive0493x5a ? 1 : 0,\n                    params.taylorGreenForcingAmplitude,\n                    params.taylorGreenForcingModeX, params.taylorGreenForcingModeY,\n                    ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),\n                    ws.counter.data(), ws.periodicMomentumAccum0493x7dv2fix2.data(),\n                    q6GfDiagnosticsThisStep0493x7k ? 1 : 0);\n                check_cuda_0400(cudaGetLastError(),\n                                "0493x7q full-domain periodic RT0 apply launch");\n\n                q6_finalize_exact_periodic_b1_closure_0493x7q<<<\n                    1, threads, tripleShared>>>(\n                    ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),\n                    particleBlocks, ws.periodicMomentumAccum0493x7dv2fix2.data(),\n                    periodicX ? 1 : 0, periodicY ? 1 : 0);\n                check_cuda_0400(cudaGetLastError(),\n                                "0493x7q exact periodic B1 reduction launch");\n\n                q6_apply_exact_periodic_b1_closure_0493x7q<<<\n                    particleBlocks, threads>>>(\n                    particles, cells, denseMask, audit.type, nParticles,\n                    ws.periodicMomentumAccum0493x7dv2fix2.data(),\n                    periodicX ? 1 : 0, periodicY ? 1 : 0);\n                check_cuda_0400(cudaGetLastError(),\n                                "0493x7q exact periodic B1 closure launch");\n            } else {\n'
replacement = outer + "\n" + SPECIAL + indented_historical + "            }\n"
text = text[:start] + replacement + text[end:]

# 4) Diagnostics report the complete x7d-v2 + x7q uniform velocity removed.
rx = re.compile(
    r"diag\.momentumCorrectionVx\s*=\s*\n\s*"
    r"periodicMomentumAudit0493x7dv2fix2\.momentumX\s*/\s*\n\s*"
    r"periodicMomentumAudit0493x7dv2fix2\.activeMass\s*;"
)
ry = re.compile(
    r"diag\.momentumCorrectionVy\s*=\s*\n\s*"
    r"periodicMomentumAudit0493x7dv2fix2\.momentumY\s*/\s*\n\s*"
    r"periodicMomentumAudit0493x7dv2fix2\.activeMass\s*;"
)
text, nx = rx.subn(
    "diag.momentumCorrectionVx =\n"
    "                    periodicMomentumAudit0493x7dv2fix2.momentumX /\n"
    "                    periodicMomentumAudit0493x7dv2fix2.activeMass +\n"
    "                    periodicMomentumAudit0493x7dv2fix2.residualVelocityX0493x7q;",
    text,
    count=1,
)
text, ny = ry.subn(
    "diag.momentumCorrectionVy =\n"
    "                    periodicMomentumAudit0493x7dv2fix2.momentumY /\n"
    "                    periodicMomentumAudit0493x7dv2fix2.activeMass +\n"
    "                    periodicMomentumAudit0493x7dv2fix2.residualVelocityY0493x7q;",
    text,
    count=1,
)
if nx != 1 or ny != 1:
    raise SystemExit(
        "ERROR: could not update x7q momentum diagnostics "
        f"(x matches={nx}, y matches={ny}); source was not written"
    )

checks = {
    "x7q specialized B1 kernel": text.count("__global__ void q6_apply_full_domain_periodic_rt0_0493x7q(") == 1,
    "x7q reduction kernel": text.count("__global__ void q6_finalize_exact_periodic_b1_closure_0493x7q(") == 1,
    "x7q closure kernel": text.count("__global__ void q6_apply_exact_periodic_b1_closure_0493x7q(") == 1,
    "historical B1 kernel retained": text.count("__global__ void q6_apply_free_surface_force_and_rt0_correction_0493x6h_b1(") == 1,
    "historical host B1 launch retained": text.count("q6_apply_free_surface_force_and_rt0_correction_0493x6h_b1<<<") == 1,
    "full-domain gate retained": "faceToParticleRt00493x6hB1 && audit.fullDomain" in text,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("ERROR: x7q invariant check failed: " + ", ".join(failed))
if text == original:
    raise SystemExit("ERROR: no source change produced")

TARGET.write_text(text)
print("PASS: applied 0493x7q exact particle-level periodic B1 momentum closure")
print("      scope: B1 && fullDomain && periodic direction(s)")
print("      partial-domain/dam-break historical B1 launch retained unchanged")
print(f"modified: {TARGET}")

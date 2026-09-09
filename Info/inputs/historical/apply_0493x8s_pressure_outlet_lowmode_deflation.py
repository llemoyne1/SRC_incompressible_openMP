#!/usr/bin/env python3
'''
0493x8s — exact low-mode deflation for the x8r full-height pressure outlet.

x8r fixes the Neumann outlet physics, but the resulting mixed
Neumann/Dirichlet Poisson operator is much more weakly conditioned in a long
channel. On 1200x400, both x7j resident CG and the host fallback reach the
identical residual 1.085e-5 after 2500 iterations, just above tol=1e-5.

For a full-domain rectangular grid with non-periodic x, pressure-Neumann on the
left, and x8r phi=0 on the complete right face, the three slowest longitudinal
pressure modes are known exactly:

  e_m(ix) = cos(theta_m*(ix+1/2))
  theta_m = (m+1/2)*pi/Nx, m=0,1,2
  lambda_m = 4*sin^2(theta_m/2)/dx^2
  ||e_m||^2 = Nx*Ny/2

x8s solves those three components analytically at CG initialization and starts
CG on the exactly orthogonal residual. This does not change the equation,
tolerance, outlet physics, or projection strength.

Activation is deliberately narrow:
  fullDomain && !periodicX && x8r pressure outlet covers the full right face.

Both Q6GF CG implementations are covered:
  - x7j cooperative resident CG
  - host-driven fallback CG

No new parameter. No clean-tree guard.
'''

from pathlib import Path

ROOT = Path.cwd()
CU = ROOT / "src/cuda_q6_resident_0400.cu"
TAG = "0493x8s"
MARKER = "0493x8s exact pressure-outlet low-mode deflation"

if not CU.is_file():
    raise SystemExit(f"[{TAG}] missing {CU}")

def once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"[{TAG}] {label}: expected one anchor, found {n}")
    return text.replace(old, new, 1)

cu = CU.read_text(encoding="utf-8")

if MARKER in cu:
    raise SystemExit(f"[{TAG}] already applied")
if "0493x8r passive pressure outlet" not in cu:
    raise SystemExit(f"[{TAG}] x8r marker not found; apply x8r first")

# Host activation helper.
anchor = '''bool q6_has_passive_pressure_outlet_right_0493x8r(
    const Q6SegmentedIo0409& cfg) {
'''
pos = cu.find(anchor)
if pos < 0:
    raise SystemExit(f"[{TAG}] x8r host helper not found")
end = cu.find("\n}\n", pos)
if end < 0:
    raise SystemExit(f"[{TAG}] x8r host helper end not found")
end += 3

helper = r'''
bool q6_has_fullheight_passive_pressure_outlet_right_0493x8s(
    const Q6SegmentedIo0409& cfg) {
    if (!cfg.enabled || !cfg.passiveNeumannRightOutlet0493x8l) return false;
    constexpr double eps = 1.0e-12;
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] == 1 && cfg.mode[k] == 2 &&
            cfg.sMin[k] <= eps && cfg.sMax[k] >= 1.0 - eps) {
            return true;
        }
    }
    return false;
}
'''
cu = cu[:end] + helper + cu[end:]

# Device spectral helpers + host-fallback kernels.
init_anchor = "__global__ void q6_init_masked_cg_0493w5("
init_pos = cu.find(init_anchor)
if init_pos < 0:
    raise SystemExit(f"[{TAG}] CG init kernel not found")

spectral_code = r'''// 0493x8s exact pressure-outlet low-mode deflation.
__host__ __device__ __forceinline__ double q6_pressure_outlet_mode_0493x8s(
    int ix,
    int nx,
    int mode) {
    constexpr double pi = 3.141592653589793238462643383279502884;
    const double theta =
        (static_cast<double>(mode) + 0.5) * pi / static_cast<double>(nx);
    return cos(theta * (static_cast<double>(ix) + 0.5));
}

__host__ __device__ __forceinline__ double q6_pressure_outlet_mode_lambda_0493x8s(
    int nx,
    int mode,
    double invDx2) {
    constexpr double pi = 3.141592653589793238462643383279502884;
    const double theta =
        (static_cast<double>(mode) + 0.5) * pi / static_cast<double>(nx);
    const double s = sin(0.5 * theta);
    return 4.0 * s * s * invDx2;
}

__global__ void q6_reduce_pressure_outlet_modes_0493x8s(
    const double* rhs,
    double* partial0,
    double* partial1,
    double* partial2,
    int nx,
    int ny) {
    extern __shared__ double sh[];
    double* sh0 = sh;
    double* sh1 = sh + blockDim.x;
    double* sh2 = sh + 2 * blockDim.x;
    const int tid = threadIdx.x;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    double b0 = 0.0;
    double b1 = 0.0;
    double b2 = 0.0;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const double v = rhs[c];
        b0 += v * q6_pressure_outlet_mode_0493x8s(ix, nx, 0);
        b1 += v * q6_pressure_outlet_mode_0493x8s(ix, nx, 1);
        b2 += v * q6_pressure_outlet_mode_0493x8s(ix, nx, 2);
    }
    sh0[tid] = b0;
    sh1[tid] = b1;
    sh2[tid] = b2;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh0[tid] += sh0[tid + offset];
            sh1[tid] += sh1[tid + offset];
            sh2[tid] += sh2[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partial0[blockIdx.x] = sh0[0];
        partial1[blockIdx.x] = sh1[0];
        partial2[blockIdx.x] = sh2[0];
    }
}

__global__ void q6_init_pressure_outlet_deflated_cg_0493x8s(
    const double* rhs,
    double* phi,
    double* r,
    double* p,
    double rhsMode0,
    double rhsMode1,
    double rhsMode2,
    double lambda0,
    double lambda1,
    double lambda2,
    int nx,
    int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const double e0 = q6_pressure_outlet_mode_0493x8s(ix, nx, 0);
        const double e1 = q6_pressure_outlet_mode_0493x8s(ix, nx, 1);
        const double e2 = q6_pressure_outlet_mode_0493x8s(ix, nx, 2);
        const double lowRhs =
            rhsMode0 * e0 + rhsMode1 * e1 + rhsMode2 * e2;
        const double lowPhi =
            (rhsMode0 / lambda0) * e0 +
            (rhsMode1 / lambda1) * e1 +
            (rhsMode2 / lambda2) * e2;
        const double rv = rhs[c] - lowRhs;
        phi[c] = lowPhi;
        r[c] = rv;
        p[c] = rv;
    }
}

'''
cu = cu[:init_pos] + spectral_code + cu[init_pos:]

# Resident CG signature.
old_tail = '''    Q6SegmentedIo0409 segmentedIo,
    int pressureOutletDirichlet0493x8r,
    int fullDomain) {
'''
new_tail = '''    Q6SegmentedIo0409 segmentedIo,
    int pressureOutletDirichlet0493x8r,
    int pressureOutletDeflation0493x8s,
    int fullDomain) {
'''
cu = once(cu, old_tail, new_tail, "resident CG signature")

# Resident initialization.
old_init = '''    const bool removeConstantNullspace0493x8r =
        fullDomain && !pressureOutletDirichlet0493x8r;
    const double rhsMean = removeConstantNullspace0493x8r
        ? state->rhsSum / static_cast<double>(n)
        : 0.0;

    double localRr = 0.0;
    for (int c = idx; c < n; c += stride) {
        if (!fullDomain && mask[c] == 0u) {
            rhs[c] = 0.0;
            phi[c] = 0.0;
            r[c] = 0.0;
            p[c] = 0.0;
            Ap[c] = 0.0;
            continue;
        }
        const double v =
            rhs[c] - (removeConstantNullspace0493x8r ? rhsMean : 0.0);
        rhs[c] = v;
        phi[c] = 0.0;
        r[c] = v;
        p[c] = v;
        localRr += v * v;
    }

    const double rr0 = q6_grid_sum_0493x7j(
        localRr, blockPartials0, warpSums, grid, state);
    if (blockIdx.x == 0 && threadIdx.x == 0) {
        const double rhsNorm = sqrt(fmax(0.0, rr0));
        state->rr = rr0;
        state->rhsNormSafe = fmax(rhsNorm, 1.0e-300);
        state->residualRel = rhsNorm <= tolerance ? 0.0 : 1.0;
        state->iterations = 0;
        state->status = rhsNorm <= tolerance ? 1 : 0;
    }
'''
new_init = '''    const bool removeConstantNullspace0493x8r =
        fullDomain && !pressureOutletDirichlet0493x8r;
    const bool deflatePressureOutlet0493x8s =
        pressureOutletDeflation0493x8s != 0;
    const double rhsMean = removeConstantNullspace0493x8r
        ? state->rhsSum / static_cast<double>(n)
        : 0.0;

    double rhsMode0 = 0.0;
    double rhsMode1 = 0.0;
    double rhsMode2 = 0.0;
    double rhsNormSq0493x8s = 0.0;
    if (deflatePressureOutlet0493x8s) {
        double local0 = 0.0;
        double local1 = 0.0;
        double local2 = 0.0;
        double localSq = 0.0;
        for (int c = idx; c < n; c += stride) {
            const int ix = c % nx;
            const double v = rhs[c];
            local0 += v * q6_pressure_outlet_mode_0493x8s(ix, nx, 0);
            local1 += v * q6_pressure_outlet_mode_0493x8s(ix, nx, 1);
            local2 += v * q6_pressure_outlet_mode_0493x8s(ix, nx, 2);
            localSq += v * v;
        }
        const double dot0 = q6_grid_sum_0493x7j(
            local0, blockPartials0, warpSums, grid, state);
        const double dot1 = q6_grid_sum_0493x7j(
            local1, blockPartials0, warpSums, grid, state);
        const double dot2 = q6_grid_sum_0493x7j(
            local2, blockPartials0, warpSums, grid, state);
        rhsNormSq0493x8s = q6_grid_sum_0493x7j(
            localSq, blockPartials0, warpSums, grid, state);
        const double modeNorm = 0.5 * static_cast<double>(n);
        rhsMode0 = dot0 / modeNorm;
        rhsMode1 = dot1 / modeNorm;
        rhsMode2 = dot2 / modeNorm;
    }

    const double lambda0 = deflatePressureOutlet0493x8s
        ? q6_pressure_outlet_mode_lambda_0493x8s(nx, 0, invDx2) : 1.0;
    const double lambda1 = deflatePressureOutlet0493x8s
        ? q6_pressure_outlet_mode_lambda_0493x8s(nx, 1, invDx2) : 1.0;
    const double lambda2 = deflatePressureOutlet0493x8s
        ? q6_pressure_outlet_mode_lambda_0493x8s(nx, 2, invDx2) : 1.0;

    double localRr = 0.0;
    for (int c = idx; c < n; c += stride) {
        if (!fullDomain && mask[c] == 0u) {
            rhs[c] = 0.0;
            phi[c] = 0.0;
            r[c] = 0.0;
            p[c] = 0.0;
            Ap[c] = 0.0;
            continue;
        }
        const double v =
            rhs[c] - (removeConstantNullspace0493x8r ? rhsMean : 0.0);
        rhs[c] = v;
        if (deflatePressureOutlet0493x8s) {
            const int ix = c % nx;
            const double e0 = q6_pressure_outlet_mode_0493x8s(ix, nx, 0);
            const double e1 = q6_pressure_outlet_mode_0493x8s(ix, nx, 1);
            const double e2 = q6_pressure_outlet_mode_0493x8s(ix, nx, 2);
            const double lowRhs =
                rhsMode0 * e0 + rhsMode1 * e1 + rhsMode2 * e2;
            phi[c] =
                (rhsMode0 / lambda0) * e0 +
                (rhsMode1 / lambda1) * e1 +
                (rhsMode2 / lambda2) * e2;
            const double rv = v - lowRhs;
            r[c] = rv;
            p[c] = rv;
            localRr += rv * rv;
        } else {
            phi[c] = 0.0;
            r[c] = v;
            p[c] = v;
            localRr += v * v;
        }
    }

    const double rr0 = q6_grid_sum_0493x7j(
        localRr, blockPartials0, warpSums, grid, state);
    if (blockIdx.x == 0 && threadIdx.x == 0) {
        const double rhsNorm = deflatePressureOutlet0493x8s
            ? sqrt(fmax(0.0, rhsNormSq0493x8s))
            : sqrt(fmax(0.0, rr0));
        const double residualRel0 =
            sqrt(fmax(0.0, rr0)) / fmax(rhsNorm, 1.0e-300);
        state->rr = rr0;
        state->rhsNormSafe = fmax(rhsNorm, 1.0e-300);
        state->residualRel = rhsNorm <= tolerance ? 0.0 : residualRel0;
        state->iterations = 0;
        state->status =
            (rhsNorm <= tolerance || residualRel0 <= tolerance) ? 1 : 0;
    }
'''
cu = once(cu, old_init, new_init, "resident deflated initialization")

# Resident launch wrapper.
old_launch_sig = '''    Q6SegmentedIo0409 segmentedIo,
    bool pressureOutletDirichlet0493x8r,
    bool fullDomain,
    double& divBeforeSqOut0493x7j,
'''
new_launch_sig = '''    Q6SegmentedIo0409 segmentedIo,
    bool pressureOutletDirichlet0493x8r,
    bool pressureOutletDeflation0493x8s,
    bool fullDomain,
    double& divBeforeSqOut0493x7j,
'''
cu = once(cu, old_launch_sig, new_launch_sig, "resident launch wrapper signature")

old_locals = '''    int pressureOutlet = pressureOutletDirichlet0493x8r ? 1 : 0;
    int full = fullDomain ? 1 : 0;

    void* args[] = {
'''
new_locals = '''    int pressureOutlet = pressureOutletDirichlet0493x8r ? 1 : 0;
    int pressureOutletDeflation = pressureOutletDeflation0493x8s ? 1 : 0;
    int full = fullDomain ? 1 : 0;

    void* args[] = {
'''
cu = once(cu, old_locals, new_locals, "resident launch locals")

old_args = '''        &invDx2, &invDy2, &periodicX, &periodicY,
        &segmentedIo, &pressureOutlet, &full
'''
new_args = '''        &invDx2, &invDy2, &periodicX, &periodicY,
        &segmentedIo, &pressureOutlet, &pressureOutletDeflation, &full
'''
cu = once(cu, old_args, new_args, "resident cooperative args")

# Driver activation.
old_flag = '''    // 0493x8r passive pressure outlet
    // A phi=0 outlet face removes the constant pressure-correction nullspace
    // even when every pressure cell is active.
    const bool pressureOutletDirichlet0493x8r =
        q6_has_passive_pressure_outlet_right_0493x8r(segmentedIo);

    for (int s = 0; s < speciesCount; ++s) {
'''
new_flag = f'''    // 0493x8r passive pressure outlet
    // A phi=0 outlet face removes the constant pressure-correction nullspace
    // even when every pressure cell is active.
    const bool pressureOutletDirichlet0493x8r =
        q6_has_passive_pressure_outlet_right_0493x8r(segmentedIo);
    // {MARKER}
    const bool pressureOutletDeflation0493x8s =
        pressureOutletDirichlet0493x8r && !periodicX &&
        q6_has_fullheight_passive_pressure_outlet_right_0493x8s(segmentedIo);

    for (int s = 0; s < speciesCount; ++s) {{
'''
cu = once(cu, old_flag, new_flag, "driver deflation flag")

old_launch_call = '''                periodicX, periodicY, segmentedIo,
                pressureOutletDirichlet0493x8r,
                audit.fullDomain, divBeforeSq, audit);
'''
new_launch_call = '''                periodicX, periodicY, segmentedIo,
                pressureOutletDirichlet0493x8r,
                pressureOutletDeflation0493x8s && audit.fullDomain,
                audit.fullDomain, divBeforeSq, audit);
'''
cu = once(cu, old_launch_call, new_launch_call, "resident launch call")

# Host fallback initialization.
old_host_init = '''            q6_init_masked_cg_0493w5<<<cellBlocks, threads>>>(
                ws.rhs.data(), ws.phi.data(), ws.r.data(), ws.p.data(),
                q6SolveMask0493x6f, rhsMean,
                removeConstantNullspace0493x8r ? 1 : 0,
                grid.numCells);
            check_cuda_0400(cudaGetLastError(), "independent masked cg init launch");
            q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                ws.r.data(), ws.partial0.data(), grid.numCells);
            check_cuda_0400(cudaGetLastError(), "independent masked initial rr launch");
            double rr = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            const double rhsNorm = std::sqrt(std::max(0.0, rr));
            const double rhsNormSafe = std::max(rhsNorm, 1.0e-300);
            audit.converged = rhsNorm <= tol;
            audit.residualRel = audit.converged ? 0.0 : 1.0;
'''
new_host_init = '''            const bool deflatePressureOutlet0493x8s =
                pressureOutletDeflation0493x8s && audit.fullDomain;
            double rhsNorm = 0.0;
            if (deflatePressureOutlet0493x8s) {
                q6_reduce_pressure_outlet_modes_0493x8s<<<
                    cellBlocks, threads, tripleShared>>>(
                    ws.rhs.data(), ws.partial0.data(), ws.partial1.data(),
                    ws.partial2.data(), grid.Nx, grid.Ny);
                check_cuda_0400(cudaGetLastError(),
                                "0493x8s pressure outlet mode reduction launch");
                const double dot0 = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
                const double dot1 = reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
                const double dot2 = reduce_host_sum_0400(ws.partial2.data(), cellBlocks);
                const double modeNorm =
                    0.5 * static_cast<double>(grid.numCells);
                const double rhsMode0 = dot0 / modeNorm;
                const double rhsMode1 = dot1 / modeNorm;
                const double rhsMode2 = dot2 / modeNorm;
                const double lambda0 =
                    q6_pressure_outlet_mode_lambda_0493x8s(
                        grid.Nx, 0, invDx2);
                const double lambda1 =
                    q6_pressure_outlet_mode_lambda_0493x8s(
                        grid.Nx, 1, invDx2);
                const double lambda2 =
                    q6_pressure_outlet_mode_lambda_0493x8s(
                        grid.Nx, 2, invDx2);

                q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                    ws.rhs.data(), ws.partial0.data(), grid.numCells);
                check_cuda_0400(cudaGetLastError(),
                                "0493x8s pressure outlet rhs norm launch");
                const double rhsSq =
                    reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
                rhsNorm = std::sqrt(std::max(0.0, rhsSq));

                q6_init_pressure_outlet_deflated_cg_0493x8s<<<
                    cellBlocks, threads>>>(
                    ws.rhs.data(), ws.phi.data(), ws.r.data(), ws.p.data(),
                    rhsMode0, rhsMode1, rhsMode2,
                    lambda0, lambda1, lambda2,
                    grid.Nx, grid.numCells);
                check_cuda_0400(cudaGetLastError(),
                                "0493x8s pressure outlet deflated cg init launch");
            } else {
                q6_init_masked_cg_0493w5<<<cellBlocks, threads>>>(
                    ws.rhs.data(), ws.phi.data(), ws.r.data(), ws.p.data(),
                    q6SolveMask0493x6f, rhsMean,
                    removeConstantNullspace0493x8r ? 1 : 0,
                    grid.numCells);
                check_cuda_0400(cudaGetLastError(),
                                "independent masked cg init launch");
            }

            q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                ws.r.data(), ws.partial0.data(), grid.numCells);
            check_cuda_0400(cudaGetLastError(), "independent masked initial rr launch");
            double rr = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            if (!deflatePressureOutlet0493x8s) {
                rhsNorm = std::sqrt(std::max(0.0, rr));
            }
            const double rhsNormSafe = std::max(rhsNorm, 1.0e-300);
            audit.residualRel =
                std::sqrt(std::max(0.0, rr)) / rhsNormSafe;
            audit.converged =
                rhsNorm <= tol || audit.residualRel <= tol;
            if (rhsNorm <= tol) audit.residualRel = 0.0;
'''
cu = once(cu, old_host_init, new_host_init, "host deflated initialization")

CU.write_text(cu, encoding="utf-8")

print(f"[{TAG}] patched {CU}")
print(f"[{TAG}] activation: fullDomain + nonperiodic x + full-height x8r right outlet")
print(f"[{TAG}] deflated exact modes: m=0,1,2")
print(f"[{TAG}] tolerance and 2500 iteration cap unchanged")
print(f"[{TAG}] physics/operator unchanged; only CG initial subspace changed")

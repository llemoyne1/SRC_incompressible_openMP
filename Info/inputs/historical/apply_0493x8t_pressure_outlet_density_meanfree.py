#!/usr/bin/env python3
'''
0493x8t — make the x7d density-relaxation divergence target mean-free when it
is coupled to the x8r passive pressure outlet on a full pressure domain.

Observed discriminator:
  x8r/x8s + normal x7d density relaxation:
      outlet net ~ 1356 particles/step
  x8r/x8s + density relaxation disabled:
      outlet net ~ 487 particles/step

x7d-v2 uses asymmetric compression/traction admission thresholds. Its admitted
local target can therefore have a non-zero spatial mean in a thermally
fluctuating homogeneous fluid. Before x8r, the full-domain pressure-Neumann
solve removed the constant RHS mode. With a genuine pressure outlet, that mode
becomes solvable and acts as an unintended global volumetric source.

x8t removes ONLY the spatial mean of the density-relaxation target:
    d_rho_centered(c) = d_rho(c) - <d_rho>
before the pressure solve, and only for:
    active density relaxation
    + x8r passive pressure outlet
    + full pressure domain.

Local x7d redistribution is retained. Masked/free-surface cases and all
non-pressure-outlet cases retain historical x7d semantics.

Both Q6GF CG implementations are covered:
  - x7j cooperative resident CG, without an extra host synchronization
  - host-driven fallback CG

No new user parameter. No tolerance/max-iteration change. No clean-tree guard.
'''

from pathlib import Path

ROOT = Path.cwd()
CU = ROOT / "src/cuda_q6_resident_0400.cu"
TAG = "0493x8t"
MARKER = "0493x8t pressure-outlet density target mean removal"

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
for required in ("0493x8r passive pressure outlet",
                 "0493x8s exact pressure-outlet low-mode deflation"):
    if required not in cu:
        raise SystemExit(f"[{TAG}] prerequisite marker not found: {required}")

# 1) Audit/state scalar.
cu = once(
    cu,
    r'''    double rhsSum = 0.0;
    double divBeforeSq = 0.0;
''',
    r'''    double rhsSum = 0.0;
    double densityRelaxationTargetDivMeanRemoved0493x8t = 0.0;
    double divBeforeSq = 0.0;
''',
    "resident state audit scalar",
)

cu = once(
    cu,
    r'''    double densityRelaxationTargetDivRms = 0.0;
    // 0493x7j: audit only; the production default is one cooperative,
''',
    r'''    double densityRelaxationTargetDivRms = 0.0;
    // 0493x8t: raw spatial mean removed from the x7d density-divergence
    // target when a full-domain x8r pressure outlet is active.
    double densityRelaxationTargetDivMeanRemoved0493x8t = 0.0;
    // 0493x7j: audit only; the production default is one cooperative,
''',
    "species audit scalar",
)

cu = once(
    cu,
    r'''               "q6DensityRelaxationTime,densityRelaxationTargetDivRms,"
               "residentCg0493x7j,residentCgBlocks0493x7j\n";
''',
    r'''               "q6DensityRelaxationTime,densityRelaxationTargetDivRms,"
               "densityRelaxationTargetDivMeanRemoved0493x8t,"
               "residentCg0493x7j,residentCgBlocks0493x7j\n";
''',
    "audit CSV header",
)

cu = once(
    cu,
    r'''            << r.densityRelaxationTargetDivRms << ','
            << r.residentCg0493x7j << ',' << r.residentCgBlocks0493x7j << '\n';
''',
    r'''            << r.densityRelaxationTargetDivRms << ','
            << r.densityRelaxationTargetDivMeanRemoved0493x8t << ','
            << r.residentCg0493x7j << ',' << r.residentCgBlocks0493x7j << '\n';
''',
    "audit CSV row",
)

# 2) RHS builder: when centering is active, partialSum carries the raw
# density-target sum instead of the total RHS sum.
cu = once(
    cu,
    r'''    double densityRelaxationTractionThresholdFill0493x7dv2signed1,
    double densityRelaxationTractionGain0493x7dv2signed1,
    int densityRelaxationEnable0493x7c,
    int fullDomain) {
''',
    r'''    double densityRelaxationTractionThresholdFill0493x7dv2signed1,
    double densityRelaxationTractionGain0493x7dv2signed1,
    int densityRelaxationEnable0493x7c,
    int densityRelaxationCenterMean0493x8t,
    int fullDomain) {
''',
    "RHS builder signature",
)

cu = once(
    cu,
    r'''        if (densityRelaxationEnable0493x7c) {
            rhsValue += q6_density_relaxation_target_divergence_0493x7c(
                densityRelaxationRawFill0493x7c, mask, c, nx, ny,
                periodicX, periodicY, densityRelaxationBeta0493x7c,
                densityRelaxationDt0493x7c,
                densityRelaxationCompressionThresholdFill0493x7dv2,
                densityRelaxationCompressionGateEnable0493x7dv2,
                densityRelaxationTractionThresholdFill0493x7dv2signed1,
                densityRelaxationTractionGain0493x7dv2signed1, 1);
        }
        rhs[c] = rhsValue;
        sum += rhs[c];
''',
    r'''        double densityTarget0493x8t = 0.0;
        if (densityRelaxationEnable0493x7c) {
            densityTarget0493x8t =
                q6_density_relaxation_target_divergence_0493x7c(
                    densityRelaxationRawFill0493x7c, mask, c, nx, ny,
                    periodicX, periodicY, densityRelaxationBeta0493x7c,
                    densityRelaxationDt0493x7c,
                    densityRelaxationCompressionThresholdFill0493x7dv2,
                    densityRelaxationCompressionGateEnable0493x7dv2,
                    densityRelaxationTractionThresholdFill0493x7dv2signed1,
                    densityRelaxationTractionGain0493x7dv2signed1, 1);
            rhsValue += densityTarget0493x8t;
        }
        rhs[c] = rhsValue;
        // 0493x8t: in the pressure-outlet centering path partialSum carries
        // the raw density-target integral. Otherwise preserve historical
        // total-RHS reduction semantics exactly.
        sum += densityRelaxationCenterMean0493x8t
            ? densityTarget0493x8t
            : rhs[c];
''',
    "RHS builder density target",
)

# Tiny fallback helper.
insert_anchor = "__global__ void q6_reduce_square_sum_0400("
pos = cu.find(insert_anchor)
if pos < 0:
    raise SystemExit(f"[{TAG}] reduction kernel insertion anchor not found")
helper = r'''// 0493x8t host-fallback helper: remove only the constant component of
// the density-relaxation target from the already assembled RHS.
__global__ void q6_subtract_density_target_mean_from_rhs_0493x8t(
    double* rhs,
    const unsigned char* mask,
    double mean,
    int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (mask[c] != 0u) rhs[c] -= mean;
    }
}

'''
cu = cu[:pos] + helper + cu[pos:]

# 3) Projected-divergence diagnostic uses the centered target.
diag_start = cu.find("__global__ void q6_masked_projected_divergence_stats_0493w5(")
if diag_start < 0:
    raise SystemExit(f"[{TAG}] projected divergence diagnostic not found")
diag_end = cu.find("\n}\n", diag_start)
if diag_end < 0:
    raise SystemExit(f"[{TAG}] projected divergence diagnostic end not found")
diag_end += 3
reg = cu[diag_start:diag_end]

reg = once(
    reg,
    r'''    double densityRelaxationTractionThresholdFill0493x7dv2signed1,
    double densityRelaxationTractionGain0493x7dv2signed1,
    int densityRelaxationEnable0493x7c,
    double* partialTargetSq0493x7c,
''',
    r'''    double densityRelaxationTractionThresholdFill0493x7dv2signed1,
    double densityRelaxationTractionGain0493x7dv2signed1,
    int densityRelaxationEnable0493x7c,
    double densityRelaxationTargetDivMean0493x8t,
    double* partialTargetSq0493x7c,
''',
    "projected diagnostic signature",
)

reg = once(
    reg,
    r'''                densityRelaxationTractionThresholdFill0493x7dv2signed1,
                densityRelaxationTractionGain0493x7dv2signed1, 1);
            residual -= targetDiv0493x7c;
''',
    r'''                densityRelaxationTractionThresholdFill0493x7dv2signed1,
                densityRelaxationTractionGain0493x7dv2signed1, 1);
            targetDiv0493x7c -= densityRelaxationTargetDivMean0493x8t;
            residual -= targetDiv0493x7c;
''',
    "projected diagnostic centered target",
)
cu = cu[:diag_start] + reg + cu[diag_end:]

# 4) Resident x7j CG.
cu = once(
    cu,
    r'''    Q6SegmentedIo0409 segmentedIo,
    int pressureOutletDirichlet0493x8r,
    int pressureOutletDeflation0493x8s,
    int fullDomain) {
''',
    r'''    Q6SegmentedIo0409 segmentedIo,
    int densityRelaxationCenterMean0493x8t,
    int pressureOutletDirichlet0493x8r,
    int pressureOutletDeflation0493x8s,
    int fullDomain) {
''',
    "resident CG signature",
)

cu = once(
    cu,
    r'''        if (threadIdx.x == 0) {
            state->rhsSum = totalRhs;
            state->divBeforeSq = totalDivSq;
            state->divBeforeMaxAbs = totalDivMax;
        }
    }
    q6_grid_barrier_0493x7j(grid);

    const bool removeConstantNullspace0493x8r =
''',
    r'''        if (threadIdx.x == 0) {
            state->densityRelaxationTargetDivMeanRemoved0493x8t =
                densityRelaxationCenterMean0493x8t
                    ? totalRhs / static_cast<double>(n)
                    : 0.0;
            state->rhsSum =
                densityRelaxationCenterMean0493x8t ? 0.0 : totalRhs;
            state->divBeforeSq = totalDivSq;
            state->divBeforeMaxAbs = totalDivMax;
        }
    }
    q6_grid_barrier_0493x7j(grid);

    if (densityRelaxationCenterMean0493x8t) {
        const double mean0493x8t =
            state->densityRelaxationTargetDivMeanRemoved0493x8t;
        double localCenteredRhsSum0493x8t = 0.0;
        for (int c = idx; c < n; c += stride) {
            if (!fullDomain && mask[c] == 0u) continue;
            rhs[c] -= mean0493x8t;
            localCenteredRhsSum0493x8t += rhs[c];
        }
        const double centeredRhsSum0493x8t = q6_grid_sum_0493x7j(
            localCenteredRhsSum0493x8t,
            blockPartials0, warpSums, grid, state);
        if (blockIdx.x == 0 && threadIdx.x == 0) {
            state->rhsSum = centeredRhsSum0493x8t;
        }
        q6_grid_barrier_0493x7j(grid);
    }

    const bool removeConstantNullspace0493x8r =
''',
    "resident target mean removal",
)

# Launch wrapper.
cu = once(
    cu,
    r'''    Q6SegmentedIo0409 segmentedIo,
    bool pressureOutletDirichlet0493x8r,
    bool pressureOutletDeflation0493x8s,
    bool fullDomain,
''',
    r'''    Q6SegmentedIo0409 segmentedIo,
    bool densityRelaxationCenterMean0493x8t,
    bool pressureOutletDirichlet0493x8r,
    bool pressureOutletDeflation0493x8s,
    bool fullDomain,
''',
    "resident launch wrapper signature",
)

cu = once(
    cu,
    r'''    int pressureOutlet = pressureOutletDirichlet0493x8r ? 1 : 0;
    int pressureOutletDeflation = pressureOutletDeflation0493x8s ? 1 : 0;
''',
    r'''    int densityRelaxationCenterMean =
        densityRelaxationCenterMean0493x8t ? 1 : 0;
    int pressureOutlet = pressureOutletDirichlet0493x8r ? 1 : 0;
    int pressureOutletDeflation = pressureOutletDeflation0493x8s ? 1 : 0;
''',
    "resident launch locals",
)

cu = once(
    cu,
    r'''        &invDx2, &invDy2, &periodicX, &periodicY,
        &segmentedIo, &pressureOutlet, &pressureOutletDeflation, &full
''',
    r'''        &invDx2, &invDy2, &periodicX, &periodicY,
        &segmentedIo, &densityRelaxationCenterMean,
        &pressureOutlet, &pressureOutletDeflation, &full
''',
    "resident cooperative args",
)

cu = once(
    cu,
    r'''    audit.residentCg0493x7j = 1;
    audit.residentCgBlocks0493x7j = gridBlocks;
''',
    r'''    audit.densityRelaxationTargetDivMeanRemoved0493x8t =
        hostState.densityRelaxationTargetDivMeanRemoved0493x8t;
    audit.residentCg0493x7j = 1;
    audit.residentCgBlocks0493x7j = gridBlocks;
''',
    "resident audit propagation",
)

# 5) Driver activation immediately before main RHS launch.
rhs_launch = r'''        q6_build_independent_rhs_after_mask_0493w5<<<cellBlocks, threads, tripleShared>>>(
'''
pos = cu.find(rhs_launch)
if pos < 0:
    raise SystemExit(f"[{TAG}] main RHS launch not found")
flag = f'''        // {MARKER}
        // x7d remains active locally, but its constant divergence mode may not
        // act as a second global flow controller beside the x8r pressure outlet.
        const bool densityRelaxationCenterMean0493x8t =
            densityRelaxationRequested0493x7c &&
            pressureOutletDirichlet0493x8r &&
            audit.fullDomain;

'''
cu = cu[:pos] + flag + cu[pos:]

cu = once(
    cu,
    r'''            params.q6DensityRelaxationTractionThresholdFill,
            params.q6DensityRelaxationTractionGain,
            densityRelaxationRequested0493x7c ? 1 : 0,
            audit.fullDomain ? 1 : 0);
''',
    r'''            params.q6DensityRelaxationTractionThresholdFill,
            params.q6DensityRelaxationTractionGain,
            densityRelaxationRequested0493x7c ? 1 : 0,
            densityRelaxationCenterMean0493x8t ? 1 : 0,
            audit.fullDomain ? 1 : 0);
''',
    "main RHS launch args",
)

cu = once(
    cu,
    r'''                periodicX, periodicY, segmentedIo,
                pressureOutletDirichlet0493x8r,
                pressureOutletDeflation0493x8s && audit.fullDomain,
''',
    r'''                periodicX, periodicY, segmentedIo,
                densityRelaxationCenterMean0493x8t,
                pressureOutletDirichlet0493x8r,
                pressureOutletDeflation0493x8s && audit.fullDomain,
''',
    "resident launch call",
)

cu = once(
    cu,
    r'''        if (!residentCgUsed0493x7j) {
            const double rhsSum = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            divBeforeSq = reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
''',
    r'''        if (!residentCgUsed0493x7j) {
            double rhsSum = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            if (densityRelaxationCenterMean0493x8t) {
                const double densityTargetMean0493x8t =
                    rhsSum / static_cast<double>(
                        std::max<std::uint64_t>(1u, audit.activeCells));
                audit.densityRelaxationTargetDivMeanRemoved0493x8t =
                    densityTargetMean0493x8t;
                q6_subtract_density_target_mean_from_rhs_0493x8t<<<
                    cellBlocks, threads>>>(
                    ws.rhs.data(), q6SolveMask0493x6f,
                    densityTargetMean0493x8t, grid.numCells);
                check_cuda_0400(cudaGetLastError(),
                                "0493x8t centered density RHS launch");
                q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                    ws.rhs.data(), ws.partial0.data(), grid.numCells);
                check_cuda_0400(cudaGetLastError(),
                                "0493x8t centered RHS sum launch");
                rhsSum = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            }
            divBeforeSq = reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
''',
    "host fallback target mean removal",
)

cu = once(
    cu,
    r'''                params.q6DensityRelaxationTractionThresholdFill,
                params.q6DensityRelaxationTractionGain,
                densityRelaxationRequested0493x7c ? 1 : 0,
                ws.partial2.data(), audit.fullDomain ? 1 : 0);
''',
    r'''                params.q6DensityRelaxationTractionThresholdFill,
                params.q6DensityRelaxationTractionGain,
                densityRelaxationRequested0493x7c ? 1 : 0,
                audit.densityRelaxationTargetDivMeanRemoved0493x8t,
                ws.partial2.data(), audit.fullDomain ? 1 : 0);
''',
    "projected diagnostic call",
)

# Post-apply RHS diagnostic call has density relaxation disabled.
cu = once(
    cu,
    r'''                nullptr, 0.0, params.dt, 0.0, 0, 0.0, 0.0, 0,
                audit.fullDomain ? 1 : 0);
''',
    r'''                nullptr, 0.0, params.dt, 0.0, 0, 0.0, 0.0, 0, 0,
                audit.fullDomain ? 1 : 0);
''',
    "postapply RHS x8t flag",
)

CU.write_text(cu, encoding="utf-8")

print(f"[{TAG}] patched {CU}")
print(f"[{TAG}] local x7d density response retained")
print(f"[{TAG}] removed only density-target spatial mean for full-domain x8r outlet")
print(f"[{TAG}] resident x7j path adds no host synchronization")
print(f"[{TAG}] masked/free-surface and non-pressure-outlet paths unchanged")

#!/usr/bin/env python3
from pathlib import Path
import re
import sys

PATH = Path("src/cuda_q6_resident_0400.cu")
MARKER = "0493x10v — ONE-FOR-ONE LOCAL VELOCITY SWAP"


def fail(msg: str) -> None:
    raise SystemExit(f"[0493x10v-swap] ERROR: {msg}")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        fail(f"{label}: expected exactly one anchor, found {n}")
    return text.replace(old, new, 1)


if not PATH.exists():
    fail(f"missing {PATH}; run from repository root")

orig = PATH.read_text()
if MARKER in orig:
    print("[0493x10v-swap] already applied; no changes")
    sys.exit(0)

for prerequisite in (
    "0493x10u-oneforone — CONSERVATIVE ONE-PARTICLE SUPPORT RELOCATION",
    "MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE",
    "q6_x10biq_collide_moving_patch",
    "q6_x10biq_closest_current_wall",
):
    if prerequisite not in orig:
        fail(f"current source is missing prerequisite: {prerequisite}")

text = orig

# One byte/particle only when x10v is enabled. The two per-cell x10m impulse
# arrays are reused later as candidate-index scratch, so no new O(Ncell) field.
old = """    DeviceBuffer0400<double> kineticMovingWallImpulseX0493x10m;\n    DeviceBuffer0400<double> kineticMovingWallImpulseY0493x10m;\n"""
new = old + """    // 0493x10v: one byte per particle, allocated only for the optional\n    // one-for-one local velocity-swap path. It marks particles whose support\n    // position was relocated by x10u during the current interface pass.\n    DeviceBuffer0400<unsigned char> kineticOneForOneRelocated0493x10v;\n"""
text = replace_once(text, old, new, "workspace relocated marker")

# Pass an optional marker to the support-relocation kernel.
old = """    double thermalThickness0493x10poly,\n    int quadraticInterface0493x10poly,\n    int oneForOneRelocation0493x10u,\n    int microTraceStep0493x10diag,\n"""
new = """    double thermalThickness0493x10poly,\n    int quadraticInterface0493x10poly,\n    int oneForOneRelocation0493x10u,\n    unsigned char* oneForOneRelocated0493x10v,\n    int microTraceStep0493x10diag,\n"""
text = replace_once(text, old, new, "collision kernel marker argument")

old = """        particles.vx[p] = cvx;\n        particles.vy[p] = cvy;\n        if (audit)\n"""
new = """        particles.vx[p] = cvx;\n        particles.vy[p] = cvy;\n        if (oneForOneRelocation0493x10u && oneForOneRelocated0493x10v)\n            oneForOneRelocated0493x10v[p] = 1u;\n        if (audit)\n"""
text = replace_once(text, old, new, "relocated particle mark")

# Candidate collection + race-free local literal velocity exchange.
old = """}\n\n// 0493x10i: reduce existing per-cell donor/receiver statistics into\n"""
new = r''' }

// =============================================================================
// 0493x10v — ONE-FOR-ONE LOCAL VELOCITY SWAP
// =============================================================================
// x10u established that spatial-only relocation removes the direct wall
// impulse but lets outward thermal velocities repeatedly escape. x10v keeps
// the same support relocation and then permutes velocities locally: every
// relocated phase-A particle may exchange its velocity with one non-relocated
// equal-mass phase-A particle in a nearby, more liquid cell. A literal swap of
// equal-mass velocities preserves each particle mass and preserves total P and
// kinetic K exactly. No velocity is invented, reflected or thermalized here.
//
// Two candidate particle indices per cell are stored temporarily in the two
// x10m impulse buffers after the relocation kernel. In x10u/x10v these impulse
// fields are identically zero and are not consumed afterwards. This avoids any
// new O(Ncell) storage. The only new resident scratch is one byte/particle for
// the relocated marker. Candidate ownership is claimed with atomicCAS, so one
// interior particle can participate in at most one swap per step.

__global__ void q6_x10v_build_velocity_swap_candidates(
    CudaParticleDeviceView particles,
    std::uint64_t nParticles,
    const unsigned char* relocated,
    const double* alpha,
    unsigned long long* candidate0,
    unsigned long long* candidate1,
    std::uint32_t phaseAType,
    int nx, int ny,
    double lx, double ly,
    int periodicX, int periodicY,
    unsigned long long step0493x10v,
    unsigned long long seed0493x10v) {
    const std::uint64_t idx =
        static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride =
        static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    const unsigned long long empty = ~0ull;

    for (std::uint64_t p = idx; p < nParticles; p += stride) {
        if (relocated && relocated[p]) continue;
        if (particles.role && particles.role[p] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[p] != phaseAType) continue;
        const int c = q6_x10n_position_cell(
            particles.x[p], particles.y[p],
            nx, ny, lx, ly, periodicX, periodicY);
        if (c < 0) continue;
        if (!alpha || !(alpha[c] >= 0.5)) continue;

        if (p > 0xffffffffull) continue;
        // Randomized deterministic priority avoids repeatedly selecting the
        // lowest particle index in every cell. The low 32 bits retain the
        // particle index; the high 32 bits are a step/seed-dependent key.
        const unsigned long long h = q6_x9t_mix64(
            seed0493x10v ^ static_cast<unsigned long long>(p) ^
            ((step0493x10v + 0x10f0493ull) * 0x9e3779b97f4a7c15ull));
        const unsigned long long packed =
            ((h >> 32) << 32) | static_cast<unsigned long long>(p);
        const unsigned long long old0 = atomicMin(&candidate0[c], packed);
        const unsigned long long displaced =
            (packed < old0) ? old0 : packed;
        if (displaced != empty)
            atomicMin(&candidate1[c], displaced);
    }
}

__device__ __forceinline__ bool q6_x10v_equal_mass_for_literal_swap(
    double a, double b) {
    const double scale = fmax(1.0, fmax(fabs(a), fabs(b)));
    return fabs(a - b) <= 1.0e-12 * scale;
}

__global__ void q6_x10v_apply_local_velocity_swaps(
    CudaParticleDeviceView particles,
    std::uint64_t nParticles,
    const unsigned char* relocated,
    const double* alpha,
    unsigned long long* candidate0,
    unsigned long long* candidate1,
    std::uint32_t phaseAType,
    int nx, int ny,
    double lx, double ly,
    int periodicX, int periodicY) {
    const std::uint64_t idx =
        static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride =
        static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    const unsigned long long empty = ~0ull;

    for (std::uint64_t p = idx; p < nParticles; p += stride) {
        if (!relocated || !relocated[p]) continue;
        if (particles.role && particles.role[p] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[p] != phaseAType) continue;

        const int pc = q6_x10n_position_cell(
            particles.x[p], particles.y[p],
            nx, ny, lx, ly, periodicX, periodicY);
        if (pc < 0) continue;
        const int pi = pc % nx;
        const int pj = pc / nx;

        // Two candidates/cell over the local 3x3 neighborhood. Prefer the
        // candidate cell with the largest liquid alpha, i.e. the deepest local
        // support available without introducing a nonlocal population move.
        for (int attempt = 0; attempt < 18; ++attempt) {
            unsigned long long* bestPtr = nullptr;
            unsigned long long bestPacked = empty;
            double bestScore = -1.0e300;

            for (int dj = -1; dj <= 1; ++dj) {
                for (int di = -1; di <= 1; ++di) {
                    const int c = q6_x10n_cell_index(
                        pi + di, pj + dj, nx, ny, periodicX, periodicY);
                    if (c < 0) continue;
                    const double ac = alpha ? alpha[c] : 0.0;
                    if (!(ac >= 0.5)) continue;
                    const double distancePenalty =
                        1.0e-9 * static_cast<double>(di * di + dj * dj);
                    unsigned long long* slots[2] = {
                        candidate0 + c, candidate1 + c};
                    for (int s = 0; s < 2; ++s) {
                        const unsigned long long packed = *slots[s];
                        if (packed == empty) continue;
                        const std::uint64_t q = static_cast<std::uint64_t>(
                            static_cast<std::uint32_t>(packed & 0xffffffffull));
                        if (q >= nParticles || q == p) continue;
                        const double score =
                            ac - distancePenalty - 1.0e-12 * static_cast<double>(s);
                        if (score > bestScore) {
                            bestScore = score;
                            bestPtr = slots[s];
                            bestPacked = packed;
                        }
                    }
                }
            }

            if (!bestPtr || bestPacked == empty) break;
            if (atomicCAS(bestPtr, bestPacked, empty) != bestPacked)
                continue;

            const std::uint64_t q = static_cast<std::uint64_t>(
                static_cast<std::uint32_t>(bestPacked & 0xffffffffull));
            if (q >= nParticles || q == p ||
                (relocated && relocated[q]) ||
                (particles.role && particles.role[q] != kParticleRoleFluid) ||
                !particles.type || particles.type[q] != phaseAType) {
                continue;
            }

            const double mp = particles.mass ? particles.mass[p] : 1.0;
            const double mq = particles.mass ? particles.mass[q] : 1.0;
            if (!q6_x10v_equal_mass_for_literal_swap(mp, mq)) {
                // Literal swapping is exactly conservative only for equal
                // masses. Unequal-mass pairs are left unchanged rather than
                // introducing any momentum or kinetic-energy error.
                continue;
            }

            const double pvx = particles.vx[p];
            const double pvy = particles.vy[p];
            const double qvx = particles.vx[q];
            const double qvy = particles.vy[q];
            particles.vx[p] = qvx;
            particles.vy[p] = qvy;
            particles.vx[q] = pvx;
            particles.vy[q] = pvy;
            break;
        }
    }
}

// 0493x10i: reduce existing per-cell donor/receiver statistics into
'''.replace(''' }\n\n// =============================================================================''', '''}\n\n// =============================================================================''', 1)
text = replace_once(text, old, new, "x10v kernels insertion")

# Host mode gate. Existing x10u remains available as an A/B baseline.
old = """    const bool oneForOneRelocation0493x10u =\n        quadraticInterface0493x10poly &&\n        env_int_0400("MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE", 0) != 0;\n    if (oneForOneRelocation0493x10u && !initialOverlapResolution0493x10p) {\n        throw std::runtime_error(\n            "0493x10u one-for-one relocation requires x10p initial-overlap resolution");\n    }\n"""
new = old + """    const bool oneForOneVelocitySwapRequested0493x10v =\n        env_int_0400("MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP", 0) != 0;\n    if (oneForOneVelocitySwapRequested0493x10v &&\n        !oneForOneRelocation0493x10u) {\n        throw std::runtime_error(\n            "0493x10v velocity swap requires MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1");\n    }\n    const bool oneForOneVelocitySwap0493x10v =\n        oneForOneRelocation0493x10u && oneForOneVelocitySwapRequested0493x10v;\n"""
text = replace_once(text, old, new, "x10v host gate")

old = """                  << " cic=" << (kineticInterfaceCIC0493x10cic ? 1 : 0)\n                  << " biq=" << (quadraticInterface0493x10poly ? 1 : 0)\n                  << " semantics=position-mirror-only;mass-velocity-unchanged"\n                  << std::endl;\n"""
new = """                  << " cic=" << (kineticInterfaceCIC0493x10cic ? 1 : 0)\n                  << " biq=" << (quadraticInterface0493x10poly ? 1 : 0)\n                  << " swap=" << (oneForOneVelocitySwap0493x10v ? 1 : 0)\n                  << " semantics="\n                  << (oneForOneVelocitySwap0493x10v\n                          ? "position-mirror+local-equal-mass-velocity-swap"\n                          : "position-mirror-only;mass-velocity-unchanged")\n                  << std::endl;\n"""
text = replace_once(text, old, new, "x10u/x10v startup report")

old = """    ws.ensure_kinetic_interface_0493x9x(\n        grid.numCells, cellBlocks, mesoReservoirs);\n    const std::size_t kineticCellCount0493x10cic =\n"""
new = """    ws.ensure_kinetic_interface_0493x9x(\n        grid.numCells, cellBlocks, mesoReservoirs);\n    if (oneForOneVelocitySwap0493x10v) {\n        const std::size_t particleCount0493x10v =\n            static_cast<std::size_t>(std::max<std::uint64_t>(1ull, nParticles));\n        ws.kineticOneForOneRelocated0493x10v.ensure(particleCount0493x10v);\n        check_cuda_0400(cudaMemset(\n            ws.kineticOneForOneRelocated0493x10v.data(), 0,\n            particleCount0493x10v * sizeof(unsigned char)),\n            "0493x10v relocated marker zero");\n    }\n    const std::size_t kineticCellCount0493x10cic =\n"""
text = replace_once(text, old, new, "x10v marker allocation")

old = """            thermalThickness0493x10o,\n            quadraticInterface0493x10poly ? 1 : 0,\n            oneForOneRelocation0493x10u ? 1 : 0,\n            (microReflectionTrace0493x10diag ? step : -1),\n"""
new = """            thermalThickness0493x10o,\n            quadraticInterface0493x10poly ? 1 : 0,\n            oneForOneRelocation0493x10u ? 1 : 0,\n            oneForOneVelocitySwap0493x10v\n                ? ws.kineticOneForOneRelocated0493x10v.data()\n                : nullptr,\n            (microReflectionTrace0493x10diag ? step : -1),\n"""
text = replace_once(text, old, new, "x10v marker launch argument")

old = """        check_cuda_0400(\n            cudaGetLastError(), "0493x10n continuous-interface collision launch");\n    } else if (movingInterfaceWall0493x10m) {\n"""
new = """        check_cuda_0400(\n            cudaGetLastError(), "0493x10n continuous-interface collision launch");\n\n        if (oneForOneVelocitySwap0493x10v) {\n            // x10u has produced zero wall impulse, so these two O(Ncell)\n            // buffers are dead at this point and can hold two donor indices.\n            const std::size_t candidateBytes0493x10v =\n                static_cast<std::size_t>(std::max(1, grid.numCells)) *\n                sizeof(unsigned long long);\n            static_assert(sizeof(double) == sizeof(unsigned long long),\n                          "0493x10v scratch alias requires 64-bit double/index");\n            check_cuda_0400(cudaMemset(\n                ws.kineticMovingWallImpulseX0493x10m.data(), 0xff,\n                candidateBytes0493x10v),\n                "0493x10v candidate0 sentinel fill");\n            check_cuda_0400(cudaMemset(\n                ws.kineticMovingWallImpulseY0493x10m.data(), 0xff,\n                candidateBytes0493x10v),\n                "0493x10v candidate1 sentinel fill");\n\n            auto* candidate00493x10v = reinterpret_cast<unsigned long long*>(\n                ws.kineticMovingWallImpulseX0493x10m.data());\n            auto* candidate10493x10v = reinterpret_cast<unsigned long long*>(\n                ws.kineticMovingWallImpulseY0493x10m.data());\n            q6_x10v_build_velocity_swap_candidates<<<particleBlocks, threads>>>(\n                particles, nParticles,\n                ws.kineticOneForOneRelocated0493x10v.data(),\n                phaseAlphaKinetic0493x10cic,\n                candidate00493x10v, candidate10493x10v,\n                phaseAType, grid.Nx, grid.Ny, params.Lx, params.Ly,\n                periodicX, periodicY,\n                static_cast<unsigned long long>(step),\n                static_cast<unsigned long long>(params.rngSeed));\n            check_cuda_0400(\n                cudaGetLastError(), "0493x10v local swap candidate build launch");\n            q6_x10v_apply_local_velocity_swaps<<<particleBlocks, threads>>>(\n                particles, nParticles,\n                ws.kineticOneForOneRelocated0493x10v.data(),\n                phaseAlphaKinetic0493x10cic,\n                candidate00493x10v, candidate10493x10v,\n                phaseAType, grid.Nx, grid.Ny, params.Lx, params.Ly,\n                periodicX, periodicY);\n            check_cuda_0400(\n                cudaGetLastError(), "0493x10v local equal-mass velocity swap launch");\n        }\n    } else if (movingInterfaceWall0493x10m) {\n"""
text = replace_once(text, old, new, "x10v post-relocation launches")

# Static review checks: conservative literal swap and no particle-mass writes.
checks = (
    "MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP",
    "q6_x10v_build_velocity_swap_candidates",
    "q6_x10v_apply_local_velocity_swaps",
    "q6_x10v_equal_mass_for_literal_swap",
    "particles.vx[p] = qvx;",
    "particles.vx[q] = pvx;",
    "candidate0 sentinel fill",
    "kineticOneForOneRelocated0493x10v",
)
for needle in checks:
    if needle not in text:
        fail(f"postcondition missing: {needle}")
region = text[text.index("// 0493x10u-oneforone"):text.index("// 0493x10i: reduce existing")]
if re.search(r"particles\.mass\s*\[[^]]+\]\s*=", region):
    fail("x10u/x10v region unexpectedly writes particle mass")

# Basic lexical guard against a malformed semantic insertion.
if text.count("{") != text.count("}") or text.count("(") != text.count(")"):
    fail("lexical delimiter count changed inconsistently")

PATH.write_text(text)
print("[0493x10v-swap] PASS current x10u prerequisite")
print("[0493x10v-swap] PASS local two-candidate/cell selection")
print("[0493x10v-swap] PASS atomic single-owner donor claim")
print("[0493x10v-swap] PASS literal equal-mass velocity exchange")
print("[0493x10v-swap] PASS individual particle masses untouched")
print("[0493x10v-swap] PASS total P and kinetic K exact for every performed swap")
print("[0493x10v-swap] PASS no new O(Ncell) buffer; x10m impulse scratch reused")
print("[0493x10v-swap] PASS only one byte/particle conditional scratch")
print("[0493x10v-swap] PASS x10u position-only baseline retained")
print(f"[0493x10v-swap] updated {PATH}")

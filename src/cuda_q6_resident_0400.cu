#include "cuda_q6_resident_0400.h"

#if defined(MPCD_ENABLE_CUDA_Q6_RESIDENT_0400)

#include "cuda_cell_workspace.h"
#include "cuda_darcy_brinkman_0343.h"
#include "cuda_shared_particle_state_0251.h"
#include "cuda_species_cell_fields_0490h.h"
#include "open_boundary_segments.h"

#include <cuda_runtime.h>
#include <cooperative_groups.h>
#include <iostream>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace mpcd {
namespace {

using Clock0400 = std::chrono::steady_clock;

bool truthy_0400(const char* value) {
    if (value == nullptr || *value == '\0') {
        return false;
    }
    const std::string s(value);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0400(const char* name, int fallback) {
    const char* value = std::getenv(name);
    if (value == nullptr || *value == '\0') return fallback;
    char* end = nullptr;
    const long parsed = std::strtol(value, &end, 10);
    if (end == value) return fallback;
    return static_cast<int>(parsed);
}

double env_double_0400(const char* name, double fallback) {
    const char* value = std::getenv(name);
    if (value == nullptr || *value == '\0') return fallback;
    char* end = nullptr;
    const double parsed = std::strtod(value, &end);
    if (end == value || !std::isfinite(parsed)) return fallback;
    return parsed;
}

bool cuda_q6_single_block_cg_0407_enabled(int numCells) {
    const char* forced = std::getenv("MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407");
    if (forced != nullptr && *forced != '\0') return truthy_0400(forced);
    const int threshold = env_int_0400("MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_MAX_CELLS_0407", 65536);
    return threshold > 0 && numCells <= threshold;
}

bool cuda_q6_warm_start_0408_requested() {
    return truthy_0400(std::getenv("MPCD_CUDA_Q6_RESIDENT_WARM_START_0408"));
}

// 0493x7j: Q6-g-f must remain CUDA-resident through the elliptic solve.
// The legacy masked CG is retained only as an explicit/debug fallback or on
// devices that cannot launch a cooperative grid.  Default is ON.
bool cuda_q6_g_f_resident_cg_0493x7j_requested() {
    const char* value = std::getenv("MPCD_Q6_G_F_RESIDENT_CG_0493X7J");
    return value == nullptr || *value == '\0' || truthy_0400(value);
}

// 0493x7y: controlled physics ablation of x7q only.
//
// Default ON preserves the qualified production path. OFF does NOT disable B1
// and does NOT disable the preceding x7d-v2-fix2 periodic projected-species
// momentum correction. It only bypasses the x7q exact particle-level residual
// reduction and second closure pass, returning full-domain periodic B1 to the
// immediately pre-x7q implementation.
bool cuda_q6_exact_periodic_b1_closure_0493x7y_requested() {
    const char* value =
        std::getenv("MPCD_Q6_EXACT_PERIODIC_B1_CLOSURE_0493X7Y");
    const bool requested =
        value == nullptr || *value == '\0' || truthy_0400(value);
    static bool reported = false;
    if (!reported) {
        std::cout << "[0493x7y] exactPeriodicB1Closure="
                  << (requested ? 1 : 0)
                  << " env="
                  << ((value == nullptr || *value == '\0') ? "<default>" : value)
                  << std::endl;
        reported = true;
    }
    return requested;
}

bool cuda_q6_segmented_io_0409_requested() {
    return truthy_0400(std::getenv("MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409"));
}

// 0493x6a: diagnostic-only phase-pressure scaffold.  This does not alter the
// Q6 operator or particle velocities.  It reconstructs the ideal-gas external
// pressure potential that a later phase-coupled interface condition will use.
bool cuda_q6_phase_pressure_diagnostics_0493x6a_requested() {
    return truthy_0400(std::getenv("MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A"));
}

// 0493x6b: diagnostic-only phase-geometry scaffold.  It reconstructs an
// interface proxy directly from the already resident species-cell masses.
// No particle pass, no projection coefficient and no particle velocity is
// changed.  The expensive path is entered only on the existing summary cadence.
bool cuda_q6_phase_geometry_diagnostics_0493x6b_requested() {
    return truthy_0400(std::getenv("MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B"));
}

// 0493x6c: resident phase-geometry infrastructure.  It materializes one raw
// phase-fill field and one conservative filtered field on the device at every
// free-surface Q6 solve.  Neither field is consumed by the projection yet.
// Keeping this behind an experimental gate lets us measure the permanent
// two-grid-pass cost before the geometry becomes part of the production path.
bool cuda_q6_phase_geometry_resident_0493x6c_requested() {
    return truthy_0400(std::getenv("MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C"));
}

// 0493x6d: first consumer of the resident geometry.  Only in-domain faces
// separating the current Q6 carrier mask from an inactive cell are eligible.
// The pressure remains zero gauge at the reconstructed interface; gas pressure
// and surface tension are deliberately still absent from this stage.
bool cuda_q6_phase_geometry_cutface_0493x6d_requested() {
    return truthy_0400(std::getenv("MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D"));
}

// 0493x6e: diagnostic-only topology of the physical alpha=0.5 interface.
// Unlike x6d, this scan is independent of the carrier-mask boundary: every
// unique in-domain alpha=0.5 crossing is classified as active-active,
// active-inactive or inactive-inactive.  It is fused into the sparse x6c audit
// kernel, so it adds no production pass and does not alter Q6 physics.
bool cuda_q6_phase_interface_topology_0493x6e_requested() {
    return truthy_0400(std::getenv("MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E"));
}

// 0493x6f2 bounded phase geometry: raw occupancy is retained unbounded; the interface filter consumes clamp(raw,0,1).
// 0493x6f: phase-interface pressure stencil.  The physical pressure domain is
// reconstructed from the resident alpha=0.5 geometry while the historical
// occupancy mask remains a numerical carrier for particle data.  The x6f
// preparation pass materializes a pressure mask and east/north face
// coefficients once per Q6 solve, so the iterative CG path no longer evaluates
// alpha crossings, divisions or cut-face branches.  The interfacial pressure
// value is still zero in x6f; x6g will reuse the same stencil for p_g.
bool cuda_q6_phase_interface_stencil_0493x6f_requested() {
    return truthy_0400(std::getenv("MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F"));
}

// 0493x6g: first physical use of the x6f interface stencil.  The gas-side
// ideal-gas EOS provides the interfacial Dirichlet value while the matrix
// coefficients remain exactly those prepared by x6f.  The pressure reference
// is a pure gauge subtraction; the same face-value buffers are intended to
// receive p_g + sigma*kappa in the later capillary stage.
bool cuda_q6_phase_gas_pressure_0493x6g_requested() {
    return truthy_0400(std::getenv("MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G"));
}

// 0493x9a: passive capillary geometry.  Build outward normals and curvature
// from the already-qualified x6c alpha field, but do not feed either field to
// x6f/x6g or to particle velocities.  This isolates the only new numerical
// ingredient needed by a later Young--Laplace jump.
bool cuda_q6_phase_curvature_diagnostics_0493x9a_requested() {
    return truthy_0400(
        std::getenv("MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A"));
}

// 0493x9b: second passive estimator.  It deliberately owns a curvature-only
// geometry field distinct from the x6c physical alpha: one isotropic 3x3
// binomial pass reduces MPCD occupancy quantization, then Scharr 3x3
// derivatives build n and div(n).  Nothing from x9b enters x6f/x6g/RHS/B1.
bool cuda_q6_phase_curvature_diagnostics_0493x9b_requested() {
    return truthy_0400(
        std::getenv("MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B"));
}

// 0493x9c: passive smoothing-support qualification.  It keeps the x9b Scharr
// operator fixed and evaluates two additional alphaK supports (2 and 3 total
// binomial 3x3 passes).  The candidates are summary-cadence diagnostics only.
bool cuda_q6_phase_curvature_diagnostics_0493x9c_requested() {
    return truthy_0400(
        std::getenv("MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C"));
}

// 0493x9e: static-drop qualification diagnostics.  This gate is strictly
// observational: no geometry, RHS, pressure boundary value or particle state
// is modified.  It runs only at the ordinary Q6 summary cadence.
bool cuda_q6_static_drop_diagnostics_0493x9e_requested() {
    return truthy_0400(
        std::getenv("MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E"));
}

// 0493x9f: diagnostic-only ellipse/shape qualification layered on x9e.
// It adds no force, pressure term, geometry smoothing or particle update.
// The runner enables it together with x9e so pressure/curvature and shape
// histories share the same summary cadence.
bool cuda_q6_ellipse_diagnostics_0493x9f_requested() {
    return truthy_0400(
        std::getenv("MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F"));
}

// 0493x9b-audit2: diagnostic-only exclusion band used to separate free
// interface curvature from wall-intersection artefacts.  Periodic directions
// have no wall and therefore do not participate in the exclusion test.
int cuda_q6_phase_curvature_audit_wall_margin_0493x9b() {
    return std::max(0, env_int_0400(
        "MPCD_Q6_PHASE_CURVATURE_AUDIT_WALL_MARGIN_CELLS_0493X9B", 8));
}

// 0493x6h-B0: diagnostic-only localization of the divergence that remains
// after the face-projected Q6 correction has been applied to resident
// particles and redeposited.  The extra pass is summary-cadence only and is
// completely absent unless explicitly requested.
bool cuda_q6_postapply_region_diagnostics_0493x6h_b0_requested() {
    return truthy_0400(
        std::getenv("MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0"));
}

// 0493x6h-B1: reconstruct the free-surface Q6 correction as an affine
// face-compatible field at each resident particle instead of applying one
// cell-constant increment.  B1 is intentionally gated and initially limited
// to the single projected-species, fused force+Q6 free-surface path so the
// existing east/north face buffers can be consumed directly without adding
// persistent per-species storage or another particle pass.
bool cuda_q6_face_to_particle_rt0_0493x6h_b1_requested() {
    return truthy_0400(
        std::getenv("MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1"));
}

// 0493x7k: Q6-g-f production diagnostics run only at the first step and at
// summary cadence.  Failure diagnostics remain unconditional.  This is not a
// new runtime option: summaryEvery already defines the cadence at which the
// surrounding solver reports its state.
bool q6_g_f_diagnostics_this_step_0493x7k(
    const SimulationParams& params,
    std::uint64_t step) {
    const std::uint64_t every = static_cast<std::uint64_t>(
        std::max(1, params.summaryEvery));
    return step <= 1u || (step % every) == 0u;
}

enum class PhaseGasPressureMode0493x6g : int {
    Eos = 0,
    Constant = 1
};

PhaseGasPressureMode0493x6g phase_gas_pressure_mode_0493x6g() {
    const char* value = std::getenv("MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G");
    if (value == nullptr || *value == '\0' || std::strcmp(value, "eos") == 0 ||
        std::strcmp(value, "EOS") == 0) {
        return PhaseGasPressureMode0493x6g::Eos;
    }
    if (std::strcmp(value, "constant") == 0 || std::strcmp(value, "CONSTANT") == 0) {
        return PhaseGasPressureMode0493x6g::Constant;
    }
    throw std::runtime_error(
        std::string("0493x6g invalid MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G: ") + value);
}

const char* phase_gas_pressure_mode_name_0493x6g(PhaseGasPressureMode0493x6g mode) {
    return mode == PhaseGasPressureMode0493x6g::Constant ? "constant" : "eos";
}

// Small-cut-cell conditioning guard for the first active geometry test.  A
// smaller theta would make the Dirichlet diagonal factor 1/theta very large.
// Such faces keep the legacy half-cell factor rather than being clipped, so the
// fallback remains explicit and measurable.  This is not a user parameter.
constexpr double kPhaseCutFaceThetaMin0493x6d = 0.10;

// One explicit conservative diffusion step.  lambda <= 1/4 keeps the 2-D
// five-point update non-negative for non-negative input.  This fixed value is
// intentionally not a new user parameter during the scaffold stage.
constexpr double kPhaseGeometryFilterLambda0493x6c = 0.125;

struct Q6SegmentedIo0409 {
    int enabled = 0;
    int count = 0;
    int inletProfileCode = 0; // 0 uniform, 1 local Poiseuille Umax, 2 local Poiseuille Umean
    int passiveNeumannRightOutlet0493x8l = 0;
    int face[kOpenBoundaryMaxSegments]{}; // 0 left, 1 right, 2 bottom, 3 top
    int mode[kOpenBoundaryMaxSegments]{}; // 1 inlet, 2 outlet
    std::uint32_t type[kOpenBoundaryMaxSegments]{};
    double sMin[kOpenBoundaryMaxSegments]{};
    double sMax[kOpenBoundaryMaxSegments]{};
    double flux[kOpenBoundaryMaxSegments]{};
};

bool q6_open_fullface_0404_supported(const SimulationParams& params);
bool q6_open_segmented_0409_supported(const SimulationParams& params);

bool q6_static_wall_mode_0493x1(const std::string& mode) {
    return mode == "solid" || mode == "specular" || mode == "bounceback";
}

bool q6_closed_box_0493x1_supported(const SimulationParams& params) {
    return truthy_0400(std::getenv("MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1")) &&
           !is_x_periodic(params) && !is_y_periodic(params) &&
           q6_static_wall_mode_0493x1(params.bcLeft) &&
           q6_static_wall_mode_0493x1(params.bcRight) &&
           q6_static_wall_mode_0493x1(params.bcBottom) &&
           q6_static_wall_mode_0493x1(params.bcTop) &&
           params.bcLeft != "bounceback" && params.bcRight != "bounceback" &&
           params.bcBottom != "bounceback" && params.bcTop != "bounceback";
}

void check_cuda_0400(cudaError_t err, const char* where) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_q6_resident_0400 ") + where + ": " +
                                 cudaGetErrorString(err));
    }
}

double seconds_since_0400(const Clock0400::time_point& t0) {
    return std::chrono::duration<double>(Clock0400::now() - t0).count();
}

__device__ void q6_force_acceleration_0493x4b(
    const double x,
    const double y,
    const double Lx,
    const double Ly,
    const double bodyAx,
    const double bodyAy,
    const int tgEnable,
    const double tgAmplitude,
    const int tgModeX,
    const int tgModeY,
    double* ax,
    double* ay) {
    double localAx = bodyAx;
    double localAy = bodyAy;
    if (tgEnable && tgAmplitude > 0.0) {
        constexpr double pi = 3.141592653589793238462643383279502884;
        const double kx = 2.0 * pi * static_cast<double>(tgModeX) / Lx;
        const double ky = 2.0 * pi * static_cast<double>(tgModeY) / Ly;
        localAx += tgAmplitude * sin(kx * x) * cos(ky * y);
        localAy -= tgAmplitude * cos(kx * x) * sin(ky * y);
    }
    *ax = localAx;
    *ay = localAy;
}

__global__ void q6_force_kick_0493x3(
    CudaParticleDeviceView particles,
    const std::uint64_t nParticles,
    const double dt,
    const double Lx,
    const double Ly,
    const double bodyAx,
    const double bodyAy,
    const int tgEnable,
    const double tgAmplitude,
    const int tgModeX,
    const int tgModeY,
    const unsigned char fluidRole) {
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) *
                                static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= nParticles || particles.role[i] != fluidRole) return;

    double ax = bodyAx;
    double ay = bodyAy;
    if (tgEnable && tgAmplitude > 0.0) {
        constexpr double pi = 3.141592653589793238462643383279502884;
        const double kx = 2.0 * pi * static_cast<double>(tgModeX) / Lx;
        const double ky = 2.0 * pi * static_cast<double>(tgModeY) / Ly;
        const double x = particles.x[i];
        const double y = particles.y[i];
        ax += tgAmplitude * sin(kx * x) * cos(ky * y);
        ay -= tgAmplitude * cos(kx * x) * sin(ky * y);
    }
    particles.vx[i] += ax * dt;
    particles.vy[i] += ay * dt;
}

std::string q6_boundary_family_0491g(const SimulationParams& params) {
    if (q6_open_segmented_0409_supported(params)) return "open_segmented";
    if (q6_open_fullface_0404_supported(params)) return "open_fullface";
    if (is_x_periodic(params) && is_y_periodic(params)) return "periodic";
    if (is_x_periodic(params) && !is_y_periodic(params)) return "channel_wall";
    if (q6_closed_box_0493x1_supported(params)) return "closed_box";
    return "other";
}

void append_species_q6_resident_audit_0491e(
    const SimulationParams& params,
    int step,
    double time,
    int speciesCount,
    const CudaQ6Resident0400Diagnostics& diag) {
    if (!params.speciesQ6Enable || params.outputDir.empty()) return;
    const std::filesystem::path path =
        std::filesystem::path(params.outputDir) / "cuda_species_q6_0491.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error("0491e failed to open species-Q6 resident audit CSV: " +
                                 path.string());
    }
    if (header) {
        out << "step,time,mode,sensitivity,speciesCount,boundaryFamily,"
               "openBoundaryEnabled,darcyBrinkmanEnable,"
               "species_q6_device_resident,species_q6_host_cell_array_entries,"
               "species_q6_weight_h2d,species_q6_full_state_download,"
               "species_q6_cpu_fallback,species_q6_remaining_cpu_scope,"
               "species_q6_allocated_bytes,species_q6_allocation_calls,"
               "species_q6_metadata_h2d_bytes,"
               "species_q6_deposit_seconds,species_q6_weight_seconds,"
               "species_q6_particle_apply_seconds,"
               "q6Applied,q6Converged,q6Iterations,barycentricResidualMaxAbs,"
               "barycentricResidualMaxScaled,"
               "depositSeconds,solveSeconds,applySeconds,totalSeconds\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ','
        << '"' << params.speciesQ6Mode << '"' << ','
        << params.speciesQ6Sensitivity << ','
        << speciesCount << ','
        << '"' << q6_boundary_family_0491g(params) << '"' << ','
        << (diag.openBoundaryEnabled ? 1 : 0) << ','
        << (params.darcyBrinkmanEnable ? 1 : 0) << ','
        << 1 << ','  // species-Q6 deposit, weights and correction are device-resident.
        << 0 << ','  // no host cell-species array is materialized by this path.
        << 0 << ','  // weights are derived from resident cell-species masses on device.
        << 0 << ','  // this path never downloads the full particle state.
        << 0 << ','
        << "\"none\","
        << diag.speciesQ6AllocatedBytes << ','
        << diag.speciesQ6AllocationCalls << ','
        << diag.speciesQ6MetadataH2DBytes << ','
        << diag.speciesQ6DepositSeconds << ','
        << diag.speciesQ6WeightSeconds << ','
        << diag.speciesQ6ParticleApplySeconds << ','
        << (diag.applied ? 1 : 0) << ','
        << (diag.converged ? 1 : 0) << ','
        << diag.iterations << ','
        << diag.speciesQ6BarycentricResidualMaxAbs << ','
        << diag.speciesQ6BarycentricResidualMaxScaled << ','
        << diag.depositSeconds << ','
        << diag.solveSeconds << ','
        << diag.applySeconds << ','
        << diag.totalSeconds << '\n';
}

constexpr int kQ6PostApplyRegionCount0493x6hB0 = 6;

enum Q6PostApplyRegion0493x6hB0 : int {
    Q6PostApplyBulk0493x6hB0 = 0,
    Q6PostApplyInterface0493x6hB0 = 1,
    Q6PostApplyWall0493x6hB0 = 2,
    Q6PostApplyWallInterface0493x6hB0 = 3,
    Q6PostApplyCorner0493x6hB0 = 4,
    Q6PostApplyCornerInterface0493x6hB0 = 5,
};

struct Q6PostApplyRegionAccumulator0493x6hB0 {
    unsigned long long cells[kQ6PostApplyRegionCount0493x6hB0]{};
    double divSq[kQ6PostApplyRegionCount0493x6hB0]{};
    // Positive IEEE-754 doubles preserve ordering in their bit pattern, so a
    // native atomicMax on these bits gives an inexpensive per-region |div|max.
    unsigned long long divMaxAbsBits[kQ6PostApplyRegionCount0493x6hB0]{};
};

// 0493x7a: tiny resident accumulator for the historical weak virial/EOS
// density-restoring kick.  Only active-liquid mass and momentum sums are needed
// every step for the exact global momentum correction.  The remaining fields
// are filled only on audit steps.
struct VirialDensityAccumulator0493x7a {
    unsigned long long pressureCells = 0ull;
    unsigned long long activeBulkCells = 0ull;
    double activeMass = 0.0;
    double momentumX = 0.0;
    double momentumY = 0.0;
    double fillDefectSq = 0.0;
    double pressureSq = 0.0;
    double kickMassSq = 0.0;
};

// 0493x7d-v2-fix2 / 0493x7q: full-domain B1 periodic momentum closure.
// x7d-v2-fix2 stores the mass-weighted cell-centred correction used as a cheap
// first k=0 estimate.  x7q additionally reduces the correction actually
// reconstructed at particle locations and removes its remaining k=0 mode in a
// second resident particle pass.  The x7q fields are touched only for
// full-domain B1 solves with at least one periodic direction; partial-domain
// free-surface (dam-break) launches keep the historical B1 kernel unchanged.
struct Q6PeriodicMomentumAccumulator0493x7dv2fix2 {
    double activeMass = 0.0;
    double momentumX = 0.0;
    double momentumY = 0.0;
    double appliedMass0493x7q = 0.0;
    double residualVelocityX0493x7q = 0.0;
    double residualVelocityY0493x7q = 0.0;
};

// 0493x7j: O(1) state shared by all blocks of the cooperative masked CG.
// Per-block reduction scratch continues to reuse partial0/partial1.
struct Q6GfResidentCgState0493x7j {
    double rhsSum = 0.0;
    double densityRelaxationTargetDivMeanRemoved0493x8t = 0.0;
    double divBeforeSq = 0.0;
    double divBeforeMaxAbs = 0.0;
    double rr = 0.0;
    double rhsNormSafe = 1.0;
    double residualRel = 0.0;
    double reduce0 = 0.0;
    double reduce1 = 0.0;
    int iterations = 0;
    int status = 0; // 1 converged, 0 max-iteration/not-yet, -1 non-positive pAp
};

const char* q6_postapply_region_name_0493x6h_b0(int region) {
    switch (region) {
        case Q6PostApplyBulk0493x6hB0: return "bulk";
        case Q6PostApplyInterface0493x6hB0: return "interface";
        case Q6PostApplyWall0493x6hB0: return "wall";
        case Q6PostApplyWallInterface0493x6hB0: return "wall_interface";
        case Q6PostApplyCorner0493x6hB0: return "corner";
        case Q6PostApplyCornerInterface0493x6hB0: return "corner_interface";
        default: return "unknown";
    }
}

double q6_positive_double_from_bits_0493x6h_b0(unsigned long long bits) {
    double value = 0.0;
    static_assert(sizeof(value) == sizeof(bits), "unexpected double size");
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}

struct IndependentMaskedSpeciesAudit0493w5 {
    int speciesIndex = -1;
    std::uint32_t type = 0u;
    double strength = 0.0;
    std::uint64_t activeCells = 0u;
    std::uint64_t correctedParticles = 0u;
    bool fullDomain = false;
    bool converged = true;
    int iterations = 0;
    double residualRel = 0.0;
    double divBeforeRms = 0.0;
    double divBeforeMaxAbs = 0.0;
    // Compatibility aliases retained for the original 0493w5 CSV schema.
    // They continue to denote the divergence of the projected auxiliary face flux.
    double divAfterRms = 0.0;
    double divAfterMaxAbs = 0.0;
    double divAfterProjectedFaceFluxRms = 0.0;
    double divAfterProjectedFaceFluxMaxAbs = 0.0;
    // 0493w6: divergence rebuilt from the post-application, per-species
    // cell velocity deposited directly from the resident particle state.
    double divAfterAppliedCellVelocityRms = 0.0;
    double divAfterAppliedCellVelocityMaxAbs = 0.0;
    double correctionRms = 0.0;
    double correctionMaxAbs = 0.0;
    double momentumX = 0.0;
    double momentumY = 0.0;
    // 0493x7c: RMS of the non-zero divergence target imposed by the density
    // relaxation RHS.  divAfterProjectedFaceFlux* remains the residual with
    // respect to the active projection constraint; for beta=0 this is exactly
    // the historical projected divergence.
    double densityRelaxationTargetDivRms = 0.0;
    // 0493x8t: raw spatial mean removed from the x7d density-divergence
    // target when a full-domain x8r pressure outlet is active.
    double densityRelaxationTargetDivMeanRemoved0493x8t = 0.0;
    // 0493x7j: audit only; the production default is one cooperative,
    // device-resident CG kernel for the complete Q6-g-f solve.
    int residentCg0493x7j = 0;
    int residentCgBlocks0493x7j = 0;
};

void append_independent_masked_species_audit_0493w5(
    const SimulationParams& params,
    int step,
    double time,
    const std::vector<IndependentMaskedSpeciesAudit0493w5>& rows) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_species_q6_independent_masked_0493w5.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493w5 failed to open independent-masked species Q6 audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,speciesIndex,type,q6Strength,minOccupancyFraction,"
               "activeCells,fullDomain,correctedParticles,converged,iterations,"
               "residualRel,divBeforeRms,divBeforeMaxAbs,divAfterRms,"
               "divAfterMaxAbs,divAfterProjectedFaceFluxRms,"
               "divAfterProjectedFaceFluxMaxAbs,divAfterAppliedCellVelocityRms,"
               "divAfterAppliedCellVelocityMaxAbs,correctionRms,correctionMaxAbs,"
               "momentumX,momentumY,q6DensityRelaxationBeta,"
               "q6DensityRelaxationTime,densityRelaxationTargetDivRms,"
               "densityRelaxationTargetDivMeanRemoved0493x8t,"
               "residentCg0493x7j,residentCgBlocks0493x7j\n";
    }
    for (const IndependentMaskedSpeciesAudit0493w5& r : rows) {
        out << std::setprecision(17)
            << step << ',' << time << ',' << r.speciesIndex << ',' << r.type << ','
            << r.strength << ',' << params.speciesQ6MinOccupancyFraction << ','
            << r.activeCells << ',' << (r.fullDomain ? 1 : 0) << ','
            << r.correctedParticles << ',' << (r.converged ? 1 : 0) << ','
            << r.iterations << ',' << r.residualRel << ','
            << r.divBeforeRms << ',' << r.divBeforeMaxAbs << ','
            << r.divAfterRms << ',' << r.divAfterMaxAbs << ','
            << r.divAfterProjectedFaceFluxRms << ','
            << r.divAfterProjectedFaceFluxMaxAbs << ','
            << r.divAfterAppliedCellVelocityRms << ','
            << r.divAfterAppliedCellVelocityMaxAbs << ','
            << r.correctionRms << ',' << r.correctionMaxAbs << ','
            << r.momentumX << ',' << r.momentumY << ',';
        const double densityRelaxationBeta0493x7d =
            params.q6DensityRelaxationTime > 0.0
                ? params.dt / params.q6DensityRelaxationTime
                : params.q6DensityRelaxationBeta;
        out << densityRelaxationBeta0493x7d << ','
            << (densityRelaxationBeta0493x7d > 0.0
                    ? params.dt / densityRelaxationBeta0493x7d
                    : 0.0) << ','
            << r.densityRelaxationTargetDivRms << ','
            << r.densityRelaxationTargetDivMeanRemoved0493x8t << ','
            << r.residentCg0493x7j << ',' << r.residentCgBlocks0493x7j << '\n';
    }
}

void append_q6_postapply_region_audit_0493x6h_b0(
    const SimulationParams& params,
    int step,
    double time,
    const IndependentMaskedSpeciesAudit0493w5& audit,
    const Q6PostApplyRegionAccumulator0493x6hB0& accum,
    bool interfaceGeometryAvailable,
    double diagnosticSeconds) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_q6_postapply_regions_0493x6h_b0.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x6h-B0 failed to open post-apply region audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,speciesIndex,type,regionCode,region,regionCells,"
               "carrierCells,q6ReportedActiveCells,divSq,divRms,divMaxAbs,"
               "divSqFraction,q6AppliedRms,q6AppliedRmsReconstructed,"
               "interfaceGeometryAvailable,diagnosticSeconds\n";
    }
    unsigned long long carrierCells = 0ull;
    double totalDivSq = 0.0;
    for (int r = 0; r < kQ6PostApplyRegionCount0493x6hB0; ++r) {
        carrierCells += accum.cells[r];
        totalDivSq += accum.divSq[r];
    }
    const double reportedDenom = static_cast<double>(
        std::max<std::uint64_t>(1u, audit.activeCells));
    const double reconstructed = std::sqrt(std::max(0.0, totalDivSq) / reportedDenom);
    for (int r = 0; r < kQ6PostApplyRegionCount0493x6hB0; ++r) {
        const double regionRms = accum.cells[r] > 0ull
            ? std::sqrt(std::max(0.0, accum.divSq[r]) /
                        static_cast<double>(accum.cells[r]))
            : 0.0;
        const double fraction = totalDivSq > 0.0 ? accum.divSq[r] / totalDivSq : 0.0;
        out << std::setprecision(17)
            << step << ',' << time << ',' << audit.speciesIndex << ',' << audit.type << ','
            << r << ',' << q6_postapply_region_name_0493x6h_b0(r) << ','
            << accum.cells[r] << ',' << carrierCells << ',' << audit.activeCells << ','
            << accum.divSq[r] << ',' << regionRms << ','
            << q6_positive_double_from_bits_0493x6h_b0(accum.divMaxAbsBits[r]) << ','
            << fraction << ',' << audit.divAfterAppliedCellVelocityRms << ','
            << reconstructed << ',' << (interfaceGeometryAvailable ? 1 : 0) << ','
            << diagnosticSeconds << '\n';
    }
}

// 0493x7a audit is intentionally sparse (step 1 and summary cadence only).
// Execution never depends on this host copy: the momentum correction consumes
// the resident accumulator directly on device.
void append_virial_density_audit_0493x7a(
    const SimulationParams& params,
    int step,
    double time,
    double dx,
    double dy,
    const VirialDensityAccumulator0493x7a& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_virial_density_0493x7a.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x7a failed to open resident virial density audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,kVirial,betaEOS,momentumCorrectionEnable,"
               "pressureCells,activeBulkCells,activeMass,fillDefectRms,"
               "virialPressureRms,rawKickMassWeightedRms,"
               "correctedKickMassWeightedRms,momentumResidualBefore,"
               "momentumCorrectionVx,momentumCorrectionVy,"
               "effectiveVirialSpeed,dx,dy,virialCFLx,virialCFLy,"
               "pressureDefinition,gradientDefinition,stiffnessUnits,scope\n";
    }
    const double n = static_cast<double>(std::max<unsigned long long>(
        1ull, a.activeBulkCells));
    const double fillRms = std::sqrt(std::max(0.0, a.fillDefectSq) / n);
    const double pressureRms = std::sqrt(std::max(0.0, a.pressureSq) / n);
    const double mass = std::max(0.0, a.activeMass);
    const double rawKickRms = mass > 0.0
        ? std::sqrt(std::max(0.0, a.kickMassSq) / mass) : 0.0;
    const double cvx =
        params.virialMomentumCorrectionEnable && mass > 0.0
            ? a.momentumX / mass : 0.0;
    const double cvy =
        params.virialMomentumCorrectionEnable && mass > 0.0
            ? a.momentumY / mass : 0.0;
    const double correctedKickSq = params.virialMomentumCorrectionEnable &&
                                   mass > 0.0
        ? std::max(0.0, a.kickMassSq -
            (a.momentumX * a.momentumX + a.momentumY * a.momentumY) / mass)
        : std::max(0.0, a.kickMassSq);
    const double correctedKickRms = mass > 0.0
        ? std::sqrt(correctedKickSq / mass) : 0.0;
    const double momentumResidual =
        std::sqrt(a.momentumX * a.momentumX + a.momentumY * a.momentumY);
    // 0493x7b: expose the continuum stiffness semantics and the explicit
    // virial Courant numbers.  These are diagnostics only; x7b intentionally
    // leaves the x7a/K32 numerical update bit-for-bit unchanged when the same
    // parameters are supplied.
    const double effectiveVirialSpeed =
        std::sqrt(std::max(0.0, params.betaEOS * params.kVirial));
    const double virialCFLx = dx > 0.0
        ? effectiveVirialSpeed * params.dt / dx : 0.0;
    const double virialCFLy = dy > 0.0
        ? effectiveVirialSpeed * params.dt / dy : 0.0;

    out << std::setprecision(17)
        << step << ',' << time << ',' << params.kVirial << ',' << params.betaEOS
        << ',' << (params.virialMomentumCorrectionEnable ? 1 : 0) << ','
        << a.pressureCells << ',' << a.activeBulkCells << ',' << a.activeMass << ','
        << fillRms << ',' << pressureRms << ',' << rawKickRms << ','
        << correctedKickRms << ',' << momentumResidual << ','
        << cvx << ',' << cvy << ','
        << effectiveVirialSpeed << ',' << dx << ',' << dy << ','
        << virialCFLx << ',' << virialCFLy << ','
        << "Pvir/rhoRef=Kvirial*(rawFill-1)" << ','
        << "physical_FV_gradient_1_over_dx_dy" << ','
        << "code_velocity_squared" << ','
        << "liquid_bulk_only_no_interface" << '\n';
}

struct PhaseInterfacePressureAudit0493x6a {
    int projectedSpeciesIndex = -1;
    std::uint32_t projectedType = 0u;
    int gasSpeciesCount = 0;
    std::uint64_t interfaceFaces = 0u;
    double projectedLiquidReferenceCellMass = 0.0;
    double cellArea = 0.0;
    double meanGasParticlesPerExteriorFace = 0.0;
    double pressureEOSMean = 0.0;
    double pressureEOSStd = 0.0;
    double pressureEOSMax = 0.0;
    double pressurePotentialMean = 0.0;
    double pressurePotentialStd = 0.0;
    double pressurePotentialMax = 0.0;
};

void append_phase_interface_pressure_audit_0493x6a(
    const SimulationParams& params,
    int step,
    double time,
    const PhaseInterfacePressureAudit0493x6a& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_interface_pressure_0493x6a.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x6a failed to open phase-interface pressure audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,gasSpeciesCount,"
               "projectedLiquidReferenceCellMass,cellArea,kBT,dt,interfaceFaces,"
               "meanGasParticlesPerExteriorFace,pressureEOSMean,pressureEOSStd,"
               "pressureEOSMax,pressurePotentialMean,pressurePotentialStd,"
               "pressurePotentialMax,pressurePotentialDefinition\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ','
        << a.projectedType << ',' << a.gasSpeciesCount << ','
        << a.projectedLiquidReferenceCellMass << ',' << a.cellArea << ','
        << params.kBT << ',' << params.dt << ',' << a.interfaceFaces << ','
        << a.meanGasParticlesPerExteriorFace << ','
        << a.pressureEOSMean << ',' << a.pressureEOSStd << ','
        << a.pressureEOSMax << ',' << a.pressurePotentialMean << ','
        << a.pressurePotentialStd << ',' << a.pressurePotentialMax << ','
        << "phi=dt*p/rho_liquid_ref" << '\n';
}

struct PhaseInterfaceGeometryAudit0493x6b {
    int projectedSpeciesIndex = -1;
    std::uint32_t projectedType = 0u;
    int liquidPhaseSpeciesCount = 0;
    std::uint64_t maskActiveCells = 0u;
    std::uint64_t phaseFillActiveCells = 0u;
    std::uint64_t maskPhaseMismatchCells = 0u;
    std::uint64_t interfaceFaces = 0u;
    double liquidPhaseReferenceCellMass = 0.0;
    double supportIsoFill = 0.0;
    double insideFillMean = 0.0;
    double outsideFillMean = 0.0;
    double supportThetaValidFraction = 0.0;
    double supportThetaMean = 0.0;
    double supportThetaStd = 0.0;
    double supportThetaMidpointRms = 0.0;
    double supportThetaNearCellFraction = 0.0;
    double supportThetaNearExteriorFraction = 0.0;
    double halfIsoBracketFraction = 0.0;
    double halfIsoThetaMean = 0.0;
    double halfIsoThetaStd = 0.0;
    double normalValidFraction = 0.0;
    double normalOutwardFraction = 0.0;
    double normalFaceAlignmentMean = 0.0;
    double diagnosticSeconds = 0.0;
};

void append_phase_interface_geometry_audit_0493x6b(
    const SimulationParams& params,
    int step,
    double time,
    const PhaseInterfaceGeometryAudit0493x6b& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_interface_geometry_0493x6b.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x6b failed to open phase-interface geometry audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,liquidPhaseSpeciesCount,"
               "liquidPhaseReferenceCellMass,supportIsoFill,maskActiveCells,"
               "phaseFillActiveCells,maskPhaseMismatchCells,interfaceFaces,"
               "insideFillMean,outsideFillMean,supportThetaValidFraction,"
               "supportThetaMean,supportThetaStd,supportThetaMidpointRms,"
               "supportThetaNearCellFraction,supportThetaNearExteriorFraction,"
               "halfIsoBracketFraction,halfIsoThetaMean,halfIsoThetaStd,"
               "normalValidFraction,normalOutwardFraction,normalFaceAlignmentMean,"
               "diagnosticSeconds,geometryDefinition\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ','
        << a.projectedType << ',' << a.liquidPhaseSpeciesCount << ','
        << a.liquidPhaseReferenceCellMass << ',' << a.supportIsoFill << ','
        << a.maskActiveCells << ',' << a.phaseFillActiveCells << ','
        << a.maskPhaseMismatchCells << ',' << a.interfaceFaces << ','
        << a.insideFillMean << ',' << a.outsideFillMean << ','
        << a.supportThetaValidFraction << ',' << a.supportThetaMean << ','
        << a.supportThetaStd << ',' << a.supportThetaMidpointRms << ','
        << a.supportThetaNearCellFraction << ','
        << a.supportThetaNearExteriorFraction << ','
        << a.halfIsoBracketFraction << ',' << a.halfIsoThetaMean << ','
        << a.halfIsoThetaStd << ',' << a.normalValidFraction << ','
        << a.normalOutwardFraction << ',' << a.normalFaceAlignmentMean << ','
        << a.diagnosticSeconds << ','
        << "phaseFill=sum_liquid_mass/sum_liquid_reference_mass;"
           "theta=(fill_in-iso)/(fill_in-fill_out);halfIso=0.5" << '\n';
}

struct PhaseGeometryResidentAudit0493x6c {
    int projectedSpeciesIndex = -1;
    std::uint32_t projectedType = 0u;
    int liquidPhaseSpeciesCount = 0;
    std::uint64_t numCells = 0u;
    std::uint64_t maskFilteredMismatchCells = 0u;
    std::uint64_t interfaceFaces = 0u;
    double liquidPhaseReferenceCellMass = 0.0;
    double filterLambda = 0.0;
    double rawFillSum = 0.0;
    double boundedGeometrySourceSum = 0.0;
    std::uint64_t boundedGeometryClippedCells = 0u;
    double filteredFillSum = 0.0;
    double conservationRelativeError = 0.0;
    double filterDeltaRms = 0.0;
    double halfIsoBracketFraction = 0.0;
    double halfIsoThetaMean = 0.0;
    double halfIsoThetaStd = 0.0;
    double normalValidFraction = 0.0;
    double normalOutwardFraction = 0.0;
    double normalFaceAlignmentMean = 0.0;
    double rawBuildSeconds = 0.0;
    double filterSeconds = 0.0;
    double auditKernelSeconds = 0.0;
    std::uint64_t residentBytes = 0u;
    int cutFaceGeometryEnabled = 0;
    std::uint64_t cutFaceGeometricFaces = 0u;
    std::uint64_t cutFaceLegacyFallbackFaces = 0u;
    std::uint64_t cutFaceSmallThetaFallbackFaces = 0u;
    double cutFaceThetaGuard = 0.0;
    double cutFaceThetaMin = 0.0;
    double cutFaceThetaMean = 0.0;
    double cutFaceThetaMax = 0.0;
    int phaseInterfaceTopologyEnabled = 0;
    std::uint64_t alphaHalfCrossingFaces = 0u;
    std::uint64_t alphaHalfCrossingActiveActiveFaces = 0u;
    std::uint64_t alphaHalfCrossingActiveInactiveFaces = 0u;
    std::uint64_t alphaHalfCrossingInactiveInactiveFaces = 0u;
    std::uint64_t alphaHalfCrossingAIActiveLiquidSideFaces = 0u;
    std::uint64_t alphaHalfCrossingAIActiveExteriorSideFaces = 0u;
    double alphaHalfThetaMin = 0.0;
    double alphaHalfThetaMean = 0.0;
    double alphaHalfThetaStd = 0.0;
    double alphaHalfThetaMax = 0.0;
};

void append_phase_geometry_resident_audit_0493x6c(
    const SimulationParams& params,
    int step,
    double time,
    const PhaseGeometryResidentAudit0493x6c& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_geometry_resident_0493x6c.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x6c failed to open resident phase-geometry audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,liquidPhaseSpeciesCount,"
               "liquidPhaseReferenceCellMass,numCells,filterLambda,rawFillSum,"
               "boundedGeometrySourceSum,boundedGeometryClippedCells,"
               "filteredFillSum,conservationRelativeError,filterDeltaRms,"
               "maskFilteredMismatchCells,interfaceFaces,halfIsoBracketFraction,"
               "halfIsoThetaMean,halfIsoThetaStd,normalValidFraction,"
               "normalOutwardFraction,normalFaceAlignmentMean,rawBuildSeconds,"
               "filterSeconds,auditKernelSeconds,residentBytes,cutFaceGeometryEnabled,"
               "cutFaceGeometricFaces,cutFaceLegacyFallbackFaces,"
               "cutFaceSmallThetaFallbackFaces,cutFaceThetaGuard,cutFaceThetaMin,"
               "cutFaceThetaMean,cutFaceThetaMax,phaseInterfaceTopologyEnabled,"
               "alphaHalfCrossingFaces,alphaHalfCrossingActiveActiveFaces,"
               "alphaHalfCrossingActiveInactiveFaces,"
               "alphaHalfCrossingInactiveInactiveFaces,"
               "alphaHalfCrossingAIActiveLiquidSideFaces,"
               "alphaHalfCrossingAIActiveExteriorSideFaces,alphaHalfThetaMin,"
               "alphaHalfThetaMean,alphaHalfThetaStd,alphaHalfThetaMax,"
               "geometryDefinition\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ','
        << a.projectedType << ',' << a.liquidPhaseSpeciesCount << ','
        << a.liquidPhaseReferenceCellMass << ',' << a.numCells << ','
        << a.filterLambda << ',' << a.rawFillSum << ','
        << a.boundedGeometrySourceSum << ',' << a.boundedGeometryClippedCells << ','
        << a.filteredFillSum << ',' << a.conservationRelativeError << ','
        << a.filterDeltaRms << ','
        << a.maskFilteredMismatchCells << ',' << a.interfaceFaces << ','
        << a.halfIsoBracketFraction << ',' << a.halfIsoThetaMean << ','
        << a.halfIsoThetaStd << ',' << a.normalValidFraction << ','
        << a.normalOutwardFraction << ',' << a.normalFaceAlignmentMean << ','
        << a.rawBuildSeconds << ',' << a.filterSeconds << ','
        << a.auditKernelSeconds << ',' << a.residentBytes << ','
        << a.cutFaceGeometryEnabled << ',' << a.cutFaceGeometricFaces << ','
        << a.cutFaceLegacyFallbackFaces << ','
        << a.cutFaceSmallThetaFallbackFaces << ',' << a.cutFaceThetaGuard << ','
        << a.cutFaceThetaMin << ',' << a.cutFaceThetaMean << ','
        << a.cutFaceThetaMax << ',' << a.phaseInterfaceTopologyEnabled << ','
        << a.alphaHalfCrossingFaces << ','
        << a.alphaHalfCrossingActiveActiveFaces << ','
        << a.alphaHalfCrossingActiveInactiveFaces << ','
        << a.alphaHalfCrossingInactiveInactiveFaces << ','
        << a.alphaHalfCrossingAIActiveLiquidSideFaces << ','
        << a.alphaHalfCrossingAIActiveExteriorSideFaces << ','
        << a.alphaHalfThetaMin << ',' << a.alphaHalfThetaMean << ','
        << a.alphaHalfThetaStd << ',' << a.alphaHalfThetaMax << ','
        << "raw=sum_phaseA_mass/sum_phaseA_reference_mass;"
           "geom0=clamp01(raw);"
           "alpha=geom0+lambda*sum_face_neighbours(geom0_nb-geom0);"
           "no_flux_at_nonperiodic_domain_boundary;halfIso=0.5" << '\n';
}


struct PhaseCurvatureAudit0493x9a {
    int projectedSpeciesIndex = -1;
    std::uint32_t projectedType = 0u;
    std::uint64_t numCells = 0u;
    std::uint64_t crossingFaces = 0u;
    std::uint64_t validCurvatureFaces = 0u;
    std::uint64_t outwardNormalFaces = 0u;
    std::uint64_t positiveCurvatureFaces = 0u;
    std::uint64_t negativeCurvatureFaces = 0u;
    double validFraction = 0.0;
    double normalOutwardFraction = 0.0;
    double normalFaceAlignmentMean = 0.0;
    double curvatureMean = 0.0;
    double curvatureRms = 0.0;
    double curvatureStd = 0.0;
    double curvatureAbsMean = 0.0;
    double curvatureAbsMax = 0.0;
    int wallMarginCells = 0;
    std::uint64_t interiorCrossingFaces = 0u;
    std::uint64_t interiorValidCurvatureFaces = 0u;
    double interiorCurvatureMean = 0.0;
    double interiorCurvatureRms = 0.0;
    double interiorCurvatureStd = 0.0;
    double interiorCurvatureAbsMean = 0.0;
    double interiorCurvatureAbsMax = 0.0;
    std::uint64_t nearWallCrossingFaces = 0u;
    std::uint64_t nearWallValidCurvatureFaces = 0u;
    double nearWallCurvatureMean = 0.0;
    double nearWallCurvatureRms = 0.0;
    double nearWallCurvatureStd = 0.0;
    double nearWallCurvatureAbsMean = 0.0;
    double nearWallCurvatureAbsMax = 0.0;
    double normalBuildSeconds = 0.0;
    double curvatureBuildSeconds = 0.0;
    double faceAuditSeconds = 0.0;
    std::uint64_t residentBytes = 0u;
};

void append_phase_curvature_audit_0493x9a(
    const SimulationParams& params,
    int step,
    double time,
    const PhaseCurvatureAudit0493x9a& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_curvature_0493x9a.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9a failed to open passive curvature audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,numCells,"
               "crossingFaces,validCurvatureFaces,outwardNormalFaces,"
               "positiveCurvatureFaces,negativeCurvatureFaces,validFraction,"
               "normalOutwardFraction,normalFaceAlignmentMean,curvatureMean,"
               "curvatureRms,curvatureStd,curvatureAbsMean,curvatureAbsMax,"
               "wallMarginCells,interiorCrossingFaces,interiorValidCurvatureFaces,"
               "interiorCurvatureMean,interiorCurvatureRms,interiorCurvatureStd,"
               "interiorCurvatureAbsMean,interiorCurvatureAbsMax,"
               "nearWallCrossingFaces,nearWallValidCurvatureFaces,"
               "nearWallCurvatureMean,nearWallCurvatureRms,nearWallCurvatureStd,"
               "nearWallCurvatureAbsMean,nearWallCurvatureAbsMax,"
               "normalBuildSeconds,curvatureBuildSeconds,faceAuditSeconds,"
               "residentBytes,curvatureDefinition\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ','
        << a.projectedType << ',' << a.numCells << ',' << a.crossingFaces << ','
        << a.validCurvatureFaces << ',' << a.outwardNormalFaces << ','
        << a.positiveCurvatureFaces << ',' << a.negativeCurvatureFaces << ','
        << a.validFraction << ',' << a.normalOutwardFraction << ','
        << a.normalFaceAlignmentMean << ',' << a.curvatureMean << ','
        << a.curvatureRms << ',' << a.curvatureStd << ','
        << a.curvatureAbsMean << ',' << a.curvatureAbsMax << ','
        << a.wallMarginCells << ',' << a.interiorCrossingFaces << ','
        << a.interiorValidCurvatureFaces << ',' << a.interiorCurvatureMean << ','
        << a.interiorCurvatureRms << ',' << a.interiorCurvatureStd << ','
        << a.interiorCurvatureAbsMean << ',' << a.interiorCurvatureAbsMax << ','
        << a.nearWallCrossingFaces << ',' << a.nearWallValidCurvatureFaces << ','
        << a.nearWallCurvatureMean << ',' << a.nearWallCurvatureRms << ','
        << a.nearWallCurvatureStd << ',' << a.nearWallCurvatureAbsMean << ','
        << a.nearWallCurvatureAbsMax << ',' << a.normalBuildSeconds << ','
        << a.curvatureBuildSeconds << ',' << a.faceAuditSeconds << ','
        << a.residentBytes << ','
        << "n=-grad(alpha)/|grad(alpha)|;kappa=div(n);"
           "kappaGamma=linear_cell_interpolation_at_alpha0.5;passive_only"
        << '\n';
}

void append_phase_curvature_audit_0493x9b(
    const SimulationParams& params,
    int step,
    double time,
    const PhaseCurvatureAudit0493x9a& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_curvature_0493x9b.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9b failed to open passive curvature audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,numCells,"
               "crossingFaces,validCurvatureFaces,outwardNormalFaces,"
               "positiveCurvatureFaces,negativeCurvatureFaces,validFraction,"
               "normalOutwardFraction,normalFaceAlignmentMean,curvatureMean,"
               "curvatureRms,curvatureStd,curvatureAbsMean,curvatureAbsMax,"
               "wallMarginCells,interiorCrossingFaces,interiorValidCurvatureFaces,"
               "interiorCurvatureMean,interiorCurvatureRms,interiorCurvatureStd,"
               "interiorCurvatureAbsMean,interiorCurvatureAbsMax,"
               "nearWallCrossingFaces,nearWallValidCurvatureFaces,"
               "nearWallCurvatureMean,nearWallCurvatureRms,nearWallCurvatureStd,"
               "nearWallCurvatureAbsMean,nearWallCurvatureAbsMax,"
               "normalBuildSeconds,curvatureBuildSeconds,faceAuditSeconds,"
               "residentBytes,curvatureDefinition\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ','
        << a.projectedType << ',' << a.numCells << ',' << a.crossingFaces << ','
        << a.validCurvatureFaces << ',' << a.outwardNormalFaces << ','
        << a.positiveCurvatureFaces << ',' << a.negativeCurvatureFaces << ','
        << a.validFraction << ',' << a.normalOutwardFraction << ','
        << a.normalFaceAlignmentMean << ',' << a.curvatureMean << ','
        << a.curvatureRms << ',' << a.curvatureStd << ','
        << a.curvatureAbsMean << ',' << a.curvatureAbsMax << ','
        << a.wallMarginCells << ',' << a.interiorCrossingFaces << ','
        << a.interiorValidCurvatureFaces << ',' << a.interiorCurvatureMean << ','
        << a.interiorCurvatureRms << ',' << a.interiorCurvatureStd << ','
        << a.interiorCurvatureAbsMean << ',' << a.interiorCurvatureAbsMax << ','
        << a.nearWallCrossingFaces << ',' << a.nearWallValidCurvatureFaces << ','
        << a.nearWallCurvatureMean << ',' << a.nearWallCurvatureRms << ','
        << a.nearWallCurvatureStd << ',' << a.nearWallCurvatureAbsMean << ','
        << a.nearWallCurvatureAbsMax << ',' << a.normalBuildSeconds << ','
        << a.curvatureBuildSeconds << ',' << a.faceAuditSeconds << ','
        << a.residentBytes << ','
        << "alphaK=binomial3x3(alpha_x6c,1pass);"
           "n=-scharr3x3_grad(alphaK)/|grad|;kappa=scharr3x3_div(n);"
           "kappaGamma=linear_cell_interpolation_at_alpha0.5;passive_only"
        << '\n';
}


void append_phase_curvature_audit_0493x9c(
    const SimulationParams& params,
    int step,
    double time,
    int smoothingPasses,
    const PhaseCurvatureAudit0493x9a& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_curvature_0493x9c.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9c failed to open passive curvature audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,smoothingPasses,projectedSpeciesIndex,projectedType,numCells,"
               "crossingFaces,validCurvatureFaces,outwardNormalFaces,"
               "positiveCurvatureFaces,negativeCurvatureFaces,validFraction,"
               "normalOutwardFraction,normalFaceAlignmentMean,curvatureMean,"
               "curvatureRms,curvatureStd,curvatureAbsMean,curvatureAbsMax,"
               "wallMarginCells,interiorCrossingFaces,interiorValidCurvatureFaces,"
               "interiorCurvatureMean,interiorCurvatureRms,interiorCurvatureStd,"
               "interiorCurvatureAbsMean,interiorCurvatureAbsMax,"
               "nearWallCrossingFaces,nearWallValidCurvatureFaces,"
               "nearWallCurvatureMean,nearWallCurvatureRms,nearWallCurvatureStd,"
               "nearWallCurvatureAbsMean,nearWallCurvatureAbsMax,"
               "normalBuildSeconds,curvatureBuildSeconds,faceAuditSeconds,"
               "residentBytes,curvatureDefinition\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << smoothingPasses << ','
        << a.projectedSpeciesIndex << ',' << a.projectedType << ','
        << a.numCells << ',' << a.crossingFaces << ','
        << a.validCurvatureFaces << ',' << a.outwardNormalFaces << ','
        << a.positiveCurvatureFaces << ',' << a.negativeCurvatureFaces << ','
        << a.validFraction << ',' << a.normalOutwardFraction << ','
        << a.normalFaceAlignmentMean << ',' << a.curvatureMean << ','
        << a.curvatureRms << ',' << a.curvatureStd << ','
        << a.curvatureAbsMean << ',' << a.curvatureAbsMax << ','
        << a.wallMarginCells << ',' << a.interiorCrossingFaces << ','
        << a.interiorValidCurvatureFaces << ',' << a.interiorCurvatureMean << ','
        << a.interiorCurvatureRms << ',' << a.interiorCurvatureStd << ','
        << a.interiorCurvatureAbsMean << ',' << a.interiorCurvatureAbsMax << ','
        << a.nearWallCrossingFaces << ',' << a.nearWallValidCurvatureFaces << ','
        << a.nearWallCurvatureMean << ',' << a.nearWallCurvatureRms << ','
        << a.nearWallCurvatureStd << ',' << a.nearWallCurvatureAbsMean << ','
        << a.nearWallCurvatureAbsMax << ',' << a.normalBuildSeconds << ','
        << a.curvatureBuildSeconds << ',' << a.faceAuditSeconds << ','
        << a.residentBytes << ','
        << "alphaK=binomial3x3(alpha_x6c," << smoothingPasses << "passes);"
           "n=-scharr3x3_grad(alphaK)/|grad|;kappa=scharr3x3_div(n);"
           "kappaGamma=linear_cell_interpolation_at_alpha0.5;passive_only"
        << '\n';
}


void append_surface_tension_limiter_audit_0493x9r(
    const SimulationParams& params,
    int step,
    double time,
    double kappaLimit,
    unsigned long long capillaryFaces,
    unsigned long long clippedFaces,
    double rawKappaAbsMax,
    double effectiveKappaAbsMax) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_surface_tension_limiter_0493x9r.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9r failed to open capillary-resolution audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,sigma,minRadiusCells,kappaLimit,capillaryFaces,"
               "clippedFaces,clipFraction,capillaryKappaRawAbsMax,"
               "capillaryKappaEffectiveAbsMax,definition\n";
    }
    const double clipFraction = capillaryFaces > 0ull
        ? static_cast<double>(clippedFaces) / static_cast<double>(capillaryFaces)
        : 0.0;
    out << std::setprecision(17)
        << step << ',' << time << ',' << params.surfaceTensionSigma << ','
        << params.surfaceTensionMinRadiusCells << ',' << kappaLimit << ','
        << capillaryFaces << ',' << clippedFaces << ',' << clipFraction << ','
        << rawKappaAbsMax << ',' << effectiveKappaAbsMax << ','
        << "face-kappa=interp(p3/x9m);limit-only-in-sigma*kappa;"
           "raw-curvature-and-LiveVis-unchanged" << '\n';
}

void append_surface_tension_audit_0493x9d(
    const SimulationParams& params,
    int step,
    double time,
    double rhoLiquidRef,
    double capillaryPotentialScale,
    const PhaseCurvatureAudit0493x9a& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_surface_tension_0493x9d.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9d failed to open surface-tension audit CSV: " + path.string());
    }
    if (header) {
        out << "step,time,sigma,rhoLiquidRef,capillaryPotentialScale,crossingFaces,"
               "validCurvatureFaces,curvatureMean,curvatureStd,curvatureAbsMax,"
               "laplacePressureMean,laplacePressureStd,capillaryPhiMean,"
               "capillaryPhiStd,definition\n";
    }
    const double pressureMean = params.surfaceTensionSigma * a.curvatureMean;
    const double pressureStd = params.surfaceTensionSigma * a.curvatureStd;
    out << std::setprecision(17)
        << step << ',' << time << ',' << params.surfaceTensionSigma << ','
        << rhoLiquidRef << ',' << capillaryPotentialScale << ','
        << a.crossingFaces << ',' << a.validCurvatureFaces << ','
        << a.curvatureMean << ',' << a.curvatureStd << ',' << a.curvatureAbsMax << ','
        << pressureMean << ',' << pressureStd << ','
        << capillaryPotentialScale * a.curvatureMean << ','
        << capillaryPotentialScale * a.curvatureStd << ','
        << "p_l-p_g=sigma*kappa_p3;phiGamma_cap=dt*sigma*kappa_p3/rhoLiquidRef;"
           "kappa_p3=binomial3x3(3)+Scharr"
        << '\n';
}


struct StaticDropCellAccumulator0493x9e {
    unsigned long long deepLiquidCells = 0ull;
    unsigned long long deepGasCells = 0ull;
    double alphaSum = 0.0;
    double liquidPhiSum = 0.0;
    double liquidPhiSqSum = 0.0;
    double gasPhiSum = 0.0;
    double gasPhiSqSum = 0.0;
};

struct StaticDropFaceAccumulator0493x9e {
    unsigned long long crossingFaces = 0ull;
    unsigned long long validFaces = 0ull;
    double curvatureSum = 0.0;
    double curvatureSqSum = 0.0;
    double discreteResultantX = 0.0;
    double discreteResultantY = 0.0;
    double discreteAbsTraction = 0.0;
    double axisBoundaryMeasure = 0.0;
};

struct StaticDropVelocityAccumulator0493x9e {
    unsigned long long liquidCells = 0ull;
    unsigned long long coreCells = 0ull;
    unsigned long long interfaceCells = 0ull;
    unsigned long long liquidSpeedMaxScaled = 0ull;
    unsigned long long coreSpeedMaxScaled = 0ull;
    unsigned long long interfaceSpeedMaxScaled = 0ull;
    double liquidVxSum = 0.0;
    double liquidVySum = 0.0;
    double liquidSpeedSqSum = 0.0;
    double coreVxSum = 0.0;
    double coreVySum = 0.0;
    double coreSpeedSqSum = 0.0;
    double interfaceVxSum = 0.0;
    double interfaceVySum = 0.0;
    double interfaceSpeedSqSum = 0.0;
};

struct EllipseParticleMomentAccumulator0493x9f {
    unsigned long long particles = 0ull;
    double massSum = 0.0;
    double massXSum = 0.0;
    double massYSum = 0.0;
    double massXXSum = 0.0;
    double massYYSum = 0.0;
    double massXYSum = 0.0;
};

struct EllipseInterfaceRadiusAccumulator0493x9f {
    unsigned long long crossingPoints = 0ull;
    unsigned long long radiusMinScaled = 0ull;
    unsigned long long radiusMaxScaled = 0ull;
    double radiusSum = 0.0;
    double radiusSqSum = 0.0;
};

void append_ellipse_shape_audit_0493x9f(
    const SimulationParams& params,
    int step,
    double time,
    std::uint32_t liquidType,
    const EllipseParticleMomentAccumulator0493x9f& m,
    const EllipseInterfaceRadiusAccumulator0493x9f& r) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_ellipse_shape_0493x9f.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9f failed to open ellipse-shape CSV: " + path.string());
    }
    if (header) {
        out << "step,time,liquidType,liquidParticles,liquidMass,xCM,yCM,"
               "Mxx,Mxy,Myy,lambdaMajor,lambdaMinor,momentRadiusMajor,"
               "momentRadiusMinor,axisRatio,ellipticity,principalAngleRad,"
               "principalAngleDeg,interfaceCrossingPoints,interfaceRadiusMin,"
               "interfaceRadiusMax,interfaceRadiusMean,interfaceRadiusStd,"
               "interfaceRadialSpan,definition\n";
    }
    const double invMass = m.massSum > 0.0 ? 1.0 / m.massSum : 0.0;
    const double xcm = m.massXSum * invMass;
    const double ycm = m.massYSum * invMass;
    const double mxx = std::max(0.0, m.massXXSum * invMass - xcm * xcm);
    const double myy = std::max(0.0, m.massYYSum * invMass - ycm * ycm);
    const double mxy = m.massXYSum * invMass - xcm * ycm;
    const double tr = mxx + myy;
    const double disc = std::sqrt(std::max(0.0,
        (mxx - myy) * (mxx - myy) + 4.0 * mxy * mxy));
    const double lambdaMajor = 0.5 * (tr + disc);
    const double lambdaMinor = std::max(0.0, 0.5 * (tr - disc));
    // For a uniform filled ellipse, covariance eigenvalues are a^2/4,b^2/4.
    const double radiusMajor = 2.0 * std::sqrt(std::max(0.0, lambdaMajor));
    const double radiusMinor = 2.0 * std::sqrt(std::max(0.0, lambdaMinor));
    const double axisRatio = radiusMinor > 0.0 ? radiusMajor / radiusMinor : 0.0;
    const double ellipticity = (radiusMajor + radiusMinor) > 0.0
        ? (radiusMajor - radiusMinor) / (radiusMajor + radiusMinor) : 0.0;
    const double angle = 0.5 * std::atan2(2.0 * mxy, mxx - myy);
    constexpr double radToDeg = 57.295779513082320876798154814105;
    constexpr double radiusScale = 1000000000.0;
    const double rmin = (r.crossingPoints > 0ull &&
                         r.radiusMinScaled != std::numeric_limits<unsigned long long>::max())
        ? static_cast<double>(r.radiusMinScaled) / radiusScale : 0.0;
    const double rmax = r.crossingPoints > 0ull
        ? static_cast<double>(r.radiusMaxScaled) / radiusScale : 0.0;
    const double invR = r.crossingPoints > 0ull
        ? 1.0 / static_cast<double>(r.crossingPoints) : 0.0;
    const double rmean = r.radiusSum * invR;
    const double rstd = r.crossingPoints > 0ull
        ? std::sqrt(std::max(0.0, r.radiusSqSum * invR - rmean * rmean)) : 0.0;
    out << std::setprecision(17)
        << step << ',' << time << ',' << liquidType << ',' << m.particles << ','
        << m.massSum << ',' << xcm << ',' << ycm << ','
        << mxx << ',' << mxy << ',' << myy << ','
        << lambdaMajor << ',' << lambdaMinor << ','
        << radiusMajor << ',' << radiusMinor << ',' << axisRatio << ','
        << ellipticity << ',' << angle << ',' << angle * radToDeg << ','
        << r.crossingPoints << ',' << rmin << ',' << rmax << ',' << rmean << ','
        << rstd << ',' << (rmax - rmin) << ','
        << "particleCOM=mass-weighted liquid fluid particles;"
           "secondMoment=mass-weighted central covariance;"
           "momentRadii=2*sqrt(eigenvalues);"
           "interfaceRadii=alpha0.5 crossing-point distance from particle COM"
        << '\n';
}

void append_static_drop_pressure_audit_0493x9e(
    const SimulationParams& params,
    int step,
    double time,
    double rhoLiquidRef,
    double pressureReference,
    double pressureScale,
    double cellArea,
    const StaticDropCellAccumulator0493x9e& c,
    const StaticDropFaceAccumulator0493x9e& f) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_static_drop_pressure_0493x9e.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9e failed to open static-drop pressure CSV: " + path.string());
    }
    if (header) {
        out << "step,time,sigma,rhoLiquidRef,pressureReference,pressureScale,"
               "alphaArea,effectiveRadius,equivalentCurvature,deepLiquidCells,"
               "deepGasCells,liquidPhiMean,liquidPhiStd,gasPhiMean,gasPhiStd,"
               "liquidProjectionPressureGaugeMean,liquidProjectionPressureGaugeStd,"
               "gasEosPressureGaugeMean,gasEosPressureGaugeStd,"
               "measuredPressureJump,laplaceTargetCurrent,pressureJumpError,"
               "crossingFaces,validCurvatureFaces,curvatureMean,curvatureStd,"
               "discreteCurvatureResultantX,discreteCurvatureResultantY,"
               "discreteCurvatureResultantNorm,discreteAbsTraction,"
               "normalizedDiscreteResultant,capillaryResultantX,capillaryResultantY,"
               "capillaryResultantNorm,axisBoundaryMeasure,definition\n";
    }
    constexpr double pi = 3.141592653589793238462643383279502884;
    const double alphaArea = c.alphaSum * cellArea;
    const double rEff = alphaArea > 0.0 ? std::sqrt(alphaArea / pi) : 0.0;
    const double kEq = rEff > 0.0 ? 1.0 / rEff : 0.0;
    const double invL = c.deepLiquidCells > 0ull
        ? 1.0 / static_cast<double>(c.deepLiquidCells) : 0.0;
    const double invG = c.deepGasCells > 0ull
        ? 1.0 / static_cast<double>(c.deepGasCells) : 0.0;
    const double phiL = c.liquidPhiSum * invL;
    const double phiG = c.gasPhiSum * invG;
    const double phiLStd = c.deepLiquidCells > 0ull
        ? std::sqrt(std::max(0.0, c.liquidPhiSqSum * invL - phiL * phiL)) : 0.0;
    const double phiGStd = c.deepGasCells > 0ull
        ? std::sqrt(std::max(0.0, c.gasPhiSqSum * invG - phiG * phiG)) : 0.0;
    const double phiToPressure = params.dt > 0.0 ? rhoLiquidRef / params.dt : 0.0;
    const double pL = phiL * phiToPressure;
    const double pLStd = phiLStd * phiToPressure;
    const double pG = phiG * phiToPressure;
    const double pGStd = phiGStd * phiToPressure;
    const double measuredJump = pL - pG;
    const double laplaceTarget = rEff > 0.0 ? params.surfaceTensionSigma / rEff : 0.0;
    const double pressureJumpError = measuredJump - laplaceTarget;
    const double invF = f.validFaces > 0ull
        ? 1.0 / static_cast<double>(f.validFaces) : 0.0;
    const double kMean = f.curvatureSum * invF;
    const double kStd = f.validFaces > 0ull
        ? std::sqrt(std::max(0.0, f.curvatureSqSum * invF - kMean * kMean)) : 0.0;
    const double resultNorm = std::hypot(f.discreteResultantX, f.discreteResultantY);
    const double resultRel = f.discreteAbsTraction > 0.0
        ? resultNorm / f.discreteAbsTraction : 0.0;
    const double capFx = params.surfaceTensionSigma * f.discreteResultantX;
    const double capFy = params.surfaceTensionSigma * f.discreteResultantY;
    out << std::setprecision(17)
        << step << ',' << time << ',' << params.surfaceTensionSigma << ','
        << rhoLiquidRef << ',' << pressureReference << ',' << pressureScale << ','
        << alphaArea << ',' << rEff << ',' << kEq << ','
        << c.deepLiquidCells << ',' << c.deepGasCells << ','
        << phiL << ',' << phiLStd << ',' << phiG << ',' << phiGStd << ','
        << pL << ',' << pLStd << ',' << pG << ',' << pGStd << ','
        << measuredJump << ',' << laplaceTarget << ',' << pressureJumpError << ','
        << f.crossingFaces << ',' << f.validFaces << ',' << kMean << ',' << kStd << ','
        << f.discreteResultantX << ',' << f.discreteResultantY << ',' << resultNorm << ','
        << f.discreteAbsTraction << ',' << resultRel << ','
        << capFx << ',' << capFy << ',' << std::hypot(capFx, capFy) << ','
        << f.axisBoundaryMeasure << ','
        << "pProjectionGauge=rhoLiquidRef*phi/dt;"
           "pGasGauge=rhoLiquidRef*phiGasEOS/dt;"
           "deepLiquid=alpha>=0.9;deepGas=alpha<=0.1;"
           "Reff=sqrt(sum(alpha)*cellArea/pi);"
           "discreteResultant=sum(kappaGamma*n_axis*faceMeasure)"
        << '\n';
}

void append_static_drop_velocity_audit_0493x9e(
    const SimulationParams& params,
    int step,
    double time,
    std::uint32_t liquidType,
    const StaticDropVelocityAccumulator0493x9e& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_static_drop_velocity_0493x9e.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9e failed to open static-drop velocity CSV: " + path.string());
    }
    if (header) {
        out << "step,time,liquidType,liquidCells,liquidMeanVx,liquidMeanVy,"
               "liquidSpeedRms,liquidFluctuationRms,liquidSpeedMax,"
               "coreCells,coreMeanVx,coreMeanVy,coreSpeedRms,coreFluctuationRms,coreSpeedMax,"
               "interfaceCells,interfaceMeanVx,interfaceMeanVy,interfaceSpeedRms,"
               "interfaceFluctuationRms,interfaceSpeedMax,definition\n";
    }
    constexpr double speedScale = 1000000000.0;
    auto stats = [](unsigned long long n, double sx, double sy, double ssq) {
        struct Result { double mx, my, rms, fluct; } r{0,0,0,0};
        if (n == 0ull) return r;
        const double inv = 1.0 / static_cast<double>(n);
        r.mx = sx * inv;
        r.my = sy * inv;
        r.rms = std::sqrt(std::max(0.0, ssq * inv));
        r.fluct = std::sqrt(std::max(0.0,
            ssq * inv - r.mx * r.mx - r.my * r.my));
        return r;
    };
    const auto l = stats(a.liquidCells, a.liquidVxSum, a.liquidVySum, a.liquidSpeedSqSum);
    const auto c = stats(a.coreCells, a.coreVxSum, a.coreVySum, a.coreSpeedSqSum);
    const auto i = stats(a.interfaceCells, a.interfaceVxSum, a.interfaceVySum,
                         a.interfaceSpeedSqSum);
    out << std::setprecision(17)
        << step << ',' << time << ',' << liquidType << ','
        << a.liquidCells << ',' << l.mx << ',' << l.my << ',' << l.rms << ',' << l.fluct << ','
        << static_cast<double>(a.liquidSpeedMaxScaled) / speedScale << ','
        << a.coreCells << ',' << c.mx << ',' << c.my << ',' << c.rms << ',' << c.fluct << ','
        << static_cast<double>(a.coreSpeedMaxScaled) / speedScale << ','
        << a.interfaceCells << ',' << i.mx << ',' << i.my << ',' << i.rms << ',' << i.fluct << ','
        << static_cast<double>(a.interfaceSpeedMaxScaled) / speedScale << ','
        << "postQ6 cell-mean velocity;liquid=alpha>=0.5;core=alpha>=0.9;"
           "interface=trueBand(cell adjacent to face straddling alpha=0.5);"
           "cells require positive projected-liquid mass"
        << '\n';
}


struct PhaseInterfaceStencilAudit0493x6f {
    int projectedSpeciesIndex = -1;
    std::uint32_t projectedType = 0u;
    std::uint64_t carrierActiveCells = 0u;
    std::uint64_t pressureActiveCells = 0u;
    std::uint64_t interiorPressureFaces = 0u;
    std::uint64_t representedInterfaceFaces = 0u;
    std::uint64_t smallThetaStabilizedFaces = 0u;
    std::uint64_t carrierTruncationFaces = 0u;
    std::uint64_t uncoveredInterfaceFaces = 0u;
    double thetaGuard = 0.0;
    double thetaMin = 0.0;
    double thetaMean = 0.0;
    double thetaMax = 0.0;
    double prepareSeconds = 0.0;
    std::uint64_t residentBytes = 0u;
};

void append_phase_interface_stencil_audit_0493x6f(
    const SimulationParams& params,
    int step,
    double time,
    const PhaseInterfaceStencilAudit0493x6f& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_interface_stencil_0493x6f.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x6f failed to open phase-interface stencil audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,carrierActiveCells,"
               "pressureActiveCells,interiorPressureFaces,representedInterfaceFaces,"
               "smallThetaStabilizedFaces,carrierTruncationFaces,"
               "uncoveredInterfaceFaces,thetaGuard,thetaMin,thetaMean,thetaMax,"
               "prepareSeconds,residentBytes,stencilDefinition\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ','
        << a.projectedType << ',' << a.carrierActiveCells << ','
        << a.pressureActiveCells << ',' << a.interiorPressureFaces << ','
        << a.representedInterfaceFaces << ',' << a.smallThetaStabilizedFaces << ','
        << a.carrierTruncationFaces << ',' << a.uncoveredInterfaceFaces << ','
        << a.thetaGuard << ',' << a.thetaMin << ',' << a.thetaMean << ','
        << a.thetaMax << ',' << a.prepareSeconds << ',' << a.residentBytes << ','
        << "pressureMask=carrier&&alpha>=0.5;"
           "faceCoeff=1(interior);1/theta(interface);2(small-theta);0(no-pressure-coupling);"
           "pGamma=optional-prepared-face-value(zero-in-x6f);external-domain-BC-unchanged" << '\n';
}

struct PhaseInterfaceGasPressureAudit0493x6g {
    int projectedSpeciesIndex = -1;
    std::uint32_t projectedType = 0u;
    int gasSpeciesCount = 0;
    std::uint64_t representedInterfaceFaces = 0u;
    std::uint64_t nonzeroPressureFaces = 0u;
    double liquidReferenceCellMass = 0.0;
    double cellArea = 0.0;
    double pressureReference = 0.0;
    double pressureScale = 1.0;
    double constantPressure = 0.0;
    double pressurePotentialMean = 0.0;
    double pressurePotentialStd = 0.0;
    double pressureDeltaMean = 0.0;
    double pressureDeltaStd = 0.0;
    double prepareSeconds = 0.0;
    std::uint64_t residentBytes = 0u;
    const char* sourceMode = "eos";
};

void append_phase_interface_gas_pressure_audit_0493x6g(
    const SimulationParams& params,
    int step,
    double time,
    const PhaseInterfaceGasPressureAudit0493x6g& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_interface_pressure_0493x6g.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x6g failed to open phase-interface gas-pressure audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,gasSpeciesCount,"
               "sourceMode,liquidReferenceCellMass,cellArea,kBT,dt,"
               "pressureReference,pressureScale,constantPressure,"
               "representedInterfaceFaces,nonzeroPressureFaces,"
               "pressurePotentialMean,pressurePotentialStd,pressureDeltaMean,"
               "pressureDeltaStd,prepareSeconds,residentBytes,pressureDefinition\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ','
        << a.projectedType << ',' << a.gasSpeciesCount << ',' << a.sourceMode << ','
        << a.liquidReferenceCellMass << ',' << a.cellArea << ',' << params.kBT << ','
        << params.dt << ',' << a.pressureReference << ',' << a.pressureScale << ','
        << a.constantPressure << ',' << a.representedInterfaceFaces << ','
        << a.nonzeroPressureFaces << ',' << a.pressurePotentialMean << ','
        << a.pressurePotentialStd << ',' << a.pressureDeltaMean << ','
        << a.pressureDeltaStd << ',' << a.prepareSeconds << ',' << a.residentBytes << ','
        << "phiGamma=dt*pressureScale*(pGas-pressureReference)/rhoLiquidRef;"
           "EOS:pGas=Ng*kBT/cellArea;trace=gas-side(alpha<0.5)-cell" << '\n';
}

void append_q6_resident_thermostat_audit_0491f(
    const SimulationParams& params,
    std::uint64_t step,
    double targetKBT,
    std::uint64_t cellIdH2DEntries,
    const CudaQ6ResidentThermostat0400Diagnostics& diag) {
    if (!params.speciesQ6Enable || params.outputDir.empty() || !diag.handled) return;
    const std::filesystem::path path =
        std::filesystem::path(params.outputDir) / "cuda_species_q6_energy_0491f.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error("0491f failed to open species-Q6 energy audit CSV: " +
                                 path.string());
    }
    if (header) {
        out << "step,targetKBT,thermostat_device_resident,thermostat_cpu_fallback,"
               "thermostat_collision_cell_id_h2d_entries,thermostatApplied,"
               "thermostatCells,thermostatParticles,thermostatKBTBefore,"
               "thermostatKBTAfter,thermostatKBTErrorAbs,thermostatScaleMean,"
               "thermostatScaleMin,thermostatScaleMax,kineticSeconds,scaleSeconds,"
               "applySeconds,diagnosticsDownloadSeconds,totalSeconds\n";
    }
    const double kbtError =
        std::abs(diag.thermostat.kBTAfter - targetKBT);
    out << std::setprecision(17)
        << step << ','
        << targetKBT << ','
        << 1 << ','
        << 0 << ','
        << cellIdH2DEntries << ','
        << (diag.thermostat.applied ? 1 : 0) << ','
        << diag.thermostat.cellsRescaled << ','
        << diag.thermostat.particlesRescaled << ','
        << diag.thermostat.kBTBefore << ','
        << diag.thermostat.kBTAfter << ','
        << kbtError << ','
        << diag.thermostat.scaleMean << ','
        << diag.thermostat.scaleMin << ','
        << diag.thermostat.scaleMax << ','
        << diag.kineticSeconds << ','
        << diag.scaleSeconds << ','
        << diag.applySeconds << ','
        << diag.diagnosticsDownloadSeconds << ','
        << diag.totalSeconds << '\n';
}

double inlet_velocity_ramp_factor_0400(const SimulationParams& params, double time) {
    if (!params.inletVelocityRampEnable) return 1.0;
    const double t0 = params.inletVelocityRampStartTime;
    const double t1 = params.inletVelocityRampEndTime;
    if (!(t1 > t0)) return params.inletVelocityRampFinalFactor;
    double a = 0.0;
    if (time <= t0) a = 0.0;
    else if (time >= t1) a = 1.0;
    else a = (time - t0) / (t1 - t0);
    if (params.inletVelocityRampProfile == "smoothstep") {
        a = a * a * (3.0 - 2.0 * a);
    }
    return (1.0 - a) * params.inletVelocityRampInitialFactor +
           a * params.inletVelocityRampFinalFactor;
}

bool q6_wall_like_0409(const std::string& mode) {
    return mode == "solid" || mode == "specular" || mode == "bounceback";
}

int q6_face_code_0409(const std::string& face) {
    if (face == "left") return 0;
    if (face == "right") return 1;
    if (face == "bottom") return 2;
    if (face == "top") return 3;
    return -1;
}

bool q6_open_fullface_0404_supported(const SimulationParams& params) {
    const bool leftInlet = is_inlet_boundary_mode(params.bcLeft);
    const bool rightInlet = is_inlet_boundary_mode(params.bcRight);
    const bool bottomInlet = is_inlet_boundary_mode(params.bcBottom);
    const bool topInlet = is_inlet_boundary_mode(params.bcTop);
    const bool leftOutlet = is_outlet_boundary_mode(params.bcLeft);
    const bool rightOutlet = is_outlet_boundary_mode(params.bcRight);
    const bool bottomOutlet = is_outlet_boundary_mode(params.bcBottom);
    const bool topOutlet = is_outlet_boundary_mode(params.bcTop);
    const bool xPair = ((leftInlet && rightOutlet) || (leftOutlet && rightInlet)) &&
                       q6_wall_like_0409(params.bcBottom) && q6_wall_like_0409(params.bcTop);
    const bool yPair = ((bottomInlet && topOutlet) || (bottomOutlet && topInlet)) &&
                       q6_wall_like_0409(params.bcLeft) && q6_wall_like_0409(params.bcRight);
    return (xPair || yPair) &&
           !params.openBoundarySegmentsEnable && params.openBoundarySegmentCount == 0 &&
           params.inletVelocitySpatialProfile == "uniform" &&
           (params.openBoundaryOutletMode == "balanced_flux" || params.openBoundaryOutletMode == "balanced");
}

void q6_open_fullface_flux_0404(const SimulationParams& params,
                                double time,
                                double& xLowFlux,
                                double& xHighFlux,
                                double& yLowFlux,
                                double& yHighFlux) {
    const double ramp = inlet_velocity_ramp_factor_0400(params, time);
    xLowFlux = 0.0;
    xHighFlux = 0.0;
    yLowFlux = 0.0;
    yHighFlux = 0.0;
    if (is_inlet_boundary_mode(params.bcLeft)) {
        xLowFlux = ramp * params.inletUxLeft;
        xHighFlux = xLowFlux;
    } else if (is_inlet_boundary_mode(params.bcRight)) {
        xHighFlux = ramp * params.inletUxRight;
        xLowFlux = xHighFlux;
    } else if (is_inlet_boundary_mode(params.bcBottom)) {
        yLowFlux = ramp * params.inletUyBottom;
        yHighFlux = yLowFlux;
    } else if (is_inlet_boundary_mode(params.bcTop)) {
        yHighFlux = ramp * params.inletUyTop;
        yLowFlux = yHighFlux;
    }
}

int q6_segmented_profile_code_0493x8k(const SimulationParams& params) {
    if (params.inletVelocitySpatialProfile == "poiseuille_y_max") return 1;
    if (params.inletVelocitySpatialProfile == "poiseuille_y" ||
        params.inletVelocitySpatialProfile == "poiseuille_y_mean") return 2;
    return 0;
}

bool q6_open_segmented_0409_supported(const SimulationParams& params) {
    if (!cuda_q6_segmented_io_0409_requested()) return false;
    if (!params.openBoundarySegmentsEnable || params.openBoundarySegmentCount <= 0) return false;
    if (static_cast<int>(params.openBoundarySegments.size()) != params.openBoundarySegmentCount) return false;
    if (params.openBoundarySegmentCount > kOpenBoundaryMaxSegments) return false;
    if (!q6_wall_like_0409(params.bcLeft) || !q6_wall_like_0409(params.bcRight) ||
        !q6_wall_like_0409(params.bcBottom) || !q6_wall_like_0409(params.bcTop)) return false;
    if (!(params.inletVelocitySpatialProfile == "uniform" ||
          params.inletVelocitySpatialProfile == "poiseuille_y_max" ||
          params.inletVelocitySpatialProfile == "poiseuille_y" ||
          params.inletVelocitySpatialProfile == "poiseuille_y_mean")) return false;
    if (!(params.openBoundaryOutletMode == "neumann" ||
          params.openBoundaryOutletMode == "balanced_flux" ||
          params.openBoundaryOutletMode == "balanced" ||
          params.openBoundaryOutletMode == "hybrid")) return false;
    bool hasInlet = false;
    bool hasOutlet = false;
    for (const OpenBoundarySegment& seg : params.openBoundarySegments) {
        if (q6_face_code_0409(seg.face) < 0) return false;
        if (!(seg.sMin >= 0.0 && seg.sMax <= 1.0 && seg.sMax >= seg.sMin)) return false;
        if (open_boundary_segment_is_inlet(seg)) hasInlet = true;
        else if (open_boundary_segment_is_outlet(seg)) hasOutlet = true;
        else return false;
        if (!(std::isfinite(seg.ux) && std::isfinite(seg.uy))) return false;
        if (open_boundary_face_is_x(seg.face) && std::abs(seg.uy) > 1.0e-15) return false;
        if (open_boundary_face_is_y(seg.face) && std::abs(seg.ux) > 1.0e-15) return false;
    }
    return hasInlet && hasOutlet;
}

Q6SegmentedIo0409 q6_make_segmented_0409(const SimulationParams& params, double time) {
    Q6SegmentedIo0409 cfg{};
    if (!q6_open_segmented_0409_supported(params)) return cfg;
    const double ramp = inlet_velocity_ramp_factor_0400(params, time);
    cfg.enabled = 1;
    cfg.count = std::min(static_cast<int>(params.openBoundarySegments.size()), kOpenBoundaryMaxSegments);
    cfg.inletProfileCode = q6_segmented_profile_code_0493x8k(params);
    cfg.passiveNeumannRightOutlet0493x8l = params.openBoundaryOutletMode == "neumann" ? 1 : 0;
    for (int k = 0; k < cfg.count; ++k) {
        const OpenBoundarySegment& seg = params.openBoundarySegments[static_cast<std::size_t>(k)];
        cfg.face[k] = q6_face_code_0409(seg.face);
        cfg.mode[k] = open_boundary_segment_is_inlet(seg) ? 1 : 2;
        cfg.type[k] = seg.type;
        cfg.sMin[k] = seg.sMin;
        cfg.sMax[k] = seg.sMax;
        cfg.flux[k] = ramp * (open_boundary_face_is_x(seg.face) ? seg.ux : seg.uy);
    }
    return cfg;
}

bool q6_has_passive_pressure_outlet_right_0493x8r(
    const Q6SegmentedIo0409& cfg) {
    if (!cfg.enabled || !cfg.passiveNeumannRightOutlet0493x8l) return false;
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] == 1 && cfg.mode[k] == 2 &&
            cfg.sMax[k] > cfg.sMin[k]) {
            return true;
        }
    }
    return false;
}

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

double q6_segmented_flux_integral_0409(const Q6SegmentedIo0409& cfg, int face, double length) {
    if (!cfg.enabled || !(length > 0.0)) return 0.0;
    double flux = 0.0;
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] != face) continue;
        double value =
            cfg.flux[k] * std::max(0.0, cfg.sMax[k] - cfg.sMin[k]) * length;
        if (cfg.mode[k] == 1 && cfg.inletProfileCode == 1) {
            value *= 2.0 / 3.0; // mean of 4*xi*(1-xi)
        }
        // profileCode 2 has unit mean; outlets are unchanged in x8k.
        flux += value;
    }
    return flux;
}

template <typename T>
class DeviceBuffer0400 {
public:
    DeviceBuffer0400() = default;
    ~DeviceBuffer0400() { release(); }
    DeviceBuffer0400(const DeviceBuffer0400&) = delete;
    DeviceBuffer0400& operator=(const DeviceBuffer0400&) = delete;

    void release() {
        if (ptr_ != nullptr) {
            cudaFree(ptr_);
            ptr_ = nullptr;
            capacity_ = 0u;
        }
    }

    void ensure(std::size_t n) {
        if (n <= capacity_) {
            return;
        }
        release();
        check_cuda_0400(cudaMalloc(reinterpret_cast<void**>(&ptr_), n * sizeof(T)), "cudaMalloc");
        capacity_ = n;
    }

    T* data() { return ptr_; }
    const T* data() const { return ptr_; }

private:
    T* ptr_ = nullptr;
    std::size_t capacity_ = 0u;
};

struct PhaseGeometryAccumulator0493x6b {
    unsigned long long phaseFillActiveCells = 0ull;
    unsigned long long maskPhaseMismatchCells = 0ull;
    unsigned long long interfaceFaces = 0ull;
    unsigned long long supportThetaValidFaces = 0ull;
    unsigned long long supportThetaNearCellFaces = 0ull;
    unsigned long long supportThetaNearExteriorFaces = 0ull;
    unsigned long long halfIsoBracketFaces = 0ull;
    unsigned long long normalValidFaces = 0ull;
    unsigned long long normalOutwardFaces = 0ull;
    double insideFillSum = 0.0;
    double outsideFillSum = 0.0;
    double supportThetaSum = 0.0;
    double supportThetaSqSum = 0.0;
    double supportThetaMidSqSum = 0.0;
    double halfIsoThetaSum = 0.0;
    double halfIsoThetaSqSum = 0.0;
    double normalFaceAlignmentSum = 0.0;
};

struct PhaseGeometryResidentAccumulator0493x6c {
    unsigned long long maskFilteredMismatchCells = 0ull;
    unsigned long long interfaceFaces = 0ull;
    unsigned long long halfIsoBracketFaces = 0ull;
    unsigned long long normalValidFaces = 0ull;
    unsigned long long normalOutwardFaces = 0ull;
    unsigned long long cutFaceGeometricFaces = 0ull;
    unsigned long long cutFaceSmallThetaFallbackFaces = 0ull;
    unsigned long long cutFaceThetaMaxScaled = 0ull;
    unsigned long long cutFaceThetaMinComplementScaled = 0ull;
    unsigned long long alphaHalfCrossingFaces = 0ull;
    unsigned long long alphaHalfCrossingActiveActiveFaces = 0ull;
    unsigned long long alphaHalfCrossingActiveInactiveFaces = 0ull;
    unsigned long long alphaHalfCrossingInactiveInactiveFaces = 0ull;
    unsigned long long alphaHalfCrossingAIActiveLiquidSideFaces = 0ull;
    unsigned long long alphaHalfCrossingAIActiveExteriorSideFaces = 0ull;
    unsigned long long alphaHalfThetaMaxScaled = 0ull;
    unsigned long long alphaHalfThetaMinComplementScaled = 0ull;
    unsigned long long boundedGeometryClippedCells = 0ull;
    double rawFillSum = 0.0;
    double boundedGeometrySourceSum = 0.0;
    double filteredFillSum = 0.0;
    double filterDeltaSqSum = 0.0;
    double cutFaceThetaSum = 0.0;
    double alphaHalfThetaSum = 0.0;
    double alphaHalfThetaSqSum = 0.0;
    double halfIsoThetaSum = 0.0;
    double halfIsoThetaSqSum = 0.0;
    double normalFaceAlignmentSum = 0.0;
};


struct PhaseCurvatureAccumulator0493x9a {
    unsigned long long crossingFaces = 0ull;
    unsigned long long validCurvatureFaces = 0ull;
    unsigned long long outwardNormalFaces = 0ull;
    unsigned long long positiveCurvatureFaces = 0ull;
    unsigned long long negativeCurvatureFaces = 0ull;
    unsigned long long curvatureAbsMaxScaled = 0ull;
    double normalFaceAlignmentSum = 0.0;
    double curvatureSum = 0.0;
    double curvatureSqSum = 0.0;
    double curvatureAbsSum = 0.0;

    // 0493x9b-audit2: same face statistics split by distance to physical wall.
    unsigned long long interiorCrossingFaces = 0ull;
    unsigned long long interiorValidCurvatureFaces = 0ull;
    unsigned long long interiorCurvatureAbsMaxScaled = 0ull;
    double interiorCurvatureSum = 0.0;
    double interiorCurvatureSqSum = 0.0;
    double interiorCurvatureAbsSum = 0.0;
    unsigned long long nearWallCrossingFaces = 0ull;
    unsigned long long nearWallValidCurvatureFaces = 0ull;
    unsigned long long nearWallCurvatureAbsMaxScaled = 0ull;
    double nearWallCurvatureSum = 0.0;
    double nearWallCurvatureSqSum = 0.0;
    double nearWallCurvatureAbsSum = 0.0;
};

struct PhaseInterfaceStencilAccumulator0493x6f {
    unsigned long long pressureActiveCells = 0ull;
    unsigned long long interiorPressureFaces = 0ull;
    unsigned long long representedInterfaceFaces = 0ull;
    unsigned long long smallThetaStabilizedFaces = 0ull;
    unsigned long long carrierTruncationFaces = 0ull;
    unsigned long long uncoveredInterfaceFaces = 0ull;
    unsigned long long thetaMaxScaled = 0ull;
    unsigned long long thetaMinComplementScaled = 0ull;
    unsigned long long nonzeroPressureFaces0493x6g = 0ull;
    // 0493x9r: summary-cadence diagnostics of the face-level limiter.
    unsigned long long capillaryFaces0493x9r = 0ull;
    unsigned long long capillaryClippedFaces0493x9r = 0ull;
    unsigned long long capillaryKappaRawAbsMaxScaled0493x9r = 0ull;
    unsigned long long capillaryKappaEffectiveAbsMaxScaled0493x9r = 0ull;
    double thetaSum = 0.0;
    double pressurePotentialSum0493x6g = 0.0;
    double pressurePotentialSqSum0493x6g = 0.0;
};

struct WallGeometryAccumulator0493x9h {
    unsigned long long solidCells = 0ull;
    unsigned long long mixedCells = 0ull;
    unsigned long long wallBandCells = 0ull;
    unsigned long long normalValidCells = 0ull;
    double solidFractionSum = 0.0;
    double normalUnitErrorSqSum = 0.0;
};

struct ContactAngleAccumulator0493x9i {
    unsigned long long candidateCells = 0ull;
    unsigned long long correctedCells = 0ull;
    unsigned long long curvatureCells = 0ull;
    double rawAngleSum = 0.0;
    double correctedAngleSum = 0.0;
    double correctedAngleErrorSqSum = 0.0;
    double correctedDotErrorSqSum = 0.0;
    double curvatureSum = 0.0;
    double curvatureSqSum = 0.0;
};


// 0493x9t: summary-cadence audit of the kinetic retention operator.
// All physical corrections remain CUDA resident; only this O(1) accumulator is
// downloaded when a normal Q6-g-f summary is requested.
struct KineticInterfaceAccumulator0493x9t {
    unsigned long long crossings = 0ull;
    unsigned long long selectedReflections = 0ull;
    unsigned long long transmittedCrossings = 0ull;
    unsigned long long appliedReflections = 0ull;
    unsigned long long unsupportedReflections = 0ull;
    unsigned long long convertedParticles = 0ull;
    double reflectedMass = 0.0;
    double transmittedMass = 0.0;
    double outwardRelativeNormalSpeedSum = 0.0;
    double deltaPx = 0.0;
    double deltaPy = 0.0;
    double deltaKineticEnergy = 0.0;
};


// 0493x9u: support-edge extension of the x9t kinetic reflection audit.
// Runtime physics remains CUDA resident; only this O(1) accumulator is copied
// on the normal summary cadence.
struct KineticInterfaceAccumulator0493x9u {
    unsigned long long phaseAParticlesInOuterSupport = 0ull;
    unsigned long long crossings = 0ull;
    unsigned long long legacyHalfIsoCrossings = 0ull;
    unsigned long long supportExitCrossings = 0ull;
    unsigned long long selectedReflections = 0ull;
    unsigned long long transmittedCrossings = 0ull;
    unsigned long long appliedReflections = 0ull;
    unsigned long long unsupportedReflections = 0ull;
    unsigned long long bathSearchFailures = 0ull;
    unsigned long long bathDepth0 = 0ull;
    unsigned long long bathDepth1 = 0ull;
    unsigned long long bathDepth2 = 0ull;
    unsigned long long normalFallbacks = 0ull;
    unsigned long long convertedParticles = 0ull;
    // 0493x9v diagnostic-only counters. They are accumulated only when the
    // x9u audit pointer is non-null (step 1 / summary cadence), so the normal
    // production steps pay no additional geometric diagnostic work.
    unsigned long long outerSupportCellParticlesLT3 = 0ull;
    unsigned long long detectorPredictedOuterTarget = 0ull;
    unsigned long long missedOccupiedOuterTarget = 0ull;
    unsigned long long missedSparseOuterTargetLT3 = 0ull;
    unsigned long long absoluteSupportExitCandidates = 0ull;
    unsigned long long missedRelativeButAbsoluteExit = 0ull;
    unsigned long long bathSearchFailureWouldExitLocal = 0ull;
    unsigned long long bathAlphaGEHalf = 0ull;
    unsigned long long bathAlphaLTHalf = 0ull;
    unsigned long long supportExitBathAlphaGEHalf = 0ull;
    unsigned long long supportExitBathAlphaLTHalf = 0ull;
    unsigned long long unsupportedInvalidBath = 0ull;
    unsigned long long unsupportedInvalidDonorGroup = 0ull;
    unsigned long long unsupportedNoReceiverMass = 0ull;
    unsigned long long unsupportedNormalCancellation = 0ull;
    unsigned long long unsupportedGroupNotOutward = 0ull;
    unsigned long long appliedStillOutwardRelative = 0ull;
    unsigned long long appliedStillRelativeExit = 0ull;
    unsigned long long appliedStillAbsoluteExit = 0ull;
    double postRelativeNormalSpeedSum = 0.0;
    double postOutwardRelativeNormalSpeedSum = 0.0;
    double reflectedMass = 0.0;
    double transmittedMass = 0.0;
    double outwardRelativeNormalSpeedSum = 0.0;
    double deltaPx = 0.0;
    double deltaPy = 0.0;
    double deltaKineticEnergy = 0.0;
};


// 0493x9x: crossing-time kinetic reflection audit.
// No O(Nparticle) state is stored. The production path reuses x9t/x9u
// total/ref/receiver/normal cell buffers and keeps the three-particle-pass
// structure.
struct KineticCrossingAccumulator0493x9x {
    unsigned long long phaseAOuterCellParticles = 0ull;
    unsigned long long shellParticles = 0ull;
    unsigned long long deepOuterParticles = 0ull;
    unsigned long long interiorCrossings = 0ull;
    unsigned long long shellGuardCrossings = 0ull;
    unsigned long long startBelowHalf = 0ull;
    unsigned long long pointwiseOuterRoutedToShell = 0ull;
    unsigned long long pointwiseInteriorOuterCell = 0ull;
    unsigned long long bisectionInteriorCrossings = 0ull;
    unsigned long long bisectionFallbacks = 0ull;
    unsigned long long selectedReflections = 0ull;
    unsigned long long transmittedCrossings = 0ull;
    unsigned long long appliedReflections = 0ull;
    unsigned long long unsupportedReflections = 0ull;
    unsigned long long unsupportedInvalidBath = 0ull;
    unsigned long long unsupportedInvalidDonorGroup = 0ull;
    unsigned long long unsupportedNoReceiverMass = 0ull;
    unsigned long long unsupportedNormalCancellation = 0ull;
    unsigned long long unsupportedGroupNotOutward = 0ull;
    unsigned long long appliedStillOutwardRelative = 0ull;
    unsigned long long appliedInteriorPredictedOutside = 0ull;
    unsigned long long crossingPointNormalFallbacks = 0ull;
    unsigned long long endpointSealCorrections = 0ull;
    unsigned long long endpointSealSampleFallbacks = 0ull;
    unsigned long long appliedInteriorFinalOutside = 0ull;
    unsigned long long shellRecoverableParticles = 0ull;
    unsigned long long shellHardRetentionCandidates = 0ull;
    unsigned long long shellHardRetentionAlreadyInside = 0ull;
    unsigned long long shellHardRetentionCorrections = 0ull;
    unsigned long long shellHardRetentionFallbacks = 0ull;
    unsigned long long shellHardRetentionFinalOutside = 0ull;
    unsigned long long hardFinalEndpointChecks = 0ull;
    unsigned long long hardFinalEndpointOutsideBefore = 0ull;
    unsigned long long hardFinalReceiverOutsideBefore = 0ull;
    unsigned long long hardFinalNeutralOutsideBefore = 0ull;
    unsigned long long hardFinalEndpointCorrections = 0ull;
    unsigned long long hardFinalMirrorAttempts = 0ull;
    unsigned long long hardFinalMirrorAccepted = 0ull;
    unsigned long long hardFinalMirrorNormalFallbacks = 0ull;
    unsigned long long hardFinalMirrorHardFallbacks = 0ull;
    unsigned long long hardFinalLocalAnchorCorrections = 0ull;
    unsigned long long hardFinalLocalAnchorMisses = 0ull;
    unsigned long long hardFinalEndpointOutsideAfter = 0ull;
    unsigned long long convertedParticles = 0ull;
    unsigned long long individualDonorReflections = 0ull;
    unsigned long long receiverCorrectedParticles = 0ull;
    unsigned long long reactionActiveCells = 0ull;
    unsigned long long reactionFeasibleCells = 0ull;
    unsigned long long reactionNoReceiverCells = 0ull;
    unsigned long long reactionEnergyFloorCells = 0ull;
    unsigned long long reactionThermalDegenerateCells = 0ull;
    unsigned long long analyticConservativeReactionCells = 0ull;
    unsigned long long analyticPositiveScaleCells = 0ull;
    unsigned long long analyticInwardCells = 0ull;
    unsigned long long analyticNonInwardPositiveCells = 0ull;
    unsigned long long analyticTrivialCells = 0ull;
    unsigned long long analyticInvalidCells = 0ull;
    double crossingFractionSum = 0.0;
    double outwardRelativeNormalSpeedSum = 0.0;
    double reflectedMass = 0.0;
    double transmittedMass = 0.0;
    double deltaPx = 0.0;
    double deltaPy = 0.0;
    double deltaKineticEnergy = 0.0;
    double positionCorrectionAbsSum = 0.0;
    double endpointSealCorrectionAbsSum = 0.0;
    double shellHardRetentionCorrectionAbsSum = 0.0;
    double hardFinalEndpointCorrectionAbsSum = 0.0;
    double reactionEnergyResidualAbsSum = 0.0;
    double reactionDeltaUMagnitudeSum = 0.0;
    double reactionLambdaDeviationAbsSum = 0.0;
    double analyticDonorScaleSum = 0.0;
    double analyticDonorScaleAbsFromSpecularSum = 0.0;

    // 0493x10f single-component/global-reservoir ablation diagnostics.
    // This is deliberately NOT yet the production multi-liquid-domain model.
    unsigned long long globalReactionActive = 0ull;
    unsigned long long globalReactionTrivial = 0ull;
    unsigned long long globalReactionInvalid = 0ull;
    unsigned long long globalReactionDonorCells = 0ull;
    unsigned long long globalReactionReceiverCells = 0ull;
    double globalReactionA = 0.0;
    double globalReactionH = 0.0;
    double globalReactionSNorm = 0.0;
    double globalReactionCellSNormSum = 0.0;
    double globalReactionCancellationRatio = 0.0;
    double globalReactionReceiverMass = 0.0;
    double globalReactionScale = 0.0;
    double globalReactionDeltaUMagnitude = 0.0;
    double globalReactionFormulaResidual = 0.0;

    // 0493x10i shifted mesoscopic exact-reaction diagnostics.
    unsigned long long mesoReactionBlockCells = 0ull;
    unsigned long long mesoReactionShiftX = 0ull;
    unsigned long long mesoReactionShiftY = 0ull;
    unsigned long long mesoReactionReservoirSlots = 0ull;
    unsigned long long mesoReactionActiveReservoirs = 0ull;
    unsigned long long mesoReactionTrivialReservoirs = 0ull;
    unsigned long long mesoReactionInvalidReservoirs = 0ull;
    unsigned long long mesoReactionNoReceiverReservoirs = 0ull;
    unsigned long long mesoReactionDonorCells = 0ull;
    unsigned long long mesoReactionReceiverCells = 0ull;
    double mesoReactionReceiverMassSum = 0.0;
    double mesoReactionScaleSum = 0.0;
    double mesoReactionScaleAbsFromSpecularSum = 0.0;
    double mesoReactionDeltaUMagnitudeSum = 0.0;
    double mesoReactionCancellationSum = 0.0;
    double mesoReactionFormulaResidualAbsSum = 0.0;

    // 0493x10j deliberately simple laboratory-frame specular ablation.
    unsigned long long simpleSpecularReflections = 0ull;
    unsigned long long simpleSpecularInteriorCollisions = 0ull;
    unsigned long long simpleSpecularShellReflections = 0ull;
    unsigned long long simpleSpecularNonPositiveLabNormal = 0ull;
    unsigned long long simpleSpecularInteriorFinalOutside = 0ull;
    unsigned long long simpleSpecularShellFinalOutside = 0ull;
    double simpleSpecularSpeedSqAbsErrorSum = 0.0;
    double simpleSpecularSpeedSqReferenceSum = 0.0;
    double simpleSpecularPositionShiftAbsSum = 0.0;

    // 0493x10k local-liquid-frame specular ablation.
    unsigned long long localFrameSpecularReflections = 0ull;
    unsigned long long localFrameInteriorCollisions = 0ull;
    unsigned long long localFrameShellReflections = 0ull;
    unsigned long long localFrameRelativeStillOutward = 0ull;
    unsigned long long localFrameInteriorEndpointOuter = 0ull;
    unsigned long long localFrameShellEndpointOuter = 0ull;
    double localFrameRelativeSpeedSqAbsErrorSum = 0.0;
    double localFrameRelativeSpeedSqReferenceSum = 0.0;
    double localFrameLabSpeedSqChangeSum = 0.0;
    double localFrameLabSpeedSqAbsChangeSum = 0.0;
    double localFramePositionShiftAbsSum = 0.0;

    // 0493x10l passive pre-wall-interface diagnostics.
    // Geometry: alpha=.5 interface cells. Velocity: post-Q6/B1 phase-A
    // cell-mean velocity from the already-existing total moment deposit.
    unsigned long long preWallInterfaceCells = 0ull;
    unsigned long long preWallVelocityCells = 0ull;
    unsigned long long preWallPositiveVnCells = 0ull;
    unsigned long long preWallNegativeVnCells = 0ull;
    unsigned long long preWallLowerTipScore = 0ull;
    unsigned long long preWallLowerTipCells = 0ull;
    unsigned long long preWallLowerTipPositiveVnCells = 0ull;
    unsigned long long preWallLowerTipNegativeVnCells = 0ull;
    double preWallVnSum = 0.0;
    double preWallVnSqSum = 0.0;
    double preWallAbsVnSum = 0.0;
    double preWallVelocityMassSum = 0.0;
    double preWallMassVnSum = 0.0;
    double preWallNetNormalFluxProxy = 0.0;
    double preWallInterfaceLengthProxy = 0.0;
    double preWallAlphaArea = 0.0;
    double preWallLowerTipY = 0.0;
    double preWallLowerTipVnSum = 0.0;
    double preWallLowerTipVnSqSum = 0.0;
    double preWallLowerTipAbsVnSum = 0.0;
    double preWallLowerTipMassSum = 0.0;
    double preWallLowerTipMassVnSum = 0.0;

    // 0493x10m local moving-interface-wall diagnostics.
    unsigned long long movingWallInterfaceCellsBuilt = 0ull;
    unsigned long long movingWallInterfaceVelocityFallbacks = 0ull;
    unsigned long long movingWallInvalidInterfaceCells = 0ull;
    unsigned long long movingWallParticlesWithCandidate = 0ull;
    unsigned long long movingWallOldStationaryCrossingCandidates = 0ull;
    unsigned long long movingWallOldStationaryCrossingReleased = 0ull;
    unsigned long long movingWallCollisions = 0ull;
    unsigned long long movingWallAdvanceCollisions = 0ull;
    unsigned long long movingWallRecedeCollisions = 0ull;
    unsigned long long movingWallStationaryCollisions = 0ull;
    unsigned long long movingWallMultipleCollisionCandidates = 0ull;
    unsigned long long movingWallRelativeStillOutward = 0ull;
    unsigned long long movingWallFinalRelativeOutside = 0ull;
    double movingWallCollisionTimeFractionSum = 0.0;
    double movingWallWallVnSum = 0.0;
    double movingWallWallVnSqSum = 0.0;
    double movingWallWallVnAbsSum = 0.0;
    double movingWallRelativeSpeedSqAbsErrorSum = 0.0;
    double movingWallRelativeSpeedSqReferenceSum = 0.0;
    double movingWallImpulseX = 0.0;
    double movingWallImpulseY = 0.0;
    double movingWallImpulseAbsSum = 0.0;
    double movingWallPositionShiftAbsSum = 0.0;

    // 0493x10n Q6-consistent continuous alpha=.5 polyline diagnostics.
    unsigned long long continuousWallDualCellsVisited = 0ull;
    unsigned long long continuousWallInterfaceDualCells = 0ull;
    unsigned long long continuousWallSegmentsBuilt = 0ull;
    unsigned long long continuousWallAmbiguousDualCells = 0ull;
    unsigned long long continuousWallInvalidDualCells = 0ull;
    unsigned long long continuousWallParticlesWithCandidate = 0ull;
    unsigned long long continuousWallOldStationaryCrossingCandidates = 0ull;
    unsigned long long continuousWallOldStationaryCrossingReleased = 0ull;
    unsigned long long continuousWallNoNearbySegment = 0ull;
    unsigned long long continuousWallCandidateNoHit = 0ull;
    unsigned long long continuousWallCollisions = 0ull;
    unsigned long long continuousWallSecondCollisions = 0ull;
    unsigned long long continuousWallThirdCollisions = 0ull;
    unsigned long long continuousWallCollisionLimitReached = 0ull;
    unsigned long long continuousWallMultipleCollisionCandidates = 0ull;
    unsigned long long continuousWallRelativeStillOutward = 0ull;
    double continuousWallCollisionTimeFractionSum = 0.0;
    double continuousWallWallVnSum = 0.0;
    double continuousWallWallVnSqSum = 0.0;
    double continuousWallWallVnAbsSum = 0.0;
    double continuousWallRelativeSpeedSqAbsErrorSum = 0.0;
    double continuousWallRelativeSpeedSqReferenceSum = 0.0;
    double continuousWallImpulseX = 0.0;
    double continuousWallImpulseY = 0.0;
    double continuousWallImpulseAbsSum = 0.0;
    double continuousWallPositionShiftAbsSum = 0.0;

    // 0493x10o: Q6-hydrodynamic velocity + finite thermal interface layer.
    unsigned long long q6ThermalHydroCapturedCells = 0ull;
    unsigned long long q6ThermalInterfaceEndpointSamples = 0ull;
    unsigned long long q6ThermalHydroFallbacks = 0ull;
    double q6ThermalHydroVnSum = 0.0;
    double q6ThermalHydroVnSqSum = 0.0;
    double q6ThermalHydroAbsVnSum = 0.0;
    double q6ThermalThicknessSum = 0.0;

    // 0493x10p: resolve a particle which starts a step already on the
    // vacuum side of the kinetic (thermally shifted) moving interface.
    unsigned long long x10pInitialOutside = 0ull;
    unsigned long long x10pInitialOverlapResolved = 0ull;
    unsigned long long x10pInitialOverlapOutwardReflected = 0ull;
    unsigned long long x10pInitialOverlapInwardReleased = 0ull;
    unsigned long long x10pInitialOutsideTooDeep = 0ull;
    double x10pInitialOverlapPenetrationSum = 0.0;
    double x10pInitialOverlapMaxPenetration = 0.0;

    // 0493x10q: rare broad-phase recovery when the normal 3x3 search cannot
    // see the reconstructed kinetic interface from a vacuum-side cell.
    unsigned long long x10qWideSearchTriggered = 0ull;
    unsigned long long x10qWideSearchFoundSegment = 0ull;
    unsigned long long x10qOrphanNoSegmentAfterWideSearch = 0ull;
    unsigned long long x10qDeepOverlapResolved = 0ull;
    unsigned long long x10qOverlapResolveFailure = 0ull;
    double x10qResolvedNearestDistanceMax = 0.0;
};

struct KineticGlobalReaction0493x10f {
    double A = 0.0;
    double Sx = 0.0;
    double Sy = 0.0;
    double H = 0.0;
    double receiverM = 0.0;
    double receiverPx = 0.0;
    double receiverPy = 0.0;
    double cellSNormSum = 0.0;
    unsigned long long donorCells = 0ull;
    unsigned long long receiverCells = 0ull;

    double a = 0.0;
    double dux = 0.0;
    double duy = 0.0;
    int active = 0;
    int trivial = 0;
    int invalid = 0;
};

struct KineticGlobalReactionPartial0493x10g {
    double A = 0.0;
    double Sx = 0.0;
    double Sy = 0.0;
    double H = 0.0;
    double receiverM = 0.0;
    double receiverPx = 0.0;
    double receiverPy = 0.0;
    double cellSNormSum = 0.0;
    unsigned long long donorCells = 0ull;
    unsigned long long receiverCells = 0ull;
};

struct ResidentWorkspace0400 {
    CudaCellWorkspace cells;
    DeviceBuffer0400<double> rhs;
    DeviceBuffer0400<double> phi;
    DeviceBuffer0400<double> r;
    DeviceBuffer0400<double> p;
    DeviceBuffer0400<double> Ap;
    DeviceBuffer0400<double> dux;
    DeviceBuffer0400<double> duy;
    DeviceBuffer0400<unsigned char> speciesMask0493w5;
    // 0493w6 keeps the exact pre-application support mask of every species on
    // device.  The post-application diagnostic therefore cannot be perturbed by
    // a second threshold evaluation or require a host-side cell mask.
    DeviceBuffer0400<unsigned char> speciesMasks0493w6;
    DeviceBuffer0400<double> speciesDUx0493w5;
    DeviceBuffer0400<double> speciesDUy0493w5;
    // 0493x6a introduced this gas-pressure potential buffer diagnostically;
    // 0493x6g reuses it in production as the gauge-relative gas pressure
    // potential sampled by the prepared physical interface.
    DeviceBuffer0400<double> phaseGasPressurePotential0493x6a;
    // 0493x6b uses one tiny accumulator only.  The phase fill is reconstructed
    // on demand from the existing species-cell mass deposit, so there is no
    // additional O(numCells) resident geometry field in this diagnostic stage.
    DeviceBuffer0400<PhaseGeometryAccumulator0493x6b> phaseGeometryAccum0493x6b;
    // 0493x6c permanent-shape scaffold: raw phase fill and its one-step
    // conservative filtered geometry stay resident on CUDA.  Future Q6, gas
    // pressure and surface-tension stages are expected to share these buffers.
    DeviceBuffer0400<double> phaseFillRaw0493x6c;
    DeviceBuffer0400<double> phaseAlphaFiltered0493x6c;
    DeviceBuffer0400<PhaseGeometryResidentAccumulator0493x6c>
        phaseGeometryResidentAccum0493x6c;
    // 0493x9h wall geometry is deliberately separate from physical x6c alpha.
    // Domain walls live in ghost geometry; chi-backed walls use 1-chi in cells.
    // These fields are passive in x9h and become the future contact-angle input.
    DeviceBuffer0400<double> phaseWallFraction0493x9h;
    DeviceBuffer0400<double> phaseWallNormalX0493x9h;
    DeviceBuffer0400<double> phaseWallNormalY0493x9h;
    DeviceBuffer0400<WallGeometryAccumulator0493x9h> phaseWallGeometryAccum0493x9h;
    // x9i keeps only one scalar accumulator; corrected normals reuse the
    // production p3 normal arrays and do not allocate another cell field.
    DeviceBuffer0400<ContactAngleAccumulator0493x9i> contactAngleAccum0493x9i;
    // 0493x9a passive capillary geometry.  These arrays are allocated only
    // behind the x9a gate and are not consumed by the projection in this patch.
    DeviceBuffer0400<double> phaseNormalX0493x9a;
    DeviceBuffer0400<double> phaseNormalY0493x9a;
    DeviceBuffer0400<double> phaseCurvature0493x9a;
    DeviceBuffer0400<PhaseCurvatureAccumulator0493x9a>
        phaseCurvatureAccum0493x9a;
    // 0493x9b keeps a curvature-specific smoothed alpha separate from x6c.
    // This is diagnostic geometry only: x6f continues to consume x6c alpha.
    DeviceBuffer0400<double> phaseAlphaCurvature0493x9b;
    DeviceBuffer0400<double> phaseNormalX0493x9b;
    DeviceBuffer0400<double> phaseNormalY0493x9b;
    DeviceBuffer0400<double> phaseCurvature0493x9b;
    DeviceBuffer0400<PhaseCurvatureAccumulator0493x9a>
        phaseCurvatureAccum0493x9b;
    bool phaseCurvatureValid0493x9b = false;
    int phaseCurvatureNx0493x9b = 0;
    int phaseCurvatureNy0493x9b = 0;
    int phaseCurvatureStep0493x9b = -1;
    // 0493x9c passive support sweep: S2 and S3 alpha fields plus their final
    // curvatures.  x9b normals are reused sequentially because x9c is
    // summary-cadence only and no production path consumes those normals.
    DeviceBuffer0400<double> phaseAlphaCurvature2Pass0493x9c;
    DeviceBuffer0400<double> phaseAlphaCurvature3Pass0493x9c;
    DeviceBuffer0400<double> phaseCurvature2Pass0493x9c;
    DeviceBuffer0400<double> phaseCurvature3Pass0493x9c;
    DeviceBuffer0400<PhaseCurvatureAccumulator0493x9a>
        phaseCurvatureAccum2Pass0493x9c;
    DeviceBuffer0400<PhaseCurvatureAccumulator0493x9a>
        phaseCurvatureAccum3Pass0493x9c;
    // 0493x9d promotes the x9c p3 candidate to the production capillary field.
    bool phaseCurvature3PassValid0493x9d = false;
    int phaseCurvature3PassNx0493x9d = 0;
    int phaseCurvature3PassNy0493x9d = 0;
    int phaseCurvature3PassStep0493x9d = -1;
    // 0493x9e summary-cadence scalar accumulators only; no O(Ncell) diagnostic
    // storage is added.  They observe p3/x6c/phi and the existing species deposit.
    DeviceBuffer0400<StaticDropCellAccumulator0493x9e> staticDropCellAccum0493x9e;
    DeviceBuffer0400<StaticDropFaceAccumulator0493x9e> staticDropFaceAccum0493x9e;
    DeviceBuffer0400<StaticDropVelocityAccumulator0493x9e> staticDropVelocityAccum0493x9e;
    // 0493x9f keeps only scalar accumulators: no persistent diagnostic mask is
    // allocated.  The true interface band is tested directly from x6c alpha.
    DeviceBuffer0400<EllipseParticleMomentAccumulator0493x9f> ellipseParticleMomentAccum0493x9f;
    DeviceBuffer0400<EllipseInterfaceRadiusAccumulator0493x9f> ellipseInterfaceRadiusAccum0493x9f;
    // 0493x6f resident pressure-domain stencil.  These are allocated lazily
    // only when the x6f path is requested.  X/Y coefficients are stored on the
    // east/north face owned by each cell and are reused by every CG iteration.
    DeviceBuffer0400<unsigned char> phasePressureMask0493x6f;
    DeviceBuffer0400<double> phaseFaceCoeffX0493x6f;
    DeviceBuffer0400<double> phaseFaceCoeffY0493x6f;
    // 0493x6g stores the interfacial Dirichlet potential on the same owned
    // east/north faces.  These values are read by RHS assembly and by the
    // velocity correction, but never by the CG matrix-vector product.
    DeviceBuffer0400<double> phaseFacePhiGammaX0493x6g;
    DeviceBuffer0400<double> phaseFacePhiGammaY0493x6g;
    DeviceBuffer0400<PhaseInterfaceStencilAccumulator0493x6f>
        phaseInterfaceStencilAccum0493x6f;
    // 0493x6h-B0 stays lazily allocated: production paths pay neither an
    // allocation nor a kernel launch unless the diagnostic gate is enabled.
    DeviceBuffer0400<Q6PostApplyRegionAccumulator0493x6hB0>
        postApplyRegionAccum0493x6hB0;
    // 0493x7a uses the existing temporary cell correction buffers (dux/duy)
    // for the virial kick and only adds this O(1) resident accumulator.
    DeviceBuffer0400<VirialDensityAccumulator0493x7a>
        virialDensityAccum0493x7a;
    DeviceBuffer0400<Q6PeriodicMomentumAccumulator0493x7dv2fix2>
        periodicMomentumAccum0493x7dv2fix2;
    DeviceBuffer0400<Q6GfResidentCgState0493x7j> q6GfResidentCgState0493x7j;
    // 0493x9t: nine scalar cell fields are allocated only when kinetic
    // reflection is active.  They hold total-A, reflected-candidate and
    // transmitted-candidate mass/momentum for an exactly conservative
    // local group collision.
    DeviceBuffer0400<double> kineticTotalM0493x9t;
    DeviceBuffer0400<double> kineticTotalPx0493x9t;
    DeviceBuffer0400<double> kineticTotalPy0493x9t;
    DeviceBuffer0400<double> kineticRefM0493x9t;
    DeviceBuffer0400<double> kineticRefPx0493x9t;
    DeviceBuffer0400<double> kineticRefPy0493x9t;
    DeviceBuffer0400<double> kineticTxM0493x9t;
    DeviceBuffer0400<double> kineticTxPx0493x9t;
    DeviceBuffer0400<double> kineticTxPy0493x9t;
    DeviceBuffer0400<KineticInterfaceAccumulator0493x9t> kineticAccum0493x9t;
    // 0493x9u adds only two O(Ncell) scalar arrays: mass-weighted
    // interface-normal sums for donor groups sharing one inward bath.
    DeviceBuffer0400<double> kineticRefNx0493x9u;
    DeviceBuffer0400<double> kineticRefNy0493x9u;
    DeviceBuffer0400<KineticInterfaceAccumulator0493x9u> kineticAccum0493x9u;
    DeviceBuffer0400<KineticCrossingAccumulator0493x9x> kineticAccum0493x9x;
    DeviceBuffer0400<KineticGlobalReaction0493x10f> kineticGlobalReaction0493x10f;
    // 0493x10g performance-only: one atomics-free reduction record per cell block.
    DeviceBuffer0400<KineticGlobalReactionPartial0493x10g> kineticGlobalReactionPartials0493x10g;

    // 0493x10m one-step local moving interface. Geometry comes from alpha=.5;
    // wallVn comes from the post-Q6/B1 phase-A velocity field.
    DeviceBuffer0400<unsigned char> kineticMovingWallActive0493x10m;
    DeviceBuffer0400<double> kineticMovingWallNx0493x10m;
    DeviceBuffer0400<double> kineticMovingWallNy0493x10m;
    DeviceBuffer0400<double> kineticMovingWallQx0493x10m;
    DeviceBuffer0400<double> kineticMovingWallQy0493x10m;
    DeviceBuffer0400<double> kineticMovingWallVn0493x10m;
    DeviceBuffer0400<double> kineticMovingWallImpulseX0493x10m;
    DeviceBuffer0400<double> kineticMovingWallImpulseY0493x10m;

    // 0493x10n continuous interface on the cell-centre dual grid.  Every dual
    // square owns 0, 1 or 2 segments; shared Q6-style edge crossings are
    // computed from the same two alpha cell values, so neighboring segments
    // have exactly matching endpoints.
    DeviceBuffer0400<unsigned char> kineticContinuousSegCount0493x10n;
    DeviceBuffer0400<double> kineticContinuousSegAx0493x10n;
    DeviceBuffer0400<double> kineticContinuousSegAy0493x10n;
    DeviceBuffer0400<double> kineticContinuousSegBx0493x10n;
    DeviceBuffer0400<double> kineticContinuousSegBy0493x10n;
    DeviceBuffer0400<double> kineticContinuousSegUax0493x10n;
    DeviceBuffer0400<double> kineticContinuousSegUay0493x10n;
    DeviceBuffer0400<double> kineticContinuousSegUbx0493x10n;
    DeviceBuffer0400<double> kineticContinuousSegUby0493x10n;

    // 0493x10o stores the projected liquid hydrodynamic field produced by Q6
    // before r/p/dux/duy are reused.  Cell values are tentative liquid COM
    // velocity + Q6 cell correction; east/north values carry the corresponding
    // projected Q6 face component.
    DeviceBuffer0400<unsigned char> kineticQ6HydroValid0493x10o;
    DeviceBuffer0400<double> kineticQ6HydroCellUx0493x10o;
    DeviceBuffer0400<double> kineticQ6HydroCellUy0493x10o;
    DeviceBuffer0400<double> kineticQ6HydroFaceUxEast0493x10o;
    DeviceBuffer0400<double> kineticQ6HydroFaceUyNorth0493x10o;
    bool kineticQ6HydroFieldValid0493x10o = false;
    int kineticQ6HydroFieldStep0493x10o = -1;
    std::uint32_t kineticQ6HydroFieldType0493x10o = 0u;
    bool phaseInterfaceStencilValid0493x6f = false;
    int phaseInterfaceStencilStep0493x6f = -1;
    bool phaseGeometryResidentValid0493x6c = false;
    int phaseGeometryResidentStep0493x6c = -1;
    bool phaseWallGeometryValid0493x9h = false;
    int phaseWallGeometryStep0493x9h = -1;
    double phaseGeometryReferenceCellMass0493x6c = 0.0;
    int phaseGeometryLiquidSpeciesCount0493x6c = 0;
    DeviceBuffer0400<double> partial0;
    DeviceBuffer0400<double> partial1;
    DeviceBuffer0400<double> partial2;
    DeviceBuffer0400<unsigned long long> counter;
    bool warmPhiValid = false;
    int warmNx = 0;
    int warmNy = 0;
    int warmPeriodicX = 0;
    int warmPeriodicY = 0;

    void ensure_kinetic_interface_0493x9t(int numCells) {
        const std::size_t c = static_cast<std::size_t>(std::max(1, numCells));
        kineticTotalM0493x9t.ensure(c); kineticTotalPx0493x9t.ensure(c); kineticTotalPy0493x9t.ensure(c);
        kineticRefM0493x9t.ensure(c); kineticRefPx0493x9t.ensure(c); kineticRefPy0493x9t.ensure(c);
        kineticTxM0493x9t.ensure(c); kineticTxPx0493x9t.ensure(c); kineticTxPy0493x9t.ensure(c);
        kineticAccum0493x9t.ensure(1u);
    }

    void ensure_kinetic_interface_0493x9u(int numCells) {
        ensure_kinetic_interface_0493x9t(numCells);
        const std::size_t c = static_cast<std::size_t>(std::max(1, numCells));
        kineticRefNx0493x9u.ensure(c);
        kineticRefNy0493x9u.ensure(c);
        kineticAccum0493x9u.ensure(1u);
    }

    void ensure_kinetic_interface_0493x9x(
        int numCells, int reactionBlocks = 1, int reactionReservoirs = 1) {
        ensure_kinetic_interface_0493x9u(numCells);
        kineticAccum0493x9x.ensure(1u);
        kineticGlobalReaction0493x10f.ensure(
            static_cast<std::size_t>(std::max(1, reactionReservoirs)));
        kineticGlobalReactionPartials0493x10g.ensure(
            static_cast<std::size_t>(std::max(1, reactionBlocks)));
        const std::size_t c = static_cast<std::size_t>(std::max(1, numCells));
        kineticMovingWallActive0493x10m.ensure(c);
        kineticMovingWallNx0493x10m.ensure(c);
        kineticMovingWallNy0493x10m.ensure(c);
        kineticMovingWallQx0493x10m.ensure(c);
        kineticMovingWallQy0493x10m.ensure(c);
        kineticMovingWallVn0493x10m.ensure(c);
        kineticMovingWallImpulseX0493x10m.ensure(c);
        kineticMovingWallImpulseY0493x10m.ensure(c);
        kineticContinuousSegCount0493x10n.ensure(c);
        const std::size_t s2 = 2u * c;
        kineticContinuousSegAx0493x10n.ensure(s2);
        kineticContinuousSegAy0493x10n.ensure(s2);
        kineticContinuousSegBx0493x10n.ensure(s2);
        kineticContinuousSegBy0493x10n.ensure(s2);
        kineticContinuousSegUax0493x10n.ensure(s2);
        kineticContinuousSegUay0493x10n.ensure(s2);
        kineticContinuousSegUbx0493x10n.ensure(s2);
        kineticContinuousSegUby0493x10n.ensure(s2);
    }

    void ensure(std::uint64_t particles, int numCells, int blocks, int speciesCount = 1) {
        cells.ensure_capacity(particles, numCells);
        const std::size_t c = static_cast<std::size_t>(std::max(1, numCells));
        const std::size_t denseSpecies = c * static_cast<std::size_t>(std::max(1, speciesCount));
        rhs.ensure(c);
        phi.ensure(c);
        r.ensure(c);
        p.ensure(c);
        Ap.ensure(c);
        dux.ensure(c);
        duy.ensure(c);
        speciesMask0493w5.ensure(c);
        speciesMasks0493w6.ensure(denseSpecies);
        speciesDUx0493w5.ensure(denseSpecies);
        speciesDUy0493w5.ensure(denseSpecies);
        phaseGasPressurePotential0493x6a.ensure(c);
        phaseGeometryAccum0493x6b.ensure(1u);
        phaseGeometryResidentAccum0493x6c.ensure(1u);
        phaseWallGeometryAccum0493x9h.ensure(1u);
        contactAngleAccum0493x9i.ensure(1u);
        phaseCurvatureAccum0493x9a.ensure(1u);
        phaseCurvatureAccum0493x9b.ensure(1u);
        phaseInterfaceStencilAccum0493x6f.ensure(1u);
        periodicMomentumAccum0493x7dv2fix2.ensure(1u);
        q6GfResidentCgState0493x7j.ensure(1u);
        partial0.ensure(static_cast<std::size_t>(std::max(1, blocks)));
        partial1.ensure(static_cast<std::size_t>(std::max(1, blocks)));
        partial2.ensure(static_cast<std::size_t>(std::max(1, blocks)));
        counter.ensure(1u);
    }
};

ResidentWorkspace0400& resident_workspace_0400() {
    static ResidentWorkspace0400 ws;
    return ws;
}

__device__ double atomic_add_double_0400(double* address, double value) {
#if __CUDA_ARCH__ >= 600
    return atomicAdd(address, value);
#else
    unsigned long long int* addressAsUll = reinterpret_cast<unsigned long long int*>(address);
    unsigned long long int old = *addressAsUll;
    unsigned long long int assumed = 0ull;
    do {
        assumed = old;
        old = atomicCAS(addressAsUll,
                        assumed,
                        __double_as_longlong(value + __longlong_as_double(assumed)));
    } while (assumed != old);
    return __longlong_as_double(old);
#endif
}

__global__ void q6_zero_cells_0400(CudaCellWorkspaceDeviceView cells,
                                   double* rhs,
                                   double* phi,
                                   double* r,
                                   double* p,
                                   double* Ap,
                                   double* dux,
                                   double* duy,
                                   int resetPhi) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        cells.count[c] = 0u;
        cells.cellMass[c] = 0.0;
        cells.cellPx[c] = 0.0;
        cells.cellPy[c] = 0.0;
        cells.cellUx[c] = 0.0;
        cells.cellUy[c] = 0.0;
        rhs[c] = 0.0;
        if (resetPhi) phi[c] = 0.0;
        r[c] = 0.0;
        p[c] = 0.0;
        Ap[c] = 0.0;
        dux[c] = 0.0;
        duy[c] = 0.0;
    }
}

__global__ void q6_zero_particle_cell_ids_0400(CudaCellWorkspaceDeviceView cells,
                                              std::uint64_t nParticles) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        cells.cellId[i] = -1;
    }
}

__device__ int wrap_cell_index_0400(int i, int n) {
    if (i < 0) {
        return i + n;
    }
    if (i >= n) {
        return i - n;
    }
    return i;
}

__global__ void q6_deposit_periodic_0400(CudaParticleDeviceView particles,
                                         CudaCellWorkspaceDeviceView cells,
                                         std::uint64_t nParticles,
                                         int nx,
                                         int ny,
                                         double lx,
                                         double ly,
                                         int periodicX,
                                         int periodicY) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        double x = particles.x[i];
        double y = particles.y[i];
        if (periodicX) {
            x -= floor(x / lx) * lx;
        } else {
            x = fmin(fmax(x, 0.0), nextafter(lx, 0.0));
        }
        if (periodicY) {
            y -= floor(y / ly) * ly;
        } else {
            y = fmin(fmax(y, 0.0), nextafter(ly, 0.0));
        }
        int ix = static_cast<int>(floor(x / dx));
        int iy = static_cast<int>(floor(y / dy));
        if (periodicX) {
            ix = wrap_cell_index_0400(ix, nx);
        } else {
            if (ix < 0) ix = 0;
            if (ix >= nx) ix = nx - 1;
        }
        if (periodicY) {
            iy = wrap_cell_index_0400(iy, ny);
        } else {
            if (iy < 0) iy = 0;
            if (iy >= ny) iy = ny - 1;
        }
        const int c = iy * nx + ix;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        cells.cellId[i] = c;
        atomicAdd(&cells.count[c], 1u);
        atomic_add_double_0400(&cells.cellMass[c], m);
        atomic_add_double_0400(&cells.cellPx[c], m * particles.vx[i]);
        atomic_add_double_0400(&cells.cellPy[c], m * particles.vy[i]);
    }
}

__global__ void q6_deposit_tentative_force_0493x4b(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    int nx,
    int ny,
    double lx,
    double ly,
    int periodicX,
    int periodicY,
    double dt,
    double bodyAx,
    double bodyAy,
    int tgEnable,
    double tgAmplitude,
    int tgModeX,
    int tgModeY) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const double forceX = particles.x[i];
        const double forceY = particles.y[i];
        double x = forceX;
        double y = forceY;
        if (periodicX) {
            x -= floor(x / lx) * lx;
        } else {
            x = fmin(fmax(x, 0.0), nextafter(lx, 0.0));
        }
        if (periodicY) {
            y -= floor(y / ly) * ly;
        } else {
            y = fmin(fmax(y, 0.0), nextafter(ly, 0.0));
        }
        int ix = static_cast<int>(floor(x / dx));
        int iy = static_cast<int>(floor(y / dy));
        if (periodicX) {
            ix = wrap_cell_index_0400(ix, nx);
        } else {
            if (ix < 0) ix = 0;
            if (ix >= nx) ix = nx - 1;
        }
        if (periodicY) {
            iy = wrap_cell_index_0400(iy, ny);
        } else {
            if (iy < 0) iy = 0;
            if (iy >= ny) iy = ny - 1;
        }
        const int c = iy * nx + ix;
        double ax = 0.0;
        double ay = 0.0;
        q6_force_acceleration_0493x4b(
            forceX, forceY, lx, ly, bodyAx, bodyAy, tgEnable, tgAmplitude,
            tgModeX, tgModeY, &ax, &ay);
        const double vxTentative = particles.vx[i] + ax * dt;
        const double vyTentative = particles.vy[i] + ay * dt;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        cells.cellId[i] = c;
        atomicAdd(&cells.count[c], 1u);
        atomic_add_double_0400(&cells.cellMass[c], m);
        atomic_add_double_0400(&cells.cellPx[c], m * vxTentative);
        atomic_add_double_0400(&cells.cellPy[c], m * vyTentative);
    }
}

__global__ void q6_finalize_cells_0400(CudaCellWorkspaceDeviceView cells,
                                       unsigned long long* emptyCounter) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        const double m = cells.cellMass[c];
        if (m > 0.0) {
            cells.cellUx[c] = cells.cellPx[c] / m;
            cells.cellUy[c] = cells.cellPy[c] / m;
        } else {
            cells.cellUx[c] = 0.0;
            cells.cellUy[c] = 0.0;
            atomicAdd(emptyCounter, 1ull);
        }
    }
}

__device__ double q6_segmented_profiled_flux_0493x8k(
    const Q6SegmentedIo0409& cfg,
    int segmentIndex,
    double tangent) {
    if (segmentIndex < 0 || segmentIndex >= cfg.count) return 0.0;
    if (cfg.mode[segmentIndex] != 1 || cfg.inletProfileCode == 0) {
        return cfg.flux[segmentIndex];
    }

    const double sMin = cfg.sMin[segmentIndex];
    const double sMax = cfg.sMax[segmentIndex];
    const double span = sMax - sMin;
    if (!(span > 0.0)) return 0.0;

    const double xi = fmin(1.0, fmax(0.0, (tangent - sMin) / span));
    const double shape = xi * (1.0 - xi);
    const double factor =
        cfg.inletProfileCode == 1 ? 4.0 * shape : 6.0 * shape;
    return cfg.flux[segmentIndex] * factor;
}

__device__ double q6_segmented_flux_for_cell_0409(const Q6SegmentedIo0409& cfg,
                                                        int face,
                                                        int ix,
                                                        int iy,
                                                        int nx,
                                                        int ny,
                                                        double fallback) {
    if (!cfg.enabled) return fallback;
    const double s = (face == 0 || face == 1)
        ? ((static_cast<double>(iy) + 0.5) / static_cast<double>(ny > 0 ? ny : 1))
        : ((static_cast<double>(ix) + 0.5) / static_cast<double>(nx > 0 ? nx : 1));
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] == face && s >= cfg.sMin[k] && s <= cfg.sMax[k]) {
            return q6_segmented_profiled_flux_0493x8k(cfg, k, s);
        }
    }
    return 0.0;
}



__device__ double q6_species_boundary_fraction_0493w7(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    int cell,
    int exclusiveProjectedSpecies) {
    if (exclusiveProjectedSpecies) return 1.0;
    if (speciesIndex < 0 || speciesIndex >= species.speciesCount ||
        cell < 0 || cell >= species.numCells) {
        return 0.0;
    }
    const int k = speciesIndex * species.numCells + cell;
    return fmin(1.0, fmax(0.0, species.occupancyFraction[k]));
}

__device__ bool q6_passive_pressure_outlet_right_cell_0493x8r(
    const Q6SegmentedIo0409& cfg,
    int ix,
    int iy,
    int nx,
    int ny) {
    if (!cfg.enabled || !cfg.passiveNeumannRightOutlet0493x8l ||
        ix != nx - 1 || ny <= 0) {
        return false;
    }
    const double tangent =
        (static_cast<double>(iy) + 0.5) / static_cast<double>(ny);
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] == 1 && cfg.mode[k] == 2 &&
            tangent >= cfg.sMin[k] && tangent <= cfg.sMax[k]) {
            return true;
        }
    }
    return false;
}

__device__ double q6_species_boundary_flux_for_cell_0493w7(
    const Q6SegmentedIo0409& cfg,
    int face,
    int ix,
    int iy,
    int nx,
    int ny,
    double fallback,
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    std::uint32_t speciesType,
    int cell,
    int exclusiveProjectedSpecies) {
    const double fraction = q6_species_boundary_fraction_0493w7(
        species, speciesIndex, cell, exclusiveProjectedSpecies);
    if (!cfg.enabled) return fallback * fraction;
    const double tangent = (face == 0 || face == 1)
        ? ((static_cast<double>(iy) + 0.5) /
           static_cast<double>(ny > 0 ? ny : 1))
        : ((static_cast<double>(ix) + 0.5) /
           static_cast<double>(nx > 0 ? nx : 1));
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] != face || tangent < cfg.sMin[k] || tangent > cfg.sMax[k]) {
            continue;
        }
        // 0493x8l + 0493x8r passive right outlet.
        // Extrapolate the current boundary-cell ux to the BASE outlet face:
        // u*_out = u*_cell, i.e. zero normal gradient of the predictor
        // velocity.  x8r no longer treats this value as a prescribed final
        // flux: the pressure solve uses phi=0 at the outlet face and is free
        // to add the normal pressure correction required by continuity.
        if (cfg.mode[k] == 2 && cfg.passiveNeumannRightOutlet0493x8l && face == 1) {
            if (speciesIndex < 0 || speciesIndex >= species.speciesCount ||
                cell < 0 || cell >= species.numCells) {
                return 0.0;
            }
            const int sk = speciesIndex * species.numCells + cell;
            const double m = species.mass[sk];
            if (!(m > 0.0)) return 0.0;
            const double localUx = species.px[sk] / m;
            return localUx * fraction;
        }

        const double targetFlux =
            q6_segmented_profiled_flux_0493x8k(cfg, k, tangent);
        if (cfg.mode[k] == 1) {
            // A typed reservoir injects only its declared species.  Untyped
            // legacy inlets fall back to the local occupancy split.
            if (cfg.type[k] != 0u) {
                return cfg.type[k] == speciesType ? targetFlux : 0.0;
            }
            return targetFlux * fraction;
        }
        // Outlet flux is shared only when several species are independently
        // projected.  With the liquid-only target configuration, the sole
        // projected species retains the full prescribed outlet flux.
        return targetFlux * fraction;
    }
    // The complement of a segmented face remains an impermeable wall.
    return 0.0;
}

// 0493x6h-B0 is defined before the independent-masked helper bodies below.
// Keep declarations here so the diagnostic kernel reuses exactly the same
// cell/face velocity semantics as the production Q6 path without duplicating
// any logic.
__device__ double q6_species_cell_velocity_component_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    int cell,
    int component);

__device__ double q6_species_face_velocity_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    const unsigned char* mask,
    int speciesIndex,
    int cellA,
    int cellB,
    int component);

__device__ bool q6_segmented_face_is_open_for_cell_0493x6h_b0(
    const Q6SegmentedIo0409& cfg,
    int face,
    int ix,
    int iy,
    int nx,
    int ny) {
    if (!cfg.enabled) return false;
    const double tangent = (face == 0 || face == 1)
        ? ((static_cast<double>(iy) + 0.5) /
           static_cast<double>(ny > 0 ? ny : 1))
        : ((static_cast<double>(ix) + 0.5) /
           static_cast<double>(nx > 0 ? nx : 1));
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] == face && tangent >= cfg.sMin[k] &&
            tangent <= cfg.sMax[k]) {
            return true;
        }
    }
    return false;
}

__global__ void q6_postapply_region_stats_0493x6h_b0(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const unsigned char* mask,
    const double* phaseAlpha,
    int interfaceGeometryAvailable,
    Q6PostApplyRegionAccumulator0493x6hB0* accum,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    double xLowFlux,
    double yLowFlux,
    Q6SegmentedIo0409 segmentedIo,
    std::uint32_t speciesType,
    int exclusiveProjectedSpecies,
    int fullDomain,
    int wallLikeLeft,
    int wallLikeRight,
    int wallLikeBottom,
    int wallLikeTop) {
    __shared__ unsigned long long shCells[kQ6PostApplyRegionCount0493x6hB0];
    __shared__ double shDivSq[kQ6PostApplyRegionCount0493x6hB0];
    __shared__ unsigned long long shMaxBits[kQ6PostApplyRegionCount0493x6hB0];
    const int tid = threadIdx.x;
    if (tid < kQ6PostApplyRegionCount0493x6hB0) {
        shCells[tid] = 0ull;
        shDivSq[tid] = 0.0;
        shMaxBits[tid] = 0ull;
    }
    __syncthreads();

    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (mask[c] == 0u) continue;
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasWest = periodicX || ix > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const bool hasSouth = periodicY || iy > 0;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;

        const double localXLowFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 0, ix, iy, nx, ny, xLowFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);
        const double localYLowFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 2, ix, iy, nx, ny, yLowFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);

        const double uxC = q6_species_cell_velocity_component_0493w5(
            species, speciesIndex, c, 0);
        const double uyC = q6_species_cell_velocity_component_0493w5(
            species, speciesIndex, c, 1);
        const double fxEastInterior = fullDomain
            ? uxC
            : q6_species_face_velocity_0493w5(
                species, mask, speciesIndex, c, east, 0);
        const double fxWestInterior = fullDomain
            ? q6_species_cell_velocity_component_0493w5(
                species, speciesIndex, west, 0)
            : q6_species_face_velocity_0493w5(
                species, mask, speciesIndex, west, c, 0);
        const double fyNorthInterior = fullDomain
            ? uyC
            : q6_species_face_velocity_0493w5(
                species, mask, speciesIndex, c, north, 1);
        const double fySouthInterior = fullDomain
            ? q6_species_cell_velocity_component_0493w5(
                species, speciesIndex, south, 1)
            : q6_species_face_velocity_0493w5(
                species, mask, speciesIndex, south, c, 1);
        const double fxWest = hasWest ? fxWestInterior : localXLowFlux;
        const double fxEastBefore = hasEast ? fxEastInterior : uxC;
        const double fySouth = hasSouth ? fySouthInterior : localYLowFlux;
        const double fyNorthBefore = hasNorth ? fyNorthInterior : uyC;
        const double div = (fxEastBefore - fxWest) / dx +
                           (fyNorthBefore - fySouth) / dy;

        bool interfaceAdjacent = false;
        if (interfaceGeometryAvailable && phaseAlpha != nullptr) {
            const bool highC = phaseAlpha[c] >= 0.5;
            if (hasEast && ((phaseAlpha[east] >= 0.5) != highC)) interfaceAdjacent = true;
            if (hasWest && ((phaseAlpha[west] >= 0.5) != highC)) interfaceAdjacent = true;
            if (hasNorth && ((phaseAlpha[north] >= 0.5) != highC)) interfaceAdjacent = true;
            if (hasSouth && ((phaseAlpha[south] >= 0.5) != highC)) interfaceAdjacent = true;
        }

        int wallTouches = 0;
        if (!periodicX && ix == 0 && wallLikeLeft &&
            !q6_segmented_face_is_open_for_cell_0493x6h_b0(
                segmentedIo, 0, ix, iy, nx, ny)) ++wallTouches;
        if (!periodicX && ix == nx - 1 && wallLikeRight &&
            !q6_segmented_face_is_open_for_cell_0493x6h_b0(
                segmentedIo, 1, ix, iy, nx, ny)) ++wallTouches;
        if (!periodicY && iy == 0 && wallLikeBottom &&
            !q6_segmented_face_is_open_for_cell_0493x6h_b0(
                segmentedIo, 2, ix, iy, nx, ny)) ++wallTouches;
        if (!periodicY && iy == ny - 1 && wallLikeTop &&
            !q6_segmented_face_is_open_for_cell_0493x6h_b0(
                segmentedIo, 3, ix, iy, nx, ny)) ++wallTouches;

        int region = Q6PostApplyBulk0493x6hB0;
        if (wallTouches >= 2) {
            region = interfaceAdjacent ? Q6PostApplyCornerInterface0493x6hB0
                                       : Q6PostApplyCorner0493x6hB0;
        } else if (wallTouches == 1) {
            region = interfaceAdjacent ? Q6PostApplyWallInterface0493x6hB0
                                       : Q6PostApplyWall0493x6hB0;
        } else if (interfaceAdjacent) {
            region = Q6PostApplyInterface0493x6hB0;
        }

        atomicAdd(&shCells[region], 1ull);
        atomicAdd(&shDivSq[region], div * div);
        const unsigned long long bits = static_cast<unsigned long long>(
            __double_as_longlong(fabs(div)));
        atomicMax(&shMaxBits[region], bits);
    }
    __syncthreads();
    if (tid < kQ6PostApplyRegionCount0493x6hB0) {
        atomicAdd(&accum->cells[tid], shCells[tid]);
        atomic_add_double_0400(&accum->divSq[tid], shDivSq[tid]);
        atomicMax(&accum->divMaxAbsBits[tid], shMaxBits[tid]);
    }
}

__global__ void q6_build_rhs_and_stats_0400(CudaCellWorkspaceDeviceView cells,
                                           double* rhs,
                                           double* partialSum,
                                           double* partialSq,
                                           double* partialMax,
                                           int nx,
                                           int ny,
                                           double dx,
                                           double dy,
                                           int periodicX,
                                           int periodicY,
                                           double xLowFlux,
                                           double xHighFlux,
                                           double yLowFlux,
                                           double yHighFlux,
                                           Q6SegmentedIo0409 segmentedIo) {
    extern __shared__ double sh[];
    double* sh0 = sh;
    double* sh1 = sh + blockDim.x;
    double* sh2 = sh + 2 * blockDim.x;
    const int tid = threadIdx.x;
    double sum = 0.0;
    double sq = 0.0;
    double mx = 0.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasWest = periodicX || ix > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const bool hasSouth = periodicY || iy > 0;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;
        const double localXLowFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 0, ix, iy, nx, ny, xLowFlux);
        const double localXHighFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 1, ix, iy, nx, ny, xHighFlux);
        const double localYLowFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 2, ix, iy, nx, ny, yLowFlux);
        const double localYHighFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 3, ix, iy, nx, ny, yHighFlux);

        // 0493x7p: common Q6 now uses the same reflection-equivariant FV
        // convention validated by 0493x7o for independent_masked Q6.  Cell
        // velocities are cell-centred quantities; an interior face therefore
        // carries the arithmetic average of its two adjacent cells instead of
        // inheriting the east/north owner value.  This removes the historical
        // backward-difference orientation from the common-Q6 RHS.
        const double fxEastInterior = 0.5 * (cells.cellUx[c] + cells.cellUx[east]);
        const double fxWestInterior = 0.5 * (cells.cellUx[west] + cells.cellUx[c]);
        const double fyNorthInterior = 0.5 * (cells.cellUy[c] + cells.cellUy[north]);
        const double fySouthInterior = 0.5 * (cells.cellUy[south] + cells.cellUy[c]);
        const double fxWest = hasWest ? fxWestInterior : localXLowFlux;
        const double fxEastBefore = hasEast ? fxEastInterior : localXHighFlux;
        const double fxEastSolve = hasEast ? fxEastInterior : localXHighFlux;
        const double fySouth = hasSouth ? fySouthInterior : localYLowFlux;
        const double fyNorthBefore = hasNorth ? fyNorthInterior : localYHighFlux;
        const double fyNorthSolve = hasNorth ? fyNorthInterior : localYHighFlux;
        const double divBefore = (fxEastBefore - fxWest) / dx +
                                 (fyNorthBefore - fySouth) / dy;
        const double divSolve = (fxEastSolve - fxWest) / dx +
                                (fyNorthSolve - fySouth) / dy;
        rhs[c] = -divSolve;
        sum += rhs[c];
        sq += divBefore * divBefore;
        mx = fmax(mx, fabs(divBefore));
    }
    sh0[tid] = sum;
    sh1[tid] = sq;
    sh2[tid] = mx;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh0[tid] += sh0[tid + offset];
            sh1[tid] += sh1[tid + offset];
            sh2[tid] = fmax(sh2[tid], sh2[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSum[blockIdx.x] = sh0[0];
        partialSq[blockIdx.x] = sh1[0];
        partialMax[blockIdx.x] = sh2[0];
    }
}

__global__ void q6_init_cg_0400(double* rhs,
                                double* phi,
                                double* r,
                                double* p,
                                double mean,
                                int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const double v = rhs[c] - mean;
        rhs[c] = v;
        phi[c] = 0.0;
        r[c] = v;
        p[c] = v;
    }
}

__global__ void q6_apply_operator_and_dot_0400(const double* p,
                                               double* Ap,
                                               double* partialDot,
                                               int nx,
                                               int ny,
                                               double invDx2,
                                               double invDy2,
                                               int periodicX,
                                               int periodicY) {
    extern __shared__ double sh[];
    const int tid = threadIdx.x;
    double dot = 0.0;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const int east = (periodicX || ix < nx - 1) ? (iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : (ix + 1))) : c;
        const int west = (periodicX || ix > 0) ? (iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : (ix - 1))) : c;
        const int north = (periodicY || iy < ny - 1) ? ((periodicY ? wrap_cell_index_0400(iy + 1, ny) : (iy + 1)) * nx + ix) : c;
        const int south = (periodicY || iy > 0) ? ((periodicY ? wrap_cell_index_0400(iy - 1, ny) : (iy - 1)) * nx + ix) : c;
        const double a = ((periodicX || ix < nx - 1) ? invDx2 * (p[c] - p[east]) : 0.0) +
                         ((periodicX || ix > 0) ? invDx2 * (p[c] - p[west]) : 0.0) +
                         ((periodicY || iy < ny - 1) ? invDy2 * (p[c] - p[north]) : 0.0) +
                         ((periodicY || iy > 0) ? invDy2 * (p[c] - p[south]) : 0.0);
        Ap[c] = a;
        dot += p[c] * a;
    }
    sh[tid] = dot;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh[tid] += sh[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialDot[blockIdx.x] = sh[0];
    }
}

// 0493x8t host-fallback helper: remove only the constant component of
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

__global__ void q6_reduce_square_sum_0400(const double* v,
                                          double* partial,
                                          int n) {
    extern __shared__ double sh[];
    const int tid = threadIdx.x;
    double sum = 0.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < n; i += stride) {
        sum += v[i] * v[i];
    }
    sh[tid] = sum;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh[tid] += sh[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partial[blockIdx.x] = sh[0];
    }
}

__global__ void q6_reduce_sum_0400(const double* v,
                                   double* partial,
                                   int n) {
    extern __shared__ double sh[];
    const int tid = threadIdx.x;
    double sum = 0.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < n; i += stride) {
        sum += v[i];
    }
    sh[tid] = sum;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh[tid] += sh[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partial[blockIdx.x] = sh[0];
    }
}

__global__ void q6_axpy_residual_0400(double* phi,
                                      double* r,
                                      const double* p,
                                      const double* Ap,
                                      double alpha,
                                      int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < n; i += stride) {
        phi[i] += alpha * p[i];
        r[i] -= alpha * Ap[i];
    }
}

__global__ void q6_update_p_0400(double* p,
                                 const double* r,
                                 double beta,
                                 int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < n; i += stride) {
        p[i] = r[i] + beta * p[i];
    }
}

__global__ void q6_subtract_mean_pair_0400(double* a,
                                           double* b,
                                           double meanA,
                                           double meanB,
                                           int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < n; i += stride) {
        a[i] -= meanA;
        b[i] -= meanB;
    }
}

__global__ void q6_compute_face_corrections_0493x7p(
    CudaCellWorkspaceDeviceView cells,
    const double* phi,
    double* faceDUx,
    double* faceDUy,
    int nx,
    int ny,
    double dx,
    double dy,
    double strength,
    int periodicX,
    int periodicY,
    double xHighFlux,
    double yHighFlux,
    Q6SegmentedIo0409 segmentedIo) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasNorth = periodicY || iy < ny - 1;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;
        const double localXHighFlux = q6_segmented_flux_for_cell_0409(
            segmentedIo, 1, ix, iy, nx, ny, xHighFlux);
        const double localYHighFlux = q6_segmented_flux_for_cell_0409(
            segmentedIo, 3, ix, iy, nx, ny, yHighFlux);

        // East/north-owned face corrections.  Interior faces are the discrete
        // pressure gradient.  On a physical high boundary the existing Q6
        // target-before convention is retained; the symmetric low-boundary
        // counterpart is reconstructed in q6_reconstruct_cell_corrections_0493x7p.
        faceDUx[c] = hasEast
            ? -strength * (phi[east] - phi[c]) / dx
            : strength * (localXHighFlux - cells.cellUx[c]);
        faceDUy[c] = hasNorth
            ? -strength * (phi[north] - phi[c]) / dy
            : strength * (localYHighFlux - cells.cellUy[c]);
    }
}

__global__ void q6_reconstruct_cell_corrections_0493x7p(
    CudaCellWorkspaceDeviceView cells,
    const double* faceDUx,
    const double* faceDUy,
    double* cellDUx,
    double* cellDUy,
    double* partialSq,
    double* partialMax,
    int nx,
    int ny,
    double strength,
    int periodicX,
    int periodicY,
    double xLowFlux,
    double yLowFlux,
    Q6SegmentedIo0409 segmentedIo) {
    extern __shared__ double sh[];
    double* shSq = sh;
    double* shMax = sh + blockDim.x;
    const int tid = threadIdx.x;
    double sq = 0.0;
    double mx = 0.0;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasWest = periodicX || ix > 0;
        const bool hasSouth = periodicY || iy > 0;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;

        double westCorrection = hasWest ? faceDUx[west] : 0.0;
        double southCorrection = hasSouth ? faceDUy[south] : 0.0;
        if (!hasWest) {
            const double target = q6_segmented_flux_for_cell_0409(
                segmentedIo, 0, ix, iy, nx, ny, xLowFlux);
            westCorrection = strength * (target - cells.cellUx[c]);
        }
        if (!hasSouth) {
            const double target = q6_segmented_flux_for_cell_0409(
                segmentedIo, 2, ix, iy, nx, ny, yLowFlux);
            southCorrection = strength * (target - cells.cellUy[c]);
        }

        // 0493x7p: a cell receives the mean of its two opposite face
        // corrections.  This is the common-Q6 analogue of the 0493x7o
        // independent_masked reconstruction and removes the east/north-owner
        // bias from the particle correction itself.
        const double cx = 0.5 * (faceDUx[c] + westCorrection);
        const double cy = 0.5 * (faceDUy[c] + southCorrection);
        cellDUx[c] = cx;
        cellDUy[c] = cy;
        sq += cx * cx + cy * cy;
        mx = fmax(mx, sqrt(cx * cx + cy * cy));
    }
    shSq[tid] = sq;
    shMax[tid] = mx;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shSq[tid] += shSq[tid + offset];
            shMax[tid] = fmax(shMax[tid], shMax[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSq[blockIdx.x] = shSq[0];
        partialMax[blockIdx.x] = shMax[0];
    }
}


// =============================================================================
// 0493x9t — kinetic liquid/vacuum retention / internal reflection
// =============================================================================

__device__ __forceinline__ unsigned long long q6_x9t_mix64(unsigned long long x) {
    x ^= x >> 30; x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27; x *= 0x94d049bb133111ebULL;
    x ^= x >> 31;
    return x;
}

__device__ __forceinline__ double q6_x9t_uniform01(
    unsigned long long particle,
    unsigned long long step,
    unsigned long long seed) {
    const unsigned long long h = q6_x9t_mix64(
        seed ^ (particle + 0x9e3779b97f4a7c15ULL) ^
        ((step + 0x632be59bd9b4e019ULL) * 0xd6e8feb86659fd93ULL));
    return static_cast<double>(h >> 11) * (1.0 / 9007199254740992.0);
}

__device__ __forceinline__ int q6_x9t_wrap_index(int i, int n) {
    if (i < 0) return i + n;
    if (i >= n) return i - n;
    return i;
}

__device__ __forceinline__ bool q6_x9t_cell_normal(
    const double* alpha,
    int c,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    double* nxOut,
    double* nyOut) {
    if (!alpha || c < 0 || c >= nx * ny) return false;
    const int ix = c % nx;
    const int iy = c / nx;
    int iw = ix - 1, ie = ix + 1, js = iy - 1, jn = iy + 1;
    if (periodicX) { iw = q6_x9t_wrap_index(iw, nx); ie = q6_x9t_wrap_index(ie, nx); }
    if (periodicY) { js = q6_x9t_wrap_index(js, ny); jn = q6_x9t_wrap_index(jn, ny); }
    const double ac = alpha[c];
    const double aw = (iw >= 0 && iw < nx) ? alpha[iy * nx + iw] : ac;
    const double ae = (ie >= 0 && ie < nx) ? alpha[iy * nx + ie] : ac;
    const double as = (js >= 0 && js < ny) ? alpha[js * nx + ix] : ac;
    const double an = (jn >= 0 && jn < ny) ? alpha[jn * nx + ix] : ac;
    const double denomX = ((periodicX || (ix > 0 && ix < nx - 1)) ? 2.0 : 1.0) * dx;
    const double denomY = ((periodicY || (iy > 0 && iy < ny - 1)) ? 2.0 : 1.0) * dy;
    // Existing x9 convention: n_AB points from alpha-high A to alpha-low B.
    double gx = -(ae - aw) / denomX;
    double gy = -(an - as) / denomY;
    const double g = sqrt(gx * gx + gy * gy);
    if (!(g > 1.0e-14) || !isfinite(g)) return false;
    gx /= g; gy /= g;
    *nxOut = gx; *nyOut = gy;
    return true;
}

__device__ __forceinline__ bool q6_x9t_sample_alpha(
    const double* alpha,
    double x,
    double y,
    int nx,
    int ny,
    double lx,
    double ly,
    int periodicX,
    int periodicY,
    double* valueOut) {
    if (!alpha || nx < 1 || ny < 1 || !(lx > 0.0) || !(ly > 0.0)) return false;
    if (periodicX) {
        x -= floor(x / lx) * lx;
        if (x >= lx) x = 0.0;
    } else if (x < 0.0 || x > lx) {
        return false;
    }
    if (periodicY) {
        y -= floor(y / ly) * ly;
        if (y >= ly) y = 0.0;
    } else if (y < 0.0 || y > ly) {
        return false;
    }
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);
    double gx = x / dx - 0.5;
    double gy = y / dy - 0.5;
    int i0 = static_cast<int>(floor(gx));
    int j0 = static_cast<int>(floor(gy));
    double fx = gx - floor(gx);
    double fy = gy - floor(gy);
    int i1 = i0 + 1, j1 = j0 + 1;
    if (periodicX) {
        i0 = q6_x9t_wrap_index(i0, nx); i1 = q6_x9t_wrap_index(i1, nx);
    } else {
        if (i0 < 0) { i0 = 0; i1 = 0; fx = 0.0; }
        if (i1 >= nx) { i0 = nx - 1; i1 = nx - 1; fx = 0.0; }
    }
    if (periodicY) {
        j0 = q6_x9t_wrap_index(j0, ny); j1 = q6_x9t_wrap_index(j1, ny);
    } else {
        if (j0 < 0) { j0 = 0; j1 = 0; fy = 0.0; }
        if (j1 >= ny) { j0 = ny - 1; j1 = ny - 1; fy = 0.0; }
    }
    const double a00 = alpha[j0 * nx + i0];
    const double a10 = alpha[j0 * nx + i1];
    const double a01 = alpha[j1 * nx + i0];
    const double a11 = alpha[j1 * nx + i1];
    const double a0 = (1.0 - fx) * a00 + fx * a10;
    const double a1 = (1.0 - fx) * a01 + fx * a11;
    *valueOut = (1.0 - fy) * a0 + fy * a1;
    return isfinite(*valueOut);
}


// 0493x10a: value-consistent pointwise normal of the *physical* x6c alpha.
// The interpolation is exactly the bilinear cell-centre interpolation used by
// q6_x9t_sample_alpha.  n_AB points from alpha-high A toward alpha-low B.
__device__ __forceinline__ bool q6_x10a_sample_alpha_normal(
    const double* alpha,
    double x,
    double y,
    int nx,
    int ny,
    double lx,
    double ly,
    int periodicX,
    int periodicY,
    double* nxOut,
    double* nyOut) {
    if (!alpha || !nxOut || !nyOut || nx < 1 || ny < 1 || !(lx > 0.0) || !(ly > 0.0))
        return false;
    if (periodicX) {
        x -= floor(x / lx) * lx;
        if (x >= lx) x = 0.0;
    } else if (x < 0.0 || x > lx) {
        return false;
    }
    if (periodicY) {
        y -= floor(y / ly) * ly;
        if (y >= ly) y = 0.0;
    } else if (y < 0.0 || y > ly) {
        return false;
    }

    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);
    const double gx = x / dx - 0.5;
    const double gy = y / dy - 0.5;
    int i0 = static_cast<int>(floor(gx));
    int j0 = static_cast<int>(floor(gy));
    double fx = gx - floor(gx);
    double fy = gy - floor(gy);
    int i1 = i0 + 1;
    int j1 = j0 + 1;

    if (periodicX) {
        i0 = q6_x9t_wrap_index(i0, nx);
        i1 = q6_x9t_wrap_index(i1, nx);
    } else {
        if (i0 < 0) { i0 = 0; i1 = 0; fx = 0.0; }
        if (i1 >= nx) { i0 = nx - 1; i1 = nx - 1; fx = 0.0; }
    }
    if (periodicY) {
        j0 = q6_x9t_wrap_index(j0, ny);
        j1 = q6_x9t_wrap_index(j1, ny);
    } else {
        if (j0 < 0) { j0 = 0; j1 = 0; fy = 0.0; }
        if (j1 >= ny) { j0 = ny - 1; j1 = ny - 1; fy = 0.0; }
    }

    const double a00 = alpha[j0 * nx + i0];
    const double a10 = alpha[j0 * nx + i1];
    const double a01 = alpha[j1 * nx + i0];
    const double a11 = alpha[j1 * nx + i1];
    const double dadx = ((1.0 - fy) * (a10 - a00) + fy * (a11 - a01)) / dx;
    const double dady = ((1.0 - fx) * (a01 - a00) + fx * (a11 - a10)) / dy;
    double nxv = -dadx;
    double nyv = -dady;
    const double ng = sqrt(nxv * nxv + nyv * nyv);
    if (!(ng > 1.0e-14) || !isfinite(ng)) return false;
    nxv /= ng;
    nyv /= ng;
    *nxOut = nxv;
    *nyOut = nyv;
    return true;
}

struct KineticCrossingDecision0493x9t {
    bool crossing = false;
    bool reflect = false;
    double nx = 0.0;
    double ny = 0.0;
    double outwardRelativeNormalSpeed = 0.0;
};

__device__ __forceinline__ KineticCrossingDecision0493x9t q6_x9t_decide_crossing(
    std::uint64_t i,
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    std::uint32_t phaseAType,
    int nx,
    int ny,
    double lx,
    double ly,
    double dt,
    int periodicX,
    int periodicY,
    double reflectionFraction,
    unsigned long long step,
    unsigned long long seed) {
    KineticCrossingDecision0493x9t d{};
    if (particles.role && particles.role[i] != kParticleRoleFluid) return d;
    if (!particles.type || particles.type[i] != phaseAType) return d;
    const int c = cells.cellId[i];
    if (c < 0 || c >= cells.numCells) return d;
    const double mCell = totalM[c];
    if (!(mCell > 0.0) || !isfinite(mCell)) return d;
    if (!(alpha[c] >= 0.5)) return d;
    if (!q6_x9t_cell_normal(alpha, c, nx, ny, lx / nx, ly / ny,
                            periodicX, periodicY, &d.nx, &d.ny)) return d;
    const double ux = totalPx[c] / mCell;
    const double uy = totalPy[c] / mCell;
    const double cx = particles.vx[i] - ux;
    const double cy = particles.vy[i] - uy;
    const double gn = cx * d.nx + cy * d.ny;
    if (!(gn > 0.0) || !isfinite(gn)) return d;
    const double xp = particles.x[i] + cx * dt;
    const double yp = particles.y[i] + cy * dt;
    double alphaPred = 1.0;
    if (!q6_x9t_sample_alpha(alpha, xp, yp, nx, ny, lx, ly,
                             periodicX, periodicY, &alphaPred)) {
        // External-domain crossings belong to the existing wall/open BC path.
        return d;
    }
    if (!(alphaPred < 0.5)) return d;
    d.crossing = true;
    d.outwardRelativeNormalSpeed = gn;
    if (reflectionFraction >= 1.0) {
        d.reflect = true;
    } else if (reflectionFraction > 0.0) {
        d.reflect = q6_x9t_uniform01(i, step, seed) < reflectionFraction;
    }
    return d;
}

__global__ void q6_x9t_deposit_total_a_moments(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    std::uint32_t phaseAType,
    double* totalM,
    double* totalPx,
    double* totalPy) {
    const std::uint64_t idx = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role && particles.role[i] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[i] != phaseAType) continue;
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) continue;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        atomic_add_double_0400(&totalM[c], m);
        atomic_add_double_0400(&totalPx[c], m * particles.vx[i]);
        atomic_add_double_0400(&totalPy[c], m * particles.vy[i]);
    }
}

__global__ void q6_x9t_classify_crossings(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    double* refM,
    double* refPx,
    double* refPy,
    double* txM,
    double* txPx,
    double* txPy,
    std::uint32_t phaseAType,
    int nx,
    int ny,
    double lx,
    double ly,
    double dt,
    int periodicX,
    int periodicY,
    double reflectionFraction,
    unsigned long long step,
    unsigned long long seed,
    KineticInterfaceAccumulator0493x9t* audit) {
    const std::uint64_t idx = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        const auto d = q6_x9t_decide_crossing(
            i, particles, cells, alpha, totalM, totalPx, totalPy, phaseAType,
            nx, ny, lx, ly, dt, periodicX, periodicY, reflectionFraction,
            step, seed);
        if (!d.crossing) continue;
        const int c = cells.cellId[i];
        const double m = particles.mass ? particles.mass[i] : 1.0;
        if (d.reflect) {
            atomic_add_double_0400(&refM[c], m);
            atomic_add_double_0400(&refPx[c], m * particles.vx[i]);
            atomic_add_double_0400(&refPy[c], m * particles.vy[i]);
        } else {
            atomic_add_double_0400(&txM[c], m);
            atomic_add_double_0400(&txPx[c], m * particles.vx[i]);
            atomic_add_double_0400(&txPy[c], m * particles.vy[i]);
        }
        if (audit) {
            atomicAdd(&audit->crossings, 1ull);
            if (d.reflect) atomicAdd(&audit->selectedReflections, 1ull);
            else atomicAdd(&audit->transmittedCrossings, 1ull);
            if (d.reflect) atomic_add_double_0400(&audit->reflectedMass, m);
            else atomic_add_double_0400(&audit->transmittedMass, m);
            atomic_add_double_0400(
                &audit->outwardRelativeNormalSpeedSum,
                d.outwardRelativeNormalSpeed);
        }
    }
}

__global__ void q6_x9t_apply_conservative_reflection(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    const double* refM,
    const double* refPx,
    const double* refPy,
    const double* txM,
    const double* txPx,
    const double* txPy,
    std::uint32_t phaseAType,
    int evaporationTargetType,
    int nx,
    int ny,
    double lx,
    double ly,
    double dt,
    int periodicX,
    int periodicY,
    double reflectionFraction,
    unsigned long long step,
    unsigned long long seed,
    KineticInterfaceAccumulator0493x9t* audit) {
    const std::uint64_t idx = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role && particles.role[i] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[i] != phaseAType) continue;
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) continue;

        const auto d = q6_x9t_decide_crossing(
            i, particles, cells, alpha, totalM, totalPx, totalPy, phaseAType,
            nx, ny, lx, ly, dt, periodicX, periodicY, reflectionFraction,
            step, seed);

        if (d.crossing && !d.reflect) {
            if (evaporationTargetType >= 0) {
                particles.type[i] = static_cast<std::uint32_t>(evaporationTargetType);
                if (audit) atomicAdd(&audit->convertedParticles, 1ull);
            }
            continue;
        }

        const double mc = refM[c];
        if (!(mc > 0.0)) continue;  // no reflected group in this cell
        const double me = txM[c];
        const double mt = totalM[c];
        const double mr = mt - mc - me;
        if (!(mr > 1.0e-14 * fmax(1.0, mt)) || !isfinite(mr)) {
            if (d.crossing && d.reflect && audit) {
                atomicAdd(&audit->unsupportedReflections, 1ull);
            }
            continue;
        }

        double nxCell = 0.0, nyCell = 0.0;
        if (!q6_x9t_cell_normal(alpha, c, nx, ny, lx / nx, ly / ny,
                                periodicX, periodicY, &nxCell, &nyCell)) {
            if (d.crossing && d.reflect && audit) {
                atomicAdd(&audit->unsupportedReflections, 1ull);
            }
            continue;
        }

        const double ucx = refPx[c] / mc;
        const double ucy = refPy[c] / mc;
        const double prx = totalPx[c] - refPx[c] - txPx[c];
        const double pry = totalPy[c] - refPy[c] - txPy[c];
        const double urx = prx / mr;
        const double ury = pry / mr;
        const double g = (ucx - urx) * nxCell + (ucy - ury) * nyCell;
        if (!(g > 0.0) || !isfinite(g)) {
            if (d.crossing && d.reflect && audit) {
                atomicAdd(&audit->unsupportedReflections, 1ull);
            }
            continue;
        }

        const double denom = mc + mr;
        const double dUc = -2.0 * mr / denom * g;
        const double dUr =  2.0 * mc / denom * g;
        const double oldVx = particles.vx[i];
        const double oldVy = particles.vy[i];
        double newVx = oldVx;
        double newVy = oldVy;
        bool changed = false;

        if (d.crossing && d.reflect) {
            // Reflect candidate internal normal velocity around the reflected
            // subgroup mean, then apply the exact two-group recoil.  The sum of
            // internal deviations is zero, so this preserves subgroup momentum;
            // the sign flip preserves its internal kinetic energy.
            const double devn = (oldVx - ucx) * nxCell + (oldVy - ucy) * nyCell;
            newVx = oldVx + (-2.0 * devn + dUc) * nxCell;
            newVy = oldVy + (-2.0 * devn + dUc) * nyCell;
            changed = true;
            if (audit) atomicAdd(&audit->appliedReflections, 1ull);
        } else if (!d.crossing) {
            // Non-crossing A particles form the receiving internal bath.
            newVx = oldVx + dUr * nxCell;
            newVy = oldVy + dUr * nyCell;
            changed = true;
        }

        if (changed) {
            particles.vx[i] = newVx;
            particles.vy[i] = newVy;
            if (audit) {
                const double m = particles.mass ? particles.mass[i] : 1.0;
                atomic_add_double_0400(&audit->deltaPx, m * (newVx - oldVx));
                atomic_add_double_0400(&audit->deltaPy, m * (newVy - oldVy));
                atomic_add_double_0400(
                    &audit->deltaKineticEnergy,
                    0.5 * m * ((newVx * newVx + newVy * newVy) -
                               (oldVx * oldVx + oldVy * oldVy)));
            }
        }
    }
}


// =============================================================================
// 0493x9u — support-edge kinetic reflection with inward conservative bath
// =============================================================================

struct KineticSupportDecision0493x9u {
    bool crossing = false;
    bool reflect = false;
    bool outerSupportParticle = false;
    bool supportExitCrossing = false;
    bool normalFallback = false;
    bool bathSearchFailed = false;
    int bathCell = -1;
    int bathDepth = -1;
    double nx = 0.0;
    double ny = 0.0;
    double outwardRelativeNormalSpeed = 0.0;
};

__device__ __forceinline__ bool q6_x9u_position_cell(
    double x, double y, int nx, int ny, double lx, double ly,
    int periodicX, int periodicY, int* cellOut) {
    if (!cellOut || nx < 1 || ny < 1 || !(lx > 0.0) || !(ly > 0.0)) return false;
    if (periodicX) {
        x -= floor(x / lx) * lx;
        if (x >= lx) x = 0.0;
    } else if (x < 0.0 || x > lx) return false;
    if (periodicY) {
        y -= floor(y / ly) * ly;
        if (y >= ly) y = 0.0;
    } else if (y < 0.0 || y > ly) return false;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);
    int ix = static_cast<int>(floor(x / dx));
    int iy = static_cast<int>(floor(y / dy));
    if (ix < 0) ix = 0; if (iy < 0) iy = 0;
    if (ix >= nx) ix = nx - 1; if (iy >= ny) iy = ny - 1;
    *cellOut = iy * nx + ix;
    return true;
}

__device__ __forceinline__ bool q6_x9u_offset_cell(
    int c, int ox, int oy, int nx, int ny, int periodicX, int periodicY, int* out) {
    if (!out || c < 0 || c >= nx * ny) return false;
    int ix = c % nx; int iy = c / nx;
    ix += ox; iy += oy;
    if (periodicX) ix = q6_x9t_wrap_index(ix, nx);
    else if (ix < 0 || ix >= nx) return false;
    if (periodicY) iy = q6_x9t_wrap_index(iy, ny);
    else if (iy < 0 || iy >= ny) return false;
    *out = iy * nx + ix;
    return true;
}

// 0493x9w: a kinetic-recoil bath must belong to the physical liquid bulk.
// Halo occupancy (massA>0 with alpha<0.5) is never allowed to become its own
// cohesive reservoir. Search remains bounded to depth <=2 and returns as soon
// as a valid nearest-depth bulk candidate is found.
__device__ __forceinline__ bool q6_x9w_choose_strict_bulk_bath(
    const double* alpha, const double* totalM, int c,
    double nxOut, double nyOut, double particleMass,
    int nx, int ny, int periodicX, int periodicY,
    int* bathCellOut, int* bathDepthOut) {
    if (!alpha || !totalM || !bathCellOut || !bathDepthOut) return false;
    (void)particleMass;
    const int sx = nxOut > 1.0e-14 ? -1 : (nxOut < -1.0e-14 ? 1 : 0);
    const int sy = nyOut > 1.0e-14 ? -1 : (nyOut < -1.0e-14 ? 1 : 0);

    // Efficiency: at most three candidates per depth and normally only depth 1
    // is touched. Within the nearest valid depth, use the largest A mass.
    for (int depth = 1; depth <= 2; ++depth) {
        int cand[3]; int nCand = 0;
        if (sx != 0) {
            int k = -1;
            if (q6_x9u_offset_cell(c, depth * sx, 0, nx, ny,
                                   periodicX, periodicY, &k))
                cand[nCand++] = k;
        }
        if (sy != 0) {
            int k = -1;
            if (q6_x9u_offset_cell(c, 0, depth * sy, nx, ny,
                                   periodicX, periodicY, &k)) {
                bool dup = false;
                for (int q = 0; q < nCand; ++q) dup = dup || cand[q] == k;
                if (!dup) cand[nCand++] = k;
            }
        }
        if (sx != 0 && sy != 0) {
            int k = -1;
            if (q6_x9u_offset_cell(c, depth * sx, depth * sy, nx, ny,
                                   periodicX, periodicY, &k)) {
                bool dup = false;
                for (int q = 0; q < nCand; ++q) dup = dup || cand[q] == k;
                if (!dup) cand[nCand++] = k;
            }
        }

        int best = -1;
        double bestMass = 0.0;
        for (int q = 0; q < nCand; ++q) {
            const int k = cand[q];
            if (!(alpha[k] >= 0.5)) continue;
            const double mk = totalM[k];
            if (!(mk > 0.0) || !isfinite(mk)) continue;
            if (best < 0 || mk > bestMass) {
                best = k;
                bestMass = mk;
            }
        }
        if (best >= 0) {
            *bathCellOut = best;
            *bathDepthOut = depth;
            return true;
        }
    }
    return false;
}

__device__ __forceinline__ KineticSupportDecision0493x9u q6_x9u_decide_support_exit(
    std::uint64_t i, CudaParticleDeviceView particles, CudaCellWorkspaceDeviceView cells,
    const double* alpha, const double* totalM, const double* totalPx, const double* totalPy,
    std::uint32_t phaseAType, int nx, int ny, double lx, double ly, double dt,
    int periodicX, int periodicY, double reflectionFraction,
    unsigned long long step, unsigned long long seed) {
    KineticSupportDecision0493x9u d{};
    if (particles.role && particles.role[i] != kParticleRoleFluid) return d;
    if (!particles.type || particles.type[i] != phaseAType) return d;
    const int c = cells.cellId[i];
    if (c < 0 || c >= cells.numCells || !alpha || !totalM) return d;
    const double mCell = totalM[c];
    if (!(mCell > 0.0) || !isfinite(mCell)) return d;
    const bool halfIsoInterior = alpha[c] >= 0.5;
    d.outerSupportParticle = !halfIsoInterior;

    if (!q6_x9t_cell_normal(alpha, c, nx, ny, lx / nx, ly / ny,
                            periodicX, periodicY, &d.nx, &d.ny)) {
        if (halfIsoInterior || !q6_x9t_cell_normal(totalM, c, nx, ny, lx / nx, ly / ny,
                                                   periodicX, periodicY, &d.nx, &d.ny)) return d;
        d.normalFallback = true;
    }

    int bath = c, bathDepth = 0;
    const double mi = particles.mass ? particles.mass[i] : 1.0;
    if (!halfIsoInterior) {
        if (!q6_x9w_choose_strict_bulk_bath(alpha, totalM, c, d.nx, d.ny, mi, nx, ny,
                                               periodicX, periodicY, &bath, &bathDepth)) {
            d.bathSearchFailed = true; return d;
        }
    }
    const double mb = totalM[bath];
    if (!(mb > 0.0) || !isfinite(mb)) { d.bathSearchFailed = !halfIsoInterior; return d; }
    d.bathCell = bath; d.bathDepth = bathDepth;
    const double ux = totalPx[bath] / mb, uy = totalPy[bath] / mb;
    const double cx = particles.vx[i] - ux, cy = particles.vy[i] - uy;
    const double gn = cx * d.nx + cy * d.ny;
    if (!(gn > 0.0) || !isfinite(gn)) return d;
    const double xp = particles.x[i] + cx * dt, yp = particles.y[i] + cy * dt;

    if (halfIsoInterior) {
        double alphaPred = 1.0;
        if (!q6_x9t_sample_alpha(alpha, xp, yp, nx, ny, lx, ly, periodicX, periodicY, &alphaPred)) return d;
        if (!(alphaPred < 0.5)) return d;
    } else {
        int target = -1;
        if (!q6_x9u_position_cell(xp, yp, nx, ny, lx, ly, periodicX, periodicY, &target)) return d;
        if (target == c) return d;
        // 0493x9w: an already occupied alpha<0.5 halo cell is still exterior.
        // Occupancy must never bootstrap a new cohesive support layer.
        if (!(alpha[target] < 0.5)) return d;
        d.supportExitCrossing = true;
    }

    d.crossing = true; d.outwardRelativeNormalSpeed = gn;
    if (reflectionFraction >= 1.0) d.reflect = true;
    else if (reflectionFraction > 0.0) d.reflect = q6_x9t_uniform01(i, step, seed) < reflectionFraction;
    return d;
}


// 0493x9v: diagnostic helpers. No physics uses these results.
__device__ __forceinline__ bool q6_x9v_target_from_velocity(
    double x, double y, double vx, double vy, double dt,
    int currentCell, int nx, int ny, double lx, double ly,
    int periodicX, int periodicY, int* targetOut) {
    if (!targetOut) return false;
    int target = -1;
    if (!q6_x9u_position_cell(x + vx * dt, y + vy * dt,
                              nx, ny, lx, ly, periodicX, periodicY, &target)) return false;
    *targetOut = target;
    return target != currentCell;
}

__device__ __forceinline__ bool q6_x9v_cell_effectively_empty(
    const double* totalM, int cell, double particleMass) {
    if (!totalM || cell < 0) return false;
    return !(totalM[cell] > 1.0e-14 * fmax(1.0, particleMass));
}

__global__ void q6_x9u_classify_support_exits(
    CudaParticleDeviceView particles, CudaCellWorkspaceDeviceView cells, std::uint64_t nParticles,
    const double* alpha, const double* totalM, const double* totalPx, const double* totalPy,
    double* refM, double* refPx, double* refPy,
    double* recvM, double* recvPx, double* recvPy,
    double* refNx, double* refNy, std::uint32_t phaseAType,
    int nx, int ny, double lx, double ly, double dt, int periodicX, int periodicY,
    double reflectionFraction, unsigned long long step, unsigned long long seed,
    KineticInterfaceAccumulator0493x9u* audit) {
    const std::uint64_t idx = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role && particles.role[i] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[i] != phaseAType) continue;
        const int c = cells.cellId[i]; if (c < 0 || c >= cells.numCells) continue;
        const auto d = q6_x9u_decide_support_exit(i, particles, cells, alpha, totalM, totalPx, totalPy,
            phaseAType, nx, ny, lx, ly, dt, periodicX, periodicY, reflectionFraction, step, seed);
        const double m = particles.mass ? particles.mass[i] : 1.0;
        if (audit) {
            if (d.outerSupportParticle) {
                atomicAdd(&audit->phaseAParticlesInOuterSupport, 1ull);
                if (totalM[c] < 3.0 * fmax(m, 1.0e-30))
                    atomicAdd(&audit->outerSupportCellParticlesLT3, 1ull);
            }
            if (d.bathSearchFailed) atomicAdd(&audit->bathSearchFailures, 1ull);

            // What target would the actual stream x+v*dt reach before the
            // reflection operator? This is intentionally diagnostic only.
            int targetAbs0493x9v = -1;
            const bool absMove0493x9v = q6_x9v_target_from_velocity(
                particles.x[i], particles.y[i], particles.vx[i], particles.vy[i], dt,
                c, nx, ny, lx, ly, periodicX, periodicY, &targetAbs0493x9v);
            const bool absExit0493x9v = absMove0493x9v &&
                q6_x9v_cell_effectively_empty(totalM, targetAbs0493x9v, m);
            if (absExit0493x9v) {
                atomicAdd(&audit->absoluteSupportExitCandidates, 1ull);
                if (!d.crossing) atomicAdd(&audit->missedRelativeButAbsoluteExit, 1ull);
            }

            // Reconstruct the x9u relative predictor even when it returns
            // non-crossing because the target cell is already occupied. This
            // directly tests whether the halo can bootstrap its own support.
            int bath0493x9v = d.bathCell >= 0 ? d.bathCell : c;
            const double mb0493x9v = (bath0493x9v >= 0 && bath0493x9v < cells.numCells)
                ? totalM[bath0493x9v] : 0.0;
            if (d.outerSupportParticle && mb0493x9v > 0.0 && isfinite(mb0493x9v)) {
                const double ubx0493x9v = totalPx[bath0493x9v] / mb0493x9v;
                const double uby0493x9v = totalPy[bath0493x9v] / mb0493x9v;
                const double crx0493x9v = particles.vx[i] - ubx0493x9v;
                const double cry0493x9v = particles.vy[i] - uby0493x9v;
                const double gn0493x9v = crx0493x9v * d.nx + cry0493x9v * d.ny;
                int targetRel0493x9v = -1;
                if (gn0493x9v > 0.0 &&
                    q6_x9v_target_from_velocity(particles.x[i], particles.y[i],
                        crx0493x9v, cry0493x9v, dt, c, nx, ny, lx, ly,
                        periodicX, periodicY, &targetRel0493x9v) &&
                    alpha[targetRel0493x9v] < 0.5) {
                    atomicAdd(&audit->detectorPredictedOuterTarget, 1ull);
                    if (!d.crossing && totalM[targetRel0493x9v] > 1.0e-14 * fmax(1.0, m)) {
                        atomicAdd(&audit->missedOccupiedOuterTarget, 1ull);
                        if (totalM[targetRel0493x9v] < 3.0 * fmax(m, 1.0e-30))
                            atomicAdd(&audit->missedSparseOuterTargetLT3, 1ull);
                    }
                }
            }

            // A bath-search failure currently returns before a crossing can
            // be declared. Use only the local-cell mean to estimate how often
            // such failures coincide with a genuine outward support exit.
            if (d.bathSearchFailed && totalM[c] > 0.0 && isfinite(totalM[c])) {
                const double ulx0493x9v = totalPx[c] / totalM[c];
                const double uly0493x9v = totalPy[c] / totalM[c];
                const double clx0493x9v = particles.vx[i] - ulx0493x9v;
                const double cly0493x9v = particles.vy[i] - uly0493x9v;
                const double gnLocal0493x9v = clx0493x9v * d.nx + cly0493x9v * d.ny;
                int targetLocal0493x9v = -1;
                if (gnLocal0493x9v > 0.0 &&
                    q6_x9v_target_from_velocity(particles.x[i], particles.y[i],
                        clx0493x9v, cly0493x9v, dt, c, nx, ny, lx, ly,
                        periodicX, periodicY, &targetLocal0493x9v) &&
                    q6_x9v_cell_effectively_empty(totalM, targetLocal0493x9v, m))
                    atomicAdd(&audit->bathSearchFailureWouldExitLocal, 1ull);
            }
        }
        if (!d.crossing) {
            atomic_add_double_0400(&recvM[c], m);
            atomic_add_double_0400(&recvPx[c], m * particles.vx[i]);
            atomic_add_double_0400(&recvPy[c], m * particles.vy[i]);
            continue;
        }
        if (d.reflect) {
            const int b = d.bathCell;
            if (b >= 0 && b < cells.numCells) {
                atomic_add_double_0400(&refM[b], m);
                atomic_add_double_0400(&refPx[b], m * particles.vx[i]);
                atomic_add_double_0400(&refPy[b], m * particles.vy[i]);
                atomic_add_double_0400(&refNx[b], m * d.nx);
                atomic_add_double_0400(&refNy[b], m * d.ny);
            }
        }
        if (audit) {
            atomicAdd(&audit->crossings, 1ull);
            if (d.supportExitCrossing) atomicAdd(&audit->supportExitCrossings, 1ull);
            else atomicAdd(&audit->legacyHalfIsoCrossings, 1ull);
            if (d.bathCell >= 0 && d.bathCell < cells.numCells) {
                const bool bulkBath0493x9v = alpha[d.bathCell] >= 0.5;
                if (bulkBath0493x9v) atomicAdd(&audit->bathAlphaGEHalf, 1ull);
                else atomicAdd(&audit->bathAlphaLTHalf, 1ull);
                if (d.supportExitCrossing) {
                    if (bulkBath0493x9v) atomicAdd(&audit->supportExitBathAlphaGEHalf, 1ull);
                    else atomicAdd(&audit->supportExitBathAlphaLTHalf, 1ull);
                }
            }
            if (d.reflect) atomicAdd(&audit->selectedReflections, 1ull);
            else atomicAdd(&audit->transmittedCrossings, 1ull);
            if (d.bathDepth == 0) atomicAdd(&audit->bathDepth0, 1ull);
            else if (d.bathDepth == 1) atomicAdd(&audit->bathDepth1, 1ull);
            else if (d.bathDepth == 2) atomicAdd(&audit->bathDepth2, 1ull);
            if (d.normalFallback) atomicAdd(&audit->normalFallbacks, 1ull);
            if (d.reflect) atomic_add_double_0400(&audit->reflectedMass, m);
            else atomic_add_double_0400(&audit->transmittedMass, m);
            atomic_add_double_0400(&audit->outwardRelativeNormalSpeedSum, d.outwardRelativeNormalSpeed);
        }
    }
}

__global__ void q6_x9u_apply_conservative_reflection(
    CudaParticleDeviceView particles, CudaCellWorkspaceDeviceView cells, std::uint64_t nParticles,
    const double* alpha, const double* totalM, const double* totalPx, const double* totalPy,
    const double* refM, const double* refPx, const double* refPy,
    const double* recvM, const double* recvPx, const double* recvPy,
    const double* refNx, const double* refNy, std::uint32_t phaseAType, int evaporationTargetType,
    int nx, int ny, double lx, double ly, double dt, int periodicX, int periodicY,
    double reflectionFraction, unsigned long long step, unsigned long long seed,
    KineticInterfaceAccumulator0493x9u* audit) {
    const std::uint64_t idx = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role && particles.role[i] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[i] != phaseAType) continue;
        const int c = cells.cellId[i]; if (c < 0 || c >= cells.numCells) continue;
        const auto d = q6_x9u_decide_support_exit(i, particles, cells, alpha, totalM, totalPx, totalPy,
            phaseAType, nx, ny, lx, ly, dt, periodicX, periodicY, reflectionFraction, step, seed);
        if (d.crossing && !d.reflect) {
            if (evaporationTargetType >= 0) {
                particles.type[i] = static_cast<std::uint32_t>(evaporationTargetType);
                if (audit) atomicAdd(&audit->convertedParticles, 1ull);
            }
            continue;
        }
        const bool donor = d.crossing && d.reflect;
        const bool receiver = !d.crossing && refM[c] > 0.0;
        if (!donor && !receiver) continue;
        const int b = donor ? d.bathCell : c;
        if (b < 0 || b >= cells.numCells) {
            if (donor && audit) {
                atomicAdd(&audit->unsupportedReflections, 1ull);
                atomicAdd(&audit->unsupportedInvalidBath, 1ull);
            }
            continue;
        }
        const double mc = refM[b], mr = recvM[b];
        if (!(mc > 0.0) || !isfinite(mc)) {
            if (donor && audit) {
                atomicAdd(&audit->unsupportedReflections, 1ull);
                atomicAdd(&audit->unsupportedInvalidDonorGroup, 1ull);
            }
            continue;
        }
        if (!(mr > 1.0e-14 * fmax(1.0, mc)) || !isfinite(mr)) {
            if (donor && audit) {
                atomicAdd(&audit->unsupportedReflections, 1ull);
                atomicAdd(&audit->unsupportedNoReceiverMass, 1ull);
            }
            continue;
        }
        double nxCell = refNx[b], nyCell = refNy[b];
        const double ng = sqrt(nxCell * nxCell + nyCell * nyCell);
        if (!(ng > 1.0e-14) || !isfinite(ng)) {
            if (donor && audit) {
                atomicAdd(&audit->unsupportedReflections, 1ull);
                atomicAdd(&audit->unsupportedNormalCancellation, 1ull);
            }
            continue;
        }
        nxCell /= ng; nyCell /= ng;
        const double ucx = refPx[b] / mc, ucy = refPy[b] / mc;
        const double urx = recvPx[b] / mr, ury = recvPy[b] / mr;
        const double g = (ucx - urx) * nxCell + (ucy - ury) * nyCell;
        if (!(g > 0.0) || !isfinite(g)) {
            if (donor && audit) {
                atomicAdd(&audit->unsupportedReflections, 1ull);
                atomicAdd(&audit->unsupportedGroupNotOutward, 1ull);
            }
            continue;
        }
        const double denom = mc + mr;
        const double dUc = -2.0 * mr / denom * g;
        const double dUr =  2.0 * mc / denom * g;
        const double oldVx = particles.vx[i], oldVy = particles.vy[i];
        double newVx = oldVx, newVy = oldVy;
        if (donor) {
            const double devn = (oldVx - ucx) * nxCell + (oldVy - ucy) * nyCell;
            newVx += (-2.0 * devn + dUc) * nxCell;
            newVy += (-2.0 * devn + dUc) * nyCell;
            if (audit) {
                atomicAdd(&audit->appliedReflections, 1ull);
                const double urAfterX0493x9v = urx + dUr * nxCell;
                const double urAfterY0493x9v = ury + dUr * nyCell;
                const double postCx0493x9v = newVx - urAfterX0493x9v;
                const double postCy0493x9v = newVy - urAfterY0493x9v;
                const double postGn0493x9v = postCx0493x9v * nxCell + postCy0493x9v * nyCell;
                atomic_add_double_0400(&audit->postRelativeNormalSpeedSum, postGn0493x9v);
                if (postGn0493x9v > 0.0) {
                    atomicAdd(&audit->appliedStillOutwardRelative, 1ull);
                    atomic_add_double_0400(&audit->postOutwardRelativeNormalSpeedSum, postGn0493x9v);
                }

                bool postRelExit0493x9v = false;
                if (d.supportExitCrossing) {
                    int targetPostRel0493x9v = -1;
                    postRelExit0493x9v = q6_x9v_target_from_velocity(
                        particles.x[i], particles.y[i], postCx0493x9v, postCy0493x9v, dt,
                        c, nx, ny, lx, ly, periodicX, periodicY, &targetPostRel0493x9v) &&
                        q6_x9v_cell_effectively_empty(totalM, targetPostRel0493x9v,
                            particles.mass ? particles.mass[i] : 1.0);
                } else {
                    double alphaPost0493x9v = 1.0;
                    const bool sampled0493x9v = q6_x9t_sample_alpha(
                        alpha, particles.x[i] + postCx0493x9v * dt,
                        particles.y[i] + postCy0493x9v * dt,
                        nx, ny, lx, ly, periodicX, periodicY, &alphaPost0493x9v);
                    postRelExit0493x9v = sampled0493x9v && alphaPost0493x9v < 0.5;
                }
                if (postRelExit0493x9v) atomicAdd(&audit->appliedStillRelativeExit, 1ull);

                int targetPostAbs0493x9v = -1;
                if (q6_x9v_target_from_velocity(
                        particles.x[i], particles.y[i], newVx, newVy, dt,
                        c, nx, ny, lx, ly, periodicX, periodicY, &targetPostAbs0493x9v) &&
                    q6_x9v_cell_effectively_empty(totalM, targetPostAbs0493x9v,
                        particles.mass ? particles.mass[i] : 1.0))
                    atomicAdd(&audit->appliedStillAbsoluteExit, 1ull);
            }
        } else {
            newVx += dUr * nxCell; newVy += dUr * nyCell;
        }
        particles.vx[i] = newVx; particles.vy[i] = newVy;
        if (audit) {
            const double m = particles.mass ? particles.mass[i] : 1.0;
            atomic_add_double_0400(&audit->deltaPx, m * (newVx - oldVx));
            atomic_add_double_0400(&audit->deltaPy, m * (newVy - oldVy));
            atomic_add_double_0400(&audit->deltaKineticEnergy,
                0.5 * m * ((newVx * newVx + newVy * newVy) - (oldVx * oldVx + oldVy * oldVy)));
        }
    }
}


// =============================================================================
// 0493x9x — pre-crossing / crossing-time kinetic reflection
// =============================================================================

struct KineticCrossingDecision0493x9x {
    bool crossing = false;
    bool reflect = false;
    bool interiorCrossing = false;
    bool shellGuard = false;
    bool shellParticle = false;
    bool shellRecoverable = false;
    bool deepOuterParticle = false;
    bool startBelowHalf = false;
    bool pointwiseOuterRoutedToShell = false;
    bool pointwiseInteriorOuterCell = false;
    bool bisectionFallback = false;
    bool crossingPointNormalFallback = false;
    int bathCell = -1;
    double nx = 0.0;
    double ny = 0.0;
    double outwardRelativeNormalSpeed = 0.0;
    double crossingFraction = 0.0;
};

__device__ __forceinline__ bool q6_x9x_choose_direct_bulk_bath(
    const double* alpha, const double* totalM, int c,
    double nxOut, double nyOut,
    int nx, int ny, int periodicX, int periodicY, int* bathCellOut) {
    if (!alpha || !totalM || !bathCellOut) return false;
    const int sx = nxOut > 1.0e-14 ? -1 : (nxOut < -1.0e-14 ? 1 : 0);
    const int sy = nyOut > 1.0e-14 ? -1 : (nyOut < -1.0e-14 ? 1 : 0);
    int cand[3]; int nCand = 0;
    if (sx != 0) {
        int k = -1;
        if (q6_x9u_offset_cell(c, sx, 0, nx, ny, periodicX, periodicY, &k))
            cand[nCand++] = k;
    }
    if (sy != 0) {
        int k = -1;
        if (q6_x9u_offset_cell(c, 0, sy, nx, ny, periodicX, periodicY, &k)) {
            bool dup = false;
            for (int q = 0; q < nCand; ++q) dup = dup || cand[q] == k;
            if (!dup) cand[nCand++] = k;
        }
    }
    if (sx != 0 && sy != 0) {
        int k = -1;
        if (q6_x9u_offset_cell(c, sx, sy, nx, ny, periodicX, periodicY, &k)) {
            bool dup = false;
            for (int q = 0; q < nCand; ++q) dup = dup || cand[q] == k;
            if (!dup) cand[nCand++] = k;
        }
    }
    int best = -1;
    double bestMass = 0.0;
    for (int q = 0; q < nCand; ++q) {
        const int k = cand[q];
        if (!(alpha[k] >= 0.5)) continue;
        const double mk = totalM[k];
        if (!(mk > 0.0) || !isfinite(mk)) continue;
        if (best < 0 || mk > bestMass) {
            best = k; bestMass = mk;
        }
    }
    if (best < 0) return false;
    *bathCellOut = best;
    return true;
}

__device__ __forceinline__ KineticCrossingDecision0493x9x q6_x9y_decide_crossing(
    std::uint64_t i,
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    std::uint32_t phaseAType,
    int nx, int ny, double lx, double ly, double dt,
    int periodicX, int periodicY,
    double reflectionFraction,
    unsigned long long step,
    unsigned long long seed,
    bool resolveCrossingFraction) {
    KineticCrossingDecision0493x9x d{};
    (void)resolveCrossingFraction; // x10a always resolves true interior crossings.
    if (particles.role && particles.role[i] != kParticleRoleFluid) return d;
    if (!particles.type || particles.type[i] != phaseAType) return d;
    const int c = cells.cellId[i];
    if (c < 0 || c >= cells.numCells || !alpha || !totalM || !totalPx || !totalPy) return d;
    const double mc = totalM[c];
    if (!(mc > 0.0) || !isfinite(mc)) return d;

    const double x0 = particles.x[i];
    const double y0 = particles.y[i];
    const double x1 = x0 + particles.vx[i] * dt;
    const double y1 = y0 + particles.vy[i] * dt;
    const bool centerBulk = alpha[c] >= 0.5;

    double a0 = alpha[c];
    double a1 = 1.0;
    bool pointInside = false;
    bool shellSide = false;

    if (centerBulk) {
        if (!q6_x9t_sample_alpha(alpha, x1, y1,
                                 nx, ny, lx, ly, periodicX, periodicY, &a1))
            return d;
        if (!(a1 < 0.5)) return d;
        if (!q6_x9t_sample_alpha(alpha, x0, y0,
                                 nx, ny, lx, ly, periodicX, periodicY, &a0))
            return d;
        if (a0 >= 0.5) pointInside = true;
        else shellSide = true;
    } else {
        if (!q6_x9t_sample_alpha(alpha, x0, y0,
                                 nx, ny, lx, ly, periodicX, periodicY, &a0))
            return d;
        if (a0 >= 0.5) {
            d.pointwiseInteriorOuterCell = true;
            if (!q6_x9t_sample_alpha(alpha, x1, y1,
                                     nx, ny, lx, ly, periodicX, periodicY, &a1))
                return d;
            if (!(a1 < 0.5)) return d;
            pointInside = true;
        } else {
            shellSide = true;
        }
    }

    int bath = c;

    if (pointInside) {
        if (!(a0 >= 0.5) || !(a1 < 0.5)) {
            d.startBelowHalf = true;
            return d;
        }

        // Bracket the physical alpha=0.5 crossing.  lo is always a sampled
        // inside point.  sGamma is a sub-bracket interpolation used only for
        // the pointwise normal; sInside=lo remains the safe reflection anchor.
        double lo = 0.0;
        double hi = 1.0;
        double aLo = a0;
        double aHi = a1;
        bool fallback = false;
        for (int it = 0; it < 4; ++it) {
            const double mid = 0.5 * (lo + hi);
            double am = 0.5;
            if (!q6_x9t_sample_alpha(
                    alpha,
                    x0 + mid * particles.vx[i] * dt,
                    y0 + mid * particles.vy[i] * dt,
                    nx, ny, lx, ly, periodicX, periodicY, &am) ||
                !isfinite(am)) {
                fallback = true;
                break;
            }
            if (am >= 0.5) { lo = mid; aLo = am; }
            else { hi = mid; aHi = am; }
        }

        double sInside = lo;
        double sGamma = 0.5 * (lo + hi);
        if (fallback) {
            d.bisectionFallback = true;
            // x0 was explicitly sampled inside.  Keep the safe anchor there;
            // use the old endpoint interpolation only to estimate the normal.
            sInside = 0.0;
            const double den = a0 - a1;
            if (den > 1.0e-14 && isfinite(den))
                sGamma = fmin(fmax((a0 - 0.5) / den, 0.0), 1.0);
            else
                sGamma = 0.0;
        } else {
            const double den = aLo - aHi;
            if (den > 1.0e-14 && isfinite(den)) {
                const double f = fmin(fmax((aLo - 0.5) / den, 0.0), 1.0);
                sGamma = lo + f * (hi - lo);
            }
        }

        const double xGamma = x0 + sGamma * particles.vx[i] * dt;
        const double yGamma = y0 + sGamma * particles.vy[i] * dt;
        if (!q6_x10a_sample_alpha_normal(alpha, xGamma, yGamma,
                                         nx, ny, lx, ly, periodicX, periodicY,
                                         &d.nx, &d.ny)) {
            d.crossingPointNormalFallback = true;
            if (!q6_x9t_cell_normal(alpha, c, nx, ny, lx / nx, ly / ny,
                                    periodicX, periodicY, &d.nx, &d.ny))
                return d;
        }

        if (!centerBulk) {
            if (!q6_x9x_choose_direct_bulk_bath(
                    alpha, totalM, c, d.nx, d.ny,
                    nx, ny, periodicX, periodicY, &bath))
                return d;
        }

        const double mb = totalM[bath];
        if (!(mb > 0.0) || !isfinite(mb)) return d;
        const double ux = totalPx[bath] / mb;
        const double uy = totalPy[bath] / mb;
        const double crx = particles.vx[i] - ux;
        const double cry = particles.vy[i] - uy;
        const double gn = crx * d.nx + cry * d.ny;
        if (!(gn > 0.0) || !isfinite(gn)) return d;

        d.crossing = true;
        d.interiorCrossing = true;
        d.bathCell = bath;
        d.crossingFraction = sInside;
        d.outwardRelativeNormalSpeed = gn;
    } else if (shellSide) {
        d.shellParticle = true;
        d.pointwiseOuterRoutedToShell = true;

        // There is no current-step interior bracket for an already escaped
        // shell particle.  Use its own pointwise alpha normal at x0, with the
        // historical cell-gradient fallback only when the bilinear gradient is
        // degenerate.
        if (!q6_x10a_sample_alpha_normal(alpha, x0, y0,
                                         nx, ny, lx, ly, periodicX, periodicY,
                                         &d.nx, &d.ny)) {
            d.crossingPointNormalFallback = true;
            if (!q6_x9t_cell_normal(alpha, c, nx, ny, lx / nx, ly / ny,
                                    periodicX, periodicY, &d.nx, &d.ny)) {
                d.deepOuterParticle = true;
                return d;
            }
        }

        if (centerBulk) {
            bath = c;
        } else if (!q6_x9x_choose_direct_bulk_bath(
                       alpha, totalM, c, d.nx, d.ny,
                       nx, ny, periodicX, periodicY, &bath)) {
            d.deepOuterParticle = true;
            return d;
        }

        d.shellRecoverable = true;
        d.bathCell = bath;

        const double mb = totalM[bath];
        if (!(mb > 0.0) || !isfinite(mb)) {
            d.shellRecoverable = false;
            d.deepOuterParticle = true;
            return d;
        }
        const double ux = totalPx[bath] / mb;
        const double uy = totalPy[bath] / mb;
        const double crx = particles.vx[i] - ux;
        const double cry = particles.vy[i] - uy;
        const double gn = crx * d.nx + cry * d.ny;
        if (!(gn > 0.0) || !isfinite(gn)) {
            // Already pointwise outside, but not escaping thermally relative
            // to the local bath. x10h requests neither velocity reflection nor
            // positional recovery: this particle belongs to the advected
            // mobile-interface population and enters the receiver pool.
            return d;
        }

        d.crossing = true;
        d.shellGuard = true;
        d.bathCell = bath;
        d.crossingFraction = 0.0;
        d.outwardRelativeNormalSpeed = gn;
    } else {
        return d;
    }

    if (reflectionFraction >= 1.0) d.reflect = true;
    else if (reflectionFraction > 0.0)
        d.reflect = q6_x9t_uniform01(i, step, seed) < reflectionFraction;
    return d;
}

__global__ void q6_x9z_classify_individual_reflections(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    double* donorDeltaE,
    double* reactionJx,
    double* reactionJy,
    double* recvM,
    double* recvPx,
    double* recvPy,
    double* recvK,
    double* reactionLambda,
    std::uint32_t phaseAType,
    int nx, int ny, double lx, double ly, double dt,
    int periodicX, int periodicY,
    double reflectionFraction,
    unsigned long long step,
    unsigned long long seed,
    KineticCrossingAccumulator0493x9x* audit) {
    const std::uint64_t idx = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    (void)reactionLambda;

    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role && particles.role[i] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[i] != phaseAType) continue;
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) continue;

        const auto d = q6_x9y_decide_crossing(
            i, particles, cells, alpha, totalM, totalPx, totalPy,
            phaseAType, nx, ny, lx, ly, dt, periodicX, periodicY,
            reflectionFraction, step, seed, false);
        const double m = particles.mass ? particles.mass[i] : 1.0;
        const double vx = particles.vx[i];
        const double vy = particles.vy[i];

        if (audit) {
            if (alpha[c] < 0.5) atomicAdd(&audit->phaseAOuterCellParticles, 1ull);
            if (d.shellParticle) atomicAdd(&audit->shellParticles, 1ull);
            if (d.shellRecoverable) atomicAdd(&audit->shellRecoverableParticles, 1ull);
            if (d.deepOuterParticle) atomicAdd(&audit->deepOuterParticles, 1ull);
            if (d.startBelowHalf) atomicAdd(&audit->startBelowHalf, 1ull);
            if (d.crossingPointNormalFallback)
                atomicAdd(&audit->crossingPointNormalFallbacks, 1ull);
            if (d.pointwiseOuterRoutedToShell)
                atomicAdd(&audit->pointwiseOuterRoutedToShell, 1ull);
            if (d.pointwiseInteriorOuterCell)
                atomicAdd(&audit->pointwiseInteriorOuterCell, 1ull);
        }

        if (!d.crossing) {
            // 0493x10h mobile-interface semantics:
            //
            // A particle is a kinetic donor only when its velocity is outward
            // RELATIVE to its local liquid bath, g=(v-u_b).n > 0.  A particle
            // that is not such a donor belongs to the receiver population even
            // when its pointwise position is temporarily on the alpha<0.5 side.
            //
            // alpha=0.5 is a reconstructed mobile free surface, not a material
            // wall.  Non-donor particles must be free to advect the interface
            // into vacuum (jet growth, ligament extension, spreading, splash).
            // Only thermal relative escape is reflected.
            atomic_add_double_0400(&recvM[c], m);
            atomic_add_double_0400(&recvPx[c], m * vx);
            atomic_add_double_0400(&recvPy[c], m * vy);
            // Hard r=1 x10f/x10g reuses recvK as donor-H scratch below.
            // The global exact energy root does not need receiver K.
            // Preserve the historical receiver thermal accumulator only for
            // r<1 evaporation semantics.
            if (reflectionFraction < 1.0)
                atomic_add_double_0400(&recvK[c], 0.5 * m * (vx * vx + vy * vy));
            continue;
        }

        if (d.reflect) {
            const int b = d.bathCell;
            if (b >= 0 && b < cells.numCells) {
                const double mb = totalM[b];
                if (mb > 0.0 && isfinite(mb)) {
                    const double ubx = totalPx[b] / mb;
                    const double uby = totalPy[b] / mb;
                    const double gn = (vx - ubx) * d.nx + (vy - uby) * d.ny;
                    if (gn > 0.0 && isfinite(gn)) {
                        // Individual specular reflection relative to the local
                        // bulk velocity and this donor's own interface normal.
                        const double vrx = vx - 2.0 * gn * d.nx;
                        const double vry = vy - 2.0 * gn * d.ny;
                        const double dpx = m * (vrx - vx);
                        const double dpy = m * (vry - vy);
                        const double dE = 0.5 * m *
                            ((vrx * vrx + vry * vry) - (vx * vx + vy * vy));

                        if (reflectionFraction >= 1.0) {
                            // 0493x10d hard-r1 analytic conservative mode.
                            // Store the sufficient statistics
                            //   A = sum m g_i^2,
                            //   S = sum m g_i n_i.
                            // They define, together with the receiver barycentre,
                            // the exact non-trivial P/E-conserving reflection root.
                            atomic_add_double_0400(&donorDeltaE[b], m * gn * gn);
                            atomic_add_double_0400(&reactionJx[b], m * gn * d.nx);
                            atomic_add_double_0400(&reactionJy[b], m * gn * d.ny);
                            // x10f additionally accumulates
                            //   H = sum m g_i (v_i . n_i).
                            // recvK is unused by hard-r1 and gives this statistic
                            // without adding another O(Ncell) buffer.
                            atomic_add_double_0400(
                                &recvK[b],
                                m * gn * (vx * d.nx + vy * d.ny));
                        } else {
                            // Historical r<1 path retained for future evaporation:
                            // J = -sum(delta p donor),
                            // DeltaE_receiver = -sum(dE donor).
                            atomic_add_double_0400(&reactionJx[b], -dpx);
                            atomic_add_double_0400(&reactionJy[b], -dpy);
                            atomic_add_double_0400(&donorDeltaE[b], dE);
                        }
                    }
                }
            }
        }

        if (audit) {
            if (d.interiorCrossing) atomicAdd(&audit->interiorCrossings, 1ull);
            if (d.shellGuard) atomicAdd(&audit->shellGuardCrossings, 1ull);
            if (d.reflect) {
                atomicAdd(&audit->selectedReflections, 1ull);
                atomic_add_double_0400(&audit->reflectedMass, m);
            } else {
                atomicAdd(&audit->transmittedCrossings, 1ull);
                atomic_add_double_0400(&audit->transmittedMass, m);
            }
            atomic_add_double_0400(&audit->outwardRelativeNormalSpeedSum,
                                   d.outwardRelativeNormalSpeed);
        }
    }
}



// 0493x10f: hard-r1 GLOBAL-RESERVOIR ABLATION.
//
// This tests whether the cardinal accumulation of x10d is caused by forcing
// the counter-impulse into receivers from the same interface cell.  Every
// donor keeps its own pointwise normal and local bath-relative g_i, while the
// exact momentum/energy reaction is aggregated over the whole phase-A set of
// this kinetic-interface call.
//
// IMPORTANT: this is a single-liquid-component ablation only.  A production
// multi-drop/pool implementation must run the same reduction independently
// per connected alpha>=0.5 liquid component.
//
// A = sum m g^2, S = sum m g n, H = sum m g (v.n)
// receivers: M_R, P_R, u_R=P_R/M_R
// donor dv=-a g n, receiver du=+a S/M_R
// dE = a(u_R.S-H)+0.5 a^2(A+|S|^2/M_R)
// a* = 2(H-u_R.S)/(A+|S|^2/M_R)
// 0493x10i shifted mesoscopic reservoirs.
//
// blockCells is the linear side in cell units (4 or 5 in the first sweep).
// For a shift s in [0,B-1], cells before s belong to edge reservoir 0 and the
// remaining cells are grouped by B. +1 in blocksX/blocksY reserves that edge
// slot without ever wrapping nonperiodic physical boundaries together.
__device__ __forceinline__ int q6_x10i_meso_axis_index(
    int i, int blockCells, int shift) {
    if (i < shift) return 0;
    return 1 + (i - shift) / blockCells;
}

__device__ __forceinline__ int q6_x10i_meso_reservoir_id(
    int cell, int nx, int blockCells, int shiftX, int shiftY, int blocksX) {
    const int i = cell % nx;
    const int j = cell / nx;
    const int bx = q6_x10i_meso_axis_index(i, blockCells, shiftX);
    const int by = q6_x10i_meso_axis_index(j, blockCells, shiftY);
    return by * blocksX + bx;
}

static inline std::uint64_t q6_x10i_mix64_host(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ull;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ull;
    x = (x ^ (x >> 27)) * 0x94d049bb133111ebull;
    return x ^ (x >> 31);
}

// 0493x10g hierarchical global reduction — PERFORMANCE ONLY.
//
// x10f physics is unchanged.  The x10f reducer used multiple atomicAdd(double)
// operations from every active receiver cell into the same handful of global
// scalars.  On the 800x400 single-drop qualification this produced heavy
// contention.  x10g computes the identical sums hierarchically:
//   cells -> one partial per CUDA block -> one final block -> x10f finalizer.
// No particle pass, reaction equation, donor/receiver membership, a, du,
// endpoint barrier, or surface-tension path is changed.
__global__ void q6_x10g_reduce_global_reaction_blocks(
    int numCells,
    const double* donorA,
    const double* donorSx,
    const double* donorSy,
    const double* donorH,
    const double* recvM,
    const double* recvPx,
    const double* recvPy,
    KineticGlobalReactionPartial0493x10g* partials) {
    double A = 0.0, Sx = 0.0, Sy = 0.0, H = 0.0;
    double receiverM = 0.0, receiverPx = 0.0, receiverPy = 0.0;
    double cellSNormSum = 0.0;
    unsigned long long donorCells = 0ull, receiverCells = 0ull;

    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < numCells; c += stride) {
        const double a = donorA[c];
        const double sx = donorSx[c];
        const double sy = donorSy[c];
        const double h = donorH[c];
        const double donorRequest = fabs(a) + fabs(sx) + fabs(sy) + fabs(h);
        if (donorRequest > 1.0e-30 &&
            isfinite(a) && isfinite(sx) && isfinite(sy) && isfinite(h)) {
            A += a;
            Sx += sx;
            Sy += sy;
            H += h;
            cellSNormSum += sqrt(sx * sx + sy * sy);
            ++donorCells;
        }

        const double mr = recvM[c];
        const double px = recvPx[c];
        const double py = recvPy[c];
        if (mr > 1.0e-14 && isfinite(mr) && isfinite(px) && isfinite(py)) {
            receiverM += mr;
            receiverPx += px;
            receiverPy += py;
            ++receiverCells;
        }
    }

    const unsigned mask = __activemask();
    for (int off = 16; off > 0; off >>= 1) {
        A += __shfl_down_sync(mask, A, off);
        Sx += __shfl_down_sync(mask, Sx, off);
        Sy += __shfl_down_sync(mask, Sy, off);
        H += __shfl_down_sync(mask, H, off);
        receiverM += __shfl_down_sync(mask, receiverM, off);
        receiverPx += __shfl_down_sync(mask, receiverPx, off);
        receiverPy += __shfl_down_sync(mask, receiverPy, off);
        cellSNormSum += __shfl_down_sync(mask, cellSNormSum, off);
        donorCells += __shfl_down_sync(mask, donorCells, off);
        receiverCells += __shfl_down_sync(mask, receiverCells, off);
    }

    __shared__ double sA[32], sSx[32], sSy[32], sH[32];
    __shared__ double sM[32], sPx[32], sPy[32], sNorm[32];
    __shared__ unsigned long long sDonor[32], sReceiver[32];
    const int lane = threadIdx.x & 31;
    const int warp = threadIdx.x >> 5;
    const int nWarps = (blockDim.x + 31) >> 5;
    if (lane == 0) {
        sA[warp] = A; sSx[warp] = Sx; sSy[warp] = Sy; sH[warp] = H;
        sM[warp] = receiverM; sPx[warp] = receiverPx; sPy[warp] = receiverPy;
        sNorm[warp] = cellSNormSum;
        sDonor[warp] = donorCells; sReceiver[warp] = receiverCells;
    }
    __syncthreads();

    if (warp == 0) {
        A = lane < nWarps ? sA[lane] : 0.0;
        Sx = lane < nWarps ? sSx[lane] : 0.0;
        Sy = lane < nWarps ? sSy[lane] : 0.0;
        H = lane < nWarps ? sH[lane] : 0.0;
        receiverM = lane < nWarps ? sM[lane] : 0.0;
        receiverPx = lane < nWarps ? sPx[lane] : 0.0;
        receiverPy = lane < nWarps ? sPy[lane] : 0.0;
        cellSNormSum = lane < nWarps ? sNorm[lane] : 0.0;
        donorCells = lane < nWarps ? sDonor[lane] : 0ull;
        receiverCells = lane < nWarps ? sReceiver[lane] : 0ull;
        for (int off = 16; off > 0; off >>= 1) {
            A += __shfl_down_sync(mask, A, off);
            Sx += __shfl_down_sync(mask, Sx, off);
            Sy += __shfl_down_sync(mask, Sy, off);
            H += __shfl_down_sync(mask, H, off);
            receiverM += __shfl_down_sync(mask, receiverM, off);
            receiverPx += __shfl_down_sync(mask, receiverPx, off);
            receiverPy += __shfl_down_sync(mask, receiverPy, off);
            cellSNormSum += __shfl_down_sync(mask, cellSNormSum, off);
            donorCells += __shfl_down_sync(mask, donorCells, off);
            receiverCells += __shfl_down_sync(mask, receiverCells, off);
        }
        if (lane == 0) {
            KineticGlobalReactionPartial0493x10g& p = partials[blockIdx.x];
            p.A = A; p.Sx = Sx; p.Sy = Sy; p.H = H;
            p.receiverM = receiverM; p.receiverPx = receiverPx; p.receiverPy = receiverPy;
            p.cellSNormSum = cellSNormSum;
            p.donorCells = donorCells; p.receiverCells = receiverCells;
        }
    }
}

__global__ void q6_x10g_reduce_global_reaction_partials(
    int numPartials,
    const KineticGlobalReactionPartial0493x10g* partials,
    KineticGlobalReaction0493x10f* global) {
    double A = 0.0, Sx = 0.0, Sy = 0.0, H = 0.0;
    double receiverM = 0.0, receiverPx = 0.0, receiverPy = 0.0;
    double cellSNormSum = 0.0;
    unsigned long long donorCells = 0ull, receiverCells = 0ull;

    for (int pidx = threadIdx.x; pidx < numPartials; pidx += blockDim.x) {
        const KineticGlobalReactionPartial0493x10g p = partials[pidx];
        A += p.A; Sx += p.Sx; Sy += p.Sy; H += p.H;
        receiverM += p.receiverM; receiverPx += p.receiverPx; receiverPy += p.receiverPy;
        cellSNormSum += p.cellSNormSum;
        donorCells += p.donorCells; receiverCells += p.receiverCells;
    }

    const unsigned mask = __activemask();
    for (int off = 16; off > 0; off >>= 1) {
        A += __shfl_down_sync(mask, A, off);
        Sx += __shfl_down_sync(mask, Sx, off);
        Sy += __shfl_down_sync(mask, Sy, off);
        H += __shfl_down_sync(mask, H, off);
        receiverM += __shfl_down_sync(mask, receiverM, off);
        receiverPx += __shfl_down_sync(mask, receiverPx, off);
        receiverPy += __shfl_down_sync(mask, receiverPy, off);
        cellSNormSum += __shfl_down_sync(mask, cellSNormSum, off);
        donorCells += __shfl_down_sync(mask, donorCells, off);
        receiverCells += __shfl_down_sync(mask, receiverCells, off);
    }

    __shared__ double sA[32], sSx[32], sSy[32], sH[32];
    __shared__ double sM[32], sPx[32], sPy[32], sNorm[32];
    __shared__ unsigned long long sDonor[32], sReceiver[32];
    const int lane = threadIdx.x & 31;
    const int warp = threadIdx.x >> 5;
    const int nWarps = (blockDim.x + 31) >> 5;
    if (lane == 0) {
        sA[warp] = A; sSx[warp] = Sx; sSy[warp] = Sy; sH[warp] = H;
        sM[warp] = receiverM; sPx[warp] = receiverPx; sPy[warp] = receiverPy;
        sNorm[warp] = cellSNormSum;
        sDonor[warp] = donorCells; sReceiver[warp] = receiverCells;
    }
    __syncthreads();

    if (warp == 0) {
        A = lane < nWarps ? sA[lane] : 0.0;
        Sx = lane < nWarps ? sSx[lane] : 0.0;
        Sy = lane < nWarps ? sSy[lane] : 0.0;
        H = lane < nWarps ? sH[lane] : 0.0;
        receiverM = lane < nWarps ? sM[lane] : 0.0;
        receiverPx = lane < nWarps ? sPx[lane] : 0.0;
        receiverPy = lane < nWarps ? sPy[lane] : 0.0;
        cellSNormSum = lane < nWarps ? sNorm[lane] : 0.0;
        donorCells = lane < nWarps ? sDonor[lane] : 0ull;
        receiverCells = lane < nWarps ? sReceiver[lane] : 0ull;
        for (int off = 16; off > 0; off >>= 1) {
            A += __shfl_down_sync(mask, A, off);
            Sx += __shfl_down_sync(mask, Sx, off);
            Sy += __shfl_down_sync(mask, Sy, off);
            H += __shfl_down_sync(mask, H, off);
            receiverM += __shfl_down_sync(mask, receiverM, off);
            receiverPx += __shfl_down_sync(mask, receiverPx, off);
            receiverPy += __shfl_down_sync(mask, receiverPy, off);
            cellSNormSum += __shfl_down_sync(mask, cellSNormSum, off);
            donorCells += __shfl_down_sync(mask, donorCells, off);
            receiverCells += __shfl_down_sync(mask, receiverCells, off);
        }
        if (lane == 0) {
            global->A = A; global->Sx = Sx; global->Sy = Sy; global->H = H;
            global->receiverM = receiverM;
            global->receiverPx = receiverPx; global->receiverPy = receiverPy;
            global->cellSNormSum = cellSNormSum;
            global->donorCells = donorCells; global->receiverCells = receiverCells;
        }
    }
}

// =============================================================================
// 0493x10m — implicit alpha=.5 as a LOCAL MOVING BOUNDARY
// =============================================================================
// The interface is reconstructed each step and lives only during the current
// streaming interval.  This is deliberately NOT a persistent surface mesh.
// Topology (pinch-off/coalescence) therefore remains entirely alpha-driven.
//
// The collision primitive below is generic enough for a future moving solid:
// provide a local plane point q, outward normal n and normal wall velocity.
// It returns the particle velocity after an elastic specular collision in the
// wall frame plus the opposite impulse received by the boundary.
struct LocalMovingPlane0493x10m {
    double qx = 0.0;
    double qy = 0.0;
    double nx = 0.0;
    double ny = 0.0;
    double wallVn = 0.0;
    int ownerCell = -1;
};

struct LocalMovingPlaneCollision0493x10m {
    bool hit = false;
    double tHit = 0.0;
    double newVx = 0.0;
    double newVy = 0.0;
    double impulseWallX = 0.0;
    double impulseWallY = 0.0;
    double relativeNormalBefore = 0.0;
};

__device__ __forceinline__ double q6_x10m_minimum_image(
    double d, double L, int periodic) {
    if (periodic && L > 0.0) d -= nearbyint(d / L) * L;
    return d;
}

// 0493x10m-fix1: x10m owns its alpha sampling helper.
// This removes the compile-order dependency on the later x10l diagnostic
// helper q6_x10l_alpha_cell.
__device__ __forceinline__ int q6_x10m_wrap_or_clamp_index(
    int i, int n, int periodic) {
    if (periodic) {
        i %= n;
        if (i < 0) i += n;
        return i;
    }
    if (i < 0) return 0;
    if (i >= n) return n - 1;
    return i;
}

__device__ __forceinline__ double q6_x10m_alpha_cell(
    const double* alpha,
    int i, int j, int nx, int ny,
    int periodicX, int periodicY) {
    i = q6_x10m_wrap_or_clamp_index(i, nx, periodicX);
    j = q6_x10m_wrap_or_clamp_index(j, ny, periodicY);
    return alpha[j * nx + i];
}

__device__ __forceinline__ bool q6_x10m_collide_local_moving_plane(
    double x0, double y0,
    double vx, double vy,
    double mass,
    double dt,
    double dx, double dy,
    double lx, double ly,
    int periodicX, int periodicY,
    const LocalMovingPlane0493x10m& wall,
    LocalMovingPlaneCollision0493x10m* out) {
    if (!out || !(dt > 0.0)) return false;
    const double h = fmin(dx, dy);
    double rx0 = q6_x10m_minimum_image(x0 - wall.qx, lx, periodicX);
    double ry0 = q6_x10m_minimum_image(y0 - wall.qy, ly, periodicY);
    double s0 = rx0 * wall.nx + ry0 * wall.ny; // outside is positive

    // Only liquid-side particles collide.  Tiny positive tolerance covers only
    // floating point / plane-linearization noise; already-outer shell particles
    // are not forcibly recalled by x10m.
    const double sideTol = 1.0e-8 * fmax(1.0, h);
    if (s0 > sideTol || s0 < -2.25 * h) return false;
    if (s0 > 0.0) s0 = 0.0;

    const double reln = vx * wall.nx + vy * wall.ny - wall.wallVn;
    if (!(reln > 1.0e-14) || !isfinite(reln)) return false;

    const double t = -s0 / reln;
    if (!(t >= 0.0 && t <= dt) || !isfinite(t)) return false;

    // Restrict the infinite plane to the local interface segment carried by
    // its owner cell.  The projected half-width is the cell-box extent along
    // the tangent, with a small geometric margin for the linearized alpha plane.
    const double qtx = wall.qx + wall.wallVn * wall.nx * t;
    const double qty = wall.qy + wall.wallVn * wall.ny * t;
    const double xh = x0 + vx * t;
    const double yh = y0 + vy * t;
    const double rhx = q6_x10m_minimum_image(xh - qtx, lx, periodicX);
    const double rhy = q6_x10m_minimum_image(yh - qty, ly, periodicY);
    const double tangential = rhx * (-wall.ny) + rhy * wall.nx;
    const double halfSegment =
        0.5 * (fabs(wall.ny) * dx + fabs(wall.nx) * dy) + 0.35 * h;
    if (fabs(tangential) > halfSegment) return false;

    out->hit = true;
    out->tHit = t;
    out->relativeNormalBefore = reln;
    out->newVx = vx - 2.0 * reln * wall.nx;
    out->newVy = vy - 2.0 * reln * wall.ny;
    const double impulse = 2.0 * mass * reln;
    out->impulseWallX = impulse * wall.nx;
    out->impulseWallY = impulse * wall.ny;
    return isfinite(out->newVx) && isfinite(out->newVy);
}

__global__ void q6_x10m_build_moving_interface_cells(
    int numCells,
    int nx, int ny,
    double lx, double ly,
    int periodicX, int periodicY,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    unsigned char* active,
    double* wallNx,
    double* wallNy,
    double* wallQx,
    double* wallQy,
    double* wallVn,
    KineticCrossingAccumulator0493x9x* audit) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);
    const double maxOffset = 1.25 * sqrt(dx * dx + dy * dy);

    for (int c = idx; c < numCells; c += stride) {
        active[c] = 0;
        wallNx[c] = wallNy[c] = 0.0;
        wallQx[c] = wallQy[c] = 0.0;
        wallVn[c] = 0.0;

        const int i = c % nx;
        const int j = c / nx;
        const double ac = q6_x10m_alpha_cell(
            alpha, i, j, nx, ny, periodicX, periodicY);
        // One interface plane is owned by the LIQUID-SIDE cell only.  This
        // prevents duplicate planes on both sides of the same alpha=.5 sheet.
        if (!(ac >= 0.5)) continue;

        const double al = q6_x10m_alpha_cell(
            alpha, i - 1, j, nx, ny, periodicX, periodicY);
        const double ar = q6_x10m_alpha_cell(
            alpha, i + 1, j, nx, ny, periodicX, periodicY);
        const double ab = q6_x10m_alpha_cell(
            alpha, i, j - 1, nx, ny, periodicX, periodicY);
        const double at = q6_x10m_alpha_cell(
            alpha, i, j + 1, nx, ny, periodicX, periodicY);
        const double amin = fmin(fmin(al, ar), fmin(ab, at));
        if (!(amin < 0.5)) continue;

        const double gx = (ar - al) / (2.0 * dx);
        const double gy = (at - ab) / (2.0 * dy);
        const double g2 = gx * gx + gy * gy;
        if (!(g2 > 1.0e-24) || !isfinite(g2)) {
            if (audit) atomicAdd(&audit->movingWallInvalidInterfaceCells, 1ull);
            continue;
        }
        const double gmag = sqrt(g2);
        const double nxo = -gx / gmag;
        const double nyo = -gy / gmag;

        double offset = (ac - 0.5) / gmag; // center -> alpha=.5, outward
        if (!isfinite(offset)) {
            if (audit) atomicAdd(&audit->movingWallInvalidInterfaceCells, 1ull);
            continue;
        }
        offset = fmin(fmax(offset, -maxOffset), maxOffset);
        const double cx = (static_cast<double>(i) + 0.5) * dx;
        const double cy = (static_cast<double>(j) + 0.5) * dy;
        const double qx = cx + offset * nxo;
        const double qy = cy + offset * nyo;

        int bath = c;
        bool fallback = false;
        double m = totalM[c];
        if (!(m > 1.0e-14) || !isfinite(m)) {
            if (!q6_x9x_choose_direct_bulk_bath(
                    alpha, totalM, c, nxo, nyo,
                    nx, ny, periodicX, periodicY, &bath)) {
                if (audit) atomicAdd(&audit->movingWallInvalidInterfaceCells, 1ull);
                continue;
            }
            fallback = true;
            m = totalM[bath];
        }
        const double px = totalPx[bath];
        const double py = totalPy[bath];
        if (!(m > 1.0e-14) || !isfinite(m) || !isfinite(px) || !isfinite(py)) {
            if (audit) atomicAdd(&audit->movingWallInvalidInterfaceCells, 1ull);
            continue;
        }
        const double ubx = px / m;
        const double uby = py / m;
        const double vn = ubx * nxo + uby * nyo;
        if (!isfinite(vn)) {
            if (audit) atomicAdd(&audit->movingWallInvalidInterfaceCells, 1ull);
            continue;
        }

        wallNx[c] = nxo;
        wallNy[c] = nyo;
        wallQx[c] = qx;
        wallQy[c] = qy;
        wallVn[c] = vn;
        active[c] = 1;
        if (audit) {
            atomicAdd(&audit->movingWallInterfaceCellsBuilt, 1ull);
            if (fallback)
                atomicAdd(&audit->movingWallInterfaceVelocityFallbacks, 1ull);
        }
    }
}

__global__ void q6_x10m_apply_moving_interface_wall(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    const double* alpha,
    const unsigned char* active,
    const double* wallNx,
    const double* wallNy,
    const double* wallQx,
    const double* wallQy,
    const double* wallVn,
    double* wallImpulseX,
    double* wallImpulseY,
    std::uint32_t phaseAType,
    int nx, int ny,
    double lx, double ly, double dt,
    int periodicX, int periodicY,
    KineticCrossingAccumulator0493x9x* audit) {
    const std::uint64_t idx =
        static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride =
        static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);

    for (std::uint64_t p = idx; p < nParticles; p += stride) {
        if (particles.role && particles.role[p] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[p] != phaseAType) continue;
        const int c0 = cells.cellId[p];
        if (c0 < 0 || c0 >= cells.numCells) continue;

        const double x0 = particles.x[p];
        const double y0 = particles.y[p];
        const double vx0 = particles.vx[p];
        const double vy0 = particles.vy[p];
        const double mass = particles.mass ? particles.mass[p] : 1.0;

        bool oldStationaryOuter = false;
        if (audit) {
            double a0 = 0.0, a1 = 0.0;
            const bool ok0 = q6_x9t_sample_alpha(
                alpha, x0, y0, nx, ny, lx, ly, periodicX, periodicY, &a0);
            const bool ok1 = q6_x9t_sample_alpha(
                alpha, x0 + vx0 * dt, y0 + vy0 * dt,
                nx, ny, lx, ly, periodicX, periodicY, &a1);
            oldStationaryOuter = ok0 && ok1 && a0 >= 0.5 && a1 < 0.5;
            if (oldStationaryOuter)
                atomicAdd(&audit->movingWallOldStationaryCrossingCandidates, 1ull);
        }

        LocalMovingPlane0493x10m bestWall{};
        LocalMovingPlaneCollision0493x10m bestHit{};
        double bestT = dt + 1.0;
        int validHits = 0;
        int candidatePlanes = 0;

        for (int dj = -1; dj <= 1; ++dj) {
            for (int di = -1; di <= 1; ++di) {
                int wc = -1;
                if (!q6_x9u_offset_cell(
                        c0, di, dj, nx, ny,
                        periodicX, periodicY, &wc))
                    continue;
                if (wc < 0 || wc >= cells.numCells || !active[wc]) continue;
                ++candidatePlanes;

                LocalMovingPlane0493x10m wall{};
                wall.qx = wallQx[wc];
                wall.qy = wallQy[wc];
                wall.nx = wallNx[wc];
                wall.ny = wallNy[wc];
                wall.wallVn = wallVn[wc];
                wall.ownerCell = wc;
                LocalMovingPlaneCollision0493x10m hit{};
                if (!q6_x10m_collide_local_moving_plane(
                        x0, y0, vx0, vy0, mass, dt,
                        dx, dy, lx, ly, periodicX, periodicY,
                        wall, &hit))
                    continue;
                ++validHits;
                if (hit.tHit < bestT) {
                    bestT = hit.tHit;
                    bestWall = wall;
                    bestHit = hit;
                }
            }
        }

        if (audit && candidatePlanes > 0)
            atomicAdd(&audit->movingWallParticlesWithCandidate, 1ull);
        if (!bestHit.hit) {
            if (audit && oldStationaryOuter)
                atomicAdd(&audit->movingWallOldStationaryCrossingReleased, 1ull);
            continue;
        }
        if (audit && validHits > 1)
            atomicAdd(&audit->movingWallMultipleCollisionCandidates, 1ull);

        // Standard event-driven streaming split: old velocity until collision,
        // reflected velocity for the remaining interval.  Since the production
        // streamer still advances v_new for the full dt, shift the pre-stream
        // position by (v_old-v_new)*tHit so its final endpoint is identical.
        const double newVx = bestHit.newVx;
        const double newVy = bestHit.newVy;
        const double corrX = (vx0 - newVx) * bestHit.tHit;
        const double corrY = (vy0 - newVy) * bestHit.tHit;
        particles.x[p] = x0 + corrX;
        particles.y[p] = y0 + corrY;
        particles.vx[p] = newVx;
        particles.vy[p] = newVy;

        atomic_add_double_0400(
            &wallImpulseX[bestWall.ownerCell], bestHit.impulseWallX);
        atomic_add_double_0400(
            &wallImpulseY[bestWall.ownerCell], bestHit.impulseWallY);

        if (audit) {
            atomicAdd(&audit->movingWallCollisions, 1ull);
            const double vnTol = 1.0e-12;
            if (bestWall.wallVn > vnTol)
                atomicAdd(&audit->movingWallAdvanceCollisions, 1ull);
            else if (bestWall.wallVn < -vnTol)
                atomicAdd(&audit->movingWallRecedeCollisions, 1ull);
            else
                atomicAdd(&audit->movingWallStationaryCollisions, 1ull);
            atomic_add_double_0400(
                &audit->movingWallCollisionTimeFractionSum,
                bestHit.tHit / dt);
            atomic_add_double_0400(
                &audit->movingWallWallVnSum, bestWall.wallVn);
            atomic_add_double_0400(
                &audit->movingWallWallVnSqSum,
                bestWall.wallVn * bestWall.wallVn);
            atomic_add_double_0400(
                &audit->movingWallWallVnAbsSum, fabs(bestWall.wallVn));

            const double wallVx = bestWall.wallVn * bestWall.nx;
            const double wallVy = bestWall.wallVn * bestWall.ny;
            const double cbx = vx0 - wallVx;
            const double cby = vy0 - wallVy;
            const double cax = newVx - wallVx;
            const double cay = newVy - wallVy;
            const double eBefore = cbx * cbx + cby * cby;
            const double eAfter = cax * cax + cay * cay;
            atomic_add_double_0400(
                &audit->movingWallRelativeSpeedSqAbsErrorSum,
                fabs(eAfter - eBefore));
            atomic_add_double_0400(
                &audit->movingWallRelativeSpeedSqReferenceSum,
                fabs(eBefore));
            const double relAfter =
                newVx * bestWall.nx + newVy * bestWall.ny - bestWall.wallVn;
            if (!(relAfter < 1.0e-12 * fmax(1.0, fabs(bestHit.relativeNormalBefore))))
                atomicAdd(&audit->movingWallRelativeStillOutward, 1ull);

            const double xf = x0 + vx0 * bestHit.tHit +
                              newVx * (dt - bestHit.tHit);
            const double yf = y0 + vy0 * bestHit.tHit +
                              newVy * (dt - bestHit.tHit);
            const double qfx = bestWall.qx +
                               bestWall.wallVn * bestWall.nx * dt;
            const double qfy = bestWall.qy +
                               bestWall.wallVn * bestWall.ny * dt;
            const double rfx = q6_x10m_minimum_image(
                xf - qfx, lx, periodicX);
            const double rfy = q6_x10m_minimum_image(
                yf - qfy, ly, periodicY);
            const double sFinal = rfx * bestWall.nx + rfy * bestWall.ny;
            if (sFinal > 1.0e-10 * fmax(1.0, fmin(dx, dy)))
                atomicAdd(&audit->movingWallFinalRelativeOutside, 1ull);

            atomic_add_double_0400(
                &audit->movingWallImpulseX, bestHit.impulseWallX);
            atomic_add_double_0400(
                &audit->movingWallImpulseY, bestHit.impulseWallY);
            atomic_add_double_0400(
                &audit->movingWallImpulseAbsSum,
                sqrt(bestHit.impulseWallX * bestHit.impulseWallX +
                     bestHit.impulseWallY * bestHit.impulseWallY));
            atomic_add_double_0400(
                &audit->movingWallPositionShiftAbsSum,
                sqrt(corrX * corrX + corrY * corrY));
        }
    }
}

// =============================================================================
// 0493x10n — Q6-CONSISTENT CONTINUOUS MOVING alpha=.5 INTERFACE
// =============================================================================
// x10m proved the moving-boundary kinematics but approximated Gamma by one
// independently truncated plane per liquid cell.  x10n instead reconstructs a
// continuous polyline on the cell-centre dual grid.  Every edge crossing uses
// exactly the Q6 cut fraction for a linearly interpolated alpha=.5 crossing:
//
//   theta = (0.5-alpha0)/(alpha1-alpha0).
//
// A dual square then connects its 2 (or, in a saddle, 4) shared edge crossings
// with marching-squares topology.  Adjacent dual squares recompute a shared
// edge endpoint from the same two alpha values and therefore meet exactly.
// Endpoint velocities are taken from the liquid-side post-Q6/B1 cell velocity;
// the same shared edge has the same liquid-side cell, so endpoint motion also
// remains continuous during the streaming interval.
//
// The moving-segment collision primitive is intentionally generic: a future
// mobile solid can provide persistent segment endpoints/velocities and consume
// the same collision impulses for rigid-body translation/rotation.
struct MovingSegment0493x10n {
    double ax = 0.0, ay = 0.0;
    double bx = 0.0, by = 0.0;
    double uax = 0.0, uay = 0.0;
    double ubx = 0.0, uby = 0.0;
    int ownerCell = -1;
};

struct MovingSegmentCollision0493x10n {
    bool hit = false;
    double tau = 0.0;
    double lambda = 0.0;
    double newVx = 0.0, newVy = 0.0;
    double wallVx = 0.0, wallVy = 0.0;
    double nx = 0.0, ny = 0.0;
    double relnBefore = 0.0;
    double impulseWallX = 0.0, impulseWallY = 0.0;

    // x10p generic initial-overlap response. Ordinary swept collisions leave
    // these members at their zero/default values.
    bool initialOverlap = false;
    bool overlapOutwardReflected = false;
    double penetration = 0.0;
    double positionCorrectionX = 0.0;
    double positionCorrectionY = 0.0;
};

struct IsoPoint0493x10n {
    double x = 0.0, y = 0.0;
    double ux = 0.0, uy = 0.0;
    bool valid = false;
};

__device__ __forceinline__ double q6_x10n_cross2(
    double ax, double ay, double bx, double by) {
    return ax * by - ay * bx;
}

__device__ __forceinline__ int q6_x10n_cell_index(
    int i, int j, int nx, int ny, int periodicX, int periodicY) {
    if (periodicX) {
        i %= nx; if (i < 0) i += nx;
    } else if (i < 0 || i >= nx) return -1;
    if (periodicY) {
        j %= ny; if (j < 0) j += ny;
    } else if (j < 0 || j >= ny) return -1;
    return j * nx + i;
}

// =============================================================================
// 0493x10o — Q6 HYDRODYNAMIC VELOCITY + THERMAL-THICKNESS INTERFACE WALL
// =============================================================================
// x10n made Gamma continuous, but moved each shared endpoint with an
// instantaneous post-B1 particle-cell COM velocity.  x10o separates the two
// scales:
//   * hydrodynamic motion comes directly from the projected Q6 field;
//   * the kinetic wall is displaced outward from alpha=.5 by a finite thermal
//     thickness delta = min(C*dt*sqrt(kBT/m), deltaMax*h).
//
// The alpha=.5 centreline remains the capillary/Q6 interface.  The outer
// thermal envelope is only the particle reflection surface.  A shared edge
// crossing gets one shared interpolated alpha normal, one shared shifted point,
// and one shared normal wall velocity, so neighboring marching-squares cells
// remain watertight both geometrically and kinematically.

__global__ void q6_x10o_capture_projected_q6_hydrodynamics(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const unsigned char* velocityMask,
    const double* cellDUx,
    const double* cellDUy,
    const double* faceDUxEast,
    const double* faceDUyNorth,
    unsigned char* valid,
    double* cellUx,
    double* cellUy,
    double* faceUxEast,
    double* faceUyNorth,
    int nx,
    int ny,
    int periodicX,
    int periodicY) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int k = speciesIndex * species.numCells + c;
        const double m = species.mass[k];
        const bool ok = m > 1.0e-14 && isfinite(m) &&
                        isfinite(species.px[k]) && isfinite(species.py[k]);
        valid[c] = ok ? 1u : 0u;
        if (!ok) {
            cellUx[c] = 0.0; cellUy[c] = 0.0;
            faceUxEast[c] = 0.0; faceUyNorth[c] = 0.0;
            continue;
        }
        const double ux0 = species.px[k] / m;
        const double uy0 = species.py[k] / m;
        cellUx[c] = ux0 + cellDUx[c];
        cellUy[c] = uy0 + cellDUy[c];

        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasNorth = periodicY || iy < ny - 1;
        if (hasEast) {
            const int east = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
            const double base = q6_species_face_velocity_0493w5(
                species, velocityMask, speciesIndex, c, east, 0);
            faceUxEast[c] = base + faceDUxEast[c];
        } else {
            faceUxEast[c] = cellUx[c];
        }
        if (hasNorth) {
            const int north =
                (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
            const double base = q6_species_face_velocity_0493w5(
                species, velocityMask, speciesIndex, c, north, 1);
            faceUyNorth[c] = base + faceDUyNorth[c];
        } else {
            faceUyNorth[c] = cellUy[c];
        }
    }
}

__device__ __forceinline__ void q6_x10o_alpha_gradient_cell(
    const double* alpha,
    int c,
    int nx, int ny,
    double dx, double dy,
    int periodicX, int periodicY,
    double* gx, double* gy) {
    const int ix = c % nx;
    const int iy = c / nx;
    const int west = q6_x10n_cell_index(ix - 1, iy, nx, ny, periodicX, periodicY);
    const int east = q6_x10n_cell_index(ix + 1, iy, nx, ny, periodicX, periodicY);
    const int south = q6_x10n_cell_index(ix, iy - 1, nx, ny, periodicX, periodicY);
    const int north = q6_x10n_cell_index(ix, iy + 1, nx, ny, periodicX, periodicY);
    const double ac = alpha[c];
    const double aw = west >= 0 ? alpha[west] : ac;
    const double ae = east >= 0 ? alpha[east] : ac;
    const double as = south >= 0 ? alpha[south] : ac;
    const double an = north >= 0 ? alpha[north] : ac;
    const double denx = (west >= 0 && east >= 0) ? 2.0 * dx : dx;
    const double deny = (south >= 0 && north >= 0) ? 2.0 * dy : dy;
    *gx = nx > 1 ? (ae - aw) / denx : 0.0;
    *gy = ny > 1 ? (an - as) / deny : 0.0;
}

// Shared thermal-envelope endpoint.  faceComponent: 0=x projected Q6 face
// component, 1=y. faceOwner is the west/south owner of that Q6 face.
__device__ __forceinline__ bool q6_x10o_edge_crossing_q6_thermal(
    double a0, double a1,
    double x0, double y0, double x1, double y1,
    int c0, int c1,
    int faceOwner,
    int faceComponent,
    const double* alpha,
    int nx, int ny,
    double dx, double dy,
    int periodicX, int periodicY,
    const unsigned char* hydroValid,
    const double* hydroCellUx,
    const double* hydroCellUy,
    const double* hydroFaceUxEast,
    const double* hydroFaceUyNorth,
    double thermalThickness,
    IsoPoint0493x10n* out,
    KineticCrossingAccumulator0493x9x* audit) {
    if (!out) return false;
    const bool in0 = a0 >= 0.5;
    const bool in1 = a1 >= 0.5;
    if (in0 == in1) return false;
    const double den = a1 - a0;
    if (!(fabs(den) > 1.0e-15) || !isfinite(den)) return false;
    double theta = (0.5 - a0) / den;
    theta = fmin(1.0, fmax(0.0, theta));
    const int liquid = in0 ? c0 : c1;

    double g0x = 0.0, g0y = 0.0, g1x = 0.0, g1y = 0.0;
    q6_x10o_alpha_gradient_cell(
        alpha, c0, nx, ny, dx, dy, periodicX, periodicY, &g0x, &g0y);
    q6_x10o_alpha_gradient_cell(
        alpha, c1, nx, ny, dx, dy, periodicX, periodicY, &g1x, &g1y);
    double gx = (1.0 - theta) * g0x + theta * g1x;
    double gy = (1.0 - theta) * g0y + theta * g1y;
    double nxo = -gx;
    double nyo = -gy;
    double n2 = nxo * nxo + nyo * nyo;
    if (!(n2 > 1.0e-24) || !isfinite(n2)) {
        const double ex = x1 - x0;
        const double ey = y1 - y0;
        const double e2 = ex * ex + ey * ey;
        if (!(e2 > 1.0e-24)) return false;
        const double invE = 1.0 / sqrt(e2);
        nxo = (in0 ? 1.0 : -1.0) * ex * invE;
        nyo = (in0 ? 1.0 : -1.0) * ey * invE;
    } else {
        const double invN = 1.0 / sqrt(n2);
        nxo *= invN;
        nyo *= invN;
    }

    double ux = 0.0, uy = 0.0;
    bool hydroOk = hydroValid && hydroValid[liquid] != 0u;
    if (hydroOk) {
        ux = hydroCellUx[liquid];
        uy = hydroCellUy[liquid];
        if (faceOwner >= 0) {
            if (faceComponent == 0) ux = hydroFaceUxEast[faceOwner];
            else uy = hydroFaceUyNorth[faceOwner];
        }
        hydroOk = isfinite(ux) && isfinite(uy);
    }
    if (!hydroOk) {
        ux = 0.0; uy = 0.0;
        if (audit) atomicAdd(&audit->q6ThermalHydroFallbacks, 1ull);
    }

    const double vn = ux * nxo + uy * nyo;
    const double xc = x0 + theta * (x1 - x0);
    const double yc = y0 + theta * (y1 - y0);
    out->x = xc + thermalThickness * nxo;
    out->y = yc + thermalThickness * nyo;
    // Only normal motion changes the geometry of an implicit free surface.
    out->ux = vn * nxo;
    out->uy = vn * nyo;
    out->valid = isfinite(out->x) && isfinite(out->y) &&
                 isfinite(out->ux) && isfinite(out->uy);

    if (out->valid && audit) {
        atomicAdd(&audit->q6ThermalInterfaceEndpointSamples, 1ull);
        atomic_add_double_0400(&audit->q6ThermalHydroVnSum, vn);
        atomic_add_double_0400(&audit->q6ThermalHydroVnSqSum, vn * vn);
        atomic_add_double_0400(&audit->q6ThermalHydroAbsVnSum, fabs(vn));
        atomic_add_double_0400(&audit->q6ThermalThicknessSum, thermalThickness);
    }
    return out->valid;
}

__device__ __forceinline__ bool q6_x10n_cell_velocity(
    int c,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    double* ux, double* uy) {
    if (c < 0 || !ux || !uy) return false;
    const double m = totalM[c];
    const double px = totalPx[c];
    const double py = totalPy[c];
    if (!(m > 1.0e-14) || !isfinite(m) || !isfinite(px) || !isfinite(py))
        return false;
    *ux = px / m;
    *uy = py / m;
    return isfinite(*ux) && isfinite(*uy);
}

// Q6-consistent alpha=.5 crossing on one edge between two cell centres.
// The velocity attached to the endpoint is the post-Q6/B1 velocity of the
// liquid-side cell.  This choice is unique for the shared edge and therefore
// gives identical endpoint motion to both adjacent dual squares.
__device__ __forceinline__ bool q6_x10n_edge_crossing(
    double a0, double a1,
    double x0, double y0, double x1, double y1,
    int c0, int c1,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    IsoPoint0493x10n* out) {
    if (!out) return false;
    const bool in0 = a0 >= 0.5;
    const bool in1 = a1 >= 0.5;
    if (in0 == in1) return false;
    const double den = a1 - a0;
    if (!(fabs(den) > 1.0e-15) || !isfinite(den)) return false;
    double theta = (0.5 - a0) / den;
    theta = fmin(1.0, fmax(0.0, theta));
    const int liquid = in0 ? c0 : c1;
    double ux = 0.0, uy = 0.0;
    if (!q6_x10n_cell_velocity(
            liquid, totalM, totalPx, totalPy, &ux, &uy))
        return false;
    out->x = x0 + theta * (x1 - x0);
    out->y = y0 + theta * (y1 - y0);
    out->ux = ux;
    out->uy = uy;
    out->valid = isfinite(out->x) && isfinite(out->y);
    return out->valid;
}

__device__ __forceinline__ void q6_x10n_orient_segment_outward(
    IsoPoint0493x10n* a,
    IsoPoint0493x10n* b,
    double a00, double a10, double a11, double a01,
    double xBase, double yBase, double dx, double dy) {
    if (!a || !b) return;
    const double mx = 0.5 * (a->x + b->x);
    const double my = 0.5 * (a->y + b->y);
    const double xi = fmin(1.0, fmax(0.0, (mx - xBase) / dx));
    const double eta = fmin(1.0, fmax(0.0, (my - yBase) / dy));
    const double gx = ((a10 - a00) * (1.0 - eta) +
                       (a11 - a01) * eta) / dx;
    const double gy = ((a01 - a00) * (1.0 - xi) +
                       (a11 - a10) * xi) / dy;
    const double tx0 = b->x - a->x;
    const double ty0 = b->y - a->y;
    const double L2 = tx0 * tx0 + ty0 * ty0;
    if (!(L2 > 1.0e-24)) return;
    const double invL = 1.0 / sqrt(L2);
    const double nrx = ty0 * invL;   // right normal of A -> B
    const double nry = -tx0 * invL;
    // Outward is toward decreasing alpha, i.e. -grad(alpha).
    if (nrx * (-gx) + nry * (-gy) < 0.0) {
        const IsoPoint0493x10n tmp = *a;
        *a = *b;
        *b = tmp;
    }
}

__device__ __forceinline__ bool q6_x10n_store_segment(
    int owner, int slot,
    IsoPoint0493x10n a,
    IsoPoint0493x10n b,
    double a00, double a10, double a11, double a01,
    double xBase, double yBase, double dx, double dy,
    double* segAx, double* segAy,
    double* segBx, double* segBy,
    double* segUax, double* segUay,
    double* segUbx, double* segUby) {
    if (owner < 0 || slot < 0 || slot > 1 || !a.valid || !b.valid) return false;
    const double ddx = b.x - a.x;
    const double ddy = b.y - a.y;
    if (!(ddx * ddx + ddy * ddy > 1.0e-20 * fmin(dx * dx, dy * dy)))
        return false;
    q6_x10n_orient_segment_outward(
        &a, &b, a00, a10, a11, a01, xBase, yBase, dx, dy);
    const int s = 2 * owner + slot;
    segAx[s] = a.x; segAy[s] = a.y;
    segBx[s] = b.x; segBy[s] = b.y;
    segUax[s] = a.ux; segUay[s] = a.uy;
    segUbx[s] = b.ux; segUby[s] = b.uy;
    return true;
}

__global__ void q6_x10n_build_continuous_interface(
    int numCells,
    int nx, int ny,
    double lx, double ly,
    int periodicX, int periodicY,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    const unsigned char* q6HydroValid0493x10o,
    const double* q6HydroCellUx0493x10o,
    const double* q6HydroCellUy0493x10o,
    const double* q6HydroFaceUxEast0493x10o,
    const double* q6HydroFaceUyNorth0493x10o,
    double thermalThickness0493x10o,
    int useQ6ThermalWall0493x10o,
    unsigned char* segCount,
    double* segAx, double* segAy,
    double* segBx, double* segBy,
    double* segUax, double* segUay,
    double* segUbx, double* segUby,
    KineticCrossingAccumulator0493x9x* audit) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);

    for (int owner = idx; owner < numCells; owner += stride) {
        segCount[owner] = 0;
        const int i = owner % nx;
        const int j = owner / nx;
        if ((!periodicX && i + 1 >= nx) ||
            (!periodicY && j + 1 >= ny))
            continue;
        if (audit) atomicAdd(&audit->continuousWallDualCellsVisited, 1ull);

        const int c00 = q6_x10n_cell_index(i,     j,     nx, ny, periodicX, periodicY);
        const int c10 = q6_x10n_cell_index(i + 1, j,     nx, ny, periodicX, periodicY);
        const int c11 = q6_x10n_cell_index(i + 1, j + 1, nx, ny, periodicX, periodicY);
        const int c01 = q6_x10n_cell_index(i,     j + 1, nx, ny, periodicX, periodicY);
        if (c00 < 0 || c10 < 0 || c11 < 0 || c01 < 0) continue;
        const double a00 = alpha[c00], a10 = alpha[c10];
        const double a11 = alpha[c11], a01 = alpha[c01];
        if (!isfinite(a00) || !isfinite(a10) || !isfinite(a11) || !isfinite(a01)) {
            if (audit) atomicAdd(&audit->continuousWallInvalidDualCells, 1ull);
            continue;
        }
        const int b0 = a00 >= 0.5 ? 1 : 0;
        const int b1 = a10 >= 0.5 ? 1 : 0;
        const int b2 = a11 >= 0.5 ? 1 : 0;
        const int b3 = a01 >= 0.5 ? 1 : 0;
        const int code = b0 | (b1 << 1) | (b2 << 2) | (b3 << 3);
        if (code == 0 || code == 15) continue;
        if (audit) atomicAdd(&audit->continuousWallInterfaceDualCells, 1ull);

        const double x0 = (static_cast<double>(i) + 0.5) * dx;
        const double y0 = (static_cast<double>(j) + 0.5) * dy;
        const double x1 = x0 + dx;
        const double y1 = y0 + dy;
        IsoPoint0493x10n e[4];
        bool h[4] = {false, false, false, false};
        if (useQ6ThermalWall0493x10o) {
            // edge 0: c00--c10, Q6 x-face owned by c00
            h[0] = q6_x10o_edge_crossing_q6_thermal(
                a00, a10, x0, y0, x1, y0, c00, c10, c00, 0,
                alpha, nx, ny, dx, dy, periodicX, periodicY,
                q6HydroValid0493x10o, q6HydroCellUx0493x10o, q6HydroCellUy0493x10o,
                q6HydroFaceUxEast0493x10o, q6HydroFaceUyNorth0493x10o,
                thermalThickness0493x10o, &e[0], audit);
            // edge 1: c10--c11, Q6 y-face owned by c10
            h[1] = q6_x10o_edge_crossing_q6_thermal(
                a10, a11, x1, y0, x1, y1, c10, c11, c10, 1,
                alpha, nx, ny, dx, dy, periodicX, periodicY,
                q6HydroValid0493x10o, q6HydroCellUx0493x10o, q6HydroCellUy0493x10o,
                q6HydroFaceUxEast0493x10o, q6HydroFaceUyNorth0493x10o,
                thermalThickness0493x10o, &e[1], audit);
            // edge 2: c11--c01, same physical x-face is owned by c01
            h[2] = q6_x10o_edge_crossing_q6_thermal(
                a11, a01, x1, y1, x0, y1, c11, c01, c01, 0,
                alpha, nx, ny, dx, dy, periodicX, periodicY,
                q6HydroValid0493x10o, q6HydroCellUx0493x10o, q6HydroCellUy0493x10o,
                q6HydroFaceUxEast0493x10o, q6HydroFaceUyNorth0493x10o,
                thermalThickness0493x10o, &e[2], audit);
            // edge 3: c01--c00, same physical y-face is owned by c00
            h[3] = q6_x10o_edge_crossing_q6_thermal(
                a01, a00, x0, y1, x0, y0, c01, c00, c00, 1,
                alpha, nx, ny, dx, dy, periodicX, periodicY,
                q6HydroValid0493x10o, q6HydroCellUx0493x10o, q6HydroCellUy0493x10o,
                q6HydroFaceUxEast0493x10o, q6HydroFaceUyNorth0493x10o,
                thermalThickness0493x10o, &e[3], audit);
        } else {
            h[0] = q6_x10n_edge_crossing(a00, a10, x0, y0, x1, y0,
                                          c00, c10, totalM, totalPx, totalPy, &e[0]);
            h[1] = q6_x10n_edge_crossing(a10, a11, x1, y0, x1, y1,
                                          c10, c11, totalM, totalPx, totalPy, &e[1]);
            h[2] = q6_x10n_edge_crossing(a11, a01, x1, y1, x0, y1,
                                          c11, c01, totalM, totalPx, totalPy, &e[2]);
            h[3] = q6_x10n_edge_crossing(a01, a00, x0, y1, x0, y0,
                                          c01, c00, totalM, totalPx, totalPy, &e[3]);
        }
        int edges[4]; int ne = 0;
        for (int k = 0; k < 4; ++k) if (h[k]) edges[ne++] = k;

        int built = 0;
        if (ne == 2) {
            if (q6_x10n_store_segment(owner, 0, e[edges[0]], e[edges[1]],
                    a00, a10, a11, a01, x0, y0, dx, dy,
                    segAx, segAy, segBx, segBy,
                    segUax, segUay, segUbx, segUby))
                built = 1;
        } else if (ne == 4) {
            if (code != 5 && code != 10) {
                if (audit) atomicAdd(&audit->continuousWallInvalidDualCells, 1ull);
                continue;
            }
            if (audit) atomicAdd(&audit->continuousWallAmbiguousDualCells, 1ull);
            // Marching-squares asymptotic choice reduced to the bilinear value
            // at the dual-square centre.  It is deterministic and shared-edge
            // continuous; it only selects topology inside this saddle square.
            const bool centerInside = 0.25 * (a00 + a10 + a11 + a01) >= 0.5;
            int p00a = 0, p00b = 0, p11a = 0, p11b = 0;
            if (code == 5) { // inside corners 00 and 11
                if (centerInside) {
                    p00a = 0; p00b = 1; p11a = 2; p11b = 3;
                } else {
                    p00a = 3; p00b = 0; p11a = 1; p11b = 2;
                }
            } else { // code 10: inside corners 10 and 01
                if (centerInside) {
                    p00a = 3; p00b = 0; p11a = 1; p11b = 2;
                } else {
                    p00a = 0; p00b = 1; p11a = 2; p11b = 3;
                }
            }
            if (q6_x10n_store_segment(owner, built, e[p00a], e[p00b],
                    a00, a10, a11, a01, x0, y0, dx, dy,
                    segAx, segAy, segBx, segBy,
                    segUax, segUay, segUbx, segUby)) ++built;
            if (built < 2 && q6_x10n_store_segment(owner, built, e[p11a], e[p11b],
                    a00, a10, a11, a01, x0, y0, dx, dy,
                    segAx, segAy, segBx, segBy,
                    segUax, segUay, segUbx, segUby)) ++built;
        } else {
            if (audit) atomicAdd(&audit->continuousWallInvalidDualCells, 1ull);
            continue;
        }
        segCount[owner] = static_cast<unsigned char>(built);
        if (audit && built > 0)
            atomicAdd(&audit->continuousWallSegmentsBuilt,
                      static_cast<unsigned long long>(built));
    }
}

// Collision against a line segment with linearly moving endpoints.  The
// particle and endpoint trajectories are linear, so collinearity is a
// quadratic equation in tau.  At the hit, specular reflection uses the local
// interpolated wall velocity and the instantaneous segment normal.
// =============================================================================
// 0493x10p — INITIAL OVERLAP / PENETRATION RESOLUTION
// =============================================================================
// A reconstructed moving boundary can move between two alpha reconstructions.
// A particle may therefore start the next step slightly beyond the kinetic
// wall even though the previous swept collision was valid.
//
// x10p adds the second standard branch of a moving-boundary engine:
//   (1) swept collision during dt;
//   (2) initial-overlap resolution at t=0.
//
// The nearest finite segment is selected before using the sign of the distance.
// This avoids classifying against a non-nearest tangent of a curved interface.

__device__ __forceinline__ void q6_x10p_atomic_max_positive_double(
    double* address, double value) {
    if (!address || !(value > 0.0) || !isfinite(value)) return;
    auto* u = reinterpret_cast<unsigned long long*>(address);
    unsigned long long old = *u;
    while (true) {
        const double oldValue = __longlong_as_double(
            static_cast<long long>(old));
        if (oldValue >= value) return;
        const unsigned long long desired =
            static_cast<unsigned long long>(__double_as_longlong(value));
        const unsigned long long observed = atomicCAS(u, old, desired);
        if (observed == old) return;
        old = observed;
    }
}

struct InitialOverlapNearest0493x10p {
    bool valid = false;
    double distance = 0.0;
    double signedDistance = 0.0;
    double lambda = 0.0;
    double qx = 0.0, qy = 0.0;
    double wallVx = 0.0, wallVy = 0.0;
    double nx = 0.0, ny = 0.0;
    MovingSegment0493x10n seg{};
};

__device__ __forceinline__ bool q6_x10p_closest_current_segment(
    double px, double py,
    double tStart,
    double lx, double ly,
    int periodicX, int periodicY,
    const MovingSegment0493x10n& seg,
    InitialOverlapNearest0493x10p* out) {
    if (!out) return false;

    const double ax = seg.ax + seg.uax * tStart;
    const double ay = seg.ay + seg.uay * tStart;
    const double bx = seg.bx + seg.ubx * tStart;
    const double by = seg.by + seg.uby * tStart;

    const double arx = q6_x10m_minimum_image(ax - px, lx, periodicX);
    const double ary = q6_x10m_minimum_image(ay - py, ly, periodicY);
    const double dax = q6_x10m_minimum_image(bx - ax, lx, periodicX);
    const double day = q6_x10m_minimum_image(by - ay, ly, periodicY);
    const double L2 = dax * dax + day * day;
    if (!(L2 > 1.0e-24) || !isfinite(L2)) return false;

    const double pax = -arx;
    const double pay = -ary;
    double lambda = (pax * dax + pay * day) / L2;
    if (!isfinite(lambda)) return false;
    lambda = fmin(1.0, fmax(0.0, lambda));

    const double qrelx = arx + lambda * dax;
    const double qrely = ary + lambda * day;
    const double dxp = -qrelx;
    const double dyp = -qrely;
    const double distance = sqrt(dxp * dxp + dyp * dyp);

    const double invL = 1.0 / sqrt(L2);
    const double nx = day * invL;
    const double ny = -dax * invL;
    const double signedDistance = dxp * nx + dyp * ny;

    out->valid = isfinite(distance) && isfinite(signedDistance);
    out->distance = distance;
    out->signedDistance = signedDistance;
    out->lambda = lambda;
    out->qx = px + qrelx;
    out->qy = py + qrely;
    out->wallVx = seg.uax + lambda * (seg.ubx - seg.uax);
    out->wallVy = seg.uay + lambda * (seg.uby - seg.uay);
    out->nx = nx;
    out->ny = ny;
    out->seg = seg;
    return out->valid &&
           isfinite(out->wallVx) && isfinite(out->wallVy);
}

__device__ __forceinline__ bool q6_x10p_resolve_initial_overlap(
    double px, double py,
    double vx, double vy,
    double mass,
    double sideTol,
    const InitialOverlapNearest0493x10p& nearest,
    MovingSegmentCollision0493x10n* out) {
    if (!out || !nearest.valid || !(nearest.signedDistance > sideTol))
        return false;

    const double reln =
        (vx - nearest.wallVx) * nearest.nx +
        (vy - nearest.wallVy) * nearest.ny;
    if (!isfinite(reln)) return false;

    const double pushTol = 4.0 * sideTol;

    out->hit = true;
    out->initialOverlap = true;
    out->tau = 0.0;
    out->lambda = nearest.lambda;
    out->wallVx = nearest.wallVx;
    out->wallVy = nearest.wallVy;
    out->nx = nearest.nx;
    out->ny = nearest.ny;
    out->relnBefore = reln;
    out->penetration = nearest.signedDistance;

    out->positionCorrectionX =
        (nearest.qx - px) - pushTol * nearest.nx;
    out->positionCorrectionY =
        (nearest.qy - py) - pushTol * nearest.ny;

    if (reln > 1.0e-13) {
        out->overlapOutwardReflected = true;
        out->newVx = vx - 2.0 * reln * nearest.nx;
        out->newVy = vy - 2.0 * reln * nearest.ny;
        const double impulse = 2.0 * mass * reln;
        out->impulseWallX = impulse * nearest.nx;
        out->impulseWallY = impulse * nearest.ny;
    } else {
        out->overlapOutwardReflected = false;
        out->newVx = vx;
        out->newVy = vy;
        out->impulseWallX = 0.0;
        out->impulseWallY = 0.0;
    }

    return isfinite(out->newVx) && isfinite(out->newVy) &&
           isfinite(out->positionCorrectionX) &&
           isfinite(out->positionCorrectionY);
}

__device__ __forceinline__ bool q6_x10n_collide_moving_segment(
    double x0, double y0,
    double vx, double vy,
    double mass,
    double tStart,
    double window,
    double dx, double dy,
    double lx, double ly,
    int periodicX, int periodicY,
    const MovingSegment0493x10n& seg,
    MovingSegmentCollision0493x10n* out) {
    if (!out || !(window > 0.0)) return false;

    const double agx = seg.ax + seg.uax * tStart;
    const double agy = seg.ay + seg.uay * tStart;
    const double dgx = (seg.bx - seg.ax) + (seg.ubx - seg.uax) * tStart;
    const double dgy = (seg.by - seg.ay) + (seg.uby - seg.uay) * tStart;
    double arx = q6_x10m_minimum_image(agx - x0, lx, periodicX);
    double ary = q6_x10m_minimum_image(agy - y0, ly, periodicY);
    const double L20 = dgx * dgx + dgy * dgy;
    if (!(L20 > 1.0e-24) || !isfinite(L20)) return false;
    const double invL0 = 1.0 / sqrt(L20);
    const double n0x = dgy * invL0;   // outward: segments are oriented A->B
    const double n0y = -dgx * invL0;
    const double s0 = (-arx) * n0x + (-ary) * n0y;
    const double h = fmin(dx, dy);
    const double sideTol = 1.0e-8 * fmax(1.0, h);
    // x10p pre-resolves the nearest finite-segment initial overlap.
    if (s0 > sideTol || s0 < -2.5 * h) return false;

    const double r0x = -arx;
    const double r0y = -ary;
    const double urx = vx - seg.uax;
    const double ury = vy - seg.uay;
    const double udx = seg.ubx - seg.uax;
    const double udy = seg.uby - seg.uay;
    const double c0 = q6_x10n_cross2(dgx, dgy, r0x, r0y);
    const double c1 = q6_x10n_cross2(dgx, dgy, urx, ury) +
                      q6_x10n_cross2(udx, udy, r0x, r0y);
    const double c2 = q6_x10n_cross2(udx, udy, urx, ury);

    double roots[2]; int nr = 0;
    const double eps = 1.0e-14;
    if (fabs(c2) < eps) {
        if (fabs(c1) < eps) return false;
        roots[nr++] = -c0 / c1;
    } else {
        double disc = c1 * c1 - 4.0 * c2 * c0;
        if (disc < -1.0e-14 * fmax(1.0, c1 * c1)) return false;
        disc = fmax(0.0, disc);
        const double sd = sqrt(disc);
        roots[nr++] = (-c1 - sd) / (2.0 * c2);
        roots[nr++] = (-c1 + sd) / (2.0 * c2);
        if (roots[1] < roots[0]) {
            const double tmp = roots[0]; roots[0] = roots[1]; roots[1] = tmp;
        }
    }

    for (int ir = 0; ir < nr; ++ir) {
        double tau = roots[ir];
        const double tTol = 1.0e-11 * fmax(1.0, window);
        if (tau < -tTol || tau > window + tTol || !isfinite(tau)) continue;
        tau = fmin(window, fmax(0.0, tau));
        const double dxh = dgx + udx * tau;
        const double dyh = dgy + udy * tau;
        const double L2 = dxh * dxh + dyh * dyh;
        if (!(L2 > 1.0e-24)) continue;
        const double rxh = r0x + urx * tau;
        const double ryh = r0y + ury * tau;
        double lambda = (rxh * dxh + ryh * dyh) / L2;
        const double ltol = 1.0e-9;
        if (lambda < -ltol || lambda > 1.0 + ltol) continue;
        lambda = fmin(1.0, fmax(0.0, lambda));
        const double invL = 1.0 / sqrt(L2);
        const double nxh = dyh * invL;
        const double nyh = -dxh * invL;
        const double wallVx = seg.uax + lambda * (seg.ubx - seg.uax);
        const double wallVy = seg.uay + lambda * (seg.uby - seg.uay);
        const double reln = (vx - wallVx) * nxh + (vy - wallVy) * nyh;
        if (!(reln > 1.0e-13) || !isfinite(reln)) continue;

        out->hit = true;
        out->tau = tau;
        out->lambda = lambda;
        out->wallVx = wallVx;
        out->wallVy = wallVy;
        out->nx = nxh;
        out->ny = nyh;
        out->relnBefore = reln;
        out->newVx = vx - 2.0 * reln * nxh;
        out->newVy = vy - 2.0 * reln * nyh;
        const double impulse = 2.0 * mass * reln;
        out->impulseWallX = impulse * nxh;
        out->impulseWallY = impulse * nyh;
        return isfinite(out->newVx) && isfinite(out->newVy);
    }
    return false;
}

__device__ __forceinline__ int q6_x10n_position_cell(
    double x, double y,
    int nx, int ny, double lx, double ly,
    int periodicX, int periodicY) {
    if (periodicX) {
        x -= floor(x / lx) * lx;
        if (x >= lx) x = 0.0;
    }
    if (periodicY) {
        y -= floor(y / ly) * ly;
        if (y >= ly) y = 0.0;
    }
    if (x < 0.0 || x >= lx || y < 0.0 || y >= ly) return -1;
    int i = static_cast<int>(floor(x * static_cast<double>(nx) / lx));
    int j = static_cast<int>(floor(y * static_cast<double>(ny) / ly));
    if (i < 0) i = 0; else if (i >= nx) i = nx - 1;
    if (j < 0) j = 0; else if (j >= ny) j = ny - 1;
    return j * nx + i;
}

__global__ void q6_x10n_apply_continuous_moving_interface(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    const double* alpha,
    const unsigned char* segCount,
    const double* segAx, const double* segAy,
    const double* segBx, const double* segBy,
    const double* segUax, const double* segUay,
    const double* segUbx, const double* segUby,
    double* wallImpulseX,
    double* wallImpulseY,
    std::uint32_t phaseAType,
    int nx, int ny,
    double lx, double ly, double dt,
    int periodicX, int periodicY,
    int resolveInitialOverlap0493x10p,
    KineticCrossingAccumulator0493x9x* audit) {
    const std::uint64_t idx =
        static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride =
        static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);

    for (std::uint64_t p = idx; p < nParticles; p += stride) {
        if (particles.role && particles.role[p] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[p] != phaseAType) continue;
        const int initialCell = cells.cellId[p];
        if (initialCell < 0 || initialCell >= cells.numCells) continue;

        const double x0 = particles.x[p];
        const double y0 = particles.y[p];
        const double vx0 = particles.vx[p];
        const double vy0 = particles.vy[p];
        const double mass = particles.mass ? particles.mass[p] : 1.0;

        bool oldStationaryOuter = false;
        if (audit) {
            double a0 = 0.0, a1 = 0.0;
            const bool ok0 = q6_x9t_sample_alpha(
                alpha, x0, y0, nx, ny, lx, ly, periodicX, periodicY, &a0);
            const bool ok1 = q6_x9t_sample_alpha(
                alpha, x0 + vx0 * dt, y0 + vy0 * dt,
                nx, ny, lx, ly, periodicX, periodicY, &a1);
            oldStationaryOuter = ok0 && ok1 && a0 >= 0.5 && a1 < 0.5;
            if (oldStationaryOuter)
                atomicAdd(&audit->continuousWallOldStationaryCrossingCandidates, 1ull);
        }

        double cx = x0, cy = y0;
        double cvx = vx0, cvy = vy0;
        double elapsed = 0.0;
        int hitsTotal = 0;
        bool sawAnySegment = false;
        bool sawCandidateNoHit = false;
        int firstSearchCandidates = 0;

        // Up to three local impacts handles a near-vertex hit without turning
        // the interface into a multi-pass global particle correction.
        for (int event = 0; event < 3; ++event) {
            const double remaining = dt - elapsed;
            if (!(remaining > 1.0e-14)) break;
            const int cc = q6_x10n_position_cell(
                cx, cy, nx, ny, lx, ly, periodicX, periodicY);
            if (cc < 0) break;
            const int ci = cc % nx;
            const int cj = cc / nx;

            MovingSegmentCollision0493x10n best{};
            MovingSegment0493x10n bestSeg{};
            double bestTau = remaining + 1.0;
            int validHits = 0;
            int candidates = 0;

            InitialOverlapNearest0493x10p nearest{};
            double nearestDistance0493x10p = 1.0e300;

            for (int dj = -1; dj <= 1; ++dj) {
                for (int di = -1; di <= 1; ++di) {
                    const int owner = q6_x10n_cell_index(
                        ci + di, cj + dj, nx, ny, periodicX, periodicY);
                    if (owner < 0) continue;
                    const int ns = static_cast<int>(segCount[owner]);
                    for (int slot = 0; slot < ns && slot < 2; ++slot) {
                        ++candidates;
                        const int s = 2 * owner + slot;
                        MovingSegment0493x10n seg{};
                        seg.ax = segAx[s]; seg.ay = segAy[s];
                        seg.bx = segBx[s]; seg.by = segBy[s];
                        seg.uax = segUax[s]; seg.uay = segUay[s];
                        seg.ubx = segUbx[s]; seg.uby = segUby[s];
                        seg.ownerCell = owner;

                        if (resolveInitialOverlap0493x10p && event == 0) {
                            InitialOverlapNearest0493x10p q{};
                            if (q6_x10p_closest_current_segment(
                                    cx, cy, elapsed, lx, ly,
                                    periodicX, periodicY, seg, &q) &&
                                q.distance < nearestDistance0493x10p) {
                                nearestDistance0493x10p = q.distance;
                                nearest = q;
                            }
                        }

                        MovingSegmentCollision0493x10n hit{};
                        if (!q6_x10n_collide_moving_segment(
                                cx, cy, cvx, cvy, mass,
                                elapsed, remaining,
                                dx, dy, lx, ly,
                                periodicX, periodicY,
                                seg, &hit))
                            continue;
                        ++validHits;
                        if (hit.tau < bestTau) {
                            bestTau = hit.tau;
                            best = hit;
                            bestSeg = seg;
                        }
                    }
                }
            }

            // 0493x10q: fallback broad phase for initial overlap only.
            // Cost remains on the rare path: the normal swept search above is
            // unchanged (3x3). If no segment is visible from a vacuum-side
            // cell, inspect only the outer ring of a 7x7 neighborhood.
            if (resolveInitialOverlap0493x10p && event == 0 &&
                !nearest.valid && alpha && alpha[cc] < 0.5) {
                if (audit)
                    atomicAdd(&audit->x10qWideSearchTriggered, 1ull);

                for (int dj0493x10q = -3; dj0493x10q <= 3; ++dj0493x10q) {
                    for (int di0493x10q = -3; di0493x10q <= 3; ++di0493x10q) {
                        if (di0493x10q >= -1 && di0493x10q <= 1 &&
                            dj0493x10q >= -1 && dj0493x10q <= 1)
                            continue; // already covered by the normal 3x3 search
                        const int owner0493x10q = q6_x10n_cell_index(
                            ci + di0493x10q, cj + dj0493x10q,
                            nx, ny, periodicX, periodicY);
                        if (owner0493x10q < 0) continue;
                        const int ns0493x10q =
                            static_cast<int>(segCount[owner0493x10q]);
                        for (int slot0493x10q = 0;
                             slot0493x10q < ns0493x10q && slot0493x10q < 2;
                             ++slot0493x10q) {
                            const int s0493x10q =
                                2 * owner0493x10q + slot0493x10q;
                            MovingSegment0493x10n seg0493x10q{};
                            seg0493x10q.ax = segAx[s0493x10q];
                            seg0493x10q.ay = segAy[s0493x10q];
                            seg0493x10q.bx = segBx[s0493x10q];
                            seg0493x10q.by = segBy[s0493x10q];
                            seg0493x10q.uax = segUax[s0493x10q];
                            seg0493x10q.uay = segUay[s0493x10q];
                            seg0493x10q.ubx = segUbx[s0493x10q];
                            seg0493x10q.uby = segUby[s0493x10q];
                            seg0493x10q.ownerCell = owner0493x10q;

                            InitialOverlapNearest0493x10p q0493x10q{};
                            if (q6_x10p_closest_current_segment(
                                    cx, cy, elapsed, lx, ly,
                                    periodicX, periodicY,
                                    seg0493x10q, &q0493x10q) &&
                                q0493x10q.distance < nearestDistance0493x10p) {
                                nearestDistance0493x10p = q0493x10q.distance;
                                nearest = q0493x10q;
                            }
                        }
                    }
                }

                if (audit) {
                    if (nearest.valid)
                        atomicAdd(&audit->x10qWideSearchFoundSegment, 1ull);
                    else
                        atomicAdd(
                            &audit->x10qOrphanNoSegmentAfterWideSearch, 1ull);
                }
            }

            if (resolveInitialOverlap0493x10p && event == 0 && nearest.valid) {
                const double h0493x10p = fmin(dx, dy);
                const double sideTol0493x10p =
                    1.0e-8 * fmax(1.0, h0493x10p);
                if (nearest.signedDistance > sideTol0493x10p) {
                    if (audit)
                        atomicAdd(&audit->x10pInitialOutside, 1ull);

                    const bool deepOverlap0493x10q =
                        nearest.distance > 2.5 * h0493x10p;
                    MovingSegmentCollision0493x10n overlap{};
                    if (q6_x10p_resolve_initial_overlap(
                            cx, cy, cvx, cvy, mass,
                            sideTol0493x10p, nearest, &overlap)) {
                        best = overlap;
                        bestSeg = nearest.seg;
                        bestTau = 0.0;
                        if (audit) {
                            atomicAdd(
                                &audit->x10pInitialOverlapResolved, 1ull);
                            if (overlap.overlapOutwardReflected)
                                atomicAdd(
                                    &audit->x10pInitialOverlapOutwardReflected,
                                    1ull);
                            else
                                atomicAdd(
                                    &audit->x10pInitialOverlapInwardReleased,
                                    1ull);
                            atomic_add_double_0400(
                                &audit->x10pInitialOverlapPenetrationSum,
                                overlap.penetration);
                            q6_x10p_atomic_max_positive_double(
                                &audit->x10pInitialOverlapMaxPenetration,
                                overlap.penetration);
                            q6_x10p_atomic_max_positive_double(
                                &audit->x10qResolvedNearestDistanceMax,
                                nearest.distance);
                            if (deepOverlap0493x10q)
                                atomicAdd(
                                    &audit->x10qDeepOverlapResolved, 1ull);
                        }
                    } else if (audit) {
                        // This should be numerically exceptional: nearest is
                        // already finite and signedDistance>sideTol.
                        atomicAdd(&audit->x10qOverlapResolveFailure, 1ull);
                    }
                }
            }

            if (event == 0) firstSearchCandidates = candidates;
            if (candidates > 0) sawAnySegment = true;
            if (!best.hit) {
                if (candidates > 0) sawCandidateNoHit = true;
                break;
            }
            if (validHits > 1 && audit)
                atomicAdd(&audit->continuousWallMultipleCollisionCandidates, 1ull);

            cx += cvx * best.tau + best.positionCorrectionX;
            cy += cvy * best.tau + best.positionCorrectionY;
            elapsed += best.tau;
            cvx = best.newVx;
            cvy = best.newVy;
            ++hitsTotal;

            atomic_add_double_0400(
                &wallImpulseX[bestSeg.ownerCell], best.impulseWallX);
            atomic_add_double_0400(
                &wallImpulseY[bestSeg.ownerCell], best.impulseWallY);

            if (audit) {
                atomicAdd(&audit->continuousWallCollisions, 1ull);
                if (hitsTotal == 2)
                    atomicAdd(&audit->continuousWallSecondCollisions, 1ull);
                else if (hitsTotal == 3)
                    atomicAdd(&audit->continuousWallThirdCollisions, 1ull);
                atomic_add_double_0400(
                    &audit->continuousWallCollisionTimeFractionSum,
                    elapsed / dt);
                const double wallVn = best.wallVx * best.nx + best.wallVy * best.ny;
                atomic_add_double_0400(&audit->continuousWallWallVnSum, wallVn);
                atomic_add_double_0400(
                    &audit->continuousWallWallVnSqSum, wallVn * wallVn);
                atomic_add_double_0400(
                    &audit->continuousWallWallVnAbsSum, fabs(wallVn));
                const double cbx = (event == 0 ? vx0 : 0.0); // reference below is recomputed
                (void)cbx;
                double beforeRelX = 0.0;
                double beforeRelY = 0.0;
                if (best.initialOverlap && !best.overlapOutwardReflected) {
                    beforeRelX = best.newVx - best.wallVx;
                    beforeRelY = best.newVy - best.wallVy;
                } else {
                    beforeRelX =
                        (best.newVx + 2.0 * best.relnBefore * best.nx) -
                        best.wallVx;
                    beforeRelY =
                        (best.newVy + 2.0 * best.relnBefore * best.ny) -
                        best.wallVy;
                }
                const double afterRelX = best.newVx - best.wallVx;
                const double afterRelY = best.newVy - best.wallVy;
                const double eBefore = beforeRelX * beforeRelX + beforeRelY * beforeRelY;
                const double eAfter = afterRelX * afterRelX + afterRelY * afterRelY;
                atomic_add_double_0400(
                    &audit->continuousWallRelativeSpeedSqAbsErrorSum,
                    fabs(eAfter - eBefore));
                atomic_add_double_0400(
                    &audit->continuousWallRelativeSpeedSqReferenceSum,
                    fabs(eBefore));
                const double relAfter =
                    (best.newVx - best.wallVx) * best.nx +
                    (best.newVy - best.wallVy) * best.ny;
                if (!(relAfter < 1.0e-12 * fmax(1.0, fabs(best.relnBefore))))
                    atomicAdd(&audit->continuousWallRelativeStillOutward, 1ull);
                atomic_add_double_0400(
                    &audit->continuousWallImpulseX, best.impulseWallX);
                atomic_add_double_0400(
                    &audit->continuousWallImpulseY, best.impulseWallY);
                atomic_add_double_0400(
                    &audit->continuousWallImpulseAbsSum,
                    sqrt(best.impulseWallX * best.impulseWallX +
                         best.impulseWallY * best.impulseWallY));
            }
        }

        if (audit && sawAnySegment)
            atomicAdd(&audit->continuousWallParticlesWithCandidate, 1ull);
        if (audit && oldStationaryOuter && hitsTotal == 0)
            atomicAdd(&audit->continuousWallOldStationaryCrossingReleased, 1ull);
        if (audit && oldStationaryOuter && firstSearchCandidates == 0)
            atomicAdd(&audit->continuousWallNoNearbySegment, 1ull);
        if (audit && oldStationaryOuter && firstSearchCandidates > 0 && hitsTotal == 0)
            atomicAdd(&audit->continuousWallCandidateNoHit, 1ull);
        if (audit && hitsTotal >= 3)
            atomicAdd(&audit->continuousWallCollisionLimitReached, 1ull);

        if (hitsTotal == 0) continue;
        const double remaining = fmax(0.0, dt - elapsed);
        const double xf = cx + cvx * remaining;
        const double yf = cy + cvy * remaining;
        const double corrX = xf - cvx * dt - x0;
        const double corrY = yf - cvy * dt - y0;
        particles.x[p] = x0 + corrX;
        particles.y[p] = y0 + corrY;
        particles.vx[p] = cvx;
        particles.vy[p] = cvy;
        if (audit)
            atomic_add_double_0400(
                &audit->continuousWallPositionShiftAbsSum,
                sqrt(corrX * corrX + corrY * corrY));
    }
}

// 0493x10i: reduce existing per-cell donor/receiver statistics into
// shifted mesoscopic reservoirs. No particle pass is added.
// 0493x10l PASSIVE pre-wall-interface diagnostics.
// These kernels DO NOT modify particles, alpha, Q6 fields, or the kinetic
// reflection path.  They answer only: what normal interface velocity does the
// post-Q6/B1 liquid field predict before any wall/interface correction?
__device__ __forceinline__ int q6_x10l_wrap_or_clamp_index(
    int i, int n, bool periodic) {
    if (periodic) {
        i %= n;
        if (i < 0) i += n;
        return i;
    }
    return max(0, min(n - 1, i));
}

__device__ __forceinline__ double q6_x10l_alpha_cell(
    const double* alpha,
    int i, int j, int nx, int ny,
    bool periodicX, bool periodicY) {
    i = q6_x10l_wrap_or_clamp_index(i, nx, periodicX);
    j = q6_x10l_wrap_or_clamp_index(j, ny, periodicY);
    return alpha[j * nx + i];
}

__device__ __forceinline__ bool q6_x10l_interface_cell_geometry(
    const double* alpha,
    int i, int j, int nx, int ny,
    double dx, double dy,
    bool periodicX, bool periodicY,
    double* nxOut, double* nyOut) {
    const double ac = q6_x10l_alpha_cell(
        alpha, i, j, nx, ny, periodicX, periodicY);
    const double al = q6_x10l_alpha_cell(
        alpha, i - 1, j, nx, ny, periodicX, periodicY);
    const double ar = q6_x10l_alpha_cell(
        alpha, i + 1, j, nx, ny, periodicX, periodicY);
    const double ab = q6_x10l_alpha_cell(
        alpha, i, j - 1, nx, ny, periodicX, periodicY);
    const double at = q6_x10l_alpha_cell(
        alpha, i, j + 1, nx, ny, periodicX, periodicY);

    const double amin = fmin(ac, fmin(fmin(al, ar), fmin(ab, at)));
    const double amax = fmax(ac, fmax(fmax(al, ar), fmax(ab, at)));
    if (!(amin <= 0.5 && amax >= 0.5) || !(amax - amin > 1.0e-12))
        return false;

    const double gx = (ar - al) / (2.0 * dx);
    const double gy = (at - ab) / (2.0 * dy);
    const double g2 = gx * gx + gy * gy;
    if (!(g2 > 1.0e-24) || !isfinite(g2)) return false;

    const double invg = 1.0 / sqrt(g2);
    // alpha is high in liquid and low in vacuum, therefore -grad(alpha)
    // points from liquid to vacuum.
    *nxOut = -gx * invg;
    *nyOut = -gy * invg;
    return isfinite(*nxOut) && isfinite(*nyOut);
}

__global__ void q6_x10l_accumulate_prewall_interface_cells(
    int numCells,
    int nx,
    int ny,
    double lx,
    double ly,
    bool periodicX,
    bool periodicY,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    KineticCrossingAccumulator0493x9x* audit) {
    if (!audit) return;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);
    const double dsProxy = sqrt(dx * dy);
    const double cellArea = dx * dy;

    for (int c = idx; c < numCells; c += stride) {
        const double ac = alpha[c];
        if (isfinite(ac)) {
            const double af = fmin(1.0, fmax(0.0, ac));
            atomic_add_double_0400(&audit->preWallAlphaArea, af * cellArea);
        }

        const int i = c % nx;
        const int j = c / nx;
        double nxo = 0.0, nyo = 0.0;
        if (!q6_x10l_interface_cell_geometry(
                alpha, i, j, nx, ny, dx, dy,
                periodicX, periodicY, &nxo, &nyo))
            continue;

        atomicAdd(&audit->preWallInterfaceCells, 1ull);
        atomic_add_double_0400(
            &audit->preWallInterfaceLengthProxy, dsProxy);
        // Larger score means a lower Cartesian row.  Audit memory is zeroed,
        // so atomicMax works without a special sentinel.
        const unsigned long long score =
            static_cast<unsigned long long>(ny - j);
        atomicMax(&audit->preWallLowerTipScore, score);

        const double m = totalM[c];
        const double px = totalPx[c];
        const double py = totalPy[c];
        if (!(m > 1.0e-14) || !isfinite(m) || !isfinite(px) || !isfinite(py))
            continue;

        const double ux = px / m;
        const double uy = py / m;
        const double vn = ux * nxo + uy * nyo;
        if (!isfinite(vn)) continue;

        atomicAdd(&audit->preWallVelocityCells, 1ull);
        if (vn > 0.0) atomicAdd(&audit->preWallPositiveVnCells, 1ull);
        if (vn < 0.0) atomicAdd(&audit->preWallNegativeVnCells, 1ull);
        atomic_add_double_0400(&audit->preWallVnSum, vn);
        atomic_add_double_0400(&audit->preWallVnSqSum, vn * vn);
        atomic_add_double_0400(&audit->preWallAbsVnSum, fabs(vn));
        atomic_add_double_0400(&audit->preWallVelocityMassSum, m);
        atomic_add_double_0400(&audit->preWallMassVnSum, m * vn);
        atomic_add_double_0400(
            &audit->preWallNetNormalFluxProxy, vn * dsProxy);
    }
}

__global__ void q6_x10l_accumulate_prewall_lower_tip(
    int numCells,
    int nx,
    int ny,
    double lx,
    double ly,
    bool periodicX,
    bool periodicY,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    KineticCrossingAccumulator0493x9x* audit) {
    if (!audit) return;
    const unsigned long long score = audit->preWallLowerTipScore;
    if (score == 0ull) return;

    const int tipJ = ny - static_cast<int>(score);
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);

    if (blockIdx.x == 0 && threadIdx.x == 0) {
        // Cell-centre proxy of the lowest alpha=.5-support row.
        audit->preWallLowerTipY = (static_cast<double>(tipJ) + 0.5) * dy;
    }

    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < numCells; c += stride) {
        const int i = c % nx;
        const int j = c / nx;
        // Lower-tip band: lowest interface row plus two rows toward the liquid.
        if (j < tipJ || j > tipJ + 2) continue;

        double nxo = 0.0, nyo = 0.0;
        if (!q6_x10l_interface_cell_geometry(
                alpha, i, j, nx, ny, dx, dy,
                periodicX, periodicY, &nxo, &nyo))
            continue;

        const double m = totalM[c];
        const double px = totalPx[c];
        const double py = totalPy[c];
        if (!(m > 1.0e-14) || !isfinite(m) || !isfinite(px) || !isfinite(py))
            continue;
        const double ux = px / m;
        const double uy = py / m;
        const double vn = ux * nxo + uy * nyo;
        if (!isfinite(vn)) continue;

        atomicAdd(&audit->preWallLowerTipCells, 1ull);
        if (vn > 0.0)
            atomicAdd(&audit->preWallLowerTipPositiveVnCells, 1ull);
        if (vn < 0.0)
            atomicAdd(&audit->preWallLowerTipNegativeVnCells, 1ull);
        atomic_add_double_0400(&audit->preWallLowerTipVnSum, vn);
        atomic_add_double_0400(&audit->preWallLowerTipVnSqSum, vn * vn);
        atomic_add_double_0400(&audit->preWallLowerTipAbsVnSum, fabs(vn));
        atomic_add_double_0400(&audit->preWallLowerTipMassSum, m);
        atomic_add_double_0400(&audit->preWallLowerTipMassVnSum, m * vn);
    }
}

__global__ void q6_x10i_reduce_meso_reactions(
    int numCells,
    int nx,
    int blockCells,
    int shiftX,
    int shiftY,
    int blocksX,
    const double* donorA,
    const double* donorSx,
    const double* donorSy,
    const double* donorH,
    const double* recvM,
    const double* recvPx,
    const double* recvPy,
    KineticGlobalReaction0493x10f* reactions) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;

    for (int c = idx; c < numCells; c += stride) {
        const int rid = q6_x10i_meso_reservoir_id(
            c, nx, blockCells, shiftX, shiftY, blocksX);
        KineticGlobalReaction0493x10f* r = &reactions[rid];

        const double A = donorA[c];
        const double Sx = donorSx[c];
        const double Sy = donorSy[c];
        const double H = donorH[c];
        const double donorRequest = fabs(A) + fabs(Sx) + fabs(Sy) + fabs(H);
        if (donorRequest > 1.0e-30 &&
            isfinite(A) && isfinite(Sx) && isfinite(Sy) && isfinite(H)) {
            atomic_add_double_0400(&r->A, A);
            atomic_add_double_0400(&r->Sx, Sx);
            atomic_add_double_0400(&r->Sy, Sy);
            atomic_add_double_0400(&r->H, H);
            atomic_add_double_0400(
                &r->cellSNormSum, sqrt(Sx * Sx + Sy * Sy));
            atomicAdd(&r->donorCells, 1ull);
        }

        const double mr = recvM[c];
        const double px = recvPx[c];
        const double py = recvPy[c];
        if (mr > 1.0e-14 && isfinite(mr) && isfinite(px) && isfinite(py)) {
            atomic_add_double_0400(&r->receiverM, mr);
            atomic_add_double_0400(&r->receiverPx, px);
            atomic_add_double_0400(&r->receiverPy, py);
            atomicAdd(&r->receiverCells, 1ull);
        }
    }
}

// Exact x10f root independently for every mesoscopic reservoir.
__global__ void q6_x10i_finalize_meso_reactions(
    int numReservoirs,
    int blockCells,
    int shiftX,
    int shiftY,
    KineticGlobalReaction0493x10f* reactions,
    KineticCrossingAccumulator0493x9x* audit) {
    const int rid = blockIdx.x * blockDim.x + threadIdx.x;
    if (rid >= numReservoirs) return;

    KineticGlobalReaction0493x10f* global = &reactions[rid];
    const double A = global->A;
    const double Sx = global->Sx;
    const double Sy = global->Sy;
    const double H = global->H;
    const double mr = global->receiverM;

    global->a = 0.0;
    global->dux = 0.0;
    global->duy = 0.0;
    global->active = 0;
    global->trivial = 0;
    global->invalid = 0;

    if (audit && rid == 0) {
        audit->mesoReactionBlockCells =
            static_cast<unsigned long long>(blockCells);
        audit->mesoReactionShiftX =
            static_cast<unsigned long long>(shiftX);
        audit->mesoReactionShiftY =
            static_cast<unsigned long long>(shiftY);
        audit->mesoReactionReservoirSlots =
            static_cast<unsigned long long>(numReservoirs);
    }

    const double request = fabs(A) + fabs(Sx) + fabs(Sy) + fabs(H);
    if (!(request > 1.0e-30) || !isfinite(request)) return;

    global->active = 1;
    double B = 0.0;
    double uRx = 0.0;
    double uRy = 0.0;
    double numer = 0.0;
    double denom = 0.0;
    double a = 0.0;
    bool valid = true;
    bool noReceiver = false;

    if (!(mr > 1.0e-14) || !isfinite(mr) ||
        !isfinite(global->receiverPx) || !isfinite(global->receiverPy)) {
        valid = false;
        noReceiver = true;
    } else {
        uRx = global->receiverPx / mr;
        uRy = global->receiverPy / mr;
        B = (Sx * Sx + Sy * Sy) / mr;
        denom = A + B;
        numer = 2.0 * (H - (uRx * Sx + uRy * Sy));
        valid = isfinite(A) && A >= 0.0 &&
                isfinite(B) && B >= 0.0 &&
                isfinite(H) && isfinite(denom) && denom > 1.0e-30 &&
                isfinite(numer);
        if (valid) a = numer / denom;
    }

    if (!(a > 0.0) || !isfinite(a)) {
        a = 0.0;
        global->trivial = 1;
        if (!valid) global->invalid = 1;
    } else {
        global->dux = a * Sx / mr;
        global->duy = a * Sy / mr;
        if (!isfinite(global->dux) || !isfinite(global->duy)) {
            global->dux = 0.0;
            global->duy = 0.0;
            a = 0.0;
            global->trivial = 1;
            global->invalid = 1;
        }
    }
    global->a = a;

    const double residual =
        a * ((uRx * Sx + uRy * Sy) - H) +
        0.5 * a * a * (A + B);
    const double sNorm = sqrt(Sx * Sx + Sy * Sy);
    const double cancellation =
        global->cellSNormSum > 0.0 ? sNorm / global->cellSNormSum : 0.0;
    const double duMag =
        sqrt(global->dux * global->dux + global->duy * global->duy);

    if (audit) {
        atomicAdd(&audit->mesoReactionActiveReservoirs, 1ull);
        if (global->trivial)
            atomicAdd(&audit->mesoReactionTrivialReservoirs, 1ull);
        if (global->invalid)
            atomicAdd(&audit->mesoReactionInvalidReservoirs, 1ull);
        if (noReceiver)
            atomicAdd(&audit->mesoReactionNoReceiverReservoirs, 1ull);
        atomicAdd(&audit->mesoReactionDonorCells, global->donorCells);
        atomicAdd(&audit->mesoReactionReceiverCells, global->receiverCells);
        atomic_add_double_0400(
            &audit->mesoReactionReceiverMassSum, mr > 0.0 ? mr : 0.0);
        atomic_add_double_0400(&audit->mesoReactionScaleSum, a);
        atomic_add_double_0400(
            &audit->mesoReactionScaleAbsFromSpecularSum, fabs(a - 2.0));
        atomic_add_double_0400(
            &audit->mesoReactionDeltaUMagnitudeSum, duMag);
        atomic_add_double_0400(
            &audit->mesoReactionCancellationSum, cancellation);
        atomic_add_double_0400(
            &audit->mesoReactionFormulaResidualAbsSum, fabs(residual));

        atomicAdd(&audit->reactionActiveCells, 1ull);
        atomicAdd(&audit->analyticConservativeReactionCells, 1ull);
        if (noReceiver)
            atomicAdd(&audit->reactionNoReceiverCells, 1ull);
        if (a > 0.0) {
            atomicAdd(&audit->reactionFeasibleCells, 1ull);
            atomicAdd(&audit->analyticPositiveScaleCells, 1ull);
            if (a > 1.0)
                atomicAdd(&audit->analyticInwardCells, 1ull);
            else
                atomicAdd(&audit->analyticNonInwardPositiveCells, 1ull);
            atomic_add_double_0400(&audit->analyticDonorScaleSum, a);
            atomic_add_double_0400(
                &audit->analyticDonorScaleAbsFromSpecularSum, fabs(a - 2.0));
        } else {
            atomicAdd(&audit->analyticTrivialCells, 1ull);
            if (global->invalid)
                atomicAdd(&audit->analyticInvalidCells, 1ull);
        }
        atomic_add_double_0400(
            &audit->reactionEnergyResidualAbsSum, fabs(residual));
        atomic_add_double_0400(
            &audit->reactionDeltaUMagnitudeSum, duMag);
    }
}

__global__ void q6_x10f_finalize_global_reaction(
    KineticGlobalReaction0493x10f* global,
    KineticCrossingAccumulator0493x9x* audit) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;

    const double A = global->A;
    const double Sx = global->Sx;
    const double Sy = global->Sy;
    const double H = global->H;
    const double mr = global->receiverM;

    global->a = 0.0;
    global->dux = 0.0;
    global->duy = 0.0;
    global->active = 0;
    global->trivial = 0;
    global->invalid = 0;

    const double request = fabs(A) + fabs(Sx) + fabs(Sy) + fabs(H);
    if (!(request > 1.0e-30) || !isfinite(request)) {
        if (audit) {
            audit->globalReactionDonorCells = global->donorCells;
            audit->globalReactionReceiverCells = global->receiverCells;
        }
        return;
    }

    global->active = 1;
    double B = 0.0;
    double uRx = 0.0;
    double uRy = 0.0;
    double numer = 0.0;
    double denom = 0.0;
    double a = 0.0;
    bool valid = true;

    if (!(mr > 1.0e-14) || !isfinite(mr) ||
        !isfinite(global->receiverPx) || !isfinite(global->receiverPy)) {
        valid = false;
    } else {
        uRx = global->receiverPx / mr;
        uRy = global->receiverPy / mr;
        B = (Sx * Sx + Sy * Sy) / mr;
        denom = A + B;
        numer = 2.0 * (H - (uRx * Sx + uRy * Sy));
        valid = isfinite(A) && A >= 0.0 &&
                isfinite(B) && B >= 0.0 &&
                isfinite(H) && isfinite(denom) && denom > 1.0e-30 &&
                isfinite(numer);
        if (valid) a = numer / denom;
    }

    if (!(a > 0.0) || !isfinite(a)) {
        a = 0.0;
        global->trivial = 1;
        if (!valid) global->invalid = 1;
    } else {
        global->dux = a * Sx / mr;
        global->duy = a * Sy / mr;
        if (!isfinite(global->dux) || !isfinite(global->duy)) {
            global->dux = 0.0;
            global->duy = 0.0;
            a = 0.0;
            global->trivial = 1;
            global->invalid = 1;
        }
    }
    global->a = a;

    const double residual =
        a * ((uRx * Sx + uRy * Sy) - H) +
        0.5 * a * a * (A + B);
    const double sNorm = sqrt(Sx * Sx + Sy * Sy);
    const double cancellation =
        global->cellSNormSum > 0.0 ? sNorm / global->cellSNormSum : 0.0;

    if (audit) {
        // Keep generic x10d diagnostics meaningful: one reaction object per
        // audited step instead of one reaction object per active interface cell.
        atomicAdd(&audit->reactionActiveCells, 1ull);
        atomicAdd(&audit->analyticConservativeReactionCells, 1ull);
        if (!(mr > 1.0e-14) || !isfinite(mr))
            atomicAdd(&audit->reactionNoReceiverCells, 1ull);

        if (a > 0.0) {
            atomicAdd(&audit->reactionFeasibleCells, 1ull);
            atomicAdd(&audit->analyticPositiveScaleCells, 1ull);
            if (a > 1.0)
                atomicAdd(&audit->analyticInwardCells, 1ull);
            else
                atomicAdd(&audit->analyticNonInwardPositiveCells, 1ull);
            atomic_add_double_0400(&audit->analyticDonorScaleSum, a);
            atomic_add_double_0400(
                &audit->analyticDonorScaleAbsFromSpecularSum, fabs(a - 2.0));
        } else {
            atomicAdd(&audit->analyticTrivialCells, 1ull);
            if (global->invalid)
                atomicAdd(&audit->analyticInvalidCells, 1ull);
        }

        atomic_add_double_0400(
            &audit->reactionEnergyResidualAbsSum, fabs(residual));
        atomic_add_double_0400(
            &audit->reactionDeltaUMagnitudeSum,
            sqrt(global->dux * global->dux + global->duy * global->duy));

        audit->globalReactionActive = 1ull;
        audit->globalReactionTrivial = global->trivial ? 1ull : 0ull;
        audit->globalReactionInvalid = global->invalid ? 1ull : 0ull;
        audit->globalReactionDonorCells = global->donorCells;
        audit->globalReactionReceiverCells = global->receiverCells;
        audit->globalReactionA = A;
        audit->globalReactionH = H;
        audit->globalReactionSNorm = sNorm;
        audit->globalReactionCellSNormSum = global->cellSNormSum;
        audit->globalReactionCancellationRatio = cancellation;
        audit->globalReactionReceiverMass = mr;
        audit->globalReactionScale = a;
        audit->globalReactionDeltaUMagnitude =
            sqrt(global->dux * global->dux + global->duy * global->duy);
        audit->globalReactionFormulaResidual = residual;
    }
}

// 0493x10d: O(Ncell) preparation between particle passes 2 and 3.
//
// Hard r=1 mode replaces the x9z receiver affine-translation + thermal-rescale
// reaction by one exact collective elastic mode.  For donor i, with its own
// interface normal n_i and the pre-reaction bath mean u_b,
//
//   g_i = (v_i-u_b).n_i > 0,
//   A   = sum m_i g_i^2,
//   S   = sum m_i g_i n_i.
//
// Receivers in the bath cell have mass M_r and mean u_r.  The family
//
//   donor:   dv_i = -a g_i n_i
//   receiver:du_r =  a S / M_r
//
// conserves momentum for every a.  Its total kinetic-energy change is
//
//   dE(a) = a(C-A) + 0.5 a^2 (A+B),
//   B = |S|^2/M_r,  C = (u_r-u_b).S.
//
// Therefore the non-trivial exact root is
//
//   a* = 2(A-C)/(A+B).
//
// No lambda, no thermal-energy floor and no fourth particle pass are needed.
// If the non-trivial root is unavailable/non-positive, x10d deliberately uses
// the trivial exact root a=0; x10c still enforces r=1 positional containment.
// Such cells are audited and are not hidden by a clamp.
__global__ void q6_x9z_prepare_receiver_reaction(
    int numCells,
    double* donorDeltaE,
    double* reactionJx,
    double* reactionJy,
    const double* recvM,
    const double* recvPx,
    const double* recvPy,
    const double* recvK,
    double* reactionLambda,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    double reflectionFraction,
    KineticCrossingAccumulator0493x9x* audit) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;

    // ---------------------------------------------------------------------
    // Historical r<1 branch, retained so x10d does not redefine evaporation.
    // ---------------------------------------------------------------------
    if (reflectionFraction < 1.0) {
        const double dED = donorDeltaE[c];
        const double Jx = reactionJx[c];
        const double Jy = reactionJy[c];
        const double request = fabs(dED) + fabs(Jx) + fabs(Jy);

        donorDeltaE[c] = 0.0;
        reactionJx[c] = 0.0;
        reactionJy[c] = 0.0;
        reactionLambda[c] = 1.0;
        if (!(request > 1.0e-30) || !isfinite(request)) return;

        if (audit) atomicAdd(&audit->reactionActiveCells, 1ull);

        const double mr = recvM[c];
        if (!(mr > 1.0e-14) || !isfinite(mr)) {
            if (audit) atomicAdd(&audit->reactionNoReceiverCells, 1ull);
            return;
        }

        const double urx = recvPx[c] / mr;
        const double ury = recvPy[c] / mr;
        const double kr = recvK[c];
        const double meanK = 0.5 * mr * (urx * urx + ury * ury);
        double krel = kr - meanK;
        const double scale = fmax(1.0, fmax(fabs(kr), fabs(meanK)));
        const double tol = 1.0e-12 * scale;
        if (krel < 0.0 && krel > -tol) krel = 0.0;

        const double dux = Jx / mr;
        const double duy = Jy / mr;
        const double meanDeltaE = urx * Jx + ury * Jy +
            0.5 * (Jx * Jx + Jy * Jy) / mr;

        double target = krel - dED - meanDeltaE;
        double lambda = 1.0;
        double residual = 0.0;
        bool feasible = false;
        if (target < 0.0 && target > -tol) target = 0.0;

        if (krel > tol && target >= 0.0 && isfinite(target)) {
            lambda = sqrt(target / krel);
            feasible = isfinite(lambda);
        } else if (krel <= tol) {
            lambda = 1.0;
            residual = krel - target;
            if (fabs(residual) <= tol) {
                residual = 0.0;
                feasible = true;
            } else if (audit) {
                atomicAdd(&audit->reactionThermalDegenerateCells, 1ull);
            }
        } else {
            lambda = 0.0;
            residual = -target;
            if (audit) atomicAdd(&audit->reactionEnergyFloorCells, 1ull);
        }

        if (!isfinite(lambda)) {
            lambda = 1.0;
            residual = krel - target;
            feasible = false;
            if (audit) atomicAdd(&audit->reactionThermalDegenerateCells, 1ull);
        }

        donorDeltaE[c] = 1.0; // active flag
        reactionJx[c] = dux;
        reactionJy[c] = duy;
        reactionLambda[c] = lambda;

        if (audit) {
            if (feasible) atomicAdd(&audit->reactionFeasibleCells, 1ull);
            atomic_add_double_0400(&audit->reactionEnergyResidualAbsSum, fabs(residual));
            atomic_add_double_0400(&audit->reactionDeltaUMagnitudeSum,
                                   sqrt(dux * dux + duy * duy));
            atomic_add_double_0400(&audit->reactionLambdaDeviationAbsSum,
                                   fabs(lambda - 1.0));
        }
        return;
    }

    // ---------------------------------------------------------------------
    // x10d hard-r1 exact analytic collective reaction.
    // Inputs currently hold A and S; outputs reuse the same buffers as
    // activeFlag, receiver delta-u and donor scale a.
    // ---------------------------------------------------------------------
    const double A = donorDeltaE[c];
    const double Sx = reactionJx[c];
    const double Sy = reactionJy[c];
    const double request = fabs(A) + fabs(Sx) + fabs(Sy);

    donorDeltaE[c] = 0.0;   // inactive by default
    reactionJx[c] = 0.0;    // receiver du_x
    reactionJy[c] = 0.0;    // receiver du_y
    reactionLambda[c] = 0.0; // x10d donor scale a (NOT lambda) in hard r=1
    if (!(request > 1.0e-30) || !isfinite(request)) return;

    // Mark the reaction cell active even when the exact trivial root a=0 is
    // selected.  Donor and receiver pass-3 decisions remain deterministic.
    donorDeltaE[c] = 1.0;
    if (audit) {
        atomicAdd(&audit->reactionActiveCells, 1ull);
        atomicAdd(&audit->analyticConservativeReactionCells, 1ull);
    }

    const double mr = recvM[c];
    const double mb = totalM[c];
    if (!(mr > 1.0e-14) || !isfinite(mr)) {
        if (audit) {
            atomicAdd(&audit->reactionNoReceiverCells, 1ull);
            atomicAdd(&audit->analyticTrivialCells, 1ull);
        }
        return; // a=0: exact no-op root
    }
    if (!(mb > 1.0e-14) || !isfinite(mb) ||
        !isfinite(totalPx[c]) || !isfinite(totalPy[c])) {
        if (audit) {
            atomicAdd(&audit->analyticTrivialCells, 1ull);
            atomicAdd(&audit->analyticInvalidCells, 1ull);
            atomicAdd(&audit->reactionThermalDegenerateCells, 1ull);
        }
        return;
    }

    const double urx = recvPx[c] / mr;
    const double ury = recvPy[c] / mr;
    const double ubx = totalPx[c] / mb;
    const double uby = totalPy[c] / mb;

    const double B = (Sx * Sx + Sy * Sy) / mr;
    const double C = (urx - ubx) * Sx + (ury - uby) * Sy;
    const double denom = A + B;
    const double numer = 2.0 * (A - C);

    bool valid = isfinite(A) && A >= 0.0 &&
                 isfinite(B) && B >= 0.0 &&
                 isfinite(C) && isfinite(denom) && denom > 1.0e-30 &&
                 isfinite(numer);
    double a = valid ? numer / denom : 0.0;

    // Do not clamp a: a clamp would destroy exact energy conservation.
    // A non-positive/non-finite non-trivial root is replaced by the other
    // exact root, a=0, and exposed explicitly in diagnostics.
    if (!(a > 0.0) || !isfinite(a)) {
        a = 0.0;
        if (audit) {
            atomicAdd(&audit->analyticTrivialCells, 1ull);
            if (!valid || !isfinite(numer / denom))
                atomicAdd(&audit->analyticInvalidCells, 1ull);
        }
        return;
    }

    const double dux = a * Sx / mr;
    const double duy = a * Sy / mr;
    if (!isfinite(dux) || !isfinite(duy)) {
        reactionLambda[c] = 0.0;
        if (audit) {
            atomicAdd(&audit->analyticTrivialCells, 1ull);
            atomicAdd(&audit->analyticInvalidCells, 1ull);
        }
        return;
    }

    reactionJx[c] = dux;
    reactionJy[c] = duy;
    reactionLambda[c] = a;

    // Algebraic residual of the exact kinetic-energy identity.  This is not a
    // substitute for the actual pass-3 deltaKineticEnergy audit; both are kept.
    const double residual = a * (C - A) + 0.5 * a * a * (A + B);

    if (audit) {
        atomicAdd(&audit->reactionFeasibleCells, 1ull);
        atomicAdd(&audit->analyticPositiveScaleCells, 1ull);
        if (a > 1.0)
            atomicAdd(&audit->analyticInwardCells, 1ull);
        else
            atomicAdd(&audit->analyticNonInwardPositiveCells, 1ull);
        atomic_add_double_0400(&audit->analyticDonorScaleSum, a);
        atomic_add_double_0400(&audit->analyticDonorScaleAbsFromSpecularSum,
                               fabs(a - 2.0));
        atomic_add_double_0400(&audit->reactionEnergyResidualAbsSum,
                               fabs(residual));
        atomic_add_double_0400(&audit->reactionDeltaUMagnitudeSum,
                               sqrt(dux * dux + duy * duy));
        // reactionLambdaDeviationAbsSum intentionally remains zero in r=1:
        // there is no receiver thermal lambda in x10d.
    }
}

__global__ void q6_x9z_apply_individual_reflections(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    const double* reactionActive,
    const double* reactionDeltaUx,
    const double* reactionDeltaUy,
    const double* recvM,
    const double* recvPx,
    const double* recvPy,
    const double* reactionLambda,
    const KineticGlobalReaction0493x10f* mesoReactions,
    int mesoBlockCells,
    int mesoShiftX,
    int mesoShiftY,
    int mesoBlocksX,
    int simpleSpecularAblation,
    int localFrameSpecularAblation,
    std::uint32_t phaseAType,
    int evaporationTargetType,
    int nx, int ny, double lx, double ly, double dt,
    int periodicX, int periodicY,
    double reflectionFraction,
    unsigned long long step,
    unsigned long long seed,
    KineticCrossingAccumulator0493x9x* audit) {
    const std::uint64_t idx = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;

    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role && particles.role[i] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[i] != phaseAType) continue;
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) continue;

        const auto d = q6_x9y_decide_crossing(
            i, particles, cells, alpha, totalM, totalPx, totalPy,
            phaseAType, nx, ny, lx, ly, dt, periodicX, periodicY,
            reflectionFraction, step, seed, true);

        if (audit && d.crossing) {
            atomic_add_double_0400(&audit->crossingFractionSum, d.crossingFraction);
            if (d.interiorCrossing)
                atomicAdd(&audit->bisectionInteriorCrossings, 1ull);
            if (d.bisectionFallback)
                atomicAdd(&audit->bisectionFallbacks, 1ull);
        }

        if ((simpleSpecularAblation || localFrameSpecularAblation) && audit) {
            const double mAudit = particles.mass ? particles.mass[i] : 1.0;
            if (alpha[c] < 0.5) atomicAdd(&audit->phaseAOuterCellParticles, 1ull);
            if (d.shellParticle) atomicAdd(&audit->shellParticles, 1ull);
            if (d.shellRecoverable) atomicAdd(&audit->shellRecoverableParticles, 1ull);
            if (d.deepOuterParticle) atomicAdd(&audit->deepOuterParticles, 1ull);
            if (d.startBelowHalf) atomicAdd(&audit->startBelowHalf, 1ull);
            if (d.crossingPointNormalFallback)
                atomicAdd(&audit->crossingPointNormalFallbacks, 1ull);
            if (d.pointwiseOuterRoutedToShell)
                atomicAdd(&audit->pointwiseOuterRoutedToShell, 1ull);
            if (d.pointwiseInteriorOuterCell)
                atomicAdd(&audit->pointwiseInteriorOuterCell, 1ull);
            if (d.crossing) {
                if (d.interiorCrossing) atomicAdd(&audit->interiorCrossings, 1ull);
                if (d.shellGuard) atomicAdd(&audit->shellGuardCrossings, 1ull);
                if (d.reflect) {
                    atomicAdd(&audit->selectedReflections, 1ull);
                    atomic_add_double_0400(&audit->reflectedMass, mAudit);
                } else {
                    atomicAdd(&audit->transmittedCrossings, 1ull);
                    atomic_add_double_0400(&audit->transmittedMass, mAudit);
                }
                atomic_add_double_0400(
                    &audit->outwardRelativeNormalSpeedSum,
                    d.outwardRelativeNormalSpeed);
            }
        }

        if (d.crossing && !d.reflect) {
            if (evaporationTargetType >= 0) {
                particles.type[i] = static_cast<std::uint32_t>(evaporationTargetType);
                if (audit) atomicAdd(&audit->convertedParticles, 1ull);
            }
            continue;
        }

        const bool hardR1Reaction = reflectionFraction >= 1.0;
        const bool localFrameSpecular =
            localFrameSpecularAblation && hardR1Reaction;
        const bool simpleSpecular =
            (simpleSpecularAblation || localFrameSpecularAblation) &&
            hardR1Reaction;
        const bool donor = d.crossing && d.reflect;
        // x10h positional recovery is SELECTIVE: an already-outer shell
        // particle is sealed only when it is itself a reflected thermal donor.
        // Non-donor shell particles remain mobile and are ordinary receivers.
        const bool selectiveShellDonorSeal =
            !simpleSpecular && hardR1Reaction && donor && d.shellRecoverable;
        const int mesoReactionCell =
            donor && d.bathCell >= 0 ? d.bathCell : c;
        const int mesoReactionId =
            hardR1Reaction && mesoReactions && mesoReactionCell >= 0
                ? q6_x10i_meso_reservoir_id(
                      mesoReactionCell, nx, mesoBlockCells,
                      mesoShiftX, mesoShiftY, mesoBlocksX)
                : -1;
        const KineticGlobalReaction0493x10f* mesoReaction =
            mesoReactionId >= 0 ? &mesoReactions[mesoReactionId] : nullptr;
        const bool mesoReactionActive =
            hardR1Reaction && mesoReaction && mesoReaction->active != 0;
        const bool receiver =
            !simpleSpecular && !d.crossing &&
            (hardR1Reaction ? mesoReactionActive
                            : (reactionActive[c] > 0.5));

        // No x10c/x10e universal endpoint barrier in x10h.
        if (!donor && !receiver) continue;

        const double oldVx = particles.vx[i];
        const double oldVy = particles.vy[i];
        double newVx = oldVx;
        double newVy = oldVy;

        if (donor) {
            const int b = d.bathCell;
            if (b < 0 || b >= cells.numCells) {
                if (audit) {
                    atomicAdd(&audit->unsupportedReflections, 1ull);
                    atomicAdd(&audit->unsupportedInvalidBath, 1ull);
                }
                continue;
            }
            const double mb = totalM[b];
            if (!(mb > 0.0) || !isfinite(mb)) {
                if (audit) {
                    atomicAdd(&audit->unsupportedReflections, 1ull);
                    atomicAdd(&audit->unsupportedInvalidBath, 1ull);
                }
                continue;
            }

            const double ubx = totalPx[b] / mb;
            const double uby = totalPy[b] / mb;
            const double gn = (oldVx - ubx) * d.nx + (oldVy - uby) * d.ny;
            if (!(gn > 0.0) || !isfinite(gn)) {
                // Classification and apply are deterministic with no particle
                // mutation between them; this should be a pure invariant fault.
                if (audit) {
                    atomicAdd(&audit->unsupportedReflections, 1ull);
                    atomicAdd(&audit->unsupportedGroupNotOutward, 1ull);
                }
                continue;
            }

            if (simpleSpecular) {
                // 0493x10j/x10k SIMPLE ABLATIONS.
                // x10j: laboratory-frame specular reflection.
                // x10k: local-liquid-frame specular reflection
                //       v' = v - 2[(v-u_b).n] n.
                // Both deliberately ignore the interface counter-impulse and
                // bypass all B8/global receiver machinery.
                if (localFrameSpecular) {
                    const double relVxBefore = oldVx - ubx;
                    const double relVyBefore = oldVy - uby;
                    const double relSpeedSqBefore =
                        relVxBefore * relVxBefore + relVyBefore * relVyBefore;
                    const double labSpeedSqBefore =
                        oldVx * oldVx + oldVy * oldVy;

                    // gn was already evaluated from the same bath velocity and
                    // pointwise interface normal and is strictly > 0 here.
                    newVx = oldVx - 2.0 * gn * d.nx;
                    newVy = oldVy - 2.0 * gn * d.ny;

                    const double relVxAfter = newVx - ubx;
                    const double relVyAfter = newVy - uby;
                    const double relSpeedSqAfter =
                        relVxAfter * relVxAfter + relVyAfter * relVyAfter;
                    const double gnAfter =
                        relVxAfter * d.nx + relVyAfter * d.ny;
                    const double labSpeedSqAfter =
                        newVx * newVx + newVy * newVy;

                    if (audit) {
                        atomicAdd(&audit->localFrameSpecularReflections, 1ull);
                        const double tolGn =
                            1.0e-12 * fmax(1.0, fabs(gn));
                        if (!(gnAfter < tolGn) || !isfinite(gnAfter))
                            atomicAdd(
                                &audit->localFrameRelativeStillOutward, 1ull);
                        atomic_add_double_0400(
                            &audit->localFrameRelativeSpeedSqAbsErrorSum,
                            fabs(relSpeedSqAfter - relSpeedSqBefore));
                        atomic_add_double_0400(
                            &audit->localFrameRelativeSpeedSqReferenceSum,
                            fabs(relSpeedSqBefore));
                        const double labDelta =
                            labSpeedSqAfter - labSpeedSqBefore;
                        atomic_add_double_0400(
                            &audit->localFrameLabSpeedSqChangeSum, labDelta);
                        atomic_add_double_0400(
                            &audit->localFrameLabSpeedSqAbsChangeSum,
                            fabs(labDelta));
                    }
                } else {
                    // 0493x10j laboratory-frame control ablation:
                    //   v' = v - 2(v.n)n
                    const double vnLab = oldVx * d.nx + oldVy * d.ny;
                    const double speedSqBefore =
                        oldVx * oldVx + oldVy * oldVy;
                    newVx = oldVx - 2.0 * vnLab * d.nx;
                    newVy = oldVy - 2.0 * vnLab * d.ny;
                    const double speedSqAfter =
                        newVx * newVx + newVy * newVy;

                    if (audit) {
                        atomicAdd(&audit->simpleSpecularReflections, 1ull);
                        if (!(vnLab > 0.0) || !isfinite(vnLab))
                            atomicAdd(
                                &audit->simpleSpecularNonPositiveLabNormal,
                                1ull);
                        atomic_add_double_0400(
                            &audit->simpleSpecularSpeedSqAbsErrorSum,
                            fabs(speedSqAfter - speedSqBefore));
                        atomic_add_double_0400(
                            &audit->simpleSpecularSpeedSqReferenceSum,
                            fabs(speedSqBefore));
                    }
                }

                if (d.interiorCrossing) {
                    // Standard remaining-time collision kinematics.  There is
                    // deliberately NO alpha endpoint seal: an interface moving
                    // with the local liquid may legitimately leave the final
                    // particle position on the outer side of the old alpha=.5.
                    const double x0p = particles.x[i];
                    const double y0p = particles.y[i];
                    const double s = fmin(fmax(d.crossingFraction, 0.0), 1.0);
                    const double xInside = x0p + s * oldVx * dt;
                    const double yInside = y0p + s * oldVy * dt;
                    const double xTarget = xInside + (1.0 - s) * newVx * dt;
                    const double yTarget = yInside + (1.0 - s) * newVy * dt;
                    const double corrX = xTarget - newVx * dt - x0p;
                    const double corrY = yTarget - newVy * dt - y0p;
                    particles.x[i] = x0p + corrX;
                    particles.y[i] = y0p + corrY;

                    if (audit) {
                        double aFinal = 0.0;
                        const bool finalOuter =
                            !q6_x9t_sample_alpha(
                                alpha,
                                particles.x[i] + newVx * dt,
                                particles.y[i] + newVy * dt,
                                nx, ny, lx, ly,
                                periodicX, periodicY, &aFinal) ||
                            !(aFinal >= 0.5);
                        const double shiftAbs =
                            sqrt(corrX * corrX + corrY * corrY);
                        if (localFrameSpecular) {
                            atomicAdd(
                                &audit->localFrameInteriorCollisions, 1ull);
                            atomic_add_double_0400(
                                &audit->localFramePositionShiftAbsSum,
                                shiftAbs);
                            if (finalOuter)
                                atomicAdd(
                                    &audit->localFrameInteriorEndpointOuter,
                                    1ull);
                        } else {
                            atomicAdd(
                                &audit->simpleSpecularInteriorCollisions, 1ull);
                            atomic_add_double_0400(
                                &audit->simpleSpecularPositionShiftAbsSum,
                                shiftAbs);
                            if (finalOuter)
                                atomicAdd(
                                    &audit->simpleSpecularInteriorFinalOutside,
                                    1ull);
                        }
                    }
                } else if (d.shellGuard) {
                    // Shell donors get only the velocity reflection; there is
                    // no positional recovery in either simple ablation.
                    if (audit) {
                        double aFinal = 0.0;
                        const bool finalOuter =
                            !q6_x9t_sample_alpha(
                                alpha,
                                particles.x[i] + newVx * dt,
                                particles.y[i] + newVy * dt,
                                nx, ny, lx, ly,
                                periodicX, periodicY, &aFinal) ||
                            !(aFinal >= 0.5);
                        if (localFrameSpecular) {
                            atomicAdd(
                                &audit->localFrameShellReflections, 1ull);
                            if (finalOuter)
                                atomicAdd(
                                    &audit->localFrameShellEndpointOuter, 1ull);
                        } else {
                            atomicAdd(
                                &audit->simpleSpecularShellReflections, 1ull);
                            if (finalOuter)
                                atomicAdd(
                                    &audit->simpleSpecularShellFinalOutside,
                                    1ull);
                        }
                    }
                }
            } else {
                // x10d hard-r1 mode replaces fixed specular factor 2 by the
                // exact cellwise conservative scale a*. r<1 keeps the historical
                // specular factor so evaporation semantics are unchanged.
                double donorScale = 2.0;
                if (hardR1Reaction) {
                    // x10i: exact scale of the shifted mesoscopic reservoir
                    // containing the donor's liquid bath cell.
                    donorScale =
                        (mesoReaction && mesoReaction->active != 0)
                            ? mesoReaction->a : 0.0;
                    if (!(donorScale >= 0.0) || !isfinite(donorScale))
                        donorScale = 0.0;
                }
                newVx = oldVx - donorScale * gn * d.nx;
                newVy = oldVy - donorScale * gn * d.ny;

                // Historical x10a geometry seal, retained only outside x10j.
                if (d.interiorCrossing) {
                    const double x0p = particles.x[i];
                    const double y0p = particles.y[i];
                    const double s = fmin(fmax(d.crossingFraction, 0.0), 1.0);
                    const double xInside = x0p + s * oldVx * dt;
                    const double yInside = y0p + s * oldVy * dt;
                    const double xCandidate = xInside + (1.0 - s) * newVx * dt;
                    const double yCandidate = yInside + (1.0 - s) * newVy * dt;

                    double targetX = xCandidate;
                    double targetY = yCandidate;
                    double aCandidate = 1.0;
                    const bool candidateSampled = q6_x9t_sample_alpha(
                        alpha, xCandidate, yCandidate,
                        nx, ny, lx, ly, periodicX, periodicY, &aCandidate);
                    const bool candidateOutside =
                        !candidateSampled || !(aCandidate >= 0.5);

                    if (audit && candidateSampled && aCandidate < 0.5)
                        atomicAdd(&audit->appliedInteriorPredictedOutside, 1ull);

                    if (candidateOutside) {
                        bool sealFallback = !candidateSampled;
                        double aInside = 0.0;
                        if (!q6_x9t_sample_alpha(alpha, xInside, yInside,
                                                 nx, ny, lx, ly,
                                                 periodicX, periodicY,
                                                 &aInside) || !(aInside >= 0.5)) {
                            targetX = x0p;
                            targetY = y0p;
                            sealFallback = true;
                        } else if (candidateSampled) {
                            double lo = 0.0;
                            double hi = 1.0;
                            for (int it = 0; it < 4; ++it) {
                                const double mid = 0.5 * (lo + hi);
                                const double xm =
                                    xInside + mid * (xCandidate - xInside);
                                const double ym =
                                    yInside + mid * (yCandidate - yInside);
                                double am = 0.5;
                                if (!q6_x9t_sample_alpha(
                                        alpha, xm, ym,
                                        nx, ny, lx, ly,
                                        periodicX, periodicY, &am) ||
                                    !isfinite(am)) {
                                    sealFallback = true;
                                    break;
                                }
                                if (am >= 0.5) lo = mid;
                                else hi = mid;
                            }
                            if (sealFallback) {
                                targetX = xInside;
                                targetY = yInside;
                            } else {
                                targetX =
                                    xInside + lo * (xCandidate - xInside);
                                targetY =
                                    yInside + lo * (yCandidate - yInside);
                            }
                        } else {
                            targetX = xInside;
                            targetY = yInside;
                        }

                        double aTarget = 0.0;
                        if (!q6_x9t_sample_alpha(
                                alpha, targetX, targetY,
                                nx, ny, lx, ly,
                                periodicX, periodicY, &aTarget) ||
                            !(aTarget >= 0.5)) {
                            targetX = x0p;
                            targetY = y0p;
                            sealFallback = true;
                        }

                        if (audit) {
                            atomicAdd(&audit->endpointSealCorrections, 1ull);
                            if (sealFallback)
                                atomicAdd(
                                    &audit->endpointSealSampleFallbacks, 1ull);
                        }
                    }

                    const double corrX = targetX - newVx * dt - x0p;
                    const double corrY = targetY - newVy * dt - y0p;
                    particles.x[i] = x0p + corrX;
                    particles.y[i] = y0p + corrY;
                    if (audit) {
                        const double corrAbs = sqrt(corrX * corrX + corrY * corrY);
                        atomic_add_double_0400(
                            &audit->positionCorrectionAbsSum, corrAbs);
                        if (candidateOutside)
                            atomic_add_double_0400(
                                &audit->endpointSealCorrectionAbsSum, corrAbs);

                        double afinal = 0.0;
                        if (!q6_x9t_sample_alpha(
                                alpha,
                                particles.x[i] + newVx * dt,
                                particles.y[i] + newVy * dt,
                                nx, ny, lx, ly,
                                periodicX, periodicY, &afinal) ||
                            !(afinal >= 0.5))
                            atomicAdd(
                                &audit->appliedInteriorFinalOutside, 1ull);
                    }
                }
            }

            if (audit) {
                atomicAdd(&audit->appliedReflections, 1ull);
                atomicAdd(&audit->individualDonorReflections, 1ull);
                const double postGn =
                    (newVx - ubx) * d.nx + (newVy - uby) * d.ny;
                const double tol = 1.0e-12 * fmax(1.0, fabs(gn));
                if (postGn > tol)
                    atomicAdd(&audit->appliedStillOutwardRelative, 1ull);
            }
        } else if (receiver) {
            const double mr = recvM[c];
            if (!(mr > 0.0) || !isfinite(mr)) continue;
            if (hardR1Reaction) {
                // x10i: receiver correction is local to the same shifted
                // mesoscopic reservoir, preserving exact P/E per reservoir.
                const double dux = mesoReaction ? mesoReaction->dux : 0.0;
                const double duy = mesoReaction ? mesoReaction->duy : 0.0;
                newVx = oldVx + dux;
                newVy = oldVy + duy;
            } else {
                // Historical r<1 reaction retained for evaporation studies.
                const double urx = recvPx[c] / mr;
                const double ury = recvPy[c] / mr;
                const double lambda = reactionLambda[c];
                newVx = urx + reactionDeltaUx[c] + lambda * (oldVx - urx);
                newVy = ury + reactionDeltaUy[c] + lambda * (oldVy - ury);
            }
            if (audit) atomicAdd(&audit->receiverCorrectedParticles, 1ull);
        }

        // 0493x10h selective shell DONOR seal.
        //
        // This is no longer a general hard-retention mechanism. It runs only
        // for an already-outer shell particle that has independently satisfied
        // the relative thermal donor gate and has been selected for reflection.
        // Non-donor shell particles are never position-corrected here.
        if (selectiveShellDonorSeal) {
            if (audit) atomicAdd(&audit->shellHardRetentionCandidates, 1ull);

            const double x0p = particles.x[i];
            const double y0p = particles.y[i];
            const double xCandidate = x0p + newVx * dt;
            const double yCandidate = y0p + newVy * dt;
            double aCandidate = 0.0;
            const bool candidateSampled = q6_x9t_sample_alpha(
                alpha, xCandidate, yCandidate,
                nx, ny, lx, ly, periodicX, periodicY, &aCandidate);

            if (candidateSampled && aCandidate >= 0.5) {
                if (audit) atomicAdd(&audit->shellHardRetentionAlreadyInside, 1ull);
            } else {
                bool fallback = !candidateSampled;
                double targetX = xCandidate;
                double targetY = yCandidate;
                const int b = d.bathCell;

                if (b >= 0 && b < cells.numCells) {
                    const int bi = b % nx;
                    const int bj = b / nx;
                    const double dx = lx / static_cast<double>(nx);
                    const double dy = ly / static_cast<double>(ny);
                    double anchorX = (static_cast<double>(bi) + 0.5) * dx;
                    double anchorY = (static_cast<double>(bj) + 0.5) * dy;

                    // Use the nearest periodic image so the recovery segment is
                    // local even when an interface crosses a periodic seam.
                    if (periodicX) {
                        double dd = anchorX - xCandidate;
                        if (dd >  0.5 * lx) anchorX -= lx;
                        if (dd < -0.5 * lx) anchorX += lx;
                    }
                    if (periodicY) {
                        double dd = anchorY - yCandidate;
                        if (dd >  0.5 * ly) anchorY -= ly;
                        if (dd < -0.5 * ly) anchorY += ly;
                    }

                    double aAnchor = 0.0;
                    const bool anchorInside = q6_x9t_sample_alpha(
                        alpha, anchorX, anchorY,
                        nx, ny, lx, ly, periodicX, periodicY, &aAnchor) &&
                        aAnchor >= 0.5;

                    if (candidateSampled && aCandidate < 0.5 && anchorInside) {
                        // lo=outside, hi=inside.  Four iterations match x10a
                        // and are enough because the anchor is one direct bulk
                        // cell away.  Mirror the candidate by approximately the
                        // same normal distance across the located crossing;
                        // clamp at the bath centre if that mirror would overshoot.
                        double lo = 0.0;
                        double hi = 1.0;
                        for (int it = 0; it < 4; ++it) {
                            const double mid = 0.5 * (lo + hi);
                            const double xm = xCandidate + mid * (anchorX - xCandidate);
                            const double ym = yCandidate + mid * (anchorY - yCandidate);
                            double am = 0.5;
                            if (!q6_x9t_sample_alpha(alpha, xm, ym,
                                                     nx, ny, lx, ly,
                                                     periodicX, periodicY, &am) ||
                                !isfinite(am)) {
                                fallback = true;
                                break;
                            }
                            if (am >= 0.5) hi = mid;
                            else lo = mid;
                        }

                        if (!fallback) {
                            const double tMirror = fmin(1.0, 2.0 * hi);
                            targetX = xCandidate + tMirror * (anchorX - xCandidate);
                            targetY = yCandidate + tMirror * (anchorY - yCandidate);
                            double aTarget = 0.0;
                            if (!q6_x9t_sample_alpha(alpha, targetX, targetY,
                                                     nx, ny, lx, ly,
                                                     periodicX, periodicY, &aTarget) ||
                                !(aTarget >= 0.5)) {
                                // The alpha profile need not be monotone along
                                // a curved-cell diagonal.  The bulk centre is a
                                // guaranteed local fallback by construction.
                                targetX = anchorX;
                                targetY = anchorY;
                                fallback = true;
                            }
                        } else {
                            targetX = anchorX;
                            targetY = anchorY;
                        }
                    } else if (anchorInside) {
                        targetX = anchorX;
                        targetY = anchorY;
                        fallback = true;
                    } else {
                        // Should be unreachable for shellRecoverable; leave the
                        // state untouched and make the contract failure visible.
                        fallback = true;
                    }
                } else {
                    fallback = true;
                }

                double aFinal = 0.0;
                const bool finalInside = q6_x9t_sample_alpha(
                    alpha, targetX, targetY,
                    nx, ny, lx, ly, periodicX, periodicY, &aFinal) &&
                    aFinal >= 0.5;

                if (finalInside) {
                    // Store the pre-stream location that makes the ordinary
                    // downstream streaming land exactly at the recovered target.
                    const double corrX = targetX - xCandidate;
                    const double corrY = targetY - yCandidate;
                    particles.x[i] = x0p + corrX;
                    particles.y[i] = y0p + corrY;
                    if (audit) {
                        atomicAdd(&audit->shellHardRetentionCorrections, 1ull);
                        if (fallback)
                            atomicAdd(&audit->shellHardRetentionFallbacks, 1ull);
                        atomic_add_double_0400(&audit->shellHardRetentionCorrectionAbsSum,
                                              sqrt(corrX * corrX + corrY * corrY));
                    }
                } else if (audit && fallback) {
                    atomicAdd(&audit->shellHardRetentionFallbacks, 1ull);
                }
            }

            if (audit) {
                double aVerify = 0.0;
                if (!q6_x9t_sample_alpha(alpha,
                        particles.x[i] + newVx * dt,
                        particles.y[i] + newVy * dt,
                        nx, ny, lx, ly, periodicX, periodicY, &aVerify) ||
                    !(aVerify >= 0.5))
                    atomicAdd(&audit->shellHardRetentionFinalOutside, 1ull);
            }
        }

        // 0493x10h: no universal alpha(x_final)>=0.5 barrier.
        //
        // The current alpha=0.5 is allowed to move with the liquid. Only
        // actual relative-outward reflected donors receive positional sealing
        // (x10a interior donor seal or the selective shell donor seal above).
        // x10g exact global P/E reaction remains unchanged.

        particles.vx[i] = newVx;
        particles.vy[i] = newVy;

        if (audit) {
            const double m = particles.mass ? particles.mass[i] : 1.0;
            atomic_add_double_0400(&audit->deltaPx, m * (newVx - oldVx));
            atomic_add_double_0400(&audit->deltaPy, m * (newVy - oldVy));
            atomic_add_double_0400(&audit->deltaKineticEnergy,
                0.5 * m * ((newVx * newVx + newVy * newVy) -
                           (oldVx * oldVx + oldVy * oldVy)));
        }
    }
}

__global__ void q6_apply_particle_correction_0400(CudaParticleDeviceView particles,
                                                  CudaCellWorkspaceDeviceView cells,
                                                  const double* dux,
                                                  const double* duy,
                                                  std::uint64_t nParticles,
                                                  double* partialPx,
                                                  double* partialPy) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0) {
            continue;
        }
        const double dvx = dux[c];
        const double dvy = duy[c];
        particles.vx[i] += dvx;
        particles.vy[i] += dvy;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        px += m * dvx;
        py += m * dvy;
    }
    shX[tid] = px;
    shY[tid] = py;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialPx[blockIdx.x] = shX[0];
        partialPy[blockIdx.x] = shY[0];
    }
}

__global__ void q6_apply_force_and_particle_correction_0493x4b(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    const double* dux,
    const double* duy,
    std::uint64_t nParticles,
    double dt,
    double lx,
    double ly,
    double bodyAx,
    double bodyAy,
    int tgEnable,
    double tgAmplitude,
    int tgModeX,
    int tgModeY,
    double* partialPx,
    double* partialPy) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0) {
            continue;
        }
        double ax = 0.0;
        double ay = 0.0;
        q6_force_acceleration_0493x4b(
            particles.x[i], particles.y[i], lx, ly, bodyAx, bodyAy,
            tgEnable, tgAmplitude, tgModeX, tgModeY, &ax, &ay);
        const double dvx = dux[c];
        const double dvy = duy[c];
        // Preserve the 0493x4a arithmetic order while combining both updates in
        // one resident CUDA particle pass.
        particles.vx[i] += ax * dt;
        particles.vy[i] += ay * dt;
        particles.vx[i] += dvx;
        particles.vy[i] += dvy;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        // The momentum correction audits only the Q6 correction, as in the
        // separate force-kick + Q6 path.  Physical force momentum is retained.
        px += m * dvx;
        py += m * dvy;
    }
    shX[tid] = px;
    shY[tid] = py;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialPx[blockIdx.x] = shX[0];
        partialPy[blockIdx.x] = shY[0];
    }
}

__global__ void q6_reset_species_mass_0491c(CudaSpeciesCellDeviceView0490h species) {
    const int tid = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    const int dense = species.numCells * species.speciesCount;
    for (int k = tid; k < dense; k += stride) {
        species.count[k] = 0u;
        species.mass[k] = 0.0;
        species.px[k] = 0.0;
        species.py[k] = 0.0;
        species.massFraction[k] = 0.0;
        species.occupancyFraction[k] = 0.0;
    }
    for (int c = tid; c < species.numCells; c += stride) {
        species.totalCellMass[c] = 0.0;
        species.totalOccupancyWeight[c] = 0.0;
    }
    if (tid == 0 && species.invalidTypeCounter != nullptr) {
        *species.invalidTypeCounter = 0ull;
    }
}

__global__ void q6_deposit_species_mass_from_cell_ids_0491c(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    CudaSpeciesCellDeviceView0490h species,
    std::uint64_t nParticles) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= species.numCells) {
            continue;
        }
        int speciesIndex = -1;
        const std::uint32_t type = particles.type ? particles.type[i] : 0u;
        for (int s = 0; s < species.speciesCount; ++s) {
            if (species.speciesTypes[s] == type) {
                speciesIndex = s;
                break;
            }
        }
        if (speciesIndex < 0) {
            if (species.invalidTypeCounter != nullptr) {
                atomicAdd(species.invalidTypeCounter, 1ull);
            }
            continue;
        }
        const int k = speciesIndex * species.numCells + c;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        atomicAdd(&species.count[k], 1u);
        atomic_add_double_0400(&species.mass[k], m);
        atomic_add_double_0400(&species.px[k], m * particles.vx[i]);
        atomic_add_double_0400(&species.py[k], m * particles.vy[i]);
        atomic_add_double_0400(&species.totalCellMass[c], m);
    }
}

__global__ void q6_deposit_species_tentative_force_from_cell_ids_0493x4b(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    CudaSpeciesCellDeviceView0490h species,
    std::uint64_t nParticles,
    double dt,
    double lx,
    double ly,
    double bodyAx,
    double bodyAy,
    int tgEnable,
    double tgAmplitude,
    int tgModeX,
    int tgModeY) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= species.numCells) {
            continue;
        }
        int speciesIndex = -1;
        const std::uint32_t type = particles.type ? particles.type[i] : 0u;
        for (int s = 0; s < species.speciesCount; ++s) {
            if (species.speciesTypes[s] == type) {
                speciesIndex = s;
                break;
            }
        }
        if (speciesIndex < 0) {
            if (species.invalidTypeCounter != nullptr) {
                atomicAdd(species.invalidTypeCounter, 1ull);
            }
            continue;
        }
        double ax = 0.0;
        double ay = 0.0;
        q6_force_acceleration_0493x4b(
            particles.x[i], particles.y[i], lx, ly, bodyAx, bodyAy,
            tgEnable, tgAmplitude, tgModeX, tgModeY, &ax, &ay);
        const int k = speciesIndex * species.numCells + c;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        atomicAdd(&species.count[k], 1u);
        atomic_add_double_0400(&species.mass[k], m);
        atomic_add_double_0400(&species.px[k], m * (particles.vx[i] + ax * dt));
        atomic_add_double_0400(&species.py[k], m * (particles.vy[i] + ay * dt));
        atomic_add_double_0400(&species.totalCellMass[c], m);
    }
}

__global__ void q6_finalize_species_occupancy_0493w5(
    CudaSpeciesCellDeviceView0490h species) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < species.numCells; c += stride) {
        const double totalMass = species.totalCellMass[c];
        double totalOcc = 0.0;
        for (int s = 0; s < species.speciesCount; ++s) {
            const int k = s * species.numCells + c;
            const double ref = species.referenceCellMass[s];
            if (ref > 0.0) totalOcc += species.mass[k] / ref;
        }
        species.totalOccupancyWeight[c] = totalOcc;
        for (int s = 0; s < species.speciesCount; ++s) {
            const int k = s * species.numCells + c;
            species.massFraction[k] = totalMass > 0.0 ? species.mass[k] / totalMass : 0.0;
            const double ref = species.referenceCellMass[s];
            const double occ = ref > 0.0 ? species.mass[k] / ref : 0.0;
            species.occupancyFraction[k] = totalOcc > 0.0 ? occ / totalOcc : 0.0;
        }
    }
}

__global__ void q6_apply_species_particle_correction_0491c(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    CudaSpeciesCellDeviceView0490h species,
    const double* dux,
    const double* duy,
    std::uint64_t nParticles,
    double sensitivity,
    double alphaEpsilon,
    int weightedMode,
    int fatalFallback,
    double* partialPx,
    double* partialPy,
    unsigned long long* fallbackCounter) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= species.numCells) {
            continue;
        }
        int speciesIndex = -1;
        const std::uint32_t type = particles.type ? particles.type[i] : 0u;
        for (int s = 0; s < species.speciesCount; ++s) {
            if (species.speciesTypes[s] == type) {
                speciesIndex = s;
                break;
            }
        }
        if (speciesIndex < 0) {
            continue;
        }

        double weight = 1.0;
        if (weightedMode && sensitivity > 0.0) {
            const double totalMass = species.totalCellMass[c];
            double alphaBar = 0.0;
            if (totalMass > 0.0) {
                for (int s = 0; s < species.speciesCount; ++s) {
                    const double ms = species.mass[s * species.numCells + c];
                    alphaBar += (ms / totalMass) * species.q6Strength[s];
                }
            }
            if (alphaBar > alphaEpsilon) {
                weight = (1.0 - sensitivity) +
                         sensitivity * species.q6Strength[speciesIndex] / alphaBar;
            } else if (fatalFallback) {
                atomicAdd(fallbackCounter, 1ull);
                continue;
            }
        }

        const double dvx = weight * dux[c];
        const double dvy = weight * duy[c];
        particles.vx[i] += dvx;
        particles.vy[i] += dvy;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        px += m * dvx;
        py += m * dvy;
    }
    shX[tid] = px;
    shY[tid] = py;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialPx[blockIdx.x] = shX[0];
        partialPy[blockIdx.x] = shY[0];
    }
}

__global__ void q6_apply_species_force_and_particle_correction_0493x4b(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    CudaSpeciesCellDeviceView0490h species,
    const double* dux,
    const double* duy,
    std::uint64_t nParticles,
    double sensitivity,
    double alphaEpsilon,
    int weightedMode,
    int fatalFallback,
    double dt,
    double lx,
    double ly,
    double bodyAx,
    double bodyAy,
    int tgEnable,
    double tgAmplitude,
    int tgModeX,
    int tgModeY,
    double* partialPx,
    double* partialPy,
    unsigned long long* fallbackCounter) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= species.numCells) {
            continue;
        }
        int speciesIndex = -1;
        const std::uint32_t type = particles.type ? particles.type[i] : 0u;
        for (int s = 0; s < species.speciesCount; ++s) {
            if (species.speciesTypes[s] == type) {
                speciesIndex = s;
                break;
            }
        }
        if (speciesIndex < 0) {
            continue;
        }

        double weight = 1.0;
        if (weightedMode && sensitivity > 0.0) {
            const double totalMass = species.totalCellMass[c];
            double alphaBar = 0.0;
            if (totalMass > 0.0) {
                for (int s = 0; s < species.speciesCount; ++s) {
                    const double ms = species.mass[s * species.numCells + c];
                    alphaBar += (ms / totalMass) * species.q6Strength[s];
                }
            }
            if (alphaBar > alphaEpsilon) {
                weight = (1.0 - sensitivity) +
                         sensitivity * species.q6Strength[speciesIndex] / alphaBar;
            } else if (fatalFallback) {
                atomicAdd(fallbackCounter, 1ull);
                continue;
            }
        }

        double ax = 0.0;
        double ay = 0.0;
        q6_force_acceleration_0493x4b(
            particles.x[i], particles.y[i], lx, ly, bodyAx, bodyAy,
            tgEnable, tgAmplitude, tgModeX, tgModeY, &ax, &ay);
        const double dvx = weight * dux[c];
        const double dvy = weight * duy[c];
        particles.vx[i] += ax * dt;
        particles.vy[i] += ay * dt;
        particles.vx[i] += dvx;
        particles.vy[i] += dvy;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        px += m * dvx;
        py += m * dvy;
    }
    shX[tid] = px;
    shY[tid] = py;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialPx[blockIdx.x] = shX[0];
        partialPy[blockIdx.x] = shY[0];
    }
}

__global__ void q6_count_zero_alpha_bar_0491c(CudaSpeciesCellDeviceView0490h species,
                                              double alphaEpsilon,
                                              unsigned long long* fallbackCounter) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < species.numCells; c += stride) {
        const double totalMass = species.totalCellMass[c];
        if (!(totalMass > 0.0)) {
            continue;
        }
        double alphaBar = 0.0;
        for (int s = 0; s < species.speciesCount; ++s) {
            const double ms = species.mass[s * species.numCells + c];
            alphaBar += (ms / totalMass) * species.q6Strength[s];
        }
        if (!(alphaBar > alphaEpsilon)) {
            atomicAdd(fallbackCounter, 1ull);
        }
    }
}

__global__ void q6_species_barycentric_residual_stats_0491c(
    CudaSpeciesCellDeviceView0490h species,
    const double* dux,
    const double* duy,
    double sensitivity,
    double alphaEpsilon,
    int weightedMode,
    double* partialX,
    double* partialY) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double maxX = 0.0;
    double maxY = 0.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < species.numCells; c += stride) {
        const double totalMass = species.totalCellMass[c];
        if (!(totalMass > 0.0)) {
            continue;
        }

        double alphaBar = 0.0;
        if (weightedMode && sensitivity > 0.0) {
            for (int s = 0; s < species.speciesCount; ++s) {
                const double ms = species.mass[s * species.numCells + c];
                alphaBar += (ms / totalMass) * species.q6Strength[s];
            }
        }
        const int useWeighted = weightedMode && sensitivity > 0.0 && alphaBar > alphaEpsilon;

        const double targetX = totalMass * dux[c];
        const double targetY = totalMass * duy[c];
        double residualX = -targetX;
        double residualY = -targetY;
        double scaleX = fabs(targetX);
        double scaleY = fabs(targetY);
        for (int s = 0; s < species.speciesCount; ++s) {
            const double weight = useWeighted
                ? ((1.0 - sensitivity) + sensitivity * species.q6Strength[s] / alphaBar)
                : 1.0;
            const double ms = species.mass[s * species.numCells + c];
            const double termX = ms * weight * dux[c];
            const double termY = ms * weight * duy[c];
            residualX += termX;
            residualY += termY;
            scaleX += fabs(termX);
            scaleY += fabs(termY);
        }
        const double absResidualX = fabs(residualX);
        const double absResidualY = fabs(residualY);
        const double scaledResidualX = absResidualX / fmax(1.0, scaleX);
        const double scaledResidualY = absResidualY / fmax(1.0, scaleY);
        maxX = fmax(maxX, fmax(absResidualX, absResidualY));
        maxY = fmax(maxY, fmax(scaledResidualX, scaledResidualY));
    }
    shX[tid] = maxX;
    shY[tid] = maxY;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] = fmax(shX[tid], shX[tid + offset]);
            shY[tid] = fmax(shY[tid], shY[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialX[blockIdx.x] = shX[0];
        partialY[blockIdx.x] = shY[0];
    }
}


__device__ bool q6_species_cell_active_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    int cell,
    double minOccupancyFraction) {
    if (speciesIndex < 0 || speciesIndex >= species.speciesCount ||
        cell < 0 || cell >= species.numCells) {
        return false;
    }
    const int k = speciesIndex * species.numCells + cell;
    return species.q6Strength[speciesIndex] > 0.0 &&
           species.mass[k] > 0.0 &&
           species.occupancyFraction[k] >= minOccupancyFraction;
}

__device__ bool q6_species_cell_active_free_surface_0493x5a(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    int cell,
    double minFillFraction) {
    if (speciesIndex < 0 || speciesIndex >= species.speciesCount ||
        cell < 0 || cell >= species.numCells) {
        return false;
    }
    const int k = speciesIndex * species.numCells + cell;
    const double ref = species.referenceCellMass[speciesIndex];
    const double fill = ref > 0.0 ? species.mass[k] / ref : 0.0;
    return species.q6Strength[speciesIndex] > 0.0 &&
           species.mass[k] > 0.0 && fill >= minFillFraction;
}

__device__ double q6_species_cell_velocity_component_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    int cell,
    int component) {
    const int k = speciesIndex * species.numCells + cell;
    const double m = species.mass[k];
    if (!(m > 0.0)) return 0.0;
    return component == 0 ? species.px[k] / m : species.py[k] / m;
}

__device__ double q6_species_face_velocity_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    const unsigned char* mask,
    int speciesIndex,
    int cellA,
    int cellB,
    int component) {
    const bool activeA = mask[cellA] != 0u;
    const bool activeB = mask[cellB] != 0u;
    if (!activeA && !activeB) return 0.0;
    const double ua = activeA
        ? q6_species_cell_velocity_component_0493w5(species, speciesIndex, cellA, component)
        : 0.0;
    const double ub = activeB
        ? q6_species_cell_velocity_component_0493w5(species, speciesIndex, cellB, component)
        : 0.0;
    if (activeA && activeB) return 0.5 * (ua + ub);
    return activeA ? ua : ub;
}

__global__ void q6_build_independent_mask_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    double minOccupancyFraction,
    int freeSurfaceMode0493x5a,
    unsigned char* mask,
    double* rhs,
    int n,
    unsigned long long* activeCounter) {
    unsigned long long activeLocal = 0ull;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const bool active = freeSurfaceMode0493x5a
            ? q6_species_cell_active_free_surface_0493x5a(
                species, speciesIndex, c, minOccupancyFraction)
            : q6_species_cell_active_0493w5(
                species, speciesIndex, c, minOccupancyFraction);
        mask[c] = active ? 1u : 0u;
        rhs[c] = 0.0;
        if (active) ++activeLocal;
    }
    if (activeLocal != 0ull) atomicAdd(activeCounter, activeLocal);
}

__global__ void q6_regularize_free_surface_mask_0493x5a(
    const unsigned char* rawMask,
    unsigned char* regularizedMask,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    unsigned long long* activeCounter) {
    unsigned long long activeLocal = 0ull;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        bool active = rawMask[c] != 0u;
        if (!active) {
            const int ix = c % nx;
            const int iy = c / nx;
            bool enclosed = true;
            int neighbourCount = 0;

            if (periodicX || ix > 0) {
                const int west = iy * nx +
                    (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1);
                enclosed = enclosed && rawMask[west] != 0u;
                ++neighbourCount;
            }
            if (periodicX || ix < nx - 1) {
                const int east = iy * nx +
                    (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
                enclosed = enclosed && rawMask[east] != 0u;
                ++neighbourCount;
            }
            if (periodicY || iy > 0) {
                const int south =
                    (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix;
                enclosed = enclosed && rawMask[south] != 0u;
                ++neighbourCount;
            }
            if (periodicY || iy < ny - 1) {
                const int north =
                    (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
                enclosed = enclosed && rawMask[north] != 0u;
                ++neighbourCount;
            }

            // Close only a one-cell cavity fully surrounded by the raw liquid
            // support.  Missing neighbours at a solid box wall do not create a
            // free surface, while an actual liquid-empty interface always has
            // at least one in-domain inactive neighbour and remains open.
            active = enclosed && neighbourCount >= 2;
        }
        regularizedMask[c] = active ? 1u : 0u;
        if (active) ++activeLocal;
    }
    if (activeLocal != 0ull) atomicAdd(activeCounter, activeLocal);
}

__global__ void q6_build_phase_gas_pressure_potential_0493x6a(
    CudaSpeciesCellDeviceView0490h species,
    double dt,
    double kBT,
    double projectedLiquidReferenceCellMass,
    double* gasPressurePotential) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < species.numCells; c += stride) {
        unsigned long long gasCount = 0ull;
        for (int s = 0; s < species.speciesCount; ++s) {
            if (species.phaseFamily[s] ==
                static_cast<unsigned char>(SpeciesPhaseFamily::Gas)) {
                gasCount += static_cast<unsigned long long>(
                    species.count[s * species.numCells + c]);
            }
        }
        // In 2D, p_g = N_g kBT / A and rho_l,ref = M_l,ref / A, hence
        // phi_g = dt * p_g / rho_l,ref = dt * N_g kBT / M_l,ref.
        gasPressurePotential[c] = projectedLiquidReferenceCellMass > 0.0
            ? dt * kBT * static_cast<double>(gasCount) /
                  projectedLiquidReferenceCellMass
            : 0.0;
    }
}

__global__ void q6_phase_interface_pressure_stats_0493x6a(
    const unsigned char* liquidMask,
    const double* gasPressurePotential,
    double* partialSum,
    double* partialSq,
    double* partialMax,
    unsigned long long* interfaceFaceCounter,
    int nx,
    int ny,
    int periodicX,
    int periodicY) {
    extern __shared__ double sh[];
    double* shSum = sh;
    double* shSq = sh + blockDim.x;
    double* shMax = sh + 2 * blockDim.x;
    const int tid = threadIdx.x;
    double sum = 0.0;
    double sq = 0.0;
    double mx = 0.0;
    unsigned long long faces = 0ull;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (liquidMask[c] == 0u) continue;
        const int ix = c % nx;
        const int iy = c / nx;
        int neighbours[4];
        int count = 0;
        if (periodicX || ix > 0) {
            neighbours[count++] = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1);
        }
        if (periodicX || ix < nx - 1) {
            neighbours[count++] = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
        }
        if (periodicY || iy > 0) {
            neighbours[count++] =
                (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix;
        }
        if (periodicY || iy < ny - 1) {
            neighbours[count++] =
                (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
        }
        for (int k = 0; k < count; ++k) {
            const int nb = neighbours[k];
            if (liquidMask[nb] != 0u) continue;
            // Current free-surface geometry places the interface at the
            // midpoint of the active/inactive cell-centre segment.  Use the
            // matching centred interpolation of the gas pressure potential.
            const double phi = 0.5 *
                (gasPressurePotential[c] + gasPressurePotential[nb]);
            sum += phi;
            sq += phi * phi;
            mx = fmax(mx, fabs(phi));
            ++faces;
        }
    }
    shSum[tid] = sum;
    shSq[tid] = sq;
    shMax[tid] = mx;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shSum[tid] += shSum[tid + offset];
            shSq[tid] += shSq[tid + offset];
            shMax[tid] = fmax(shMax[tid], shMax[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSum[blockIdx.x] = shSum[0];
        partialSq[blockIdx.x] = shSq[0];
        partialMax[blockIdx.x] = shMax[0];
    }
    // `faces` is a per-thread accumulator.  Do not add it only from tid==0:
    // that would count the faces visited by thread 0 of each block and discard
    // those visited by every other thread.  One atomic add per participating
    // thread is negligible here because 0493x6a is diagnostic-only.
    if (faces != 0ull) atomicAdd(interfaceFaceCounter, faces);
}

enum class PhaseSelectorKind0493x9g : int {
    Family = 0,
    Type = 1,
    Vacuum = 2,
    Wall = 3
};

struct ResolvedPhaseSelector0493x9g {
    PhaseSelectorKind0493x9g kind = PhaseSelectorKind0493x9g::Family;
    std::uint32_t value = 0u;
    int matchedSpecies = 0;
    double referenceCellMass = 0.0;
    bool allMatchedGas = false;
    std::string canonical;
};

std::string lower_trim_phase_selector_0493x9g(std::string v) {
    auto notSpace = [](unsigned char c) { return !std::isspace(c); };
    v.erase(v.begin(), std::find_if(v.begin(), v.end(), notSpace));
    v.erase(std::find_if(v.rbegin(), v.rend(), notSpace).base(), v.end());
    std::transform(v.begin(), v.end(), v.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return v;
}

ResolvedPhaseSelector0493x9g resolve_phase_selector_0493x9g(
    const std::string& input,
    const std::vector<SpeciesDefinition>& definitions) {
    ResolvedPhaseSelector0493x9g out{};
    std::string v = lower_trim_phase_selector_0493x9g(input);
    if (v == "liquid" || v == "gas" || v == "dispersed" || v == "unspecified") {
        v = "family:" + v;
    }
    if (v == "none") v = "vacuum";
    out.canonical = v;
    if (v == "vacuum") {
        out.kind = PhaseSelectorKind0493x9g::Vacuum;
        return out;
    }
    if (v == "wall") {
        out.kind = PhaseSelectorKind0493x9g::Wall;
        return out;
    }
    const std::string familyPrefix = "family:";
    if (v.rfind(familyPrefix, 0) == 0) {
        const std::string f = v.substr(familyPrefix.size());
        out.kind = PhaseSelectorKind0493x9g::Family;
        if (f == "unspecified") out.value = static_cast<std::uint32_t>(SpeciesPhaseFamily::Unspecified);
        else if (f == "gas") out.value = static_cast<std::uint32_t>(SpeciesPhaseFamily::Gas);
        else if (f == "liquid") out.value = static_cast<std::uint32_t>(SpeciesPhaseFamily::Liquid);
        else if (f == "dispersed") out.value = static_cast<std::uint32_t>(SpeciesPhaseFamily::Dispersed);
        else throw std::runtime_error("0493x9g invalid family selector: " + input);
    } else {
        const std::string typePrefix = "type:";
        if (v.rfind(typePrefix, 0) != 0) {
            throw std::runtime_error("0493x9g invalid phase selector: " + input);
        }
        out.kind = PhaseSelectorKind0493x9g::Type;
        out.value = static_cast<std::uint32_t>(std::stoull(v.substr(typePrefix.size())));
    }
    out.allMatchedGas = true;
    for (const SpeciesDefinition& d : definitions) {
        const bool match = out.kind == PhaseSelectorKind0493x9g::Family
            ? static_cast<std::uint32_t>(d.phaseFamily) == out.value
            : d.type == out.value;
        if (!match) continue;
        ++out.matchedSpecies;
        out.referenceCellMass += d.referenceCellMassDeclared;
        out.allMatchedGas = out.allMatchedGas && d.phaseFamily == SpeciesPhaseFamily::Gas;
    }
    if (out.matchedSpecies == 0) out.allMatchedGas = false;
    return out;
}

bool phase_selector_matches_definition_0493x9g(
    const ResolvedPhaseSelector0493x9g& selector,
    const SpeciesDefinition& d) {
    if (selector.kind == PhaseSelectorKind0493x9g::Family) {
        return static_cast<std::uint32_t>(d.phaseFamily) == selector.value;
    }
    if (selector.kind == PhaseSelectorKind0493x9g::Type) {
        return d.type == selector.value;
    }
    return false;
}

__device__ __forceinline__ bool q6_phase_selector_matches_0493x9g(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    int selectorKind,
    unsigned int selectorValue) {
    if (speciesIndex < 0 || speciesIndex >= species.speciesCount) return false;
    if (selectorKind == static_cast<int>(PhaseSelectorKind0493x9g::Family)) {
        return species.phaseFamily != nullptr &&
               species.phaseFamily[speciesIndex] == static_cast<unsigned char>(selectorValue);
    }
    if (selectorKind == static_cast<int>(PhaseSelectorKind0493x9g::Type)) {
        return species.speciesTypes != nullptr &&
               species.speciesTypes[speciesIndex] == selectorValue;
    }
    return false;
}

__device__ double q6_phase_fill_selector_0493x9g(
    CudaSpeciesCellDeviceView0490h species,
    int cell,
    int selectorKind,
    unsigned int selectorValue,
    double phaseReferenceCellMass) {
    if (cell < 0 || cell >= species.numCells || !(phaseReferenceCellMass > 0.0)) {
        return 0.0;
    }
    double mass = 0.0;
    for (int s = 0; s < species.speciesCount; ++s) {
        if (q6_phase_selector_matches_0493x9g(
                species, s, selectorKind, selectorValue)) {
            mass += species.mass[s * species.numCells + cell];
        }
    }
    return mass / phaseReferenceCellMass;
}

// Historical x6b helper retained for old diagnostics.  Production x9g
// geometry uses q6_phase_fill_selector_0493x9g instead.
__device__ double q6_phase_fill_0493x6b(
    CudaSpeciesCellDeviceView0490h species,
    int cell,
    unsigned char phaseFamily,
    double phaseReferenceCellMass) {
    return q6_phase_fill_selector_0493x9g(
        species, cell, static_cast<int>(PhaseSelectorKind0493x9g::Family),
        static_cast<unsigned int>(phaseFamily), phaseReferenceCellMass);
}

void append_phase_pair_audit_0493x9g(
    const SimulationParams& params,
    int step,
    double time,
    int projectedSpeciesIndex,
    std::uint32_t projectedType,
    const ResolvedPhaseSelector0493x9g& phaseA,
    const ResolvedPhaseSelector0493x9g& phaseB,
    bool phaseInterfaceEnabled,
    bool phaseBPressureEnabled) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_pair_0493x9g.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9g failed to open phase-pair audit CSV: " + path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,phaseASelector,"
               "phaseAKind,phaseAValue,phaseASpeciesCount,phaseAReferenceCellMass,"
               "phaseBSelector,phaseBKind,phaseBValue,phaseBSpeciesCount,"
               "phaseBReferenceCellMass,phaseBAllGas,phaseInterfaceEnabled,"
               "phaseBPressureEnabled,surfaceTensionSigma,contract\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << projectedSpeciesIndex << ',' << projectedType << ','
        << phaseA.canonical << ',' << static_cast<int>(phaseA.kind) << ',' << phaseA.value << ','
        << phaseA.matchedSpecies << ',' << phaseA.referenceCellMass << ','
        << phaseB.canonical << ',' << static_cast<int>(phaseB.kind) << ',' << phaseB.value << ','
        << phaseB.matchedSpecies << ',' << phaseB.referenceCellMass << ','
        << (phaseB.allMatchedGas ? 1 : 0) << ',' << (phaseInterfaceEnabled ? 1 : 0) << ','
        << (phaseBPressureEnabled ? 1 : 0) << ',' << params.surfaceTensionSigma << ','
        << "A=alphaHigh/projectedSide;B=alphaLow/exteriorSide;"
           "legacyDefaults=family:liquid/family:gas;"
           "wall=geometryProviderOnly/noPressureDirichlet" << '\n';
}

struct WallGeometryAudit0493x9h {
    int projectedSpeciesIndex = -1;
    std::uint32_t projectedType = 0u;
    int domainWallLeft = 0;
    int domainWallRight = 0;
    int domainWallBottom = 0;
    int domainWallTop = 0;
    int chiProviderEnabled = 0;
    int chiCollisionWallVpEnabled = 0;
    std::uint64_t numCells = 0u;
    std::uint64_t solidCells = 0u;
    std::uint64_t mixedCells = 0u;
    std::uint64_t wallBandCells = 0u;
    std::uint64_t normalValidCells = 0u;
    double solidFractionMean = 0.0;
    double normalValidFraction = 0.0;
    double normalUnitErrorRms = 0.0;
};

void append_wall_geometry_audit_0493x9h(
    const SimulationParams& params,
    int step,
    double time,
    const WallGeometryAudit0493x9h& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_wall_geometry_0493x9h.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9h failed to open wall-geometry audit CSV: " + path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,"
               "domainWallLeft,domainWallRight,domainWallBottom,domainWallTop,"
               "chiProviderEnabled,chiCollisionWallVpEnabled,numCells,solidCells,"
               "mixedCells,wallBandCells,normalValidCells,solidFractionMean,"
               "normalValidFraction,normalUnitErrorRms,contract\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ',' << a.projectedType << ','
        << a.domainWallLeft << ',' << a.domainWallRight << ','
        << a.domainWallBottom << ',' << a.domainWallTop << ','
        << a.chiProviderEnabled << ',' << a.chiCollisionWallVpEnabled << ','
        << a.numCells << ',' << a.solidCells << ',' << a.mixedCells << ','
        << a.wallBandCells << ',' << a.normalValidCells << ','
        << a.solidFractionMean << ',' << a.normalValidFraction << ','
        << a.normalUnitErrorRms << ','
        << "wall=union(domainWallGhostFaces,chiWallVp);chiConvention=1fluid/0solid;"
           "solidFraction=1-chi;normal=fluidToSolid;passiveGeometryOnly" << '\n';
}

struct ContactAngleAudit0493x9i {
    int projectedSpeciesIndex = -1;
    std::uint32_t projectedType = 0u;
    double prescribedAngleDegrees = -1.0;
    double targetNormalWallDot = 0.0;
    std::uint64_t candidateCells = 0u;
    std::uint64_t correctedCells = 0u;
    std::uint64_t curvatureCells = 0u;
    double rawAngleMean = 0.0;
    double correctedAngleMean = 0.0;
    double correctedAngleErrorRms = 0.0;
    double correctedDotErrorRms = 0.0;
    double contactCurvatureMean = 0.0;
    double contactCurvatureRms = 0.0;
    double contactCurvatureStd = 0.0;
};

void append_contact_angle_audit_0493x9i(
    const SimulationParams& params,
    int step,
    double time,
    const ContactAngleAudit0493x9i& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_contact_angle_0493x9i.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9i failed to open contact-angle audit CSV: " + path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,prescribedAngleDegrees,"
               "targetNormalWallDot,candidateCells,correctedCells,curvatureCells,"
               "rawAngleMean,correctedAngleMean,correctedAngleErrorRms,"
               "correctedDotErrorRms,contactCurvatureMean,contactCurvatureRms,"
               "contactCurvatureStd,contract\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ',' << a.projectedType << ','
        << a.prescribedAngleDegrees << ',' << a.targetNormalWallDot << ','
        << a.candidateCells << ',' << a.correctedCells << ',' << a.curvatureCells << ','
        << a.rawAngleMean << ',' << a.correctedAngleMean << ','
        << a.correctedAngleErrorRms << ',' << a.correctedDotErrorRms << ','
        << a.contactCurvatureMean << ',' << a.contactCurvatureRms << ','
        << a.contactCurvatureStd << ','
        << "thetaMeasuredThroughA;nAB=AtoB;nWall=fluidToSolid;dot=-cos(theta);"
           "normalOnly/p3;physicalAlphaUnchanged" << '\n';
}

// 0493x9j audits the ghost-alpha closure separately from the x9i hard-normal
// experiment.  The scalar schema is intentionally identical so the two
// closures can be compared without changing the physical x6c interface.
void append_contact_angle_ghost_audit_0493x9j(
    const SimulationParams& params,
    int step,
    double time,
    const ContactAngleAudit0493x9i& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_contact_angle_ghost_0493x9j.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9j failed to open ghost-alpha contact-angle audit CSV: " + path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,prescribedAngleDegrees,"
               "targetNormalWallDot,candidateCells,correctedCells,curvatureCells,"
               "rawAngleMean,correctedAngleMean,correctedAngleErrorRms,"
               "correctedDotErrorRms,contactCurvatureMean,contactCurvatureRms,"
               "contactCurvatureStd,contract\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ',' << a.projectedType << ','
        << a.prescribedAngleDegrees << ',' << a.targetNormalWallDot << ','
        << a.candidateCells << ',' << a.correctedCells << ',' << a.curvatureCells << ','
        << a.rawAngleMean << ',' << a.correctedAngleMean << ','
        << a.correctedAngleErrorRms << ',' << a.correctedDotErrorRms << ','
        << a.contactCurvatureMean << ',' << a.contactCurvatureRms << ','
        << a.contactCurvatureStd << ','
        << "thetaMeasuredThroughA;nAB=AtoB;nWall=fluidToSolid;dot=-cos(theta);"
           "ghostAlphaDuringP3AndScharr;physicalAlphaUnchanged;domainWallsOnly_x9j" << '\n';
}


// 0493x9k: sheared-mirror ghost-alpha closure.  The scalar schema matches
// x9i/x9j so existing contact-angle diagnostics remain directly comparable.
void append_contact_angle_mirror_audit_0493x9k(
    const SimulationParams& params,
    int step,
    double time,
    const ContactAngleAudit0493x9i& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_contact_angle_mirror_0493x9k.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9k failed to open sheared-mirror contact-angle audit CSV: " + path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,prescribedAngleDegrees,"
               "targetNormalWallDot,candidateCells,correctedCells,curvatureCells,"
               "rawAngleMean,correctedAngleMean,correctedAngleErrorRms,"
               "correctedDotErrorRms,contactCurvatureMean,contactCurvatureRms,"
               "contactCurvatureStd,contract\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ',' << a.projectedType << ','
        << a.prescribedAngleDegrees << ',' << a.targetNormalWallDot << ','
        << a.candidateCells << ',' << a.correctedCells << ',' << a.curvatureCells << ','
        << a.rawAngleMean << ',' << a.correctedAngleMean << ','
        << a.correctedAngleErrorRms << ',' << a.correctedDotErrorRms << ','
        << a.contactCurvatureMean << ',' << a.contactCurvatureRms << ','
        << a.contactCurvatureStd << ','
        << "thetaMeasuredThroughA;nAB=AtoB;nWall=fluidToSolid;dot=-cos(theta);"
           "shearedMirrorGhostAlphaDuringP3AndScharr;physicalAlphaUnchanged;"
           "0<theta<180;domainWallsOnly_x9k" << '\n';
}


// 0493x9l: wall-face normal closure audit.  The prescribed Young angle lives
// at the physical wall face; cell-centred and ghost normals are reconstructed
// symmetrically in angle space around that face value before div(n).
void append_contact_angle_wallface_audit_0493x9l(
    const SimulationParams& params,
    int step,
    double time,
    const ContactAngleAudit0493x9i& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_contact_angle_wallface_0493x9l.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9l failed to open wall-face contact-angle audit CSV: " + path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,prescribedAngleDegrees,"
               "targetNormalWallDot,candidateCells,correctedCells,curvatureCells,"
               "rawAngleMean,correctedAngleMean,correctedAngleErrorRms,"
               "correctedDotErrorRms,contactCurvatureMean,contactCurvatureRms,"
               "contactCurvatureStd,contract\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ',' << a.projectedType << ','
        << a.prescribedAngleDegrees << ',' << a.targetNormalWallDot << ','
        << a.candidateCells << ',' << a.correctedCells << ',' << a.curvatureCells << ','
        << a.rawAngleMean << ',' << a.correctedAngleMean << ','
        << a.correctedAngleErrorRms << ',' << a.correctedDotErrorRms << ','
        << a.contactCurvatureMean << ',' << a.contactCurvatureRms << ','
        << a.contactCurvatureStd << ','
        << "thetaMeasuredThroughA;nAB=AtoB;nWall=fluidToSolid;dot=-cos(theta);"
           "wallFaceAngleClosure;cellAndGhostNormalsInterpolatedInAngleSpace;"
           "physicalAlphaAndP3AlphaUnchanged;0<theta<180;domainWallsOnly_x9l" << '\n';
}


// 0493x9m: off-support secant-curvature contact closure.  The prescribed
// Young normal lives at the wall face; the second normal is sampled on the
// actual A/B interface in the first layer whose p3+Scharr support is entirely
// physical (j=4, centre 4.5h).  Their normal rotation and geometric chord give
// a direct local curvature estimate without modifying alphaK or near-wall
// normals.  The scalar schema matches x9i-x9l for direct comparison.
void append_contact_angle_offsupport_audit_0493x9m(
    const SimulationParams& params,
    int step,
    double time,
    const ContactAngleAudit0493x9i& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_contact_angle_offsupport_0493x9m.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9m failed to open off-support contact-angle audit CSV: " + path.string());
    }
    if (header) {
        out << "step,time,projectedSpeciesIndex,projectedType,prescribedAngleDegrees,"
               "targetNormalWallDot,candidateCells,correctedCells,curvatureCells,"
               "rawAngleMean,correctedAngleMean,correctedAngleErrorRms,"
               "correctedDotErrorRms,contactCurvatureMean,contactCurvatureRms,"
               "contactCurvatureStd,contract\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ',' << a.projectedSpeciesIndex << ',' << a.projectedType << ','
        << a.prescribedAngleDegrees << ',' << a.targetNormalWallDot << ','
        << a.candidateCells << ',' << a.correctedCells << ',' << a.curvatureCells << ','
        << a.rawAngleMean << ',' << a.correctedAngleMean << ','
        << a.correctedAngleErrorRms << ',' << a.correctedDotErrorRms << ','
        << a.contactCurvatureMean << ',' << a.contactCurvatureRms << ','
        << a.contactCurvatureStd << ','
        << "thetaMeasuredThroughA;nAB=AtoB;nWall=fluidToSolid;dot=-cos(theta);"
           "wallFaceYoungNormal;offSupportSecantCurvature;anchorLayer=4;anchorCenter=4.5h;"
           "p3Radius=3;normalScharrRadius=1;physicalAlphaAndP3NormalsUnchanged;"
           "0<theta<180;domainWallsOnly_x9m" << '\n';
}


__global__ void q6_phase_interface_geometry_stats_0493x6b(
    CudaSpeciesCellDeviceView0490h species,
    const unsigned char* liquidMask,
    double liquidPhaseReferenceCellMass,
    double supportIsoFill,
    PhaseGeometryAccumulator0493x6b* accum,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY) {
    const unsigned char liquidFamily =
        static_cast<unsigned char>(SpeciesPhaseFamily::Liquid);
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;

    unsigned long long phaseActiveLocal = 0ull;
    unsigned long long mismatchLocal = 0ull;
    unsigned long long facesLocal = 0ull;
    unsigned long long supportValidLocal = 0ull;
    unsigned long long nearCellLocal = 0ull;
    unsigned long long nearExteriorLocal = 0ull;
    unsigned long long halfBracketLocal = 0ull;
    unsigned long long normalValidLocal = 0ull;
    unsigned long long normalOutwardLocal = 0ull;
    double insideSumLocal = 0.0;
    double outsideSumLocal = 0.0;
    double thetaSumLocal = 0.0;
    double thetaSqLocal = 0.0;
    double thetaMidSqLocal = 0.0;
    double halfThetaSumLocal = 0.0;
    double halfThetaSqLocal = 0.0;
    double normalDotSumLocal = 0.0;

    for (int c = idx; c < n; c += stride) {
        const double fillC = q6_phase_fill_0493x6b(
            species, c, liquidFamily, liquidPhaseReferenceCellMass);
        const bool phaseActive = fillC >= supportIsoFill;
        const bool maskActive = liquidMask[c] != 0u;
        if (phaseActive) ++phaseActiveLocal;
        if (phaseActive != maskActive) ++mismatchLocal;
        if (!maskActive) continue;

        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasWest = periodicX || ix > 0;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasSouth = periodicY || iy > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;

        const bool interfaceCell =
            (hasWest && liquidMask[west] == 0u) ||
            (hasEast && liquidMask[east] == 0u) ||
            (hasSouth && liquidMask[south] == 0u) ||
            (hasNorth && liquidMask[north] == 0u);
        if (!interfaceCell) continue;

        // The raw normalized phase mass is deliberately not clamped to [0,1].
        // Values above unity are useful diagnostics of local compression.  The
        // 0.5 isosurface is therefore a geometric proxy, not yet a VOF field.
        const double fillW = hasWest
            ? q6_phase_fill_0493x6b(species, west, liquidFamily,
                                    liquidPhaseReferenceCellMass)
            : fillC;
        const double fillE = hasEast
            ? q6_phase_fill_0493x6b(species, east, liquidFamily,
                                    liquidPhaseReferenceCellMass)
            : fillC;
        const double fillS = hasSouth
            ? q6_phase_fill_0493x6b(species, south, liquidFamily,
                                    liquidPhaseReferenceCellMass)
            : fillC;
        const double fillN = hasNorth
            ? q6_phase_fill_0493x6b(species, north, liquidFamily,
                                    liquidPhaseReferenceCellMass)
            : fillC;
        const double gradX = hasWest && hasEast
            ? (fillE - fillW) / (2.0 * dx)
            : (hasEast ? (fillE - fillC) / dx
                       : (hasWest ? (fillC - fillW) / dx : 0.0));
        const double gradY = hasSouth && hasNorth
            ? (fillN - fillS) / (2.0 * dy)
            : (hasNorth ? (fillN - fillC) / dy
                        : (hasSouth ? (fillC - fillS) / dy : 0.0));
        const double gradNorm = sqrt(gradX * gradX + gradY * gradY);
        const bool normalValid = gradNorm > 1.0e-14;
        const double nxOut = normalValid ? -gradX / gradNorm : 0.0;
        const double nyOut = normalValid ? -gradY / gradNorm : 0.0;

        int neighbours[4];
        double faceNx[4];
        double faceNy[4];
        int count = 0;
        if (hasWest) {
            neighbours[count] = west; faceNx[count] = -1.0; faceNy[count] = 0.0; ++count;
        }
        if (hasEast) {
            neighbours[count] = east; faceNx[count] = 1.0; faceNy[count] = 0.0; ++count;
        }
        if (hasSouth) {
            neighbours[count] = south; faceNx[count] = 0.0; faceNy[count] = -1.0; ++count;
        }
        if (hasNorth) {
            neighbours[count] = north; faceNx[count] = 0.0; faceNy[count] = 1.0; ++count;
        }

        for (int k = 0; k < count; ++k) {
            const int nb = neighbours[k];
            if (liquidMask[nb] != 0u) continue;
            const double fillNb = q6_phase_fill_0493x6b(
                species, nb, liquidFamily, liquidPhaseReferenceCellMass);
            ++facesLocal;
            insideSumLocal += fillC;
            outsideSumLocal += fillNb;

            const double denom = fillC - fillNb;
            if (denom > 1.0e-14 &&
                fillC >= supportIsoFill && fillNb < supportIsoFill) {
                const double theta = (fillC - supportIsoFill) / denom;
                if (theta >= 0.0 && theta <= 1.0) {
                    ++supportValidLocal;
                    thetaSumLocal += theta;
                    thetaSqLocal += theta * theta;
                    const double dmid = theta - 0.5;
                    thetaMidSqLocal += dmid * dmid;
                    if (theta < 0.1) ++nearCellLocal;
                    if (theta > 0.9) ++nearExteriorLocal;
                }
            }

            if (denom > 1.0e-14 && fillC >= 0.5 && fillNb < 0.5) {
                const double thetaHalf = (fillC - 0.5) / denom;
                if (thetaHalf >= 0.0 && thetaHalf <= 1.0) {
                    ++halfBracketLocal;
                    halfThetaSumLocal += thetaHalf;
                    halfThetaSqLocal += thetaHalf * thetaHalf;
                }
            }

            if (normalValid) {
                const double alignment = nxOut * faceNx[k] + nyOut * faceNy[k];
                ++normalValidLocal;
                normalDotSumLocal += alignment;
                if (alignment > 0.0) ++normalOutwardLocal;
            }
        }
    }

    if (phaseActiveLocal) atomicAdd(&accum->phaseFillActiveCells, phaseActiveLocal);
    if (mismatchLocal) atomicAdd(&accum->maskPhaseMismatchCells, mismatchLocal);
    if (facesLocal) atomicAdd(&accum->interfaceFaces, facesLocal);
    if (supportValidLocal) atomicAdd(&accum->supportThetaValidFaces, supportValidLocal);
    if (nearCellLocal) atomicAdd(&accum->supportThetaNearCellFaces, nearCellLocal);
    if (nearExteriorLocal) atomicAdd(&accum->supportThetaNearExteriorFaces, nearExteriorLocal);
    if (halfBracketLocal) atomicAdd(&accum->halfIsoBracketFaces, halfBracketLocal);
    if (normalValidLocal) atomicAdd(&accum->normalValidFaces, normalValidLocal);
    if (normalOutwardLocal) atomicAdd(&accum->normalOutwardFaces, normalOutwardLocal);
    if (insideSumLocal != 0.0) atomic_add_double_0400(&accum->insideFillSum, insideSumLocal);
    if (outsideSumLocal != 0.0) atomic_add_double_0400(&accum->outsideFillSum, outsideSumLocal);
    if (thetaSumLocal != 0.0) atomic_add_double_0400(&accum->supportThetaSum, thetaSumLocal);
    if (thetaSqLocal != 0.0) atomic_add_double_0400(&accum->supportThetaSqSum, thetaSqLocal);
    if (thetaMidSqLocal != 0.0) atomic_add_double_0400(&accum->supportThetaMidSqSum, thetaMidSqLocal);
    if (halfThetaSumLocal != 0.0) atomic_add_double_0400(&accum->halfIsoThetaSum, halfThetaSumLocal);
    if (halfThetaSqLocal != 0.0) atomic_add_double_0400(&accum->halfIsoThetaSqSum, halfThetaSqLocal);
    if (normalDotSumLocal != 0.0) atomic_add_double_0400(&accum->normalFaceAlignmentSum, normalDotSumLocal);
}

// 0493x9h passive solid-geometry provider.  The resident scalar is a solid
// fraction S in [0,1].  An optional Darcy field uses the repository convention
// chi=1 fluid / chi=0 solid, hence S=1-chi.  Static domain walls are represented
// as S=1 ghost samples outside the computational box rather than by contaminating
// the first fluid cell.  This keeps the geometry independent of the kinetic wall
// mechanism (specular/solid/bounceback) and of wallVP particle bookkeeping.
__global__ void q6_build_wall_fraction_0493x9h(
    const float* chi,
    int useChi,
    double* solidFraction,
    int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        double s = 0.0;
        if (useChi && chi != nullptr) {
            const double ch = fmin(1.0, fmax(0.0, static_cast<double>(chi[c])));
            s = 1.0 - ch;
        }
        solidFraction[c] = s;
    }
}

__device__ __forceinline__ double q6_wall_fraction_sample_0493x9h(
    const double* solidFraction,
    int ix,
    int iy,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    int wallLeft,
    int wallRight,
    int wallBottom,
    int wallTop) {
    if (periodicX) ix = wrap_cell_index_0400(ix, nx);
    else if (ix < 0) return wallLeft ? 1.0 : 0.0;
    else if (ix >= nx) return wallRight ? 1.0 : 0.0;
    if (periodicY) iy = wrap_cell_index_0400(iy, ny);
    else if (iy < 0) return wallBottom ? 1.0 : 0.0;
    else if (iy >= ny) return wallTop ? 1.0 : 0.0;
    return solidFraction[iy * nx + ix];
}

__global__ void q6_build_wall_normals_0493x9h(
    const double* solidFraction,
    double* normalX,
    double* normalY,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    int wallLeft,
    int wallRight,
    int wallBottom,
    int wallTop) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
#define WALLSAMPLE(DX,DY) q6_wall_fraction_sample_0493x9h( \
            solidFraction, ix + (DX), iy + (DY), nx, ny, periodicX, periodicY, \
            wallLeft, wallRight, wallBottom, wallTop)
        const double nw = WALLSAMPLE(-1, +1);
        const double nn = WALLSAMPLE( 0, +1);
        const double ne = WALLSAMPLE(+1, +1);
        const double ww = WALLSAMPLE(-1,  0);
        const double ee = WALLSAMPLE(+1,  0);
        const double sw = WALLSAMPLE(-1, -1);
        const double ss = WALLSAMPLE( 0, -1);
        const double se = WALLSAMPLE(+1, -1);
#undef WALLSAMPLE
        // grad(S) points from fluid toward solid because S increases into B.
        const double gx = (3.0 * (ne - nw) + 10.0 * (ee - ww) +
                           3.0 * (se - sw)) / (32.0 * dx);
        const double gy = (3.0 * (nw - sw) + 10.0 * (nn - ss) +
                           3.0 * (ne - se)) / (32.0 * dy);
        const double g = sqrt(gx * gx + gy * gy);
        if (g * fmin(dx, dy) > 1.0e-12) {
            normalX[c] = gx / g;
            normalY[c] = gy / g;
        } else {
            normalX[c] = 0.0;
            normalY[c] = 0.0;
        }
    }
}

__global__ void q6_wall_geometry_audit_0493x9h(
    const double* solidFraction,
    const double* normalX,
    const double* normalY,
    WallGeometryAccumulator0493x9h* accum,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    int wallLeft,
    int wallRight,
    int wallBottom,
    int wallTop) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    unsigned long long solidLocal = 0ull;
    unsigned long long mixedLocal = 0ull;
    unsigned long long bandLocal = 0ull;
    unsigned long long normalLocal = 0ull;
    double solidSumLocal = 0.0;
    double unitErrSqLocal = 0.0;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const double sc = fmin(1.0, fmax(0.0, solidFraction[c]));
        solidSumLocal += sc;
        if (sc >= 0.5) ++solidLocal;
        if (sc > 1.0e-12 && sc < 1.0 - 1.0e-12) ++mixedLocal;
        double sMin = sc;
        double sMax = sc;
        const double sW = q6_wall_fraction_sample_0493x9h(
            solidFraction, ix - 1, iy, nx, ny, periodicX, periodicY,
            wallLeft, wallRight, wallBottom, wallTop);
        const double sE = q6_wall_fraction_sample_0493x9h(
            solidFraction, ix + 1, iy, nx, ny, periodicX, periodicY,
            wallLeft, wallRight, wallBottom, wallTop);
        const double sS = q6_wall_fraction_sample_0493x9h(
            solidFraction, ix, iy - 1, nx, ny, periodicX, periodicY,
            wallLeft, wallRight, wallBottom, wallTop);
        const double sN = q6_wall_fraction_sample_0493x9h(
            solidFraction, ix, iy + 1, nx, ny, periodicX, periodicY,
            wallLeft, wallRight, wallBottom, wallTop);
        const double sNW = q6_wall_fraction_sample_0493x9h(
            solidFraction, ix - 1, iy + 1, nx, ny, periodicX, periodicY,
            wallLeft, wallRight, wallBottom, wallTop);
        const double sNE = q6_wall_fraction_sample_0493x9h(
            solidFraction, ix + 1, iy + 1, nx, ny, periodicX, periodicY,
            wallLeft, wallRight, wallBottom, wallTop);
        const double sSW = q6_wall_fraction_sample_0493x9h(
            solidFraction, ix - 1, iy - 1, nx, ny, periodicX, periodicY,
            wallLeft, wallRight, wallBottom, wallTop);
        const double sSE = q6_wall_fraction_sample_0493x9h(
            solidFraction, ix + 1, iy - 1, nx, ny, periodicX, periodicY,
            wallLeft, wallRight, wallBottom, wallTop);
        sMin = fmin(sMin, fmin(fmin(fmin(sW, sE), fmin(sS, sN)),
                                  fmin(fmin(sNW, sNE), fmin(sSW, sSE))));
        sMax = fmax(sMax, fmax(fmax(fmax(sW, sE), fmax(sS, sN)),
                                  fmax(fmax(sNW, sNE), fmax(sSW, sSE))));
        if (sMax - sMin > 1.0e-12) ++bandLocal;
        const double norm = sqrt(normalX[c] * normalX[c] + normalY[c] * normalY[c]);
        if (norm > 0.25) {
            ++normalLocal;
            const double e = norm - 1.0;
            unitErrSqLocal += e * e;
        }
    }
    if (solidLocal) atomicAdd(&accum->solidCells, solidLocal);
    if (mixedLocal) atomicAdd(&accum->mixedCells, mixedLocal);
    if (bandLocal) atomicAdd(&accum->wallBandCells, bandLocal);
    if (normalLocal) atomicAdd(&accum->normalValidCells, normalLocal);
    if (solidSumLocal != 0.0) atomic_add_double_0400(&accum->solidFractionSum, solidSumLocal);
    if (unitErrSqLocal != 0.0) atomic_add_double_0400(&accum->normalUnitErrorSqSum, unitErrSqLocal);
}

// 0493x9i prescribed contact angle.  The physical x6c alpha field is never
// changed.  Only the curvature-only p3 normal is replaced in cells that are
// simultaneously in the x9h wall-normal band and in a 3x3 alpha=0.5 interface
// neighbourhood.  theta is measured through phase A.  Since nAB points A->B
// while nWall points fluid->solid, Young geometry is nAB.nWall=-cos(theta).
__device__ __forceinline__ int q6_contact_index_0493x9i(
    int ix, int iy, int nx, int ny, int periodicX, int periodicY) {
    if (periodicX) ix = wrap_cell_index_0400(ix, nx);
    else ix = max(0, min(nx - 1, ix));
    if (periodicY) iy = wrap_cell_index_0400(iy, ny);
    else iy = max(0, min(ny - 1, iy));
    return iy * nx + ix;
}

__device__ __forceinline__ bool q6_contact_interface_band_0493x9i(
    const double* alpha,
    int ix,
    int iy,
    int nx,
    int ny,
    int periodicX,
    int periodicY) {
    double amin = 1.0;
    double amax = 0.0;
    for (int oy = -1; oy <= 1; ++oy) {
        for (int ox = -1; ox <= 1; ++ox) {
            const int q = q6_contact_index_0493x9i(
                ix + ox, iy + oy, nx, ny, periodicX, periodicY);
            const double a = fmin(1.0, fmax(0.0, alpha[q]));
            amin = fmin(amin, a);
            amax = fmax(amax, a);
        }
    }
    return amin < 0.5 && amax >= 0.5;
}

// 0493x9j ghost-alpha contact-angle closure for static domain walls.  The
    // physical x6c alpha and its alpha=0.5 interface remain untouched.  Only the
    // curvature-support field samples virtual alpha values behind wall faces.  The
    // ghost normal derivative follows |grad_t| cot(theta), which is the scalar-
    // field form of nAB.nWall=-cos(theta) for nAB=-grad(alpha)/|grad(alpha)|.
    __device__ __forceinline__ double q6_contact_alpha_inside_0493x9j(
        const double* alpha,
        int ix,
        int iy,
        int nx,
        int ny,
        int periodicX,
        int periodicY) {
        if (periodicX) ix = wrap_cell_index_0400(ix, nx);
        else ix = max(0, min(nx - 1, ix));
        if (periodicY) iy = wrap_cell_index_0400(iy, ny);
        else iy = max(0, min(ny - 1, iy));
        return alpha[iy * nx + ix];
    }

    __device__ __forceinline__ double q6_contact_tangent_grad_x_0493x9j(
        const double* alpha, int ix, int iy, int nx, int ny,
        double dx, int periodicX, int periodicY) {
        if (periodicX || (ix > 0 && ix < nx - 1)) {
            const double aW = q6_contact_alpha_inside_0493x9j(
                alpha, ix - 1, iy, nx, ny, periodicX, periodicY);
            const double aE = q6_contact_alpha_inside_0493x9j(
                alpha, ix + 1, iy, nx, ny, periodicX, periodicY);
            return (aE - aW) / (2.0 * dx);
        }
        const double aC = q6_contact_alpha_inside_0493x9j(
            alpha, ix, iy, nx, ny, periodicX, periodicY);
        if (ix <= 0) {
            const double aE = q6_contact_alpha_inside_0493x9j(
                alpha, ix + 1, iy, nx, ny, periodicX, periodicY);
            return (aE - aC) / dx;
        }
        const double aW = q6_contact_alpha_inside_0493x9j(
            alpha, ix - 1, iy, nx, ny, periodicX, periodicY);
        return (aC - aW) / dx;
    }

    __device__ __forceinline__ double q6_contact_tangent_grad_y_0493x9j(
        const double* alpha, int ix, int iy, int nx, int ny,
        double dy, int periodicX, int periodicY) {
        if (periodicY || (iy > 0 && iy < ny - 1)) {
            const double aS = q6_contact_alpha_inside_0493x9j(
                alpha, ix, iy - 1, nx, ny, periodicX, periodicY);
            const double aN = q6_contact_alpha_inside_0493x9j(
                alpha, ix, iy + 1, nx, ny, periodicX, periodicY);
            return (aN - aS) / (2.0 * dy);
        }
        const double aC = q6_contact_alpha_inside_0493x9j(
            alpha, ix, iy, nx, ny, periodicX, periodicY);
        if (iy <= 0) {
            const double aN = q6_contact_alpha_inside_0493x9j(
                alpha, ix, iy + 1, nx, ny, periodicX, periodicY);
            return (aN - aC) / dy;
        }
        const double aS = q6_contact_alpha_inside_0493x9j(
            alpha, ix, iy - 1, nx, ny, periodicX, periodicY);
        return (aC - aS) / dy;
    }

    __device__ __forceinline__ double q6_contact_ghost_normal_gradient_0493x9j(
        double tangentialGradient,
        double rawNormalGradient,
        double contactAngleDegrees) {
        constexpr double pi = 3.141592653589793238462643383279502884;
        const double theta = contactAngleDegrees * (pi / 180.0);
        const double st = sin(theta);
        const double ct = cos(theta);
        const double rawMag = sqrt(tangentialGradient * tangentialGradient +
                                   rawNormalGradient * rawNormalGradient);
        // Away from the degenerate 0/180 limits, retain the measured tangential
        // derivative and solve exactly for the normal derivative.  Near those
        // limits, use the local raw gradient magnitude to avoid cot(theta) blow-up.
        const double gradMag = fabs(st) > 5.0e-2
            ? fabs(tangentialGradient) / fabs(st)
            : rawMag;
        return gradMag * ct;
    }

    __device__ __forceinline__ double q6_contact_alpha_sample_0493x9j(
        const double* alpha,
        int ix,
        int iy,
        int nx,
        int ny,
        double dx,
        double dy,
        int periodicX,
        int periodicY,
        int wallLeft,
        int wallRight,
        int wallBottom,
        int wallTop,
        double contactAngleDegrees) {
        if (periodicX) ix = wrap_cell_index_0400(ix, nx);
        if (periodicY) iy = wrap_cell_index_0400(iy, ny);
        if (ix >= 0 && ix < nx && iy >= 0 && iy < ny) {
            return alpha[iy * nx + ix];
        }

        // Corners are not part of the x9j qualification.  Prefer the y-wall when
        // both coordinates are outside; this keeps the operation deterministic and
        // leaves a later corner/contact-line patch free to add a two-wall closure.
        if (!periodicY && iy < 0 && wallBottom) {
            const int bx = max(0, min(nx - 1, ix));
            const int by = 0;
            const double a0 = q6_contact_alpha_inside_0493x9j(
                alpha, bx, by, nx, ny, periodicX, periodicY);
            const double gt = q6_contact_tangent_grad_x_0493x9j(
                alpha, bx, by, nx, ny, dx, periodicX, periodicY);
            const double a1 = q6_contact_alpha_inside_0493x9j(
                alpha, bx, min(1, ny - 1), nx, ny, periodicX, periodicY);
            const double gnRaw = ny > 1 ? (a0 - a1) / dy : 0.0;
            const double gn = q6_contact_ghost_normal_gradient_0493x9j(
                gt, gnRaw, contactAngleDegrees);
            return a0 + gn * (static_cast<double>(-iy) * dy);
        }
        if (!periodicY && iy >= ny && wallTop) {
            const int bx = max(0, min(nx - 1, ix));
            const int by = ny - 1;
            const double a0 = q6_contact_alpha_inside_0493x9j(
                alpha, bx, by, nx, ny, periodicX, periodicY);
            const double gt = q6_contact_tangent_grad_x_0493x9j(
                alpha, bx, by, nx, ny, dx, periodicX, periodicY);
            const double a1 = q6_contact_alpha_inside_0493x9j(
                alpha, bx, max(0, ny - 2), nx, ny, periodicX, periodicY);
            const double gnRaw = ny > 1 ? (a0 - a1) / dy : 0.0;
            const double gn = q6_contact_ghost_normal_gradient_0493x9j(
                gt, gnRaw, contactAngleDegrees);
            return a0 + gn * (static_cast<double>(iy - (ny - 1)) * dy);
        }
        if (!periodicX && ix < 0 && wallLeft) {
            const int bx = 0;
            const int by = max(0, min(ny - 1, iy));
            const double a0 = q6_contact_alpha_inside_0493x9j(
                alpha, bx, by, nx, ny, periodicX, periodicY);
            const double gt = q6_contact_tangent_grad_y_0493x9j(
                alpha, bx, by, nx, ny, dy, periodicX, periodicY);
            const double a1 = q6_contact_alpha_inside_0493x9j(
                alpha, min(1, nx - 1), by, nx, ny, periodicX, periodicY);
            const double gnRaw = nx > 1 ? (a0 - a1) / dx : 0.0;
            const double gn = q6_contact_ghost_normal_gradient_0493x9j(
                gt, gnRaw, contactAngleDegrees);
            return a0 + gn * (static_cast<double>(-ix) * dx);
        }
        if (!periodicX && ix >= nx && wallRight) {
            const int bx = nx - 1;
            const int by = max(0, min(ny - 1, iy));
            const double a0 = q6_contact_alpha_inside_0493x9j(
                alpha, bx, by, nx, ny, periodicX, periodicY);
            const double gt = q6_contact_tangent_grad_y_0493x9j(
                alpha, bx, by, nx, ny, dy, periodicX, periodicY);
            const double a1 = q6_contact_alpha_inside_0493x9j(
                alpha, max(0, nx - 2), by, nx, ny, periodicX, periodicY);
            const double gnRaw = nx > 1 ? (a0 - a1) / dx : 0.0;
            const double gn = q6_contact_ghost_normal_gradient_0493x9j(
                gt, gnRaw, contactAngleDegrees);
            return a0 + gn * (static_cast<double>(ix - (nx - 1)) * dx);
        }

        // Non-wall nonperiodic edges keep the pre-x9j constant-extension contract.
        return q6_contact_alpha_inside_0493x9j(
            alpha, ix, iy, nx, ny, periodicX, periodicY);
    }

    // 0493x9k: sheared-mirror ghost-alpha extension for static domain walls.
// For a ghost cell center, reflect the point across the physical wall into the
// fluid and shift that mirror point tangentially so a locally planar alpha
// level set satisfies nAB.nWall=-cos(theta).  Unlike x9j linear extrapolation,
// every ghost depth samples a real interior p3 value, preserving the second-
// derivative geometry needed by kappa=div(n).  Endpoints theta=0/180 are
// deliberately outside the x9k contract.
__device__ __forceinline__ double q6_contact_alpha_interp_0493x9k(
    const double* alpha,
    double fx,
    double fy,
    int nx,
    int ny,
    int periodicX,
    int periodicY) {
    if (nx <= 0 || ny <= 0) return 0.0;

    double x = fx;
    double y = fy;
    if (!periodicX) x = fmax(0.0, fmin(static_cast<double>(nx - 1), x));
    if (!periodicY) y = fmax(0.0, fmin(static_cast<double>(ny - 1), y));

    const int ix0raw = static_cast<int>(floor(x));
    const int iy0raw = static_cast<int>(floor(y));
    const double tx = x - floor(x);
    const double ty = y - floor(y);

    const int ix0 = periodicX ? wrap_cell_index_0400(ix0raw, nx)
                              : max(0, min(nx - 1, ix0raw));
    const int iy0 = periodicY ? wrap_cell_index_0400(iy0raw, ny)
                              : max(0, min(ny - 1, iy0raw));
    const int ix1 = periodicX ? wrap_cell_index_0400(ix0raw + 1, nx)
                              : max(0, min(nx - 1, ix0raw + 1));
    const int iy1 = periodicY ? wrap_cell_index_0400(iy0raw + 1, ny)
                              : max(0, min(ny - 1, iy0raw + 1));

    const double a00 = alpha[iy0 * nx + ix0];
    const double a10 = alpha[iy0 * nx + ix1];
    const double a01 = alpha[iy1 * nx + ix0];
    const double a11 = alpha[iy1 * nx + ix1];
    const double ax0 = a00 + tx * (a10 - a00);
    const double ax1 = a01 + tx * (a11 - a01);
    return ax0 + ty * (ax1 - ax0);
}

__device__ __forceinline__ double q6_contact_shear_ratio_0493x9k(
    double tangentialGradient,
    double contactAngleDegrees) {
    constexpr double pi = 3.141592653589793238462643383279502884;
    const double theta = contactAngleDegrees * (pi / 180.0);
    const double st = sin(theta);
    const double ct = cos(theta);
    if (!(contactAngleDegrees > 0.0 && contactAngleDegrees < 180.0) ||
        fabs(st) < 1.0e-12 || fabs(tangentialGradient) < 1.0e-14) {
        return 0.0;
    }
    const double signT = tangentialGradient > 0.0 ? 1.0 : -1.0;
    // nAB=-grad(alpha)/|grad| and nAB.nWall=-cos(theta) imply
    // g_n/|g|=cos(theta), while the raw tangent selects the branch sign.
    return signT * (ct / st);
}

__device__ __forceinline__ double q6_contact_alpha_sample_0493x9k(
    const double* alpha,
    int ix,
    int iy,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    int wallLeft,
    int wallRight,
    int wallBottom,
    int wallTop,
    double contactAngleDegrees) {
    if (periodicX) ix = wrap_cell_index_0400(ix, nx);
    if (periodicY) iy = wrap_cell_index_0400(iy, ny);
    if (ix >= 0 && ix < nx && iy >= 0 && iy < ny) {
        return alpha[iy * nx + ix];
    }

    // Corners remain outside the qualification scope.  As in x9j, prefer the
    // y-wall if both coordinates are outside, then clamp/interpolate the
    // tangential mirror coordinate deterministically.
    if (!periodicY && iy < 0 && wallBottom) {
        const int bx = max(0, min(nx - 1, ix));
        const double gt = q6_contact_tangent_grad_x_0493x9j(
            alpha, bx, 0, nx, ny, dx, periodicX, periodicY);
        const double ratio = q6_contact_shear_ratio_0493x9k(gt, contactAngleDegrees);
        const int layers = -iy;
        const double normalSeparation = static_cast<double>(2 * layers - 1) * dy;
        const double mirrorX = static_cast<double>(ix) + normalSeparation * ratio / dx;
        const double mirrorY = static_cast<double>(-iy - 1);
        return q6_contact_alpha_interp_0493x9k(
            alpha, mirrorX, mirrorY, nx, ny, periodicX, periodicY);
    }
    if (!periodicY && iy >= ny && wallTop) {
        const int bx = max(0, min(nx - 1, ix));
        const double gt = q6_contact_tangent_grad_x_0493x9j(
            alpha, bx, ny - 1, nx, ny, dx, periodicX, periodicY);
        const double ratio = q6_contact_shear_ratio_0493x9k(gt, contactAngleDegrees);
        const int layers = iy - ny + 1;
        const double normalSeparation = static_cast<double>(2 * layers - 1) * dy;
        const double mirrorX = static_cast<double>(ix) + normalSeparation * ratio / dx;
        const double mirrorY = static_cast<double>(2 * ny - 1 - iy);
        return q6_contact_alpha_interp_0493x9k(
            alpha, mirrorX, mirrorY, nx, ny, periodicX, periodicY);
    }
    if (!periodicX && ix < 0 && wallLeft) {
        const int by = max(0, min(ny - 1, iy));
        const double gt = q6_contact_tangent_grad_y_0493x9j(
            alpha, 0, by, nx, ny, dy, periodicX, periodicY);
        const double ratio = q6_contact_shear_ratio_0493x9k(gt, contactAngleDegrees);
        const int layers = -ix;
        const double normalSeparation = static_cast<double>(2 * layers - 1) * dx;
        const double mirrorX = static_cast<double>(-ix - 1);
        const double mirrorY = static_cast<double>(iy) + normalSeparation * ratio / dy;
        return q6_contact_alpha_interp_0493x9k(
            alpha, mirrorX, mirrorY, nx, ny, periodicX, periodicY);
    }
    if (!periodicX && ix >= nx && wallRight) {
        const int by = max(0, min(ny - 1, iy));
        const double gt = q6_contact_tangent_grad_y_0493x9j(
            alpha, nx - 1, by, nx, ny, dy, periodicX, periodicY);
        const double ratio = q6_contact_shear_ratio_0493x9k(gt, contactAngleDegrees);
        const int layers = ix - nx + 1;
        const double normalSeparation = static_cast<double>(2 * layers - 1) * dx;
        const double mirrorX = static_cast<double>(2 * nx - 1 - ix);
        const double mirrorY = static_cast<double>(iy) + normalSeparation * ratio / dy;
        return q6_contact_alpha_interp_0493x9k(
            alpha, mirrorX, mirrorY, nx, ny, periodicX, periodicY);
    }

    return q6_contact_alpha_inside_0493x9j(
        alpha, ix, iy, nx, ny, periodicX, periodicY);
}

__global__ void q6_filter_phase_alpha_curvature_contact_0493x9j(
        const double* alpha,
        double* alphaK,
        int nx,
        int ny,
        double dx,
        double dy,
        int periodicX,
        int periodicY,
        int wallLeft,
        int wallRight,
        int wallBottom,
        int wallTop,
        double contactAngleDegrees) {
        const int n = nx * ny;
        const int idx = blockIdx.x * blockDim.x + threadIdx.x;
        const int stride = blockDim.x * gridDim.x;
        for (int c = idx; c < n; c += stride) {
            const int ix = c % nx;
            const int iy = c / nx;
            const double nw = q6_contact_alpha_sample_0493x9k(alpha, ix-1, iy+1, nx, ny, dx, dy,
                periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
            const double nn = q6_contact_alpha_sample_0493x9k(alpha, ix,   iy+1, nx, ny, dx, dy,
                periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
            const double ne = q6_contact_alpha_sample_0493x9k(alpha, ix+1, iy+1, nx, ny, dx, dy,
                periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
            const double ww = q6_contact_alpha_sample_0493x9k(alpha, ix-1, iy, nx, ny, dx, dy,
                periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
            const double cc = alpha[c];
            const double ee = q6_contact_alpha_sample_0493x9k(alpha, ix+1, iy, nx, ny, dx, dy,
                periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
            const double sw = q6_contact_alpha_sample_0493x9k(alpha, ix-1, iy-1, nx, ny, dx, dy,
                periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
            const double ss = q6_contact_alpha_sample_0493x9k(alpha, ix,   iy-1, nx, ny, dx, dy,
                periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
            const double se = q6_contact_alpha_sample_0493x9k(alpha, ix+1, iy-1, nx, ny, dx, dy,
                periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
            alphaK[c] = (nw + 2.0*nn + ne + 2.0*ww + 4.0*cc + 2.0*ee +
                         sw + 2.0*ss + se) * (1.0/16.0);
        }
    }

    __device__ __forceinline__ void q6_contact_normal_from_alpha_0493x9j(
        const double* alphaK,
        int ix,
        int iy,
        int nx,
        int ny,
        double dx,
        double dy,
        int periodicX,
        int periodicY,
        int wallLeft,
        int wallRight,
        int wallBottom,
        int wallTop,
        double contactAngleDegrees,
        double* nxOut,
        double* nyOut) {
        const double nw = q6_contact_alpha_sample_0493x9k(alphaK, ix-1, iy+1, nx, ny, dx, dy,
            periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
        const double nn = q6_contact_alpha_sample_0493x9k(alphaK, ix,   iy+1, nx, ny, dx, dy,
            periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
        const double ne = q6_contact_alpha_sample_0493x9k(alphaK, ix+1, iy+1, nx, ny, dx, dy,
            periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
        const double ww = q6_contact_alpha_sample_0493x9k(alphaK, ix-1, iy, nx, ny, dx, dy,
            periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
        const double ee = q6_contact_alpha_sample_0493x9k(alphaK, ix+1, iy, nx, ny, dx, dy,
            periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
        const double sw = q6_contact_alpha_sample_0493x9k(alphaK, ix-1, iy-1, nx, ny, dx, dy,
            periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
        const double ss = q6_contact_alpha_sample_0493x9k(alphaK, ix,   iy-1, nx, ny, dx, dy,
            periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
        const double se = q6_contact_alpha_sample_0493x9k(alphaK, ix+1, iy-1, nx, ny, dx, dy,
            periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop, contactAngleDegrees);
        const double gradX = (3.0*(ne-nw) + 10.0*(ee-ww) + 3.0*(se-sw)) / (32.0*dx);
        const double gradY = (3.0*(nw-sw) + 10.0*(nn-ss) + 3.0*(ne-se)) / (32.0*dy);
        const double g = sqrt(gradX*gradX + gradY*gradY);
        if (g * fmin(dx,dy) > 1.0e-12) {
            *nxOut = -gradX/g;
            *nyOut = -gradY/g;
        } else {
            *nxOut = 0.0;
            *nyOut = 0.0;
        }
    }

    __global__ void q6_build_phase_normals_scharr_contact_0493x9j(
        const double* alphaK,
        double* normalX,
        double* normalY,
        int nx,
        int ny,
        double dx,
        double dy,
        int periodicX,
        int periodicY,
        int wallLeft,
        int wallRight,
        int wallBottom,
        int wallTop,
        double contactAngleDegrees) {
        const int n = nx * ny;
        const int idx = blockIdx.x * blockDim.x + threadIdx.x;
        const int stride = blockDim.x * gridDim.x;
        for (int c=idx; c<n; c+=stride) {
            const int ix=c%nx, iy=c/nx;
            q6_contact_normal_from_alpha_0493x9j(alphaK, ix, iy, nx, ny, dx, dy,
                periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop,
                contactAngleDegrees, &normalX[c], &normalY[c]);
        }
    }

    __device__ __forceinline__ void q6_contact_normal_sample_0493x9j(
        const double* alphaK,
        const double* normalX,
        const double* normalY,
        int ix,
        int iy,
        int nx,
        int ny,
        double dx,
        double dy,
        int periodicX,
        int periodicY,
        int wallLeft,
        int wallRight,
        int wallBottom,
        int wallTop,
        double contactAngleDegrees,
        double* nxOut,
        double* nyOut) {
        int qx=ix, qy=iy;
        if (periodicX) qx=wrap_cell_index_0400(qx,nx);
        if (periodicY) qy=wrap_cell_index_0400(qy,ny);
        if (qx>=0 && qx<nx && qy>=0 && qy<ny) {
            const int q=qy*nx+qx;
            *nxOut=normalX[q]; *nyOut=normalY[q];
            return;
        }
        const bool ghostWall = (!periodicX && ((qx<0 && wallLeft) || (qx>=nx && wallRight))) ||
                               (!periodicY && ((qy<0 && wallBottom) || (qy>=ny && wallTop)));
        if (ghostWall) {
            q6_contact_normal_from_alpha_0493x9j(alphaK, qx, qy, nx, ny, dx, dy,
                periodicX, periodicY, wallLeft, wallRight, wallBottom, wallTop,
                contactAngleDegrees, nxOut, nyOut);
            return;
        }
        qx=max(0,min(nx-1,qx)); qy=max(0,min(ny-1,qy));
        const int q=qy*nx+qx;
        *nxOut=normalX[q]; *nyOut=normalY[q];
    }

    __global__ void q6_build_phase_curvature_scharr_contact_0493x9j(
        const double* alphaK,
        const double* normalX,
        const double* normalY,
        double* curvature,
        int nx,
        int ny,
        double dx,
        double dy,
        int periodicX,
        int periodicY,
        int wallLeft,
        int wallRight,
        int wallBottom,
        int wallTop,
        double contactAngleDegrees) {
        const int n=nx*ny;
        const int idx=blockIdx.x*blockDim.x+threadIdx.x;
        const int stride=blockDim.x*gridDim.x;
        for (int c=idx;c<n;c+=stride) {
            const int ix=c%nx, iy=c/nx;
            double nxNW,nyNW,nxN,nyN,nxNE,nyNE,nxW,nyW,nxE,nyE,nxSW,nySW,nxS,nyS,nxSE,nySE;
            q6_contact_normal_sample_0493x9j(alphaK,normalX,normalY,ix-1,iy+1,nx,ny,dx,dy,periodicX,periodicY,wallLeft,wallRight,wallBottom,wallTop,contactAngleDegrees,&nxNW,&nyNW);
            q6_contact_normal_sample_0493x9j(alphaK,normalX,normalY,ix,iy+1,nx,ny,dx,dy,periodicX,periodicY,wallLeft,wallRight,wallBottom,wallTop,contactAngleDegrees,&nxN,&nyN);
            q6_contact_normal_sample_0493x9j(alphaK,normalX,normalY,ix+1,iy+1,nx,ny,dx,dy,periodicX,periodicY,wallLeft,wallRight,wallBottom,wallTop,contactAngleDegrees,&nxNE,&nyNE);
            q6_contact_normal_sample_0493x9j(alphaK,normalX,normalY,ix-1,iy,nx,ny,dx,dy,periodicX,periodicY,wallLeft,wallRight,wallBottom,wallTop,contactAngleDegrees,&nxW,&nyW);
            q6_contact_normal_sample_0493x9j(alphaK,normalX,normalY,ix+1,iy,nx,ny,dx,dy,periodicX,periodicY,wallLeft,wallRight,wallBottom,wallTop,contactAngleDegrees,&nxE,&nyE);
            q6_contact_normal_sample_0493x9j(alphaK,normalX,normalY,ix-1,iy-1,nx,ny,dx,dy,periodicX,periodicY,wallLeft,wallRight,wallBottom,wallTop,contactAngleDegrees,&nxSW,&nySW);
            q6_contact_normal_sample_0493x9j(alphaK,normalX,normalY,ix,iy-1,nx,ny,dx,dy,periodicX,periodicY,wallLeft,wallRight,wallBottom,wallTop,contactAngleDegrees,&nxS,&nyS);
            q6_contact_normal_sample_0493x9j(alphaK,normalX,normalY,ix+1,iy-1,nx,ny,dx,dy,periodicX,periodicY,wallLeft,wallRight,wallBottom,wallTop,contactAngleDegrees,&nxSE,&nySE);
            const double dnxDx=(3.0*(nxNE-nxNW)+10.0*(nxE-nxW)+3.0*(nxSE-nxSW))/(32.0*dx);
            const double dnyDy=(3.0*(nyNW-nySW)+10.0*(nyN-nyS)+3.0*(nyNE-nySE))/(32.0*dy);
            curvature[c]=dnxDx+dnyDy;
        }
    }

    __device__ __forceinline__ void q6_contact_standard_normal_0493x9j(
        const double* alphaK, int ix, int iy, int nx, int ny, double dx, double dy,
        int periodicX, int periodicY, double* nxOut, double* nyOut) {
        const double nw=alphaK[q6_contact_index_0493x9i(ix-1,iy+1,nx,ny,periodicX,periodicY)];
        const double nn=alphaK[q6_contact_index_0493x9i(ix,iy+1,nx,ny,periodicX,periodicY)];
        const double ne=alphaK[q6_contact_index_0493x9i(ix+1,iy+1,nx,ny,periodicX,periodicY)];
        const double ww=alphaK[q6_contact_index_0493x9i(ix-1,iy,nx,ny,periodicX,periodicY)];
        const double ee=alphaK[q6_contact_index_0493x9i(ix+1,iy,nx,ny,periodicX,periodicY)];
        const double sw=alphaK[q6_contact_index_0493x9i(ix-1,iy-1,nx,ny,periodicX,periodicY)];
        const double ss=alphaK[q6_contact_index_0493x9i(ix,iy-1,nx,ny,periodicX,periodicY)];
        const double se=alphaK[q6_contact_index_0493x9i(ix+1,iy-1,nx,ny,periodicX,periodicY)];
        const double gx=(3.0*(ne-nw)+10.0*(ee-ww)+3.0*(se-sw))/(32.0*dx);
        const double gy=(3.0*(nw-sw)+10.0*(nn-ss)+3.0*(ne-se))/(32.0*dy);
        const double g=sqrt(gx*gx+gy*gy);
        if (g*fmin(dx,dy)>1.0e-12) {*nxOut=-gx/g; *nyOut=-gy/g;}
        else {*nxOut=0.0; *nyOut=0.0;}
    }

    __global__ void q6_contact_angle_ghost_normal_audit_0493x9j(
        const double* alphaPhysical,
        const double* alphaK,
        const double* wallNormalX,
        const double* wallNormalY,
        const double* phaseNormalX,
        const double* phaseNormalY,
        ContactAngleAccumulator0493x9i* accum,
        int nx,
        int ny,
        double dx,
        double dy,
        int periodicX,
        int periodicY,
        double contactAngleDegrees) {
        const int n=nx*ny;
        const int idx=blockIdx.x*blockDim.x+threadIdx.x;
        const int stride=blockDim.x*gridDim.x;
        constexpr double pi=3.141592653589793238462643383279502884;
        const double targetDot=-cos(contactAngleDegrees*(pi/180.0));
        unsigned long long candidateLocal=0ull, correctedLocal=0ull;
        double rawAngleSumLocal=0.0, correctedAngleSumLocal=0.0, angleErrSqLocal=0.0, dotErrSqLocal=0.0;
        for (int c=idx;c<n;c+=stride) {
            const int ix=c%nx, iy=c/nx;
            const double nwx=wallNormalX[c], nwy=wallNormalY[c];
            const double wg=sqrt(nwx*nwx+nwy*nwy);
            if (!(wg>0.5)) continue;
            if (!q6_contact_interface_band_0493x9i(alphaPhysical,ix,iy,nx,ny,periodicX,periodicY)) continue;
            double rx=0.0, ry=0.0;
            q6_contact_standard_normal_0493x9j(alphaK,ix,iy,nx,ny,dx,dy,periodicX,periodicY,&rx,&ry);
            const double rg=sqrt(rx*rx+ry*ry);
            const double gx=phaseNormalX[c], gy=phaseNormalY[c];
            const double gg=sqrt(gx*gx+gy*gy);
            if (!(rg>0.5) || !(gg>0.5)) continue;
            ++candidateLocal; ++correctedLocal;
            const double wx=nwx/wg, wy=nwy/wg;
            const double rawDot=fmax(-1.0,fmin(1.0,(rx*wx+ry*wy)/rg));
            const double ghostDot=fmax(-1.0,fmin(1.0,(gx*wx+gy*wy)/gg));
            const double rawAngle=acos(fmax(-1.0,fmin(1.0,-rawDot)))*(180.0/pi);
            const double ghostAngle=acos(fmax(-1.0,fmin(1.0,-ghostDot)))*(180.0/pi);
            rawAngleSumLocal+=rawAngle; correctedAngleSumLocal+=ghostAngle;
            const double ae=ghostAngle-contactAngleDegrees;
            const double de=ghostDot-targetDot;
            angleErrSqLocal+=ae*ae; dotErrSqLocal+=de*de;
        }
        if (candidateLocal) atomicAdd(&accum->candidateCells,candidateLocal);
        if (correctedLocal) atomicAdd(&accum->correctedCells,correctedLocal);
        if (rawAngleSumLocal!=0.0) atomic_add_double_0400(&accum->rawAngleSum,rawAngleSumLocal);
        if (correctedAngleSumLocal!=0.0) atomic_add_double_0400(&accum->correctedAngleSum,correctedAngleSumLocal);
        if (angleErrSqLocal!=0.0) atomic_add_double_0400(&accum->correctedAngleErrorSqSum,angleErrSqLocal);
        if (dotErrSqLocal!=0.0) atomic_add_double_0400(&accum->correctedDotErrorSqSum,dotErrSqLocal);
    }

    // 0493x9l: impose the Young angle at the physical wall face, not at the
// first cell centre.  Let n2 be the unmodified p3 normal one full cell farther
// into the fluid (s=3h/2).  The target wall-face normal is nWface at s=0.
// Interpolate the normal angle linearly: n0 at s=h/2 uses +1/3 of the signed
// rotation nWface->n2, while the ghost at s=-h/2 uses -1/3.  This keeps |n|=1
// and makes the face value exactly the prescribed contact angle without
// shearing or extrapolating the scalar alpha field.
__device__ __forceinline__ bool q6_contact_wall_frame_0493x9l(
    const double* wallNormalX,
    const double* wallNormalY,
    int bx,
    int by,
    int nx,
    int ny,
    double* wx,
    double* wy,
    int* sxIn,
    int* syIn) {
    if (bx < 0 || bx >= nx || by < 0 || by >= ny) return false;
    const int c = by*nx + bx;
    const double x = wallNormalX[c], y = wallNormalY[c];
    const double g = sqrt(x*x + y*y);
    if (!(g > 0.5)) return false;
    const double ux=x/g, uy=y/g;
    int sx=0, sy=0;
    if (fabs(ux) > 0.9 && fabs(uy) < 0.2) sx = ux > 0.0 ? -1 : 1;
    else if (fabs(uy) > 0.9 && fabs(ux) < 0.2) sy = uy > 0.0 ? -1 : 1;
    else return false; // domain-wall corners are outside the qualification scope
    const int ix2=bx+sx, iy2=by+sy;
    if (ix2 < 0 || ix2 >= nx || iy2 < 0 || iy2 >= ny) return false;
    *wx=ux; *wy=uy; *sxIn=sx; *syIn=sy;
    return true;
}

__device__ __forceinline__ bool q6_contact_wall_target_0493x9l(
    double wx,
    double wy,
    double refx,
    double refy,
    double contactAngleDegrees,
    double* txOut,
    double* tyOut) {
    constexpr double pi=3.141592653589793238462643383279502884;
    if (!(contactAngleDegrees > 0.0 && contactAngleDegrees < 180.0)) return false;
    const double rg=sqrt(refx*refx+refy*refy);
    if (!(rg > 0.5)) return false;
    refx/=rg; refy/=rg;
    const double theta=contactAngleDegrees*(pi/180.0);
    const double targetDot=-cos(theta);
    const double tangentMagnitude=sin(theta);
    const double tx=-wy, ty=wx;
    const double tangential=refx*tx+refy*ty;
    const double signT=tangential < 0.0 ? -1.0 : 1.0;
    double nx=targetDot*wx+signT*tangentMagnitude*tx;
    double ny=targetDot*wy+signT*tangentMagnitude*ty;
    const double ng=sqrt(nx*nx+ny*ny);
    if (!(ng > 1.0e-14)) return false;
    *txOut=nx/ng; *tyOut=ny/ng;
    return true;
}

__device__ __forceinline__ void q6_contact_rotate_fraction_0493x9l(
    double baseX,
    double baseY,
    double refX,
    double refY,
    double fraction,
    double* nxOut,
    double* nyOut) {
    const double rg=sqrt(refX*refX+refY*refY);
    if (!(rg > 0.5)) { *nxOut=baseX; *nyOut=baseY; return; }
    refX/=rg; refY/=rg;
    const double dot=fmax(-1.0,fmin(1.0,baseX*refX+baseY*refY));
    const double cross=baseX*refY-baseY*refX;
    const double delta=atan2(cross,dot);
    const double a=fraction*delta;
    const double ca=cos(a), sa=sin(a);
    *nxOut=ca*baseX-sa*baseY;
    *nyOut=sa*baseX+ca*baseY;
}

__global__ void q6_apply_contact_angle_wallface_normals_0493x9l(
    const double* alphaPhysical,
    const double* wallNormalX,
    const double* wallNormalY,
    double* phaseNormalX,
    double* phaseNormalY,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    double contactAngleDegrees) {
    const int n=nx*ny;
    const int idx=blockIdx.x*blockDim.x+threadIdx.x;
    const int stride=blockDim.x*gridDim.x;
    for (int c=idx;c<n;c+=stride) {
        const int ix=c%nx, iy=c/nx;
        if (!q6_contact_interface_band_0493x9i(alphaPhysical,ix,iy,nx,ny,periodicX,periodicY)) continue;
        double wx=0.0,wy=0.0; int sx=0,sy=0;
        if (!q6_contact_wall_frame_0493x9l(wallNormalX,wallNormalY,ix,iy,nx,ny,&wx,&wy,&sx,&sy)) continue;
        const int c2=(iy+sy)*nx+(ix+sx);
        const double n2x=phaseNormalX[c2], n2y=phaseNormalY[c2];
        double wallX=0.0,wallY=0.0;
        if (!q6_contact_wall_target_0493x9l(wx,wy,n2x,n2y,contactAngleDegrees,&wallX,&wallY)) continue;
        double n0x=0.0,n0y=0.0;
        q6_contact_rotate_fraction_0493x9l(wallX,wallY,n2x,n2y,1.0/3.0,&n0x,&n0y);
        phaseNormalX[c]=n0x; phaseNormalY[c]=n0y;
    }
}

__device__ __forceinline__ void q6_contact_wallface_normal_sample_0493x9l(
    const double* alphaPhysical,
    const double* wallNormalX,
    const double* wallNormalY,
    const double* normalX,
    const double* normalY,
    int ix,
    int iy,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    int wallLeft,
    int wallRight,
    int wallBottom,
    int wallTop,
    double contactAngleDegrees,
    double* nxOut,
    double* nyOut) {
    int qx=ix,qy=iy;
    if (periodicX) qx=wrap_cell_index_0400(qx,nx);
    if (periodicY) qy=wrap_cell_index_0400(qy,ny);
    if (qx>=0 && qx<nx && qy>=0 && qy<ny) {
        const int q=qy*nx+qx; *nxOut=normalX[q]; *nyOut=normalY[q]; return;
    }
    int bx=qx,by=qy;
    if (!periodicY && qy<0 && wallBottom) by=0;
    else if (!periodicY && qy>=ny && wallTop) by=ny-1;
    else if (!periodicX && qx<0 && wallLeft) bx=0;
    else if (!periodicX && qx>=nx && wallRight) bx=nx-1;
    else {
        bx=max(0,min(nx-1,bx)); by=max(0,min(ny-1,by));
        const int q=by*nx+bx; *nxOut=normalX[q]; *nyOut=normalY[q]; return;
    }
    bx=max(0,min(nx-1,bx)); by=max(0,min(ny-1,by));
    const int b=by*nx+bx;
    if (!q6_contact_interface_band_0493x9i(alphaPhysical,bx,by,nx,ny,periodicX,periodicY)) {
        *nxOut=normalX[b]; *nyOut=normalY[b]; return;
    }
    double wx=0.0,wy=0.0; int sx=0,sy=0;
    if (!q6_contact_wall_frame_0493x9l(wallNormalX,wallNormalY,bx,by,nx,ny,&wx,&wy,&sx,&sy)) {
        *nxOut=normalX[b]; *nyOut=normalY[b]; return;
    }
    const int c2=(by+sy)*nx+(bx+sx);
    const double n2x=normalX[c2], n2y=normalY[c2];
    double wallX=0.0,wallY=0.0;
    if (!q6_contact_wall_target_0493x9l(wx,wy,n2x,n2y,contactAngleDegrees,&wallX,&wallY)) {
        *nxOut=normalX[b]; *nyOut=normalY[b]; return;
    }
    q6_contact_rotate_fraction_0493x9l(wallX,wallY,n2x,n2y,-1.0/3.0,nxOut,nyOut);
}

__global__ void q6_build_phase_curvature_wallface_0493x9l(
    const double* alphaPhysical,
    const double* wallNormalX,
    const double* wallNormalY,
    const double* normalX,
    const double* normalY,
    double* curvature,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    int wallLeft,
    int wallRight,
    int wallBottom,
    int wallTop,
    double contactAngleDegrees) {
    const int n=nx*ny;
    const int idx=blockIdx.x*blockDim.x+threadIdx.x;
    const int stride=blockDim.x*gridDim.x;
    for (int c=idx;c<n;c+=stride) {
        const int ix=c%nx, iy=c/nx;
        double nxNW,nyNW,nxN,nyN,nxNE,nyNE,nxW,nyW,nxE,nyE,nxSW,nySW,nxS,nyS,nxSE,nySE;
#define X9L_NS(X,Y,NX,NY) q6_contact_wallface_normal_sample_0493x9l(alphaPhysical,wallNormalX,wallNormalY,normalX,normalY,(X),(Y),nx,ny,periodicX,periodicY,wallLeft,wallRight,wallBottom,wallTop,contactAngleDegrees,&(NX),&(NY))
        X9L_NS(ix-1,iy+1,nxNW,nyNW); X9L_NS(ix,iy+1,nxN,nyN); X9L_NS(ix+1,iy+1,nxNE,nyNE);
        X9L_NS(ix-1,iy,nxW,nyW);                                   X9L_NS(ix+1,iy,nxE,nyE);
        X9L_NS(ix-1,iy-1,nxSW,nySW); X9L_NS(ix,iy-1,nxS,nyS); X9L_NS(ix+1,iy-1,nxSE,nySE);
#undef X9L_NS
        const double dnxDx=(3.0*(nxNE-nxNW)+10.0*(nxE-nxW)+3.0*(nxSE-nxSW))/(32.0*dx);
        const double dnyDy=(3.0*(nyNW-nySW)+10.0*(nyN-nyS)+3.0*(nyNE-nySE))/(32.0*dy);
        curvature[c]=dnxDx+dnyDy;
    }
}

__global__ void q6_contact_angle_wallface_audit_0493x9l(
    const double* alphaPhysical,
    const double* alphaK,
    const double* wallNormalX,
    const double* wallNormalY,
    const double* phaseNormalX,
    const double* phaseNormalY,
    ContactAngleAccumulator0493x9i* accum,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    double contactAngleDegrees) {
    const int n=nx*ny;
    const int idx=blockIdx.x*blockDim.x+threadIdx.x;
    const int stride=blockDim.x*gridDim.x;
    constexpr double pi=3.141592653589793238462643383279502884;
    const double targetDot=-cos(contactAngleDegrees*(pi/180.0));
    unsigned long long candidateLocal=0ull, correctedLocal=0ull;
    double rawAngleSumLocal=0.0, correctedAngleSumLocal=0.0, angleErrSqLocal=0.0, dotErrSqLocal=0.0;
    for (int c=idx;c<n;c+=stride) {
        const int ix=c%nx, iy=c/nx;
        if (!q6_contact_interface_band_0493x9i(alphaPhysical,ix,iy,nx,ny,periodicX,periodicY)) continue;
        double wx=0.0,wy=0.0; int sx=0,sy=0;
        if (!q6_contact_wall_frame_0493x9l(wallNormalX,wallNormalY,ix,iy,nx,ny,&wx,&wy,&sx,&sy)) continue;
        double rx=0.0,ry=0.0;
        q6_contact_standard_normal_0493x9j(alphaK,ix,iy,nx,ny,dx,dy,periodicX,periodicY,&rx,&ry);
        const double rg=sqrt(rx*rx+ry*ry);
        if (!(rg>0.5)) continue;
        ++candidateLocal;
        const double rawDot=fmax(-1.0,fmin(1.0,(rx*wx+ry*wy)/rg));
        rawAngleSumLocal+=acos(fmax(-1.0,fmin(1.0,-rawDot)))*(180.0/pi);
        const int c2=(iy+sy)*nx+(ix+sx);
        const double n2x=phaseNormalX[c2], n2y=phaseNormalY[c2];
        double wallX=0.0,wallY=0.0;
        if (!q6_contact_wall_target_0493x9l(wx,wy,n2x,n2y,contactAngleDegrees,&wallX,&wallY)) continue;
        double ghostX=0.0,ghostY=0.0;
        q6_contact_rotate_fraction_0493x9l(wallX,wallY,n2x,n2y,-1.0/3.0,&ghostX,&ghostY);
        const double n0x=phaseNormalX[c], n0y=phaseNormalY[c];
        double fx=n0x+ghostX, fy=n0y+ghostY;
        const double fg=sqrt(fx*fx+fy*fy);
        if (!(fg>1.0e-14)) continue;
        fx/=fg; fy/=fg;
        const double dot=fmax(-1.0,fmin(1.0,fx*wx+fy*wy));
        const double measured=acos(fmax(-1.0,fmin(1.0,-dot)))*(180.0/pi);
        ++correctedLocal;
        correctedAngleSumLocal+=measured;
        const double ae=measured-contactAngleDegrees, de=dot-targetDot;
        angleErrSqLocal+=ae*ae; dotErrSqLocal+=de*de;
    }
    if (candidateLocal) atomicAdd(&accum->candidateCells,candidateLocal);
    if (correctedLocal) atomicAdd(&accum->correctedCells,correctedLocal);
    if (rawAngleSumLocal!=0.0) atomic_add_double_0400(&accum->rawAngleSum,rawAngleSumLocal);
    if (correctedAngleSumLocal!=0.0) atomic_add_double_0400(&accum->correctedAngleSum,correctedAngleSumLocal);
    if (angleErrSqLocal!=0.0) atomic_add_double_0400(&accum->correctedAngleErrorSqSum,angleErrSqLocal);
    if (dotErrSqLocal!=0.0) atomic_add_double_0400(&accum->correctedDotErrorSqSum,dotErrSqLocal);
}

// 0493x9m off-support anchor.  Three binomial 3x3 passes plus the
// Scharr normal use a radius-four scalar support, so layer j=4 (centre 4.5h)
// is the first raw p3 normal independent of virtual samples behind the wall.
// For a circular arc, two endpoint normals separated by chord length L obey
// kappa = 2 sin(DeltaPhi/2)/L.  x9m uses this as the wall-contact curvature
// closure; no scalar or normal field is overwritten.
__device__ __forceinline__ bool q6_contact_find_tangent_crossing_0493x9m(
    const double* alphaPhysical,
    int bx,
    int by,
    int sx,
    int sy,
    int layer,
    double predictedOffset,
    int searchRadius,
    int nx,
    int ny,
    double* crossingOffsetOut) {
    const int txi=sy, tyi=-sx; // t_w=(-nWall_y,nWall_x)
    bool found=false;
    double best=1.0e300, bestOffset=0.0;
    for (int off=-searchRadius; off<searchRadius; ++off) {
        const int x0=bx+layer*sx+off*txi;
        const int y0=by+layer*sy+off*tyi;
        const int x1=bx+layer*sx+(off+1)*txi;
        const int y1=by+layer*sy+(off+1)*tyi;
        if (x0<0 || x0>=nx || y0<0 || y0>=ny ||
            x1<0 || x1>=nx || y1<0 || y1>=ny) continue;
        const double a0=fmin(1.0,fmax(0.0,alphaPhysical[y0*nx+x0]));
        const double a1=fmin(1.0,fmax(0.0,alphaPhysical[y1*nx+x1]));
        const bool crossing=(a0<0.5 && a1>=0.5) || (a1<0.5 && a0>=0.5);
        if (!crossing || fabs(a1-a0)<1.0e-14) continue;
        const double f=(0.5-a0)/(a1-a0);
        if (!(f>=0.0 && f<=1.0)) continue;
        const double pos=static_cast<double>(off)+f;
        const double score=fabs(pos-predictedOffset);
        if (!found || score<best) { found=true; best=score; bestOffset=pos; }
    }
    if (!found) return false;
    *crossingOffsetOut=bestOffset;
    return true;
}

__device__ __forceinline__ bool q6_contact_interp_anchor_normal_0493x9m(
    const double* normalX,
    const double* normalY,
    int bx,
    int by,
    int sx,
    int sy,
    int layer,
    double crossingOffset,
    int nx,
    int ny,
    double* nxOut,
    double* nyOut) {
    const int txi=sy, tyi=-sx;
    const int off0=static_cast<int>(floor(crossingOffset));
    const double f=crossingOffset-static_cast<double>(off0);
    const int x0=bx+layer*sx+off0*txi;
    const int y0=by+layer*sy+off0*tyi;
    const int x1=bx+layer*sx+(off0+1)*txi;
    const int y1=by+layer*sy+(off0+1)*tyi;
    if (x0<0 || x0>=nx || y0<0 || y0>=ny ||
        x1<0 || x1>=nx || y1<0 || y1>=ny) return false;
    double vx=(1.0-f)*normalX[y0*nx+x0]+f*normalX[y1*nx+x1];
    double vy=(1.0-f)*normalY[y0*nx+x0]+f*normalY[y1*nx+x1];
    const double g=sqrt(vx*vx+vy*vy);
    if (!(g>0.5)) return false;
    *nxOut=vx/g; *nyOut=vy/g;
    return true;
}

__device__ __forceinline__ bool q6_contact_offsupport_secant_0493x9m(
    const double* alphaPhysical,
    const double* normalX,
    const double* normalY,
    double wx,
    double wy,
    int sx,
    int sy,
    int bx,
    int by,
    int nx,
    int ny,
    double dx,
    double dy,
    double contactAngleDegrees,
    double* wallNXOut,
    double* wallNYOut,
    double* curvatureOut) {
    constexpr int anchorLayer=4;
    constexpr double pi=3.141592653589793238462643383279502884;
    if (!(contactAngleDegrees>0.0 && contactAngleDegrees<180.0)) return false;
    const int b=by*nx+bx;
    const double brx=normalX[b], bry=normalY[b];
    if (!(sqrt(brx*brx+bry*bry)>0.5)) return false;
    double wallNX=0.0,wallNY=0.0;
    if (!q6_contact_wall_target_0493x9l(
            wx,wy,brx,bry,contactAngleDegrees,&wallNX,&wallNY)) return false;
    const double theta=contactAngleDegrees*(pi/180.0);
    const double st=sin(theta), ct=cos(theta);
    if (!(fabs(st)>1.0e-12)) return false;
    const double hNormal=(sx!=0) ? dx : dy;
    const double hTangent=(sx!=0) ? dy : dx;
    if (!(hNormal>0.0) || !(hTangent>0.0)) return false;
    const int txi=sy, tyi=-sx;
    const double signT=(wallNX*static_cast<double>(txi)+wallNY*static_cast<double>(tyi))<0.0 ? -1.0 : 1.0;
    const double cotTheta=ct/st;
    const double ratio=hNormal/hTangent;

    // First locate the alpha=0.5 crossing in the boundary cell-centre layer.
    // Project that crossing by half a normal cell back to the physical wall face.
    double row0Cross=0.0;
    if (!q6_contact_find_tangent_crossing_0493x9m(
            alphaPhysical,bx,by,sx,sy,0,0.0,6,nx,ny,&row0Cross)) return false;
    const double wallCross=row0Cross+signT*0.5*ratio*cotTheta;

    // Predict the interface position at the clean anchor layer and snap to the
    // nearest physical alpha=0.5 crossing there.  This avoids anchoring in bulk
    // for shallow angles such as 30/150 degrees.
    const double anchorPred=wallCross-signT*(anchorLayer+0.5)*ratio*cotTheta;
    const int searchRadius=min(48,max(8,static_cast<int>(ceil(fabs(anchorPred)))+8));
    double anchorCross=0.0;
    if (!q6_contact_find_tangent_crossing_0493x9m(
            alphaPhysical,bx,by,sx,sy,anchorLayer,anchorPred,searchRadius,
            nx,ny,&anchorCross)) return false;
    double anchorNX=0.0,anchorNY=0.0;
    if (!q6_contact_interp_anchor_normal_0493x9m(
            normalX,normalY,bx,by,sx,sy,anchorLayer,anchorCross,
            nx,ny,&anchorNX,&anchorNY)) return false;

    const double dt=(anchorCross-wallCross)*hTangent;
    const double dn=(anchorLayer+0.5)*hNormal;
    const double chordX=dt*static_cast<double>(txi)+dn*static_cast<double>(sx);
    const double chordY=dt*static_cast<double>(tyi)+dn*static_cast<double>(sy);
    const double chord=sqrt(chordX*chordX+chordY*chordY);
    if (!(chord>1.0e-14)) return false;
    const double dot=fmax(-1.0,fmin(1.0,wallNX*anchorNX+wallNY*anchorNY));
    const double cross=wallNX*anchorNY-wallNY*anchorNX;
    const double delta=atan2(cross,dot);
    const double tangent0X=-wallNY, tangent0Y=wallNX;
    const double orientDot=chordX*tangent0X+chordY*tangent0Y;
    if (!(fabs(orientDot)>1.0e-14)) return false;
    const double orient=orientDot>=0.0 ? 1.0 : -1.0;
    const double kappa=2.0*sin(0.5*delta)/(orient*chord);
    if (!isfinite(kappa)) return false;
    *wallNXOut=wallNX; *wallNYOut=wallNY; *curvatureOut=kappa;
    return true;
}

__global__ void q6_apply_contact_angle_offsupport_curvature_0493x9m(
    const double* alphaPhysical,
    const double* wallNormalX,
    const double* wallNormalY,
    const double* phaseNormalX,
    const double* phaseNormalY,
    double* curvature,
    ContactAngleAccumulator0493x9i* accum,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    double contactAngleDegrees) {
    const int n=nx*ny;
    const int idx=blockIdx.x*blockDim.x+threadIdx.x;
    const int stride=blockDim.x*gridDim.x;
    constexpr double pi=3.141592653589793238462643383279502884;
    const double targetDot=-cos(contactAngleDegrees*(pi/180.0));
    unsigned long long candidateLocal=0ull, correctedLocal=0ull;
    double rawAngleSumLocal=0.0, correctedAngleSumLocal=0.0, angleErrSqLocal=0.0, dotErrSqLocal=0.0;
    for (int c=idx;c<n;c+=stride) {
        const int ix=c%nx, iy=c/nx;
        if (!q6_contact_interface_band_0493x9i(
                alphaPhysical,ix,iy,nx,ny,periodicX,periodicY)) continue;
        double wx=0.0,wy=0.0; int sx=0,sy=0;
        if (!q6_contact_wall_frame_0493x9l(
                wallNormalX,wallNormalY,ix,iy,nx,ny,&wx,&wy,&sx,&sy)) continue;
        const double rx=phaseNormalX[c], ry=phaseNormalY[c];
        const double rg=sqrt(rx*rx+ry*ry);
        if (!(rg>0.5)) continue;
        ++candidateLocal;
        const double rawDot=fmax(-1.0,fmin(1.0,(rx*wx+ry*wy)/rg));
        rawAngleSumLocal+=acos(fmax(-1.0,fmin(1.0,-rawDot)))*(180.0/pi);
        double wallNX=0.0,wallNY=0.0,kappa=0.0;
        if (!q6_contact_offsupport_secant_0493x9m(
                alphaPhysical,phaseNormalX,phaseNormalY,wx,wy,sx,sy,ix,iy,
                nx,ny,dx,dy,contactAngleDegrees,&wallNX,&wallNY,&kappa)) continue;
        curvature[c]=kappa;
        const double dot=fmax(-1.0,fmin(1.0,wallNX*wx+wallNY*wy));
        const double measured=acos(fmax(-1.0,fmin(1.0,-dot)))*(180.0/pi);
        ++correctedLocal;
        correctedAngleSumLocal+=measured;
        const double ae=measured-contactAngleDegrees, de=dot-targetDot;
        angleErrSqLocal+=ae*ae; dotErrSqLocal+=de*de;
    }
    if (candidateLocal) atomicAdd(&accum->candidateCells,candidateLocal);
    if (correctedLocal) atomicAdd(&accum->correctedCells,correctedLocal);
    if (rawAngleSumLocal!=0.0) atomic_add_double_0400(&accum->rawAngleSum,rawAngleSumLocal);
    if (correctedAngleSumLocal!=0.0) atomic_add_double_0400(&accum->correctedAngleSum,correctedAngleSumLocal);
    if (angleErrSqLocal!=0.0) atomic_add_double_0400(&accum->correctedAngleErrorSqSum,angleErrSqLocal);
    if (dotErrSqLocal!=0.0) atomic_add_double_0400(&accum->correctedDotErrorSqSum,dotErrSqLocal);
}

__global__ void q6_apply_contact_angle_normals_0493x9i(
    const double* alphaPhysical,
    const double* wallNormalX,
    const double* wallNormalY,
    double* phaseNormalX,
    double* phaseNormalY,
    ContactAngleAccumulator0493x9i* accum,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    double contactAngleDegrees) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    constexpr double pi = 3.141592653589793238462643383279502884;
    const double theta = contactAngleDegrees * (pi / 180.0);
    const double targetDot = -cos(theta);
    const double tangentMagnitude = sqrt(fmax(0.0, 1.0 - targetDot * targetDot));
    unsigned long long candidateLocal = 0ull;
    unsigned long long correctedLocal = 0ull;
    double rawAngleSumLocal = 0.0;
    double correctedAngleSumLocal = 0.0;
    double angleErrSqLocal = 0.0;
    double dotErrSqLocal = 0.0;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const double nwx = wallNormalX[c];
        const double nwy = wallNormalY[c];
        const double wg = sqrt(nwx*nwx + nwy*nwy);
        if (!(wg > 0.5)) continue;
        if (!q6_contact_interface_band_0493x9i(
                alphaPhysical, ix, iy, nx, ny, periodicX, periodicY)) continue;
        const double rx = phaseNormalX[c];
        const double ry = phaseNormalY[c];
        const double rg = sqrt(rx*rx + ry*ry);
        if (!(rg > 0.5)) continue;
        ++candidateLocal;
        const double wx = nwx / wg;
        const double wy = nwy / wg;
        const double rnx = rx / rg;
        const double rny = ry / rg;
        const double rawDot = fmax(-1.0, fmin(1.0, rnx*wx + rny*wy));
        const double rawAngle = acos(fmax(-1.0, fmin(1.0, -rawDot))) * (180.0/pi);
        rawAngleSumLocal += rawAngle;
        const double tx = -wy;
        const double ty = wx;
        const double tangentialRaw = rnx*tx + rny*ty;
        const double signT = tangentialRaw < 0.0 ? -1.0 : 1.0;
        double nxNew = targetDot*wx + signT*tangentMagnitude*tx;
        double nyNew = targetDot*wy + signT*tangentMagnitude*ty;
        const double ng = sqrt(nxNew*nxNew + nyNew*nyNew);
        if (!(ng > 1.0e-14)) continue;
        nxNew /= ng;
        nyNew /= ng;
        phaseNormalX[c] = nxNew;
        phaseNormalY[c] = nyNew;
        ++correctedLocal;
        const double dot = fmax(-1.0, fmin(1.0, nxNew*wx + nyNew*wy));
        const double measuredAngle = acos(fmax(-1.0, fmin(1.0, -dot))) * (180.0/pi);
        correctedAngleSumLocal += measuredAngle;
        const double ae = measuredAngle - contactAngleDegrees;
        const double de = dot - targetDot;
        angleErrSqLocal += ae*ae;
        dotErrSqLocal += de*de;
    }
    if (candidateLocal) atomicAdd(&accum->candidateCells, candidateLocal);
    if (correctedLocal) atomicAdd(&accum->correctedCells, correctedLocal);
    if (rawAngleSumLocal != 0.0) atomic_add_double_0400(&accum->rawAngleSum, rawAngleSumLocal);
    if (correctedAngleSumLocal != 0.0) atomic_add_double_0400(&accum->correctedAngleSum, correctedAngleSumLocal);
    if (angleErrSqLocal != 0.0) atomic_add_double_0400(&accum->correctedAngleErrorSqSum, angleErrSqLocal);
    if (dotErrSqLocal != 0.0) atomic_add_double_0400(&accum->correctedDotErrorSqSum, dotErrSqLocal);
}

__global__ void q6_contact_angle_curvature_audit_0493x9i(
    const double* alphaPhysical,
    const double* wallNormalX,
    const double* wallNormalY,
    const double* curvature,
    ContactAngleAccumulator0493x9i* accum,
    int nx,
    int ny,
    int periodicX,
    int periodicY) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    unsigned long long countLocal = 0ull;
    double sumLocal = 0.0;
    double sqLocal = 0.0;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const double wg = sqrt(wallNormalX[c]*wallNormalX[c] + wallNormalY[c]*wallNormalY[c]);
        if (!(wg > 0.5)) continue;
        if (!q6_contact_interface_band_0493x9i(
                alphaPhysical, ix, iy, nx, ny, periodicX, periodicY)) continue;
        const double k = curvature[c];
        if (!isfinite(k)) continue;
        ++countLocal;
        sumLocal += k;
        sqLocal += k*k;
    }
    if (countLocal) atomicAdd(&accum->curvatureCells, countLocal);
    if (sumLocal != 0.0) atomic_add_double_0400(&accum->curvatureSum, sumLocal);
    if (sqLocal != 0.0) atomic_add_double_0400(&accum->curvatureSqSum, sqLocal);
}

__global__ void q6_build_phase_fill_resident_0493x6c(
    CudaSpeciesCellDeviceView0490h species,
    int phaseASelectorKind0493x9g,
    unsigned int phaseASelectorValue0493x9g,
    double phaseAReferenceCellMass0493x9g,
    int phaseBSelectorKind0493x9g,
    unsigned int phaseBSelectorValue0493x9g,
    double* rawFill,
    int n,
    double* gasPressurePotential0493x6g,
    int buildGasPressure0493x6g,
    int gasPressureMode0493x6g,
    double dt0493x6g,
    double kBT0493x6g,
    double cellArea0493x6g,
    double pressureReference0493x6g,
    double constantPressure0493x6g,
    double pressureScale0493x6g) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        rawFill[c] = q6_phase_fill_selector_0493x9g(
            species, c, phaseASelectorKind0493x9g,
            phaseASelectorValue0493x9g, phaseAReferenceCellMass0493x9g);
        if (buildGasPressure0493x6g && gasPressurePotential0493x6g != nullptr) {
            double pressure = constantPressure0493x6g;
            if (gasPressureMode0493x6g == static_cast<int>(PhaseGasPressureMode0493x6g::Eos)) {
                unsigned long long gasCount = 0ull;
                for (int s = 0; s < species.speciesCount; ++s) {
                    if (q6_phase_selector_matches_0493x9g(
                            species, s, phaseBSelectorKind0493x9g,
                            phaseBSelectorValue0493x9g)) {
                        gasCount += static_cast<unsigned long long>(
                            species.count[s * species.numCells + c]);
                    }
                }
                pressure = cellArea0493x6g > 0.0
                    ? static_cast<double>(gasCount) * kBT0493x6g / cellArea0493x6g
                    : 0.0;
            }
            // rho_l,ref = M_l,ref / A_cell.  Store only the gauge-relative
            // pressure potential.  This keeps the matrix independent of p_g
            // and avoids carrying a large uniform ambient pressure through CG.
            gasPressurePotential0493x6g[c] =
                phaseAReferenceCellMass0493x9g > 0.0
                    ? dt0493x6g * pressureScale0493x6g *
                          (pressure - pressureReference0493x6g) * cellArea0493x6g /
                          phaseAReferenceCellMass0493x9g
                    : 0.0;
        }
    }
}

__global__ void q6_filter_phase_fill_conservative_0493x6c(
    const double* rawFill,
    double* alpha,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    double lambda) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;

        // 0493x6f2: rawFill remains the unbounded mass/occupancy diagnostic.
        // Geometry is built from g=clamp(rawFill,0,1) before filtering.
        // For lambda<=1/4 the five-point update is a convex combination of
        // bounded values, hence alpha remains in [0,1] without post-clipping.
        const double center = fmin(1.0, fmax(0.0, rawFill[c]));
        double lap = 0.0;
        if (periodicX || ix > 0) {
            const int xw = periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1;
            const double neighbour = fmin(1.0, fmax(0.0, rawFill[iy * nx + xw]));
            lap += neighbour - center;
        }
        if (periodicX || ix < nx - 1) {
            const int xe = periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1;
            const double neighbour = fmin(1.0, fmax(0.0, rawFill[iy * nx + xe]));
            lap += neighbour - center;
        }
        if (periodicY || iy > 0) {
            const int ys = periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1;
            const double neighbour = fmin(1.0, fmax(0.0, rawFill[ys * nx + ix]));
            lap += neighbour - center;
        }
        if (periodicY || iy < ny - 1) {
            const int yn = periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1;
            const double neighbour = fmin(1.0, fmax(0.0, rawFill[yn * nx + ix]));
            lap += neighbour - center;
        }
        alpha[c] = center + lambda * lap;
    }
}


// 0493x9a outward normal: alpha~1 in liquid and alpha~0 in gas, therefore
// -grad(alpha) points from liquid to gas.  Boundary differencing deliberately
// matches the x6c resident-geometry diagnostic convention.
__global__ void q6_build_phase_normals_0493x9a(
    const double* alpha,
    double* normalX,
    double* normalY,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasWest = periodicX || ix > 0;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasSouth = periodicY || iy > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;
        const double alphaC = alpha[c];
        const double gradX = hasWest && hasEast
            ? (alpha[east] - alpha[west]) / (2.0 * dx)
            : (hasEast ? (alpha[east] - alphaC) / dx
                       : (hasWest ? (alphaC - alpha[west]) / dx : 0.0));
        const double gradY = hasSouth && hasNorth
            ? (alpha[north] - alpha[south]) / (2.0 * dy)
            : (hasNorth ? (alpha[north] - alphaC) / dy
                        : (hasSouth ? (alphaC - alpha[south]) / dy : 0.0));
        const double norm = sqrt(gradX * gradX + gradY * gradY);
        if (norm > 1.0e-14) {
            normalX[c] = -gradX / norm;
            normalY[c] = -gradY / norm;
        } else {
            normalX[c] = 0.0;
            normalY[c] = 0.0;
        }
    }
}

__global__ void q6_build_phase_curvature_0493x9a(
    const double* normalX,
    const double* normalY,
    double* curvature,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasWest = periodicX || ix > 0;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasSouth = periodicY || iy > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;
        const double nxC = normalX[c];
        const double nyC = normalY[c];
        const double dnxDx = hasWest && hasEast
            ? (normalX[east] - normalX[west]) / (2.0 * dx)
            : (hasEast ? (normalX[east] - nxC) / dx
                       : (hasWest ? (nxC - normalX[west]) / dx : 0.0));
        const double dnyDy = hasSouth && hasNorth
            ? (normalY[north] - normalY[south]) / (2.0 * dy)
            : (hasNorth ? (normalY[north] - nyC) / dy
                        : (hasSouth ? (nyC - normalY[south]) / dy : 0.0));
        curvature[c] = dnxDx + dnyDy;
    }
}

// 0493x9b curvature-only alpha filter and rotationally improved 3x3
// derivatives.  Nonperiodic boundaries use constant extension; this field is
// not the physical x6c alpha and therefore cannot move the x6f interface.
__device__ __forceinline__ int q6_phase_index_0493x9b(
    int ix, int iy, int nx, int ny, int periodicX, int periodicY) {
    if (periodicX) ix = wrap_cell_index_0400(ix, nx);
    else ix = max(0, min(nx - 1, ix));
    if (periodicY) iy = wrap_cell_index_0400(iy, ny);
    else iy = max(0, min(ny - 1, iy));
    return iy * nx + ix;
}

__global__ void q6_filter_phase_alpha_curvature_0493x9b(
    const double* alpha, double* alphaK, int nx, int ny,
    int periodicX, int periodicY) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const double nw = alpha[q6_phase_index_0493x9b(ix - 1, iy + 1, nx, ny, periodicX, periodicY)];
        const double nn = alpha[q6_phase_index_0493x9b(ix,     iy + 1, nx, ny, periodicX, periodicY)];
        const double ne = alpha[q6_phase_index_0493x9b(ix + 1, iy + 1, nx, ny, periodicX, periodicY)];
        const double ww = alpha[q6_phase_index_0493x9b(ix - 1, iy,     nx, ny, periodicX, periodicY)];
        const double cc = alpha[c];
        const double ee = alpha[q6_phase_index_0493x9b(ix + 1, iy,     nx, ny, periodicX, periodicY)];
        const double sw = alpha[q6_phase_index_0493x9b(ix - 1, iy - 1, nx, ny, periodicX, periodicY)];
        const double ss = alpha[q6_phase_index_0493x9b(ix,     iy - 1, nx, ny, periodicX, periodicY)];
        const double se = alpha[q6_phase_index_0493x9b(ix + 1, iy - 1, nx, ny, periodicX, periodicY)];
        alphaK[c] = (nw + 2.0 * nn + ne +
                     2.0 * ww + 4.0 * cc + 2.0 * ee +
                     sw + 2.0 * ss + se) * (1.0 / 16.0);
    }
}

__global__ void q6_build_phase_normals_scharr_0493x9b(
    const double* alphaK, double* normalX, double* normalY,
    int nx, int ny, double dx, double dy, int periodicX, int periodicY) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const double nw = alphaK[q6_phase_index_0493x9b(ix - 1, iy + 1, nx, ny, periodicX, periodicY)];
        const double nn = alphaK[q6_phase_index_0493x9b(ix,     iy + 1, nx, ny, periodicX, periodicY)];
        const double ne = alphaK[q6_phase_index_0493x9b(ix + 1, iy + 1, nx, ny, periodicX, periodicY)];
        const double ww = alphaK[q6_phase_index_0493x9b(ix - 1, iy,     nx, ny, periodicX, periodicY)];
        const double ee = alphaK[q6_phase_index_0493x9b(ix + 1, iy,     nx, ny, periodicX, periodicY)];
        const double sw = alphaK[q6_phase_index_0493x9b(ix - 1, iy - 1, nx, ny, periodicX, periodicY)];
        const double ss = alphaK[q6_phase_index_0493x9b(ix,     iy - 1, nx, ny, periodicX, periodicY)];
        const double se = alphaK[q6_phase_index_0493x9b(ix + 1, iy - 1, nx, ny, periodicX, periodicY)];
        const double gradX = (3.0 * (ne - nw) + 10.0 * (ee - ww) +
                              3.0 * (se - sw)) / (32.0 * dx);
        const double gradY = (3.0 * (nw - sw) + 10.0 * (nn - ss) +
                              3.0 * (ne - se)) / (32.0 * dy);
        const double norm = sqrt(gradX * gradX + gradY * gradY);
        if (norm * fmin(dx, dy) > 1.0e-12) {
            normalX[c] = -gradX / norm;
            normalY[c] = -gradY / norm;
        } else {
            normalX[c] = 0.0;
            normalY[c] = 0.0;
        }
    }
}

__global__ void q6_build_phase_curvature_scharr_0493x9b(
    const double* normalX, const double* normalY, double* curvature,
    int nx, int ny, double dx, double dy, int periodicX, int periodicY) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const int nw = q6_phase_index_0493x9b(ix - 1, iy + 1, nx, ny, periodicX, periodicY);
        const int nn = q6_phase_index_0493x9b(ix,     iy + 1, nx, ny, periodicX, periodicY);
        const int ne = q6_phase_index_0493x9b(ix + 1, iy + 1, nx, ny, periodicX, periodicY);
        const int ww = q6_phase_index_0493x9b(ix - 1, iy,     nx, ny, periodicX, periodicY);
        const int ee = q6_phase_index_0493x9b(ix + 1, iy,     nx, ny, periodicX, periodicY);
        const int sw = q6_phase_index_0493x9b(ix - 1, iy - 1, nx, ny, periodicX, periodicY);
        const int ss = q6_phase_index_0493x9b(ix,     iy - 1, nx, ny, periodicX, periodicY);
        const int se = q6_phase_index_0493x9b(ix + 1, iy - 1, nx, ny, periodicX, periodicY);
        const double dnxDx = (3.0 * (normalX[ne] - normalX[nw]) +
                               10.0 * (normalX[ee] - normalX[ww]) +
                               3.0 * (normalX[se] - normalX[sw])) / (32.0 * dx);
        const double dnyDy = (3.0 * (normalY[nw] - normalY[sw]) +
                               10.0 * (normalY[nn] - normalY[ss]) +
                               3.0 * (normalY[ne] - normalY[se])) / (32.0 * dy);
        curvature[c] = dnxDx + dnyDy;
    }
}

constexpr double kPhaseCurvatureAbsScale0493x9a = 1000000.0;

void populate_phase_curvature_region_metrics_0493x9b(
    const PhaseCurvatureAccumulator0493x9a& accum,
    int wallMarginCells,
    PhaseCurvatureAudit0493x9a* audit) {
    if (audit == nullptr) return;
    audit->wallMarginCells = wallMarginCells;
    audit->interiorCrossingFaces =
        static_cast<std::uint64_t>(accum.interiorCrossingFaces);
    audit->interiorValidCurvatureFaces =
        static_cast<std::uint64_t>(accum.interiorValidCurvatureFaces);
    if (accum.interiorValidCurvatureFaces > 0ull) {
        const double inv = 1.0 /
            static_cast<double>(accum.interiorValidCurvatureFaces);
        audit->interiorCurvatureMean = accum.interiorCurvatureSum * inv;
        const double meanSq = accum.interiorCurvatureSqSum * inv;
        audit->interiorCurvatureRms = std::sqrt(std::max(0.0, meanSq));
        audit->interiorCurvatureStd = std::sqrt(std::max(
            0.0, meanSq - audit->interiorCurvatureMean *
                              audit->interiorCurvatureMean));
        audit->interiorCurvatureAbsMean = accum.interiorCurvatureAbsSum * inv;
    }
    audit->interiorCurvatureAbsMax =
        static_cast<double>(accum.interiorCurvatureAbsMaxScaled) /
        kPhaseCurvatureAbsScale0493x9a;

    audit->nearWallCrossingFaces =
        static_cast<std::uint64_t>(accum.nearWallCrossingFaces);
    audit->nearWallValidCurvatureFaces =
        static_cast<std::uint64_t>(accum.nearWallValidCurvatureFaces);
    if (accum.nearWallValidCurvatureFaces > 0ull) {
        const double inv = 1.0 /
            static_cast<double>(accum.nearWallValidCurvatureFaces);
        audit->nearWallCurvatureMean = accum.nearWallCurvatureSum * inv;
        const double meanSq = accum.nearWallCurvatureSqSum * inv;
        audit->nearWallCurvatureRms = std::sqrt(std::max(0.0, meanSq));
        audit->nearWallCurvatureStd = std::sqrt(std::max(
            0.0, meanSq - audit->nearWallCurvatureMean *
                              audit->nearWallCurvatureMean));
        audit->nearWallCurvatureAbsMean = accum.nearWallCurvatureAbsSum * inv;
    }
    audit->nearWallCurvatureAbsMax =
        static_cast<double>(accum.nearWallCurvatureAbsMaxScaled) /
        kPhaseCurvatureAbsScale0493x9a;
}

// Summary-cadence audit only.  Each physical east/north alpha=0.5 crossing is
// visited once.  Curvature is linearly interpolated to the same sub-cell
// interface position theta used by x6f; no x6f buffer is modified here.
__global__ void q6_phase_curvature_face_audit_0493x9a(
    const double* alpha,
    const double* normalX,
    const double* normalY,
    const double* curvature,
    PhaseCurvatureAccumulator0493x9a* accum,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    int wallMarginCells) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;

    unsigned long long crossingLocal = 0ull;
    unsigned long long validLocal = 0ull;
    unsigned long long outwardLocal = 0ull;
    unsigned long long positiveLocal = 0ull;
    unsigned long long negativeLocal = 0ull;
    unsigned long long absMaxScaledLocal = 0ull;
    double alignmentSumLocal = 0.0;
    double kappaSumLocal = 0.0;
    double kappaSqSumLocal = 0.0;
    double kappaAbsSumLocal = 0.0;

    unsigned long long interiorCrossingLocal = 0ull;
    unsigned long long interiorValidLocal = 0ull;
    unsigned long long interiorAbsMaxScaledLocal = 0ull;
    double interiorKappaSumLocal = 0.0;
    double interiorKappaSqSumLocal = 0.0;
    double interiorKappaAbsSumLocal = 0.0;
    unsigned long long nearWallCrossingLocal = 0ull;
    unsigned long long nearWallValidLocal = 0ull;
    unsigned long long nearWallAbsMaxScaledLocal = 0ull;
    double nearWallKappaSumLocal = 0.0;
    double nearWallKappaSqSumLocal = 0.0;
    double nearWallKappaAbsSumLocal = 0.0;

    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const double alphaC = alpha[c];

        int neighbours[2];
        double faceX[2];
        double faceY[2];
        int count = 0;
        if (periodicX || ix < nx - 1) {
            neighbours[count] = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
            faceX[count] = 1.0;
            faceY[count] = 0.0;
            ++count;
        }
        if (periodicY || iy < ny - 1) {
            neighbours[count] =
                (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
            faceX[count] = 0.0;
            faceY[count] = 1.0;
            ++count;
        }

        for (int k = 0; k < count; ++k) {
            const int nb = neighbours[k];
            const double alphaNb = alpha[nb];
            const bool cHigh = alphaC >= 0.5 && alphaNb < 0.5;
            const bool nbHigh = alphaNb >= 0.5 && alphaC < 0.5;
            if (!(cHigh || nbHigh)) continue;
            ++crossingLocal;

            const int high = cHigh ? c : nb;
            const int low = cHigh ? nb : c;
            const int highIx = high % nx;
            const int highIy = high / nx;
            const int lowIx = low % nx;
            const int lowIy = low / nx;
            const bool interiorX = periodicX ||
                (highIx >= wallMarginCells && highIx < nx - wallMarginCells &&
                 lowIx >= wallMarginCells && lowIx < nx - wallMarginCells);
            const bool interiorY = periodicY ||
                (highIy >= wallMarginCells && highIy < ny - wallMarginCells &&
                 lowIy >= wallMarginCells && lowIy < ny - wallMarginCells);
            const bool interiorFace = interiorX && interiorY;
            if (interiorFace) ++interiorCrossingLocal;
            else ++nearWallCrossingLocal;

            const double alphaHigh = alpha[high];
            const double alphaLow = alpha[low];
            const double denom = alphaHigh - alphaLow;
            if (!(denom > 0.0)) continue;
            const double theta = (alphaHigh - 0.5) / denom;
            if (!(theta >= 0.0 && theta <= 1.0)) continue;

            const double oneMinusTheta = 1.0 - theta;
            const double nxFace = oneMinusTheta * normalX[high] + theta * normalX[low];
            const double nyFace = oneMinusTheta * normalY[high] + theta * normalY[low];
            const double nNorm = sqrt(nxFace * nxFace + nyFace * nyFace);
            const double kappa = oneMinusTheta * curvature[high] + theta * curvature[low];
            if (!(nNorm > 0.25) || !isfinite(kappa)) continue;

            const double outwardX = cHigh ? faceX[k] : -faceX[k];
            const double outwardY = cHigh ? faceY[k] : -faceY[k];
            const double alignment = (nxFace * outwardX + nyFace * outwardY) / nNorm;
            ++validLocal;
            if (alignment > 0.0) ++outwardLocal;
            alignmentSumLocal += alignment;
            kappaSumLocal += kappa;
            kappaSqSumLocal += kappa * kappa;
            const double absKappa = fabs(kappa);
            kappaAbsSumLocal += absKappa;
            if (kappa > 0.0) ++positiveLocal;
            if (kappa < 0.0) ++negativeLocal;
            const double capped = fmin(absKappa, 1.0e9);
            const unsigned long long scaled = static_cast<unsigned long long>(
                capped * kPhaseCurvatureAbsScale0493x9a + 0.5);
            absMaxScaledLocal = absMaxScaledLocal > scaled ? absMaxScaledLocal : scaled;

            if (interiorFace) {
                ++interiorValidLocal;
                interiorKappaSumLocal += kappa;
                interiorKappaSqSumLocal += kappa * kappa;
                interiorKappaAbsSumLocal += absKappa;
                interiorAbsMaxScaledLocal = interiorAbsMaxScaledLocal > scaled
                    ? interiorAbsMaxScaledLocal : scaled;
            } else {
                ++nearWallValidLocal;
                nearWallKappaSumLocal += kappa;
                nearWallKappaSqSumLocal += kappa * kappa;
                nearWallKappaAbsSumLocal += absKappa;
                nearWallAbsMaxScaledLocal = nearWallAbsMaxScaledLocal > scaled
                    ? nearWallAbsMaxScaledLocal : scaled;
            }
        }
    }

    if (crossingLocal) atomicAdd(&accum->crossingFaces, crossingLocal);
    if (validLocal) atomicAdd(&accum->validCurvatureFaces, validLocal);
    if (outwardLocal) atomicAdd(&accum->outwardNormalFaces, outwardLocal);
    if (positiveLocal) atomicAdd(&accum->positiveCurvatureFaces, positiveLocal);
    if (negativeLocal) atomicAdd(&accum->negativeCurvatureFaces, negativeLocal);
    if (absMaxScaledLocal) atomicMax(&accum->curvatureAbsMaxScaled, absMaxScaledLocal);
    if (alignmentSumLocal != 0.0) {
        atomic_add_double_0400(&accum->normalFaceAlignmentSum, alignmentSumLocal);
    }
    if (kappaSumLocal != 0.0) {
        atomic_add_double_0400(&accum->curvatureSum, kappaSumLocal);
    }
    if (kappaSqSumLocal != 0.0) {
        atomic_add_double_0400(&accum->curvatureSqSum, kappaSqSumLocal);
    }
    if (kappaAbsSumLocal != 0.0) {
        atomic_add_double_0400(&accum->curvatureAbsSum, kappaAbsSumLocal);
    }

    if (interiorCrossingLocal) atomicAdd(&accum->interiorCrossingFaces, interiorCrossingLocal);
    if (interiorValidLocal) atomicAdd(&accum->interiorValidCurvatureFaces, interiorValidLocal);
    if (interiorAbsMaxScaledLocal) {
        atomicMax(&accum->interiorCurvatureAbsMaxScaled, interiorAbsMaxScaledLocal);
    }
    if (interiorKappaSumLocal != 0.0) {
        atomic_add_double_0400(&accum->interiorCurvatureSum, interiorKappaSumLocal);
    }
    if (interiorKappaSqSumLocal != 0.0) {
        atomic_add_double_0400(&accum->interiorCurvatureSqSum, interiorKappaSqSumLocal);
    }
    if (interiorKappaAbsSumLocal != 0.0) {
        atomic_add_double_0400(&accum->interiorCurvatureAbsSum, interiorKappaAbsSumLocal);
    }

    if (nearWallCrossingLocal) atomicAdd(&accum->nearWallCrossingFaces, nearWallCrossingLocal);
    if (nearWallValidLocal) atomicAdd(&accum->nearWallValidCurvatureFaces, nearWallValidLocal);
    if (nearWallAbsMaxScaledLocal) {
        atomicMax(&accum->nearWallCurvatureAbsMaxScaled, nearWallAbsMaxScaledLocal);
    }
    if (nearWallKappaSumLocal != 0.0) {
        atomic_add_double_0400(&accum->nearWallCurvatureSum, nearWallKappaSumLocal);
    }
    if (nearWallKappaSqSumLocal != 0.0) {
        atomic_add_double_0400(&accum->nearWallCurvatureSqSum, nearWallKappaSqSumLocal);
    }
    if (nearWallKappaAbsSumLocal != 0.0) {
        atomic_add_double_0400(&accum->nearWallCurvatureAbsSum, nearWallKappaAbsSumLocal);
    }
}


__global__ void q6_static_drop_pressure_cells_0493x9e(
    const double* alpha,
    const unsigned char* pressureMask,
    const double* phi,
    const double* gasPressurePotential,
    StaticDropCellAccumulator0493x9e* accum,
    int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    unsigned long long liquidLocal = 0ull;
    unsigned long long gasLocal = 0ull;
    double alphaLocal = 0.0;
    double lSum = 0.0, lSq = 0.0, gSum = 0.0, gSq = 0.0;
    for (int c = idx; c < n; c += stride) {
        const double a = fmin(1.0, fmax(0.0, alpha[c]));
        alphaLocal += a;
        if (a >= 0.9 && pressureMask[c] != 0u) {
            const double v = phi[c];
            if (isfinite(v)) {
                ++liquidLocal;
                lSum += v;
                lSq += v * v;
            }
        }
        if (a <= 0.1 && gasPressurePotential != nullptr) {
            const double v = gasPressurePotential[c];
            if (isfinite(v)) {
                ++gasLocal;
                gSum += v;
                gSq += v * v;
            }
        }
    }
    if (liquidLocal) atomicAdd(&accum->deepLiquidCells, liquidLocal);
    if (gasLocal) atomicAdd(&accum->deepGasCells, gasLocal);
    if (alphaLocal != 0.0) atomic_add_double_0400(&accum->alphaSum, alphaLocal);
    if (lSum != 0.0) atomic_add_double_0400(&accum->liquidPhiSum, lSum);
    if (lSq != 0.0) atomic_add_double_0400(&accum->liquidPhiSqSum, lSq);
    if (gSum != 0.0) atomic_add_double_0400(&accum->gasPhiSum, gSum);
    if (gSq != 0.0) atomic_add_double_0400(&accum->gasPhiSqSum, gSq);
}

__global__ void q6_static_drop_capillary_resultant_0493x9e(
    const double* alpha,
    const double* curvature,
    StaticDropFaceAccumulator0493x9e* accum,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    unsigned long long crossingLocal = 0ull, validLocal = 0ull;
    double kSum = 0.0, kSq = 0.0, fx = 0.0, fy = 0.0, absT = 0.0, measure = 0.0;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const double aC = alpha[c];
        int nb[2];
        double nxAxis[2], nyAxis[2], faceMeasure[2];
        int count = 0;
        if (periodicX || ix < nx - 1) {
            nb[count] = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
            nxAxis[count] = 1.0; nyAxis[count] = 0.0; faceMeasure[count] = dy; ++count;
        }
        if (periodicY || iy < ny - 1) {
            nb[count] = (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
            nxAxis[count] = 0.0; nyAxis[count] = 1.0; faceMeasure[count] = dx; ++count;
        }
        for (int j = 0; j < count; ++j) {
            const int b = nb[j];
            const double aB = alpha[b];
            const bool cHigh = aC >= 0.5 && aB < 0.5;
            const bool bHigh = aB >= 0.5 && aC < 0.5;
            if (!(cHigh || bHigh)) continue;
            ++crossingLocal;
            const int high = cHigh ? c : b;
            const int low = cHigh ? b : c;
            const double denom = alpha[high] - alpha[low];
            if (!(denom > 0.0)) continue;
            const double theta = (alpha[high] - 0.5) / denom;
            if (!(theta >= 0.0 && theta <= 1.0)) continue;
            const double kappa = (1.0 - theta) * curvature[high] + theta * curvature[low];
            if (!isfinite(kappa)) continue;
            const double ox = cHigh ? nxAxis[j] : -nxAxis[j];
            const double oy = cHigh ? nyAxis[j] : -nyAxis[j];
            const double dsAxis = faceMeasure[j];
            ++validLocal;
            kSum += kappa;
            kSq += kappa * kappa;
            fx += kappa * ox * dsAxis;
            fy += kappa * oy * dsAxis;
            absT += fabs(kappa) * dsAxis;
            measure += dsAxis;
        }
    }
    if (crossingLocal) atomicAdd(&accum->crossingFaces, crossingLocal);
    if (validLocal) atomicAdd(&accum->validFaces, validLocal);
    if (kSum != 0.0) atomic_add_double_0400(&accum->curvatureSum, kSum);
    if (kSq != 0.0) atomic_add_double_0400(&accum->curvatureSqSum, kSq);
    if (fx != 0.0) atomic_add_double_0400(&accum->discreteResultantX, fx);
    if (fy != 0.0) atomic_add_double_0400(&accum->discreteResultantY, fy);
    if (absT != 0.0) atomic_add_double_0400(&accum->discreteAbsTraction, absT);
    if (measure != 0.0) atomic_add_double_0400(&accum->axisBoundaryMeasure, measure);
}

__device__ __forceinline__ bool q6_cell_adjacent_to_alpha05_crossing_0493x9f(
    const double* alpha, int c, int nx, int ny, int periodicX, int periodicY) {
    const int ix = c % nx;
    const int iy = c / nx;
    const bool high = alpha[c] >= 0.5;
    if (periodicX || ix > 0) {
        const int jx = periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1;
        if ((alpha[iy * nx + jx] >= 0.5) != high) return true;
    }
    if (periodicX || ix < nx - 1) {
        const int jx = periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1;
        if ((alpha[iy * nx + jx] >= 0.5) != high) return true;
    }
    if (periodicY || iy > 0) {
        const int jy = periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1;
        if ((alpha[jy * nx + ix] >= 0.5) != high) return true;
    }
    if (periodicY || iy < ny - 1) {
        const int jy = periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1;
        if ((alpha[jy * nx + ix] >= 0.5) != high) return true;
    }
    return false;
}

__global__ void q6_ellipse_particle_moments_0493x9f(
    CudaParticleDeviceView particles,
    std::uint64_t nParticles,
    std::uint32_t liquidType,
    EllipseParticleMomentAccumulator0493x9f* accum) {
    const std::uint64_t idx = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    unsigned long long count = 0ull;
    double sm=0.0,sx=0.0,sy=0.0,sxx=0.0,syy=0.0,sxy=0.0;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.type == nullptr || particles.type[i] != liquidType) continue;
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) continue;
        const double mass = particles.mass ? particles.mass[i] : 1.0;
        const double x = particles.x[i];
        const double y = particles.y[i];
        if (!(mass > 0.0) || !isfinite(mass) || !isfinite(x) || !isfinite(y)) continue;
        ++count;
        sm += mass;
        sx += mass * x;
        sy += mass * y;
        sxx += mass * x * x;
        syy += mass * y * y;
        sxy += mass * x * y;
    }
    if (count) atomicAdd(&accum->particles, count);
    if (sm!=0.0) atomic_add_double_0400(&accum->massSum, sm);
    if (sx!=0.0) atomic_add_double_0400(&accum->massXSum, sx);
    if (sy!=0.0) atomic_add_double_0400(&accum->massYSum, sy);
    if (sxx!=0.0) atomic_add_double_0400(&accum->massXXSum, sxx);
    if (syy!=0.0) atomic_add_double_0400(&accum->massYYSum, syy);
    if (sxy!=0.0) atomic_add_double_0400(&accum->massXYSum, sxy);
}

__global__ void q6_ellipse_interface_radii_0493x9f(
    const double* alpha,
    double xcm,
    double ycm,
    EllipseInterfaceRadiusAccumulator0493x9f* accum,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY) {
    constexpr double radiusScale = 1000000000.0;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    unsigned long long count=0ull,rmin=~0ull,rmax=0ull;
    double rsum=0.0,rsq=0.0;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const double aC = alpha[c];
        const double xC = (static_cast<double>(ix) + 0.5) * dx;
        const double yC = (static_cast<double>(iy) + 0.5) * dy;
        // Diagnostic shape runner uses a closed box.  Periodic neighbours are
        // supported algebraically, but droplets spanning a periodic seam need
        // an unwrapped COM and are outside this x9f qualification contract.
        if (periodicX || ix < nx - 1) {
            const int jx = periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1;
            const int b = iy * nx + jx;
            const double aB = alpha[b];
            const bool cHigh = aC >= 0.5 && aB < 0.5;
            const bool bHigh = aB >= 0.5 && aC < 0.5;
            if (cHigh || bHigh) {
                const int high = cHigh ? c : b;
                const int low = cHigh ? b : c;
                const double denom = alpha[high] - alpha[low];
                if (denom > 0.0) {
                    const double theta = (alpha[high] - 0.5) / denom;
                    if (theta >= 0.0 && theta <= 1.0) {
                        const double xB = (static_cast<double>(jx) + 0.5) * dx;
                        const double xH = cHigh ? xC : xB;
                        const double xL = cHigh ? xB : xC;
                        const double xp = (1.0 - theta) * xH + theta * xL;
                        const double rp = hypot(xp - xcm, yC - ycm);
                        if (isfinite(rp)) {
                            const unsigned long long rr = static_cast<unsigned long long>(
                                fmin(rp, 1.0e6) * radiusScale + 0.5);
                            ++count; rsum += rp; rsq += rp*rp;
                            rmin = rmin < rr ? rmin : rr; rmax = rmax > rr ? rmax : rr;
                        }
                    }
                }
            }
        }
        if (periodicY || iy < ny - 1) {
            const int jy = periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1;
            const int b = jy * nx + ix;
            const double aB = alpha[b];
            const bool cHigh = aC >= 0.5 && aB < 0.5;
            const bool bHigh = aB >= 0.5 && aC < 0.5;
            if (cHigh || bHigh) {
                const int high = cHigh ? c : b;
                const int low = cHigh ? b : c;
                const double denom = alpha[high] - alpha[low];
                if (denom > 0.0) {
                    const double theta = (alpha[high] - 0.5) / denom;
                    if (theta >= 0.0 && theta <= 1.0) {
                        const double yB = (static_cast<double>(jy) + 0.5) * dy;
                        const double yH = cHigh ? yC : yB;
                        const double yL = cHigh ? yB : yC;
                        const double yp = (1.0 - theta) * yH + theta * yL;
                        const double rp = hypot(xC - xcm, yp - ycm);
                        if (isfinite(rp)) {
                            const unsigned long long rr = static_cast<unsigned long long>(
                                fmin(rp, 1.0e6) * radiusScale + 0.5);
                            ++count; rsum += rp; rsq += rp*rp;
                            rmin = rmin < rr ? rmin : rr; rmax = rmax > rr ? rmax : rr;
                        }
                    }
                }
            }
        }
    }
    if (count) atomicAdd(&accum->crossingPoints,count);
    if (count) atomicMin(&accum->radiusMinScaled,rmin);
    if (rmax) atomicMax(&accum->radiusMaxScaled,rmax);
    if (rsum!=0.0) atomic_add_double_0400(&accum->radiusSum,rsum);
    if (rsq!=0.0) atomic_add_double_0400(&accum->radiusSqSum,rsq);
}

__global__ void q6_static_drop_velocity_cells_0493x9e(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const double* alpha,
    StaticDropVelocityAccumulator0493x9e* accum,
    int nx,
    int ny,
    int periodicX,
    int periodicY) {
    const int n = nx * ny;
    constexpr double speedScale = 1000000000.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    unsigned long long nL=0ull,nC=0ull,nI=0ull,mL=0ull,mC=0ull,mI=0ull;
    double lx=0.0,ly=0.0,ls=0.0,cx=0.0,cy=0.0,cs=0.0,ixs=0.0,iys=0.0,is=0.0;
    for (int c = idx; c < n; c += stride) {
        const int sk = speciesIndex * species.numCells + c;
        const double m = species.mass[sk];
        if (!(m > 0.0)) continue;
        const double vx = species.px[sk] / m;
        const double vy = species.py[sk] / m;
        if (!isfinite(vx) || !isfinite(vy)) continue;
        const double speedSq = vx * vx + vy * vy;
        const double speed = sqrt(speedSq);
        const unsigned long long scaled = static_cast<unsigned long long>(
            fmin(speed, 1.0e6) * speedScale + 0.5);
        const double a = fmin(1.0, fmax(0.0, alpha[c]));
        if (a >= 0.5) {
            ++nL; lx += vx; ly += vy; ls += speedSq; mL = mL > scaled ? mL : scaled;
        }
        if (a >= 0.9) {
            ++nC; cx += vx; cy += vy; cs += speedSq; mC = mC > scaled ? mC : scaled;
        }
        // 0493x9f: a true interface cell is adjacent to at least one grid
        // face whose two x6c alpha values straddle alpha=0.5.  This replaces
        // the old 0.1<=alpha<=0.9 occupancy band, which admitted bulk cells.
        if (q6_cell_adjacent_to_alpha05_crossing_0493x9f(
                alpha, c, nx, ny, periodicX, periodicY)) {
            ++nI; ixs += vx; iys += vy; is += speedSq; mI = mI > scaled ? mI : scaled;
        }
    }
    if (nL) atomicAdd(&accum->liquidCells,nL);
    if (nC) atomicAdd(&accum->coreCells,nC);
    if (nI) atomicAdd(&accum->interfaceCells,nI);
    if (mL) atomicMax(&accum->liquidSpeedMaxScaled,mL);
    if (mC) atomicMax(&accum->coreSpeedMaxScaled,mC);
    if (mI) atomicMax(&accum->interfaceSpeedMaxScaled,mI);
    if (lx!=0.0) atomic_add_double_0400(&accum->liquidVxSum,lx);
    if (ly!=0.0) atomic_add_double_0400(&accum->liquidVySum,ly);
    if (ls!=0.0) atomic_add_double_0400(&accum->liquidSpeedSqSum,ls);
    if (cx!=0.0) atomic_add_double_0400(&accum->coreVxSum,cx);
    if (cy!=0.0) atomic_add_double_0400(&accum->coreVySum,cy);
    if (cs!=0.0) atomic_add_double_0400(&accum->coreSpeedSqSum,cs);
    if (ixs!=0.0) atomic_add_double_0400(&accum->interfaceVxSum,ixs);
    if (iys!=0.0) atomic_add_double_0400(&accum->interfaceVySum,iys);
    if (is!=0.0) atomic_add_double_0400(&accum->interfaceSpeedSqSum,is);
}

__global__ void q6_prepare_phase_interface_stencil_0493x6f(
    const unsigned char* carrierMask,
    const double* alpha,
    unsigned char* pressureMask,
    double* faceCoeffX,
    double* faceCoeffY,
    const double* gasPressurePotential0493x6g,
    const double* capillaryCurvature0493x9d,
    double capillaryPotentialScale0493x9d,
    double capillaryKappaMax0493x9r,
    double* facePhiGammaX0493x6g,
    double* facePhiGammaY0493x6g,
    int useGasPressure0493x6g,
    int useSurfaceTension0493x9d,
    int usePhaseInterface0493x7m,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    double thetaMinGuard,
    unsigned long long* activeCounter,
    PhaseInterfaceStencilAccumulator0493x6f* accum,
    int auditEnabled) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;

    unsigned long long activeLocal = 0ull;
    unsigned long long interiorLocal = 0ull;
    unsigned long long representedLocal = 0ull;
    unsigned long long smallThetaLocal = 0ull;
    unsigned long long truncationLocal = 0ull;
    unsigned long long uncoveredLocal = 0ull;
    unsigned long long nonzeroPressureLocal0493x6g = 0ull;
    unsigned long long capillaryFacesLocal0493x9r = 0ull;
    unsigned long long capillaryClippedLocal0493x9r = 0ull;
    double capillaryKappaRawAbsMaxLocal0493x9r = 0.0;
    double capillaryKappaEffectiveAbsMaxLocal0493x9r = 0.0;
    double thetaMinLocal = 1.0;
    double thetaMaxLocal = 0.0;
    double thetaSumLocal = 0.0;
    double pressurePotentialSumLocal0493x6g = 0.0;
    double pressurePotentialSqSumLocal0493x6g = 0.0;

    for (int c = idx; c < n; c += stride) {
        const double alphaC = alpha[c];
        // 0493x7m-fix1: alpha=0.5 is a phase boundary only when the registry
        // actually contains a gas phase. In an explicitly monophase liquid
        // registry the pressure domain is the full computational grid:
        // particle-density fluctuations or transient empty carrier cells are
        // sampling defects, not physical pressure boundaries.
        const bool pressureC =
            !usePhaseInterface0493x7m ||
            (carrierMask[c] != 0u && alphaC >= 0.5);
        pressureMask[c] = pressureC ? 1u : 0u;
        if (pressureC) ++activeLocal;

        const int ix = c % nx;
        const int iy = c / nx;

        // Each stored coefficient owns one unique east/north face.  External
        // non-periodic domain faces are intentionally left at zero here: the
        // existing wall/open-boundary path continues to classify them.
        double coeffX = 0.0;
        double phiGammaX0493x6g = 0.0;
        if (periodicX || ix < nx - 1) {
            const int east = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
            const double alphaE = alpha[east];
            const bool pressureE =
                !usePhaseInterface0493x7m ||
                (carrierMask[east] != 0u && alphaE >= 0.5);
            const bool cHigh = alphaC >= 0.5 && alphaE < 0.5;
            const bool eHigh = alphaE >= 0.5 && alphaC < 0.5;
            const bool crossing =
                usePhaseInterface0493x7m && (cHigh || eHigh);
            if (pressureC && pressureE) {
                coeffX = 1.0;
                if (auditEnabled) ++interiorLocal;
            } else if (pressureC || pressureE) {
                if (crossing) {
                    const double alphaHigh = cHigh ? alphaC : alphaE;
                    const double alphaLow = cHigh ? alphaE : alphaC;
                    const int gasSideCell = cHigh ? east : c;
                    const double denom = alphaHigh - alphaLow;
                    if (denom > 0.0) {
                        const double theta = (alphaHigh - 0.5) / denom;
                        coeffX = theta >= thetaMinGuard ? 1.0 / theta : 2.0;
                        double gasPhiGammaX0493x6g = 0.0;
                        if (useGasPressure0493x6g && gasPressurePotential0493x6g != nullptr) {
                            // First-order exterior trace: use the alpha<0.5
                            // cell value.  It remains well-defined for AA and
                            // AI carrier topologies and does not dilute p_g
                            // with the liquid-side cell where gas may be absent.
                            gasPhiGammaX0493x6g = gasPressurePotential0493x6g[gasSideCell];
                            phiGammaX0493x6g += gasPhiGammaX0493x6g;
                        }
                        if (useSurfaceTension0493x9d && capillaryCurvature0493x9d != nullptr) {
                            const int highCell = cHigh ? c : east;
                            const int lowCell = cHigh ? east : c;
                            const double kappaGammaRaw0493x9r =
                                (1.0 - theta) * capillaryCurvature0493x9d[highCell] +
                                theta * capillaryCurvature0493x9d[lowCell];
                            if (isfinite(kappaGammaRaw0493x9r)) {
                                double kappaGammaEffective0493x9r = kappaGammaRaw0493x9r;
                                bool clipped0493x9r = false;
                                if (capillaryKappaMax0493x9r > 0.0 &&
                                    fabs(kappaGammaRaw0493x9r) > capillaryKappaMax0493x9r) {
                                    kappaGammaEffective0493x9r = copysign(
                                        capillaryKappaMax0493x9r, kappaGammaRaw0493x9r);
                                    clipped0493x9r = true;
                                }
                                phiGammaX0493x6g += capillaryPotentialScale0493x9d *
                                    kappaGammaEffective0493x9r;
                                if (auditEnabled) {
                                    ++capillaryFacesLocal0493x9r;
                                    if (clipped0493x9r) ++capillaryClippedLocal0493x9r;
                                    capillaryKappaRawAbsMaxLocal0493x9r = fmax(
                                        capillaryKappaRawAbsMaxLocal0493x9r,
                                        fabs(kappaGammaRaw0493x9r));
                                    capillaryKappaEffectiveAbsMaxLocal0493x9r = fmax(
                                        capillaryKappaEffectiveAbsMaxLocal0493x9r,
                                        fabs(kappaGammaEffective0493x9r));
                                }
                            }
                        }
                        if (auditEnabled) {
                            ++representedLocal;
                            if (theta < thetaMinGuard) ++smallThetaLocal;
                            thetaMinLocal = fmin(thetaMinLocal, theta);
                            thetaMaxLocal = fmax(thetaMaxLocal, theta);
                            thetaSumLocal += theta;
                            if (useGasPressure0493x6g) {
                                if (fabs(gasPhiGammaX0493x6g) > 0.0) {
                                    ++nonzeroPressureLocal0493x6g;
                                }
                                pressurePotentialSumLocal0493x6g += gasPhiGammaX0493x6g;
                                pressurePotentialSqSumLocal0493x6g +=
                                    gasPhiGammaX0493x6g * gasPhiGammaX0493x6g;
                            }
                        }
                    }
                } else {
                    // The alpha-defined liquid continues across this face but
                    // the numerical carrier has ended.  Do not turn that
                    // carrier loss into an artificial p=0 interface.
                    coeffX = 0.0;
                    if (auditEnabled) ++truncationLocal;
                }
            } else if (crossing && auditEnabled) {
                // The physical interface lies outside the available carrier.
                // This is an explicit support-coverage diagnostic, not a
                // pressure boundary silently invented by the solver.
                ++uncoveredLocal;
            }
        }
        faceCoeffX[c] = coeffX;
        if (facePhiGammaX0493x6g != nullptr) facePhiGammaX0493x6g[c] = phiGammaX0493x6g;

        double coeffY = 0.0;
        double phiGammaY0493x6g = 0.0;
        if (periodicY || iy < ny - 1) {
            const int north =
                (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
            const double alphaN = alpha[north];
            const bool pressureN =
                !usePhaseInterface0493x7m ||
                (carrierMask[north] != 0u && alphaN >= 0.5);
            const bool cHigh = alphaC >= 0.5 && alphaN < 0.5;
            const bool nHigh = alphaN >= 0.5 && alphaC < 0.5;
            const bool crossing =
                usePhaseInterface0493x7m && (cHigh || nHigh);
            if (pressureC && pressureN) {
                coeffY = 1.0;
                if (auditEnabled) ++interiorLocal;
            } else if (pressureC || pressureN) {
                if (crossing) {
                    const double alphaHigh = cHigh ? alphaC : alphaN;
                    const double alphaLow = cHigh ? alphaN : alphaC;
                    const int gasSideCell = cHigh ? north : c;
                    const double denom = alphaHigh - alphaLow;
                    if (denom > 0.0) {
                        const double theta = (alphaHigh - 0.5) / denom;
                        coeffY = theta >= thetaMinGuard ? 1.0 / theta : 2.0;
                        double gasPhiGammaY0493x6g = 0.0;
                        if (useGasPressure0493x6g && gasPressurePotential0493x6g != nullptr) {
                            gasPhiGammaY0493x6g = gasPressurePotential0493x6g[gasSideCell];
                            phiGammaY0493x6g += gasPhiGammaY0493x6g;
                        }
                        if (useSurfaceTension0493x9d && capillaryCurvature0493x9d != nullptr) {
                            const int highCell = cHigh ? c : north;
                            const int lowCell = cHigh ? north : c;
                            const double kappaGammaRaw0493x9r =
                                (1.0 - theta) * capillaryCurvature0493x9d[highCell] +
                                theta * capillaryCurvature0493x9d[lowCell];
                            if (isfinite(kappaGammaRaw0493x9r)) {
                                double kappaGammaEffective0493x9r = kappaGammaRaw0493x9r;
                                bool clipped0493x9r = false;
                                if (capillaryKappaMax0493x9r > 0.0 &&
                                    fabs(kappaGammaRaw0493x9r) > capillaryKappaMax0493x9r) {
                                    kappaGammaEffective0493x9r = copysign(
                                        capillaryKappaMax0493x9r, kappaGammaRaw0493x9r);
                                    clipped0493x9r = true;
                                }
                                phiGammaY0493x6g += capillaryPotentialScale0493x9d *
                                    kappaGammaEffective0493x9r;
                                if (auditEnabled) {
                                    ++capillaryFacesLocal0493x9r;
                                    if (clipped0493x9r) ++capillaryClippedLocal0493x9r;
                                    capillaryKappaRawAbsMaxLocal0493x9r = fmax(
                                        capillaryKappaRawAbsMaxLocal0493x9r,
                                        fabs(kappaGammaRaw0493x9r));
                                    capillaryKappaEffectiveAbsMaxLocal0493x9r = fmax(
                                        capillaryKappaEffectiveAbsMaxLocal0493x9r,
                                        fabs(kappaGammaEffective0493x9r));
                                }
                            }
                        }
                        if (auditEnabled) {
                            ++representedLocal;
                            if (theta < thetaMinGuard) ++smallThetaLocal;
                            thetaMinLocal = fmin(thetaMinLocal, theta);
                            thetaMaxLocal = fmax(thetaMaxLocal, theta);
                            thetaSumLocal += theta;
                            if (useGasPressure0493x6g) {
                                if (fabs(gasPhiGammaY0493x6g) > 0.0) {
                                    ++nonzeroPressureLocal0493x6g;
                                }
                                pressurePotentialSumLocal0493x6g += gasPhiGammaY0493x6g;
                                pressurePotentialSqSumLocal0493x6g +=
                                    gasPhiGammaY0493x6g * gasPhiGammaY0493x6g;
                            }
                        }
                    }
                } else {
                    coeffY = 0.0;
                    if (auditEnabled) ++truncationLocal;
                }
            } else if (crossing && auditEnabled) {
                ++uncoveredLocal;
            }
        }
        faceCoeffY[c] = coeffY;
        if (facePhiGammaY0493x6g != nullptr) facePhiGammaY0493x6g[c] = phiGammaY0493x6g;
    }

    if (activeLocal) atomicAdd(activeCounter, activeLocal);
    if (!auditEnabled) return;
    if (activeLocal) atomicAdd(&accum->pressureActiveCells, activeLocal);
    if (interiorLocal) atomicAdd(&accum->interiorPressureFaces, interiorLocal);
    if (representedLocal) {
        atomicAdd(&accum->representedInterfaceFaces, representedLocal);
        constexpr double kThetaScale0493x6f = 1000000000.0;
        const auto maxScaled = static_cast<unsigned long long>(
            fmin(1.0, fmax(0.0, thetaMaxLocal)) * kThetaScale0493x6f + 0.5);
        const auto minComplementScaled = static_cast<unsigned long long>(
            (1.0 - fmin(1.0, fmax(0.0, thetaMinLocal))) *
                kThetaScale0493x6f + 0.5);
        atomicMax(&accum->thetaMaxScaled, maxScaled);
        atomicMax(&accum->thetaMinComplementScaled, minComplementScaled);
        atomic_add_double_0400(&accum->thetaSum, thetaSumLocal);
    }
    if (smallThetaLocal) {
        atomicAdd(&accum->smallThetaStabilizedFaces, smallThetaLocal);
    }
    if (truncationLocal) {
        atomicAdd(&accum->carrierTruncationFaces, truncationLocal);
    }
    if (uncoveredLocal) {
        atomicAdd(&accum->uncoveredInterfaceFaces, uncoveredLocal);
    }
    if (nonzeroPressureLocal0493x6g) {
        atomicAdd(&accum->nonzeroPressureFaces0493x6g, nonzeroPressureLocal0493x6g);
    }
    if (capillaryFacesLocal0493x9r) {
        atomicAdd(&accum->capillaryFaces0493x9r, capillaryFacesLocal0493x9r);
        if (capillaryClippedLocal0493x9r) {
            atomicAdd(&accum->capillaryClippedFaces0493x9r, capillaryClippedLocal0493x9r);
        }
        constexpr double kKappaScale0493x9r = 1000000.0;
        const auto rawMaxScaled0493x9r = static_cast<unsigned long long>(
            fmin(1.0e12, capillaryKappaRawAbsMaxLocal0493x9r) * kKappaScale0493x9r + 0.5);
        const auto effectiveMaxScaled0493x9r = static_cast<unsigned long long>(
            fmin(1.0e12, capillaryKappaEffectiveAbsMaxLocal0493x9r) * kKappaScale0493x9r + 0.5);
        atomicMax(&accum->capillaryKappaRawAbsMaxScaled0493x9r, rawMaxScaled0493x9r);
        atomicMax(&accum->capillaryKappaEffectiveAbsMaxScaled0493x9r, effectiveMaxScaled0493x9r);
    }
    if (pressurePotentialSumLocal0493x6g != 0.0) {
        atomic_add_double_0400(&accum->pressurePotentialSum0493x6g,
                               pressurePotentialSumLocal0493x6g);
    }
    if (pressurePotentialSqSumLocal0493x6g != 0.0) {
        atomic_add_double_0400(&accum->pressurePotentialSqSum0493x6g,
                               pressurePotentialSqSumLocal0493x6g);
    }
}

__global__ void q6_phase_geometry_resident_audit_0493x6c(
    const double* rawFill,
    const double* alpha,
    const unsigned char* liquidMask,
    double supportIsoFill,
    PhaseGeometryResidentAccumulator0493x6c* accum,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    int phaseInterfaceTopologyEnabled,
    double cutFaceThetaMinGuard) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;

    unsigned long long mismatchLocal = 0ull;
    unsigned long long facesLocal = 0ull;
    unsigned long long halfBracketLocal = 0ull;
    unsigned long long normalValidLocal = 0ull;
    unsigned long long normalOutwardLocal = 0ull;
    unsigned long long cutFaceGeometricLocal = 0ull;
    unsigned long long cutFaceSmallThetaFallbackLocal = 0ull;
    unsigned long long alphaHalfCrossingLocal = 0ull;
    unsigned long long alphaHalfActiveActiveLocal = 0ull;
    unsigned long long alphaHalfActiveInactiveLocal = 0ull;
    unsigned long long alphaHalfInactiveInactiveLocal = 0ull;
    unsigned long long alphaHalfAIActiveLiquidSideLocal = 0ull;
    unsigned long long alphaHalfAIActiveExteriorSideLocal = 0ull;
    double alphaHalfThetaMinLocal = 1.0;
    double alphaHalfThetaMaxLocal = 0.0;
    double alphaHalfThetaSumLocal = 0.0;
    double alphaHalfThetaSqSumLocal = 0.0;
    double cutFaceThetaMinLocal = 1.0;
    double cutFaceThetaMaxLocal = 0.0;
    double cutFaceThetaSumLocal = 0.0;
    unsigned long long boundedGeometryClippedLocal = 0ull;
    double rawSumLocal = 0.0;
    double boundedGeometrySumLocal = 0.0;
    double alphaSumLocal = 0.0;
    double deltaSqLocal = 0.0;
    double halfThetaSumLocal = 0.0;
    double halfThetaSqLocal = 0.0;
    double normalDotSumLocal = 0.0;

    for (int c = idx; c < n; c += stride) {
        const double rawC = rawFill[c];
        const double geometryC = fmin(1.0, fmax(0.0, rawC));
        const double alphaC = alpha[c];
        rawSumLocal += rawC;
        boundedGeometrySumLocal += geometryC;
        if (geometryC != rawC) ++boundedGeometryClippedLocal;
        alphaSumLocal += alphaC;
        const double delta = alphaC - geometryC;
        deltaSqLocal += delta * delta;
        const bool maskActive = liquidMask[c] != 0u;
        const bool filteredActive = alphaC >= supportIsoFill;
        if (maskActive != filteredActive) ++mismatchLocal;

        const int ix = c % nx;
        const int iy = c / nx;

        // x6e scans each physical grid face exactly once (east and north only),
        // independently of the carrier-mask boundary.  The high-alpha side is
        // the liquid side for theta, so theta is always measured from liquid
        // cell center toward the exterior cell center.
        if (phaseInterfaceTopologyEnabled) {
            int topologyNeighbours[2];
            int topologyCount = 0;
            if (periodicX || ix < nx - 1) {
                topologyNeighbours[topologyCount++] = iy * nx +
                    (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
            }
            if (periodicY || iy < ny - 1) {
                topologyNeighbours[topologyCount++] =
                    (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
            }
            for (int tk = 0; tk < topologyCount; ++tk) {
                const int nb = topologyNeighbours[tk];
                const double alphaNb = alpha[nb];
                const bool cLiquidSide = alphaC >= 0.5 && alphaNb < 0.5;
                const bool nbLiquidSide = alphaNb >= 0.5 && alphaC < 0.5;
                if (!(cLiquidSide || nbLiquidSide)) continue;

                ++alphaHalfCrossingLocal;
                const bool maskNb = liquidMask[nb] != 0u;
                if (maskActive && maskNb) {
                    ++alphaHalfActiveActiveLocal;
                } else if (maskActive || maskNb) {
                    ++alphaHalfActiveInactiveLocal;
                    const bool liquidSideActive = cLiquidSide ? maskActive : maskNb;
                    if (liquidSideActive) {
                        ++alphaHalfAIActiveLiquidSideLocal;
                    } else {
                        ++alphaHalfAIActiveExteriorSideLocal;
                    }
                } else {
                    ++alphaHalfInactiveInactiveLocal;
                }

                const double alphaHigh = cLiquidSide ? alphaC : alphaNb;
                const double alphaLow = cLiquidSide ? alphaNb : alphaC;
                const double denomHalf = alphaHigh - alphaLow;
                if (denomHalf > 1.0e-14) {
                    const double thetaHalf = (alphaHigh - 0.5) / denomHalf;
                    alphaHalfThetaMinLocal = fmin(alphaHalfThetaMinLocal, thetaHalf);
                    alphaHalfThetaMaxLocal = fmax(alphaHalfThetaMaxLocal, thetaHalf);
                    alphaHalfThetaSumLocal += thetaHalf;
                    alphaHalfThetaSqSumLocal += thetaHalf * thetaHalf;
                }
            }
        }

        if (!maskActive) continue;

        const bool hasWest = periodicX || ix > 0;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasSouth = periodicY || iy > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;

        const double alphaW = hasWest ? alpha[west] : alphaC;
        const double alphaE = hasEast ? alpha[east] : alphaC;
        const double alphaS = hasSouth ? alpha[south] : alphaC;
        const double alphaN = hasNorth ? alpha[north] : alphaC;
        const double gradX = hasWest && hasEast
            ? (alphaE - alphaW) / (2.0 * dx)
            : (hasEast ? (alphaE - alphaC) / dx
                       : (hasWest ? (alphaC - alphaW) / dx : 0.0));
        const double gradY = hasSouth && hasNorth
            ? (alphaN - alphaS) / (2.0 * dy)
            : (hasNorth ? (alphaN - alphaC) / dy
                        : (hasSouth ? (alphaC - alphaS) / dy : 0.0));
        const double gradNorm = sqrt(gradX * gradX + gradY * gradY);
        const bool normalValid = gradNorm > 1.0e-14;
        const double nxOut = normalValid ? -gradX / gradNorm : 0.0;
        const double nyOut = normalValid ? -gradY / gradNorm : 0.0;

        int neighbours[4];
        double faceNx[4];
        double faceNy[4];
        int count = 0;
        if (hasWest) {
            neighbours[count] = west; faceNx[count] = -1.0; faceNy[count] = 0.0; ++count;
        }
        if (hasEast) {
            neighbours[count] = east; faceNx[count] = 1.0; faceNy[count] = 0.0; ++count;
        }
        if (hasSouth) {
            neighbours[count] = south; faceNx[count] = 0.0; faceNy[count] = -1.0; ++count;
        }
        if (hasNorth) {
            neighbours[count] = north; faceNx[count] = 0.0; faceNy[count] = 1.0; ++count;
        }

        for (int k = 0; k < count; ++k) {
            const int nb = neighbours[k];
            if (liquidMask[nb] != 0u) continue;
            ++facesLocal;
            const double alphaNb = alpha[nb];
            const double denom = alphaC - alphaNb;
            if (denom > 1.0e-14 && alphaC >= 0.5 && alphaNb < 0.5) {
                const double theta = (alphaC - 0.5) / denom;
                if (theta >= 0.0 && theta <= 1.0) {
                    ++halfBracketLocal;
                    halfThetaSumLocal += theta;
                    halfThetaSqLocal += theta * theta;
                    if (theta >= cutFaceThetaMinGuard) {
                        ++cutFaceGeometricLocal;
                        cutFaceThetaMinLocal = fmin(cutFaceThetaMinLocal, theta);
                        cutFaceThetaMaxLocal = fmax(cutFaceThetaMaxLocal, theta);
                        cutFaceThetaSumLocal += theta;
                    } else {
                        ++cutFaceSmallThetaFallbackLocal;
                    }
                }
            }
            if (normalValid) {
                const double alignment = nxOut * faceNx[k] + nyOut * faceNy[k];
                ++normalValidLocal;
                normalDotSumLocal += alignment;
                if (alignment > 0.0) ++normalOutwardLocal;
            }
        }
    }

    if (mismatchLocal) atomicAdd(&accum->maskFilteredMismatchCells, mismatchLocal);
    if (facesLocal) atomicAdd(&accum->interfaceFaces, facesLocal);
    if (halfBracketLocal) atomicAdd(&accum->halfIsoBracketFaces, halfBracketLocal);
    if (normalValidLocal) atomicAdd(&accum->normalValidFaces, normalValidLocal);
    if (normalOutwardLocal) atomicAdd(&accum->normalOutwardFaces, normalOutwardLocal);
    if (cutFaceGeometricLocal) {
        atomicAdd(&accum->cutFaceGeometricFaces, cutFaceGeometricLocal);
        constexpr double kThetaScale0493x6d = 1000000000.0;
        const auto maxScaled = static_cast<unsigned long long>(
            fmin(1.0, fmax(0.0, cutFaceThetaMaxLocal)) * kThetaScale0493x6d + 0.5);
        const auto minComplementScaled = static_cast<unsigned long long>(
            (1.0 - fmin(1.0, fmax(0.0, cutFaceThetaMinLocal))) *
                kThetaScale0493x6d + 0.5);
        atomicMax(&accum->cutFaceThetaMaxScaled, maxScaled);
        atomicMax(&accum->cutFaceThetaMinComplementScaled, minComplementScaled);
        if (cutFaceThetaSumLocal != 0.0) {
            atomic_add_double_0400(&accum->cutFaceThetaSum, cutFaceThetaSumLocal);
        }
    }
    if (cutFaceSmallThetaFallbackLocal) {
        atomicAdd(&accum->cutFaceSmallThetaFallbackFaces,
                  cutFaceSmallThetaFallbackLocal);
    }
    if (alphaHalfCrossingLocal) {
        atomicAdd(&accum->alphaHalfCrossingFaces, alphaHalfCrossingLocal);
        atomicAdd(&accum->alphaHalfCrossingActiveActiveFaces,
                  alphaHalfActiveActiveLocal);
        atomicAdd(&accum->alphaHalfCrossingActiveInactiveFaces,
                  alphaHalfActiveInactiveLocal);
        atomicAdd(&accum->alphaHalfCrossingInactiveInactiveFaces,
                  alphaHalfInactiveInactiveLocal);
        atomicAdd(&accum->alphaHalfCrossingAIActiveLiquidSideFaces,
                  alphaHalfAIActiveLiquidSideLocal);
        atomicAdd(&accum->alphaHalfCrossingAIActiveExteriorSideFaces,
                  alphaHalfAIActiveExteriorSideLocal);
        constexpr double kThetaScale0493x6e = 1000000000.0;
        const auto maxScaled = static_cast<unsigned long long>(
            fmin(1.0, fmax(0.0, alphaHalfThetaMaxLocal)) * kThetaScale0493x6e + 0.5);
        const auto minComplementScaled = static_cast<unsigned long long>(
            (1.0 - fmin(1.0, fmax(0.0, alphaHalfThetaMinLocal))) *
                kThetaScale0493x6e + 0.5);
        atomicMax(&accum->alphaHalfThetaMaxScaled, maxScaled);
        atomicMax(&accum->alphaHalfThetaMinComplementScaled, minComplementScaled);
        atomic_add_double_0400(&accum->alphaHalfThetaSum, alphaHalfThetaSumLocal);
        atomic_add_double_0400(&accum->alphaHalfThetaSqSum, alphaHalfThetaSqSumLocal);
    }
    if (boundedGeometryClippedLocal) {
        atomicAdd(&accum->boundedGeometryClippedCells, boundedGeometryClippedLocal);
    }
    if (rawSumLocal != 0.0) atomic_add_double_0400(&accum->rawFillSum, rawSumLocal);
    if (boundedGeometrySumLocal != 0.0) {
        atomic_add_double_0400(&accum->boundedGeometrySourceSum, boundedGeometrySumLocal);
    }
    if (alphaSumLocal != 0.0) atomic_add_double_0400(&accum->filteredFillSum, alphaSumLocal);
    if (deltaSqLocal != 0.0) atomic_add_double_0400(&accum->filterDeltaSqSum, deltaSqLocal);
    if (halfThetaSumLocal != 0.0) atomic_add_double_0400(&accum->halfIsoThetaSum, halfThetaSumLocal);
    if (halfThetaSqLocal != 0.0) atomic_add_double_0400(&accum->halfIsoThetaSqSum, halfThetaSqLocal);
    if (normalDotSumLocal != 0.0) {
        atomic_add_double_0400(&accum->normalFaceAlignmentSum, normalDotSumLocal);
    }
}

// 0493x7c: target divergence for a first-order density-error relaxation.
// The target is deliberately bulk-only: a pressure cell must have every
// existing face-neighbour inside the x6f pressure domain.  Missing neighbours
// at non-periodic physical walls are not phase interfaces and therefore do not
// disable the source.  This is the same geometric scope used by the x7a bulk
// virial experiment, but the correction is now consumed by the Q6 solve itself
// instead of being applied as a post-projection velocity kick.
__device__ double q6_density_relaxation_target_divergence_0493x7c(
    const double* rawFill,
    const unsigned char* pressureMask,
    int c,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    double beta,
    double dt,
    double compressionThresholdFill0493x7dv2,
    int compressionGateEnable0493x7dv2,
    double tractionThresholdFill0493x7dv2signed1,
    double tractionGain0493x7dv2signed1,
    int enabled) {
    if (!enabled || rawFill == nullptr || pressureMask == nullptr ||
        !(beta > 0.0) || !(dt > 0.0) || pressureMask[c] == 0u) {
        return 0.0;
    }

    const int ix = c % nx;
    const int iy = c / nx;
    bool bulk = true;
    if (periodicX || ix > 0) {
        const int xw = periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1;
        bulk = bulk && pressureMask[iy * nx + xw] != 0u;
    }
    if (periodicX || ix < nx - 1) {
        const int xe = periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1;
        bulk = bulk && pressureMask[iy * nx + xe] != 0u;
    }
    if (periodicY || iy > 0) {
        const int ys = periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1;
        bulk = bulk && pressureMask[ys * nx + ix] != 0u;
    }
    if (periodicY || iy < ny - 1) {
        const int yn = periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1;
        bulk = bulk && pressureMask[yn * nx + ix] != 0u;
    }
    if (!bulk) return 0.0;

    const double defect = rawFill[c] - 1.0;
    if (!isfinite(defect)) return 0.0;

    // 0493x7d-v2: classify positive coherent compression before applying the
    // historical x7d target. Once classified, keep the full defect: this is a
    // gate, not a dead-band subtraction.
    if (compressionGateEnable0493x7dv2) {
        if (compressionThresholdFill0493x7dv2 > 0.0 &&
            defect >= compressionThresholdFill0493x7dv2) {
            bool coherent0493x7dv2 = false;
            if (periodicX || ix > 0) {
                const int xw = periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1;
                const double nd = rawFill[iy * nx + xw] - 1.0;
                coherent0493x7dv2 =
                    isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;
            }
            if (!coherent0493x7dv2 && (periodicX || ix < nx - 1)) {
                const int xe = periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1;
                const double nd = rawFill[iy * nx + xe] - 1.0;
                coherent0493x7dv2 =
                    isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;
            }
            if (!coherent0493x7dv2 && (periodicY || iy > 0)) {
                const int ys = periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1;
                const double nd = rawFill[ys * nx + ix] - 1.0;
                coherent0493x7dv2 =
                    isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;
            }
            if (!coherent0493x7dv2 && (periodicY || iy < ny - 1)) {
                const int yn = periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1;
                const double nd = rawFill[yn * nx + ix] - 1.0;
                coherent0493x7dv2 =
                    isfinite(nd) && nd >= compressionThresholdFill0493x7dv2;
            }
            if (!coherent0493x7dv2) return 0.0;
            return beta * defect / dt;
        }

        // 0493x7d-v2-signed1: coherent traction/depression response.  The
        // material law is intentionally topology-independent: free-surface
        // exclusion remains the responsibility of the existing bulk contract
        // above.  Like the positive branch, this is a classifier only; after
        // admission the full negative defect is retained.
        if (tractionGain0493x7dv2signed1 > 0.0 &&
            tractionThresholdFill0493x7dv2signed1 > 0.0 &&
            defect <= -tractionThresholdFill0493x7dv2signed1) {
            bool coherentTraction0493x7dv2signed1 = false;
            if (periodicX || ix > 0) {
                const int xw = periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1;
                const double nd = rawFill[iy * nx + xw] - 1.0;
                coherentTraction0493x7dv2signed1 =
                    isfinite(nd) && nd <= -tractionThresholdFill0493x7dv2signed1;
            }
            if (!coherentTraction0493x7dv2signed1 && (periodicX || ix < nx - 1)) {
                const int xe = periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1;
                const double nd = rawFill[iy * nx + xe] - 1.0;
                coherentTraction0493x7dv2signed1 =
                    isfinite(nd) && nd <= -tractionThresholdFill0493x7dv2signed1;
            }
            if (!coherentTraction0493x7dv2signed1 && (periodicY || iy > 0)) {
                const int ys = periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1;
                const double nd = rawFill[ys * nx + ix] - 1.0;
                coherentTraction0493x7dv2signed1 =
                    isfinite(nd) && nd <= -tractionThresholdFill0493x7dv2signed1;
            }
            if (!coherentTraction0493x7dv2signed1 && (periodicY || iy < ny - 1)) {
                const int yn = periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1;
                const double nd = rawFill[yn * nx + ix] - 1.0;
                coherentTraction0493x7dv2signed1 =
                    isfinite(nd) && nd <= -tractionThresholdFill0493x7dv2signed1;
            }
            if (!coherentTraction0493x7dv2signed1) return 0.0;
            return tractionGain0493x7dv2signed1 * beta * defect / dt;
        }

        return 0.0;
    }

    return beta * defect / dt;
}

__global__ void q6_build_independent_rhs_after_mask_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const unsigned char* mask,
    const unsigned char* velocityMask,
    double* rhs,
    double* partialSum,
    double* partialSq,
    double* partialMax,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    double xLowFlux,
    double xHighFlux,
    double yLowFlux,
    double yHighFlux,
    Q6SegmentedIo0409 segmentedIo,
    std::uint32_t speciesType,
    int exclusiveProjectedSpecies,
    const double* preparedFaceCoeffX0493x6g,
    const double* preparedFaceCoeffY0493x6g,
    const double* preparedFacePhiGammaX0493x6g,
    const double* preparedFacePhiGammaY0493x6g,
    int usePreparedInterfacePressure0493x6g,
    const double* densityRelaxationRawFill0493x7c,
    double densityRelaxationBeta0493x7c,
    double densityRelaxationDt0493x7c,
    double densityRelaxationCompressionThresholdFill0493x7dv2,
    int densityRelaxationCompressionGateEnable0493x7dv2,
    double densityRelaxationTractionThresholdFill0493x7dv2signed1,
    double densityRelaxationTractionGain0493x7dv2signed1,
    int densityRelaxationEnable0493x7c,
    int densityRelaxationCenterMean0493x8t,
    int fullDomain) {
    extern __shared__ double sh[];
    double* shSum = sh;
    double* shSq = sh + blockDim.x;
    double* shMax = sh + 2 * blockDim.x;
    const int tid = threadIdx.x;
    double sum = 0.0;
    double sq = 0.0;
    double mx = 0.0;
    // 0493x7o keeps the historical ABI/call sites while removing the
    // directional fullDomain shortcut from the discretization itself.
    (void)fullDomain;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (mask[c] == 0u) {
            rhs[c] = 0.0;
            continue;
        }
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasWest = periodicX || ix > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const bool hasSouth = periodicY || iy > 0;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;

        const double localXLowFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 0, ix, iy, nx, ny, xLowFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);
        const double localXHighFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 1, ix, iy, nx, ny, xHighFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);
        const double localYLowFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 2, ix, iy, nx, ny, yLowFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);
        const double localYHighFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 3, ix, iy, nx, ny, yHighFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);

        // 0493x7o: use reflection-equivariant finite-volume face velocities in
        // the full-domain path as well.  The historical fullDomain shortcut
        // treated the cell-centered value as the east/north face and the
        // west/south neighbour as the opposite face, which is a directional
        // backward difference and is not equivariant under x/y reflection.
        // q6_species_face_velocity_0493w5 reduces to the centered arithmetic
        // face average when both full-domain cells are active, while preserving
        // the existing masked/free-surface semantics outside fullDomain.
        const double fxEastInterior = q6_species_face_velocity_0493w5(
            species, velocityMask, speciesIndex, c, east, 0);
        const double fxWestInterior = q6_species_face_velocity_0493w5(
            species, velocityMask, speciesIndex, west, c, 0);
        const double fyNorthInterior = q6_species_face_velocity_0493w5(
            species, velocityMask, speciesIndex, c, north, 1);
        const double fySouthInterior = q6_species_face_velocity_0493w5(
            species, velocityMask, speciesIndex, south, c, 1);

        const double fxWest = hasWest ? fxWestInterior : localXLowFlux;
        const double fxEastBefore = hasEast ? fxEastInterior : localXHighFlux;
        const double fxEastSolve = hasEast ? fxEastInterior : localXHighFlux;
        const double fySouth = hasSouth ? fySouthInterior : localYLowFlux;
        const double fyNorthBefore = hasNorth ? fyNorthInterior : localYHighFlux;
        const double fyNorthSolve = hasNorth ? fyNorthInterior : localYHighFlux;
        const double divBefore = (fxEastBefore - fxWest) / dx +
                                 (fyNorthBefore - fySouth) / dy;
        const double divSolve = (fxEastSolve - fxWest) / dx +
                                (fyNorthSolve - fySouth) / dy;
        double rhsValue = -divSolve;
        if (usePreparedInterfacePressure0493x6g) {
            const double invDx2Local = 1.0 / (dx * dx);
            const double invDy2Local = 1.0 / (dy * dy);
            if (hasEast && mask[east] == 0u) {
                rhsValue += preparedFaceCoeffX0493x6g[c] *
                            preparedFacePhiGammaX0493x6g[c] * invDx2Local;
            }
            if (hasWest && mask[west] == 0u) {
                rhsValue += preparedFaceCoeffX0493x6g[west] *
                            preparedFacePhiGammaX0493x6g[west] * invDx2Local;
            }
            if (hasNorth && mask[north] == 0u) {
                rhsValue += preparedFaceCoeffY0493x6g[c] *
                            preparedFacePhiGammaY0493x6g[c] * invDy2Local;
            }
            if (hasSouth && mask[south] == 0u) {
                rhsValue += preparedFaceCoeffY0493x6g[south] *
                            preparedFacePhiGammaY0493x6g[south] * invDy2Local;
            }
        }
        double densityTarget0493x8t = 0.0;
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
        sq += divBefore * divBefore;
        mx = fmax(mx, fabs(divBefore));
    }
    shSum[tid] = sum;
    shSq[tid] = sq;
    shMax[tid] = mx;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shSum[tid] += shSum[tid + offset];
            shSq[tid] += shSq[tid + offset];
            shMax[tid] = fmax(shMax[tid], shMax[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSum[blockIdx.x] = shSum[0];
        partialSq[blockIdx.x] = shSq[0];
        partialMax[blockIdx.x] = shMax[0];
    }
}

// 0493x8s exact pressure-outlet low-mode deflation.
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

__global__ void q6_init_masked_cg_0493w5(
    double* rhs,
    double* phi,
    double* r,
    double* p,
    const unsigned char* mask,
    double mean,
    int subtractMean,
    int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (mask[c] == 0u) {
            rhs[c] = 0.0;
            phi[c] = 0.0;
            r[c] = 0.0;
            p[c] = 0.0;
            continue;
        }
        const double v = rhs[c] - (subtractMean ? mean : 0.0);
        rhs[c] = v;
        phi[c] = 0.0;
        r[c] = v;
        p[c] = v;
    }
}

// Return the coefficient multiplying a center-to-neighbour pressure difference.
// Interior liquid faces keep coefficient 1.  On a carrier/exterior face x6d
// reconstructs alpha=0.5 at distance theta*h from the active-cell center, so
// the finite-volume Dirichlet contribution is 1/(theta*h^2) and the face
// correction is grad(phi)=Delta(phi)/(theta*h).  Faces that do not bracket the
// interface, or whose theta is below the conditioning guard, retain the x5a
// half-cell factor 2.
__device__ double q6_masked_face_factor_0493x6d(
    const unsigned char* mask,
    const double* phaseAlpha,
    int cellA,
    int cellB,
    double legacyInactiveFactor,
    int useCutFaceGeometry,
    double thetaMinGuard) {
    const bool activeA = mask[cellA] != 0u;
    const bool activeB = mask[cellB] != 0u;
    if (activeA && activeB) return 1.0;
    if (!activeA && !activeB) return legacyInactiveFactor;
    if (!useCutFaceGeometry || phaseAlpha == nullptr) return legacyInactiveFactor;

    const int inside = activeA ? cellA : cellB;
    const int outside = activeA ? cellB : cellA;
    const double alphaInside = phaseAlpha[inside];
    const double alphaOutside = phaseAlpha[outside];
    const double denom = alphaInside - alphaOutside;
    if (!(alphaInside >= 0.5 && alphaOutside < 0.5 && denom > 1.0e-14)) {
        return legacyInactiveFactor;
    }
    const double theta = (alphaInside - 0.5) / denom;
    if (!(theta >= thetaMinGuard && theta <= 1.0)) {
        return legacyInactiveFactor;
    }
    return 1.0 / theta;
}

__global__ void q6_apply_masked_operator_and_dot_0493w5(
    const double* p,
    double* Ap,
    const unsigned char* mask,
    double* partialDot,
    int nx,
    int ny,
    double invDx2,
    double invDy2,
    int periodicX,
    int periodicY,
    const double* phaseAlpha,
    int useCutFaceGeometry,
    double cutFaceThetaMinGuard,
    const double* preparedFaceCoeffX,
    const double* preparedFaceCoeffY,
    int usePreparedPhaseStencil,
    double inactiveNeighborFactor,
    Q6SegmentedIo0409 segmentedIo) {
    extern __shared__ double sh[];
    const int tid = threadIdx.x;
    double dot = 0.0;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (mask[c] == 0u) {
            Ap[c] = 0.0;
            continue;
        }
        const int ix = c % nx;
        const int iy = c / nx;
        double a = 0.0;
        if (periodicX || ix < nx - 1) {
            const int east = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
            const double factor = usePreparedPhaseStencil
                ? preparedFaceCoeffX[c]
                : q6_masked_face_factor_0493x6d(
                    mask, phaseAlpha, c, east, inactiveNeighborFactor,
                    useCutFaceGeometry, cutFaceThetaMinGuard);
            a += factor * invDx2 *
                 (p[c] - (mask[east] ? p[east] : 0.0));
        } else if (q6_passive_pressure_outlet_right_cell_0493x8r(
                       segmentedIo, ix, iy, nx, ny)) {
            // 0493x8r passive pressure outlet: phi=0 at the physical face,
            // whose distance from this cell centre is dx/2.
            a += 2.0 * invDx2 * p[c];
        }
        if (periodicX || ix > 0) {
            const int west = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1);
            const double factor = usePreparedPhaseStencil
                ? preparedFaceCoeffX[west]
                : q6_masked_face_factor_0493x6d(
                    mask, phaseAlpha, c, west, inactiveNeighborFactor,
                    useCutFaceGeometry, cutFaceThetaMinGuard);
            a += factor * invDx2 *
                 (p[c] - (mask[west] ? p[west] : 0.0));
        }
        if (periodicY || iy < ny - 1) {
            const int north =
                (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
            const double factor = usePreparedPhaseStencil
                ? preparedFaceCoeffY[c]
                : q6_masked_face_factor_0493x6d(
                    mask, phaseAlpha, c, north, inactiveNeighborFactor,
                    useCutFaceGeometry, cutFaceThetaMinGuard);
            a += factor * invDy2 *
                 (p[c] - (mask[north] ? p[north] : 0.0));
        }
        if (periodicY || iy > 0) {
            const int south =
                (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix;
            const double factor = usePreparedPhaseStencil
                ? preparedFaceCoeffY[south]
                : q6_masked_face_factor_0493x6d(
                    mask, phaseAlpha, c, south, inactiveNeighborFactor,
                    useCutFaceGeometry, cutFaceThetaMinGuard);
            a += factor * invDy2 *
                 (p[c] - (mask[south] ? p[south] : 0.0));
        }
        Ap[c] = a;
        dot += p[c] * a;
    }
    sh[tid] = dot;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) sh[tid] += sh[tid + offset];
        __syncthreads();
    }
    if (tid == 0) partialDot[blockIdx.x] = sh[0];
}

__global__ void q6_compute_masked_face_correction_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const double* phi,
    const unsigned char* mask,
    double* faceDUx,
    double* faceDUy,
    int nx,
    int ny,
    double dx,
    double dy,
    double strength,
    int periodicX,
    int periodicY,
    const double* phaseAlpha,
    int useCutFaceGeometry,
    double cutFaceThetaMinGuard,
    const double* preparedFaceCoeffX,
    const double* preparedFaceCoeffY,
    const double* preparedFacePhiGammaX0493x6g,
    const double* preparedFacePhiGammaY0493x6g,
    int usePreparedInterfacePressure0493x6g,
    int usePreparedPhaseStencil,
    double inactiveNeighborFactor,
    double xHighFlux,
    double yHighFlux,
    Q6SegmentedIo0409 segmentedIo,
    std::uint32_t speciesType,
    int exclusiveProjectedSpecies) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasNorth = periodicY || iy < ny - 1;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;

        if (hasEast) {
            if (mask[c] || mask[east]) {
                const double phiGamma = usePreparedInterfacePressure0493x6g
                    ? preparedFacePhiGammaX0493x6g[c] : 0.0;
                const double pc = mask[c] ? phi[c] : phiGamma;
                const double pe = mask[east] ? phi[east] : phiGamma;
                const double factor = usePreparedPhaseStencil
                    ? preparedFaceCoeffX[c]
                    : q6_masked_face_factor_0493x6d(
                        mask, phaseAlpha, c, east, inactiveNeighborFactor,
                        useCutFaceGeometry, cutFaceThetaMinGuard);
                faceDUx[c] = -strength * factor * (pe - pc) / dx;
            } else {
                faceDUx[c] = 0.0;
            }
        } else if (mask[c]) {
            if (q6_passive_pressure_outlet_right_cell_0493x8r(
                    segmentedIo, ix, iy, nx, ny)) {
                // 0493x8r: correction = -grad(phi), phi_out=0 and
                // distance(cell centre, outlet face)=dx/2.
                faceDUx[c] = strength * (2.0 * phi[c] / dx);
            } else {
                const double target = q6_species_boundary_flux_for_cell_0493w7(
                    segmentedIo, 1, ix, iy, nx, ny, xHighFlux, species, speciesIndex,
                    speciesType, c, exclusiveProjectedSpecies);
                const double before = q6_species_cell_velocity_component_0493w5(
                    species, speciesIndex, c, 0);
                faceDUx[c] = strength * (target - before);
            }
        } else {
            faceDUx[c] = 0.0;
        }

        if (hasNorth) {
            if (mask[c] || mask[north]) {
                const double phiGamma = usePreparedInterfacePressure0493x6g
                    ? preparedFacePhiGammaY0493x6g[c] : 0.0;
                const double pc = mask[c] ? phi[c] : phiGamma;
                const double pn = mask[north] ? phi[north] : phiGamma;
                const double factor = usePreparedPhaseStencil
                    ? preparedFaceCoeffY[c]
                    : q6_masked_face_factor_0493x6d(
                        mask, phaseAlpha, c, north, inactiveNeighborFactor,
                        useCutFaceGeometry, cutFaceThetaMinGuard);
                faceDUy[c] = -strength * factor * (pn - pc) / dy;
            } else {
                faceDUy[c] = 0.0;
            }
        } else if (mask[c]) {
            const double target = q6_species_boundary_flux_for_cell_0493w7(
                segmentedIo, 3, ix, iy, nx, ny, yHighFlux, species, speciesIndex,
                speciesType, c, exclusiveProjectedSpecies);
            const double before = q6_species_cell_velocity_component_0493w5(
                species, speciesIndex, c, 1);
            faceDUy[c] = strength * (target - before);
        } else {
            faceDUy[c] = 0.0;
        }
    }
}

__global__ void q6_compute_masked_cell_correction_stats_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const unsigned char* mask,
    const unsigned char* pressureMask,
    const double* faceDUx,
    const double* faceDUy,
    double* cellDUx,
    double* cellDUy,
    double* partialSq,
    double* partialMax,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    int fullDomain,
    double strength,
    double xLowFlux,
    double yLowFlux,
    Q6SegmentedIo0409 segmentedIo,
    std::uint32_t speciesType,
    int exclusiveProjectedSpecies,
    Q6PeriodicMomentumAccumulator0493x7dv2fix2* periodicMomentumAccum0493x7dv2fix2,
    int periodicMomentumCorrectionEnable0493x7dv2fix2,
    int periodicMomentumCorrectX0493x7dv2fix2,
    int periodicMomentumCorrectY0493x7dv2fix2,
    int collectStats0493x7k) {
    extern __shared__ double sh[];
    double* shSq = sh;
    double* shMax = sh + blockDim.x;
    const int tid = threadIdx.x;
    double sq = 0.0;
    double mx = 0.0;
    // 0493x7o: fullDomain is retained in the kernel signature for call-site
    // stability; both full and masked paths now use the same symmetric face-to-cell reconstruction.
    (void)fullDomain;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (mask[c] == 0u) {
            cellDUx[c] = 0.0;
            cellDUy[c] = 0.0;
            continue;
        }
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasWest = periodicX || ix > 0;
        const bool hasSouth = periodicY || iy > 0;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;
        // 0493x6h / patch A: on a non-periodic low domain boundary there is
        // no west/south owner cell from which to fetch an east/north-owned face
        // correction.  The projected boundary face is nevertheless constrained
        // to its target by the FV solve.  Reconstruct the missing low-face
        // increment with the same target-before convention used for high
        // (east/north) physical faces.  Gate it with the pressure mask, exactly
        // like q6_compute_masked_face_correction_0493w5 does on high faces, so
        // carrier-only interface-band cells do not acquire a spurious wall kick.
        double westCorrection = hasWest ? faceDUx[west] : 0.0;
        double southCorrection = hasSouth ? faceDUy[south] : 0.0;
        if (!hasWest && pressureMask[c] != 0u) {
            const double target = q6_species_boundary_flux_for_cell_0493w7(
                segmentedIo, 0, ix, iy, nx, ny, xLowFlux, species, speciesIndex,
                speciesType, c, exclusiveProjectedSpecies);
            const double before = q6_species_cell_velocity_component_0493w5(
                species, speciesIndex, c, 0);
            westCorrection = strength * (target - before);
        }
        if (!hasSouth && pressureMask[c] != 0u) {
            const double target = q6_species_boundary_flux_for_cell_0493w7(
                segmentedIo, 2, ix, iy, nx, ny, yLowFlux, species, speciesIndex,
                speciesType, c, exclusiveProjectedSpecies);
            const double before = q6_species_cell_velocity_component_0493w5(
                species, speciesIndex, c, 1);
            southCorrection = strength * (target - before);
        }
        // 0493x7o: reconstruct the cell correction from both opposite FV
        // faces in every mode.  For fullDomain this removes the historical
        // east/north-owner bias.  At low physical boundaries the missing
        // west/south face increment is reconstructed with exactly the same
        // target-before convention already used for the stored high face.
        const double cx = 0.5 * (faceDUx[c] + westCorrection);
        const double cy = 0.5 * (faceDUy[c] + southCorrection);
        cellDUx[c] = cx;
        cellDUy[c] = cy;
        if (periodicMomentumCorrectionEnable0493x7dv2fix2 &&
            periodicMomentumAccum0493x7dv2fix2 != nullptr) {
            const int k = speciesIndex * species.numCells + c;
            const double cellMass = species.mass != nullptr ? species.mass[k] : 0.0;
            if (cellMass > 0.0 && isfinite(cellMass)) {
                atomic_add_double_0400(
                    &periodicMomentumAccum0493x7dv2fix2->activeMass, cellMass);
                if (periodicMomentumCorrectX0493x7dv2fix2) {
                    atomic_add_double_0400(
                        &periodicMomentumAccum0493x7dv2fix2->momentumX, cellMass * cx);
                }
                if (periodicMomentumCorrectY0493x7dv2fix2) {
                    atomic_add_double_0400(
                        &periodicMomentumAccum0493x7dv2fix2->momentumY, cellMass * cy);
                }
            }
        }
        if (collectStats0493x7k) {
            const double q = cx * cx + cy * cy;
            sq += q;
            mx = fmax(mx, sqrt(q));
        }
    }
    if (!collectStats0493x7k) return;
    shSq[tid] = sq;
    shMax[tid] = mx;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shSq[tid] += shSq[tid + offset];
            shMax[tid] = fmax(shMax[tid], shMax[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSq[blockIdx.x] = shSq[0];
        partialMax[blockIdx.x] = shMax[0];
    }
}

__global__ void q6_masked_projected_divergence_stats_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const unsigned char* mask,
    const unsigned char* velocityMask,
    const double* faceDUx,
    const double* faceDUy,
    double* partialSq,
    double* partialMax,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    double xLowFlux,
    double xHighFlux,
    double yLowFlux,
    double yHighFlux,
    Q6SegmentedIo0409 segmentedIo,
    std::uint32_t speciesType,
    int exclusiveProjectedSpecies,
    const double* densityRelaxationRawFill0493x7c,
    double densityRelaxationBeta0493x7c,
    double densityRelaxationDt0493x7c,
    double densityRelaxationCompressionThresholdFill0493x7dv2,
    int densityRelaxationCompressionGateEnable0493x7dv2,
    double densityRelaxationTractionThresholdFill0493x7dv2signed1,
    double densityRelaxationTractionGain0493x7dv2signed1,
    int densityRelaxationEnable0493x7c,
    double densityRelaxationTargetDivMean0493x8t,
    double* partialTargetSq0493x7c,
    int fullDomain) {
    extern __shared__ double sh[];
    double* shSq = sh;
    double* shMax = sh + blockDim.x;
    double* shTargetSq = sh + 2 * blockDim.x;
    const int tid = threadIdx.x;
    (void)xHighFlux;
    (void)yHighFlux;
    double sq = 0.0;
    double mx = 0.0;
    double targetSq = 0.0;
    // 0493x7o: retain the parameter for ABI/call-site stability; diagnostics
    // now use the same reflection-equivariant face semantics in every mode.
    (void)fullDomain;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (mask[c] == 0u) continue;
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasWest = periodicX || ix > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const bool hasSouth = periodicY || iy > 0;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;

        const double localXLowFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 0, ix, iy, nx, ny, xLowFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);
        const double localYLowFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 2, ix, iy, nx, ny, yLowFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);

        const double uxC = q6_species_cell_velocity_component_0493w5(
            species, speciesIndex, c, 0);
        const double uyC = q6_species_cell_velocity_component_0493w5(
            species, speciesIndex, c, 1);
        // 0493x7o: diagnostics must use the same centered FV face semantics
        // as the RHS, otherwise a mirrored full-domain state reports a different
        // projected divergence even when the solve itself converges.
        const double fxEastBase = hasEast
            ? q6_species_face_velocity_0493w5(
                species, velocityMask, speciesIndex, c, east, 0)
            : uxC;
        const double fxWestBase = hasWest
            ? q6_species_face_velocity_0493w5(
                species, velocityMask, speciesIndex, west, c, 0)
            : localXLowFlux;
        const double fyNorthBase = hasNorth
            ? q6_species_face_velocity_0493w5(
                species, velocityMask, speciesIndex, c, north, 1)
            : uyC;
        const double fySouthBase = hasSouth
            ? q6_species_face_velocity_0493w5(
                species, velocityMask, speciesIndex, south, c, 1)
            : localYLowFlux;

        const double fxEast = fxEastBase + faceDUx[c];
        const double fxWest = hasWest ? fxWestBase + faceDUx[west] : fxWestBase;
        const double fyNorth = fyNorthBase + faceDUy[c];
        const double fySouth = hasSouth ? fySouthBase + faceDUy[south] : fySouthBase;
        const double div = (fxEast - fxWest) / dx + (fyNorth - fySouth) / dy;
        double residual = div;
        double targetDiv0493x7c = 0.0;
        if (densityRelaxationEnable0493x7c) {
            targetDiv0493x7c = q6_density_relaxation_target_divergence_0493x7c(
                densityRelaxationRawFill0493x7c, mask, c, nx, ny,
                periodicX, periodicY, densityRelaxationBeta0493x7c,
                densityRelaxationDt0493x7c,
                densityRelaxationCompressionThresholdFill0493x7dv2,
                densityRelaxationCompressionGateEnable0493x7dv2,
                densityRelaxationTractionThresholdFill0493x7dv2signed1,
                densityRelaxationTractionGain0493x7dv2signed1, 1);
            targetDiv0493x7c -= densityRelaxationTargetDivMean0493x8t;
            residual -= targetDiv0493x7c;
        }
        sq += residual * residual;
        mx = fmax(mx, fabs(residual));
        targetSq += targetDiv0493x7c * targetDiv0493x7c;
    }
    shSq[tid] = sq;
    shMax[tid] = mx;
    shTargetSq[tid] = targetSq;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shSq[tid] += shSq[tid + offset];
            shMax[tid] = fmax(shMax[tid], shMax[tid + offset]);
            shTargetSq[tid] += shTargetSq[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSq[blockIdx.x] = shSq[0];
        partialMax[blockIdx.x] = shMax[0];
        partialTargetSq0493x7c[blockIdx.x] = shTargetSq[0];
    }
}

__global__ void q6_apply_independent_species_correction_0493w5(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    const unsigned char* mask,
    const double* cellDUx,
    const double* cellDUy,
    std::uint32_t speciesType,
    std::uint64_t nParticles,
    double* partialPx,
    double* partialPy,
    unsigned long long* correctedCounter,
    int collectDiagnostics0493x7k) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    unsigned long long correctedLocal = 0ull;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) continue;
        if (particles.type == nullptr || particles.type[i] != speciesType) continue;
        const int c = cells.cellId[i];
        if (c < 0 || mask[c] == 0u) continue;
        const double dvx = cellDUx[c];
        const double dvy = cellDUy[c];
        particles.vx[i] += dvx;
        particles.vy[i] += dvy;
        if (collectDiagnostics0493x7k) {
            const double m = particles.mass ? particles.mass[i] : 1.0;
            px += m * dvx;
            py += m * dvy;
            ++correctedLocal;
        }
    }
    if (!collectDiagnostics0493x7k) return;
    if (correctedLocal != 0ull) atomicAdd(correctedCounter, correctedLocal);
    shX[tid] = px;
    shY[tid] = py;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialPx[blockIdx.x] = shX[0];
        partialPy[blockIdx.x] = shY[0];
    }
}

// 0493x7a: first CUDA-resident port of the historical weak virial density
// restoring term.  The pressure variable is normalized by the declared liquid
// reference density, so Pvir/rhoRef = Kvirial*(rawFill-1) and
// du = -betaEOS*dt*grad(Pvir/rhoRef).  rawFill is the unbounded x6c liquid
// mass/reference-cell-mass field; no clamp is allowed here because overfill is
// precisely the quantity being restored.
//
// The kick is deliberately bulk-only.  A pressure cell is excluded when any
// existing face-neighbour is outside the x6f pressure domain.  Non-periodic
// external boundaries are not treated as phase interfaces: the historical
// one-sided gradient is retained there.  This keeps the first port away from
// gas/interface traction while remaining compatible with closed-box walls.
__global__ void q6_prepare_virial_density_kick_0493x7a(
    CudaSpeciesCellDeviceView0490h species,
    int liquidSpeciesIndex,
    const double* rawFill,
    const unsigned char* pressureMask,
    unsigned char* bulkMask,
    double* kickVx,
    double* kickVy,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    double kVirial,
    double betaEOS,
    double dt,
    VirialDensityAccumulator0493x7a* accum,
    int auditEnabled) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const bool pressureC = pressureMask != nullptr && pressureMask[c] != 0u;
        if (auditEnabled && pressureC) {
            atomicAdd(&accum->pressureCells, 1ull);
        }

        bool bulk = pressureC;
        int west = c;
        int east = c;
        int south = c;
        int north = c;

        if (periodicX || ix > 0) {
            const int xw = periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1;
            west = iy * nx + xw;
            bulk = bulk && pressureMask[west] != 0u;
        }
        if (periodicX || ix < nx - 1) {
            const int xe = periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1;
            east = iy * nx + xe;
            bulk = bulk && pressureMask[east] != 0u;
        }
        if (periodicY || iy > 0) {
            const int ys = periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1;
            south = ys * nx + ix;
            bulk = bulk && pressureMask[south] != 0u;
        }
        if (periodicY || iy < ny - 1) {
            const int yn = periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1;
            north = yn * nx + ix;
            bulk = bulk && pressureMask[north] != 0u;
        }

        const int k = liquidSpeciesIndex * species.numCells + c;
        const double cellMass =
            species.mass != nullptr && k >= 0 ? species.mass[k] : 0.0;
        bulk = bulk && cellMass > 0.0 && isfinite(cellMass);

        if (!bulk) {
            bulkMask[c] = 0u;
            kickVx[c] = 0.0;
            kickVy[c] = 0.0;
            continue;
        }

        const double fillC = rawFill[c];
        const double pC = kVirial * (fillC - 1.0);
        const double pW = (west == c) ? pC :
            kVirial * (rawFill[west] - 1.0);
        const double pE = (east == c) ? pC :
            kVirial * (rawFill[east] - 1.0);
        const double pS = (south == c) ? pC :
            kVirial * (rawFill[south] - 1.0);
        const double pN = (north == c) ? pC :
            kVirial * (rawFill[north] - 1.0);

        const bool twoSidedX = (periodicX || ix > 0) &&
                               (periodicX || ix < nx - 1);
        const bool twoSidedY = (periodicY || iy > 0) &&
                               (periodicY || iy < ny - 1);
        const double denomX = nx > 1 ? (twoSidedX ? 2.0 * dx : dx) : 1.0;
        const double denomY = ny > 1 ? (twoSidedY ? 2.0 * dy : dy) : 1.0;
        const double dpdx = nx > 1 ? (pE - pW) / denomX : 0.0;
        const double dpdy = ny > 1 ? (pN - pS) / denomY : 0.0;
        const double dvx = -betaEOS * dt * dpdx;
        const double dvy = -betaEOS * dt * dpdy;

        bulkMask[c] = 1u;
        kickVx[c] = isfinite(dvx) ? dvx : 0.0;
        kickVy[c] = isfinite(dvy) ? dvy : 0.0;

        // These three sums are part of the production algorithm: the global
        // momentum correction is consumed directly on device by the particle
        // apply/deposit kernel below.
        atomic_add_double_0400(&accum->activeMass, cellMass);
        atomic_add_double_0400(&accum->momentumX, cellMass * kickVx[c]);
        atomic_add_double_0400(&accum->momentumY, cellMass * kickVy[c]);

        if (auditEnabled) {
            atomicAdd(&accum->activeBulkCells, 1ull);
            const double defect = fillC - 1.0;
            atomic_add_double_0400(&accum->fillDefectSq, defect * defect);
            atomic_add_double_0400(&accum->pressureSq, pC * pC);
            atomic_add_double_0400(
                &accum->kickMassSq,
                cellMass * (kickVx[c] * kickVx[c] + kickVy[c] * kickVy[c]));
        }
    }
}


// 0493x7a is applied after the existing q6Applied diagnostic, so that q6A
// keeps its established meaning (Q6/B1 only).  The kick is fused into the
// mandatory final resident cell-moment refresh; therefore x7a adds no new
// O(Np) particle pass.  The global correction is exact for this cell-constant
// kick because the same deposited liquid cell masses were used above.
__global__ void q6_apply_virial_and_deposit_moments_0493x7a(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    const unsigned char* bulkMask,
    const double* kickVx,
    const double* kickVy,
    std::uint32_t liquidType,
    std::uint64_t nParticles,
    const VirialDensityAccumulator0493x7a* accum,
    int momentumCorrectionEnable) {
    double cvx = 0.0;
    double cvy = 0.0;
    if (momentumCorrectionEnable && accum != nullptr && accum->activeMass > 0.0) {
        cvx = accum->momentumX / accum->activeMass;
        cvy = accum->momentumY / accum->activeMass;
    }

    const std::uint64_t idx =
        static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride =
        static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) continue;

        if (particles.type != nullptr && particles.type[i] == liquidType &&
            bulkMask[c] != 0u) {
            particles.vx[i] += kickVx[c] - cvx;
            particles.vy[i] += kickVy[c] - cvy;
        }

        const double m = particles.mass ? particles.mass[i] : 1.0;
        atomicAdd(&cells.count[c], 1u);
        atomic_add_double_0400(&cells.cellMass[c], m);
        atomic_add_double_0400(&cells.cellPx[c], m * particles.vx[i]);
        atomic_add_double_0400(&cells.cellPy[c], m * particles.vy[i]);
    }
}


// 0493x6h-B1: affine RT0/MAC-to-particle reconstruction for the gated
// free-surface path.  q6_compute_masked_cell_correction_stats_0493w5 stores
// Cx=(dUw+dUe)/2 and Cy=(dVs+dVn)/2 for non-full-domain cells (Patch A
// supplies the missing low-wall faces).  Therefore the west/south values need
// not be loaded: dUw=2*Cx-dUe and dVs=2*Cy-dVn.  The interpolation below is
// exactly linear between the two face corrections and has the same discrete
// divergence as the FV correction field used by Q6.
__global__ void q6_apply_free_surface_force_and_rt0_correction_0493x6h_b1(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    const unsigned char* mask,
    const double* cellDUx,
    const double* cellDUy,
    const double* faceDUxEast,
    const double* faceDUyNorth,
    std::uint32_t projectedType,
    std::uint64_t nParticles,
    int nx,
    int ny,
    double lx,
    double ly,
    int periodicX,
    int periodicY,
    double dt,
    double bodyAx,
    double bodyAy,
    int tgEnable,
    double tgAmplitude,
    int tgModeX,
    int tgModeY,
    double* partialPx,
    double* partialPy,
    unsigned long long* correctedCounter,
    const Q6PeriodicMomentumAccumulator0493x7dv2fix2* periodicMomentumAccum0493x7dv2fix2,
    int periodicMomentumCorrectionEnable0493x7dv2fix2,
    int periodicMomentumCorrectX0493x7dv2fix2,
    int periodicMomentumCorrectY0493x7dv2fix2,
    int collectDiagnostics0493x7k) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    unsigned long long correctedLocal = 0ull;
    double periodicCvx0493x7dv2fix2 = 0.0;
    double periodicCvy0493x7dv2fix2 = 0.0;
    if (periodicMomentumCorrectionEnable0493x7dv2fix2 &&
        periodicMomentumAccum0493x7dv2fix2 != nullptr &&
        periodicMomentumAccum0493x7dv2fix2->activeMass > 0.0) {
        const double invMass = 1.0 / periodicMomentumAccum0493x7dv2fix2->activeMass;
        if (periodicMomentumCorrectX0493x7dv2fix2) {
            periodicCvx0493x7dv2fix2 =
                periodicMomentumAccum0493x7dv2fix2->momentumX * invMass;
        }
        if (periodicMomentumCorrectY0493x7dv2fix2) {
            periodicCvy0493x7dv2fix2 =
                periodicMomentumAccum0493x7dv2fix2->momentumY * invMass;
        }
    }
    const double invDx = static_cast<double>(nx) / lx;
    const double invDy = static_cast<double>(ny) / ly;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) continue;

        double ax = 0.0;
        double ay = 0.0;
        q6_force_acceleration_0493x4b(
            particles.x[i], particles.y[i], lx, ly, bodyAx, bodyAy,
            tgEnable, tgAmplitude, tgModeX, tgModeY, &ax, &ay);
        particles.vx[i] += ax * dt;
        particles.vy[i] += ay * dt;

        if (particles.type == nullptr || particles.type[i] != projectedType) continue;
        const int c = cells.cellId[i];
        if (c < 0 || mask[c] == 0u) continue;

        const int ix = c % nx;
        const int iy = c / nx;
        double x = particles.x[i];
        double y = particles.y[i];
        if (periodicX) {
            x -= floor(x / lx) * lx;
        } else {
            x = fmin(fmax(x, 0.0), nextafter(lx, 0.0));
        }
        if (periodicY) {
            y -= floor(y / ly) * ly;
        } else {
            y = fmin(fmax(y, 0.0), nextafter(ly, 0.0));
        }
        const double xi = fmin(fmax(x * invDx - static_cast<double>(ix), 0.0), 1.0);
        const double eta = fmin(fmax(y * invDy - static_cast<double>(iy), 0.0), 1.0);

        const double cx = cellDUx[c];
        const double cy = cellDUy[c];
        const double dUe = faceDUxEast[c];
        const double dVn = faceDUyNorth[c];
        // C + (2*s-1)*(Fplus-C) is algebraically identical to linear
        // interpolation between Fminus=2*C-Fplus and Fplus.
        const double dvx = cx + (2.0 * xi - 1.0) * (dUe - cx);
        const double dvy = cy + (2.0 * eta - 1.0) * (dVn - cy);
        particles.vx[i] += dvx - periodicCvx0493x7dv2fix2;
        particles.vy[i] += dvy - periodicCvy0493x7dv2fix2;
        if (collectDiagnostics0493x7k) {
            const double m = particles.mass ? particles.mass[i] : 1.0;
            // As in x5a, audit only the pressure correction.  The physical force
            // momentum is deliberately not folded into the Q6 momentum residual.
            px += m * dvx;
            py += m * dvy;
            ++correctedLocal;
        }
    }
    if (!collectDiagnostics0493x7k) return;
    if (correctedLocal != 0ull) atomicAdd(correctedCounter, correctedLocal);
    shX[tid] = px;
    shY[tid] = py;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialPx[blockIdx.x] = shX[0];
        partialPy[blockIdx.x] = shY[0];
    }
}

// 0493x7q: full-domain periodic specialization of B1.  Keep the historical
// q6_apply_free_surface_force_and_rt0_correction_0493x6h_b1 kernel untouched
// so partial-domain free-surface/dam-break runs retain exactly their qualified
// GPU kernel.  This specialization additionally reduces the mass and the raw
// RT0 correction actually sampled at particle locations.
__global__ void q6_apply_full_domain_periodic_rt0_0493x7q(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    const unsigned char* mask,
    const double* cellDUx,
    const double* cellDUy,
    const double* faceDUxEast,
    const double* faceDUyNorth,
    std::uint32_t projectedType,
    std::uint64_t nParticles,
    int nx,
    int ny,
    double lx,
    double ly,
    int periodicX,
    int periodicY,
    double dt,
    double bodyAx,
    double bodyAy,
    int tgEnable,
    double tgAmplitude,
    int tgModeX,
    int tgModeY,
    double* partialPx,
    double* partialPy,
    double* partialMass,
    unsigned long long* correctedCounter,
    const Q6PeriodicMomentumAccumulator0493x7dv2fix2* periodicMomentumAccum,
    int collectDiagnostics0493x7k) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    double* shM = shY + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    double pm = 0.0;
    unsigned long long correctedLocal = 0ull;

    double periodicCvx = 0.0;
    double periodicCvy = 0.0;
    if (periodicMomentumAccum != nullptr && periodicMomentumAccum->activeMass > 0.0) {
        const double invMass = 1.0 / periodicMomentumAccum->activeMass;
        if (periodicX) periodicCvx = periodicMomentumAccum->momentumX * invMass;
        if (periodicY) periodicCvy = periodicMomentumAccum->momentumY * invMass;
    }

    const double invDx = static_cast<double>(nx) / lx;
    const double invDy = static_cast<double>(ny) / ly;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) continue;

        double ax = 0.0;
        double ay = 0.0;
        q6_force_acceleration_0493x4b(
            particles.x[i], particles.y[i], lx, ly, bodyAx, bodyAy,
            tgEnable, tgAmplitude, tgModeX, tgModeY, &ax, &ay);
        particles.vx[i] += ax * dt;
        particles.vy[i] += ay * dt;

        if (particles.type == nullptr || particles.type[i] != projectedType) continue;
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells || mask[c] == 0u) continue;

        const int ix = c % nx;
        const int iy = c / nx;
        double x = particles.x[i];
        double y = particles.y[i];
        if (periodicX) {
            x -= floor(x / lx) * lx;
        } else {
            x = fmin(fmax(x, 0.0), nextafter(lx, 0.0));
        }
        if (periodicY) {
            y -= floor(y / ly) * ly;
        } else {
            y = fmin(fmax(y, 0.0), nextafter(ly, 0.0));
        }
        const double xi = fmin(fmax(x * invDx - static_cast<double>(ix), 0.0), 1.0);
        const double eta = fmin(fmax(y * invDy - static_cast<double>(iy), 0.0), 1.0);

        const double cx = cellDUx[c];
        const double cy = cellDUy[c];
        const double dUe = faceDUxEast[c];
        const double dVn = faceDUyNorth[c];
        const double dvx = cx + (2.0 * xi - 1.0) * (dUe - cx);
        const double dvy = cy + (2.0 * eta - 1.0) * (dVn - cy);
        particles.vx[i] += dvx - periodicCvx;
        particles.vy[i] += dvy - periodicCvy;

        const double m = particles.mass ? particles.mass[i] : 1.0;
        // Raw RT0 momentum only: do not include the physical force or the
        // x7d-v2 uniform pre-closure.  This lets x7q compute the exact residual.
        px += m * dvx;
        py += m * dvy;
        pm += m;
        if (collectDiagnostics0493x7k) ++correctedLocal;
    }

    if (collectDiagnostics0493x7k && correctedLocal != 0ull) {
        atomicAdd(correctedCounter, correctedLocal);
    }
    shX[tid] = px;
    shY[tid] = py;
    shM[tid] = pm;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
            shM[tid] += shM[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialPx[blockIdx.x] = shX[0];
        partialPy[blockIdx.x] = shY[0];
        partialMass[blockIdx.x] = shM[0];
    }
}

// Collapse the per-block particle reduction on device.  The first B1 pass has
// already removed the cell-centred x7d-v2 estimate.  Store only the remaining
// uniform velocity required to make the applied Q6 correction exactly momentum
// neutral in each periodic direction.
__global__ void q6_finalize_exact_periodic_b1_closure_0493x7q(
    const double* partialPx,
    const double* partialPy,
    const double* partialMass,
    int blocks,
    Q6PeriodicMomentumAccumulator0493x7dv2fix2* accum,
    int correctX,
    int correctY) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    double* shM = shY + blockDim.x;
    const int tid = threadIdx.x;
    double sx = 0.0;
    double sy = 0.0;
    double sm = 0.0;
    for (int b = tid; b < blocks; b += blockDim.x) {
        sx += partialPx[b];
        sy += partialPy[b];
        sm += partialMass[b];
    }
    shX[tid] = sx;
    shY[tid] = sy;
    shM[tid] = sm;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
            shM[tid] += shM[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        accum->appliedMass0493x7q = shM[0];
        accum->residualVelocityX0493x7q = 0.0;
        accum->residualVelocityY0493x7q = 0.0;
        if (shM[0] > 0.0 && isfinite(shM[0])) {
            const double preCvx = accum->activeMass > 0.0
                ? accum->momentumX / accum->activeMass : 0.0;
            const double preCvy = accum->activeMass > 0.0
                ? accum->momentumY / accum->activeMass : 0.0;
            if (correctX) accum->residualVelocityX0493x7q = shX[0] / shM[0] - preCvx;
            if (correctY) accum->residualVelocityY0493x7q = shY[0] / shM[0] - preCvy;
        }
    }
}

// Second resident particle pass.  It is never launched for partial-domain
// free-surface runs, so dam-break keeps the exact pre-x7q GPU path and cost.
__global__ void q6_apply_exact_periodic_b1_closure_0493x7q(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    const unsigned char* mask,
    std::uint32_t projectedType,
    std::uint64_t nParticles,
    const Q6PeriodicMomentumAccumulator0493x7dv2fix2* accum,
    int correctX,
    int correctY) {
    const double cvx = correctX ? accum->residualVelocityX0493x7q : 0.0;
    const double cvy = correctY ? accum->residualVelocityY0493x7q : 0.0;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) continue;
        if (particles.type == nullptr || particles.type[i] != projectedType) continue;
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells || mask[c] == 0u) continue;
        if (correctX) particles.vx[i] -= cvx;
        if (correctY) particles.vy[i] -= cvy;
    }
}

__global__ void q6_apply_free_surface_force_and_correction_0493x5a(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    const unsigned char* mask,
    const double* cellDUx,
    const double* cellDUy,
    std::uint32_t projectedType,
    std::uint64_t nParticles,
    double dt,
    double lx,
    double ly,
    double bodyAx,
    double bodyAy,
    int tgEnable,
    double tgAmplitude,
    int tgModeX,
    int tgModeY,
    double* partialPx,
    double* partialPy,
    unsigned long long* correctedCounter,
    int collectDiagnostics0493x7k) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    unsigned long long correctedLocal = 0ull;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) continue;
        double ax = 0.0;
        double ay = 0.0;
        q6_force_acceleration_0493x4b(
            particles.x[i], particles.y[i], lx, ly, bodyAx, bodyAy,
            tgEnable, tgAmplitude, tgModeX, tgModeY, &ax, &ay);
        particles.vx[i] += ax * dt;
        particles.vy[i] += ay * dt;

        if (particles.type == nullptr || particles.type[i] != projectedType) continue;
        const int c = cells.cellId[i];
        if (c < 0 || mask[c] == 0u) continue;
        const double dvx = cellDUx[c];
        const double dvy = cellDUy[c];
        particles.vx[i] += dvx;
        particles.vy[i] += dvy;
        if (collectDiagnostics0493x7k) {
            const double m = particles.mass ? particles.mass[i] : 1.0;
            // Keep the momentum audit restricted to the pressure correction.  The
            // physical force momentum must not be removed by a global correction.
            px += m * dvx;
            py += m * dvy;
            ++correctedLocal;
        }
    }
    if (!collectDiagnostics0493x7k) return;
    if (correctedLocal != 0ull) atomicAdd(correctedCounter, correctedLocal);
    shX[tid] = px;
    shY[tid] = py;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialPx[blockIdx.x] = shX[0];
        partialPy[blockIdx.x] = shY[0];
    }
}

__global__ void q6_zero_cell_moments_only_0493w5(CudaCellWorkspaceDeviceView cells) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        cells.count[c] = 0u;
        cells.cellMass[c] = 0.0;
        cells.cellPx[c] = 0.0;
        cells.cellPy[c] = 0.0;
        cells.cellUx[c] = 0.0;
        cells.cellUy[c] = 0.0;
    }
}

__global__ void q6_apply_uniform_momentum_correction_0400(CudaParticleDeviceView particles,
                                                          std::uint64_t nParticles,
                                                          double cvx,
                                                          double cvy) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        particles.vx[i] -= cvx;
        particles.vy[i] -= cvy;
    }
}

__global__ void q6_update_corrected_cell_means_0400(CudaCellWorkspaceDeviceView cells,
                                                    const double* dux,
                                                    const double* duy,
                                                    double cvx,
                                                    double cvy) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        cells.cellUx[c] += dux[c] - cvx;
        cells.cellUy[c] += duy[c] - cvy;
    }
}

__global__ void q6_thermostat_deposit_moments_from_cell_ids_0400(CudaParticleDeviceView particles,
                                                                       CudaCellWorkspaceDeviceView cells,
                                                                       std::uint64_t nParticles) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) {
            continue;
        }
        const double m = particles.mass ? particles.mass[i] : 1.0;
        atomicAdd(&cells.count[c], 1u);
        atomic_add_double_0400(&cells.cellMass[c], m);
        atomic_add_double_0400(&cells.cellPx[c], m * particles.vx[i]);
        atomic_add_double_0400(&cells.cellPy[c], m * particles.vy[i]);
    }
}

__global__ void q6_thermostat_kinetic_0400(CudaParticleDeviceView particles,
                                           CudaCellWorkspaceDeviceView cells,
                                           std::uint64_t nParticles) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) {
            continue;
        }
        const double dvx = particles.vx[i] - cells.cellUx[c];
        const double dvy = particles.vy[i] - cells.cellUy[c];
        const double m = particles.mass ? particles.mass[i] : 1.0;
        atomic_add_double_0400(&cells.cellKinetic[c], 0.5 * m * (dvx * dvx + dvy * dvy));
        atomicAdd(cells.fluidCounter, 1ull);
    }
}

__global__ void q6_thermostat_scale_0400(CudaCellWorkspaceDeviceView cells,
                                         double targetKBT,
                                         int minParticles,
                                         double epsilon,
                                         double* partial0,
                                         double* partial1) {
    extern __shared__ double sh[];
    double* shK = sh;
    double* shTarget = sh + blockDim.x;
    const int tid = threadIdx.x;
    double kSum = 0.0;
    double targetSum = 0.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        double scale = 1.0;
        const unsigned int count = cells.count[c];
        const double K = cells.cellKinetic[c];
        if (count >= static_cast<unsigned int>(minParticles) && K > epsilon) {
            const double dof = 2.0 * static_cast<double>(count - 1u);
            const double targetK = 0.5 * dof * targetKBT;
            scale = sqrt(targetK / K);
            kSum += K;
            targetSum += targetK;
        }
        cells.cellScale[c] = scale;
    }
    shK[tid] = kSum;
    shTarget[tid] = targetSum;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shK[tid] += shK[tid + offset];
            shTarget[tid] += shTarget[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partial0[blockIdx.x] = shK[0];
        partial1[blockIdx.x] = shTarget[0];
    }
}

__global__ void q6_thermostat_apply_0400(CudaParticleDeviceView particles,
                                         CudaCellWorkspaceDeviceView cells,
                                         std::uint64_t nParticles) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) {
            continue;
        }
        const double scale = cells.cellScale[c];
        if (scale == 1.0) {
            continue;
        }
        const double ux = cells.cellUx[c];
        const double uy = cells.cellUy[c];
        particles.vx[i] = ux + scale * (particles.vx[i] - ux);
        particles.vy[i] = uy + scale * (particles.vy[i] - uy);
    }
}

__global__ void q6_projected_divergence_stats_0400(CudaCellWorkspaceDeviceView cells,
                                                   const double* faceDUx,
                                                   const double* faceDUy,
                                                   double* partialSq,
                                                   double* partialMax,
                                                   int nx,
                                                   int ny,
                                                   double dx,
                                                   double dy,
                                                   int periodicX,
                                                   int periodicY,
                                                   double xLowFlux,
                                                   double xHighFlux,
                                                   double yLowFlux,
                                                   double yHighFlux,
                                                   Q6SegmentedIo0409 segmentedIo) {
    extern __shared__ double sh[];
    double* shSq = sh;
    double* shMax = sh + blockDim.x;
    const int tid = threadIdx.x;
    double sq = 0.0;
    double mx = 0.0;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasWest = periodicX || ix > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const bool hasSouth = periodicY || iy > 0;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;
        const double localXLowFlux = q6_segmented_flux_for_cell_0409(
            segmentedIo, 0, ix, iy, nx, ny, xLowFlux);
        const double localXHighFlux = q6_segmented_flux_for_cell_0409(
            segmentedIo, 1, ix, iy, nx, ny, xHighFlux);
        const double localYLowFlux = q6_segmented_flux_for_cell_0409(
            segmentedIo, 2, ix, iy, nx, ny, yLowFlux);
        const double localYHighFlux = q6_segmented_flux_for_cell_0409(
            segmentedIo, 3, ix, iy, nx, ny, yHighFlux);

        // Diagnose the same face field that enters the FV solve.  Internal
        // base velocities are centred arithmetic face averages.  At physical
        // boundaries, the imposed target is the projected face value; this is
        // exactly the convention used by 0493x7o in the validated species path.
        const double fxEast = hasEast
            ? 0.5 * (cells.cellUx[c] + cells.cellUx[east]) + faceDUx[c]
            : localXHighFlux;
        const double fxWest = hasWest
            ? 0.5 * (cells.cellUx[west] + cells.cellUx[c]) + faceDUx[west]
            : localXLowFlux;
        const double fyNorth = hasNorth
            ? 0.5 * (cells.cellUy[c] + cells.cellUy[north]) + faceDUy[c]
            : localYHighFlux;
        const double fySouth = hasSouth
            ? 0.5 * (cells.cellUy[south] + cells.cellUy[c]) + faceDUy[south]
            : localYLowFlux;
        const double div = (fxEast - fxWest) / dx + (fyNorth - fySouth) / dy;
        sq += div * div;
        mx = fmax(mx, fabs(div));
    }
    shSq[tid] = sq;
    shMax[tid] = mx;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shSq[tid] += shSq[tid + offset];
            shMax[tid] = fmax(shMax[tid], shMax[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSq[blockIdx.x] = shSq[0];
        partialMax[blockIdx.x] = shMax[0];
    }
}

__global__ void q6_cg_single_block_0407(double* rhs,
                                        double* phi,
                                        double* r,
                                        double* p,
                                        double* Ap,
                                        double* outIterations,
                                        double* outResidualRel,
                                        double* outStatus,
                                        int nx,
                                        int ny,
                                        int n,
                                        int maxIterations,
                                        double tolerance,
                                        double rhsMean,
                                        double invDx2,
                                        double invDy2,
                                        int periodicX,
                                        int periodicY,
                                        int warmStart) {
    extern __shared__ double sh[];
    __shared__ double rr;
    __shared__ double rrNew;
    __shared__ double rhsNormSafe;
    __shared__ double pAp;
    __shared__ double residualRel;
    __shared__ double phiMean;
    __shared__ double rMean;
    __shared__ int iterations;
    __shared__ int status;
    __shared__ int done;

    const int tid = threadIdx.x;
    double local = 0.0;
    if (warmStart) {
        for (int c = tid; c < n; c += blockDim.x) local += phi[c];
        sh[tid] = local;
        __syncthreads();
        for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
            if (tid < offset) sh[tid] += sh[tid + offset];
            __syncthreads();
        }
        if (tid == 0) phiMean = sh[0] / static_cast<double>(n);
        __syncthreads();
    } else if (tid == 0) {
        phiMean = 0.0;
    }
    __syncthreads();

    local = 0.0;
    double localRhsNorm = 0.0;
    for (int c = tid; c < n; c += blockDim.x) {
        const int ix = c % nx;
        const int iy = c / nx;
        const double phiOld = warmStart ? phi[c] : 0.0;
        double aPhi = 0.0;
        if (warmStart) {
            if (periodicX || ix > 0) {
                const int west = iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : (ix - 1));
                aPhi += (phiOld - phi[west]) * invDx2;
            }
            if (periodicX || ix < nx - 1) {
                const int east = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : (ix + 1));
                aPhi += (phiOld - phi[east]) * invDx2;
            }
            if (periodicY || iy > 0) {
                const int south = (periodicY ? wrap_cell_index_0400(iy - 1, ny) : (iy - 1)) * nx + ix;
                aPhi += (phiOld - phi[south]) * invDy2;
            }
            if (periodicY || iy < ny - 1) {
                const int north = (periodicY ? wrap_cell_index_0400(iy + 1, ny) : (iy + 1)) * nx + ix;
                aPhi += (phiOld - phi[north]) * invDy2;
            }
        } else {
            phi[c] = 0.0;
        }
        const double v = rhs[c] - rhsMean;
        rhs[c] = v;
        const double rv = warmStart ? (v - aPhi) : v;
        r[c] = rv;
        p[c] = rv;
        local += rv * rv;
        localRhsNorm += v * v;
    }
    sh[tid] = local;
    sh[blockDim.x + tid] = localRhsNorm;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh[tid] += sh[tid + offset];
            sh[blockDim.x + tid] += sh[blockDim.x + tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        rr = sh[0];
        const double rhsNorm = sqrt(fmax(0.0, sh[blockDim.x]));
        rhsNormSafe = fmax(rhsNorm, 1.0e-300);
        residualRel = 0.0;
        iterations = 0;
        status = (rhsNorm <= tolerance) ? 1 : 0;
        done = (status == 1 || maxIterations <= 0) ? 1 : 0;
    }
    __syncthreads();
    if (warmStart) {
        for (int c = tid; c < n; c += blockDim.x) {
            phi[c] -= phiMean;
        }
    }
    __syncthreads();

    for (int it = 0; it < maxIterations; ++it) {
        if (done) break;
        local = 0.0;
        for (int c = tid; c < n; c += blockDim.x) {
            const int ix = c % nx;
            const int iy = c / nx;
            const double center = p[c];
            double value = 0.0;
            if (periodicX || ix > 0) {
                const int west = iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : (ix - 1));
                value += (center - p[west]) * invDx2;
            }
            if (periodicX || ix < nx - 1) {
                const int east = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : (ix + 1));
                value += (center - p[east]) * invDx2;
            }
            if (periodicY || iy > 0) {
                const int south = (periodicY ? wrap_cell_index_0400(iy - 1, ny) : (iy - 1)) * nx + ix;
                value += (center - p[south]) * invDy2;
            }
            if (periodicY || iy < ny - 1) {
                const int north = (periodicY ? wrap_cell_index_0400(iy + 1, ny) : (iy + 1)) * nx + ix;
                value += (center - p[north]) * invDy2;
            }
            Ap[c] = value;
            local += center * value;
        }
        sh[tid] = local;
        __syncthreads();
        for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
            if (tid < offset) sh[tid] += sh[tid + offset];
            __syncthreads();
        }
        if (tid == 0) {
            pAp = sh[0];
            if (!(pAp > 0.0) || !isfinite(pAp)) {
                status = -1;
                done = 1;
            }
        }
        __syncthreads();
        if (done) break;

        const double alpha = rr / pAp;
        local = 0.0;
        for (int c = tid; c < n; c += blockDim.x) {
            phi[c] += alpha * p[c];
            const double rv = r[c] - alpha * Ap[c];
            r[c] = rv;
            local += rv * rv;
        }
        sh[tid] = local;
        __syncthreads();
        for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
            if (tid < offset) sh[tid] += sh[tid + offset];
            __syncthreads();
        }
        if (tid == 0) {
            rrNew = sh[0];
            iterations = it + 1;
            residualRel = sqrt(fmax(0.0, rrNew)) / rhsNormSafe;
            if (residualRel <= tolerance) {
                rr = rrNew;
                status = 1;
                done = 1;
            }
        }
        __syncthreads();
        if (done) break;

        if (((it + 1) % 25) == 0) {
            double sumPhi = 0.0;
            double sumR = 0.0;
            for (int c = tid; c < n; c += blockDim.x) {
                sumPhi += phi[c];
                sumR += r[c];
            }
            sh[tid] = sumPhi;
            sh[blockDim.x + tid] = sumR;
            __syncthreads();
            for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
                if (tid < offset) {
                    sh[tid] += sh[tid + offset];
                    sh[blockDim.x + tid] += sh[blockDim.x + tid + offset];
                }
                __syncthreads();
            }
            if (tid == 0) {
                phiMean = sh[0] / static_cast<double>(n);
                rMean = sh[blockDim.x] / static_cast<double>(n);
            }
            __syncthreads();
            local = 0.0;
            for (int c = tid; c < n; c += blockDim.x) {
                phi[c] -= phiMean;
                const double rv = r[c] - rMean;
                r[c] = rv;
                local += rv * rv;
            }
            sh[tid] = local;
            __syncthreads();
            for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
                if (tid < offset) sh[tid] += sh[tid + offset];
                __syncthreads();
            }
            if (tid == 0) rrNew = sh[0];
            __syncthreads();
        }

        const double beta = rrNew / fmax(rr, 1.0e-300);
        for (int c = tid; c < n; c += blockDim.x) {
            p[c] = r[c] + beta * p[c];
        }
        if (tid == 0) rr = rrNew;
        __syncthreads();
    }

    if (tid == 0) {
        outIterations[0] = static_cast<double>(iterations);
        outResidualRel[0] = residualRel;
        outStatus[0] = static_cast<double>(status);
    }
}

// 0493x7j -------------------------------------------------------------------
// Fully device-resident CG for Q6-g-f.  The former free_surface_masked loop
// launched several kernels and copied pAp / r.r to the host at every iteration.
// This cooperative kernel keeps the complete Krylov recurrence on the GPU and
// synchronizes blocks with cooperative_groups::grid_group.  It has two uniform
// modes:
//   fullDomain=1 : exact standard FV Laplacian, including the historical
//                  25-iteration null-space mean removal;
//   fullDomain=0 : x6f prepared pressure mask + east/north face coefficients.
// No Q6-g-f physics, RHS, tolerance, interface coefficient or application rule
// is changed by this kernel.

__device__ __forceinline__ double q6_warp_sum_0493x7j(double v) {
    constexpr unsigned int mask = 0xffffffffu;
    for (int offset = 16; offset > 0; offset >>= 1) {
        v += __shfl_down_sync(mask, v, offset);
    }
    return v;
}

__device__ __forceinline__ double q6_block_sum_0493x7j(double v, double* warpSums) {
    const int lane = threadIdx.x & 31;
    const int warp = threadIdx.x >> 5;
    const int warps = (blockDim.x + 31) >> 5;
    v = q6_warp_sum_0493x7j(v);
    if (lane == 0) warpSums[warp] = v;
    __syncthreads();
    double total = (warp == 0 && lane < warps) ? warpSums[lane] : 0.0;
    if (warp == 0) total = q6_warp_sum_0493x7j(total);
    __syncthreads();
    return total;
}

__device__ __forceinline__ double q6_warp_max_0493x7j(double v) {
    constexpr unsigned int mask = 0xffffffffu;
    for (int offset = 16; offset > 0; offset >>= 1) {
        v = fmax(v, __shfl_down_sync(mask, v, offset));
    }
    return v;
}

__device__ __forceinline__ double q6_block_max_0493x7j(double v, double* warpValues) {
    const int lane = threadIdx.x & 31;
    const int warp = threadIdx.x >> 5;
    const int warps = (blockDim.x + 31) >> 5;
    v = q6_warp_max_0493x7j(v);
    if (lane == 0) warpValues[warp] = v;
    __syncthreads();
    double total = (warp == 0 && lane < warps) ? warpValues[lane] : 0.0;
    if (warp == 0) total = q6_warp_max_0493x7j(total);
    __syncthreads();
    return total;
}

__device__ __forceinline__ void q6_grid_barrier_0493x7j(
    cooperative_groups::grid_group& grid) {
    // The historical 0407 heuristic deliberately uses one persistent block
    // for modest cell counts.  In that case avoid the cooperative-grid barrier
    // machinery entirely: __syncthreads() is sufficient and materially cheaper.
    if (gridDim.x == 1) {
        __syncthreads();
    } else {
        grid.sync();
    }
}

__device__ __forceinline__ double q6_grid_sum_0493x7j(
    double local,
    double* blockPartials,
    double* warpSums,
    cooperative_groups::grid_group& grid,
    Q6GfResidentCgState0493x7j* state) {
    const double block = q6_block_sum_0493x7j(local, warpSums);
    if (gridDim.x == 1) {
        if (threadIdx.x == 0) state->reduce0 = block;
        __syncthreads();
        return state->reduce0;
    }
    if (threadIdx.x == 0) blockPartials[blockIdx.x] = block;
    grid.sync();
    if (blockIdx.x == 0) {
        double v = 0.0;
        for (int i = threadIdx.x; i < gridDim.x; i += blockDim.x) {
            v += blockPartials[i];
        }
        const double total = q6_block_sum_0493x7j(v, warpSums);
        if (threadIdx.x == 0) state->reduce0 = total;
    }
    grid.sync();
    return state->reduce0;
}

__device__ __forceinline__ void q6_grid_sum_pair_0493x7j(
    double local0,
    double local1,
    double* blockPartials0,
    double* blockPartials1,
    double* warpSums,
    cooperative_groups::grid_group& grid,
    Q6GfResidentCgState0493x7j* state) {
    const double block0 = q6_block_sum_0493x7j(local0, warpSums);
    const double block1 = q6_block_sum_0493x7j(local1, warpSums);
    if (gridDim.x == 1) {
        if (threadIdx.x == 0) {
            state->reduce0 = block0;
            state->reduce1 = block1;
        }
        __syncthreads();
        return;
    }
    if (threadIdx.x == 0) {
        blockPartials0[blockIdx.x] = block0;
        blockPartials1[blockIdx.x] = block1;
    }
    grid.sync();
    if (blockIdx.x == 0) {
        double v0 = 0.0;
        double v1 = 0.0;
        for (int i = threadIdx.x; i < gridDim.x; i += blockDim.x) {
            v0 += blockPartials0[i];
            v1 += blockPartials1[i];
        }
        const double total0 = q6_block_sum_0493x7j(v0, warpSums);
        const double total1 = q6_block_sum_0493x7j(v1, warpSums);
        if (threadIdx.x == 0) {
            state->reduce0 = total0;
            state->reduce1 = total1;
        }
    }
    grid.sync();
}

__device__ __forceinline__ double q6_full_operator_cell_0493x7j(
    const double* p,
    int c,
    int nx,
    int ny,
    double invDx2,
    double invDy2,
    int periodicX,
    int periodicY,
    Q6SegmentedIo0409 segmentedIo) {
    const int ix = c % nx;
    const int iy = c / nx;
    const double center = p[c];
    double value = 0.0;
    if (periodicX || ix > 0) {
        const int west = iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1);
        value += (center - p[west]) * invDx2;
    }
    if (periodicX || ix < nx - 1) {
        const int east = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
        value += (center - p[east]) * invDx2;
    } else if (q6_passive_pressure_outlet_right_cell_0493x8r(
                   segmentedIo, ix, iy, nx, ny)) {
        value += 2.0 * center * invDx2;
    }
    if (periodicY || iy > 0) {
        const int south = (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix;
        value += (center - p[south]) * invDy2;
    }
    if (periodicY || iy < ny - 1) {
        const int north = (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
        value += (center - p[north]) * invDy2;
    }
    return value;
}

__device__ __forceinline__ double q6_prepared_masked_operator_cell_0493x7j(
    const double* p,
    const unsigned char* mask,
    const double* faceCoeffX,
    const double* faceCoeffY,
    int c,
    int nx,
    int ny,
    double invDx2,
    double invDy2,
    int periodicX,
    int periodicY,
    Q6SegmentedIo0409 segmentedIo) {
    const int ix = c % nx;
    const int iy = c / nx;
    const double center = p[c];
    double value = 0.0;
    if (periodicX || ix < nx - 1) {
        const int east = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
        value += faceCoeffX[c] * invDx2 * (center - (mask[east] ? p[east] : 0.0));
    } else if (q6_passive_pressure_outlet_right_cell_0493x8r(
                   segmentedIo, ix, iy, nx, ny)) {
        value += 2.0 * center * invDx2;
    }
    if (periodicX || ix > 0) {
        const int west = iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1);
        value += faceCoeffX[west] * invDx2 * (center - (mask[west] ? p[west] : 0.0));
    }
    if (periodicY || iy < ny - 1) {
        const int north = (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
        value += faceCoeffY[c] * invDy2 * (center - (mask[north] ? p[north] : 0.0));
    }
    if (periodicY || iy > 0) {
        const int south = (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix;
        value += faceCoeffY[south] * invDy2 * (center - (mask[south] ? p[south] : 0.0));
    }
    return value;
}

__global__ void q6_cg_g_f_resident_0493x7j(
    double* rhs,
    double* phi,
    double* r,
    double* p,
    double* Ap,
    const unsigned char* mask,
    const double* faceCoeffX,
    const double* faceCoeffY,
    double* blockPartials0,
    double* blockPartials1,
    double* blockPartials2,
    Q6GfResidentCgState0493x7j* state,
    int rhsPartialBlocks,
    int nx,
    int ny,
    int n,
    int maxIterations,
    double tolerance,
    double invDx2,
    double invDy2,
    int periodicX,
    int periodicY,
    Q6SegmentedIo0409 segmentedIo,
    int densityRelaxationCenterMean0493x8t,
    int pressureOutletDirichlet0493x8r,
    int pressureOutletDeflation0493x8s,
    int fullDomain) {
    cooperative_groups::grid_group grid = cooperative_groups::this_grid();
    extern __shared__ double warpSums[];
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;

    // Consume the RHS diagnostics produced by the immediately preceding RHS
    // kernel before partial0/1/2 are reused as CG reduction scratch.  Keeping
    // this reduction inside the cooperative kernel removes the last pre-CG
    // host synchronization from the Q6-g-f solve path.
    if (blockIdx.x == 0) {
        double rhsSum = 0.0;
        double divSq = 0.0;
        double divMax = 0.0;
        for (int i = threadIdx.x; i < rhsPartialBlocks; i += blockDim.x) {
            rhsSum += blockPartials0[i];
            divSq += blockPartials1[i];
            divMax = fmax(divMax, blockPartials2[i]);
        }
        const double totalRhs = q6_block_sum_0493x7j(rhsSum, warpSums);
        const double totalDivSq = q6_block_sum_0493x7j(divSq, warpSums);
        const double totalDivMax = q6_block_max_0493x7j(divMax, warpSums);
        if (threadIdx.x == 0) {
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
    q6_grid_barrier_0493x7j(grid);

    if (state->status == 1 || maxIterations <= 0) return;

    for (int it = 0; it < maxIterations; ++it) {
        double localPAp = 0.0;
        for (int c = idx; c < n; c += stride) {
            if (!fullDomain && mask[c] == 0u) {
                Ap[c] = 0.0;
                continue;
            }
            const double value = fullDomain
                ? q6_full_operator_cell_0493x7j(
                      p, c, nx, ny, invDx2, invDy2, periodicX, periodicY,
                      segmentedIo)
                : q6_prepared_masked_operator_cell_0493x7j(
                      p, mask, faceCoeffX, faceCoeffY, c, nx, ny,
                      invDx2, invDy2, periodicX, periodicY, segmentedIo);
            Ap[c] = value;
            localPAp += p[c] * value;
        }
        const double pAp = q6_grid_sum_0493x7j(
            localPAp, blockPartials0, warpSums, grid, state);
        if (!(pAp > 0.0) || !isfinite(pAp)) {
            if (blockIdx.x == 0 && threadIdx.x == 0) {
                state->status = -1;
                state->residualRel = __longlong_as_double(0x7ff0000000000000LL);
            }
            q6_grid_barrier_0493x7j(grid);
            return;
        }

        const double alpha = state->rr / pAp;
        double localRrNew = 0.0;
        for (int c = idx; c < n; c += stride) {
            if (!fullDomain && mask[c] == 0u) continue;
            phi[c] += alpha * p[c];
            const double rv = r[c] - alpha * Ap[c];
            r[c] = rv;
            localRrNew += rv * rv;
        }
        double rrNew = q6_grid_sum_0493x7j(
            localRrNew, blockPartials0, warpSums, grid, state);
        double residualRel = sqrt(fmax(0.0, rrNew)) / state->rhsNormSafe;
        if (residualRel <= tolerance) {
            if (blockIdx.x == 0 && threadIdx.x == 0) {
                state->rr = rrNew;
                state->residualRel = residualRel;
                state->iterations = it + 1;
                state->status = 1;
            }
            q6_grid_barrier_0493x7j(grid);
            return;
        }

        if (removeConstantNullspace0493x8r && ((it + 1) % 25) == 0) {
            double localPhi = 0.0;
            double localR = 0.0;
            for (int c = idx; c < n; c += stride) {
                localPhi += phi[c];
                localR += r[c];
            }
            q6_grid_sum_pair_0493x7j(
                localPhi, localR, blockPartials0, blockPartials1,
                warpSums, grid, state);
            const double phiMean = state->reduce0 / static_cast<double>(n);
            const double rMean = state->reduce1 / static_cast<double>(n);
            localRrNew = 0.0;
            for (int c = idx; c < n; c += stride) {
                phi[c] -= phiMean;
                const double rv = r[c] - rMean;
                r[c] = rv;
                localRrNew += rv * rv;
            }
            rrNew = q6_grid_sum_0493x7j(
                localRrNew, blockPartials0, warpSums, grid, state);
        }

        const double beta = rrNew / fmax(state->rr, 1.0e-300);
        for (int c = idx; c < n; c += stride) {
            if (!fullDomain && mask[c] == 0u) continue;
            p[c] = r[c] + beta * p[c];
        }
        if (blockIdx.x == 0 && threadIdx.x == 0) {
            state->rr = rrNew;
            state->residualRel = residualRel;
            state->iterations = it + 1;
        }
        q6_grid_barrier_0493x7j(grid);
    }
}

struct Q6GfResidentCgLaunch0493x7j {
    int device = -1;
    int threads = 256;
    int maxBlocks = 0;
    bool cooperative = false;
    bool initialized = false;
};

Q6GfResidentCgLaunch0493x7j& q6_g_f_resident_cg_launch_0493x7j() {
    static Q6GfResidentCgLaunch0493x7j cfg;
    int device = 0;
    check_cuda_0400(cudaGetDevice(&device), "0493x7j cudaGetDevice");
    if (cfg.initialized && cfg.device == device) return cfg;

    cfg = Q6GfResidentCgLaunch0493x7j{};
    cfg.device = device;
    cfg.initialized = true;
    int cooperative = 0;
    check_cuda_0400(cudaDeviceGetAttribute(
                        &cooperative, cudaDevAttrCooperativeLaunch, device),
                    "0493x7j cooperative launch attribute");
    if (!cooperative) return cfg;

    int smCount = 0;
    check_cuda_0400(cudaDeviceGetAttribute(
                        &smCount, cudaDevAttrMultiProcessorCount, device),
                    "0493x7j multiprocessor count");
    const int warpCount = (cfg.threads + 31) / 32;
    const std::size_t sharedBytes = static_cast<std::size_t>(warpCount) * sizeof(double);
    int blocksPerSm = 0;
    check_cuda_0400(cudaOccupancyMaxActiveBlocksPerMultiprocessor(
                        &blocksPerSm, q6_cg_g_f_resident_0493x7j,
                        cfg.threads, sharedBytes),
                    "0493x7j cooperative occupancy");
    cfg.maxBlocks = std::max(0, blocksPerSm * smCount);
    cfg.cooperative = cfg.maxBlocks > 0;
    return cfg;
}

bool launch_q6_g_f_resident_cg_0493x7j(
    ResidentWorkspace0400& ws,
    const unsigned char* solveMask,
    const double* faceCoeffX,
    const double* faceCoeffY,
    int cellBlocks,
    int nx,
    int ny,
    int numCells,
    int maxIterations,
    double tolerance,
    double invDx2,
    double invDy2,
    int periodicX,
    int periodicY,
    Q6SegmentedIo0409 segmentedIo,
    bool densityRelaxationCenterMean0493x8t,
    bool pressureOutletDirichlet0493x8r,
    bool pressureOutletDeflation0493x8s,
    bool fullDomain,
    double& divBeforeSqOut0493x7j,
    IndependentMaskedSpeciesAudit0493w5& audit) {
    if (!cuda_q6_g_f_resident_cg_0493x7j_requested()) return false;
    Q6GfResidentCgLaunch0493x7j& cfg = q6_g_f_resident_cg_launch_0493x7j();
    if (!cfg.cooperative) return false;
    const bool singleBlockFast0493x7j = cuda_q6_single_block_cg_0407_enabled(numCells);
    const int gridBlocks = singleBlockFast0493x7j
        ? 1
        : std::max(1, std::min(cellBlocks, cfg.maxBlocks));
    const int warpCount = (cfg.threads + 31) / 32;
    const std::size_t sharedBytes = static_cast<std::size_t>(warpCount) * sizeof(double);

    double* rhs = ws.rhs.data();
    double* phi = ws.phi.data();
    double* r = ws.r.data();
    double* p = ws.p.data();
    double* Ap = ws.Ap.data();
    double* partial0 = ws.partial0.data();
    double* partial1 = ws.partial1.data();
    double* partial2 = ws.partial2.data();
    Q6GfResidentCgState0493x7j* state = ws.q6GfResidentCgState0493x7j.data();
    const unsigned char* mask = solveMask;
    const double* coeffX = faceCoeffX;
    const double* coeffY = faceCoeffY;
    int densityRelaxationCenterMean =
        densityRelaxationCenterMean0493x8t ? 1 : 0;
    int pressureOutlet = pressureOutletDirichlet0493x8r ? 1 : 0;
    int pressureOutletDeflation = pressureOutletDeflation0493x8s ? 1 : 0;
    int full = fullDomain ? 1 : 0;

    void* args[] = {
        &rhs, &phi, &r, &p, &Ap, &mask, &coeffX, &coeffY,
        &partial0, &partial1, &partial2, &state, &cellBlocks,
        &nx, &ny, &numCells, &maxIterations, &tolerance,
        &invDx2, &invDy2, &periodicX, &periodicY,
        &segmentedIo, &densityRelaxationCenterMean,
        &pressureOutlet, &pressureOutletDeflation, &full
    };
    check_cuda_0400(cudaLaunchCooperativeKernel(
                        reinterpret_cast<const void*>(q6_cg_g_f_resident_0493x7j),
                        dim3(gridBlocks), dim3(cfg.threads), args, sharedBytes, nullptr),
                    "0493x7j cooperative resident CG launch");

    Q6GfResidentCgState0493x7j hostState{};
    check_cuda_0400(cudaMemcpy(&hostState, state, sizeof(hostState), cudaMemcpyDeviceToHost),
                    "0493x7j resident CG state download");
    divBeforeSqOut0493x7j = hostState.divBeforeSq;
    audit.divBeforeMaxAbs = hostState.divBeforeMaxAbs;
    audit.divBeforeRms = std::sqrt(
        hostState.divBeforeSq /
        static_cast<double>(std::max<std::uint64_t>(1u, audit.activeCells)));
    audit.iterations = hostState.iterations;
    audit.residualRel = hostState.residualRel;
    audit.converged = hostState.status == 1;
    audit.densityRelaxationTargetDivMeanRemoved0493x8t =
        hostState.densityRelaxationTargetDivMeanRemoved0493x8t;
    audit.residentCg0493x7j = 1;
    audit.residentCgBlocks0493x7j = gridBlocks;
    return true;
}

double reduce_host_sum_0400(double* devicePartials, int blocks) {
    std::vector<double> host(static_cast<std::size_t>(blocks), 0.0);
    check_cuda_0400(cudaMemcpy(host.data(), devicePartials,
                               static_cast<std::size_t>(blocks) * sizeof(double),
                               cudaMemcpyDeviceToHost),
                    "copy partial sum");
    double s = 0.0;
    for (double v : host) {
        s += v;
    }
    return s;
}

double reduce_host_max_0400(double* devicePartials, int blocks) {
    std::vector<double> host(static_cast<std::size_t>(blocks), 0.0);
    check_cuda_0400(cudaMemcpy(host.data(), devicePartials,
                               static_cast<std::size_t>(blocks) * sizeof(double),
                               cudaMemcpyDeviceToHost),
                    "copy partial max");
    double m = 0.0;
    for (double v : host) {
        m = std::max(m, v);
    }
    return m;
}



void append_kinetic_interface_audit_0493x9t(
    const SimulationParams& params,
    int step,
    double time,
    const KineticInterfaceAccumulator0493x9t& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_kinetic_reflection_0493x9t.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493x9t failed to open kinetic-interface audit CSV: " + path.string());
    }
    if (header) {
        out << "step,time,reflectionFraction,evaporationTargetType,crossings,"
               "selectedReflections,transmittedCrossings,appliedReflections,"
               "unsupportedReflections,convertedParticles,reflectedMass,"
               "transmittedMass,outwardRelativeNormalSpeedMean,deltaPx,deltaPy,"
               "deltaKineticEnergy,contract\n";
    }
    const double meanOut = a.crossings > 0ull
        ? a.outwardRelativeNormalSpeedSum / static_cast<double>(a.crossings)
        : 0.0;
    out << std::setprecision(17)
        << step << ',' << time << ','
        << params.phaseInterfaceKineticReflectionFraction << ','
        << params.phaseInterfaceEvaporationTargetType << ','
        << a.crossings << ',' << a.selectedReflections << ','
        << a.transmittedCrossings << ',' << a.appliedReflections << ','
        << a.unsupportedReflections << ',' << a.convertedParticles << ','
        << a.reflectedMass << ',' << a.transmittedMass << ',' << meanOut << ','
        << a.deltaPx << ',' << a.deltaPy << ',' << a.deltaKineticEnergy << ','
        << "physical-alpha-x6c;relative-to-local-A-mean;normal-only;"
           "same-cell-two-group-elastic-recoil;deterministic-hash;"
           "transmitted-type-conversion-does-not-change-mass-or-velocity" << '\n';
}


bool apply_kinetic_interface_reflection_0493x9t(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    ResidentWorkspace0400& ws,
    const SimulationParams& params,
    const CellGrid& grid,
    int step,
    double time,
    std::uint64_t nParticles,
    int threads,
    int cellBlocks,
    int particleBlocks,
    int periodicX,
    int periodicY,
    std::uint32_t phaseAType,
    const double* phaseAlpha0493x6c,
    bool geometryValid0493x6c) {
    const double r = params.phaseInterfaceKineticReflectionFraction;
    if (!(r > 0.0)) return false; // exact source/runtime no-op
    if (!geometryValid0493x6c || phaseAlpha0493x6c == nullptr) {
        throw std::runtime_error(
            "0493x9t kinetic reflection requested without valid resident x6c alpha geometry");
    }

    ws.ensure_kinetic_interface_0493x9t(grid.numCells);
    const std::size_t bytes = static_cast<std::size_t>(grid.numCells) * sizeof(double);
    double* fields[] = {
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data(),
        ws.kineticRefM0493x9t.data(), ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
        ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data()
    };
    for (double* field : fields) {
        check_cuda_0400(cudaMemset(field, 0, bytes), "0493x9t cell moment zero");
    }

    const bool auditThisStep = step <= 1 ||
        step % std::max(1, params.summaryEvery) == 0;
    KineticInterfaceAccumulator0493x9t* auditDev = nullptr;
    if (auditThisStep) {
        check_cuda_0400(cudaMemset(
            ws.kineticAccum0493x9t.data(), 0,
            sizeof(KineticInterfaceAccumulator0493x9t)),
            "0493x9t audit zero");
        auditDev = ws.kineticAccum0493x9t.data();
    }

    q6_x9t_deposit_total_a_moments<<<particleBlocks, threads>>>(
        particles, cells, nParticles, phaseAType,
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(),
        ws.kineticTotalPy0493x9t.data());
    check_cuda_0400(cudaGetLastError(), "0493x9t total-A deposit launch");

    q6_x9t_classify_crossings<<<particleBlocks, threads>>>(
        particles, cells, nParticles, phaseAlpha0493x6c,
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(),
        ws.kineticTotalPy0493x9t.data(), ws.kineticRefM0493x9t.data(),
        ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
        ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(),
        ws.kineticTxPy0493x9t.data(), phaseAType, grid.Nx, grid.Ny,
        params.Lx, params.Ly, params.dt, periodicX, periodicY, r,
        static_cast<unsigned long long>(step),
        static_cast<unsigned long long>(params.rngSeed), auditDev);
    check_cuda_0400(cudaGetLastError(), "0493x9t crossing classification launch");

    q6_x9t_apply_conservative_reflection<<<particleBlocks, threads>>>(
        particles, cells, nParticles, phaseAlpha0493x6c,
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(),
        ws.kineticTotalPy0493x9t.data(), ws.kineticRefM0493x9t.data(),
        ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
        ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(),
        ws.kineticTxPy0493x9t.data(), phaseAType,
        params.phaseInterfaceEvaporationTargetType, grid.Nx, grid.Ny,
        params.Lx, params.Ly, params.dt, periodicX, periodicY, r,
        static_cast<unsigned long long>(step),
        static_cast<unsigned long long>(params.rngSeed), auditDev);
    check_cuda_0400(cudaGetLastError(), "0493x9t conservative reflection launch");

    // Keep the resident all-particle cell means coherent with the modified
    // velocities before returning to the pre-stream caller.
    check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                    "0493x9t cell refresh counter zero");
    q6_zero_cell_moments_only_0493w5<<<cellBlocks, threads>>>(cells);
    check_cuda_0400(cudaGetLastError(), "0493x9t cell moments reset launch");
    q6_thermostat_deposit_moments_from_cell_ids_0400<<<particleBlocks, threads>>>(
        particles, cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "0493x9t cell moments redeposit launch");
    q6_finalize_cells_0400<<<cellBlocks, threads>>>(cells, ws.counter.data());
    check_cuda_0400(cudaGetLastError(), "0493x9t cell moments finalize launch");

    if (auditThisStep) {
        KineticInterfaceAccumulator0493x9t audit{};
        check_cuda_0400(cudaMemcpy(
            &audit, ws.kineticAccum0493x9t.data(), sizeof(audit), cudaMemcpyDeviceToHost),
            "0493x9t audit download");
        append_kinetic_interface_audit_0493x9t(params, step, time, audit);
    }
    return true;
}


void append_kinetic_interface_audit_0493x9u(
    const SimulationParams& params, int step, double time,
    const KineticInterfaceAccumulator0493x9u& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_kinetic_reflection_0493x9u.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) || std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) throw std::runtime_error("0493x9u failed to open kinetic-interface audit CSV: " + path.string());
    if (header) {
        out << "step,time,reflectionFraction,evaporationTargetType,phaseAParticlesInOuterSupport,"
               "crossings,legacyHalfIsoCrossings,supportExitCrossings,selectedReflections,"
               "transmittedCrossings,appliedReflections,unsupportedReflections,bathSearchFailures,"
               "bathDepth0,bathDepth1,bathDepth2,normalFallbacks,convertedParticles,reflectedMass,"
               "transmittedMass,outwardRelativeNormalSpeedMean,deltaPx,deltaPy,deltaKineticEnergy,contract\n";
    }
    const double meanOut = a.crossings > 0ull ? a.outwardRelativeNormalSpeedSum / static_cast<double>(a.crossings) : 0.0;
    out << std::setprecision(17) << step << ',' << time << ','
        << params.phaseInterfaceKineticReflectionFraction << ',' << params.phaseInterfaceEvaporationTargetType << ','
        << a.phaseAParticlesInOuterSupport << ',' << a.crossings << ',' << a.legacyHalfIsoCrossings << ','
        << a.supportExitCrossings << ',' << a.selectedReflections << ',' << a.transmittedCrossings << ','
        << a.appliedReflections << ',' << a.unsupportedReflections << ',' << a.bathSearchFailures << ','
        << a.bathDepth0 << ',' << a.bathDepth1 << ',' << a.bathDepth2 << ',' << a.normalFallbacks << ','
        << a.convertedParticles << ',' << a.reflectedMass << ',' << a.transmittedMass << ',' << meanOut << ','
        << a.deltaPx << ',' << a.deltaPy << ',' << a.deltaKineticEnergy << ','
        << "x9t-halfiso-preserved;x9w-strict-bulk-bath-alphaGE0.5;"
           "outer-target-occupancy-ignored;relative-to-inward-A-bath;max-bath-depth=2;"
           "nearest-depth-largest-mass;mass-weighted-shared-normal;two-group-elastic-recoil;"
           "same-three-particle-passes-as-x9t;deterministic-hash" << '\n';
}


void append_kinetic_interface_diagnostic_0493x9v(
    const SimulationParams& params, int step, double time,
    const KineticInterfaceAccumulator0493x9u& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_kinetic_escape_diagnostic_0493x9v.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) || std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) throw std::runtime_error("0493x9v failed to open kinetic escape diagnostic CSV: " + path.string());
    if (header) {
        out << "step,time,reflectionFraction,outerSupportParticles,outerSupportCellParticlesLT3,"
               "crossings,supportExitCrossings,bathSearchFailures,bathSearchFailureWouldExitLocal,"
               "detectorPredictedOuterTarget,missedOccupiedOuterTarget,missedSparseOuterTargetLT3,"
               "absoluteSupportExitCandidates,missedRelativeButAbsoluteExit,"
               "bathAlphaGEHalf,bathAlphaLTHalf,supportExitBathAlphaGEHalf,supportExitBathAlphaLTHalf,"
               "selectedReflections,appliedReflections,unsupportedReflections,"
               "unsupportedInvalidBath,unsupportedInvalidDonorGroup,unsupportedNoReceiverMass,"
               "unsupportedNormalCancellation,unsupportedGroupNotOutward,"
               "appliedStillOutwardRelative,appliedStillRelativeExit,appliedStillAbsoluteExit,"
               "postRelativeNormalSpeedMean,postOutwardRelativeNormalSpeedMean,deltaPx,deltaPy,deltaKineticEnergy,contract\n";
    }
    const double postMean = a.appliedReflections > 0ull
        ? a.postRelativeNormalSpeedSum / static_cast<double>(a.appliedReflections) : 0.0;
    const double postOutMean = a.appliedStillOutwardRelative > 0ull
        ? a.postOutwardRelativeNormalSpeedSum / static_cast<double>(a.appliedStillOutwardRelative) : 0.0;
    out << std::setprecision(17) << step << ',' << time << ','
        << params.phaseInterfaceKineticReflectionFraction << ','
        << a.phaseAParticlesInOuterSupport << ',' << a.outerSupportCellParticlesLT3 << ','
        << a.crossings << ',' << a.supportExitCrossings << ',' << a.bathSearchFailures << ','
        << a.bathSearchFailureWouldExitLocal << ',' << a.detectorPredictedOuterTarget << ','
        << a.missedOccupiedOuterTarget << ',' << a.missedSparseOuterTargetLT3 << ','
        << a.absoluteSupportExitCandidates << ',' << a.missedRelativeButAbsoluteExit << ','
        << a.bathAlphaGEHalf << ',' << a.bathAlphaLTHalf << ','
        << a.supportExitBathAlphaGEHalf << ',' << a.supportExitBathAlphaLTHalf << ','
        << a.selectedReflections << ',' << a.appliedReflections << ',' << a.unsupportedReflections << ','
        << a.unsupportedInvalidBath << ',' << a.unsupportedInvalidDonorGroup << ','
        << a.unsupportedNoReceiverMass << ',' << a.unsupportedNormalCancellation << ','
        << a.unsupportedGroupNotOutward << ',' << a.appliedStillOutwardRelative << ','
        << a.appliedStillRelativeExit << ',' << a.appliedStillAbsoluteExit << ','
        << postMean << ',' << postOutMean << ',' << a.deltaPx << ',' << a.deltaPy << ','
        << a.deltaKineticEnergy << ','
        << "diagnostic-only;x9w-physics=strict-bulk-bath-alphaGE0.5+occupied-halo-not-support;"
           "no-new-particle-pass;extra-work-only-on-audit-steps;"
           "tests=occupied-halo-target,bath-alpha,unsupported-reason,post-reflection-relative-and-absolute-exit"
        << '\n';
}

bool apply_kinetic_interface_reflection_0493x9u(
    CudaParticleDeviceView particles, CudaCellWorkspaceDeviceView cells, ResidentWorkspace0400& ws,
    const SimulationParams& params, const CellGrid& grid, int step, double time,
    std::uint64_t nParticles, int threads, int cellBlocks, int particleBlocks,
    int periodicX, int periodicY, std::uint32_t phaseAType,
    const double* phaseAlpha0493x6c, bool geometryValid0493x6c) {
    const double r = params.phaseInterfaceKineticReflectionFraction;
    if (!(r > 0.0)) return false;
    if (!geometryValid0493x6c || phaseAlpha0493x6c == nullptr)
        throw std::runtime_error("0493x9u kinetic reflection requested without valid resident x6c alpha geometry");

    ws.ensure_kinetic_interface_0493x9u(grid.numCells);
    const std::size_t bytes = static_cast<std::size_t>(grid.numCells) * sizeof(double);
    double* fields[] = {
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data(),
        ws.kineticRefM0493x9t.data(), ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
        ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data(),
        ws.kineticRefNx0493x9u.data(), ws.kineticRefNy0493x9u.data()
    };
    for (double* field : fields) check_cuda_0400(cudaMemset(field, 0, bytes), "0493x9u cell field zero");

    const bool auditThisStep = step <= 1 || step % std::max(1, params.summaryEvery) == 0;
    KineticInterfaceAccumulator0493x9u* auditDev = nullptr;
    if (auditThisStep) {
        check_cuda_0400(cudaMemset(ws.kineticAccum0493x9u.data(), 0, sizeof(KineticInterfaceAccumulator0493x9u)),
                        "0493x9u audit zero");
        auditDev = ws.kineticAccum0493x9u.data();
    }

    q6_x9t_deposit_total_a_moments<<<particleBlocks, threads>>>(particles, cells, nParticles, phaseAType,
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data());
    check_cuda_0400(cudaGetLastError(), "0493x9u total-A deposit launch");

    q6_x9u_classify_support_exits<<<particleBlocks, threads>>>(particles, cells, nParticles, phaseAlpha0493x6c,
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data(),
        ws.kineticRefM0493x9t.data(), ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
        ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data(),
        ws.kineticRefNx0493x9u.data(), ws.kineticRefNy0493x9u.data(), phaseAType,
        grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt, periodicX, periodicY, r,
        static_cast<unsigned long long>(step), static_cast<unsigned long long>(params.rngSeed), auditDev);
    check_cuda_0400(cudaGetLastError(), "0493x9u support-exit classification launch");

    q6_x9u_apply_conservative_reflection<<<particleBlocks, threads>>>(particles, cells, nParticles, phaseAlpha0493x6c,
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data(),
        ws.kineticRefM0493x9t.data(), ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
        ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data(),
        ws.kineticRefNx0493x9u.data(), ws.kineticRefNy0493x9u.data(), phaseAType,
        params.phaseInterfaceEvaporationTargetType, grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt,
        periodicX, periodicY, r, static_cast<unsigned long long>(step),
        static_cast<unsigned long long>(params.rngSeed), auditDev);
    check_cuda_0400(cudaGetLastError(), "0493x9u conservative reflection launch");

    check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)), "0493x9u cell refresh counter zero");
    q6_zero_cell_moments_only_0493w5<<<cellBlocks, threads>>>(cells);
    check_cuda_0400(cudaGetLastError(), "0493x9u cell moments reset launch");
    q6_thermostat_deposit_moments_from_cell_ids_0400<<<particleBlocks, threads>>>(particles, cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "0493x9u cell moments redeposit launch");
    q6_finalize_cells_0400<<<cellBlocks, threads>>>(cells, ws.counter.data());
    check_cuda_0400(cudaGetLastError(), "0493x9u cell moments finalize launch");

    if (auditThisStep) {
        KineticInterfaceAccumulator0493x9u audit{};
        check_cuda_0400(cudaMemcpy(&audit, ws.kineticAccum0493x9u.data(), sizeof(audit), cudaMemcpyDeviceToHost),
                        "0493x9u audit download");
        append_kinetic_interface_audit_0493x9u(params, step, time, audit);
        append_kinetic_interface_diagnostic_0493x9v(params, step, time, audit);
    }
    return true;
}


void append_kinetic_crossing_audit_0493x9x(
    const SimulationParams& params,
    int step,
    double time,
    const KineticCrossingAccumulator0493x9x& a) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_phase_kinetic_crossing_0493x9z.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) || std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) throw std::runtime_error("0493x9x failed to open kinetic crossing audit CSV: " + path.string());

    if (header) {
        out << "step,time,reflectionFraction,evaporationTargetType,"
               "phaseAOuterCellParticles,shellParticles,deepOuterParticles,"
               "interiorCrossings,shellGuardCrossings,startBelowHalf,"
               "pointwiseOuterRoutedToShell,pointwiseInteriorOuterCell,"
               "bisectionInteriorCrossings,bisectionFallbacks,"
               "selectedReflections,transmittedCrossings,appliedReflections,"
               "unsupportedReflections,unsupportedInvalidBath,"
               "unsupportedInvalidDonorGroup,unsupportedNoReceiverMass,"
               "unsupportedNormalCancellation,unsupportedGroupNotOutward,"
               "appliedStillOutwardRelative,appliedInteriorPredictedOutside,"
               "crossingPointNormalFallbacks,endpointSealCorrections,"
               "endpointSealSampleFallbacks,appliedInteriorFinalOutside,"
               "shellRecoverableParticles,shellHardRetentionCandidates,"
               "shellHardRetentionAlreadyInside,shellHardRetentionCorrections,"
               "shellHardRetentionFallbacks,shellHardRetentionFinalOutside,"
               "hardFinalEndpointChecks,hardFinalEndpointOutsideBefore,"
               "hardFinalReceiverOutsideBefore,hardFinalNeutralOutsideBefore,"
               "hardFinalEndpointCorrections,hardFinalMirrorAttempts,"
               "hardFinalMirrorAccepted,hardFinalMirrorNormalFallbacks,"
               "hardFinalMirrorHardFallbacks,hardFinalLocalAnchorCorrections,"
               "hardFinalLocalAnchorMisses,hardFinalEndpointOutsideAfter,"
               "convertedParticles,individualDonorReflections,receiverCorrectedParticles,"
               "reactionActiveCells,reactionFeasibleCells,reactionNoReceiverCells,"
               "reactionEnergyFloorCells,reactionThermalDegenerateCells,"
               "crossingFractionMean,"
               "outwardRelativeNormalSpeedMean,reflectedMass,transmittedMass,"
               "deltaPx,deltaPy,deltaKineticEnergy,positionCorrectionAbsMean,"
               "endpointSealCorrectionAbsMean,shellHardRetentionCorrectionAbsMean,"
               "hardFinalEndpointCorrectionAbsMean,"
               "reactionEnergyResidualAbs,reactionDeltaUMagnitudeMean,"
               "reactionLambdaDeviationAbsMean,"
               "analyticConservativeReactionCells,analyticPositiveScaleCells,"
               "analyticInwardCells,analyticNonInwardPositiveCells,"
               "analyticTrivialCells,analyticInvalidCells,"
               "analyticDonorScaleMean,analyticDonorScaleAbsFromSpecularMean,"
               "globalReactionActive,globalReactionTrivial,globalReactionInvalid,"
               "globalReactionDonorCells,globalReactionReceiverCells,"
               "globalReactionA,globalReactionH,globalReactionSNorm,"
               "globalReactionCellSNormSum,globalReactionCancellationRatio,"
               "globalReactionReceiverMass,globalReactionScale,"
               "globalReactionDeltaUMagnitude,globalReactionFormulaResidual,"
               "mesoReactionBlockCells,mesoReactionShiftX,mesoReactionShiftY,"
               "mesoReactionReservoirSlots,mesoReactionActiveReservoirs,"
               "mesoReactionTrivialReservoirs,mesoReactionInvalidReservoirs,"
               "mesoReactionNoReceiverReservoirs,mesoReactionDonorCells,"
               "mesoReactionReceiverCells,mesoReactionReceiverMassSum,"
               "mesoReactionScaleMean,mesoReactionScaleAbsFromSpecularMean,"
               "mesoReactionDeltaUMagnitudeMean,mesoReactionCancellationMean,"
               "mesoReactionFormulaResidualAbsSum,"
               "simpleSpecularReflections,simpleSpecularInteriorCollisions,"
               "simpleSpecularShellReflections,simpleSpecularNonPositiveLabNormal,"
               "simpleSpecularInteriorFinalOutside,simpleSpecularShellFinalOutside,"
               "simpleSpecularSpeedSqAbsErrorSum,simpleSpecularSpeedSqReferenceSum,"
               "simpleSpecularPositionShiftAbsSum,"
               "localFrameSpecularReflections,localFrameInteriorCollisions,"
               "localFrameShellReflections,localFrameRelativeStillOutward,"
               "localFrameInteriorEndpointOuter,localFrameShellEndpointOuter,"
               "localFrameRelativeSpeedSqAbsErrorSum,"
               "localFrameRelativeSpeedSqReferenceSum,"
               "localFrameLabSpeedSqChangeSum,localFrameLabSpeedSqAbsChangeSum,"
               "localFramePositionShiftAbsSum,"
               "preWallInterfaceCells,preWallVelocityCells,"
               "preWallPositiveVnCells,preWallNegativeVnCells,"
               "preWallVnSum,preWallVnSqSum,preWallAbsVnSum,"
               "preWallVelocityMassSum,preWallMassVnSum,"
               "preWallNetNormalFluxProxy,preWallInterfaceLengthProxy,"
               "preWallAlphaArea,preWallLowerTipScore,preWallLowerTipY,"
               "preWallLowerTipCells,preWallLowerTipPositiveVnCells,"
               "preWallLowerTipNegativeVnCells,preWallLowerTipVnSum,"
               "preWallLowerTipVnSqSum,preWallLowerTipAbsVnSum,"
               "preWallLowerTipMassSum,preWallLowerTipMassVnSum,"
               "movingWallInterfaceCellsBuilt,movingWallInterfaceVelocityFallbacks,"
               "movingWallInvalidInterfaceCells,movingWallParticlesWithCandidate,"
               "movingWallOldStationaryCrossingCandidates,"
               "movingWallOldStationaryCrossingReleased,movingWallCollisions,"
               "movingWallAdvanceCollisions,movingWallRecedeCollisions,"
               "movingWallStationaryCollisions,movingWallMultipleCollisionCandidates,"
               "movingWallRelativeStillOutward,movingWallFinalRelativeOutside,"
               "movingWallMeanCollisionTimeFraction,movingWallMeanWallVn,"
               "movingWallRmsWallVn,movingWallMeanAbsWallVn,"
               "movingWallRelativeSpeedSqAbsErrorSum,"
               "movingWallRelativeSpeedSqReferenceSum,"
               "movingWallImpulseX,movingWallImpulseY,movingWallImpulseAbsSum,"
               "movingWallPositionShiftAbsSum,"
               "continuousWallDualCellsVisited,continuousWallInterfaceDualCells,"
               "continuousWallSegmentsBuilt,continuousWallAmbiguousDualCells,"
               "continuousWallInvalidDualCells,continuousWallParticlesWithCandidate,"
               "continuousWallOldStationaryCrossingCandidates,"
               "continuousWallOldStationaryCrossingReleased,"
               "continuousWallNoNearbySegment,continuousWallCandidateNoHit,"
               "continuousWallCollisions,continuousWallSecondCollisions,"
               "continuousWallThirdCollisions,continuousWallCollisionLimitReached,"
               "continuousWallMultipleCollisionCandidates,"
               "continuousWallRelativeStillOutward,"
               "continuousWallMeanCollisionTimeFraction,continuousWallMeanWallVn,"
               "continuousWallRmsWallVn,continuousWallMeanAbsWallVn,"
               "continuousWallRelativeSpeedSqAbsErrorSum,"
               "continuousWallRelativeSpeedSqReferenceSum,"
               "continuousWallImpulseX,continuousWallImpulseY,"
               "continuousWallImpulseAbsSum,continuousWallPositionShiftAbsSum,"
               "q6ThermalHydroCapturedCells,q6ThermalInterfaceEndpointSamples,"
               "q6ThermalHydroFallbacks,q6ThermalMeanHydroVn,"
               "q6ThermalRmsHydroVn,q6ThermalMeanAbsHydroVn,"
               "q6ThermalMeanThickness,"
               "x10pInitialOutside,x10pInitialOverlapResolved,"
               "x10pInitialOverlapOutwardReflected,"
               "x10pInitialOverlapInwardReleased,"
               "x10pInitialOutsideTooDeep,"
               "x10pInitialOverlapPenetrationSum,"
               "x10pInitialOverlapMaxPenetration,"
               "x10qWideSearchTriggered,x10qWideSearchFoundSegment,"
               "x10qOrphanNoSegmentAfterWideSearch,"
               "x10qDeepOverlapResolved,x10qOverlapResolveFailure,"
               "x10qResolvedNearestDistanceMax,"
               "contract\n";
    }

    const unsigned long long crossings = a.interiorCrossings + a.shellGuardCrossings;
    const double meanS = crossings > 0ull ? a.crossingFractionSum / static_cast<double>(crossings) : 0.0;
    const double meanOut = crossings > 0ull ? a.outwardRelativeNormalSpeedSum / static_cast<double>(crossings) : 0.0;
    const double meanCorr = a.appliedReflections > 0ull ?
        a.positionCorrectionAbsSum / static_cast<double>(a.appliedReflections) : 0.0;
    const double meanSealCorr = a.endpointSealCorrections > 0ull ?
        a.endpointSealCorrectionAbsSum / static_cast<double>(a.endpointSealCorrections) : 0.0;
    const double meanShellRetentionCorr = a.shellHardRetentionCorrections > 0ull ?
        a.shellHardRetentionCorrectionAbsSum / static_cast<double>(a.shellHardRetentionCorrections) : 0.0;
    const double meanHardFinalCorr = a.hardFinalEndpointCorrections > 0ull ?
        a.hardFinalEndpointCorrectionAbsSum /
            static_cast<double>(a.hardFinalEndpointCorrections) : 0.0;
    const double meanReactionDU = a.reactionActiveCells > 0ull ?
        a.reactionDeltaUMagnitudeSum / static_cast<double>(a.reactionActiveCells) : 0.0;
    const double meanLambdaDev = a.reactionActiveCells > 0ull ?
        a.reactionLambdaDeviationAbsSum / static_cast<double>(a.reactionActiveCells) : 0.0;
    const double meanAnalyticScale = a.analyticPositiveScaleCells > 0ull ?
        a.analyticDonorScaleSum / static_cast<double>(a.analyticPositiveScaleCells) : 0.0;
    const double meanAnalyticScaleAbsFrom2 = a.analyticPositiveScaleCells > 0ull ?
        a.analyticDonorScaleAbsFromSpecularSum /
            static_cast<double>(a.analyticPositiveScaleCells) : 0.0;
    const double meanMesoScale =
        a.mesoReactionActiveReservoirs > 0ull ?
        a.mesoReactionScaleSum /
            static_cast<double>(a.mesoReactionActiveReservoirs) : 0.0;
    const double meanMesoScaleAbsFrom2 =
        a.mesoReactionActiveReservoirs > 0ull ?
        a.mesoReactionScaleAbsFromSpecularSum /
            static_cast<double>(a.mesoReactionActiveReservoirs) : 0.0;
    const double meanMesoDU =
        a.mesoReactionActiveReservoirs > 0ull ?
        a.mesoReactionDeltaUMagnitudeSum /
            static_cast<double>(a.mesoReactionActiveReservoirs) : 0.0;
    const double meanMesoCancellation =
        a.mesoReactionActiveReservoirs > 0ull ?
        a.mesoReactionCancellationSum /
            static_cast<double>(a.mesoReactionActiveReservoirs) : 0.0;
    const double movingWallMeanTime = a.movingWallCollisions > 0ull ?
        a.movingWallCollisionTimeFractionSum /
            static_cast<double>(a.movingWallCollisions) : 0.0;
    const double movingWallMeanVn = a.movingWallCollisions > 0ull ?
        a.movingWallWallVnSum /
            static_cast<double>(a.movingWallCollisions) : 0.0;
    const double movingWallRmsVn = a.movingWallCollisions > 0ull ?
        sqrt(fmax(0.0, a.movingWallWallVnSqSum /
            static_cast<double>(a.movingWallCollisions))) : 0.0;
    const double movingWallMeanAbsVn = a.movingWallCollisions > 0ull ?
        a.movingWallWallVnAbsSum /
            static_cast<double>(a.movingWallCollisions) : 0.0;
    const double continuousWallMeanTime = a.continuousWallCollisions > 0ull ?
        a.continuousWallCollisionTimeFractionSum /
            static_cast<double>(a.continuousWallCollisions) : 0.0;
    const double continuousWallMeanVn = a.continuousWallCollisions > 0ull ?
        a.continuousWallWallVnSum /
            static_cast<double>(a.continuousWallCollisions) : 0.0;
    const double continuousWallRmsVn = a.continuousWallCollisions > 0ull ?
        sqrt(fmax(0.0, a.continuousWallWallVnSqSum /
            static_cast<double>(a.continuousWallCollisions))) : 0.0;
    const double continuousWallMeanAbsVn = a.continuousWallCollisions > 0ull ?
        a.continuousWallWallVnAbsSum /
            static_cast<double>(a.continuousWallCollisions) : 0.0;
    const double q6ThermalMeanHydroVn = a.q6ThermalInterfaceEndpointSamples > 0ull ?
        a.q6ThermalHydroVnSum /
            static_cast<double>(a.q6ThermalInterfaceEndpointSamples) : 0.0;
    const double q6ThermalRmsHydroVn = a.q6ThermalInterfaceEndpointSamples > 0ull ?
        sqrt(fmax(0.0, a.q6ThermalHydroVnSqSum /
            static_cast<double>(a.q6ThermalInterfaceEndpointSamples))) : 0.0;
    const double q6ThermalMeanAbsHydroVn = a.q6ThermalInterfaceEndpointSamples > 0ull ?
        a.q6ThermalHydroAbsVnSum /
            static_cast<double>(a.q6ThermalInterfaceEndpointSamples) : 0.0;
    const double q6ThermalMeanThickness = a.q6ThermalInterfaceEndpointSamples > 0ull ?
        a.q6ThermalThicknessSum /
            static_cast<double>(a.q6ThermalInterfaceEndpointSamples) : 0.0;

    out << std::setprecision(17)
        << step << ',' << time << ','
        << params.phaseInterfaceKineticReflectionFraction << ','
        << params.phaseInterfaceEvaporationTargetType << ','
        << a.phaseAOuterCellParticles << ',' << a.shellParticles << ',' << a.deepOuterParticles << ','
        << a.interiorCrossings << ',' << a.shellGuardCrossings << ',' << a.startBelowHalf << ','
        << a.pointwiseOuterRoutedToShell << ',' << a.pointwiseInteriorOuterCell << ','
        << a.bisectionInteriorCrossings << ',' << a.bisectionFallbacks << ','
        << a.selectedReflections << ',' << a.transmittedCrossings << ',' << a.appliedReflections << ','
        << a.unsupportedReflections << ',' << a.unsupportedInvalidBath << ','
        << a.unsupportedInvalidDonorGroup << ',' << a.unsupportedNoReceiverMass << ','
        << a.unsupportedNormalCancellation << ',' << a.unsupportedGroupNotOutward << ','
        << a.appliedStillOutwardRelative << ',' << a.appliedInteriorPredictedOutside << ','
        << a.crossingPointNormalFallbacks << ',' << a.endpointSealCorrections << ','
        << a.endpointSealSampleFallbacks << ',' << a.appliedInteriorFinalOutside << ','
        << a.shellRecoverableParticles << ',' << a.shellHardRetentionCandidates << ','
        << a.shellHardRetentionAlreadyInside << ',' << a.shellHardRetentionCorrections << ','
        << a.shellHardRetentionFallbacks << ',' << a.shellHardRetentionFinalOutside << ','
        << a.hardFinalEndpointChecks << ',' << a.hardFinalEndpointOutsideBefore << ','
        << a.hardFinalReceiverOutsideBefore << ',' << a.hardFinalNeutralOutsideBefore << ','
        << a.hardFinalEndpointCorrections << ',' << a.hardFinalMirrorAttempts << ','
        << a.hardFinalMirrorAccepted << ',' << a.hardFinalMirrorNormalFallbacks << ','
        << a.hardFinalMirrorHardFallbacks << ',' << a.hardFinalLocalAnchorCorrections << ','
        << a.hardFinalLocalAnchorMisses << ',' << a.hardFinalEndpointOutsideAfter << ','
        << a.convertedParticles << ','
        << a.individualDonorReflections << ',' << a.receiverCorrectedParticles << ','
        << a.reactionActiveCells << ',' << a.reactionFeasibleCells << ','
        << a.reactionNoReceiverCells << ',' << a.reactionEnergyFloorCells << ','
        << a.reactionThermalDegenerateCells << ','
        << meanS << ',' << meanOut << ','
        << a.reflectedMass << ',' << a.transmittedMass << ','
        << a.deltaPx << ',' << a.deltaPy << ',' << a.deltaKineticEnergy << ',' << meanCorr << ','
        << meanSealCorr << ',' << meanShellRetentionCorr << ',' << meanHardFinalCorr << ','
        << a.reactionEnergyResidualAbsSum << ',' << meanReactionDU << ',' << meanLambdaDev << ','
        << a.analyticConservativeReactionCells << ',' << a.analyticPositiveScaleCells << ','
        << a.analyticInwardCells << ',' << a.analyticNonInwardPositiveCells << ','
        << a.analyticTrivialCells << ',' << a.analyticInvalidCells << ','
        << meanAnalyticScale << ',' << meanAnalyticScaleAbsFrom2 << ','
        << a.globalReactionActive << ',' << a.globalReactionTrivial << ','
        << a.globalReactionInvalid << ',' << a.globalReactionDonorCells << ','
        << a.globalReactionReceiverCells << ',' << a.globalReactionA << ','
        << a.globalReactionH << ',' << a.globalReactionSNorm << ','
        << a.globalReactionCellSNormSum << ','
        << a.globalReactionCancellationRatio << ','
        << a.globalReactionReceiverMass << ',' << a.globalReactionScale << ','
        << a.globalReactionDeltaUMagnitude << ','
        << a.globalReactionFormulaResidual << ','
        << a.mesoReactionBlockCells << ',' << a.mesoReactionShiftX << ','
        << a.mesoReactionShiftY << ',' << a.mesoReactionReservoirSlots << ','
        << a.mesoReactionActiveReservoirs << ','
        << a.mesoReactionTrivialReservoirs << ','
        << a.mesoReactionInvalidReservoirs << ','
        << a.mesoReactionNoReceiverReservoirs << ','
        << a.mesoReactionDonorCells << ',' << a.mesoReactionReceiverCells << ','
        << a.mesoReactionReceiverMassSum << ',' << meanMesoScale << ','
        << meanMesoScaleAbsFrom2 << ',' << meanMesoDU << ','
        << meanMesoCancellation << ','
        << a.mesoReactionFormulaResidualAbsSum << ','
        << a.simpleSpecularReflections << ','
        << a.simpleSpecularInteriorCollisions << ','
        << a.simpleSpecularShellReflections << ','
        << a.simpleSpecularNonPositiveLabNormal << ','
        << a.simpleSpecularInteriorFinalOutside << ','
        << a.simpleSpecularShellFinalOutside << ','
        << a.simpleSpecularSpeedSqAbsErrorSum << ','
        << a.simpleSpecularSpeedSqReferenceSum << ','
        << a.simpleSpecularPositionShiftAbsSum << ','
        << a.localFrameSpecularReflections << ','
        << a.localFrameInteriorCollisions << ','
        << a.localFrameShellReflections << ','
        << a.localFrameRelativeStillOutward << ','
        << a.localFrameInteriorEndpointOuter << ','
        << a.localFrameShellEndpointOuter << ','
        << a.localFrameRelativeSpeedSqAbsErrorSum << ','
        << a.localFrameRelativeSpeedSqReferenceSum << ','
        << a.localFrameLabSpeedSqChangeSum << ','
        << a.localFrameLabSpeedSqAbsChangeSum << ','
        << a.localFramePositionShiftAbsSum << ','
        << a.preWallInterfaceCells << ',' << a.preWallVelocityCells << ','
        << a.preWallPositiveVnCells << ',' << a.preWallNegativeVnCells << ','
        << a.preWallVnSum << ',' << a.preWallVnSqSum << ','
        << a.preWallAbsVnSum << ',' << a.preWallVelocityMassSum << ','
        << a.preWallMassVnSum << ',' << a.preWallNetNormalFluxProxy << ','
        << a.preWallInterfaceLengthProxy << ',' << a.preWallAlphaArea << ','
        << a.preWallLowerTipScore << ',' << a.preWallLowerTipY << ','
        << a.preWallLowerTipCells << ','
        << a.preWallLowerTipPositiveVnCells << ','
        << a.preWallLowerTipNegativeVnCells << ','
        << a.preWallLowerTipVnSum << ',' << a.preWallLowerTipVnSqSum << ','
        << a.preWallLowerTipAbsVnSum << ',' << a.preWallLowerTipMassSum << ','
        << a.preWallLowerTipMassVnSum << ','
        << a.movingWallInterfaceCellsBuilt << ','
        << a.movingWallInterfaceVelocityFallbacks << ','
        << a.movingWallInvalidInterfaceCells << ','
        << a.movingWallParticlesWithCandidate << ','
        << a.movingWallOldStationaryCrossingCandidates << ','
        << a.movingWallOldStationaryCrossingReleased << ','
        << a.movingWallCollisions << ','
        << a.movingWallAdvanceCollisions << ','
        << a.movingWallRecedeCollisions << ','
        << a.movingWallStationaryCollisions << ','
        << a.movingWallMultipleCollisionCandidates << ','
        << a.movingWallRelativeStillOutward << ','
        << a.movingWallFinalRelativeOutside << ','
        << movingWallMeanTime << ',' << movingWallMeanVn << ','
        << movingWallRmsVn << ',' << movingWallMeanAbsVn << ','
        << a.movingWallRelativeSpeedSqAbsErrorSum << ','
        << a.movingWallRelativeSpeedSqReferenceSum << ','
        << a.movingWallImpulseX << ',' << a.movingWallImpulseY << ','
        << a.movingWallImpulseAbsSum << ','
        << a.movingWallPositionShiftAbsSum << ','
        << a.continuousWallDualCellsVisited << ','
        << a.continuousWallInterfaceDualCells << ','
        << a.continuousWallSegmentsBuilt << ','
        << a.continuousWallAmbiguousDualCells << ','
        << a.continuousWallInvalidDualCells << ','
        << a.continuousWallParticlesWithCandidate << ','
        << a.continuousWallOldStationaryCrossingCandidates << ','
        << a.continuousWallOldStationaryCrossingReleased << ','
        << a.continuousWallNoNearbySegment << ','
        << a.continuousWallCandidateNoHit << ','
        << a.continuousWallCollisions << ','
        << a.continuousWallSecondCollisions << ','
        << a.continuousWallThirdCollisions << ','
        << a.continuousWallCollisionLimitReached << ','
        << a.continuousWallMultipleCollisionCandidates << ','
        << a.continuousWallRelativeStillOutward << ','
        << continuousWallMeanTime << ',' << continuousWallMeanVn << ','
        << continuousWallRmsVn << ',' << continuousWallMeanAbsVn << ','
        << a.continuousWallRelativeSpeedSqAbsErrorSum << ','
        << a.continuousWallRelativeSpeedSqReferenceSum << ','
        << a.continuousWallImpulseX << ',' << a.continuousWallImpulseY << ','
        << a.continuousWallImpulseAbsSum << ','
        << a.continuousWallPositionShiftAbsSum << ','
        << a.q6ThermalHydroCapturedCells << ','
        << a.q6ThermalInterfaceEndpointSamples << ','
        << a.q6ThermalHydroFallbacks << ','
        << q6ThermalMeanHydroVn << ',' << q6ThermalRmsHydroVn << ','
        << q6ThermalMeanAbsHydroVn << ',' << q6ThermalMeanThickness << ','
        << a.x10pInitialOutside << ','
        << a.x10pInitialOverlapResolved << ','
        << a.x10pInitialOverlapOutwardReflected << ','
        << a.x10pInitialOverlapInwardReleased << ','
        << a.x10pInitialOutsideTooDeep << ','
        << a.x10pInitialOverlapPenetrationSum << ','
        << a.x10pInitialOverlapMaxPenetration << ','
        << a.x10qWideSearchTriggered << ','
        << a.x10qWideSearchFoundSegment << ','
        << a.x10qOrphanNoSegmentAfterWideSearch << ','
        << a.x10qDeepOverlapResolved << ','
        << a.x10qOverlapResolveFailure << ','
        << a.x10qResolvedNearestDistanceMax << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
           "alpha0.5-four-bisection-last-inside;one-cell-shell-guard;no-halo-search;"
           "individual-donor-crossing-point-normal-reflection;"
           "r1-analytic-collective-exact-momentum-energy-reaction;"
           "r1-no-receiver-thermal-lambda-no-energy-floor;rlt1-legacy-reaction-retained;"
           "interior-reflected-endpoint-alpha-ge-half-seal;"
           "r1-shell-position-seal-reflected-donors-only;"
           "r1-no-universal-alpha-endpoint-barrier;"
           "r1-mobile-interface-relative-thermal-donor-only-retention;"
           "r1-global-single-component-reservoir-ablation;"
           "0493x10g-hierarchical-global-reduction-performance-only;"
           "0493x10h-mobile-interface-relative-thermal-retention;"
           "0493x10i-shifted-mesoscopic-reservoirs;"
           "0493x10j-simple-lab-specular-ablation;"
           "0493x10k-local-frame-specular-ablation;"
           "0493x10l-prewall-interface-diagnostics;"
           "0493x10m-moving-interface-wall;"
           "0493x10m-fix1-local-alpha-helper-order-independent;"
           "0493x10n-q6-continuous-moving-interface;"
           "0493x10o-q6-hydrodynamic-thermal-interface;"
           "0493x10p-initial-overlap-resolution;"
           "0493x10q-wide-overlap-recovery;"
           "x10q-normal-swept-search-remains-3x3;"
           "x10q-initial-overlap-fallback-ring-7x7-only-when-no-3x3-segment;"
           "x10q-known-deep-overlap-always-resolved;"
           "x10p-nearest-finite-moving-segment-before-s0-sign;"
           "x10p-outward-overlap-specular-inward-overlap-depenetrate-only;"
           "x10p-no-extra-particle-pass;"
           "x10o-q6-projected-face-plus-cell-hydrodynamic-velocity;"
           "x10o-normal-only-interface-motion;"
           "x10o-thermal-envelope-dt-sqrt-kbt-over-m;"
           "x10n-shared-q6-theta-edge-crossings;"
           "x10n-marching-squares-continuous-dual-grid-polyline;"
           "x10n-shared-endpoint-post-q6-b1-liquid-velocity;"
           "x10n-moving-segment-event-collision-up-to-three-impacts;"
           "x10n-free-surface-impulse-diagnostic-only;"
           "x10m-alpha0.5-one-step-local-moving-boundary;"
           "x10m-wall-vn-from-post-q6-b1-liquid-cell-velocity;"
           "x10m-event-driven-moving-plane-specular-collision;"
           "x10m-boundary-impulse-recorded-not-fed-back-for-free-surface;"
           "x10m-local-plane-primitive-prepares-mobile-solid-collision-path;"
           "x10l-passive-after-q6-b1-before-kinetic-wall;"
           "x10k-v-minus-2-vminusub-dot-n-n;"
           "x10k-relative-speed-norm-conserving-no-interface-counterreaction;"
           "x10k-runtime-overrides-x10j-and-r1-mesoscopic-reaction-when-enabled;"
           "x10j-runtime-overrides-r1-mesoscopic-reaction-when-enabled;"
           "x10j-lab-speed-norm-conserving-no-interface-counterreaction;"
           "x10j-interior-collision-time-kinematics-no-endpoint-seal;"
           "x10j-no-shell-position-recovery;"
           "mesoscopic-block-size-runtime-4-or-5;"
           "deterministic-step-shifted-reaction-partition;"
           "multi-component-not-production-no-ccl;"
           "no-merge-no-resampling;"
           "same-three-x9-particle-passes-plus-one-cell-kernel;deterministic-hash" << '\n';
}

bool apply_kinetic_interface_reflection_0493x9x(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    ResidentWorkspace0400& ws,
    const SimulationParams& params,
    const CellGrid& grid,
    int step,
    double time,
    std::uint64_t nParticles,
    int threads,
    int cellBlocks,
    int particleBlocks,
    int periodicX,
    int periodicY,
    std::uint32_t phaseAType,
    const double* phaseAlpha0493x6c,
    bool geometryValid0493x6c) {
    const double r = params.phaseInterfaceKineticReflectionFraction;
    if (!(r > 0.0)) return false;
    const bool q6ThermalInterfaceWall0493x10o =
        r >= 1.0 &&
        env_int_0400("MPCD_X10O_Q6_THERMAL_INTERFACE_WALL", 0) != 0;
    const bool initialOverlapResolution0493x10p =
        q6ThermalInterfaceWall0493x10o &&
        env_int_0400("MPCD_X10P_INITIAL_OVERLAP_RESOLUTION", 1) != 0;
    const bool continuousInterfaceWall0493x10n =
        !q6ThermalInterfaceWall0493x10o && r >= 1.0 &&
        env_int_0400("MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL", 0) != 0;
    const bool movingInterfaceWall0493x10m =
        !q6ThermalInterfaceWall0493x10o && !continuousInterfaceWall0493x10n && r >= 1.0 &&
        env_int_0400("MPCD_X10M_MOVING_INTERFACE_WALL", 0) != 0;
    const bool localFrameSpecularAblation =
        !q6ThermalInterfaceWall0493x10o && !continuousInterfaceWall0493x10n &&
        !movingInterfaceWall0493x10m && r >= 1.0 &&
        env_int_0400("MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION", 0) != 0;
    const bool simpleSpecularAblation =
        !q6ThermalInterfaceWall0493x10o && !continuousInterfaceWall0493x10n &&
        !movingInterfaceWall0493x10m && !localFrameSpecularAblation && r >= 1.0 &&
        env_int_0400("MPCD_X10J_SIMPLE_SPECULAR_ABLATION", 0) != 0;
    const bool anySimpleSpecularAblation =
        q6ThermalInterfaceWall0493x10o || continuousInterfaceWall0493x10n ||
        movingInterfaceWall0493x10m || simpleSpecularAblation ||
        localFrameSpecularAblation;
    const bool preWallInterfaceDiagnostics0493x10l =
        env_int_0400("MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS", 0) != 0;
    if (!geometryValid0493x6c || phaseAlpha0493x6c == nullptr)
        throw std::runtime_error("0493x9x kinetic reflection requested without valid resident x6c alpha geometry");

    double thermalThickness0493x10o = 0.0;
    if (q6ThermalInterfaceWall0493x10o) {
        if (!ws.kineticQ6HydroFieldValid0493x10o ||
            ws.kineticQ6HydroFieldStep0493x10o != step ||
            ws.kineticQ6HydroFieldType0493x10o != phaseAType) {
            throw std::runtime_error(
                "0493x10o requested without same-step projected Q6 liquid hydrodynamic field");
        }
        const double particleMass0493x10o = fmax(
            1.0e-30, env_double_0400("MPCD_X10O_THERMAL_PARTICLE_MASS", 1.0));
        const double thermalSigmas0493x10o = fmax(
            0.0, env_double_0400("MPCD_X10O_THERMAL_SIGMAS", 3.0));
        const double thermalMaxCells0493x10o = fmax(
            0.0, env_double_0400("MPCD_X10O_THERMAL_MAX_CELLS", 0.75));
        const double thermalKBT0493x10o =
            params.thermostatTargetKBT > 0.0 ? params.thermostatTargetKBT : params.kBT;
        const double h0493x10o = fmin(
            params.Lx / static_cast<double>(grid.Nx),
            params.Ly / static_cast<double>(grid.Ny));
        const double ballistic0493x10o = thermalSigmas0493x10o * params.dt *
            sqrt(fmax(0.0, thermalKBT0493x10o) / particleMass0493x10o);
        thermalThickness0493x10o = fmin(
            thermalMaxCells0493x10o * h0493x10o, ballistic0493x10o);
    }

    const int mesoBlockCells =
        std::max(2, std::min(32,
            env_int_0400("MPCD_X10I_REACTION_BLOCK_CELLS", 5)));
    const std::uint64_t mesoHashX = q6_x10i_mix64_host(
        static_cast<std::uint64_t>(step) ^
        (static_cast<std::uint64_t>(params.rngSeed) + 0x10a10493ull));
    const std::uint64_t mesoHashY = q6_x10i_mix64_host(
        mesoHashX ^ 0xd1b54a32d192ed03ull);
    const int mesoShiftX =
        static_cast<int>(mesoHashX % static_cast<std::uint64_t>(mesoBlockCells));
    const int mesoShiftY =
        static_cast<int>(mesoHashY % static_cast<std::uint64_t>(mesoBlockCells));
    const int mesoBlocksX =
        2 + (std::max(1, grid.Nx) - 1) / mesoBlockCells;
    const int mesoBlocksY =
        2 + (std::max(1, grid.Ny) - 1) / mesoBlockCells;
    const int mesoReservoirs = anySimpleSpecularAblation
        ? 1 : mesoBlocksX * mesoBlocksY;

    ws.ensure_kinetic_interface_0493x9x(
        grid.numCells, cellBlocks, mesoReservoirs);
    const std::size_t bytes = static_cast<std::size_t>(grid.numCells) * sizeof(double);
    double* fields[] = {
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data(),
        ws.kineticRefM0493x9t.data(), ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
        ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data(),
        ws.kineticRefNx0493x9u.data(), ws.kineticRefNy0493x9u.data()
    };
    for (double* field : fields)
        check_cuda_0400(cudaMemset(field, 0, bytes), "0493x9x cell field zero");

    const bool auditThisStep = step <= 1 || step % std::max(1, params.summaryEvery) == 0;
    KineticCrossingAccumulator0493x9x* auditDev = nullptr;
    if (auditThisStep) {
        check_cuda_0400(cudaMemset(ws.kineticAccum0493x9x.data(), 0,
            sizeof(KineticCrossingAccumulator0493x9x)), "0493x9x audit zero");
        auditDev = ws.kineticAccum0493x9x.data();
    }

    q6_x9t_deposit_total_a_moments<<<particleBlocks, threads>>>(
        particles, cells, nParticles, phaseAType,
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data());
    check_cuda_0400(cudaGetLastError(), "0493x9x total-A deposit launch");

    if (q6ThermalInterfaceWall0493x10o || continuousInterfaceWall0493x10n) {
        const std::size_t cellCount =
            static_cast<std::size_t>(std::max(1, grid.numCells));
        check_cuda_0400(
            cudaMemset(ws.kineticContinuousSegCount0493x10n.data(), 0,
                       cellCount * sizeof(unsigned char)),
            "0493x10n segment-count zero");
        check_cuda_0400(
            cudaMemset(ws.kineticMovingWallImpulseX0493x10m.data(), 0,
                       cellCount * sizeof(double)),
            "0493x10n interface impulseX zero");
        check_cuda_0400(
            cudaMemset(ws.kineticMovingWallImpulseY0493x10m.data(), 0,
                       cellCount * sizeof(double)),
            "0493x10n interface impulseY zero");
        q6_x10n_build_continuous_interface<<<cellBlocks, threads>>>(
            grid.numCells, grid.Nx, grid.Ny,
            params.Lx, params.Ly, periodicX, periodicY,
            phaseAlpha0493x6c,
            ws.kineticTotalM0493x9t.data(),
            ws.kineticTotalPx0493x9t.data(),
            ws.kineticTotalPy0493x9t.data(),
            q6ThermalInterfaceWall0493x10o ? ws.kineticQ6HydroValid0493x10o.data() : nullptr,
            q6ThermalInterfaceWall0493x10o ? ws.kineticQ6HydroCellUx0493x10o.data() : nullptr,
            q6ThermalInterfaceWall0493x10o ? ws.kineticQ6HydroCellUy0493x10o.data() : nullptr,
            q6ThermalInterfaceWall0493x10o ? ws.kineticQ6HydroFaceUxEast0493x10o.data() : nullptr,
            q6ThermalInterfaceWall0493x10o ? ws.kineticQ6HydroFaceUyNorth0493x10o.data() : nullptr,
            thermalThickness0493x10o,
            q6ThermalInterfaceWall0493x10o ? 1 : 0,
            ws.kineticContinuousSegCount0493x10n.data(),
            ws.kineticContinuousSegAx0493x10n.data(),
            ws.kineticContinuousSegAy0493x10n.data(),
            ws.kineticContinuousSegBx0493x10n.data(),
            ws.kineticContinuousSegBy0493x10n.data(),
            ws.kineticContinuousSegUax0493x10n.data(),
            ws.kineticContinuousSegUay0493x10n.data(),
            ws.kineticContinuousSegUbx0493x10n.data(),
            ws.kineticContinuousSegUby0493x10n.data(),
            auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x10n continuous-interface build launch");
    } else if (movingInterfaceWall0493x10m) {
        const std::size_t cellCount =
            static_cast<std::size_t>(std::max(1, grid.numCells));
        check_cuda_0400(
            cudaMemset(ws.kineticMovingWallActive0493x10m.data(), 0,
                       cellCount * sizeof(unsigned char)),
            "0493x10m moving-wall active zero");
        check_cuda_0400(
            cudaMemset(ws.kineticMovingWallImpulseX0493x10m.data(), 0,
                       cellCount * sizeof(double)),
            "0493x10m moving-wall impulseX zero");
        check_cuda_0400(
            cudaMemset(ws.kineticMovingWallImpulseY0493x10m.data(), 0,
                       cellCount * sizeof(double)),
            "0493x10m moving-wall impulseY zero");

        q6_x10m_build_moving_interface_cells<<<cellBlocks, threads>>>(
            grid.numCells,
            grid.Nx, grid.Ny,
            params.Lx, params.Ly,
            periodicX, periodicY,
            phaseAlpha0493x6c,
            ws.kineticTotalM0493x9t.data(),
            ws.kineticTotalPx0493x9t.data(),
            ws.kineticTotalPy0493x9t.data(),
            ws.kineticMovingWallActive0493x10m.data(),
            ws.kineticMovingWallNx0493x10m.data(),
            ws.kineticMovingWallNy0493x10m.data(),
            ws.kineticMovingWallQx0493x10m.data(),
            ws.kineticMovingWallQy0493x10m.data(),
            ws.kineticMovingWallVn0493x10m.data(),
            auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x10m moving-interface build launch");
    }

    if (preWallInterfaceDiagnostics0493x10l && auditDev) {
        q6_x10l_accumulate_prewall_interface_cells<<<cellBlocks, threads>>>(
            grid.numCells,
            grid.Nx,
            grid.Ny,
            params.Lx,
            params.Ly,
            periodicX,
            periodicY,
            phaseAlpha0493x6c,
            ws.kineticTotalM0493x9t.data(),
            ws.kineticTotalPx0493x9t.data(),
            ws.kineticTotalPy0493x9t.data(),
            auditDev);
        check_cuda_0400(
            cudaGetLastError(),
            "0493x10l pre-wall interface-cell diagnostic launch");

        q6_x10l_accumulate_prewall_lower_tip<<<cellBlocks, threads>>>(
            grid.numCells,
            grid.Nx,
            grid.Ny,
            params.Lx,
            params.Ly,
            periodicX,
            periodicY,
            phaseAlpha0493x6c,
            ws.kineticTotalM0493x9t.data(),
            ws.kineticTotalPx0493x9t.data(),
            ws.kineticTotalPy0493x9t.data(),
            auditDev);
        check_cuda_0400(
            cudaGetLastError(),
            "0493x10l pre-wall lower-tip diagnostic launch");
    }

    if (!anySimpleSpecularAblation) {
        q6_x9z_classify_individual_reflections<<<particleBlocks, threads>>>(
            particles, cells, nParticles, phaseAlpha0493x6c,
            ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data(),
            ws.kineticRefM0493x9t.data(), ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
            ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data(),
            ws.kineticRefNx0493x9u.data(), ws.kineticRefNy0493x9u.data(), phaseAType,
            grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt, periodicX, periodicY, r,
            static_cast<unsigned long long>(step), static_cast<unsigned long long>(params.rngSeed), auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x9x crossing classification launch");
    }

    if (!anySimpleSpecularAblation) {
        if (r >= 1.0) {
            check_cuda_0400(
                cudaMemset(
                    ws.kineticGlobalReaction0493x10f.data(), 0,
                    static_cast<std::size_t>(mesoReservoirs) *
                        sizeof(KineticGlobalReaction0493x10f)),
                "0493x10i mesoscopic reaction array zero");

            q6_x10i_reduce_meso_reactions<<<cellBlocks, threads>>>(
                grid.numCells,
                grid.Nx,
                mesoBlockCells,
                mesoShiftX,
                mesoShiftY,
                mesoBlocksX,
                ws.kineticRefM0493x9t.data(),
                ws.kineticRefPx0493x9t.data(),
                ws.kineticRefPy0493x9t.data(),
                ws.kineticRefNx0493x9u.data(),
                ws.kineticTxM0493x9t.data(),
                ws.kineticTxPx0493x9t.data(),
                ws.kineticTxPy0493x9t.data(),
                ws.kineticGlobalReaction0493x10f.data());
            check_cuda_0400(
                cudaGetLastError(), "0493x10i mesoscopic reaction reduce launch");

            const int mesoFinalizeBlocks =
                (mesoReservoirs + threads - 1) / threads;
            q6_x10i_finalize_meso_reactions<<<mesoFinalizeBlocks, threads>>>(
                mesoReservoirs,
                mesoBlockCells,
                mesoShiftX,
                mesoShiftY,
                ws.kineticGlobalReaction0493x10f.data(),
                auditDev);
            check_cuda_0400(
                cudaGetLastError(), "0493x10i mesoscopic reaction finalize launch");
        } else {
            q6_x9z_prepare_receiver_reaction<<<cellBlocks, threads>>>(
                grid.numCells,
                ws.kineticRefM0493x9t.data(),
                ws.kineticRefPx0493x9t.data(),
                ws.kineticRefPy0493x9t.data(),
                ws.kineticTxM0493x9t.data(),
                ws.kineticTxPx0493x9t.data(),
                ws.kineticTxPy0493x9t.data(),
                ws.kineticRefNx0493x9u.data(),
                ws.kineticRefNy0493x9u.data(),
                ws.kineticTotalM0493x9t.data(),
                ws.kineticTotalPx0493x9t.data(),
                ws.kineticTotalPy0493x9t.data(),
                r,
                auditDev);
            check_cuda_0400(
                cudaGetLastError(), "0493x9z receiver reaction prepare launch");
        }

    }

    if (q6ThermalInterfaceWall0493x10o || continuousInterfaceWall0493x10n) {
        q6_x10n_apply_continuous_moving_interface<<<particleBlocks, threads>>>(
            particles, cells, nParticles,
            phaseAlpha0493x6c,
            ws.kineticContinuousSegCount0493x10n.data(),
            ws.kineticContinuousSegAx0493x10n.data(),
            ws.kineticContinuousSegAy0493x10n.data(),
            ws.kineticContinuousSegBx0493x10n.data(),
            ws.kineticContinuousSegBy0493x10n.data(),
            ws.kineticContinuousSegUax0493x10n.data(),
            ws.kineticContinuousSegUay0493x10n.data(),
            ws.kineticContinuousSegUbx0493x10n.data(),
            ws.kineticContinuousSegUby0493x10n.data(),
            ws.kineticMovingWallImpulseX0493x10m.data(),
            ws.kineticMovingWallImpulseY0493x10m.data(),
            phaseAType,
            grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt,
            periodicX, periodicY,
            initialOverlapResolution0493x10p ? 1 : 0,
            auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x10n continuous-interface collision launch");
    } else if (movingInterfaceWall0493x10m) {
        q6_x10m_apply_moving_interface_wall<<<particleBlocks, threads>>>(
            particles, cells, nParticles,
            phaseAlpha0493x6c,
            ws.kineticMovingWallActive0493x10m.data(),
            ws.kineticMovingWallNx0493x10m.data(),
            ws.kineticMovingWallNy0493x10m.data(),
            ws.kineticMovingWallQx0493x10m.data(),
            ws.kineticMovingWallQy0493x10m.data(),
            ws.kineticMovingWallVn0493x10m.data(),
            ws.kineticMovingWallImpulseX0493x10m.data(),
            ws.kineticMovingWallImpulseY0493x10m.data(),
            phaseAType,
            grid.Nx, grid.Ny,
            params.Lx, params.Ly, params.dt,
            periodicX, periodicY,
            auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x10m moving-interface collision launch");
    } else {
        q6_x9z_apply_individual_reflections<<<particleBlocks, threads>>>(
            particles, cells, nParticles, phaseAlpha0493x6c,
            ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data(),
            ws.kineticRefM0493x9t.data(), ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
            ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data(),
            ws.kineticRefNy0493x9u.data(),
            ws.kineticGlobalReaction0493x10f.data(),
            mesoBlockCells,
            mesoShiftX,
            mesoShiftY,
            mesoBlocksX,
            simpleSpecularAblation ? 1 : 0,
            localFrameSpecularAblation ? 1 : 0,
            phaseAType,
            params.phaseInterfaceEvaporationTargetType,
            grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt, periodicX, periodicY, r,
            static_cast<unsigned long long>(step), static_cast<unsigned long long>(params.rngSeed), auditDev);
        check_cuda_0400(cudaGetLastError(), "0493x9x crossing reflection launch");
    }

    check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                    "0493x9x cell refresh counter zero");
    q6_zero_cell_moments_only_0493w5<<<cellBlocks, threads>>>(cells);
    check_cuda_0400(cudaGetLastError(), "0493x9x cell moments reset launch");
    q6_thermostat_deposit_moments_from_cell_ids_0400<<<particleBlocks, threads>>>(particles, cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "0493x9x cell moments redeposit launch");
    q6_finalize_cells_0400<<<cellBlocks, threads>>>(cells, ws.counter.data());
    check_cuda_0400(cudaGetLastError(), "0493x9x cell moments finalize launch");

    if (auditThisStep) {
        KineticCrossingAccumulator0493x9x audit{};
        check_cuda_0400(cudaMemcpy(&audit, ws.kineticAccum0493x9x.data(), sizeof(audit), cudaMemcpyDeviceToHost),
                        "0493x9x audit download");
        append_kinetic_crossing_audit_0493x9x(params, step, time, audit);
    }
    return true;
}

bool apply_independent_masked_species_q6_0493w5(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    CudaSpeciesCellDeviceView0490h species,
    ResidentWorkspace0400& ws,
    const SimulationParams& params,
    const CellGrid& grid,
    int step,
    double time,
    std::uint64_t nParticles,
    int threads,
    int cellBlocks,
    int particleBlocks,
    std::size_t scalarShared,
    std::size_t pairShared,
    std::size_t tripleShared,
    int periodicX,
    int periodicY,
    double xLowFlux,
    double xHighFlux,
    double yLowFlux,
    double yHighFlux,
    Q6SegmentedIo0409 segmentedIo,
    bool freeSurfaceMode0493x5a,
    bool fuseForceKick0493x4b,
    CudaQ6Resident0400Diagnostics& diag) {
    const auto tSolveAll = Clock0400::now();
    const bool q6GfDiagnosticsThisStep0493x7k =
        !freeSurfaceMode0493x5a ||
        q6_g_f_diagnostics_this_step_0493x7k(params, static_cast<std::uint64_t>(step));
    const bool phaseGeometryResident0493x6c =
        freeSurfaceMode0493x5a &&
        cuda_q6_phase_geometry_resident_0493x6c_requested();
    const bool cutFaceGeometry0493x6d =
        freeSurfaceMode0493x5a &&
        cuda_q6_phase_geometry_cutface_0493x6d_requested();
    const bool phaseInterfaceTopology0493x6e =
        freeSurfaceMode0493x5a &&
        cuda_q6_phase_interface_topology_0493x6e_requested();
    const bool phaseInterfaceStencil0493x6f =
        freeSurfaceMode0493x5a &&
        cuda_q6_phase_interface_stencil_0493x6f_requested();
    const bool phaseGasPressure0493x6g =
        freeSurfaceMode0493x5a &&
        cuda_q6_phase_gas_pressure_0493x6g_requested();
    const bool surfaceTensionActive0493x9d =
        freeSurfaceMode0493x5a && params.surfaceTensionSigma > 0.0;
    const bool contactAngleActive0493x9i =
        freeSurfaceMode0493x5a && params.phaseInterfaceContactAngleDegrees >= 0.0;
    // x9j replaces the x9i hard-normal production closure.  Keep the old
    // closure only behind an explicit test-only environment gate so the x9i
    // baseline runner remains reproducible for A/B comparison.
    const bool contactAngleHardNormalLegacy0493x9i =
        contactAngleActive0493x9i &&
        truthy_0400(std::getenv("MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I"));
    // 0493x9m: use the first p3 normal outside the wall-contaminated support
    // to close contact curvature geometrically.  x9m has precedence over x9l
    // if both experimental gates are accidentally enabled.
    const bool contactAngleOffSupport0493x9m =
        contactAngleActive0493x9i && !contactAngleHardNormalLegacy0493x9i &&
        truthy_0400(std::getenv("MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M"));
    const bool contactAngleWallFace0493x9l =
        contactAngleActive0493x9i && !contactAngleHardNormalLegacy0493x9i &&
        !contactAngleOffSupport0493x9m &&
        truthy_0400(std::getenv("MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L"));
    const bool contactAngleGhostAlpha0493x9j =
        contactAngleActive0493x9i && !contactAngleHardNormalLegacy0493x9i &&
        !contactAngleOffSupport0493x9m && !contactAngleWallFace0493x9l;
    const bool phaseCurvatureDiagnostics0493x9a =
        freeSurfaceMode0493x5a &&
        cuda_q6_phase_curvature_diagnostics_0493x9a_requested();
    const bool phaseCurvatureDiagnostics0493x9b =
        freeSurfaceMode0493x5a &&
        cuda_q6_phase_curvature_diagnostics_0493x9b_requested();
    const bool phaseCurvatureDiagnostics0493x9c =
        freeSurfaceMode0493x5a &&
        cuda_q6_phase_curvature_diagnostics_0493x9c_requested();
    const bool staticDropDiagnostics0493x9e =
        freeSurfaceMode0493x5a &&
        cuda_q6_static_drop_diagnostics_0493x9e_requested();
    const bool ellipseDiagnostics0493x9f =
        staticDropDiagnostics0493x9e &&
        cuda_q6_ellipse_diagnostics_0493x9f_requested();
    const bool staticDropDiagnosticsThisStep0493x9e =
        staticDropDiagnostics0493x9e && q6GfDiagnosticsThisStep0493x7k;
    const bool ellipseDiagnosticsThisStep0493x9f =
        ellipseDiagnostics0493x9f && q6GfDiagnosticsThisStep0493x7k;
    const int curvatureAuditWallMarginCells0493x9b =
        (phaseCurvatureDiagnostics0493x9a || phaseCurvatureDiagnostics0493x9b ||
         phaseCurvatureDiagnostics0493x9c)
            ? cuda_q6_phase_curvature_audit_wall_margin_0493x9b()
            : 0;
    const bool postApplyRegionDiagnostics0493x6hB0 =
        freeSurfaceMode0493x5a &&
        cuda_q6_postapply_region_diagnostics_0493x6h_b0_requested();
    const bool faceToParticleRt0Requested0493x6hB1 =
        cuda_q6_face_to_particle_rt0_0493x6h_b1_requested();
    const bool virialDensityKickRequested0493x7a =
        params.virialDensityKickEnable && params.kVirial > 0.0 &&
        params.betaEOS > 0.0;
    const double densityRelaxationBeta0493x7d =
        params.q6DensityRelaxationTime > 0.0
            ? params.dt / params.q6DensityRelaxationTime
            : params.q6DensityRelaxationBeta;
    const bool densityRelaxationRequested0493x7c =
        densityRelaxationBeta0493x7d > 0.0;
    const bool q6ThermalInterfaceWallRequested0493x10o =
        freeSurfaceMode0493x5a && params.phaseInterfaceKineticReflectionFraction >= 1.0 &&
        env_int_0400("MPCD_X10O_Q6_THERMAL_INTERFACE_WALL", 0) != 0;
    if (faceToParticleRt0Requested0493x6hB1 &&
        (!freeSurfaceMode0493x5a || !fuseForceKick0493x4b)) {
        diag.reason =
            "0493x6h-B1 requires free_surface_masked with fused prestream force+Q6";
        return false;
    }
    const bool postApplyRegionAuditThisStep0493x6hB0 =
        postApplyRegionDiagnostics0493x6hB0 &&
        (step <= 1 || step % std::max(1, params.summaryEvery) == 0);
    const PhaseGasPressureMode0493x6g phaseGasPressureMode0493x6g =
        phaseGasPressure0493x6g ? phase_gas_pressure_mode_0493x6g()
                                : PhaseGasPressureMode0493x6g::Eos;
    const double phaseGasPressureReference0493x6g = env_double_0400(
        "MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G", 0.0);
    const double phaseGasPressureConstant0493x6g = env_double_0400(
        "MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G", 0.0);
    const double phaseGasPressureScale0493x6g = env_double_0400(
        "MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G", 1.0);
    if (cutFaceGeometry0493x6d && phaseInterfaceStencil0493x6f) {
        diag.reason = "0493x6d cut-face and 0493x6f prepared interface stencil are mutually exclusive";
        return false;
    }
    if (cutFaceGeometry0493x6d && !phaseGeometryResident0493x6c) {
        diag.reason = "0493x6d cut-face geometry requires 0493x6c resident geometry";
        return false;
    }
    if (phaseInterfaceTopology0493x6e && !phaseGeometryResident0493x6c) {
        diag.reason = "0493x6e interface topology requires 0493x6c resident geometry";
        return false;
    }
    if (phaseInterfaceStencil0493x6f && !phaseGeometryResident0493x6c) {
        diag.reason = "0493x6f interface stencil requires 0493x6c resident geometry";
        return false;
    }
    if (phaseCurvatureDiagnostics0493x9a && !phaseGeometryResident0493x6c) {
        diag.reason = "0493x9a passive curvature requires 0493x6c resident geometry";
        return false;
    }
    if (phaseCurvatureDiagnostics0493x9b && !phaseGeometryResident0493x6c) {
        diag.reason = "0493x9b passive curvature requires 0493x6c resident geometry";
        return false;
    }
    if (phaseCurvatureDiagnostics0493x9c &&
        (!phaseCurvatureDiagnostics0493x9b || !phaseGeometryResident0493x6c)) {
        diag.reason = "0493x9c passive smoothing sweep requires x9b and x6c";
        return false;
    }
    if (phaseGasPressure0493x6g && !phaseInterfaceStencil0493x6f) {
        diag.reason = "0493x6g gas pressure requires the x6f prepared interface stencil";
        return false;
    }
    if (surfaceTensionActive0493x9d &&
        (!phaseGeometryResident0493x6c || !phaseInterfaceStencil0493x6f ||
         !faceToParticleRt0Requested0493x6hB1 || !fuseForceKick0493x4b)) {
        diag.reason =
            "0493x9d surface tension requires x6c+x6f, B1 and fused prestream Q6-G-F";
        return false;
    }
    if (phaseGasPressure0493x6g && !(phaseGasPressureScale0493x6g >= 0.0)) {
        diag.reason = "0493x6g gas-pressure scale must be finite and non-negative";
        return false;
    }
    if (staticDropDiagnostics0493x9e) {
        ws.staticDropCellAccum0493x9e.ensure(1u);
        ws.staticDropFaceAccum0493x9e.ensure(1u);
        ws.staticDropVelocityAccum0493x9e.ensure(1u);
    }
    if (ellipseDiagnostics0493x9f) {
        ws.ellipseParticleMomentAccum0493x9f.ensure(1u);
        ws.ellipseInterfaceRadiusAccum0493x9f.ensure(1u);
    }
    if (virialDensityKickRequested0493x7a &&
        (!freeSurfaceMode0493x5a || !fuseForceKick0493x4b ||
         !faceToParticleRt0Requested0493x6hB1 ||
         !phaseGeometryResident0493x6c || !phaseInterfaceStencil0493x6f)) {
        diag.reason =
            "0493x7b virial requires x6c+x6f free_surface_masked, fused force Q6 and B1";
        return false;
    }
    if (densityRelaxationRequested0493x7c &&
        (!freeSurfaceMode0493x5a || !fuseForceKick0493x4b ||
         !faceToParticleRt0Requested0493x6hB1 ||
         !phaseGeometryResident0493x6c || !phaseInterfaceStencil0493x6f)) {
        diag.reason =
            "0493x7c density RHS requires x6c+x6f free_surface_masked, fused force Q6 and B1";
        return false;
    }
    if (densityRelaxationRequested0493x7c && virialDensityKickRequested0493x7a) {
        diag.reason =
            "0493x7c density RHS and x7b explicit virial kick are mutually exclusive";
        return false;
    }
    if (phaseGeometryResident0493x6c) {
        ws.phaseGeometryResidentValid0493x6c = false;
        ws.phaseGeometryResidentStep0493x6c = -1;
        ws.phaseWallGeometryValid0493x9h = false;
        ws.phaseWallGeometryStep0493x9h = -1;
    }
    if (phaseInterfaceStencil0493x6f) {
        ws.phaseInterfaceStencilValid0493x6f = false;
        ws.phaseInterfaceStencilStep0493x6f = -1;
    }
    const int speciesCount = static_cast<int>(params.speciesDefinitions.size());
    // 0493x9g: resolve the phase pair once on the host.  Defaults are the exact
    // historical liquid/gas selectors.  The same contract can later attach a
    // wall alpha provider without changing curvature or the Laplace jump.
    const ResolvedPhaseSelector0493x9g phaseA0493x9g =
        resolve_phase_selector_0493x9g(
            params.phaseInterfaceASelector, params.speciesDefinitions);
    const ResolvedPhaseSelector0493x9g phaseB0493x9g =
        resolve_phase_selector_0493x9g(
            params.phaseInterfaceBSelector, params.speciesDefinitions);
    if (freeSurfaceMode0493x5a) {
        if (phaseA0493x9g.kind == PhaseSelectorKind0493x9g::Vacuum ||
            phaseA0493x9g.kind == PhaseSelectorKind0493x9g::Wall ||
            phaseA0493x9g.matchedSpecies == 0 ||
            !(phaseA0493x9g.referenceCellMass > 0.0)) {
            diag.reason = "0493x9g phase A selector does not resolve to positive-reference particle species";
            return false;
        }
        bool overlap0493x9g = false;
        for (const SpeciesDefinition& d : params.speciesDefinitions) {
            overlap0493x9g = overlap0493x9g ||
                (phase_selector_matches_definition_0493x9g(phaseA0493x9g, d) &&
                 phase_selector_matches_definition_0493x9g(phaseB0493x9g, d));
        }
        if (overlap0493x9g) {
            diag.reason = "0493x9g phase A and B selectors overlap registered species";
            return false;
        }
    }
    const bool phaseBWall0493x9h =
        phaseB0493x9g.kind == PhaseSelectorKind0493x9g::Wall;
    if (contactAngleActive0493x9i && phaseBWall0493x9h) {
        diag.reason = "0493x9i contact angle requires A/B fluid phases plus a separate wall provider";
        return false;
    }
    if (contactAngleActive0493x9i && !surfaceTensionActive0493x9d) {
        diag.reason = "0493x9i contact angle requires active surface tension";
        return false;
    }
    const bool wallGeometryRequested0493x9i =
        phaseBWall0493x9h || contactAngleActive0493x9i;
    const int wallLeft0493x9h = q6_wall_like_0409(params.bcLeft) ? 1 : 0;
    const int wallRight0493x9h = q6_wall_like_0409(params.bcRight) ? 1 : 0;
    const int wallBottom0493x9h = q6_wall_like_0409(params.bcBottom) ? 1 : 0;
    const int wallTop0493x9h = q6_wall_like_0409(params.bcTop) ? 1 : 0;
    const bool domainWallGeometry0493x9h =
        wallLeft0493x9h || wallRight0493x9h || wallBottom0493x9h || wallTop0493x9h;
    const bool chiWallGeometryRequested0493x9h =
        wallGeometryRequested0493x9i && params.darcyBrinkmanEnable &&
        params.darcyChiCollisionVpEnable;
    const float* wallChi0493x9h = nullptr;
    int wallChiNx0493x9h = 0;
    int wallChiNy0493x9h = 0;
    bool chiWallGeometry0493x9h = false;
    if (chiWallGeometryRequested0493x9h) {
        chiWallGeometry0493x9h = cuda_darcy_brinkman_0343_device_chi_field(
            params, &wallChi0493x9h, &wallChiNx0493x9h, &wallChiNy0493x9h);
        if (!chiWallGeometry0493x9h || wallChi0493x9h == nullptr ||
            wallChiNx0493x9h != grid.Nx || wallChiNy0493x9h != grid.Ny) {
            diag.reason = "0493x9h wall chi geometry provider unavailable or grid-mismatched";
            return false;
        }
    }
    if (contactAngleGhostAlpha0493x9j && !domainWallGeometry0493x9h) {
        diag.reason = "0493x9j ghost-alpha contact-angle closure currently requires at least one static domain wall; chi-only extension follows later";
        return false;
    }
    if (contactAngleGhostAlpha0493x9j && chiWallGeometry0493x9h) {
        diag.reason = "0493x9j ghost-alpha contact-angle closure does not yet combine domain-wall and chi-wall geometry";
        return false;
    }
    if (contactAngleGhostAlpha0493x9j &&
        !(params.phaseInterfaceContactAngleDegrees > 0.0 &&
          params.phaseInterfaceContactAngleDegrees < 180.0)) {
        diag.reason = "0493x9k sheared-mirror ghost-alpha requires 0 < phaseInterfaceContactAngleDegrees < 180; endpoints are deliberately unsupported";
        return false;
    }
    if (contactAngleOffSupport0493x9m && !domainWallGeometry0493x9h) {
        diag.reason = "0493x9m off-support curvature closure currently requires at least one static domain wall";
        return false;
    }
    if (contactAngleOffSupport0493x9m && chiWallGeometry0493x9h) {
        diag.reason = "0493x9m off-support curvature closure does not yet combine domain-wall and chi-wall geometry";
        return false;
    }
    if (contactAngleOffSupport0493x9m &&
        !(params.phaseInterfaceContactAngleDegrees > 0.0 &&
          params.phaseInterfaceContactAngleDegrees < 180.0)) {
        diag.reason = "0493x9m off-support curvature closure requires 0 < phaseInterfaceContactAngleDegrees < 180";
        return false;
    }
    if (contactAngleWallFace0493x9l && !domainWallGeometry0493x9h) {
        diag.reason = "0493x9l wall-face normal closure currently requires at least one static domain wall";
        return false;
    }
    if (contactAngleWallFace0493x9l && chiWallGeometry0493x9h) {
        diag.reason = "0493x9l wall-face normal closure does not yet combine domain-wall and chi-wall geometry";
        return false;
    }
    if (contactAngleWallFace0493x9l &&
        !(params.phaseInterfaceContactAngleDegrees > 0.0 &&
          params.phaseInterfaceContactAngleDegrees < 180.0)) {
        diag.reason = "0493x9l wall-face normal closure requires 0 < phaseInterfaceContactAngleDegrees < 180";
        return false;
    }
    if (wallGeometryRequested0493x9i && !domainWallGeometry0493x9h &&
        !chiWallGeometry0493x9h) {
        diag.reason = phaseBWall0493x9h
            ? "0493x9h B=wall resolved without domain-wall or chi-wallVP geometry"
            : "0493x9i contact angle resolved without domain-wall or chi-wallVP geometry";
        return false;
    }
    if (wallGeometryRequested0493x9i && !phaseGeometryResident0493x6c) {
        diag.reason = "0493x9i wall/contact geometry requires x6c resident geometry";
        return false;
    }
    if (phaseBWall0493x9h && surfaceTensionActive0493x9d) {
        diag.reason = "0493x9i B=wall remains passive geometry; wetting uses A/B plus separate wall geometry";
        return false;
    }
    if (phaseBWall0493x9h &&
        (virialDensityKickRequested0493x7a || densityRelaxationRequested0493x7c)) {
        diag.reason = "0493x9h B=wall passive geometry excludes x7b/x7d density closure until wall pressure coupling is defined";
        return false;
    }
    // x7m particle-phase topology remains unchanged.  A wall is deliberately
    // NOT registered as an alpha-low pressure side in x9h: static-wall Q6 BCs
    // stay authoritative and the wall geometry is passive/resident only.
    const bool registeredPhaseB0493x9g =
        phaseB0493x9g.kind == PhaseSelectorKind0493x9g::Vacuum ||
        (!phaseBWall0493x9h && phaseB0493x9g.matchedSpecies > 0);
    const std::size_t dense = static_cast<std::size_t>(grid.numCells) *
                              static_cast<std::size_t>(speciesCount);
    if (postApplyRegionAuditThisStep0493x6hB0) {
        ws.postApplyRegionAccum0493x6hB0.ensure(1u);
    }
    check_cuda_0400(cudaMemset(ws.speciesMasks0493w6.data(), 0,
                                   dense * sizeof(unsigned char)),
                    "independent masked dense support zero");
    check_cuda_0400(cudaMemset(ws.speciesDUx0493w5.data(), 0, dense * sizeof(double)),
                    "independent masked dux zero");
    check_cuda_0400(cudaMemset(ws.speciesDUy0493w5.data(), 0, dense * sizeof(double)),
                    "independent masked duy zero");

    std::vector<IndependentMaskedSpeciesAudit0493w5> audits;
    audits.reserve(static_cast<std::size_t>(speciesCount));
    double totalDivBeforeSq = 0.0;
    double totalDivAfterSq = 0.0;
    double totalCorrectionSq = 0.0;
    std::uint64_t totalActiveCells = 0u;
    double maxDivBefore = 0.0;
    double maxDivAfter = 0.0;
    double maxCorrection = 0.0;
    int maxIterations = 0;
    double maxResidualRel = 0.0;
    bool allConverged = true;
    const double dx = grid.dx;
    const double dy = grid.dy;
    const double invDx2 = 1.0 / (dx * dx);
    const double invDy2 = 1.0 / (dy * dy);
    const double tol = std::max(0.0, params.projectionTolerance);
    const double inactiveNeighborFactor0493x5a =
        freeSurfaceMode0493x5a ? 2.0 : 1.0;
    const bool tgForceActive0493x5a = params.taylorGreenForcingEnable &&
                                      params.taylorGreenForcingAmplitude > 0.0;
    int projectedSpeciesCount = 0;
    int projectedSpeciesIndex0493x7a = -1;
    std::uint32_t projectedSpeciesType0493x7a = 0u;
    int liquidPhaseSpeciesCount0493x7a = 0;
    for (int s = 0; s < speciesCount; ++s) {
        const SpeciesDefinition& def =
            params.speciesDefinitions[static_cast<std::size_t>(s)];
        if (def.phaseFamily == SpeciesPhaseFamily::Liquid) {
            ++liquidPhaseSpeciesCount0493x7a;
        }
        if (def.q6StrengthDeclared > 0.0) {
            ++projectedSpeciesCount;
            projectedSpeciesIndex0493x7a = s;
            projectedSpeciesType0493x7a = def.type;
        }
    }
    const int exclusiveProjectedSpecies = projectedSpeciesCount == 1 ? 1 : 0;
    if (faceToParticleRt0Requested0493x6hB1 && !exclusiveProjectedSpecies) {
        // The current resident workspace reuses r/p as the east/north face
        // buffers.  Keep B1 allocation-free by enabling it only when one Q6
        // species owns those buffers.  Multi-projected-species B1 will require
        // either persistent per-species faces or immediate per-species apply.
        diag.reason = "0493x6h-B1 currently requires exactly one projected Q6 species";
        return false;
    }
    const bool faceToParticleRt00493x6hB1 =
        faceToParticleRt0Requested0493x6hB1 && exclusiveProjectedSpecies;
    if (q6ThermalInterfaceWallRequested0493x10o) {
        if (!faceToParticleRt00493x6hB1 || projectedSpeciesIndex0493x7a < 0 ||
            liquidPhaseSpeciesCount0493x7a != 1 ||
            params.speciesDefinitions[
                static_cast<std::size_t>(projectedSpeciesIndex0493x7a)].phaseFamily !=
                SpeciesPhaseFamily::Liquid) {
            diag.reason =
                "0493x10o requires one projected liquid species with free-surface B1/RT0";
            return false;
        }
        const std::size_t c0493x10o =
            static_cast<std::size_t>(std::max(1, grid.numCells));
        ws.kineticQ6HydroValid0493x10o.ensure(c0493x10o);
        ws.kineticQ6HydroCellUx0493x10o.ensure(c0493x10o);
        ws.kineticQ6HydroCellUy0493x10o.ensure(c0493x10o);
        ws.kineticQ6HydroFaceUxEast0493x10o.ensure(c0493x10o);
        ws.kineticQ6HydroFaceUyNorth0493x10o.ensure(c0493x10o);
        ws.kineticQ6HydroFieldValid0493x10o = false;
        ws.kineticQ6HydroFieldStep0493x10o = -1;
        ws.kineticQ6HydroFieldType0493x10o = projectedSpeciesType0493x7a;
    }
    if (virialDensityKickRequested0493x7a || densityRelaxationRequested0493x7c) {
        if (!exclusiveProjectedSpecies || projectedSpeciesIndex0493x7a < 0 ||
            liquidPhaseSpeciesCount0493x7a != 1 ||
            params.speciesDefinitions[
                static_cast<std::size_t>(projectedSpeciesIndex0493x7a)].phaseFamily !=
                SpeciesPhaseFamily::Liquid) {
            diag.reason = virialDensityKickRequested0493x7a
                ? "0493x7b virial currently requires exactly one liquid phase and one projected liquid species"
                : "0493x7c density RHS currently requires exactly one liquid phase and one projected liquid species";
            return false;
        }
        if (virialDensityKickRequested0493x7a) {
            ws.virialDensityAccum0493x7a.ensure(1u);
        }
    }

    bool periodicProjectedMomentumCorrection0493x7dv2fix2 = false;
    // 0493x8r passive pressure outlet
    // A phi=0 outlet face removes the constant pressure-correction nullspace
    // even when every pressure cell is active.
    const bool pressureOutletDirichlet0493x8r =
        q6_has_passive_pressure_outlet_right_0493x8r(segmentedIo);
    // 0493x8s exact pressure-outlet low-mode deflation
    const bool pressureOutletDeflation0493x8s =
        pressureOutletDirichlet0493x8r && !periodicX &&
        q6_has_fullheight_passive_pressure_outlet_right_0493x8s(segmentedIo);

    for (int s = 0; s < speciesCount; ++s) {
        IndependentMaskedSpeciesAudit0493w5 audit{};
        audit.speciesIndex = s;
        audit.type = params.speciesDefinitions[static_cast<std::size_t>(s)].type;
        audit.strength = params.speciesDefinitions[static_cast<std::size_t>(s)].q6StrengthDeclared;
        const bool phaseInterfaceStencilSpecies0493x6f =
            phaseInterfaceStencil0493x6f && !phaseBWall0493x9h &&
            phase_selector_matches_definition_0493x9g(
                phaseA0493x9g,
                params.speciesDefinitions[static_cast<std::size_t>(s)]);
        const bool phaseGasPressureSpecies0493x6g =
            phaseGasPressure0493x6g && phaseInterfaceStencilSpecies0493x6f;
        // A zero scale is a strict physical no-op.  Keep the x6g audit enabled,
        // but bypass every production-side gas-pressure buffer, branch and
        // arithmetic contribution so the trajectory is exactly the x6f path.
        const bool phaseGasPressureApplySpecies0493x6g =
            phaseGasPressureSpecies0493x6g && phaseGasPressureScale0493x6g != 0.0;
        const bool surfaceTensionApplySpecies0493x9d =
            surfaceTensionActive0493x9d && phaseInterfaceStencilSpecies0493x6f;
        const bool interfaceDirichletApplySpecies0493x9d =
            phaseGasPressureApplySpecies0493x6g || surfaceTensionApplySpecies0493x9d;
        if (!(audit.strength > 0.0)) {
            audits.push_back(audit);
            continue;
        }

        check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                        "independent masked active counter zero");
        q6_build_independent_mask_0493w5<<<cellBlocks, threads>>>(
            species, s, params.speciesQ6MinOccupancyFraction,
            freeSurfaceMode0493x5a ? 1 : 0,
            ws.speciesMask0493w5.data(), ws.rhs.data(),
            grid.numCells, ws.counter.data());
        check_cuda_0400(cudaGetLastError(), "independent masked support launch");
        unsigned char* denseMask0493w6 = ws.speciesMasks0493w6.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        if (freeSurfaceMode0493x5a) {
            check_cuda_0400(cudaMemset(ws.counter.data(), 0,
                                       sizeof(unsigned long long)),
                            "0493x5a regularized active counter zero");
            q6_regularize_free_surface_mask_0493x5a<<<cellBlocks, threads>>>(
                ws.speciesMask0493w5.data(), denseMask0493w6,
                grid.Nx, grid.Ny, periodicX, periodicY, ws.counter.data());
            check_cuda_0400(cudaGetLastError(),
                            "0493x5a free-surface mask regularization launch");
            check_cuda_0400(cudaMemcpy(ws.speciesMask0493w5.data(), denseMask0493w6,
                                       static_cast<std::size_t>(grid.numCells) *
                                           sizeof(unsigned char),
                                       cudaMemcpyDeviceToDevice),
                            "0493x5a regularized support restore");
        } else {
            check_cuda_0400(cudaMemcpy(denseMask0493w6, ws.speciesMask0493w5.data(),
                                       static_cast<std::size_t>(grid.numCells) *
                                           sizeof(unsigned char),
                                       cudaMemcpyDeviceToDevice),
                            "independent masked dense support store");
        }
        unsigned long long activeCells = 0ull;
        check_cuda_0400(cudaMemcpy(&activeCells, ws.counter.data(), sizeof(activeCells),
                                   cudaMemcpyDeviceToHost),
                        "independent masked active counter download");
        audit.activeCells = static_cast<std::uint64_t>(activeCells);
        audit.fullDomain = audit.activeCells == static_cast<std::uint64_t>(grid.numCells);
        if (audit.activeCells == 0u) {
            audits.push_back(audit);
            continue;
        }
        const std::uint64_t carrierActiveCells0493x6f = audit.activeCells;
        const unsigned char* q6SolveMask0493x6f = ws.speciesMask0493w5.data();

        if (phaseGeometryResident0493x6c) {
            const double phaseAReferenceCellMass0493x9g =
                phaseA0493x9g.referenceCellMass;
            const int phaseASpeciesCount0493x9g = phaseA0493x9g.matchedSpecies;
            if (!(phaseAReferenceCellMass0493x9g > 0.0) ||
                phaseASpeciesCount0493x9g == 0) {
                diag.reason =
                    "0493x9g resident phase geometry requires a positive phase-A reference mass";
                append_independent_masked_species_audit_0493w5(params, step, time, audits);
                return false;
            }

            const std::size_t geometryCells0493x6c =
                static_cast<std::size_t>(std::max(1, grid.numCells));
            ws.phaseFillRaw0493x6c.ensure(geometryCells0493x6c);
            ws.phaseAlphaFiltered0493x6c.ensure(geometryCells0493x6c);
            const bool geometryAuditThisStep0493x6c =
                step <= 1 || step % std::max(1, params.summaryEvery) == 0;

            cudaEvent_t geometryStart0493x6c{};
            cudaEvent_t geometryRawDone0493x6c{};
            cudaEvent_t geometryFilterDone0493x6c{};
            cudaEvent_t geometryAuditDone0493x6c{};
            if (geometryAuditThisStep0493x6c) {
                check_cuda_0400(cudaEventCreate(&geometryStart0493x6c),
                                "0493x6c geometry start event create");
                check_cuda_0400(cudaEventCreate(&geometryRawDone0493x6c),
                                "0493x6c geometry raw event create");
                check_cuda_0400(cudaEventCreate(&geometryFilterDone0493x6c),
                                "0493x6c geometry filter event create");
                check_cuda_0400(cudaEventCreate(&geometryAuditDone0493x6c),
                                "0493x6c geometry audit event create");
                check_cuda_0400(cudaEventRecord(geometryStart0493x6c),
                                "0493x6c geometry start event record");
            }

            if (wallGeometryRequested0493x9i) {
                ws.phaseWallFraction0493x9h.ensure(geometryCells0493x6c);
                ws.phaseWallNormalX0493x9h.ensure(geometryCells0493x6c);
                ws.phaseWallNormalY0493x9h.ensure(geometryCells0493x6c);
                q6_build_wall_fraction_0493x9h<<<cellBlocks, threads>>>(
                    chiWallGeometry0493x9h ? wallChi0493x9h : nullptr,
                    chiWallGeometry0493x9h ? 1 : 0,
                    ws.phaseWallFraction0493x9h.data(), grid.numCells);
                check_cuda_0400(cudaGetLastError(),
                                "0493x9h wall solid-fraction build launch");
                q6_build_wall_normals_0493x9h<<<cellBlocks, threads>>>(
                    ws.phaseWallFraction0493x9h.data(),
                    ws.phaseWallNormalX0493x9h.data(),
                    ws.phaseWallNormalY0493x9h.data(),
                    grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                    wallLeft0493x9h, wallRight0493x9h,
                    wallBottom0493x9h, wallTop0493x9h);
                check_cuda_0400(cudaGetLastError(),
                                "0493x9h wall normal build launch");
                ws.phaseWallGeometryValid0493x9h = true;
                ws.phaseWallGeometryStep0493x9h = step;

                if (geometryAuditThisStep0493x6c) {
                    check_cuda_0400(cudaMemset(
                                        ws.phaseWallGeometryAccum0493x9h.data(), 0,
                                        sizeof(WallGeometryAccumulator0493x9h)),
                                    "0493x9h wall geometry accumulator zero");
                    q6_wall_geometry_audit_0493x9h<<<cellBlocks, threads>>>(
                        ws.phaseWallFraction0493x9h.data(),
                        ws.phaseWallNormalX0493x9h.data(),
                        ws.phaseWallNormalY0493x9h.data(),
                        ws.phaseWallGeometryAccum0493x9h.data(),
                        grid.Nx, grid.Ny, periodicX, periodicY,
                        wallLeft0493x9h, wallRight0493x9h,
                        wallBottom0493x9h, wallTop0493x9h);
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9h wall geometry audit launch");
                    WallGeometryAccumulator0493x9h wallAccum0493x9h{};
                    check_cuda_0400(cudaMemcpy(
                                        &wallAccum0493x9h,
                                        ws.phaseWallGeometryAccum0493x9h.data(),
                                        sizeof(wallAccum0493x9h), cudaMemcpyDeviceToHost),
                                    "0493x9h wall geometry audit download");
                    WallGeometryAudit0493x9h wallAudit0493x9h{};
                    wallAudit0493x9h.projectedSpeciesIndex = s;
                    wallAudit0493x9h.projectedType = audit.type;
                    wallAudit0493x9h.domainWallLeft = wallLeft0493x9h;
                    wallAudit0493x9h.domainWallRight = wallRight0493x9h;
                    wallAudit0493x9h.domainWallBottom = wallBottom0493x9h;
                    wallAudit0493x9h.domainWallTop = wallTop0493x9h;
                    wallAudit0493x9h.chiProviderEnabled = chiWallGeometry0493x9h ? 1 : 0;
                    wallAudit0493x9h.chiCollisionWallVpEnabled =
                        params.darcyChiCollisionVpEnable ? 1 : 0;
                    wallAudit0493x9h.numCells =
                        static_cast<std::uint64_t>(grid.numCells);
                    wallAudit0493x9h.solidCells =
                        static_cast<std::uint64_t>(wallAccum0493x9h.solidCells);
                    wallAudit0493x9h.mixedCells =
                        static_cast<std::uint64_t>(wallAccum0493x9h.mixedCells);
                    wallAudit0493x9h.wallBandCells =
                        static_cast<std::uint64_t>(wallAccum0493x9h.wallBandCells);
                    wallAudit0493x9h.normalValidCells =
                        static_cast<std::uint64_t>(wallAccum0493x9h.normalValidCells);
                    if (grid.numCells > 0) {
                        wallAudit0493x9h.solidFractionMean =
                            wallAccum0493x9h.solidFractionSum /
                            static_cast<double>(grid.numCells);
                    }
                    if (wallAccum0493x9h.wallBandCells > 0ull) {
                        wallAudit0493x9h.normalValidFraction =
                            static_cast<double>(wallAccum0493x9h.normalValidCells) /
                            static_cast<double>(wallAccum0493x9h.wallBandCells);
                    }
                    if (wallAccum0493x9h.normalValidCells > 0ull) {
                        wallAudit0493x9h.normalUnitErrorRms = std::sqrt(
                            std::max(0.0, wallAccum0493x9h.normalUnitErrorSqSum /
                                              static_cast<double>(wallAccum0493x9h.normalValidCells)));
                    }
                    append_wall_geometry_audit_0493x9h(
                        params, step, time, wallAudit0493x9h);
                }
            }

            const int phaseBSpeciesCount0493x9g = phaseB0493x9g.matchedSpecies;
            if (phaseGasPressureApplySpecies0493x6g &&
                phaseGasPressureMode0493x6g == PhaseGasPressureMode0493x6g::Eos) {
                if (phaseBSpeciesCount0493x9g == 0) {
                    diag.reason = "0493x9g EOS phase-B pressure requires registered phase-B species";
                    append_independent_masked_species_audit_0493w5(
                        params, step, time, audits);
                    return false;
                }
                if (!phaseB0493x9g.allMatchedGas) {
                    diag.reason =
                        "0493x9g x6g EOS provider is ideal-gas only; non-gas phase B requires constant/off pressure provider";
                    append_independent_masked_species_audit_0493w5(
                        params, step, time, audits);
                    return false;
                }
            }

            q6_build_phase_fill_resident_0493x6c<<<cellBlocks, threads>>>(
                species,
                static_cast<int>(phaseA0493x9g.kind), phaseA0493x9g.value,
                phaseAReferenceCellMass0493x9g,
                static_cast<int>(phaseB0493x9g.kind), phaseB0493x9g.value,
                ws.phaseFillRaw0493x6c.data(), grid.numCells,
                phaseGasPressureApplySpecies0493x6g ? ws.phaseGasPressurePotential0493x6a.data() : nullptr,
                phaseGasPressureApplySpecies0493x6g ? 1 : 0,
                static_cast<int>(phaseGasPressureMode0493x6g),
                params.dt, params.kBT, dx * dy,
                phaseGasPressureReference0493x6g,
                phaseGasPressureConstant0493x6g,
                phaseGasPressureScale0493x6g);
            check_cuda_0400(cudaGetLastError(),
                            "0493x6c resident raw phase-fill launch");
            if (geometryAuditThisStep0493x6c) {
                check_cuda_0400(cudaEventRecord(geometryRawDone0493x6c),
                                "0493x6c geometry raw event record");
            }

            q6_filter_phase_fill_conservative_0493x6c<<<cellBlocks, threads>>>(
                ws.phaseFillRaw0493x6c.data(),
                ws.phaseAlphaFiltered0493x6c.data(),
                grid.Nx, grid.Ny, periodicX, periodicY,
                kPhaseGeometryFilterLambda0493x6c);
            check_cuda_0400(cudaGetLastError(),
                            "0493x6c resident conservative phase filter launch");
            if (geometryAuditThisStep0493x6c) {
                check_cuda_0400(cudaEventRecord(geometryFilterDone0493x6c),
                                "0493x6c geometry filter event record");
            }

            if (phaseCurvatureDiagnostics0493x9a) {
                ws.phaseNormalX0493x9a.ensure(geometryCells0493x6c);
                ws.phaseNormalY0493x9a.ensure(geometryCells0493x6c);
                ws.phaseCurvature0493x9a.ensure(geometryCells0493x6c);
                const bool curvatureAuditThisStep0493x9a =
                    geometryAuditThisStep0493x6c;

                cudaEvent_t curvatureStart0493x9a{};
                cudaEvent_t normalDone0493x9a{};
                cudaEvent_t curvatureDone0493x9a{};
                cudaEvent_t faceAuditDone0493x9a{};
                if (curvatureAuditThisStep0493x9a) {
                    check_cuda_0400(cudaEventCreate(&curvatureStart0493x9a),
                                    "0493x9a curvature start event create");
                    check_cuda_0400(cudaEventCreate(&normalDone0493x9a),
                                    "0493x9a normal event create");
                    check_cuda_0400(cudaEventCreate(&curvatureDone0493x9a),
                                    "0493x9a curvature event create");
                    check_cuda_0400(cudaEventCreate(&faceAuditDone0493x9a),
                                    "0493x9a face audit event create");
                    check_cuda_0400(cudaEventRecord(curvatureStart0493x9a),
                                    "0493x9a curvature start event record");
                }

                q6_build_phase_normals_0493x9a<<<cellBlocks, threads>>>(
                    ws.phaseAlphaFiltered0493x6c.data(),
                    ws.phaseNormalX0493x9a.data(),
                    ws.phaseNormalY0493x9a.data(),
                    grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                check_cuda_0400(cudaGetLastError(),
                                "0493x9a phase normal build launch");
                if (curvatureAuditThisStep0493x9a) {
                    check_cuda_0400(cudaEventRecord(normalDone0493x9a),
                                    "0493x9a normal event record");
                }

                q6_build_phase_curvature_0493x9a<<<cellBlocks, threads>>>(
                    ws.phaseNormalX0493x9a.data(),
                    ws.phaseNormalY0493x9a.data(),
                    ws.phaseCurvature0493x9a.data(),
                    grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                check_cuda_0400(cudaGetLastError(),
                                "0493x9a phase curvature build launch");
                if (curvatureAuditThisStep0493x9a) {
                    check_cuda_0400(cudaEventRecord(curvatureDone0493x9a),
                                    "0493x9a curvature event record");
                    check_cuda_0400(cudaMemset(
                                        ws.phaseCurvatureAccum0493x9a.data(), 0,
                                        sizeof(PhaseCurvatureAccumulator0493x9a)),
                                    "0493x9a curvature accumulator zero");
                    q6_phase_curvature_face_audit_0493x9a<<<cellBlocks, threads>>>(
                        ws.phaseAlphaFiltered0493x6c.data(),
                        ws.phaseNormalX0493x9a.data(),
                        ws.phaseNormalY0493x9a.data(),
                        ws.phaseCurvature0493x9a.data(),
                        ws.phaseCurvatureAccum0493x9a.data(),
                        grid.Nx, grid.Ny, periodicX, periodicY,
                        curvatureAuditWallMarginCells0493x9b);
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9a curvature face audit launch");
                    check_cuda_0400(cudaEventRecord(faceAuditDone0493x9a),
                                    "0493x9a face audit event record");

                    PhaseCurvatureAccumulator0493x9a accum0493x9a{};
                    check_cuda_0400(cudaMemcpy(
                                        &accum0493x9a,
                                        ws.phaseCurvatureAccum0493x9a.data(),
                                        sizeof(accum0493x9a), cudaMemcpyDeviceToHost),
                                    "0493x9a curvature audit download");

                    float normalMs0493x9a = 0.0f;
                    float curvatureMs0493x9a = 0.0f;
                    float faceAuditMs0493x9a = 0.0f;
                    check_cuda_0400(cudaEventElapsedTime(
                                        &normalMs0493x9a, curvatureStart0493x9a,
                                        normalDone0493x9a),
                                    "0493x9a normal elapsed time");
                    check_cuda_0400(cudaEventElapsedTime(
                                        &curvatureMs0493x9a, normalDone0493x9a,
                                        curvatureDone0493x9a),
                                    "0493x9a curvature elapsed time");
                    check_cuda_0400(cudaEventElapsedTime(
                                        &faceAuditMs0493x9a, curvatureDone0493x9a,
                                        faceAuditDone0493x9a),
                                    "0493x9a face audit elapsed time");
                    cudaEventDestroy(curvatureStart0493x9a);
                    cudaEventDestroy(normalDone0493x9a);
                    cudaEventDestroy(curvatureDone0493x9a);
                    cudaEventDestroy(faceAuditDone0493x9a);

                    PhaseCurvatureAudit0493x9a audit0493x9a{};
                    audit0493x9a.projectedSpeciesIndex = s;
                    audit0493x9a.projectedType = audit.type;
                    audit0493x9a.numCells =
                        static_cast<std::uint64_t>(grid.numCells);
                    audit0493x9a.crossingFaces = static_cast<std::uint64_t>(
                        accum0493x9a.crossingFaces);
                    audit0493x9a.validCurvatureFaces = static_cast<std::uint64_t>(
                        accum0493x9a.validCurvatureFaces);
                    audit0493x9a.outwardNormalFaces = static_cast<std::uint64_t>(
                        accum0493x9a.outwardNormalFaces);
                    audit0493x9a.positiveCurvatureFaces = static_cast<std::uint64_t>(
                        accum0493x9a.positiveCurvatureFaces);
                    audit0493x9a.negativeCurvatureFaces = static_cast<std::uint64_t>(
                        accum0493x9a.negativeCurvatureFaces);
                    if (accum0493x9a.crossingFaces > 0ull) {
                        audit0493x9a.validFraction =
                            static_cast<double>(accum0493x9a.validCurvatureFaces) /
                            static_cast<double>(accum0493x9a.crossingFaces);
                    }
                    if (accum0493x9a.validCurvatureFaces > 0ull) {
                        const double inv = 1.0 /
                            static_cast<double>(accum0493x9a.validCurvatureFaces);
                        audit0493x9a.normalOutwardFraction =
                            static_cast<double>(accum0493x9a.outwardNormalFaces) * inv;
                        audit0493x9a.normalFaceAlignmentMean =
                            accum0493x9a.normalFaceAlignmentSum * inv;
                        audit0493x9a.curvatureMean = accum0493x9a.curvatureSum * inv;
                        const double meanSq = accum0493x9a.curvatureSqSum * inv;
                        audit0493x9a.curvatureRms = std::sqrt(std::max(0.0, meanSq));
                        audit0493x9a.curvatureStd = std::sqrt(std::max(
                            0.0, meanSq - audit0493x9a.curvatureMean *
                                              audit0493x9a.curvatureMean));
                        audit0493x9a.curvatureAbsMean =
                            accum0493x9a.curvatureAbsSum * inv;
                    }
                    audit0493x9a.curvatureAbsMax =
                        static_cast<double>(accum0493x9a.curvatureAbsMaxScaled) /
                        kPhaseCurvatureAbsScale0493x9a;
                    populate_phase_curvature_region_metrics_0493x9b(
                        accum0493x9a, curvatureAuditWallMarginCells0493x9b,
                        &audit0493x9a);
                    audit0493x9a.normalBuildSeconds =
                        1.0e-3 * static_cast<double>(normalMs0493x9a);
                    audit0493x9a.curvatureBuildSeconds =
                        1.0e-3 * static_cast<double>(curvatureMs0493x9a);
                    audit0493x9a.faceAuditSeconds =
                        1.0e-3 * static_cast<double>(faceAuditMs0493x9a);
                    audit0493x9a.residentBytes = static_cast<std::uint64_t>(
                        3u * geometryCells0493x6c * sizeof(double));
                    append_phase_curvature_audit_0493x9a(
                        params, step, time, audit0493x9a);
                }
            }

            if (phaseCurvatureDiagnostics0493x9b) {
                ws.phaseAlphaCurvature0493x9b.ensure(geometryCells0493x6c);
                ws.phaseNormalX0493x9b.ensure(geometryCells0493x6c);
                ws.phaseNormalY0493x9b.ensure(geometryCells0493x6c);
                ws.phaseCurvature0493x9b.ensure(geometryCells0493x6c);
                const bool curvatureAuditThisStep0493x9b =
                    geometryAuditThisStep0493x6c;

                cudaEvent_t curvatureStart0493x9b{};
                cudaEvent_t normalDone0493x9b{};
                cudaEvent_t curvatureDone0493x9b{};
                cudaEvent_t faceAuditDone0493x9b{};
                if (curvatureAuditThisStep0493x9b) {
                    check_cuda_0400(cudaEventCreate(&curvatureStart0493x9b),
                                    "0493x9b curvature start event create");
                    check_cuda_0400(cudaEventCreate(&normalDone0493x9b),
                                    "0493x9b normal event create");
                    check_cuda_0400(cudaEventCreate(&curvatureDone0493x9b),
                                    "0493x9b curvature event create");
                    check_cuda_0400(cudaEventCreate(&faceAuditDone0493x9b),
                                    "0493x9b face audit event create");
                    check_cuda_0400(cudaEventRecord(curvatureStart0493x9b),
                                    "0493x9b curvature start event record");
                }

                q6_filter_phase_alpha_curvature_0493x9b<<<cellBlocks, threads>>>(
                    ws.phaseAlphaFiltered0493x6c.data(),
                    ws.phaseAlphaCurvature0493x9b.data(),
                    grid.Nx, grid.Ny, periodicX, periodicY);
                check_cuda_0400(cudaGetLastError(),
                                "0493x9b curvature alpha filter launch");
                q6_build_phase_normals_scharr_0493x9b<<<cellBlocks, threads>>>(
                    ws.phaseAlphaCurvature0493x9b.data(),
                    ws.phaseNormalX0493x9b.data(),
                    ws.phaseNormalY0493x9b.data(),
                    grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                check_cuda_0400(cudaGetLastError(),
                                "0493x9b phase normal build launch");
                if (curvatureAuditThisStep0493x9b) {
                    check_cuda_0400(cudaEventRecord(normalDone0493x9b),
                                    "0493x9b normal event record");
                }

                q6_build_phase_curvature_scharr_0493x9b<<<cellBlocks, threads>>>(
                    ws.phaseNormalX0493x9b.data(),
                    ws.phaseNormalY0493x9b.data(),
                    ws.phaseCurvature0493x9b.data(),
                    grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                check_cuda_0400(cudaGetLastError(),
                                "0493x9b phase curvature build launch");
                ws.phaseCurvatureValid0493x9b = true;
                ws.phaseCurvatureNx0493x9b = grid.Nx;
                ws.phaseCurvatureNy0493x9b = grid.Ny;
                ws.phaseCurvatureStep0493x9b = step;
                if (curvatureAuditThisStep0493x9b) {
                    check_cuda_0400(cudaEventRecord(curvatureDone0493x9b),
                                    "0493x9b curvature event record");
                    check_cuda_0400(cudaMemset(
                                        ws.phaseCurvatureAccum0493x9b.data(), 0,
                                        sizeof(PhaseCurvatureAccumulator0493x9a)),
                                    "0493x9b curvature accumulator zero");
                    q6_phase_curvature_face_audit_0493x9a<<<cellBlocks, threads>>>(
                        ws.phaseAlphaFiltered0493x6c.data(),
                        ws.phaseNormalX0493x9b.data(),
                        ws.phaseNormalY0493x9b.data(),
                        ws.phaseCurvature0493x9b.data(),
                        ws.phaseCurvatureAccum0493x9b.data(),
                        grid.Nx, grid.Ny, periodicX, periodicY,
                        curvatureAuditWallMarginCells0493x9b);
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9b curvature face audit launch");
                    check_cuda_0400(cudaEventRecord(faceAuditDone0493x9b),
                                    "0493x9b face audit event record");

                    PhaseCurvatureAccumulator0493x9a accum0493x9b{};
                    check_cuda_0400(cudaMemcpy(
                                        &accum0493x9b,
                                        ws.phaseCurvatureAccum0493x9b.data(),
                                        sizeof(accum0493x9b), cudaMemcpyDeviceToHost),
                                    "0493x9b curvature audit download");

                    float normalMs0493x9b = 0.0f;
                    float curvatureMs0493x9b = 0.0f;
                    float faceAuditMs0493x9b = 0.0f;
                    check_cuda_0400(cudaEventElapsedTime(
                                        &normalMs0493x9b, curvatureStart0493x9b,
                                        normalDone0493x9b),
                                    "0493x9b normal elapsed time");
                    check_cuda_0400(cudaEventElapsedTime(
                                        &curvatureMs0493x9b, normalDone0493x9b,
                                        curvatureDone0493x9b),
                                    "0493x9b curvature elapsed time");
                    check_cuda_0400(cudaEventElapsedTime(
                                        &faceAuditMs0493x9b, curvatureDone0493x9b,
                                        faceAuditDone0493x9b),
                                    "0493x9b face audit elapsed time");
                    cudaEventDestroy(curvatureStart0493x9b);
                    cudaEventDestroy(normalDone0493x9b);
                    cudaEventDestroy(curvatureDone0493x9b);
                    cudaEventDestroy(faceAuditDone0493x9b);

                    PhaseCurvatureAudit0493x9a audit0493x9b{};
                    audit0493x9b.projectedSpeciesIndex = s;
                    audit0493x9b.projectedType = audit.type;
                    audit0493x9b.numCells = static_cast<std::uint64_t>(grid.numCells);
                    audit0493x9b.crossingFaces = static_cast<std::uint64_t>(accum0493x9b.crossingFaces);
                    audit0493x9b.validCurvatureFaces = static_cast<std::uint64_t>(accum0493x9b.validCurvatureFaces);
                    audit0493x9b.outwardNormalFaces = static_cast<std::uint64_t>(accum0493x9b.outwardNormalFaces);
                    audit0493x9b.positiveCurvatureFaces = static_cast<std::uint64_t>(accum0493x9b.positiveCurvatureFaces);
                    audit0493x9b.negativeCurvatureFaces = static_cast<std::uint64_t>(accum0493x9b.negativeCurvatureFaces);
                    if (accum0493x9b.crossingFaces > 0ull) {
                        audit0493x9b.validFraction =
                            static_cast<double>(accum0493x9b.validCurvatureFaces) /
                            static_cast<double>(accum0493x9b.crossingFaces);
                    }
                    if (accum0493x9b.validCurvatureFaces > 0ull) {
                        const double inv = 1.0 /
                            static_cast<double>(accum0493x9b.validCurvatureFaces);
                        audit0493x9b.normalOutwardFraction =
                            static_cast<double>(accum0493x9b.outwardNormalFaces) * inv;
                        audit0493x9b.normalFaceAlignmentMean = accum0493x9b.normalFaceAlignmentSum * inv;
                        audit0493x9b.curvatureMean = accum0493x9b.curvatureSum * inv;
                        const double meanSq = accum0493x9b.curvatureSqSum * inv;
                        audit0493x9b.curvatureRms = std::sqrt(std::max(0.0, meanSq));
                        audit0493x9b.curvatureStd = std::sqrt(std::max(
                            0.0, meanSq - audit0493x9b.curvatureMean * audit0493x9b.curvatureMean));
                        audit0493x9b.curvatureAbsMean = accum0493x9b.curvatureAbsSum * inv;
                    }
                    audit0493x9b.curvatureAbsMax =
                        static_cast<double>(accum0493x9b.curvatureAbsMaxScaled) /
                        kPhaseCurvatureAbsScale0493x9a;
                    populate_phase_curvature_region_metrics_0493x9b(
                        accum0493x9b, curvatureAuditWallMarginCells0493x9b,
                        &audit0493x9b);
                    audit0493x9b.normalBuildSeconds = 1.0e-3 * static_cast<double>(normalMs0493x9b);
                    audit0493x9b.curvatureBuildSeconds = 1.0e-3 * static_cast<double>(curvatureMs0493x9b);
                    audit0493x9b.faceAuditSeconds = 1.0e-3 * static_cast<double>(faceAuditMs0493x9b);
                    audit0493x9b.residentBytes = static_cast<std::uint64_t>(
                        4u * geometryCells0493x6c * sizeof(double));
                    append_phase_curvature_audit_0493x9b(params, step, time, audit0493x9b);

                    // 0493x9c: evaluate two larger curvature-only supports while
                    // keeping the x9b Scharr operator unchanged.  These kernels
                    // run only on summary/audit steps and never enter Q6 physics.
                    if (phaseCurvatureDiagnostics0493x9c) {
                        ws.phaseAlphaCurvature2Pass0493x9c.ensure(geometryCells0493x6c);
                        ws.phaseAlphaCurvature3Pass0493x9c.ensure(geometryCells0493x6c);
                        ws.phaseCurvature2Pass0493x9c.ensure(geometryCells0493x6c);
                        ws.phaseCurvature3Pass0493x9c.ensure(geometryCells0493x6c);
                        ws.phaseCurvatureAccum2Pass0493x9c.ensure(1u);
                        ws.phaseCurvatureAccum3Pass0493x9c.ensure(1u);

                        // Two total binomial passes: S2 = B(B(alpha_x6c)).
                        q6_filter_phase_alpha_curvature_0493x9b<<<cellBlocks, threads>>>(
                            ws.phaseAlphaCurvature0493x9b.data(),
                            ws.phaseAlphaCurvature2Pass0493x9c.data(),
                            grid.Nx, grid.Ny, periodicX, periodicY);
                        check_cuda_0400(cudaGetLastError(),
                                        "0493x9c 2pass alpha filter launch");
                        q6_build_phase_normals_scharr_0493x9b<<<cellBlocks, threads>>>(
                            ws.phaseAlphaCurvature2Pass0493x9c.data(),
                            ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                            grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                        check_cuda_0400(cudaGetLastError(),
                                        "0493x9c 2pass normal launch");
                        q6_build_phase_curvature_scharr_0493x9b<<<cellBlocks, threads>>>(
                            ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                            ws.phaseCurvature2Pass0493x9c.data(),
                            grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                        check_cuda_0400(cudaGetLastError(),
                                        "0493x9c 2pass curvature launch");
                        check_cuda_0400(cudaMemset(ws.phaseCurvatureAccum2Pass0493x9c.data(), 0,
                                                  sizeof(PhaseCurvatureAccumulator0493x9a)),
                                        "0493x9c 2pass accumulator zero");
                        q6_phase_curvature_face_audit_0493x9a<<<cellBlocks, threads>>>(
                            ws.phaseAlphaFiltered0493x6c.data(),
                            ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                            ws.phaseCurvature2Pass0493x9c.data(),
                            ws.phaseCurvatureAccum2Pass0493x9c.data(),
                            grid.Nx, grid.Ny, periodicX, periodicY,
                            curvatureAuditWallMarginCells0493x9b);
                        check_cuda_0400(cudaGetLastError(),
                                        "0493x9c 2pass face audit launch");
                        PhaseCurvatureAccumulator0493x9a accum2{};
                        check_cuda_0400(cudaMemcpy(&accum2,
                                                  ws.phaseCurvatureAccum2Pass0493x9c.data(),
                                                  sizeof(accum2), cudaMemcpyDeviceToHost),
                                        "0493x9c 2pass audit download");
                        PhaseCurvatureAudit0493x9a audit2{};
                        audit2.projectedSpeciesIndex = s;
                        audit2.projectedType = audit.type;
                        audit2.numCells = static_cast<std::uint64_t>(grid.numCells);
                        audit2.crossingFaces = static_cast<std::uint64_t>(accum2.crossingFaces);
                        audit2.validCurvatureFaces = static_cast<std::uint64_t>(accum2.validCurvatureFaces);
                        audit2.outwardNormalFaces = static_cast<std::uint64_t>(accum2.outwardNormalFaces);
                        audit2.positiveCurvatureFaces = static_cast<std::uint64_t>(accum2.positiveCurvatureFaces);
                        audit2.negativeCurvatureFaces = static_cast<std::uint64_t>(accum2.negativeCurvatureFaces);
                        if (accum2.crossingFaces > 0ull) {
                            audit2.validFraction = static_cast<double>(accum2.validCurvatureFaces) /
                                                   static_cast<double>(accum2.crossingFaces);
                        }
                        if (accum2.validCurvatureFaces > 0ull) {
                            const double inv = 1.0 / static_cast<double>(accum2.validCurvatureFaces);
                            audit2.normalOutwardFraction = static_cast<double>(accum2.outwardNormalFaces) * inv;
                            audit2.normalFaceAlignmentMean = accum2.normalFaceAlignmentSum * inv;
                            audit2.curvatureMean = accum2.curvatureSum * inv;
                            const double meanSq = accum2.curvatureSqSum * inv;
                            audit2.curvatureRms = std::sqrt(std::max(0.0, meanSq));
                            audit2.curvatureStd = std::sqrt(std::max(
                                0.0, meanSq - audit2.curvatureMean * audit2.curvatureMean));
                            audit2.curvatureAbsMean = accum2.curvatureAbsSum * inv;
                        }
                        audit2.curvatureAbsMax = static_cast<double>(accum2.curvatureAbsMaxScaled) /
                                                 kPhaseCurvatureAbsScale0493x9a;
                        populate_phase_curvature_region_metrics_0493x9b(
                            accum2, curvatureAuditWallMarginCells0493x9b, &audit2);
                        audit2.residentBytes = static_cast<std::uint64_t>(
                            4u * geometryCells0493x6c * sizeof(double));
                        append_phase_curvature_audit_0493x9c(params, step, time, 2, audit2);

                        // Three total passes: one more binomial pass from S2.
                        q6_filter_phase_alpha_curvature_0493x9b<<<cellBlocks, threads>>>(
                            ws.phaseAlphaCurvature2Pass0493x9c.data(),
                            ws.phaseAlphaCurvature3Pass0493x9c.data(),
                            grid.Nx, grid.Ny, periodicX, periodicY);
                        check_cuda_0400(cudaGetLastError(),
                                        "0493x9c 3pass alpha filter launch");
                        q6_build_phase_normals_scharr_0493x9b<<<cellBlocks, threads>>>(
                            ws.phaseAlphaCurvature3Pass0493x9c.data(),
                            ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                            grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                        check_cuda_0400(cudaGetLastError(),
                                        "0493x9c 3pass normal launch");
                        q6_build_phase_curvature_scharr_0493x9b<<<cellBlocks, threads>>>(
                            ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                            ws.phaseCurvature3Pass0493x9c.data(),
                            grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                        check_cuda_0400(cudaGetLastError(),
                                        "0493x9c 3pass curvature launch");
                        ws.phaseCurvature3PassValid0493x9d = true;
                        ws.phaseCurvature3PassNx0493x9d = grid.Nx;
                        ws.phaseCurvature3PassNy0493x9d = grid.Ny;
                        ws.phaseCurvature3PassStep0493x9d = step;
                        check_cuda_0400(cudaMemset(ws.phaseCurvatureAccum3Pass0493x9c.data(), 0,
                                                  sizeof(PhaseCurvatureAccumulator0493x9a)),
                                        "0493x9c 3pass accumulator zero");
                        q6_phase_curvature_face_audit_0493x9a<<<cellBlocks, threads>>>(
                            ws.phaseAlphaFiltered0493x6c.data(),
                            ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                            ws.phaseCurvature3Pass0493x9c.data(),
                            ws.phaseCurvatureAccum3Pass0493x9c.data(),
                            grid.Nx, grid.Ny, periodicX, periodicY,
                            curvatureAuditWallMarginCells0493x9b);
                        check_cuda_0400(cudaGetLastError(),
                                        "0493x9c 3pass face audit launch");
                        PhaseCurvatureAccumulator0493x9a accum3{};
                        check_cuda_0400(cudaMemcpy(&accum3,
                                                  ws.phaseCurvatureAccum3Pass0493x9c.data(),
                                                  sizeof(accum3), cudaMemcpyDeviceToHost),
                                        "0493x9c 3pass audit download");
                        PhaseCurvatureAudit0493x9a audit3{};
                        audit3.projectedSpeciesIndex = s;
                        audit3.projectedType = audit.type;
                        audit3.numCells = static_cast<std::uint64_t>(grid.numCells);
                        audit3.crossingFaces = static_cast<std::uint64_t>(accum3.crossingFaces);
                        audit3.validCurvatureFaces = static_cast<std::uint64_t>(accum3.validCurvatureFaces);
                        audit3.outwardNormalFaces = static_cast<std::uint64_t>(accum3.outwardNormalFaces);
                        audit3.positiveCurvatureFaces = static_cast<std::uint64_t>(accum3.positiveCurvatureFaces);
                        audit3.negativeCurvatureFaces = static_cast<std::uint64_t>(accum3.negativeCurvatureFaces);
                        if (accum3.crossingFaces > 0ull) {
                            audit3.validFraction = static_cast<double>(accum3.validCurvatureFaces) /
                                                   static_cast<double>(accum3.crossingFaces);
                        }
                        if (accum3.validCurvatureFaces > 0ull) {
                            const double inv = 1.0 / static_cast<double>(accum3.validCurvatureFaces);
                            audit3.normalOutwardFraction = static_cast<double>(accum3.outwardNormalFaces) * inv;
                            audit3.normalFaceAlignmentMean = accum3.normalFaceAlignmentSum * inv;
                            audit3.curvatureMean = accum3.curvatureSum * inv;
                            const double meanSq = accum3.curvatureSqSum * inv;
                            audit3.curvatureRms = std::sqrt(std::max(0.0, meanSq));
                            audit3.curvatureStd = std::sqrt(std::max(
                                0.0, meanSq - audit3.curvatureMean * audit3.curvatureMean));
                            audit3.curvatureAbsMean = accum3.curvatureAbsSum * inv;
                        }
                        audit3.curvatureAbsMax = static_cast<double>(accum3.curvatureAbsMaxScaled) /
                                                 kPhaseCurvatureAbsScale0493x9a;
                        populate_phase_curvature_region_metrics_0493x9b(
                            accum3, curvatureAuditWallMarginCells0493x9b, &audit3);
                        audit3.residentBytes = static_cast<std::uint64_t>(
                            4u * geometryCells0493x6c * sizeof(double));
                        append_phase_curvature_audit_0493x9c(params, step, time, 3, audit3);
                    }
                }
            }

            // 0493x9d production curvature: promote the x9c p3 support to a
            // per-step field when capillarity is physically active.
            //
            // 0493x11c-fix6-x9e-sigma0-p3-diagnostic:
            // x9e also needs the same p3 field at summary cadence for the
            // sigma=0 paired Young-Laplace control. This is observational only:
            // the x6f stencil below still receives curvature and a capillary
            // potential iff surfaceTensionApplySpecies0493x9d is true.
            const bool buildPhaseCurvature3Pass0493x11c =
                surfaceTensionApplySpecies0493x9d ||
                staticDropDiagnosticsThisStep0493x9e;
            if (buildPhaseCurvature3Pass0493x11c) {
                ws.phaseAlphaCurvature0493x9b.ensure(geometryCells0493x6c);
                ws.phaseAlphaCurvature2Pass0493x9c.ensure(geometryCells0493x6c);
                ws.phaseAlphaCurvature3Pass0493x9c.ensure(geometryCells0493x6c);
                ws.phaseNormalX0493x9b.ensure(geometryCells0493x6c);
                ws.phaseNormalY0493x9b.ensure(geometryCells0493x6c);
                ws.phaseCurvature3Pass0493x9c.ensure(geometryCells0493x6c);

                if (contactAngleGhostAlpha0493x9j) {
                    q6_filter_phase_alpha_curvature_contact_0493x9j<<<cellBlocks, threads>>>(
                        ws.phaseAlphaFiltered0493x6c.data(),
                        ws.phaseAlphaCurvature0493x9b.data(),
                        grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                        wallLeft0493x9h, wallRight0493x9h, wallBottom0493x9h, wallTop0493x9h,
                        params.phaseInterfaceContactAngleDegrees);
                } else {
                    q6_filter_phase_alpha_curvature_0493x9b<<<cellBlocks, threads>>>(
                        ws.phaseAlphaFiltered0493x6c.data(),
                        ws.phaseAlphaCurvature0493x9b.data(),
                        grid.Nx, grid.Ny, periodicX, periodicY);
                }
                check_cuda_0400(cudaGetLastError(),
                                "0493x9j/x9d p3 pass1 alpha filter launch");
                if (contactAngleGhostAlpha0493x9j) {
                    q6_filter_phase_alpha_curvature_contact_0493x9j<<<cellBlocks, threads>>>(
                        ws.phaseAlphaCurvature0493x9b.data(),
                        ws.phaseAlphaCurvature2Pass0493x9c.data(),
                        grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                        wallLeft0493x9h, wallRight0493x9h, wallBottom0493x9h, wallTop0493x9h,
                        params.phaseInterfaceContactAngleDegrees);
                } else {
                    q6_filter_phase_alpha_curvature_0493x9b<<<cellBlocks, threads>>>(
                        ws.phaseAlphaCurvature0493x9b.data(),
                        ws.phaseAlphaCurvature2Pass0493x9c.data(),
                        grid.Nx, grid.Ny, periodicX, periodicY);
                }
                check_cuda_0400(cudaGetLastError(),
                                "0493x9j/x9d p3 pass2 alpha filter launch");
                if (contactAngleGhostAlpha0493x9j) {
                    q6_filter_phase_alpha_curvature_contact_0493x9j<<<cellBlocks, threads>>>(
                        ws.phaseAlphaCurvature2Pass0493x9c.data(),
                        ws.phaseAlphaCurvature3Pass0493x9c.data(),
                        grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                        wallLeft0493x9h, wallRight0493x9h, wallBottom0493x9h, wallTop0493x9h,
                        params.phaseInterfaceContactAngleDegrees);
                } else {
                    q6_filter_phase_alpha_curvature_0493x9b<<<cellBlocks, threads>>>(
                        ws.phaseAlphaCurvature2Pass0493x9c.data(),
                        ws.phaseAlphaCurvature3Pass0493x9c.data(),
                        grid.Nx, grid.Ny, periodicX, periodicY);
                }
                check_cuda_0400(cudaGetLastError(),
                                "0493x9j/x9d p3 pass3 alpha filter launch");
                if (contactAngleGhostAlpha0493x9j) {
                    if (!ws.phaseWallGeometryValid0493x9h ||
                        ws.phaseWallGeometryStep0493x9h != step) {
                        diag.reason = "0493x9j ghost-alpha contact angle requested without current wall geometry";
                        append_independent_masked_species_audit_0493w5(params, step, time, audits);
                        return false;
                    }
                    check_cuda_0400(cudaMemset(
                                        ws.contactAngleAccum0493x9i.data(), 0,
                                        sizeof(ContactAngleAccumulator0493x9i)),
                                    "0493x9j ghost-alpha contact accumulator zero");
                    q6_build_phase_normals_scharr_contact_0493x9j<<<cellBlocks, threads>>>(
                        ws.phaseAlphaCurvature3Pass0493x9c.data(),
                        ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                        grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                        wallLeft0493x9h, wallRight0493x9h, wallBottom0493x9h, wallTop0493x9h,
                        params.phaseInterfaceContactAngleDegrees);
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9j ghost-alpha p3 normal build launch");
                    q6_contact_angle_ghost_normal_audit_0493x9j<<<cellBlocks, threads>>>(
                        ws.phaseAlphaFiltered0493x6c.data(),
                        ws.phaseAlphaCurvature3Pass0493x9c.data(),
                        ws.phaseWallNormalX0493x9h.data(), ws.phaseWallNormalY0493x9h.data(),
                        ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                        ws.contactAngleAccum0493x9i.data(),
                        grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                        params.phaseInterfaceContactAngleDegrees);
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9j ghost-alpha contact-angle normal audit launch");
                    q6_build_phase_curvature_scharr_contact_0493x9j<<<cellBlocks, threads>>>(
                        ws.phaseAlphaCurvature3Pass0493x9c.data(),
                        ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                        ws.phaseCurvature3Pass0493x9c.data(),
                        grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                        wallLeft0493x9h, wallRight0493x9h, wallBottom0493x9h, wallTop0493x9h,
                        params.phaseInterfaceContactAngleDegrees);
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9j ghost-alpha p3 curvature build launch");
                } else {
                    q6_build_phase_normals_scharr_0493x9b<<<cellBlocks, threads>>>(
                        ws.phaseAlphaCurvature3Pass0493x9c.data(),
                        ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                        grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9d p3 normal build launch");
                    if (contactAngleHardNormalLegacy0493x9i || contactAngleWallFace0493x9l ||
                        contactAngleOffSupport0493x9m) {
                        if (!ws.phaseWallGeometryValid0493x9h ||
                            ws.phaseWallGeometryStep0493x9h != step) {
                            diag.reason = contactAngleOffSupport0493x9m
                                ? "0493x9m off-support contact curvature requested without current wall geometry"
                                : (contactAngleWallFace0493x9l
                                    ? "0493x9l wall-face contact angle requested without current wall geometry"
                                    : "0493x9i legacy hard-normal contact angle requested without current wall geometry");
                            append_independent_masked_species_audit_0493w5(params, step, time, audits);
                            return false;
                        }
                        check_cuda_0400(cudaMemset(
                                            ws.contactAngleAccum0493x9i.data(), 0,
                                            sizeof(ContactAngleAccumulator0493x9i)),
                                        contactAngleOffSupport0493x9m
                                            ? "0493x9m off-support contact accumulator zero"
                                            : (contactAngleWallFace0493x9l
                                                ? "0493x9l wall-face contact accumulator zero"
                                                : "0493x9i legacy contact-angle accumulator zero"));
                        if (contactAngleWallFace0493x9l) {
                            q6_apply_contact_angle_wallface_normals_0493x9l<<<cellBlocks, threads>>>(
                                ws.phaseAlphaFiltered0493x6c.data(),
                                ws.phaseWallNormalX0493x9h.data(), ws.phaseWallNormalY0493x9h.data(),
                                ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                                grid.Nx, grid.Ny, periodicX, periodicY,
                                params.phaseInterfaceContactAngleDegrees);
                            check_cuda_0400(cudaGetLastError(),
                                            "0493x9l wall-face normal closure launch");
                            q6_contact_angle_wallface_audit_0493x9l<<<cellBlocks, threads>>>(
                                ws.phaseAlphaFiltered0493x6c.data(),
                                ws.phaseAlphaCurvature3Pass0493x9c.data(),
                                ws.phaseWallNormalX0493x9h.data(), ws.phaseWallNormalY0493x9h.data(),
                                ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                                ws.contactAngleAccum0493x9i.data(),
                                grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                                params.phaseInterfaceContactAngleDegrees);
                            check_cuda_0400(cudaGetLastError(),
                                            "0493x9l wall-face contact-angle audit launch");
                        } else if (contactAngleHardNormalLegacy0493x9i) {
                            q6_apply_contact_angle_normals_0493x9i<<<cellBlocks, threads>>>(
                                ws.phaseAlphaFiltered0493x6c.data(),
                                ws.phaseWallNormalX0493x9h.data(), ws.phaseWallNormalY0493x9h.data(),
                                ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                                ws.contactAngleAccum0493x9i.data(),
                                grid.Nx, grid.Ny, periodicX, periodicY,
                                params.phaseInterfaceContactAngleDegrees);
                            check_cuda_0400(cudaGetLastError(),
                                            "0493x9i legacy hard-normal closure launch");
                        }
                    }
                    if (contactAngleWallFace0493x9l) {
                        q6_build_phase_curvature_wallface_0493x9l<<<cellBlocks, threads>>>(
                            ws.phaseAlphaFiltered0493x6c.data(),
                            ws.phaseWallNormalX0493x9h.data(), ws.phaseWallNormalY0493x9h.data(),
                            ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                            ws.phaseCurvature3Pass0493x9c.data(),
                            grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                            wallLeft0493x9h, wallRight0493x9h, wallBottom0493x9h, wallTop0493x9h,
                            params.phaseInterfaceContactAngleDegrees);
                        check_cuda_0400(cudaGetLastError(),
                                        "0493x9l wall-face curvature build launch");
                    } else {
                        q6_build_phase_curvature_scharr_0493x9b<<<cellBlocks, threads>>>(
                            ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                            ws.phaseCurvature3Pass0493x9c.data(),
                            grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                        check_cuda_0400(cudaGetLastError(),
                                        "0493x9d p3 curvature build launch");
                        if (contactAngleOffSupport0493x9m) {
                            q6_apply_contact_angle_offsupport_curvature_0493x9m<<<cellBlocks, threads>>>(
                                ws.phaseAlphaFiltered0493x6c.data(),
                                ws.phaseWallNormalX0493x9h.data(), ws.phaseWallNormalY0493x9h.data(),
                                ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                                ws.phaseCurvature3Pass0493x9c.data(),
                                ws.contactAngleAccum0493x9i.data(),
                                grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                                params.phaseInterfaceContactAngleDegrees);
                            check_cuda_0400(cudaGetLastError(),
                                            "0493x9m off-support contact-curvature closure launch");
                        }
                    }
                }
                if (contactAngleActive0493x9i) {
                    q6_contact_angle_curvature_audit_0493x9i<<<cellBlocks, threads>>>(
                        ws.phaseAlphaFiltered0493x6c.data(),
                        ws.phaseWallNormalX0493x9h.data(),
                        ws.phaseWallNormalY0493x9h.data(),
                        ws.phaseCurvature3Pass0493x9c.data(),
                        ws.contactAngleAccum0493x9i.data(),
                        grid.Nx, grid.Ny, periodicX, periodicY);
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9i contact-angle curvature audit launch");
                    if (geometryAuditThisStep0493x6c) {
                        ContactAngleAccumulator0493x9i ca{};
                        check_cuda_0400(cudaMemcpy(
                                            &ca, ws.contactAngleAccum0493x9i.data(),
                                            sizeof(ca), cudaMemcpyDeviceToHost),
                                        "0493x9i contact-angle audit download");
                        ContactAngleAudit0493x9i a{};
                        a.projectedSpeciesIndex = s;
                        a.projectedType = audit.type;
                        a.prescribedAngleDegrees = params.phaseInterfaceContactAngleDegrees;
                        constexpr double pi0493x9i = 3.141592653589793238462643383279502884;
                        a.targetNormalWallDot = -std::cos(
                            params.phaseInterfaceContactAngleDegrees * (pi0493x9i / 180.0));
                        a.candidateCells = static_cast<std::uint64_t>(ca.candidateCells);
                        a.correctedCells = static_cast<std::uint64_t>(ca.correctedCells);
                        a.curvatureCells = static_cast<std::uint64_t>(ca.curvatureCells);
                        if (ca.candidateCells > 0ull) {
                            a.rawAngleMean = ca.rawAngleSum /
                                static_cast<double>(ca.candidateCells);
                        }
                        if (ca.correctedCells > 0ull) {
                            const double inv = 1.0 / static_cast<double>(ca.correctedCells);
                            a.correctedAngleMean = ca.correctedAngleSum * inv;
                            a.correctedAngleErrorRms = std::sqrt(
                                std::max(0.0, ca.correctedAngleErrorSqSum * inv));
                            a.correctedDotErrorRms = std::sqrt(
                                std::max(0.0, ca.correctedDotErrorSqSum * inv));
                        }
                        if (ca.curvatureCells > 0ull) {
                            const double inv = 1.0 / static_cast<double>(ca.curvatureCells);
                            a.contactCurvatureMean = ca.curvatureSum * inv;
                            const double ms = ca.curvatureSqSum * inv;
                            a.contactCurvatureRms = std::sqrt(std::max(0.0, ms));
                            a.contactCurvatureStd = std::sqrt(std::max(
                                0.0, ms - a.contactCurvatureMean*a.contactCurvatureMean));
                        }
                        if (contactAngleOffSupport0493x9m) {
                            append_contact_angle_offsupport_audit_0493x9m(params, step, time, a);
                        } else if (contactAngleWallFace0493x9l) {
                            append_contact_angle_wallface_audit_0493x9l(params, step, time, a);
                        } else if (contactAngleGhostAlpha0493x9j) {
                            append_contact_angle_mirror_audit_0493x9k(params, step, time, a);
                        } else {
                            append_contact_angle_audit_0493x9i(params, step, time, a);
                        }
                    }
                }
                ws.phaseCurvature3PassValid0493x9d = true;
                ws.phaseCurvature3PassNx0493x9d = grid.Nx;
                ws.phaseCurvature3PassNy0493x9d = grid.Ny;
                ws.phaseCurvature3PassStep0493x9d = step;

                if (geometryAuditThisStep0493x6c) {
                    ws.phaseCurvatureAccum3Pass0493x9c.ensure(1u);
                    check_cuda_0400(cudaMemset(
                                        ws.phaseCurvatureAccum3Pass0493x9c.data(), 0,
                                        sizeof(PhaseCurvatureAccumulator0493x9a)),
                                    "0493x9d capillary curvature accumulator zero");
                    q6_phase_curvature_face_audit_0493x9a<<<cellBlocks, threads>>>(
                        ws.phaseAlphaFiltered0493x6c.data(),
                        ws.phaseNormalX0493x9b.data(), ws.phaseNormalY0493x9b.data(),
                        ws.phaseCurvature3Pass0493x9c.data(),
                        ws.phaseCurvatureAccum3Pass0493x9c.data(),
                        grid.Nx, grid.Ny, periodicX, periodicY,
                        curvatureAuditWallMarginCells0493x9b);
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9d capillary curvature audit launch");
                    PhaseCurvatureAccumulator0493x9a capAccum{};
                    check_cuda_0400(cudaMemcpy(
                                        &capAccum,
                                        ws.phaseCurvatureAccum3Pass0493x9c.data(),
                                        sizeof(capAccum), cudaMemcpyDeviceToHost),
                                    "0493x9d capillary curvature audit download");
                    PhaseCurvatureAudit0493x9a capAudit{};
                    capAudit.projectedSpeciesIndex = s;
                    capAudit.projectedType = audit.type;
                    capAudit.numCells = static_cast<std::uint64_t>(grid.numCells);
                    capAudit.crossingFaces = static_cast<std::uint64_t>(capAccum.crossingFaces);
                    capAudit.validCurvatureFaces = static_cast<std::uint64_t>(capAccum.validCurvatureFaces);
                    if (capAccum.validCurvatureFaces > 0ull) {
                        const double inv = 1.0 / static_cast<double>(capAccum.validCurvatureFaces);
                        capAudit.curvatureMean = capAccum.curvatureSum * inv;
                        const double meanSq = capAccum.curvatureSqSum * inv;
                        capAudit.curvatureRms = std::sqrt(std::max(0.0, meanSq));
                        capAudit.curvatureStd = std::sqrt(std::max(
                            0.0, meanSq - capAudit.curvatureMean * capAudit.curvatureMean));
                    }
                    capAudit.curvatureAbsMax =
                        static_cast<double>(capAccum.curvatureAbsMaxScaled) /
                        kPhaseCurvatureAbsScale0493x9a;
                    const double rhoLiquidRef0493x9d =
                        phaseAReferenceCellMass0493x9g / (dx * dy);
                    const double capillaryPotentialScale0493x9d =
                        params.dt * params.surfaceTensionSigma / rhoLiquidRef0493x9d;
                    append_surface_tension_audit_0493x9d(
                        params, step, time, rhoLiquidRef0493x9d,
                        capillaryPotentialScale0493x9d, capAudit);
                }
            }

            ws.phaseGeometryResidentValid0493x6c = true;
            ws.phaseGeometryResidentStep0493x6c = step;
            // Historical workspace field names are retained for ABI/locality;
            // under x9g they carry phase-A reference/count semantics.
            ws.phaseGeometryReferenceCellMass0493x6c =
                phaseAReferenceCellMass0493x9g;
            ws.phaseGeometryLiquidSpeciesCount0493x6c =
                phaseASpeciesCount0493x9g;

            if (geometryAuditThisStep0493x6c) {
                append_phase_pair_audit_0493x9g(
                    params, step, time, s, audit.type,
                    phaseA0493x9g, phaseB0493x9g,
                    registeredPhaseB0493x9g, phaseGasPressureApplySpecies0493x6g);
                check_cuda_0400(cudaMemset(
                                    ws.phaseGeometryResidentAccum0493x6c.data(), 0,
                                    sizeof(PhaseGeometryResidentAccumulator0493x6c)),
                                "0493x6c resident geometry accumulator zero");
                q6_phase_geometry_resident_audit_0493x6c<<<cellBlocks, threads>>>(
                    ws.phaseFillRaw0493x6c.data(),
                    ws.phaseAlphaFiltered0493x6c.data(),
                    ws.speciesMask0493w5.data(),
                    params.speciesQ6MinOccupancyFraction,
                    ws.phaseGeometryResidentAccum0493x6c.data(),
                    grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                    phaseInterfaceTopology0493x6e ? 1 : 0,
                    kPhaseCutFaceThetaMin0493x6d);
                check_cuda_0400(cudaGetLastError(),
                                "0493x6c resident phase geometry audit launch");
                check_cuda_0400(cudaEventRecord(geometryAuditDone0493x6c),
                                "0493x6c geometry audit event record");

                PhaseGeometryResidentAccumulator0493x6c accum0493x6c{};
                check_cuda_0400(cudaMemcpy(
                                    &accum0493x6c,
                                    ws.phaseGeometryResidentAccum0493x6c.data(),
                                    sizeof(accum0493x6c), cudaMemcpyDeviceToHost),
                                "0493x6c resident phase geometry audit download");

                float rawMs0493x6c = 0.0f;
                float filterMs0493x6c = 0.0f;
                float auditMs0493x6c = 0.0f;
                check_cuda_0400(cudaEventElapsedTime(
                                    &rawMs0493x6c, geometryStart0493x6c,
                                    geometryRawDone0493x6c),
                                "0493x6c raw geometry elapsed time");
                check_cuda_0400(cudaEventElapsedTime(
                                    &filterMs0493x6c, geometryRawDone0493x6c,
                                    geometryFilterDone0493x6c),
                                "0493x6c filter geometry elapsed time");
                check_cuda_0400(cudaEventElapsedTime(
                                    &auditMs0493x6c, geometryFilterDone0493x6c,
                                    geometryAuditDone0493x6c),
                                "0493x6c audit geometry elapsed time");
                cudaEventDestroy(geometryStart0493x6c);
                cudaEventDestroy(geometryRawDone0493x6c);
                cudaEventDestroy(geometryFilterDone0493x6c);
                cudaEventDestroy(geometryAuditDone0493x6c);

                PhaseGeometryResidentAudit0493x6c geometryAudit0493x6c{};
                geometryAudit0493x6c.projectedSpeciesIndex = s;
                geometryAudit0493x6c.projectedType = audit.type;
                geometryAudit0493x6c.liquidPhaseSpeciesCount =
                    phaseASpeciesCount0493x9g;
                geometryAudit0493x6c.liquidPhaseReferenceCellMass =
                    phaseAReferenceCellMass0493x9g;
                geometryAudit0493x6c.numCells =
                    static_cast<std::uint64_t>(grid.numCells);
                geometryAudit0493x6c.filterLambda =
                    kPhaseGeometryFilterLambda0493x6c;
                geometryAudit0493x6c.rawFillSum = accum0493x6c.rawFillSum;
                geometryAudit0493x6c.boundedGeometrySourceSum =
                    accum0493x6c.boundedGeometrySourceSum;
                geometryAudit0493x6c.boundedGeometryClippedCells =
                    static_cast<std::uint64_t>(
                        accum0493x6c.boundedGeometryClippedCells);
                geometryAudit0493x6c.filteredFillSum =
                    accum0493x6c.filteredFillSum;
                // 0493x6f2: the filter conserves the bounded geometric source;
                // rawFill remains a separate unbounded occupancy diagnostic.
                const double conservationScale0493x6c = std::max(
                    1.0, std::abs(accum0493x6c.boundedGeometrySourceSum));
                geometryAudit0493x6c.conservationRelativeError =
                    std::abs(accum0493x6c.filteredFillSum -
                             accum0493x6c.boundedGeometrySourceSum) /
                    conservationScale0493x6c;
                if (grid.numCells > 0) {
                    geometryAudit0493x6c.filterDeltaRms = std::sqrt(
                        std::max(0.0, accum0493x6c.filterDeltaSqSum /
                                          static_cast<double>(grid.numCells)));
                }
                geometryAudit0493x6c.maskFilteredMismatchCells =
                    static_cast<std::uint64_t>(
                        accum0493x6c.maskFilteredMismatchCells);
                geometryAudit0493x6c.interfaceFaces =
                    static_cast<std::uint64_t>(accum0493x6c.interfaceFaces);
                if (accum0493x6c.interfaceFaces > 0ull) {
                    const double invFaces =
                        1.0 / static_cast<double>(accum0493x6c.interfaceFaces);
                    geometryAudit0493x6c.halfIsoBracketFraction =
                        static_cast<double>(accum0493x6c.halfIsoBracketFaces) *
                        invFaces;
                }
                if (accum0493x6c.halfIsoBracketFaces > 0ull) {
                    const double inv = 1.0 /
                        static_cast<double>(accum0493x6c.halfIsoBracketFaces);
                    geometryAudit0493x6c.halfIsoThetaMean =
                        accum0493x6c.halfIsoThetaSum * inv;
                    const double meanSq = accum0493x6c.halfIsoThetaSqSum * inv;
                    geometryAudit0493x6c.halfIsoThetaStd = std::sqrt(std::max(
                        0.0, meanSq - geometryAudit0493x6c.halfIsoThetaMean *
                                          geometryAudit0493x6c.halfIsoThetaMean));
                }
                if (accum0493x6c.normalValidFaces > 0ull) {
                    const double inv = 1.0 /
                        static_cast<double>(accum0493x6c.normalValidFaces);
                    geometryAudit0493x6c.normalValidFraction =
                        accum0493x6c.interfaceFaces > 0ull
                            ? static_cast<double>(accum0493x6c.normalValidFaces) /
                                  static_cast<double>(accum0493x6c.interfaceFaces)
                            : 0.0;
                    geometryAudit0493x6c.normalOutwardFraction =
                        static_cast<double>(accum0493x6c.normalOutwardFaces) * inv;
                    geometryAudit0493x6c.normalFaceAlignmentMean =
                        accum0493x6c.normalFaceAlignmentSum * inv;
                }
                geometryAudit0493x6c.rawBuildSeconds =
                    1.0e-3 * static_cast<double>(rawMs0493x6c);
                geometryAudit0493x6c.filterSeconds =
                    1.0e-3 * static_cast<double>(filterMs0493x6c);
                geometryAudit0493x6c.auditKernelSeconds =
                    1.0e-3 * static_cast<double>(auditMs0493x6c);
                geometryAudit0493x6c.residentBytes =
                    static_cast<std::uint64_t>(2u * geometryCells0493x6c *
                                               sizeof(double));
                geometryAudit0493x6c.cutFaceGeometryEnabled =
                    cutFaceGeometry0493x6d ? 1 : 0;
                geometryAudit0493x6c.cutFaceGeometricFaces =
                    static_cast<std::uint64_t>(accum0493x6c.cutFaceGeometricFaces);
                geometryAudit0493x6c.cutFaceSmallThetaFallbackFaces =
                    static_cast<std::uint64_t>(
                        accum0493x6c.cutFaceSmallThetaFallbackFaces);
                geometryAudit0493x6c.cutFaceLegacyFallbackFaces =
                    geometryAudit0493x6c.interfaceFaces >=
                            geometryAudit0493x6c.cutFaceGeometricFaces
                        ? geometryAudit0493x6c.interfaceFaces -
                              geometryAudit0493x6c.cutFaceGeometricFaces
                        : 0u;
                geometryAudit0493x6c.cutFaceThetaGuard =
                    kPhaseCutFaceThetaMin0493x6d;
                if (accum0493x6c.cutFaceGeometricFaces > 0ull) {
                    constexpr double kThetaScale0493x6d = 1000000000.0;
                    geometryAudit0493x6c.cutFaceThetaMin = 1.0 -
                        static_cast<double>(
                            accum0493x6c.cutFaceThetaMinComplementScaled) /
                            kThetaScale0493x6d;
                    geometryAudit0493x6c.cutFaceThetaMean =
                        accum0493x6c.cutFaceThetaSum /
                        static_cast<double>(accum0493x6c.cutFaceGeometricFaces);
                    geometryAudit0493x6c.cutFaceThetaMax =
                        static_cast<double>(accum0493x6c.cutFaceThetaMaxScaled) /
                        kThetaScale0493x6d;
                }
                geometryAudit0493x6c.phaseInterfaceTopologyEnabled =
                    phaseInterfaceTopology0493x6e ? 1 : 0;
                geometryAudit0493x6c.alphaHalfCrossingFaces =
                    static_cast<std::uint64_t>(accum0493x6c.alphaHalfCrossingFaces);
                geometryAudit0493x6c.alphaHalfCrossingActiveActiveFaces =
                    static_cast<std::uint64_t>(
                        accum0493x6c.alphaHalfCrossingActiveActiveFaces);
                geometryAudit0493x6c.alphaHalfCrossingActiveInactiveFaces =
                    static_cast<std::uint64_t>(
                        accum0493x6c.alphaHalfCrossingActiveInactiveFaces);
                geometryAudit0493x6c.alphaHalfCrossingInactiveInactiveFaces =
                    static_cast<std::uint64_t>(
                        accum0493x6c.alphaHalfCrossingInactiveInactiveFaces);
                geometryAudit0493x6c.alphaHalfCrossingAIActiveLiquidSideFaces =
                    static_cast<std::uint64_t>(
                        accum0493x6c.alphaHalfCrossingAIActiveLiquidSideFaces);
                geometryAudit0493x6c.alphaHalfCrossingAIActiveExteriorSideFaces =
                    static_cast<std::uint64_t>(
                        accum0493x6c.alphaHalfCrossingAIActiveExteriorSideFaces);
                if (accum0493x6c.alphaHalfCrossingFaces > 0ull) {
                    constexpr double kThetaScale0493x6e = 1000000000.0;
                    geometryAudit0493x6c.alphaHalfThetaMin = 1.0 -
                        static_cast<double>(
                            accum0493x6c.alphaHalfThetaMinComplementScaled) /
                            kThetaScale0493x6e;
                    geometryAudit0493x6c.alphaHalfThetaMax =
                        static_cast<double>(accum0493x6c.alphaHalfThetaMaxScaled) /
                        kThetaScale0493x6e;
                    const double invAlphaHalf = 1.0 /
                        static_cast<double>(accum0493x6c.alphaHalfCrossingFaces);
                    geometryAudit0493x6c.alphaHalfThetaMean =
                        accum0493x6c.alphaHalfThetaSum * invAlphaHalf;
                    const double alphaHalfMeanSq =
                        accum0493x6c.alphaHalfThetaSqSum * invAlphaHalf;
                    geometryAudit0493x6c.alphaHalfThetaStd = std::sqrt(std::max(
                        0.0, alphaHalfMeanSq -
                                 geometryAudit0493x6c.alphaHalfThetaMean *
                                     geometryAudit0493x6c.alphaHalfThetaMean));
                }
                append_phase_geometry_resident_audit_0493x6c(
                    params, step, time, geometryAudit0493x6c);
            }

            if (phaseInterfaceStencilSpecies0493x6f) {
                // x6f converts the resident phase geometry into the algebraic
                // pressure domain once per solve.  The historical occupancy
                // support remains available in denseMask0493w6 for particle
                // correction and support diagnostics.
                ws.phasePressureMask0493x6f.ensure(geometryCells0493x6c);
                ws.phaseFaceCoeffX0493x6f.ensure(geometryCells0493x6c);
                ws.phaseFaceCoeffY0493x6f.ensure(geometryCells0493x6c);
                if (interfaceDirichletApplySpecies0493x9d) {
                    ws.phaseFacePhiGammaX0493x6g.ensure(geometryCells0493x6c);
                    ws.phaseFacePhiGammaY0493x6g.ensure(geometryCells0493x6c);
                }
                check_cuda_0400(cudaMemset(ws.counter.data(), 0,
                                           sizeof(unsigned long long)),
                                "0493x6f pressure active counter zero");

                cudaEvent_t stencilStart0493x6f{};
                cudaEvent_t stencilDone0493x6f{};
                if (geometryAuditThisStep0493x6c) {
                    check_cuda_0400(cudaMemset(
                                        ws.phaseInterfaceStencilAccum0493x6f.data(), 0,
                                        sizeof(PhaseInterfaceStencilAccumulator0493x6f)),
                                    "0493x6f stencil accumulator zero");
                    check_cuda_0400(cudaEventCreate(&stencilStart0493x6f),
                                    "0493x6f stencil start event create");
                    check_cuda_0400(cudaEventCreate(&stencilDone0493x6f),
                                    "0493x6f stencil done event create");
                    check_cuda_0400(cudaEventRecord(stencilStart0493x6f),
                                    "0493x6f stencil start event record");
                }

                const double capillaryKappaMax0493x9r =
                    surfaceTensionApplySpecies0493x9d && params.surfaceTensionMinRadiusCells > 0.0
                        ? 1.0 / (params.surfaceTensionMinRadiusCells * fmin(dx, dy))
                        : 0.0;

                q6_prepare_phase_interface_stencil_0493x6f<<<cellBlocks, threads>>>(
                    ws.speciesMask0493w5.data(),
                    ws.phaseAlphaFiltered0493x6c.data(),
                    ws.phasePressureMask0493x6f.data(),
                    ws.phaseFaceCoeffX0493x6f.data(),
                    ws.phaseFaceCoeffY0493x6f.data(),
                    phaseGasPressureApplySpecies0493x6g
                        ? ws.phaseGasPressurePotential0493x6a.data() : nullptr,
                    surfaceTensionApplySpecies0493x9d
                        ? ws.phaseCurvature3Pass0493x9c.data() : nullptr,
                    surfaceTensionApplySpecies0493x9d
                        ? params.dt * params.surfaceTensionSigma * (dx * dy) /
                              phaseAReferenceCellMass0493x9g
                        : 0.0,
                    capillaryKappaMax0493x9r,
                    interfaceDirichletApplySpecies0493x9d
                        ? ws.phaseFacePhiGammaX0493x6g.data() : nullptr,
                    interfaceDirichletApplySpecies0493x9d
                        ? ws.phaseFacePhiGammaY0493x6g.data() : nullptr,
                    phaseGasPressureApplySpecies0493x6g ? 1 : 0,
                    surfaceTensionApplySpecies0493x9d ? 1 : 0,
                    registeredPhaseB0493x9g ? 1 : 0,
                    grid.Nx, grid.Ny, periodicX, periodicY,
                    kPhaseCutFaceThetaMin0493x6d,
                    ws.counter.data(),
                    ws.phaseInterfaceStencilAccum0493x6f.data(),
                    geometryAuditThisStep0493x6c ? 1 : 0);
                check_cuda_0400(cudaGetLastError(),
                                "0493x6f phase-interface stencil prepare launch");
                if (geometryAuditThisStep0493x6c) {
                    check_cuda_0400(cudaEventRecord(stencilDone0493x6f),
                                    "0493x6f stencil done event record");
                }

                unsigned long long pressureActiveCells0493x6f = 0ull;
                check_cuda_0400(cudaMemcpy(
                                    &pressureActiveCells0493x6f, ws.counter.data(),
                                    sizeof(pressureActiveCells0493x6f),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f pressure active counter download");
                if (pressureActiveCells0493x6f == 0ull) {
                    diag.reason = "0493x6f alpha=0.5 pressure domain has no active cells";
                    append_independent_masked_species_audit_0493w5(
                        params, step, time, audits);
                    return false;
                }
                q6SolveMask0493x6f = ws.phasePressureMask0493x6f.data();
                audit.activeCells =
                    static_cast<std::uint64_t>(pressureActiveCells0493x6f);
                audit.fullDomain =
                    audit.activeCells == static_cast<std::uint64_t>(grid.numCells);
                ws.phaseInterfaceStencilValid0493x6f = true;
                ws.phaseInterfaceStencilStep0493x6f = step;

                if (geometryAuditThisStep0493x6c) {
                    PhaseInterfaceStencilAccumulator0493x6f accum0493x6f{};
                    check_cuda_0400(cudaMemcpy(
                                        &accum0493x6f,
                                        ws.phaseInterfaceStencilAccum0493x6f.data(),
                                        sizeof(accum0493x6f), cudaMemcpyDeviceToHost),
                                    "0493x6f stencil audit download");
                    float prepareMs0493x6f = 0.0f;
                    check_cuda_0400(cudaEventElapsedTime(
                                        &prepareMs0493x6f, stencilStart0493x6f,
                                        stencilDone0493x6f),
                                    "0493x6f stencil elapsed time");
                    cudaEventDestroy(stencilStart0493x6f);
                    cudaEventDestroy(stencilDone0493x6f);

                    PhaseInterfaceStencilAudit0493x6f stencilAudit0493x6f{};
                    stencilAudit0493x6f.projectedSpeciesIndex = s;
                    stencilAudit0493x6f.projectedType = audit.type;
                    stencilAudit0493x6f.carrierActiveCells =
                        carrierActiveCells0493x6f;
                    stencilAudit0493x6f.pressureActiveCells =
                        static_cast<std::uint64_t>(pressureActiveCells0493x6f);
                    stencilAudit0493x6f.interiorPressureFaces =
                        static_cast<std::uint64_t>(accum0493x6f.interiorPressureFaces);
                    stencilAudit0493x6f.representedInterfaceFaces =
                        static_cast<std::uint64_t>(accum0493x6f.representedInterfaceFaces);
                    stencilAudit0493x6f.smallThetaStabilizedFaces =
                        static_cast<std::uint64_t>(accum0493x6f.smallThetaStabilizedFaces);
                    stencilAudit0493x6f.carrierTruncationFaces =
                        static_cast<std::uint64_t>(accum0493x6f.carrierTruncationFaces);
                    stencilAudit0493x6f.uncoveredInterfaceFaces =
                        static_cast<std::uint64_t>(accum0493x6f.uncoveredInterfaceFaces);
                    stencilAudit0493x6f.thetaGuard = kPhaseCutFaceThetaMin0493x6d;
                    if (accum0493x6f.representedInterfaceFaces > 0ull) {
                        constexpr double kThetaScale0493x6f = 1000000000.0;
                        stencilAudit0493x6f.thetaMin = 1.0 -
                            static_cast<double>(accum0493x6f.thetaMinComplementScaled) /
                                kThetaScale0493x6f;
                        stencilAudit0493x6f.thetaMean = accum0493x6f.thetaSum /
                            static_cast<double>(accum0493x6f.representedInterfaceFaces);
                        stencilAudit0493x6f.thetaMax =
                            static_cast<double>(accum0493x6f.thetaMaxScaled) /
                                kThetaScale0493x6f;
                    }
                    stencilAudit0493x6f.prepareSeconds =
                        1.0e-3 * static_cast<double>(prepareMs0493x6f);
                    stencilAudit0493x6f.residentBytes =
                        static_cast<std::uint64_t>(geometryCells0493x6c) *
                        static_cast<std::uint64_t>(sizeof(unsigned char) +
                                                   2u * sizeof(double));
                    append_phase_interface_stencil_audit_0493x6f(
                        params, step, time, stencilAudit0493x6f);
                    if (surfaceTensionApplySpecies0493x9d) {
                        constexpr double kKappaScale0493x9r = 1000000.0;
                        append_surface_tension_limiter_audit_0493x9r(
                            params, step, time, capillaryKappaMax0493x9r,
                            accum0493x6f.capillaryFaces0493x9r,
                            accum0493x6f.capillaryClippedFaces0493x9r,
                            static_cast<double>(accum0493x6f.capillaryKappaRawAbsMaxScaled0493x9r) / kKappaScale0493x9r,
                            static_cast<double>(accum0493x6f.capillaryKappaEffectiveAbsMaxScaled0493x9r) / kKappaScale0493x9r);
                    }
                    if (phaseGasPressureSpecies0493x6g) {
                        const int gasSpeciesCount0493x6g = phaseB0493x9g.matchedSpecies;
                        PhaseInterfaceGasPressureAudit0493x6g gasAudit0493x6g{};
                        gasAudit0493x6g.projectedSpeciesIndex = s;
                        gasAudit0493x6g.projectedType = audit.type;
                        gasAudit0493x6g.gasSpeciesCount = gasSpeciesCount0493x6g;
                        gasAudit0493x6g.representedInterfaceFaces =
                            static_cast<std::uint64_t>(accum0493x6f.representedInterfaceFaces);
                        gasAudit0493x6g.nonzeroPressureFaces =
                            static_cast<std::uint64_t>(accum0493x6f.nonzeroPressureFaces0493x6g);
                        gasAudit0493x6g.liquidReferenceCellMass =
                            phaseAReferenceCellMass0493x9g;
                        gasAudit0493x6g.cellArea = dx * dy;
                        gasAudit0493x6g.pressureReference =
                            phaseGasPressureReference0493x6g;
                        gasAudit0493x6g.pressureScale = phaseGasPressureScale0493x6g;
                        gasAudit0493x6g.constantPressure =
                            phaseGasPressureConstant0493x6g;
                        gasAudit0493x6g.prepareSeconds =
                            1.0e-3 * static_cast<double>(prepareMs0493x6f);
                        gasAudit0493x6g.residentBytes =
                            phaseGasPressureApplySpecies0493x6g
                                ? static_cast<std::uint64_t>(geometryCells0493x6c) *
                                      static_cast<std::uint64_t>(3u * sizeof(double))
                                : 0u;
                        gasAudit0493x6g.sourceMode =
                            phase_gas_pressure_mode_name_0493x6g(
                                phaseGasPressureMode0493x6g);
                        if (accum0493x6f.representedInterfaceFaces > 0ull) {
                            const double invFaces = 1.0 /
                                static_cast<double>(accum0493x6f.representedInterfaceFaces);
                            gasAudit0493x6g.pressurePotentialMean =
                                accum0493x6f.pressurePotentialSum0493x6g * invFaces;
                            const double phiMeanSq =
                                accum0493x6f.pressurePotentialSqSum0493x6g * invFaces;
                            gasAudit0493x6g.pressurePotentialStd = std::sqrt(std::max(
                                0.0, phiMeanSq -
                                    gasAudit0493x6g.pressurePotentialMean *
                                        gasAudit0493x6g.pressurePotentialMean));
                            const double rhoLiquidRef =
                                phaseAReferenceCellMass0493x9g / (dx * dy);
                            if (params.dt > 0.0) {
                                const double pressurePerPhi = rhoLiquidRef / params.dt;
                                gasAudit0493x6g.pressureDeltaMean =
                                    gasAudit0493x6g.pressurePotentialMean * pressurePerPhi;
                                gasAudit0493x6g.pressureDeltaStd =
                                    gasAudit0493x6g.pressurePotentialStd * pressurePerPhi;
                            }
                        }
                        append_phase_interface_gas_pressure_audit_0493x6g(
                            params, step, time, gasAudit0493x6g);
                    }
                }
            }
        }

        if (freeSurfaceMode0493x5a &&
            cuda_q6_phase_pressure_diagnostics_0493x6a_requested()) {
            double liquidReferenceCellMass0493x6a = 0.0;
            int gasSpeciesCount0493x6a = 0;
            for (const SpeciesDefinition& d : params.speciesDefinitions) {
                if (d.phaseFamily == SpeciesPhaseFamily::Liquid &&
                    d.q6StrengthDeclared > 0.0) {
                    liquidReferenceCellMass0493x6a += d.referenceCellMassDeclared;
                }
                if (d.phaseFamily == SpeciesPhaseFamily::Gas) {
                    ++gasSpeciesCount0493x6a;
                }
            }
            if (!(liquidReferenceCellMass0493x6a > 0.0)) {
                diag.reason =
                    "0493x6a phase-pressure diagnostic requires positive projected liquid reference mass";
                append_independent_masked_species_audit_0493w5(params, step, time, audits);
                return false;
            }
            q6_build_phase_gas_pressure_potential_0493x6a<<<cellBlocks, threads>>>(
                species, params.dt, params.kBT, liquidReferenceCellMass0493x6a,
                ws.phaseGasPressurePotential0493x6a.data());
            check_cuda_0400(cudaGetLastError(),
                            "0493x6a gas pressure-potential build launch");
            check_cuda_0400(cudaMemset(ws.counter.data(), 0,
                                       sizeof(unsigned long long)),
                            "0493x6a interface-face counter zero");
            q6_phase_interface_pressure_stats_0493x6a<<<
                cellBlocks, threads, tripleShared>>>(
                    ws.speciesMask0493w5.data(),
                    ws.phaseGasPressurePotential0493x6a.data(),
                    ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),
                    ws.counter.data(), grid.Nx, grid.Ny, periodicX, periodicY);
            check_cuda_0400(cudaGetLastError(),
                            "0493x6a interface pressure stats launch");
            unsigned long long interfaceFaces0493x6a = 0ull;
            check_cuda_0400(cudaMemcpy(&interfaceFaces0493x6a, ws.counter.data(),
                                       sizeof(interfaceFaces0493x6a),
                                       cudaMemcpyDeviceToHost),
                            "0493x6a interface-face counter download");
            const double phiSum0493x6a =
                reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            const double phiSq0493x6a =
                reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
            const double phiMax0493x6a =
                reduce_host_max_0400(ws.partial2.data(), cellBlocks);

            PhaseInterfacePressureAudit0493x6a pressureAudit{};
            pressureAudit.projectedSpeciesIndex = s;
            pressureAudit.projectedType = audit.type;
            pressureAudit.gasSpeciesCount = gasSpeciesCount0493x6a;
            pressureAudit.interfaceFaces =
                static_cast<std::uint64_t>(interfaceFaces0493x6a);
            pressureAudit.projectedLiquidReferenceCellMass =
                liquidReferenceCellMass0493x6a;
            pressureAudit.cellArea = dx * dy;
            if (interfaceFaces0493x6a > 0ull) {
                const double invFaces =
                    1.0 / static_cast<double>(interfaceFaces0493x6a);
                pressureAudit.pressurePotentialMean = phiSum0493x6a * invFaces;
                const double phiMeanSq = phiSq0493x6a * invFaces;
                pressureAudit.pressurePotentialStd = std::sqrt(std::max(
                    0.0, phiMeanSq -
                    pressureAudit.pressurePotentialMean *
                        pressureAudit.pressurePotentialMean));
                pressureAudit.pressurePotentialMax = phiMax0493x6a;
                if (params.dt > 0.0 && params.kBT > 0.0) {
                    pressureAudit.meanGasParticlesPerExteriorFace =
                        pressureAudit.pressurePotentialMean *
                        liquidReferenceCellMass0493x6a /
                        (params.dt * params.kBT);
                }
                const double rhoLiquidRef = pressureAudit.cellArea > 0.0
                    ? liquidReferenceCellMass0493x6a / pressureAudit.cellArea
                    : 0.0;
                const double phiToPressure = params.dt > 0.0
                    ? rhoLiquidRef / params.dt : 0.0;
                pressureAudit.pressureEOSMean =
                    pressureAudit.pressurePotentialMean * phiToPressure;
                pressureAudit.pressureEOSStd =
                    pressureAudit.pressurePotentialStd * phiToPressure;
                pressureAudit.pressureEOSMax =
                    pressureAudit.pressurePotentialMax * phiToPressure;
            }
            append_phase_interface_pressure_audit_0493x6a(
                params, step, time, pressureAudit);
        }

        const bool geometryDiagnostic0493x6b =
            freeSurfaceMode0493x5a &&
            cuda_q6_phase_geometry_diagnostics_0493x6b_requested() &&
            (step <= 1 || step % std::max(1, params.summaryEvery) == 0);
        if (geometryDiagnostic0493x6b) {
            double liquidPhaseReferenceCellMass0493x6b = 0.0;
            int liquidPhaseSpeciesCount0493x6b = 0;
            for (const SpeciesDefinition& d : params.speciesDefinitions) {
                if (d.phaseFamily == SpeciesPhaseFamily::Liquid) {
                    liquidPhaseReferenceCellMass0493x6b += d.referenceCellMassDeclared;
                    ++liquidPhaseSpeciesCount0493x6b;
                }
            }
            if (!(liquidPhaseReferenceCellMass0493x6b > 0.0) ||
                liquidPhaseSpeciesCount0493x6b == 0) {
                diag.reason =
                    "0493x6b phase-geometry diagnostic requires a positive liquid phase reference mass";
                append_independent_masked_species_audit_0493w5(params, step, time, audits);
                return false;
            }

            check_cuda_0400(cudaMemset(ws.phaseGeometryAccum0493x6b.data(), 0,
                                       sizeof(PhaseGeometryAccumulator0493x6b)),
                            "0493x6b phase geometry accumulator zero");
            const auto tGeometry0493x6b = Clock0400::now();
            q6_phase_interface_geometry_stats_0493x6b<<<cellBlocks, threads>>>(
                species, ws.speciesMask0493w5.data(),
                liquidPhaseReferenceCellMass0493x6b,
                params.speciesQ6MinOccupancyFraction,
                ws.phaseGeometryAccum0493x6b.data(),
                grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
            check_cuda_0400(cudaGetLastError(),
                            "0493x6b phase geometry stats launch");
            PhaseGeometryAccumulator0493x6b geometryAccum0493x6b{};
            check_cuda_0400(cudaMemcpy(&geometryAccum0493x6b,
                                       ws.phaseGeometryAccum0493x6b.data(),
                                       sizeof(geometryAccum0493x6b),
                                       cudaMemcpyDeviceToHost),
                            "0493x6b phase geometry accumulator download");

            PhaseInterfaceGeometryAudit0493x6b geometryAudit{};
            geometryAudit.projectedSpeciesIndex = s;
            geometryAudit.projectedType = audit.type;
            geometryAudit.liquidPhaseSpeciesCount = liquidPhaseSpeciesCount0493x6b;
            geometryAudit.maskActiveCells = carrierActiveCells0493x6f;
            geometryAudit.phaseFillActiveCells =
                static_cast<std::uint64_t>(geometryAccum0493x6b.phaseFillActiveCells);
            geometryAudit.maskPhaseMismatchCells =
                static_cast<std::uint64_t>(geometryAccum0493x6b.maskPhaseMismatchCells);
            geometryAudit.interfaceFaces =
                static_cast<std::uint64_t>(geometryAccum0493x6b.interfaceFaces);
            geometryAudit.liquidPhaseReferenceCellMass =
                liquidPhaseReferenceCellMass0493x6b;
            geometryAudit.supportIsoFill = params.speciesQ6MinOccupancyFraction;
            if (geometryAccum0493x6b.interfaceFaces > 0ull) {
                const double invFaces =
                    1.0 / static_cast<double>(geometryAccum0493x6b.interfaceFaces);
                geometryAudit.insideFillMean = geometryAccum0493x6b.insideFillSum * invFaces;
                geometryAudit.outsideFillMean = geometryAccum0493x6b.outsideFillSum * invFaces;
                geometryAudit.supportThetaValidFraction =
                    static_cast<double>(geometryAccum0493x6b.supportThetaValidFaces) * invFaces;
                geometryAudit.supportThetaNearCellFraction =
                    static_cast<double>(geometryAccum0493x6b.supportThetaNearCellFaces) * invFaces;
                geometryAudit.supportThetaNearExteriorFraction =
                    static_cast<double>(geometryAccum0493x6b.supportThetaNearExteriorFaces) * invFaces;
                geometryAudit.halfIsoBracketFraction =
                    static_cast<double>(geometryAccum0493x6b.halfIsoBracketFaces) * invFaces;
                geometryAudit.normalValidFraction =
                    static_cast<double>(geometryAccum0493x6b.normalValidFaces) * invFaces;
            }
            if (geometryAccum0493x6b.supportThetaValidFaces > 0ull) {
                const double inv = 1.0 /
                    static_cast<double>(geometryAccum0493x6b.supportThetaValidFaces);
                geometryAudit.supportThetaMean = geometryAccum0493x6b.supportThetaSum * inv;
                const double meanSq = geometryAccum0493x6b.supportThetaSqSum * inv;
                geometryAudit.supportThetaStd = std::sqrt(std::max(
                    0.0, meanSq - geometryAudit.supportThetaMean *
                                      geometryAudit.supportThetaMean));
                geometryAudit.supportThetaMidpointRms = std::sqrt(std::max(
                    0.0, geometryAccum0493x6b.supportThetaMidSqSum * inv));
            }
            if (geometryAccum0493x6b.halfIsoBracketFaces > 0ull) {
                const double inv = 1.0 /
                    static_cast<double>(geometryAccum0493x6b.halfIsoBracketFaces);
                geometryAudit.halfIsoThetaMean = geometryAccum0493x6b.halfIsoThetaSum * inv;
                const double meanSq = geometryAccum0493x6b.halfIsoThetaSqSum * inv;
                geometryAudit.halfIsoThetaStd = std::sqrt(std::max(
                    0.0, meanSq - geometryAudit.halfIsoThetaMean *
                                      geometryAudit.halfIsoThetaMean));
            }
            if (geometryAccum0493x6b.normalValidFaces > 0ull) {
                const double inv = 1.0 /
                    static_cast<double>(geometryAccum0493x6b.normalValidFaces);
                geometryAudit.normalOutwardFraction =
                    static_cast<double>(geometryAccum0493x6b.normalOutwardFaces) * inv;
                geometryAudit.normalFaceAlignmentMean =
                    geometryAccum0493x6b.normalFaceAlignmentSum * inv;
            }
            geometryAudit.diagnosticSeconds = seconds_since_0400(tGeometry0493x6b);
            append_phase_interface_geometry_audit_0493x6b(
                params, step, time, geometryAudit);
        }

        // 0493x8t pressure-outlet density target mean removal
        // x7d remains active locally, but its constant divergence mode may not
        // act as a second global flow controller beside the x8r pressure outlet.
        const bool densityRelaxationCenterMean0493x8t =
            densityRelaxationRequested0493x7c &&
            pressureOutletDirichlet0493x8r &&
            audit.fullDomain;

        q6_build_independent_rhs_after_mask_0493w5<<<cellBlocks, threads, tripleShared>>>(
            species, s, q6SolveMask0493x6f, ws.speciesMask0493w5.data(),
            ws.rhs.data(),
            ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),
            grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
            xLowFlux, xHighFlux, yLowFlux, yHighFlux, segmentedIo,
            audit.type, exclusiveProjectedSpecies,
            interfaceDirichletApplySpecies0493x9d ? ws.phaseFaceCoeffX0493x6f.data() : nullptr,
            interfaceDirichletApplySpecies0493x9d ? ws.phaseFaceCoeffY0493x6f.data() : nullptr,
            interfaceDirichletApplySpecies0493x9d ? ws.phaseFacePhiGammaX0493x6g.data() : nullptr,
            interfaceDirichletApplySpecies0493x9d ? ws.phaseFacePhiGammaY0493x6g.data() : nullptr,
            interfaceDirichletApplySpecies0493x9d ? 1 : 0,
            densityRelaxationRequested0493x7c ? ws.phaseFillRaw0493x6c.data() : nullptr,
            densityRelaxationBeta0493x7d, params.dt,
            params.q6DensityRelaxationCompressionThresholdFill,
            params.q6DensityRelaxationCompressionGateEnable ? 1 : 0,
            params.q6DensityRelaxationTractionThresholdFill,
            params.q6DensityRelaxationTractionGain,
            densityRelaxationRequested0493x7c ? 1 : 0,
            densityRelaxationCenterMean0493x8t ? 1 : 0,
            audit.fullDomain ? 1 : 0);
        check_cuda_0400(cudaGetLastError(), "independent masked rhs launch");
        double divBeforeSq = 0.0;

        const bool residentCgUsed0493x7j =
            phaseInterfaceStencilSpecies0493x6f &&
            launch_q6_g_f_resident_cg_0493x7j(
                ws, q6SolveMask0493x6f,
                ws.phaseFaceCoeffX0493x6f.data(),
                ws.phaseFaceCoeffY0493x6f.data(),
                cellBlocks, grid.Nx, grid.Ny, grid.numCells,
                params.projectionMaxIterations, tol, invDx2, invDy2,
                periodicX, periodicY, segmentedIo,
                densityRelaxationCenterMean0493x8t,
                pressureOutletDirichlet0493x8r,
                pressureOutletDeflation0493x8s && audit.fullDomain,
                audit.fullDomain, divBeforeSq, audit);
        if (!residentCgUsed0493x7j) {
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
            audit.divBeforeMaxAbs = reduce_host_max_0400(ws.partial2.data(), cellBlocks);
            audit.divBeforeRms = std::sqrt(
                divBeforeSq /
                static_cast<double>(std::max<std::uint64_t>(1u, audit.activeCells)));
            const bool removeConstantNullspace0493x8r =
                audit.fullDomain && !pressureOutletDirichlet0493x8r;
            const double rhsMean = removeConstantNullspace0493x8r
                ? rhsSum / static_cast<double>(grid.numCells)
                : 0.0;
            const bool deflatePressureOutlet0493x8s =
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

            for (int it = 0; it < params.projectionMaxIterations && !audit.converged; ++it) {
                q6_apply_masked_operator_and_dot_0493w5<<<cellBlocks, threads, scalarShared>>>(
                    ws.p.data(), ws.Ap.data(), q6SolveMask0493x6f,
                    ws.partial0.data(), grid.Nx, grid.Ny, invDx2, invDy2,
                    periodicX, periodicY,
                    cutFaceGeometry0493x6d ? ws.phaseAlphaFiltered0493x6c.data() : nullptr,
                    cutFaceGeometry0493x6d ? 1 : 0,
                    kPhaseCutFaceThetaMin0493x6d,
                    phaseInterfaceStencilSpecies0493x6f ? ws.phaseFaceCoeffX0493x6f.data() : nullptr,
                    phaseInterfaceStencilSpecies0493x6f ? ws.phaseFaceCoeffY0493x6f.data() : nullptr,
                    phaseInterfaceStencilSpecies0493x6f ? 1 : 0,
                    inactiveNeighborFactor0493x5a, segmentedIo);
                check_cuda_0400(cudaGetLastError(), "independent masked operator launch");
                const double pAp = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
                if (!(pAp > 0.0) || !std::isfinite(pAp)) {
                    audit.converged = false;
                    audit.residualRel = std::numeric_limits<double>::infinity();
                    break;
                }
                const double alpha = rr / pAp;
                q6_axpy_residual_0400<<<cellBlocks, threads>>>(
                    ws.phi.data(), ws.r.data(), ws.p.data(), ws.Ap.data(), alpha,
                    grid.numCells);
                check_cuda_0400(cudaGetLastError(), "independent masked axpy launch");
                q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                    ws.r.data(), ws.partial0.data(), grid.numCells);
                check_cuda_0400(cudaGetLastError(), "independent masked rr launch");
                double rrNew = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
                audit.iterations = it + 1;
                audit.residualRel = std::sqrt(std::max(0.0, rrNew)) / rhsNormSafe;
                if (audit.residualRel <= tol) {
                    rr = rrNew;
                    audit.converged = true;
                    break;
                }
                if (removeConstantNullspace0493x8r && (it + 1) % 25 == 0) {
                    q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                        ws.phi.data(), ws.partial0.data(), grid.numCells);
                    q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                        ws.r.data(), ws.partial1.data(), grid.numCells);
                    check_cuda_0400(cudaGetLastError(),
                                    "independent masked mean reduction launch");
                    const double phiMean = reduce_host_sum_0400(ws.partial0.data(), cellBlocks) /
                                           static_cast<double>(grid.numCells);
                    const double rMean = reduce_host_sum_0400(ws.partial1.data(), cellBlocks) /
                                         static_cast<double>(grid.numCells);
                    q6_subtract_mean_pair_0400<<<cellBlocks, threads>>>(
                        ws.phi.data(), ws.r.data(), phiMean, rMean, grid.numCells);
                    check_cuda_0400(cudaGetLastError(),
                                    "independent masked mean subtract launch");
                    q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                        ws.r.data(), ws.partial0.data(), grid.numCells);
                    check_cuda_0400(cudaGetLastError(),
                                    "independent masked rr after mean launch");
                    rrNew = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
                }
                const double beta = rrNew / std::max(rr, 1.0e-300);
                q6_update_p_0400<<<cellBlocks, threads>>>(
                    ws.p.data(), ws.r.data(), beta, grid.numCells);
                check_cuda_0400(cudaGetLastError(), "independent masked p update launch");
                rr = rrNew;
            }

        }

        allConverged = allConverged && audit.converged;
        maxIterations = std::max(maxIterations, audit.iterations);
        maxResidualRel = std::max(maxResidualRel, audit.residualRel);

        // 0493x9e: observe the solved Q6 pressure potential in deep liquid and
        // the x6g EOS potential in deep gas using the same gauge.  Also compute
        // a discrete face-normal capillary resultant from the p3 curvature.
        if (staticDropDiagnosticsThisStep0493x9e && audit.converged &&
            phaseInterfaceStencilSpecies0493x6f &&
            ws.phaseCurvature3PassValid0493x9d &&
            ws.phaseCurvature3PassStep0493x9d == step) {
            check_cuda_0400(cudaMemset(ws.staticDropCellAccum0493x9e.data(), 0,
                                      sizeof(StaticDropCellAccumulator0493x9e)),
                            "0493x9e pressure accumulator zero");
            check_cuda_0400(cudaMemset(ws.staticDropFaceAccum0493x9e.data(), 0,
                                      sizeof(StaticDropFaceAccumulator0493x9e)),
                            "0493x9e face resultant accumulator zero");
            q6_static_drop_pressure_cells_0493x9e<<<cellBlocks, threads>>>(
                ws.phaseAlphaFiltered0493x6c.data(), q6SolveMask0493x6f,
                ws.phi.data(),
                phaseGasPressureApplySpecies0493x6g
                    ? ws.phaseGasPressurePotential0493x6a.data() : nullptr,
                ws.staticDropCellAccum0493x9e.data(), grid.numCells);
            check_cuda_0400(cudaGetLastError(),
                            "0493x9e pressure cells launch");
            q6_static_drop_capillary_resultant_0493x9e<<<cellBlocks, threads>>>(
                ws.phaseAlphaFiltered0493x6c.data(),
                ws.phaseCurvature3Pass0493x9c.data(),
                ws.staticDropFaceAccum0493x9e.data(),
                grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
            check_cuda_0400(cudaGetLastError(),
                            "0493x9e capillary resultant launch");
            StaticDropCellAccumulator0493x9e cellAudit0493x9e{};
            StaticDropFaceAccumulator0493x9e faceAudit0493x9e{};
            check_cuda_0400(cudaMemcpy(&cellAudit0493x9e,
                                      ws.staticDropCellAccum0493x9e.data(),
                                      sizeof(cellAudit0493x9e), cudaMemcpyDeviceToHost),
                            "0493x9e pressure accumulator download");
            check_cuda_0400(cudaMemcpy(&faceAudit0493x9e,
                                      ws.staticDropFaceAccum0493x9e.data(),
                                      sizeof(faceAudit0493x9e), cudaMemcpyDeviceToHost),
                            "0493x9e face accumulator download");
            double liquidReferenceMass0493x9e = 0.0;
            for (const SpeciesDefinition& d : params.speciesDefinitions) {
                if (d.phaseFamily == SpeciesPhaseFamily::Liquid) {
                    liquidReferenceMass0493x9e += d.referenceCellMassDeclared;
                }
            }
            const double rhoLiquidRef0493x9e =
                liquidReferenceMass0493x9e / (dx * dy);
            append_static_drop_pressure_audit_0493x9e(
                params, step, time, rhoLiquidRef0493x9e,
                phaseGasPressureReference0493x6g, phaseGasPressureScale0493x6g,
                dx * dy, cellAudit0493x9e, faceAudit0493x9e);
        }
        if (!audit.converged) {
            // 0493x6f-d1: failure-only algebraic/topology audit for the
            // alpha-defined free-surface pressure domain.
            //
            // IMPORTANT: this block is diagnostic only.  It does not modify
            // rhs, phi, masks, face coefficients, convergence criteria, or
            // particle/cell corrections.  The device fields are downloaded
            // only after the masked CG has already failed.
            //
            // The audit views the actual pressure operator as a graph:
            //   - pressure-pressure faces with a positive prepared coefficient
            //     connect pressure unknowns;
            //   - pressure/non-pressure faces with coefficient > 0 are
            //     Dirichlet anchors (physical alpha=0.5 interface in x6f);
            //   - pressure/non-pressure faces with coefficient == 0 are
            //     Neumann-like algebraic truncations;
            //   - non-periodic exterior domain faces are also non-Dirichlet
            //     for this masked operator.
            //
            // For every connected component we report sum(rhs).  An
            // unanchored component requires sum(rhs)=0 for solvability.
            if (freeSurfaceMode0493x5a && phaseInterfaceStencilSpecies0493x6f) {
                const int topoNx0493x6fd1 = grid.Nx;
                const int topoNy0493x6fd1 = grid.Ny;
                const int topoN0493x6fd1 = grid.numCells;

                std::vector<unsigned char> pressureMaskH0493x6fd1(
                    static_cast<std::size_t>(topoN0493x6fd1), 0u);
                std::vector<unsigned char> carrierMaskH0493x6fd1(
                    static_cast<std::size_t>(topoN0493x6fd1), 0u);
                std::vector<double> faceCoeffXH0493x6fd1(
                    static_cast<std::size_t>(topoN0493x6fd1), 0.0);
                std::vector<double> faceCoeffYH0493x6fd1(
                    static_cast<std::size_t>(topoN0493x6fd1), 0.0);
                std::vector<double> rhsH0493x6fd1(
                    static_cast<std::size_t>(topoN0493x6fd1), 0.0);

                // 0493x6f-d2: capture the projected-species state that produced
                // each carrier truncation.  These downloads remain failure-only.
                std::vector<unsigned int> speciesCountH0493x6fd2(
                    static_cast<std::size_t>(topoN0493x6fd1), 0u);
                std::vector<double> speciesMassH0493x6fd2(
                    static_cast<std::size_t>(topoN0493x6fd1), 0.0);
                std::vector<double> speciesPxH0493x6fd2(
                    static_cast<std::size_t>(topoN0493x6fd1), 0.0);
                std::vector<double> speciesPyH0493x6fd2(
                    static_cast<std::size_t>(topoN0493x6fd1), 0.0);
                std::vector<double> alphaFilteredH0493x6fd2(
                    static_cast<std::size_t>(topoN0493x6fd1), 0.0);
                // 0493x6f-d3: download the exact resident raw phase-fill field
                // consumed by the x6c five-point filter.  This avoids inferring
                // geometry from the projected species alone when more than one
                // liquid species exists.
                std::vector<double> phaseFillRawH0493x6fd3(
                    static_cast<std::size_t>(topoN0493x6fd1), 0.0);
                double referenceCellMassH0493x6fd2 = 0.0;
                const std::size_t speciesOffset0493x6fd2 =
                    static_cast<std::size_t>(s) *
                    static_cast<std::size_t>(topoN0493x6fd1);

                check_cuda_0400(cudaMemcpy(
                                    pressureMaskH0493x6fd1.data(),
                                    q6SolveMask0493x6f,
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(unsigned char),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d1 pressure mask download");
                check_cuda_0400(cudaMemcpy(
                                    carrierMaskH0493x6fd1.data(),
                                    ws.speciesMask0493w5.data(),
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(unsigned char),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d1 carrier mask download");
                check_cuda_0400(cudaMemcpy(
                                    faceCoeffXH0493x6fd1.data(),
                                    ws.phaseFaceCoeffX0493x6f.data(),
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(double),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d1 face coeff X download");
                check_cuda_0400(cudaMemcpy(
                                    faceCoeffYH0493x6fd1.data(),
                                    ws.phaseFaceCoeffY0493x6f.data(),
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(double),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d1 face coeff Y download");
                check_cuda_0400(cudaMemcpy(
                                    rhsH0493x6fd1.data(),
                                    ws.rhs.data(),
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(double),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d1 rhs download");
                check_cuda_0400(cudaMemcpy(
                                    speciesCountH0493x6fd2.data(),
                                    species.count + speciesOffset0493x6fd2,
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(unsigned int),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d2 species count download");
                check_cuda_0400(cudaMemcpy(
                                    speciesMassH0493x6fd2.data(),
                                    species.mass + speciesOffset0493x6fd2,
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(double),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d2 species mass download");
                check_cuda_0400(cudaMemcpy(
                                    speciesPxH0493x6fd2.data(),
                                    species.px + speciesOffset0493x6fd2,
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(double),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d2 species px download");
                check_cuda_0400(cudaMemcpy(
                                    speciesPyH0493x6fd2.data(),
                                    species.py + speciesOffset0493x6fd2,
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(double),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d2 species py download");
                check_cuda_0400(cudaMemcpy(
                                    alphaFilteredH0493x6fd2.data(),
                                    ws.phaseAlphaFiltered0493x6c.data(),
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(double),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d2 filtered alpha download");
                check_cuda_0400(cudaMemcpy(
                                    phaseFillRawH0493x6fd3.data(),
                                    ws.phaseFillRaw0493x6c.data(),
                                    static_cast<std::size_t>(topoN0493x6fd1) *
                                        sizeof(double),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d3 raw phase-fill download");
                check_cuda_0400(cudaMemcpy(
                                    &referenceCellMassH0493x6fd2,
                                    species.referenceCellMass + s,
                                    sizeof(double),
                                    cudaMemcpyDeviceToHost),
                                "0493x6f-d2 reference cell mass download");

                std::cerr
                    << "[0493x6f-d2] carrier-threshold context"
                    << " step=" << step
                    << " time=" << time
                    << " species=" << s
                    << " referenceCellMass=" << referenceCellMassH0493x6fd2
                    << " minFill="
                    << params.speciesQ6MinOccupancyFraction
                    << "\n";

                struct PressureComponent0493x6fd1 {
                    std::uint64_t cells = 0;
                    std::uint64_t dirichletFaces = 0;
                    std::uint64_t zeroCoeffBoundaryFaces = 0;
                    std::uint64_t truncationFaces = 0;
                    std::uint64_t zeroCoeffCarrierPresentFaces = 0;
                    std::uint64_t domainBoundaryFaces = 0;
                    std::uint64_t zeroDiagCells = 0;
                    std::uint64_t nonFiniteDiagCells = 0;
                    std::uint64_t negativeFaceCoeffUses = 0;
                    std::uint64_t nonFiniteFaceCoeffUses = 0;
                    double rhsSum = 0.0;
                    double rhsAbsSum = 0.0;
                    double rhsSqSum = 0.0;
                    double diagMin = std::numeric_limits<double>::infinity();
                    double diagMax = 0.0;
                };

                std::vector<int> componentId0493x6fd1(
                    static_cast<std::size_t>(topoN0493x6fd1), -1);
                std::vector<int> stack0493x6fd1;
                stack0493x6fd1.reserve(256);
                std::vector<PressureComponent0493x6fd1> components0493x6fd1;

                const double invDx2Topo0493x6fd1 = 1.0 / (dx * dx);
                const double invDy2Topo0493x6fd1 = 1.0 / (dy * dy);

                for (int seed0493x6fd1 = 0;
                     seed0493x6fd1 < topoN0493x6fd1;
                     ++seed0493x6fd1) {
                    if (pressureMaskH0493x6fd1[seed0493x6fd1] == 0u ||
                        componentId0493x6fd1[seed0493x6fd1] >= 0) {
                        continue;
                    }

                    const int cid0493x6fd1 =
                        static_cast<int>(components0493x6fd1.size());
                    components0493x6fd1.emplace_back();
                    auto& comp0493x6fd1 = components0493x6fd1.back();
                    componentId0493x6fd1[seed0493x6fd1] = cid0493x6fd1;
                    stack0493x6fd1.clear();
                    stack0493x6fd1.push_back(seed0493x6fd1);

                    while (!stack0493x6fd1.empty()) {
                        const int c0493x6fd1 = stack0493x6fd1.back();
                        stack0493x6fd1.pop_back();
                        ++comp0493x6fd1.cells;

                        const double rhsValue0493x6fd1 =
                            rhsH0493x6fd1[c0493x6fd1];
                        comp0493x6fd1.rhsSum += rhsValue0493x6fd1;
                        comp0493x6fd1.rhsAbsSum += std::fabs(rhsValue0493x6fd1);
                        comp0493x6fd1.rhsSqSum +=
                            rhsValue0493x6fd1 * rhsValue0493x6fd1;

                        const int ix0493x6fd1 = c0493x6fd1 % topoNx0493x6fd1;
                        const int iy0493x6fd1 = c0493x6fd1 / topoNx0493x6fd1;
                        double diag0493x6fd1 = 0.0;

                        auto inspectFace0493x6fd1 =
                            [&](bool hasNeighbour0493x6fd1,
                                int neighbour0493x6fd1,
                                double factor0493x6fd1,
                                double invH20493x6fd1) {
                                if (!hasNeighbour0493x6fd1) {
                                    ++comp0493x6fd1.domainBoundaryFaces;
                                    return;
                                }

                                if (!std::isfinite(factor0493x6fd1)) {
                                    ++comp0493x6fd1.nonFiniteFaceCoeffUses;
                                    diag0493x6fd1 =
                                        std::numeric_limits<double>::quiet_NaN();
                                    return;
                                }
                                if (factor0493x6fd1 < 0.0) {
                                    ++comp0493x6fd1.negativeFaceCoeffUses;
                                }

                                diag0493x6fd1 +=
                                    factor0493x6fd1 * invH20493x6fd1;

                                if (pressureMaskH0493x6fd1[
                                        neighbour0493x6fd1] != 0u) {
                                    // Connectivity is defined by the actual
                                    // off-diagonal coupling of A, not merely
                                    // by pressure-mask adjacency.
                                    if (factor0493x6fd1 > 0.0 &&
                                        componentId0493x6fd1[
                                            neighbour0493x6fd1] < 0) {
                                        componentId0493x6fd1[
                                            neighbour0493x6fd1] =
                                            cid0493x6fd1;
                                        stack0493x6fd1.push_back(
                                            neighbour0493x6fd1);
                                    }
                                    return;
                                }

                                if (factor0493x6fd1 > 0.0) {
                                    ++comp0493x6fd1.dirichletFaces;
                                } else {
                                    ++comp0493x6fd1.zeroCoeffBoundaryFaces;
                                    if (carrierMaskH0493x6fd1[
                                            neighbour0493x6fd1] == 0u) {
                                        ++comp0493x6fd1.truncationFaces;
                                    } else {
                                        // This is not the normal x6f
                                        // same-phase carrier truncation.
                                        // It catches a pressure/exterior face
                                        // whose carrier still exists but whose
                                        // prepared coefficient nevertheless
                                        // vanished (e.g. a pathological
                                        // crossing/denominator case).
                                        ++comp0493x6fd1
                                              .zeroCoeffCarrierPresentFaces;
                                    }
                                }
                            };

                        // East.
                        if (periodicX || ix0493x6fd1 < topoNx0493x6fd1 - 1) {
                            const int xe0493x6fd1 =
                                ix0493x6fd1 + 1 < topoNx0493x6fd1
                                    ? ix0493x6fd1 + 1 : 0;
                            const int east0493x6fd1 =
                                iy0493x6fd1 * topoNx0493x6fd1 + xe0493x6fd1;
                            inspectFace0493x6fd1(
                                true, east0493x6fd1,
                                faceCoeffXH0493x6fd1[c0493x6fd1],
                                invDx2Topo0493x6fd1);
                        } else {
                            inspectFace0493x6fd1(false, c0493x6fd1, 0.0,
                                                invDx2Topo0493x6fd1);
                        }

                        // West.
                        if (periodicX || ix0493x6fd1 > 0) {
                            const int xw0493x6fd1 =
                                ix0493x6fd1 > 0
                                    ? ix0493x6fd1 - 1 : topoNx0493x6fd1 - 1;
                            const int west0493x6fd1 =
                                iy0493x6fd1 * topoNx0493x6fd1 + xw0493x6fd1;
                            inspectFace0493x6fd1(
                                true, west0493x6fd1,
                                faceCoeffXH0493x6fd1[west0493x6fd1],
                                invDx2Topo0493x6fd1);
                        } else {
                            inspectFace0493x6fd1(false, c0493x6fd1, 0.0,
                                                invDx2Topo0493x6fd1);
                        }

                        // North.
                        if (periodicY || iy0493x6fd1 < topoNy0493x6fd1 - 1) {
                            const int yn0493x6fd1 =
                                iy0493x6fd1 + 1 < topoNy0493x6fd1
                                    ? iy0493x6fd1 + 1 : 0;
                            const int north0493x6fd1 =
                                yn0493x6fd1 * topoNx0493x6fd1 + ix0493x6fd1;
                            inspectFace0493x6fd1(
                                true, north0493x6fd1,
                                faceCoeffYH0493x6fd1[c0493x6fd1],
                                invDy2Topo0493x6fd1);
                        } else {
                            inspectFace0493x6fd1(false, c0493x6fd1, 0.0,
                                                invDy2Topo0493x6fd1);
                        }

                        // South.
                        if (periodicY || iy0493x6fd1 > 0) {
                            const int ys0493x6fd1 =
                                iy0493x6fd1 > 0
                                    ? iy0493x6fd1 - 1 : topoNy0493x6fd1 - 1;
                            const int south0493x6fd1 =
                                ys0493x6fd1 * topoNx0493x6fd1 + ix0493x6fd1;
                            inspectFace0493x6fd1(
                                true, south0493x6fd1,
                                faceCoeffYH0493x6fd1[south0493x6fd1],
                                invDy2Topo0493x6fd1);
                        } else {
                            inspectFace0493x6fd1(false, c0493x6fd1, 0.0,
                                                invDy2Topo0493x6fd1);
                        }

                        if (!std::isfinite(diag0493x6fd1)) {
                            ++comp0493x6fd1.nonFiniteDiagCells;
                        } else {
                            if (!(diag0493x6fd1 > 0.0)) {
                                ++comp0493x6fd1.zeroDiagCells;
                            }
                            comp0493x6fd1.diagMin =
                                std::min(comp0493x6fd1.diagMin,
                                         diag0493x6fd1);
                            comp0493x6fd1.diagMax =
                                std::max(comp0493x6fd1.diagMax,
                                         diag0493x6fd1);
                        }
                    }
                }

                std::uint64_t pressureCells0493x6fd1 = 0;
                std::uint64_t unanchoredComponents0493x6fd1 = 0;
                std::uint64_t unanchoredCells0493x6fd1 = 0;
                std::uint64_t largestUnanchoredCells0493x6fd1 = 0;
                double worstCompatibility0493x6fd1 = 0.0;
                int worstCompatibilityComponent0493x6fd1 = -1;

                for (std::size_t ci0493x6fd1 = 0;
                     ci0493x6fd1 < components0493x6fd1.size();
                     ++ci0493x6fd1) {
                    const auto& comp0493x6fd1 =
                        components0493x6fd1[ci0493x6fd1];
                    pressureCells0493x6fd1 += comp0493x6fd1.cells;
                    if (comp0493x6fd1.dirichletFaces != 0u) continue;

                    ++unanchoredComponents0493x6fd1;
                    unanchoredCells0493x6fd1 += comp0493x6fd1.cells;
                    largestUnanchoredCells0493x6fd1 =
                        std::max(largestUnanchoredCells0493x6fd1,
                                 comp0493x6fd1.cells);
                    const double compatibility0493x6fd1 =
                        std::fabs(comp0493x6fd1.rhsSum) /
                        std::max(comp0493x6fd1.rhsAbsSum, 1.0e-300);
                    if (compatibility0493x6fd1 >
                        worstCompatibility0493x6fd1) {
                        worstCompatibility0493x6fd1 =
                            compatibility0493x6fd1;
                        worstCompatibilityComponent0493x6fd1 =
                            static_cast<int>(ci0493x6fd1);
                    }
                }

                std::cerr
                    << "[0493x6f-d1] masked-CG failure topology"
                    << " step=" << step
                    << " time=" << time
                    << " species=" << s
                    << " iterations=" << audit.iterations
                    << " residualRel=" << audit.residualRel
                    << " pressureCells=" << pressureCells0493x6fd1
                    << " components=" << components0493x6fd1.size()
                    << " unanchoredComponents="
                    << unanchoredComponents0493x6fd1
                    << " unanchoredCells=" << unanchoredCells0493x6fd1
                    << " largestUnanchoredCells="
                    << largestUnanchoredCells0493x6fd1
                    << " worstCompatibility="
                    << worstCompatibility0493x6fd1
                    << " worstComponent="
                    << worstCompatibilityComponent0493x6fd1
                    << "\n";

                constexpr std::size_t kMaxPrintedComponents0493x6fd1 = 64;
                constexpr std::size_t kMaxDetailedCells0493x6fd2 = 256;
                constexpr std::size_t kMaxDetailedFaces0493x6fd2 = 512;
                std::size_t printedComponents0493x6fd1 = 0;
                std::size_t printedCells0493x6fd2 = 0;
                std::size_t printedFaces0493x6fd2 = 0;
                for (std::size_t ci0493x6fd1 = 0;
                     ci0493x6fd1 < components0493x6fd1.size();
                     ++ci0493x6fd1) {
                    const auto& comp0493x6fd1 =
                        components0493x6fd1[ci0493x6fd1];
                    if (comp0493x6fd1.dirichletFaces != 0u) continue;
                    if (printedComponents0493x6fd1 >=
                        kMaxPrintedComponents0493x6fd1) {
                        break;
                    }
                    const double compatibility0493x6fd1 =
                        std::fabs(comp0493x6fd1.rhsSum) /
                        std::max(comp0493x6fd1.rhsAbsSum, 1.0e-300);
                    const double rhsRms0493x6fd1 =
                        comp0493x6fd1.cells > 0u
                            ? std::sqrt(
                                  comp0493x6fd1.rhsSqSum /
                                  static_cast<double>(comp0493x6fd1.cells))
                            : 0.0;
                    std::cerr
                        << "[0493x6f-d1] unanchored"
                        << " component=" << ci0493x6fd1
                        << " cells=" << comp0493x6fd1.cells
                        << " dirichletFaces="
                        << comp0493x6fd1.dirichletFaces
                        << " truncationFaces="
                        << comp0493x6fd1.truncationFaces
                        << " zeroCoeffBoundaryFaces="
                        << comp0493x6fd1.zeroCoeffBoundaryFaces
                        << " zeroCoeffCarrierPresentFaces="
                        << comp0493x6fd1.zeroCoeffCarrierPresentFaces
                        << " domainBoundaryFaces="
                        << comp0493x6fd1.domainBoundaryFaces
                        << " rhsSum=" << comp0493x6fd1.rhsSum
                        << " rhsAbsSum=" << comp0493x6fd1.rhsAbsSum
                        << " rhsRms=" << rhsRms0493x6fd1
                        << " compatibility=" << compatibility0493x6fd1
                        << " zeroDiagCells="
                        << comp0493x6fd1.zeroDiagCells
                        << " nonFiniteDiagCells="
                        << comp0493x6fd1.nonFiniteDiagCells
                        << " negativeFaceCoeffUses="
                        << comp0493x6fd1.negativeFaceCoeffUses
                        << " nonFiniteFaceCoeffUses="
                        << comp0493x6fd1.nonFiniteFaceCoeffUses
                        << " diagMin=" << comp0493x6fd1.diagMin
                        << " diagMax=" << comp0493x6fd1.diagMax
                        << "\n";

                    // d2 resolves what the occupancy threshold removed on the
                    // algebraic boundary of this unanchored component.  The
                    // raw free-surface criterion is
                    //   fill = speciesMass / referenceCellMass >= minFill.
                    // x5a regularization can only add enclosed raw-inactive
                    // cells, so a final carrier-inactive neighbour that still
                    // has positive mass should normally classify as
                    // "below_min_fill".
                    double truncationRhsSum0493x6fd2 = 0.0;
                    std::uint64_t truncationFacesSeen0493x6fd2 = 0u;
                    for (int c0493x6fd2 = 0;
                         c0493x6fd2 < topoN0493x6fd1;
                         ++c0493x6fd2) {
                        if (componentId0493x6fd1[c0493x6fd2] !=
                            static_cast<int>(ci0493x6fd1)) {
                            continue;
                        }

                        const int ix0493x6fd2 =
                            c0493x6fd2 % topoNx0493x6fd1;
                        const int iy0493x6fd2 =
                            c0493x6fd2 / topoNx0493x6fd1;
                        const double massC0493x6fd2 =
                            speciesMassH0493x6fd2[c0493x6fd2];
                        const double fillC0493x6fd2 =
                            referenceCellMassH0493x6fd2 > 0.0
                                ? massC0493x6fd2 /
                                      referenceCellMassH0493x6fd2
                                : 0.0;
                        const double uxC0493x6fd2 =
                            massC0493x6fd2 > 0.0
                                ? speciesPxH0493x6fd2[c0493x6fd2] /
                                      massC0493x6fd2
                                : 0.0;
                        const double uyC0493x6fd2 =
                            massC0493x6fd2 > 0.0
                                ? speciesPyH0493x6fd2[c0493x6fd2] /
                                      massC0493x6fd2
                                : 0.0;

                        if (printedCells0493x6fd2 <
                            kMaxDetailedCells0493x6fd2) {
                            std::cerr
                                << "[0493x6f-d2] component-cell"
                                << " component=" << ci0493x6fd1
                                << " cell=" << c0493x6fd2
                                << " ix=" << ix0493x6fd2
                                << " iy=" << iy0493x6fd2
                                << " x="
                                << (static_cast<double>(ix0493x6fd2) + 0.5) *
                                       dx
                                << " y="
                                << (static_cast<double>(iy0493x6fd2) + 0.5) *
                                       dy
                                << " count="
                                << speciesCountH0493x6fd2[c0493x6fd2]
                                << " mass=" << massC0493x6fd2
                                << " fill=" << fillC0493x6fd2
                                << " alphaFiltered="
                                << alphaFilteredH0493x6fd2[c0493x6fd2]
                                << " carrier="
                                << static_cast<int>(
                                       carrierMaskH0493x6fd1[c0493x6fd2])
                                << " pressure="
                                << static_cast<int>(
                                       pressureMaskH0493x6fd1[c0493x6fd2])
                                << " rhs="
                                << rhsH0493x6fd1[c0493x6fd2]
                                << " ux=" << uxC0493x6fd2
                                << " uy=" << uyC0493x6fd2
                                << "\n";
                            ++printedCells0493x6fd2;
                        }

                        auto inspectTruncation0493x6fd2 =
                            [&](const char* face0493x6fd2,
                                bool hasNeighbour0493x6fd2,
                                int neighbour0493x6fd2,
                                double factor0493x6fd2,
                                double tentativeFaceVelocity0493x6fd2,
                                double rhsFaceContribution0493x6fd2) {
                                if (!hasNeighbour0493x6fd2 ||
                                    pressureMaskH0493x6fd1[
                                        neighbour0493x6fd2] != 0u ||
                                    factor0493x6fd2 != 0.0 ||
                                    carrierMaskH0493x6fd1[
                                        neighbour0493x6fd2] != 0u) {
                                    return;
                                }

                                ++truncationFacesSeen0493x6fd2;
                                truncationRhsSum0493x6fd2 +=
                                    rhsFaceContribution0493x6fd2;

                                if (printedFaces0493x6fd2 >=
                                    kMaxDetailedFaces0493x6fd2) {
                                    return;
                                }

                                const int nix0493x6fd2 =
                                    neighbour0493x6fd2 % topoNx0493x6fd1;
                                const int niy0493x6fd2 =
                                    neighbour0493x6fd2 / topoNx0493x6fd1;
                                const double nMass0493x6fd2 =
                                    speciesMassH0493x6fd2[
                                        neighbour0493x6fd2];
                                const double nFill0493x6fd2 =
                                    referenceCellMassH0493x6fd2 > 0.0
                                        ? nMass0493x6fd2 /
                                              referenceCellMassH0493x6fd2
                                        : 0.0;
                                const bool rawThresholdActive0493x6fd2 =
                                    nMass0493x6fd2 > 0.0 &&
                                    referenceCellMassH0493x6fd2 > 0.0 &&
                                    nFill0493x6fd2 >=
                                        params.speciesQ6MinOccupancyFraction;
                                const char* carrierReason0493x6fd2 =
                                    !(nMass0493x6fd2 > 0.0)
                                        ? "mass_nonpositive"
                                        : (nFill0493x6fd2 <
                                                   params
                                                       .speciesQ6MinOccupancyFraction
                                               ? "below_min_fill"
                                               : "unexpected_inactive_after_regularization");
                                const double nUx0493x6fd2 =
                                    nMass0493x6fd2 > 0.0
                                        ? speciesPxH0493x6fd2[
                                              neighbour0493x6fd2] /
                                              nMass0493x6fd2
                                        : 0.0;
                                const double nUy0493x6fd2 =
                                    nMass0493x6fd2 > 0.0
                                        ? speciesPyH0493x6fd2[
                                              neighbour0493x6fd2] /
                                              nMass0493x6fd2
                                        : 0.0;

                                // Re-evaluate the exact x6c conservative filter
                                // on the carrier-inactive neighbour.  Non-periodic
                                // missing neighbours contribute nothing (the same
                                // no-flux convention as the device kernel).
                                const double rawCenter0493x6fd3 =
                                    phaseFillRawH0493x6fd3[
                                        neighbour0493x6fd2];
                                const bool hasW0493x6fd3 =
                                    periodicX || nix0493x6fd2 > 0;
                                const bool hasE0493x6fd3 =
                                    periodicX ||
                                    nix0493x6fd2 < topoNx0493x6fd1 - 1;
                                const bool hasS0493x6fd3 =
                                    periodicY || niy0493x6fd2 > 0;
                                const bool hasN0493x6fd3 =
                                    periodicY ||
                                    niy0493x6fd2 < topoNy0493x6fd1 - 1;

                                const int wix0493x6fd3 =
                                    nix0493x6fd2 > 0
                                        ? nix0493x6fd2 - 1
                                        : topoNx0493x6fd1 - 1;
                                const int eix0493x6fd3 =
                                    nix0493x6fd2 + 1 < topoNx0493x6fd1
                                        ? nix0493x6fd2 + 1
                                        : 0;
                                const int siy0493x6fd3 =
                                    niy0493x6fd2 > 0
                                        ? niy0493x6fd2 - 1
                                        : topoNy0493x6fd1 - 1;
                                const int northIy0493x6fd3 =
                                    niy0493x6fd2 + 1 < topoNy0493x6fd1
                                        ? niy0493x6fd2 + 1
                                        : 0;

                                const int westCell0493x6fd3 =
                                    niy0493x6fd2 * topoNx0493x6fd1 +
                                    wix0493x6fd3;
                                const int eastCell0493x6fd3 =
                                    niy0493x6fd2 * topoNx0493x6fd1 +
                                    eix0493x6fd3;
                                const int southCell0493x6fd3 =
                                    siy0493x6fd3 * topoNx0493x6fd1 +
                                    nix0493x6fd2;
                                const int northCell0493x6fd3 =
                                    northIy0493x6fd3 * topoNx0493x6fd1 +
                                    nix0493x6fd2;

                                const double rawW0493x6fd3 =
                                    hasW0493x6fd3
                                        ? phaseFillRawH0493x6fd3[
                                              westCell0493x6fd3]
                                        : 0.0;
                                const double rawE0493x6fd3 =
                                    hasE0493x6fd3
                                        ? phaseFillRawH0493x6fd3[
                                              eastCell0493x6fd3]
                                        : 0.0;
                                const double rawS0493x6fd3 =
                                    hasS0493x6fd3
                                        ? phaseFillRawH0493x6fd3[
                                              southCell0493x6fd3]
                                        : 0.0;
                                const double rawN0493x6fd3 =
                                    hasN0493x6fd3
                                        ? phaseFillRawH0493x6fd3[
                                              northCell0493x6fd3]
                                        : 0.0;

                                // 0493x6f2: reconstruct the exact bounded
                                // geometric source used by the device filter.
                                const double geomCenter0493x6fd3 =
                                    std::min(1.0, std::max(0.0, rawCenter0493x6fd3));
                                const double geomW0493x6fd3 =
                                    std::min(1.0, std::max(0.0, rawW0493x6fd3));
                                const double geomE0493x6fd3 =
                                    std::min(1.0, std::max(0.0, rawE0493x6fd3));
                                const double geomS0493x6fd3 =
                                    std::min(1.0, std::max(0.0, rawS0493x6fd3));
                                const double geomN0493x6fd3 =
                                    std::min(1.0, std::max(0.0, rawN0493x6fd3));

                                const double contribW0493x6fd3 =
                                    hasW0493x6fd3
                                        ? kPhaseGeometryFilterLambda0493x6c *
                                              (geomW0493x6fd3 - geomCenter0493x6fd3)
                                        : 0.0;
                                const double contribE0493x6fd3 =
                                    hasE0493x6fd3
                                        ? kPhaseGeometryFilterLambda0493x6c *
                                              (geomE0493x6fd3 - geomCenter0493x6fd3)
                                        : 0.0;
                                const double contribS0493x6fd3 =
                                    hasS0493x6fd3
                                        ? kPhaseGeometryFilterLambda0493x6c *
                                              (geomS0493x6fd3 - geomCenter0493x6fd3)
                                        : 0.0;
                                const double contribN0493x6fd3 =
                                    hasN0493x6fd3
                                        ? kPhaseGeometryFilterLambda0493x6c *
                                              (geomN0493x6fd3 - geomCenter0493x6fd3)
                                        : 0.0;
                                const double alphaReconstructed0493x6fd3 =
                                    geomCenter0493x6fd3 +
                                    contribW0493x6fd3 +
                                    contribE0493x6fd3 +
                                    contribS0493x6fd3 +
                                    contribN0493x6fd3;

                                std::cerr
                                    << "[0493x6f-d2] truncation-face"
                                    << " component=" << ci0493x6fd1
                                    << " face=" << face0493x6fd2
                                    << " fromCell=" << c0493x6fd2
                                    << " fromIx=" << ix0493x6fd2
                                    << " fromIy=" << iy0493x6fd2
                                    << " toCell=" << neighbour0493x6fd2
                                    << " toIx=" << nix0493x6fd2
                                    << " toIy=" << niy0493x6fd2
                                    << " coeff=" << factor0493x6fd2
                                    << " faceVelocity="
                                    << tentativeFaceVelocity0493x6fd2
                                    << " rhsFaceContribution="
                                    << rhsFaceContribution0493x6fd2
                                    << " neighbourCount="
                                    << speciesCountH0493x6fd2[
                                           neighbour0493x6fd2]
                                    << " neighbourMass="
                                    << nMass0493x6fd2
                                    << " neighbourFill="
                                    << nFill0493x6fd2
                                    << " minFill="
                                    << params.speciesQ6MinOccupancyFraction
                                    << " neighbourAlphaFiltered="
                                    << alphaFilteredH0493x6fd2[
                                           neighbour0493x6fd2]
                                    << " neighbourCarrier="
                                    << static_cast<int>(
                                           carrierMaskH0493x6fd1[
                                               neighbour0493x6fd2])
                                    << " neighbourPressure="
                                    << static_cast<int>(
                                           pressureMaskH0493x6fd1[
                                               neighbour0493x6fd2])
                                    << " rawThresholdActive="
                                    << (rawThresholdActive0493x6fd2 ? 1 : 0)
                                    << " carrierReason="
                                    << carrierReason0493x6fd2
                                    << " neighbourUx=" << nUx0493x6fd2
                                    << " neighbourUy=" << nUy0493x6fd2
                                    << "\n";
                                std::cerr
                                    << "[0493x6f-d3] alpha-reconstruction"
                                    << " component=" << ci0493x6fd1
                                    << " face=" << face0493x6fd2
                                    << " cell=" << neighbour0493x6fd2
                                    << " ix=" << nix0493x6fd2
                                    << " iy=" << niy0493x6fd2
                                    << " lambda="
                                    << kPhaseGeometryFilterLambda0493x6c
                                    << " rawCenter=" << rawCenter0493x6fd3
                                    << " geomCenter=" << geomCenter0493x6fd3
                                    << " hasW=" << (hasW0493x6fd3 ? 1 : 0)
                                    << " rawW=" << rawW0493x6fd3
                                    << " geomW=" << geomW0493x6fd3
                                    << " contribW=" << contribW0493x6fd3
                                    << " hasE=" << (hasE0493x6fd3 ? 1 : 0)
                                    << " rawE=" << rawE0493x6fd3
                                    << " geomE=" << geomE0493x6fd3
                                    << " contribE=" << contribE0493x6fd3
                                    << " hasS=" << (hasS0493x6fd3 ? 1 : 0)
                                    << " rawS=" << rawS0493x6fd3
                                    << " geomS=" << geomS0493x6fd3
                                    << " contribS=" << contribS0493x6fd3
                                    << " hasN=" << (hasN0493x6fd3 ? 1 : 0)
                                    << " rawN=" << rawN0493x6fd3
                                    << " geomN=" << geomN0493x6fd3
                                    << " contribN=" << contribN0493x6fd3
                                    << " alphaReconstructed="
                                    << alphaReconstructed0493x6fd3
                                    << " alphaStored="
                                    << alphaFilteredH0493x6fd2[
                                           neighbour0493x6fd2]
                                    << " delta="
                                    << (alphaReconstructed0493x6fd3 -
                                        alphaFilteredH0493x6fd2[
                                            neighbour0493x6fd2])
                                    << "\n";
                                ++printedFaces0493x6fd2;
                            };

                        if (periodicX ||
                            ix0493x6fd2 < topoNx0493x6fd1 - 1) {
                            const int xe0493x6fd2 =
                                ix0493x6fd2 + 1 < topoNx0493x6fd1
                                    ? ix0493x6fd2 + 1 : 0;
                            const int east0493x6fd2 =
                                iy0493x6fd2 * topoNx0493x6fd1 +
                                xe0493x6fd2;
                            inspectTruncation0493x6fd2(
                                "E", true, east0493x6fd2,
                                faceCoeffXH0493x6fd1[c0493x6fd2],
                                uxC0493x6fd2, -uxC0493x6fd2 / dx);
                        }
                        if (periodicX || ix0493x6fd2 > 0) {
                            const int xw0493x6fd2 =
                                ix0493x6fd2 > 0
                                    ? ix0493x6fd2 - 1
                                    : topoNx0493x6fd1 - 1;
                            const int west0493x6fd2 =
                                iy0493x6fd2 * topoNx0493x6fd1 +
                                xw0493x6fd2;
                            inspectTruncation0493x6fd2(
                                "W", true, west0493x6fd2,
                                faceCoeffXH0493x6fd1[west0493x6fd2],
                                uxC0493x6fd2, uxC0493x6fd2 / dx);
                        }
                        if (periodicY ||
                            iy0493x6fd2 < topoNy0493x6fd1 - 1) {
                            const int yn0493x6fd2 =
                                iy0493x6fd2 + 1 < topoNy0493x6fd1
                                    ? iy0493x6fd2 + 1 : 0;
                            const int north0493x6fd2 =
                                yn0493x6fd2 * topoNx0493x6fd1 +
                                ix0493x6fd2;
                            inspectTruncation0493x6fd2(
                                "N", true, north0493x6fd2,
                                faceCoeffYH0493x6fd1[c0493x6fd2],
                                uyC0493x6fd2, -uyC0493x6fd2 / dy);
                        }
                        if (periodicY || iy0493x6fd2 > 0) {
                            const int ys0493x6fd2 =
                                iy0493x6fd2 > 0
                                    ? iy0493x6fd2 - 1
                                    : topoNy0493x6fd1 - 1;
                            const int south0493x6fd2 =
                                ys0493x6fd2 * topoNx0493x6fd1 +
                                ix0493x6fd2;
                            inspectTruncation0493x6fd2(
                                "S", true, south0493x6fd2,
                                faceCoeffYH0493x6fd1[south0493x6fd2],
                                uyC0493x6fd2, uyC0493x6fd2 / dy);
                        }
                    }

                    std::cerr
                        << "[0493x6f-d2] component-flux"
                        << " component=" << ci0493x6fd1
                        << " truncationFacesSeen="
                        << truncationFacesSeen0493x6fd2
                        << " truncationRhsSum="
                        << truncationRhsSum0493x6fd2
                        << " componentRhsSum="
                        << comp0493x6fd1.rhsSum
                        << " nonTruncationRhsSum="
                        << (comp0493x6fd1.rhsSum -
                            truncationRhsSum0493x6fd2)
                        << "\n";

                    ++printedComponents0493x6fd1;
                }
                if (unanchoredComponents0493x6fd1 >
                    printedComponents0493x6fd1) {
                    std::cerr
                        << "[0493x6f-d1] unanchored output truncated"
                        << " printed=" << printedComponents0493x6fd1
                        << " total=" << unanchoredComponents0493x6fd1
                        << "\n";
                }
                if (printedCells0493x6fd2 >= kMaxDetailedCells0493x6fd2 ||
                    printedFaces0493x6fd2 >= kMaxDetailedFaces0493x6fd2) {
                    std::cerr
                        << "[0493x6f-d2] detailed output capped"
                        << " printedCells=" << printedCells0493x6fd2
                        << " printedFaces=" << printedFaces0493x6fd2
                        << " maxCells=" << kMaxDetailedCells0493x6fd2
                        << " maxFaces=" << kMaxDetailedFaces0493x6fd2
                        << "\n";
                }
            }

            audits.push_back(audit);
            append_independent_masked_species_audit_0493w5(params, step, time, audits);
            diag.reason = freeSurfaceMode0493x5a
                ? "free_surface_masked species solve did not converge"
                : "independent_masked species solve did not converge";
            return false;
        }

        const double effectiveStrength = params.q6ProjectionStrength * audit.strength;
        q6_compute_masked_face_correction_0493w5<<<cellBlocks, threads>>>(
            species, s, ws.phi.data(), q6SolveMask0493x6f,
            ws.r.data(), ws.p.data(), grid.Nx, grid.Ny, dx, dy,
            effectiveStrength, periodicX, periodicY,
            cutFaceGeometry0493x6d ? ws.phaseAlphaFiltered0493x6c.data() : nullptr,
            cutFaceGeometry0493x6d ? 1 : 0,
            kPhaseCutFaceThetaMin0493x6d,
            phaseInterfaceStencilSpecies0493x6f ? ws.phaseFaceCoeffX0493x6f.data() : nullptr,
            phaseInterfaceStencilSpecies0493x6f ? ws.phaseFaceCoeffY0493x6f.data() : nullptr,
            interfaceDirichletApplySpecies0493x9d ? ws.phaseFacePhiGammaX0493x6g.data() : nullptr,
            interfaceDirichletApplySpecies0493x9d ? ws.phaseFacePhiGammaY0493x6g.data() : nullptr,
            interfaceDirichletApplySpecies0493x9d ? 1 : 0,
            phaseInterfaceStencilSpecies0493x6f ? 1 : 0,
            inactiveNeighborFactor0493x5a,
            xHighFlux, yHighFlux,
            segmentedIo, audit.type, exclusiveProjectedSpecies);
        check_cuda_0400(cudaGetLastError(), "independent masked face correction launch");
        // The pressure solve uses q6SolveMask0493x6f, but the liquid carrier
        // remains the correction/application band.  Exterior-side mixed cells
        // can therefore receive the interface-face gradient without becoming
        // pressure unknowns themselves.
        const bool periodicMomentumCorrectionThisSpecies0493x7dv2fix2 =
            faceToParticleRt00493x6hB1 && audit.fullDomain &&
            !virialDensityKickRequested0493x7a && (periodicX || periodicY);
        if (periodicMomentumCorrectionThisSpecies0493x7dv2fix2) {
            check_cuda_0400(cudaMemset(
                ws.periodicMomentumAccum0493x7dv2fix2.data(), 0,
                sizeof(Q6PeriodicMomentumAccumulator0493x7dv2fix2)),
                "0493x7d-v2-fix2 periodic momentum accumulator zero");
            periodicProjectedMomentumCorrection0493x7dv2fix2 = true;
        }
        q6_compute_masked_cell_correction_stats_0493w5<<<
            cellBlocks, threads, q6GfDiagnosticsThisStep0493x7k ? pairShared : 0u>>>(
            species, s, ws.speciesMask0493w5.data(), q6SolveMask0493x6f,
            ws.r.data(), ws.p.data(), ws.dux.data(), ws.duy.data(),
            ws.partial0.data(), ws.partial1.data(), grid.Nx, grid.Ny,
            periodicX, periodicY, audit.fullDomain ? 1 : 0,
            effectiveStrength, xLowFlux, yLowFlux, segmentedIo, audit.type,
            exclusiveProjectedSpecies,
            periodicMomentumCorrectionThisSpecies0493x7dv2fix2
                ? ws.periodicMomentumAccum0493x7dv2fix2.data() : nullptr,
            periodicMomentumCorrectionThisSpecies0493x7dv2fix2 ? 1 : 0,
            periodicX ? 1 : 0, periodicY ? 1 : 0,
            q6GfDiagnosticsThisStep0493x7k ? 1 : 0);
        check_cuda_0400(cudaGetLastError(), "independent masked cell correction launch");

        if (q6ThermalInterfaceWallRequested0493x10o &&
            s == projectedSpeciesIndex0493x7a) {
            q6_x10o_capture_projected_q6_hydrodynamics<<<cellBlocks, threads>>>(
                species, s, ws.speciesMask0493w5.data(),
                ws.dux.data(), ws.duy.data(), ws.r.data(), ws.p.data(),
                ws.kineticQ6HydroValid0493x10o.data(),
                ws.kineticQ6HydroCellUx0493x10o.data(),
                ws.kineticQ6HydroCellUy0493x10o.data(),
                ws.kineticQ6HydroFaceUxEast0493x10o.data(),
                ws.kineticQ6HydroFaceUyNorth0493x10o.data(),
                grid.Nx, grid.Ny, periodicX, periodicY);
            check_cuda_0400(
                cudaGetLastError(), "0493x10o projected Q6 hydrodynamic capture launch");
            ws.kineticQ6HydroFieldValid0493x10o = true;
            ws.kineticQ6HydroFieldStep0493x10o = step;
            ws.kineticQ6HydroFieldType0493x10o = audit.type;
        }
        double correctionSq = 0.0;
        double divAfterSq = 0.0;
        if (q6GfDiagnosticsThisStep0493x7k) {
            correctionSq = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            audit.correctionMaxAbs = reduce_host_max_0400(ws.partial1.data(), cellBlocks);
            audit.correctionRms = std::sqrt(
                correctionSq /
                static_cast<double>(std::max<std::uint64_t>(1u, audit.activeCells)));

            q6_masked_projected_divergence_stats_0493w5<<<
                cellBlocks, threads, tripleShared>>>(
                species, s, q6SolveMask0493x6f, ws.speciesMask0493w5.data(),
                ws.r.data(), ws.p.data(),
                ws.partial0.data(), ws.partial1.data(), grid.Nx, grid.Ny, dx, dy,
                periodicX, periodicY, xLowFlux, xHighFlux, yLowFlux, yHighFlux,
                segmentedIo, audit.type, exclusiveProjectedSpecies,
                densityRelaxationRequested0493x7c ? ws.phaseFillRaw0493x6c.data() : nullptr,
                densityRelaxationBeta0493x7d, params.dt,
                params.q6DensityRelaxationCompressionThresholdFill,
                params.q6DensityRelaxationCompressionGateEnable ? 1 : 0,
                params.q6DensityRelaxationTractionThresholdFill,
                params.q6DensityRelaxationTractionGain,
                densityRelaxationRequested0493x7c ? 1 : 0,
                audit.densityRelaxationTargetDivMeanRemoved0493x8t,
                ws.partial2.data(), audit.fullDomain ? 1 : 0);
            check_cuda_0400(cudaGetLastError(),
                            "independent masked projected divergence launch");
            divAfterSq = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            audit.divAfterProjectedFaceFluxMaxAbs =
                reduce_host_max_0400(ws.partial1.data(), cellBlocks);
            const double densityTargetDivSq0493x7c =
                reduce_host_sum_0400(ws.partial2.data(), cellBlocks);
            audit.divAfterProjectedFaceFluxRms = std::sqrt(
                divAfterSq /
                static_cast<double>(std::max<std::uint64_t>(1u, audit.activeCells)));
            audit.densityRelaxationTargetDivRms = std::sqrt(
                densityTargetDivSq0493x7c /
                static_cast<double>(std::max<std::uint64_t>(1u, audit.activeCells)));
            // Preserve the 0493w5 zero-target meaning.  With x7c enabled these
            // columns become the residual to the non-zero divergence constraint;
            // beta=0 is bit-for-bit the historical projected divergence path.
            audit.divAfterMaxAbs = audit.divAfterProjectedFaceFluxMaxAbs;
            audit.divAfterRms = audit.divAfterProjectedFaceFluxRms;
        }

        double* denseDUx = ws.speciesDUx0493w5.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        double* denseDUy = ws.speciesDUy0493w5.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        check_cuda_0400(cudaMemcpy(denseDUx, ws.dux.data(),
                                   static_cast<std::size_t>(grid.numCells) * sizeof(double),
                                   cudaMemcpyDeviceToDevice),
                        "independent masked dux store");
        check_cuda_0400(cudaMemcpy(denseDUy, ws.duy.data(),
                                   static_cast<std::size_t>(grid.numCells) * sizeof(double),
                                   cudaMemcpyDeviceToDevice),
                        "independent masked duy store");

        totalDivBeforeSq += divBeforeSq;
        if (q6GfDiagnosticsThisStep0493x7k) {
            totalDivAfterSq += divAfterSq;
            totalCorrectionSq += correctionSq;
            maxDivAfter = std::max(maxDivAfter, audit.divAfterProjectedFaceFluxMaxAbs);
            maxCorrection = std::max(maxCorrection, audit.correctionMaxAbs);
        }
        totalActiveCells += audit.activeCells;
        maxDivBefore = std::max(maxDivBefore, audit.divBeforeMaxAbs);
        ++diag.speciesQ6IndependentSolves;
        diag.speciesQ6IndependentActiveCells += audit.activeCells;
        audits.push_back(audit);
    }

    diag.solveSeconds = seconds_since_0400(tSolveAll);
    diag.converged = allConverged;
    diag.iterations = maxIterations;
    diag.residualRel = maxResidualRel;
    if (totalActiveCells > 0u) {
        const double denom = static_cast<double>(totalActiveCells);
        diag.divBeforeRms = std::sqrt(totalDivBeforeSq / denom);
        if (q6GfDiagnosticsThisStep0493x7k) {
            diag.divAfterProjectedFluxRms = std::sqrt(totalDivAfterSq / denom);
            diag.correctionVelocityRms = std::sqrt(totalCorrectionSq / denom);
        }
    }
    diag.divBeforeMaxAbs = maxDivBefore;
    if (q6GfDiagnosticsThisStep0493x7k) {
        diag.divAfterProjectedFluxMaxAbs = maxDivAfter;
        diag.correctionVelocityMaxAbs = maxCorrection;
    }
    if (freeSurfaceMode0493x5a && totalActiveCells == 0u) {
        diag.reason = "free_surface_masked has no active liquid support";
        return false;
    }

    const auto tApplyAll = Clock0400::now();
    double totalDpx = 0.0;
    double totalDpy = 0.0;
    for (IndependentMaskedSpeciesAudit0493w5& audit : audits) {
        if (!(audit.strength > 0.0) || audit.activeCells == 0u) continue;
        const int s = audit.speciesIndex;
        const double* denseDUx = ws.speciesDUx0493w5.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        const double* denseDUy = ws.speciesDUy0493w5.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        if (q6GfDiagnosticsThisStep0493x7k) {
            check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                            "independent masked corrected counter zero");
        }
        const unsigned char* denseMask = ws.speciesMasks0493w6.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        if (faceToParticleRt00493x6hB1) {
            if (periodicProjectedMomentumCorrection0493x7dv2fix2 &&
                cuda_q6_exact_periodic_b1_closure_0493x7y_requested()) {
                // 0493x7q is intentionally a separate kernel path.  Only the
                // monophase full-domain B1 case enters here; partial-domain
                // free-surface/dam-break runs execute the historical B1 launch
                // below byte-for-byte unchanged.
                q6_apply_full_domain_periodic_rt0_0493x7q<<<
                    particleBlocks, threads, tripleShared>>>(
                    particles, cells, denseMask, denseDUx, denseDUy,
                    ws.r.data(), ws.p.data(), audit.type, nParticles,
                    grid.Nx, grid.Ny, params.Lx, params.Ly, periodicX, periodicY,
                    params.dt, params.bodyAccelerationX, params.bodyAccelerationY,
                    tgForceActive0493x5a ? 1 : 0,
                    params.taylorGreenForcingAmplitude,
                    params.taylorGreenForcingModeX, params.taylorGreenForcingModeY,
                    ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),
                    ws.counter.data(), ws.periodicMomentumAccum0493x7dv2fix2.data(),
                    q6GfDiagnosticsThisStep0493x7k ? 1 : 0);
                check_cuda_0400(cudaGetLastError(),
                                "0493x7q full-domain periodic RT0 apply launch");

                q6_finalize_exact_periodic_b1_closure_0493x7q<<<
                    1, threads, tripleShared>>>(
                    ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),
                    particleBlocks, ws.periodicMomentumAccum0493x7dv2fix2.data(),
                    periodicX ? 1 : 0, periodicY ? 1 : 0);
                check_cuda_0400(cudaGetLastError(),
                                "0493x7q exact periodic B1 reduction launch");

                q6_apply_exact_periodic_b1_closure_0493x7q<<<
                    particleBlocks, threads>>>(
                    particles, cells, denseMask, audit.type, nParticles,
                    ws.periodicMomentumAccum0493x7dv2fix2.data(),
                    periodicX ? 1 : 0, periodicY ? 1 : 0);
                check_cuda_0400(cudaGetLastError(),
                                "0493x7q exact periodic B1 closure launch");
            } else {
                // Historical B1 path: keep this launch unchanged for all
                // partial-domain free-surface cases, including dam-break.
                q6_apply_free_surface_force_and_rt0_correction_0493x6h_b1<<<
                    particleBlocks, threads, q6GfDiagnosticsThisStep0493x7k ? pairShared : 0u>>>(
                    particles, cells, denseMask, denseDUx, denseDUy,
                    ws.r.data(), ws.p.data(), audit.type, nParticles,
                    grid.Nx, grid.Ny, params.Lx, params.Ly, periodicX, periodicY,
                    params.dt, params.bodyAccelerationX, params.bodyAccelerationY,
                    tgForceActive0493x5a ? 1 : 0,
                    params.taylorGreenForcingAmplitude,
                    params.taylorGreenForcingModeX, params.taylorGreenForcingModeY,
                    ws.partial0.data(), ws.partial1.data(), ws.counter.data(),
                    periodicProjectedMomentumCorrection0493x7dv2fix2
                        ? ws.periodicMomentumAccum0493x7dv2fix2.data() : nullptr,
                    periodicProjectedMomentumCorrection0493x7dv2fix2 ? 1 : 0,
                    periodicX ? 1 : 0, periodicY ? 1 : 0,
                    q6GfDiagnosticsThisStep0493x7k ? 1 : 0);
                check_cuda_0400(cudaGetLastError(),
                                "0493x6h-B1 fused RT0 free-surface force and Q6 apply launch");
            }
        } else if (freeSurfaceMode0493x5a && fuseForceKick0493x4b) {
            q6_apply_free_surface_force_and_correction_0493x5a<<<
                particleBlocks, threads, q6GfDiagnosticsThisStep0493x7k ? pairShared : 0u>>>(
                particles, cells, denseMask, denseDUx, denseDUy, audit.type,
                nParticles, params.dt, params.Lx, params.Ly,
                params.bodyAccelerationX, params.bodyAccelerationY,
                tgForceActive0493x5a ? 1 : 0,
                params.taylorGreenForcingAmplitude,
                params.taylorGreenForcingModeX, params.taylorGreenForcingModeY,
                ws.partial0.data(), ws.partial1.data(), ws.counter.data(),
                q6GfDiagnosticsThisStep0493x7k ? 1 : 0);
            check_cuda_0400(cudaGetLastError(),
                            "0493x5a fused free-surface force and Q6 apply launch");
        } else {
            q6_apply_independent_species_correction_0493w5<<<
                particleBlocks, threads, q6GfDiagnosticsThisStep0493x7k ? pairShared : 0u>>>(
                particles, cells, denseMask, denseDUx, denseDUy, audit.type,
                nParticles, ws.partial0.data(), ws.partial1.data(),
                ws.counter.data(), q6GfDiagnosticsThisStep0493x7k ? 1 : 0);
            check_cuda_0400(cudaGetLastError(),
                            "independent masked particle apply launch");
        }
        if (q6GfDiagnosticsThisStep0493x7k) {
            audit.momentumX = reduce_host_sum_0400(ws.partial0.data(), particleBlocks);
            audit.momentumY = reduce_host_sum_0400(ws.partial1.data(), particleBlocks);
            unsigned long long corrected = 0ull;
            check_cuda_0400(cudaMemcpy(&corrected, ws.counter.data(), sizeof(corrected),
                                       cudaMemcpyDeviceToHost),
                            "independent masked corrected counter download");
            audit.correctedParticles = static_cast<std::uint64_t>(corrected);
            diag.speciesQ6IndependentCorrectedParticles += audit.correctedParticles;
            totalDpx += audit.momentumX;
            totalDpy += audit.momentumY;
        }
    }
    diag.speciesQ6ParticleApplySeconds = seconds_since_0400(tApplyAll);
    diag.applySeconds = diag.speciesQ6ParticleApplySeconds;
    diag.momentumResidualBeforeCorrection = std::sqrt(totalDpx * totalDpx + totalDpy * totalDpy);
    // A masked free-surface pressure solve may legitimately change the momentum
    // of the projected species through its Dirichlet interface.  Therefore the
    // legacy all-particle correction remains forbidden.  For the monophase
    // full-domain B1 path only, an internal pressure gradient cannot change the
    // projected-species k=0 momentum in a periodic direction.  x7d-v2-fix2
    // removes the cell-centred estimate inside B1; x7q then removes the exact
    // particle-level residual.  Non-periodic traction components remain untouched.
    diag.momentumCorrectionVx = 0.0;
    diag.momentumCorrectionVy = 0.0;
    if (periodicProjectedMomentumCorrection0493x7dv2fix2 &&
        q6GfDiagnosticsThisStep0493x7k) {
        Q6PeriodicMomentumAccumulator0493x7dv2fix2 periodicMomentumAudit0493x7dv2fix2{};
        check_cuda_0400(cudaMemcpy(
            &periodicMomentumAudit0493x7dv2fix2,
            ws.periodicMomentumAccum0493x7dv2fix2.data(),
            sizeof(periodicMomentumAudit0493x7dv2fix2), cudaMemcpyDeviceToHost),
            "0493x7d-v2-fix2 periodic momentum accumulator download");
        if (periodicMomentumAudit0493x7dv2fix2.activeMass > 0.0) {
            if (periodicX) {
                diag.momentumCorrectionVx =
                    periodicMomentumAudit0493x7dv2fix2.momentumX /
                    periodicMomentumAudit0493x7dv2fix2.activeMass +
                    periodicMomentumAudit0493x7dv2fix2.residualVelocityX0493x7q;
            }
            if (periodicY) {
                diag.momentumCorrectionVy =
                    periodicMomentumAudit0493x7dv2fix2.momentumY /
                    periodicMomentumAudit0493x7dv2fix2.activeMass +
                    periodicMomentumAudit0493x7dv2fix2.residualVelocityY0493x7q;
            }
        }
    }

    // 0493x7k: the 0493w6 post-application species rebuild existed to measure
    // the applied-cell divergence.  Positions and masses are unchanged by Q6,
    // and the general cell moments are rebuilt below for the production path.
    // Therefore skip this complete diagnostic redeposit between summary steps.
    // Preserve it when the legacy virial experiment is requested so that path
    // keeps its historical observation point.
    const bool postApplyDiagnosticsThisStep0493x7k =
        q6GfDiagnosticsThisStep0493x7k || virialDensityKickRequested0493x7a;
    if (postApplyDiagnosticsThisStep0493x7k) {
        const int speciesResetBlocks0493w6 = std::max(
            1, std::min(1024,
                (std::max(grid.numCells, grid.numCells * speciesCount) + threads - 1) / threads));
        q6_reset_species_mass_0491c<<<speciesResetBlocks0493w6, threads>>>(species);
        check_cuda_0400(cudaGetLastError(),
                        "independent masked post-apply species reset launch");
        q6_deposit_species_mass_from_cell_ids_0491c<<<particleBlocks, threads>>>(
            particles, cells, species, nParticles);
        check_cuda_0400(cudaGetLastError(),
                        "independent masked post-apply species deposit launch");
        q6_finalize_species_occupancy_0493w5<<<cellBlocks, threads>>>(species);
        check_cuda_0400(cudaGetLastError(),
                        "independent masked post-apply occupancy finalize launch");

        double totalAppliedCellDivSq0493w6 = 0.0;
        double maxAppliedCellDiv0493w6 = 0.0;
        std::uint64_t totalAppliedActiveCells0493w6 = 0u;
        for (IndependentMaskedSpeciesAudit0493w5& audit : audits) {
            if (!(audit.strength > 0.0) || audit.activeCells == 0u) continue;
            const unsigned char* denseMask0493w6 = ws.speciesMasks0493w6.data() +
                static_cast<std::size_t>(audit.speciesIndex) *
                    static_cast<std::size_t>(grid.numCells);
            if (staticDropDiagnosticsThisStep0493x9e &&
                params.speciesDefinitions[static_cast<std::size_t>(audit.speciesIndex)].phaseFamily ==
                    SpeciesPhaseFamily::Liquid &&
                ws.phaseGeometryResidentValid0493x6c &&
                ws.phaseGeometryResidentStep0493x6c == step) {
                check_cuda_0400(cudaMemset(ws.staticDropVelocityAccum0493x9e.data(), 0,
                                          sizeof(StaticDropVelocityAccumulator0493x9e)),
                                "0493x9e velocity accumulator zero");
                q6_static_drop_velocity_cells_0493x9e<<<cellBlocks, threads>>>(
                    species, audit.speciesIndex,
                    ws.phaseAlphaFiltered0493x6c.data(),
                    ws.staticDropVelocityAccum0493x9e.data(),
                    grid.Nx, grid.Ny, periodicX, periodicY);
                check_cuda_0400(cudaGetLastError(),
                                "0493x9e post-Q6 velocity cells launch");
                StaticDropVelocityAccumulator0493x9e velocityAudit0493x9e{};
                check_cuda_0400(cudaMemcpy(&velocityAudit0493x9e,
                                          ws.staticDropVelocityAccum0493x9e.data(),
                                          sizeof(velocityAudit0493x9e), cudaMemcpyDeviceToHost),
                                "0493x9e velocity accumulator download");
                append_static_drop_velocity_audit_0493x9e(
                    params, step, time, audit.type, velocityAudit0493x9e);
                if (ellipseDiagnosticsThisStep0493x9f) {
                    check_cuda_0400(cudaMemset(ws.ellipseParticleMomentAccum0493x9f.data(), 0,
                                              sizeof(EllipseParticleMomentAccumulator0493x9f)),
                                    "0493x9f particle moment accumulator zero");
                    q6_ellipse_particle_moments_0493x9f<<<particleBlocks, threads>>>(
                        particles, nParticles, audit.type,
                        ws.ellipseParticleMomentAccum0493x9f.data());
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9f particle moment launch");
                    EllipseParticleMomentAccumulator0493x9f momentAudit0493x9f{};
                    check_cuda_0400(cudaMemcpy(&momentAudit0493x9f,
                                              ws.ellipseParticleMomentAccum0493x9f.data(),
                                              sizeof(momentAudit0493x9f), cudaMemcpyDeviceToHost),
                                    "0493x9f particle moment download");
                    const double invMass0493x9f = momentAudit0493x9f.massSum > 0.0
                        ? 1.0 / momentAudit0493x9f.massSum : 0.0;
                    const double xcm0493x9f = momentAudit0493x9f.massXSum * invMass0493x9f;
                    const double ycm0493x9f = momentAudit0493x9f.massYSum * invMass0493x9f;
                    EllipseInterfaceRadiusAccumulator0493x9f radiusInit0493x9f{};
                    radiusInit0493x9f.radiusMinScaled =
                        std::numeric_limits<unsigned long long>::max();
                    check_cuda_0400(cudaMemcpy(ws.ellipseInterfaceRadiusAccum0493x9f.data(),
                                              &radiusInit0493x9f,
                                              sizeof(radiusInit0493x9f), cudaMemcpyHostToDevice),
                                    "0493x9f interface radius accumulator init");
                    q6_ellipse_interface_radii_0493x9f<<<cellBlocks, threads>>>(
                        ws.phaseAlphaFiltered0493x6c.data(), xcm0493x9f, ycm0493x9f,
                        ws.ellipseInterfaceRadiusAccum0493x9f.data(),
                        grid.Nx, grid.Ny, dx, dy, periodicX, periodicY);
                    check_cuda_0400(cudaGetLastError(),
                                    "0493x9f interface radius launch");
                    EllipseInterfaceRadiusAccumulator0493x9f radiusAudit0493x9f{};
                    check_cuda_0400(cudaMemcpy(&radiusAudit0493x9f,
                                              ws.ellipseInterfaceRadiusAccum0493x9f.data(),
                                              sizeof(radiusAudit0493x9f), cudaMemcpyDeviceToHost),
                                    "0493x9f interface radius download");
                    append_ellipse_shape_audit_0493x9f(
                        params, step, time, audit.type,
                        momentAudit0493x9f, radiusAudit0493x9f);
                }
            }
            q6_build_independent_rhs_after_mask_0493w5<<<
                cellBlocks, threads, tripleShared>>>(
                species, audit.speciesIndex, denseMask0493w6, denseMask0493w6,
                ws.rhs.data(),
                ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),
                grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                xLowFlux, xHighFlux, yLowFlux, yHighFlux, segmentedIo,
                audit.type, exclusiveProjectedSpecies,
                nullptr, nullptr, nullptr, nullptr, 0,
                nullptr, 0.0, params.dt, 0.0, 0, 0.0, 0.0, 0, 0,
                audit.fullDomain ? 1 : 0);
            check_cuda_0400(cudaGetLastError(),
                            "independent masked post-apply divergence launch");
            const double divAppliedSq0493w6 =
                reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
            audit.divAfterAppliedCellVelocityMaxAbs =
                reduce_host_max_0400(ws.partial2.data(), cellBlocks);
            audit.divAfterAppliedCellVelocityRms = std::sqrt(
                divAppliedSq0493w6 /
                static_cast<double>(std::max<std::uint64_t>(1u, audit.activeCells)));

            if (postApplyRegionAuditThisStep0493x6hB0) {
                const auto tRegion0493x6hB0 = Clock0400::now();
                check_cuda_0400(cudaMemset(
                    ws.postApplyRegionAccum0493x6hB0.data(), 0,
                    sizeof(Q6PostApplyRegionAccumulator0493x6hB0)),
                    "0493x6h-B0 post-apply region accumulator zero");
                const bool interfaceGeometryAvailable0493x6hB0 =
                    phaseGeometryResident0493x6c &&
                    ws.phaseGeometryResidentValid0493x6c &&
                    ws.phaseGeometryResidentStep0493x6c == step;
                q6_postapply_region_stats_0493x6h_b0<<<cellBlocks, threads>>>(
                    species, audit.speciesIndex, denseMask0493w6,
                    interfaceGeometryAvailable0493x6hB0
                        ? ws.phaseAlphaFiltered0493x6c.data() : nullptr,
                    interfaceGeometryAvailable0493x6hB0 ? 1 : 0,
                    ws.postApplyRegionAccum0493x6hB0.data(),
                    grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
                    xLowFlux, yLowFlux, segmentedIo,
                    audit.type, exclusiveProjectedSpecies, audit.fullDomain ? 1 : 0,
                    q6_wall_like_0409(params.bcLeft) ? 1 : 0,
                    q6_wall_like_0409(params.bcRight) ? 1 : 0,
                    q6_wall_like_0409(params.bcBottom) ? 1 : 0,
                    q6_wall_like_0409(params.bcTop) ? 1 : 0);
                check_cuda_0400(cudaGetLastError(),
                                "0493x6h-B0 post-apply region stats launch");
                Q6PostApplyRegionAccumulator0493x6hB0 regionAccum0493x6hB0{};
                check_cuda_0400(cudaMemcpy(
                    &regionAccum0493x6hB0, ws.postApplyRegionAccum0493x6hB0.data(),
                    sizeof(regionAccum0493x6hB0), cudaMemcpyDeviceToHost),
                    "0493x6h-B0 post-apply region accumulator download");
                append_q6_postapply_region_audit_0493x6h_b0(
                    params, step, time, audit, regionAccum0493x6hB0,
                    interfaceGeometryAvailable0493x6hB0,
                    seconds_since_0400(tRegion0493x6hB0));
            }

            totalAppliedCellDivSq0493w6 += divAppliedSq0493w6;
            totalAppliedActiveCells0493w6 += audit.activeCells;
            maxAppliedCellDiv0493w6 = std::max(
                maxAppliedCellDiv0493w6, audit.divAfterAppliedCellVelocityMaxAbs);
        }
        if (totalAppliedActiveCells0493w6 > 0u) {
            diag.divAfterCellVelocityRms = std::sqrt(
                totalAppliedCellDivSq0493w6 /
                static_cast<double>(totalAppliedActiveCells0493w6));
        }
        diag.divAfterCellVelocityMaxAbs = maxAppliedCellDiv0493w6;
    }

    // 0493x7a: prepare the weak virial density-restoring field only after the
    // established q6Applied diagnostic has been evaluated.  The density itself
    // is unchanged by Q6, so x6c rawFill remains authoritative.  Reuse the
    // temporary species mask and dux/duy buffers: no new O(numCells) storage.
    const bool virialAuditThisStep0493x7a =
        virialDensityKickRequested0493x7a &&
        (step <= 1 || step % std::max(1, params.summaryEvery) == 0);
    if (virialDensityKickRequested0493x7a) {
        check_cuda_0400(cudaMemset(
            ws.virialDensityAccum0493x7a.data(), 0,
            sizeof(VirialDensityAccumulator0493x7a)),
            "0493x7a virial accumulator zero");
        q6_prepare_virial_density_kick_0493x7a<<<cellBlocks, threads>>>(
            species, projectedSpeciesIndex0493x7a,
            ws.phaseFillRaw0493x6c.data(),
            ws.phasePressureMask0493x6f.data(),
            ws.speciesMask0493w5.data(),
            ws.dux.data(), ws.duy.data(),
            grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
            params.kVirial, params.betaEOS, params.dt,
            ws.virialDensityAccum0493x7a.data(),
            virialAuditThisStep0493x7a ? 1 : 0);
        check_cuda_0400(cudaGetLastError(),
                        "0493x7a resident virial density preparation launch");
    }

    check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                    "independent masked cell refresh counter zero");
    q6_zero_cell_moments_only_0493w5<<<cellBlocks, threads>>>(cells);
    check_cuda_0400(cudaGetLastError(), "independent masked cell moments reset launch");
    if (virialDensityKickRequested0493x7a) {
        q6_apply_virial_and_deposit_moments_0493x7a<<<particleBlocks, threads>>>(
            particles, cells, ws.speciesMask0493w5.data(),
            ws.dux.data(), ws.duy.data(), projectedSpeciesType0493x7a,
            nParticles, ws.virialDensityAccum0493x7a.data(),
            params.virialMomentumCorrectionEnable ? 1 : 0);
        check_cuda_0400(cudaGetLastError(),
                        "0493x7a virial apply plus cell moments redeposit launch");
    } else {
        q6_thermostat_deposit_moments_from_cell_ids_0400<<<particleBlocks, threads>>>(
            particles, cells, nParticles);
        check_cuda_0400(cudaGetLastError(),
                        "independent masked cell moments redeposit launch");
    }
    q6_finalize_cells_0400<<<cellBlocks, threads>>>(cells, ws.counter.data());
    check_cuda_0400(cudaGetLastError(), "independent masked cell moments finalize launch");

    if (virialAuditThisStep0493x7a) {
        VirialDensityAccumulator0493x7a virialAudit0493x7a{};
        check_cuda_0400(cudaMemcpy(
            &virialAudit0493x7a, ws.virialDensityAccum0493x7a.data(),
            sizeof(virialAudit0493x7a), cudaMemcpyDeviceToHost),
            "0493x7a virial audit download");
        append_virial_density_audit_0493x7a(
            params, step, time, dx, dy, virialAudit0493x7a);
    }

    if (freeSurfaceMode0493x5a &&
        params.phaseInterfaceKineticReflectionFraction > 0.0) {
        const bool geometryValid0493x9x =
            phaseGeometryResident0493x6c &&
            ws.phaseGeometryResidentValid0493x6c &&
            ws.phaseGeometryResidentStep0493x6c == step;
        apply_kinetic_interface_reflection_0493x9x(
            particles, cells, ws, params, grid, step, time, nParticles,
            threads, cellBlocks, particleBlocks, periodicX, periodicY,
            projectedSpeciesType0493x7a,
            geometryValid0493x9x ? ws.phaseAlphaFiltered0493x6c.data() : nullptr,
            geometryValid0493x9x);
    }

    if (q6GfDiagnosticsThisStep0493x7k) {
        append_independent_masked_species_audit_0493w5(params, step, time, audits);
    }
    diag.speciesQ6IndependentMasked = true;
    diag.speciesQ6IndependentDisabledCorrectionMaxAbs = 0.0;
    diag.speciesQ6BarycentricResidualMaxAbs = 0.0;
    diag.speciesQ6BarycentricResidualMaxScaled = 0.0;
    return true;
}

bool supported_subset_0400(const SimulationParams& params,
                           const CellGrid& grid,
                           const FluidDomainBounds& domain,
                           const CudaQ6Resident0400Diagnostics& diag,
                           const char** reason) {
    (void)diag;
    if (!params.projectionEnable) {
        *reason = "projection disabled";
        return false;
    }
    if (params.projectionBackend != "cuda") {
        *reason = "projectionBackend is not cuda";
        return false;
    }
    const bool periodicXY = is_x_periodic(params) && is_y_periodic(params);
    const bool channelXY = is_x_periodic(params) && !is_y_periodic(params) &&
        q6_static_wall_mode_0493x1(params.bcBottom) &&
        q6_static_wall_mode_0493x1(params.bcTop);
    const bool closedBox = q6_closed_box_0493x1_supported(params);
    const bool openFullface = q6_open_fullface_0404_supported(params);
    const bool openSegmented0409 = q6_open_segmented_0409_supported(params);
    if (!periodicXY && !channelXY && !closedBox && !openFullface && !openSegmented0409) {
        *reason = "unsupported boundary condition";
        return false;
    }
    if (params.immersedSolidEnable || params.projectionImmersedSolidMaskEnable) {
        *reason = "immersed solid or projection mask requested";
        return false;
    }
    if ((params.openBoundarySegmentsEnable && !openSegmented0409) ||
        params.closedCapacityResponseEnable || params.closedCapacityVirialKickEnable) {
        *reason = "unsupported segmented open boundary or closed-capacity coupling requested";
        return false;
    }
    if (grid.Nx <= 0 || grid.Ny <= 0 || grid.numCells != grid.Nx * grid.Ny) {
        *reason = "invalid grid";
        return false;
    }
    const double tol = 1.0e-12;
    if (std::abs(domain.xMin) > tol || std::abs(domain.yMin) > tol ||
        std::abs(domain.xMax - params.Lx) > tol || std::abs(domain.yMax - params.Ly) > tol ||
        std::abs(domain.vxMin) > tol || std::abs(domain.vxMax) > tol ||
        std::abs(domain.vyMin) > tol || std::abs(domain.vyMax) > tol) {
        *reason = "moving or truncated fluid domain";
        return false;
    }
    if (!(params.q6ProjectionStrength >= 0.0 && params.q6ProjectionStrength <= 1.0)) {
        *reason = "invalid projection strength";
        return false;
    }
    return true;
}

} // namespace

CudaQ6PhaseCurvatureView0493x9b cuda_q6_phase_curvature_view_0493x9b() {
    CudaQ6PhaseCurvatureView0493x9b view{};
    ResidentWorkspace0400& ws = resident_workspace_0400();
    if (!ws.phaseCurvatureValid0493x9b ||
        ws.phaseCurvature0493x9b.data() == nullptr ||
        ws.phaseCurvatureNx0493x9b <= 0 || ws.phaseCurvatureNy0493x9b <= 0) {
        return view;
    }
    view.deviceCurvature = ws.phaseCurvature0493x9b.data();
    view.nx = ws.phaseCurvatureNx0493x9b;
    view.ny = ws.phaseCurvatureNy0493x9b;
    view.step = ws.phaseCurvatureStep0493x9b;
    view.valid = true;
    return view;
}

CudaQ6PhaseCurvatureView0493x9d cuda_q6_phase_curvature_view_0493x9d() {
    CudaQ6PhaseCurvatureView0493x9d view{};
    ResidentWorkspace0400& ws = resident_workspace_0400();
    if (!ws.phaseCurvature3PassValid0493x9d ||
        ws.phaseCurvature3Pass0493x9c.data() == nullptr ||
        ws.phaseCurvature3PassNx0493x9d <= 0 || ws.phaseCurvature3PassNy0493x9d <= 0) {
        return view;
    }
    view.deviceCurvature = ws.phaseCurvature3Pass0493x9c.data();
    view.deviceAlpha = ws.phaseAlphaFiltered0493x6c.data();
    view.nx = ws.phaseCurvature3PassNx0493x9d;
    view.ny = ws.phaseCurvature3PassNy0493x9d;
    view.step = ws.phaseCurvature3PassStep0493x9d;
    view.valid = true;
    return view;
}


CudaQ6ForceKick0493x3Diagnostics try_apply_cuda_q6_force_kick_0493x3(
    ParticleState& state,
    const SimulationParams& params) {
    CudaQ6ForceKick0493x3Diagnostics diag;
    diag.requested = params.q6ForceProjectionMode == "prestream" ||
                     params.q6ForceProjectionMode == "prestream_single";
    if (!diag.requested) {
        diag.reason = "legacy force ordering";
        return diag;
    }
    const bool tgActive = params.taylorGreenForcingEnable &&
                          params.taylorGreenForcingAmplitude > 0.0;
    const bool uniformActive = params.bodyAccelerationX != 0.0 ||
                               params.bodyAccelerationY != 0.0;
    if (!tgActive && !uniformActive) {
        diag.handled = true;
        diag.reason = "zero force";
        return diag;
    }

    const std::uint64_t active = active_fluid_count(state);
    if (active == 0u) {
        diag.reason = "no active fluid particles";
        return diag;
    }
    CudaParticleState& gpuState = cuda_shared_particle_state_0251();
    if (!cuda_shared_particle_state_0251_is_fresh()) {
        gpuState.upload_all(state);
        gpuState.set_active_fluid_size(active);
        cuda_shared_particle_state_0251_mark_fresh("cuda_q6_force_kick_0493x3_upload");
    }
    CudaParticleDeviceView particles = gpuState.device_view();
    const std::uint64_t nParticles =
        particles.nActiveFluid > 0u ? particles.nActiveFluid : active;
    if (nParticles == 0u || nParticles > particles.n) {
        diag.reason = "invalid resident active prefix";
        return diag;
    }

    const int threads = 256;
    const int blocks = std::max(
        1, std::min(4096, static_cast<int>((nParticles + threads - 1u) / threads)));
    q6_force_kick_0493x3<<<blocks, threads>>>(
        particles, nParticles, params.dt, params.Lx, params.Ly,
        params.bodyAccelerationX, params.bodyAccelerationY,
        tgActive ? 1 : 0, params.taylorGreenForcingAmplitude,
        params.taylorGreenForcingModeX, params.taylorGreenForcingModeY,
        static_cast<unsigned char>(ParticleRole::Fluid));
    check_cuda_0400(cudaGetLastError(), "0493x3 force kick launch");

    state.NactiveFluid = nParticles;
    cuda_shared_particle_state_0251_mark_fresh("cuda_q6_force_kick_0493x3");
    diag.handled = true;
    diag.applied = true;
    diag.particles = nParticles;
    diag.blocks = blocks;
    diag.threads = threads;
    diag.reason = "ok";
    return diag;
}

CudaQ6Resident0400Diagnostics try_apply_cuda_q6_resident_0400(ParticleState& state,
                                                              const SimulationParams& params,
                                                              const CellGrid& grid,
                                                              const FluidDomainBounds& domain,
                                                              int step,
                                                              double time,
                                                              CudaSpeciesCellWorkspace0490h* speciesWorkspace0491c,
                                                              bool fuseForceKick0493x4b) {
    (void)step;
    CudaQ6Resident0400Diagnostics diag;
    diag.requested = truthy_0400(std::getenv("MPCD_CUDA_Q6_RESIDENT_0400"));
    if (!diag.requested) {
        return diag;
    }
    const auto tTotal = Clock0400::now();
    const char* reason = "";
    diag.supported = supported_subset_0400(params, grid, domain, diag, &reason);
    diag.reason = reason;
    if (!diag.supported) {
        return diag;
    }
    diag.fusedForceKick0493x4b = fuseForceKick0493x4b;
    const bool tgForceActive0493x4b = params.taylorGreenForcingEnable &&
                                      params.taylorGreenForcingAmplitude > 0.0;
    const bool uniformForceActive0493x4b = params.bodyAccelerationX != 0.0 ||
                                           params.bodyAccelerationY != 0.0;
    if (fuseForceKick0493x4b) {
        if (params.q6ForceProjectionMode != "prestream_single_fused") {
            diag.reason = "fused force kick requires q6ForceProjectionMode=prestream_single_fused";
            return diag;
        }
        const bool zeroForceQ6Gf0493x7f =
            params.speciesQ6Enable &&
            params.speciesQ6Mode == "free_surface_masked";
        if (!tgForceActive0493x4b && !uniformForceActive0493x4b &&
            !zeroForceQ6Gf0493x7f) {
            diag.reason = "fused force kick requested with zero force outside Q6-g-f";
            return diag;
        }
        if (params.speciesQ6Enable && params.speciesQ6Mode != "common" &&
            params.speciesQ6Mode != "free_surface_masked") {
            diag.reason =
                "fused force kick requires speciesQ6Mode=common or free_surface_masked";
            return diag;
        }
    }

    const std::uint64_t active = active_fluid_count(state);
    if (active == 0u) {
        diag.reason = "no active fluid particles";
        return diag;
    }
    CudaParticleState& gpuState = cuda_shared_particle_state_0251();
    if (!cuda_shared_particle_state_0251_is_fresh()) {
        gpuState.upload_all(state);
        gpuState.set_active_fluid_size(active);
        cuda_shared_particle_state_0251_mark_fresh("cuda_q6_resident_0400_upload");
    }
    CudaParticleDeviceView particles = gpuState.device_view();
    const std::uint64_t nParticles = particles.nActiveFluid > 0u ? particles.nActiveFluid : active;
    if (nParticles == 0u || nParticles > particles.n) {
        diag.reason = "invalid resident active prefix";
        return diag;
    }

    const int threads = 256;
    const int cellBlocks = std::max(1, std::min(1024, (grid.numCells + threads - 1) / threads));
    const int particleBlocks = std::max(1, std::min(4096, static_cast<int>((nParticles + threads - 1u) / threads)));
    const int blocks = std::max(cellBlocks, particleBlocks);
    diag.blocks = blocks;
    diag.threads = threads;
    diag.particles = nParticles;
    diag.cells = static_cast<std::uint64_t>(grid.numCells);

    ResidentWorkspace0400& ws = resident_workspace_0400();
    ws.ensure(nParticles, grid.numCells, blocks,
              params.speciesQ6Enable ? static_cast<int>(params.speciesDefinitions.size()) : 1);
    CudaCellWorkspaceDeviceView cells = ws.cells.device_view();
    CudaSpeciesCellDeviceView0490h species0491c{};
    const bool speciesQ6Weighted0491c =
        params.speciesQ6Enable && params.speciesQ6Mode == "weighted" &&
        params.speciesQ6Sensitivity > 0.0;
    const bool speciesQ6FreeSurfaceMasked0493x5a =
        params.speciesQ6Enable && params.speciesQ6Mode == "free_surface_masked";
    const bool speciesQ6IndependentMasked0493w5 =
        params.speciesQ6Enable &&
        (params.speciesQ6Mode == "independent_masked" ||
         speciesQ6FreeSurfaceMasked0493x5a);
    diag.speciesQ6IndependentMasked = speciesQ6IndependentMasked0493w5;
    if (params.speciesQ6Enable) {
        if (speciesWorkspace0491c == nullptr) {
            diag.reason = "speciesQ6Enable requires a resident CUDA species workspace";
            return diag;
        }
        if (params.speciesDefinitions.empty()) {
            diag.reason = "speciesQ6Enable requires registered species definitions";
            return diag;
        }
    }
    const std::size_t scalarShared = static_cast<std::size_t>(threads) * sizeof(double);
    const std::size_t pairShared = 2u * static_cast<std::size_t>(threads) * sizeof(double);
    const int periodicX = is_x_periodic(params) ? 1 : 0;
    const int periodicY = is_y_periodic(params) ? 1 : 0;
    double xLowFlux = 0.0;
    double xHighFlux = 0.0;
    double yLowFlux = 0.0;
    double yHighFlux = 0.0;
    Q6SegmentedIo0409 segmentedIo0409 = q6_make_segmented_0409(params, time);
    if (q6_open_fullface_0404_supported(params)) {
        q6_open_fullface_flux_0404(params, time, xLowFlux, xHighFlux, yLowFlux, yHighFlux);
        diag.openBoundaryEnabled = true;
    } else if (segmentedIo0409.enabled) {
        const double xLowIntegratedFlux = q6_segmented_flux_integral_0409(segmentedIo0409, 0, params.Ly);
        const double xHighIntegratedFlux = q6_segmented_flux_integral_0409(segmentedIo0409, 1, params.Ly);
        const double yLowIntegratedFlux = q6_segmented_flux_integral_0409(segmentedIo0409, 2, params.Lx);
        const double yHighIntegratedFlux = q6_segmented_flux_integral_0409(segmentedIo0409, 3, params.Lx);
        xLowFlux = params.Ly > 0.0 ? xLowIntegratedFlux / params.Ly : 0.0;
        xHighFlux = params.Ly > 0.0 ? xHighIntegratedFlux / params.Ly : 0.0;
        yLowFlux = params.Lx > 0.0 ? yLowIntegratedFlux / params.Lx : 0.0;
        yHighFlux = params.Lx > 0.0 ? yHighIntegratedFlux / params.Lx : 0.0;
        diag.openBoundaryEnabled = true;
    }
    if (diag.openBoundaryEnabled) {
        diag.openBoundaryFluxXLow = xLowFlux;
        diag.openBoundaryFluxXHigh = xHighFlux;
        diag.openBoundaryFluxYLow = yLowFlux;
        diag.openBoundaryFluxYHigh = yHighFlux;
        diag.openBoundaryFluxBalance = (xHighFlux - xLowFlux) * params.Ly + (yHighFlux - yLowFlux) * params.Lx;
        const double area = params.Lx * params.Ly;
        diag.openBoundaryMeanDivergence = area > 0.0 ? diag.openBoundaryFluxBalance / area : 0.0;
    }

    const bool singleBlockCg0407 = cuda_q6_single_block_cg_0407_enabled(grid.numCells);
    const bool warmRequested0408 = cuda_q6_warm_start_0408_requested();
    const bool warmUsable0408 = warmRequested0408 && singleBlockCg0407 && ws.warmPhiValid &&
                                ws.warmNx == grid.Nx && ws.warmNy == grid.Ny &&
                                ws.warmPeriodicX == periodicX && ws.warmPeriodicY == periodicY;
    const int resetPhi0408 = warmUsable0408 ? 0 : 1;

    check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)), "counter zero");
    const auto tDeposit = Clock0400::now();
    q6_zero_cells_0400<<<cellBlocks, threads>>>(cells, ws.rhs.data(), ws.phi.data(), ws.r.data(),
                                                ws.p.data(), ws.Ap.data(), ws.dux.data(), ws.duy.data(),
                                                resetPhi0408);
    check_cuda_0400(cudaGetLastError(), "zero cells launch");
    q6_zero_particle_cell_ids_0400<<<particleBlocks, threads>>>(cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "zero particle cell ids launch");
    if (fuseForceKick0493x4b) {
        q6_deposit_tentative_force_0493x4b<<<particleBlocks, threads>>>(
            particles, cells, nParticles, grid.Nx, grid.Ny, params.Lx, params.Ly,
            periodicX, periodicY, params.dt, params.bodyAccelerationX,
            params.bodyAccelerationY, tgForceActive0493x4b ? 1 : 0,
            params.taylorGreenForcingAmplitude, params.taylorGreenForcingModeX,
            params.taylorGreenForcingModeY);
        check_cuda_0400(cudaGetLastError(), "0493x4b fused tentative force deposit launch");
    } else {
        q6_deposit_periodic_0400<<<particleBlocks, threads>>>(
            particles, cells, nParticles, grid.Nx, grid.Ny, params.Lx, params.Ly,
            periodicX, periodicY);
        check_cuda_0400(cudaGetLastError(), "deposit launch");
    }
    q6_finalize_cells_0400<<<cellBlocks, threads>>>(cells, ws.counter.data());
    check_cuda_0400(cudaGetLastError(), "finalize cells launch");
    if (params.speciesQ6Enable) {
        const auto tSpeciesDeposit0491h = Clock0400::now();
        CudaSpeciesCellDepositDiagnostics0490h speciesDiag0491c{};
        speciesWorkspace0491c->ensure_capacity(
            grid.numCells,
            static_cast<int>(params.speciesDefinitions.size()),
            &speciesDiag0491c);
        diag.speciesQ6AllocatedBytes = speciesDiag0491c.allocatedBytes;
        diag.speciesQ6AllocationCalls = speciesDiag0491c.allocationCalls;
        species0491c = speciesWorkspace0491c->device_view();
        std::vector<std::uint32_t> hSpeciesTypes0491c(params.speciesDefinitions.size());
        std::vector<double> hQ6Strength0491c(params.speciesDefinitions.size());
        std::vector<double> hReferenceCellMass0493w5(params.speciesDefinitions.size());
        std::vector<unsigned char> hPhaseFamily0493x6a(params.speciesDefinitions.size());
        for (std::size_t s = 0; s < params.speciesDefinitions.size(); ++s) {
            hSpeciesTypes0491c[s] = params.speciesDefinitions[s].type;
            hQ6Strength0491c[s] = params.speciesDefinitions[s].q6StrengthDeclared;
            hReferenceCellMass0493w5[s] =
                params.speciesDefinitions[s].referenceCellMassDeclared;
            hPhaseFamily0493x6a[s] = static_cast<unsigned char>(
                params.speciesDefinitions[s].phaseFamily);
        }
        diag.speciesQ6MetadataH2DBytes =
            hSpeciesTypes0491c.size() * sizeof(std::uint32_t) +
            hQ6Strength0491c.size() * sizeof(double) +
            hReferenceCellMass0493w5.size() * sizeof(double) +
            hPhaseFamily0493x6a.size() * sizeof(unsigned char);
        check_cuda_0400(cudaMemcpy(species0491c.speciesTypes, hSpeciesTypes0491c.data(),
                                   hSpeciesTypes0491c.size() * sizeof(std::uint32_t),
                                   cudaMemcpyHostToDevice),
                        "species q6 type metadata upload");
        check_cuda_0400(cudaMemcpy(species0491c.q6Strength, hQ6Strength0491c.data(),
                                   hQ6Strength0491c.size() * sizeof(double),
                                   cudaMemcpyHostToDevice),
                        "species q6 strength metadata upload");
        check_cuda_0400(cudaMemcpy(species0491c.referenceCellMass,
                                   hReferenceCellMass0493w5.data(),
                                   hReferenceCellMass0493w5.size() * sizeof(double),
                                   cudaMemcpyHostToDevice),
                        "species q6 reference cell mass metadata upload");
        check_cuda_0400(cudaMemcpy(species0491c.phaseFamily,
                                   hPhaseFamily0493x6a.data(),
                                   hPhaseFamily0493x6a.size() * sizeof(unsigned char),
                                   cudaMemcpyHostToDevice),
                        "0493x6a species phase-family metadata upload");
        const int denseSpecies0491c =
            grid.numCells * static_cast<int>(params.speciesDefinitions.size());
        const int speciesResetBlocks0491c =
            std::max(1, std::min(1024, (std::max(grid.numCells, denseSpecies0491c) + threads - 1) / threads));
        q6_reset_species_mass_0491c<<<speciesResetBlocks0491c, threads>>>(species0491c);
        check_cuda_0400(cudaGetLastError(), "species q6 mass reset launch");
        if (fuseForceKick0493x4b) {
            q6_deposit_species_tentative_force_from_cell_ids_0493x4b<<<particleBlocks, threads>>>(
                particles, cells, species0491c, nParticles, params.dt, params.Lx,
                params.Ly, params.bodyAccelerationX, params.bodyAccelerationY,
                tgForceActive0493x4b ? 1 : 0, params.taylorGreenForcingAmplitude,
                params.taylorGreenForcingModeX, params.taylorGreenForcingModeY);
            check_cuda_0400(cudaGetLastError(),
                            "0493x4b fused species tentative force deposit launch");
        } else {
            q6_deposit_species_mass_from_cell_ids_0491c<<<particleBlocks, threads>>>(
                particles, cells, species0491c, nParticles);
            check_cuda_0400(cudaGetLastError(), "species q6 mass deposit launch");
        }
        q6_finalize_species_occupancy_0493w5<<<cellBlocks, threads>>>(species0491c);
        check_cuda_0400(cudaGetLastError(), "species q6 occupancy finalize launch");
        unsigned long long invalidSpecies0491c = 0ull;
        check_cuda_0400(cudaMemcpy(&invalidSpecies0491c, species0491c.invalidTypeCounter,
                                   sizeof(invalidSpecies0491c), cudaMemcpyDeviceToHost),
                        "species q6 invalid type counter download");
        if (invalidSpecies0491c != 0ull) {
            diag.reason = "speciesQ6Enable encountered unregistered fluid particle types";
            return diag;
        }
        diag.speciesQ6DepositSeconds = seconds_since_0400(tSpeciesDeposit0491h);
    }
    check_cuda_0400(cudaMemcpy(&diag.emptyCells, ws.counter.data(), sizeof(unsigned long long),
                               cudaMemcpyDeviceToHost),
                    "copy empty counter");
    diag.depositSeconds = seconds_since_0400(tDeposit);

    const std::size_t tripleShared = 3u * static_cast<std::size_t>(threads) * sizeof(double);
    if (speciesQ6IndependentMasked0493w5) {
        ws.warmPhiValid = false;
        const bool ok0493w5 = apply_independent_masked_species_q6_0493w5(
            particles, cells, species0491c, ws, params, grid, step, time,
            nParticles, threads, cellBlocks, particleBlocks,
            scalarShared, pairShared, tripleShared, periodicX, periodicY,
            xLowFlux, xHighFlux, yLowFlux, yHighFlux, segmentedIo0409,
            speciesQ6FreeSurfaceMasked0493x5a, fuseForceKick0493x4b, diag);
        if (!ok0493w5) {
            return diag;
        }
        cuda_shared_particle_state_0251_mark_fresh(
            speciesQ6FreeSurfaceMasked0493x5a
                ? "cuda_q6_resident_0400_free_surface_masked_0493x5a"
                : "cuda_q6_resident_0400_independent_masked_0493w5");
        diag.applied = true;
        diag.handled = true;
        diag.reason = speciesQ6FreeSurfaceMasked0493x5a
            ? "ok_free_surface_masked_0493x5a" : "ok";
        diag.totalSeconds = seconds_since_0400(tTotal);
        if (!speciesQ6FreeSurfaceMasked0493x5a ||
            q6_g_f_diagnostics_this_step_0493x7k(params, step)) {
            append_species_q6_resident_audit_0491e(
                params, step, time, static_cast<int>(params.speciesDefinitions.size()), diag);
        }
        return diag;
    }

    const auto tSolve = Clock0400::now();
    const double dx = grid.dx;
    const double dy = grid.dy;
    q6_build_rhs_and_stats_0400<<<cellBlocks, threads, tripleShared>>>(
        cells, ws.rhs.data(), ws.partial0.data(), ws.partial1.data(), ws.partial2.data(), grid.Nx, grid.Ny, dx, dy,
        periodicX, periodicY, xLowFlux, xHighFlux, yLowFlux, yHighFlux, segmentedIo0409);
    check_cuda_0400(cudaGetLastError(), "build rhs launch");
    const double rhsSum = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
    const double divSq = reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
    diag.divBeforeMaxAbs = reduce_host_max_0400(ws.partial2.data(), cellBlocks);
    diag.divBeforeRms = std::sqrt(divSq / static_cast<double>(grid.numCells));
    const double rhsMean = rhsSum / static_cast<double>(grid.numCells);
    const double tol = std::max(0.0, params.projectionTolerance);
    const double invDx2 = 1.0 / (dx * dx);
    const double invDy2 = 1.0 / (dy * dy);

    if (singleBlockCg0407) {
        constexpr int cgThreads0407 = 256;
        const std::size_t cgShared0407 = 2u * static_cast<std::size_t>(cgThreads0407) * sizeof(double);
        q6_cg_single_block_0407<<<1, cgThreads0407, cgShared0407>>>(
            ws.rhs.data(), ws.phi.data(), ws.r.data(), ws.p.data(), ws.Ap.data(),
            ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),
            grid.Nx, grid.Ny, grid.numCells, params.projectionMaxIterations, tol, rhsMean,
            invDx2, invDy2, periodicX, periodicY, warmUsable0408 ? 1 : 0);
        check_cuda_0400(cudaGetLastError(), "single-block cg launch");
        double cgIterations = 0.0;
        double cgResidualRel = 0.0;
        double cgStatus = 0.0;
        check_cuda_0400(cudaMemcpy(&cgIterations, ws.partial0.data(), sizeof(double), cudaMemcpyDeviceToHost),
                        "copy single-block cg iterations");
        check_cuda_0400(cudaMemcpy(&cgResidualRel, ws.partial1.data(), sizeof(double), cudaMemcpyDeviceToHost),
                        "copy single-block cg residual");
        check_cuda_0400(cudaMemcpy(&cgStatus, ws.partial2.data(), sizeof(double), cudaMemcpyDeviceToHost),
                        "copy single-block cg status");
        diag.iterations = static_cast<int>(std::llround(cgIterations));
        diag.residualRel = cgResidualRel;
        diag.converged = cgStatus > 0.5;
        if (cgStatus < -0.5) {
            diag.reason = "non-positive CG pAp";
        }
    } else {
    q6_init_cg_0400<<<cellBlocks, threads>>>(ws.rhs.data(), ws.phi.data(), ws.r.data(), ws.p.data(),
                                             rhsMean, grid.numCells);
    check_cuda_0400(cudaGetLastError(), "init cg launch");
    q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(ws.r.data(), ws.partial0.data(),
                                                                     grid.numCells);
    check_cuda_0400(cudaGetLastError(), "initial rr launch");
    double rr = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
    const double rhsNorm = std::sqrt(std::max(0.0, rr));
    const double rhsNormSafe = std::max(rhsNorm, 1.0e-300);
    const double tol = std::max(0.0, params.projectionTolerance);
    const double invDx2 = 1.0 / (dx * dx);
    const double invDy2 = 1.0 / (dy * dy);

    diag.converged = rhsNorm <= tol;
    for (int it = 0; it < params.projectionMaxIterations && !diag.converged; ++it) {
        q6_apply_operator_and_dot_0400<<<cellBlocks, threads, scalarShared>>>(
            ws.p.data(), ws.Ap.data(), ws.partial0.data(), grid.Nx, grid.Ny, invDx2, invDy2,
            periodicX, periodicY);
        check_cuda_0400(cudaGetLastError(), "apply operator launch");
        const double pAp = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        if (!(pAp > 0.0) || !std::isfinite(pAp)) {
            diag.reason = "non-positive CG pAp";
            break;
        }
        const double alpha = rr / pAp;
        q6_axpy_residual_0400<<<cellBlocks, threads>>>(ws.phi.data(), ws.r.data(), ws.p.data(),
                                                       ws.Ap.data(), alpha, grid.numCells);
        check_cuda_0400(cudaGetLastError(), "axpy residual launch");
        q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(ws.r.data(), ws.partial0.data(),
                                                                         grid.numCells);
        check_cuda_0400(cudaGetLastError(), "rr update launch");
        double rrNew = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        diag.iterations = it + 1;
        diag.residualRel = std::sqrt(std::max(0.0, rrNew)) / rhsNormSafe;
        if (diag.residualRel <= tol) {
            rr = rrNew;
            diag.converged = true;
            break;
        }
        if ((it + 1) % 25 == 0) {
            q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(ws.phi.data(), ws.partial0.data(),
                                                                      grid.numCells);
            q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(ws.r.data(), ws.partial1.data(),
                                                                      grid.numCells);
            check_cuda_0400(cudaGetLastError(), "mean reduction launch");
            const double phiMean = reduce_host_sum_0400(ws.partial0.data(), cellBlocks) /
                                   static_cast<double>(grid.numCells);
            const double rMean = reduce_host_sum_0400(ws.partial1.data(), cellBlocks) /
                                 static_cast<double>(grid.numCells);
            q6_subtract_mean_pair_0400<<<cellBlocks, threads>>>(ws.phi.data(), ws.r.data(),
                                                                phiMean, rMean, grid.numCells);
            check_cuda_0400(cudaGetLastError(), "mean subtract launch");
            q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(ws.r.data(), ws.partial0.data(),
                                                                             grid.numCells);
            check_cuda_0400(cudaGetLastError(), "rr after mean launch");
            rrNew = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        }
        const double beta = rrNew / std::max(rr, 1.0e-300);
        q6_update_p_0400<<<cellBlocks, threads>>>(ws.p.data(), ws.r.data(), beta, grid.numCells);
        check_cuda_0400(cudaGetLastError(), "update p launch");
        rr = rrNew;
    }
    }
    if (warmRequested0408 && singleBlockCg0407 && diag.converged) {
        ws.warmPhiValid = true;
        ws.warmNx = grid.Nx;
        ws.warmNy = grid.Ny;
        ws.warmPeriodicX = periodicX;
        ws.warmPeriodicY = periodicY;
    } else {
        ws.warmPhiValid = false;
    }
    diag.solveSeconds = seconds_since_0400(tSolve);
    if (!diag.converged && params.projectionMaxIterations <= 0) {
        diag.reason = "zero CG iterations";
    }

    const auto tApply = Clock0400::now();
    // 0493x7p reuses the post-CG r/p work arrays as transient east/north
    // face-correction storage.  No additional O(Ncell) allocation is needed:
    // warm-start state lives in phi, while r/p are dead once the solve ends.
    q6_compute_face_corrections_0493x7p<<<cellBlocks, threads>>>(
        cells, ws.phi.data(), ws.r.data(), ws.p.data(), grid.Nx, grid.Ny, dx, dy,
        params.q6ProjectionStrength, periodicX, periodicY, xHighFlux, yHighFlux,
        segmentedIo0409);
    check_cuda_0400(cudaGetLastError(), "0493x7p compute face correction launch");

    q6_projected_divergence_stats_0400<<<cellBlocks, threads, pairShared>>>(
        cells, ws.r.data(), ws.p.data(), ws.partial0.data(), ws.partial1.data(),
        grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
        xLowFlux, xHighFlux, yLowFlux, yHighFlux, segmentedIo0409);
    check_cuda_0400(cudaGetLastError(), "0493x7p projected face divergence stats launch");
    const double divAfterSq = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
    diag.divAfterProjectedFluxMaxAbs = reduce_host_max_0400(ws.partial1.data(), cellBlocks);
    diag.divAfterProjectedFluxRms = std::sqrt(divAfterSq / static_cast<double>(grid.numCells));

    q6_reconstruct_cell_corrections_0493x7p<<<cellBlocks, threads, pairShared>>>(
        cells, ws.r.data(), ws.p.data(), ws.dux.data(), ws.duy.data(),
        ws.partial0.data(), ws.partial1.data(), grid.Nx, grid.Ny,
        params.q6ProjectionStrength, periodicX, periodicY, xLowFlux, yLowFlux,
        segmentedIo0409);
    check_cuda_0400(cudaGetLastError(), "0493x7p reconstruct cell correction launch");
    const double corrSq = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
    diag.correctionVelocityMaxAbs = reduce_host_max_0400(ws.partial1.data(), cellBlocks);
    diag.correctionVelocityRms = std::sqrt(corrSq / static_cast<double>(grid.numCells));

    // The common path historically reported one post-projection divergence for
    // both fields.  Keep that diagnostic ABI: the strict FV constraint remains
    // the face-flux residual, while ws.dux/ws.duy now correctly denote the
    // cell-centred correction that is actually applied to particles.
    diag.divAfterCellVelocityRms = diag.divAfterProjectedFluxRms;
    diag.divAfterCellVelocityMaxAbs = diag.divAfterProjectedFluxMaxAbs;

    q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(cells.cellMass, ws.partial0.data(),
                                                              grid.numCells);
    check_cuda_0400(cudaGetLastError(), "total mass reduction launch");
    const double totalMass = std::max(1.0e-300, reduce_host_sum_0400(ws.partial0.data(), cellBlocks));

    if (params.speciesQ6Enable) {
        const auto tSpeciesWeight0491h = Clock0400::now();
        check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                        "species q6 fallback counter zero");
        if (speciesQ6Weighted0491c && params.speciesQ6FallbackMode == "fatal") {
            q6_count_zero_alpha_bar_0491c<<<cellBlocks, threads>>>(
                species0491c, params.speciesQ6AlphaEpsilon, ws.counter.data());
            check_cuda_0400(cudaGetLastError(), "species q6 alphaBar validation launch");
            unsigned long long fallbackCount0491c = 0ull;
            check_cuda_0400(cudaMemcpy(&fallbackCount0491c, ws.counter.data(),
                                       sizeof(fallbackCount0491c), cudaMemcpyDeviceToHost),
                            "species q6 alphaBar validation counter download");
            if (fallbackCount0491c != 0ull) {
                diag.reason = "speciesQ6 fallback=fatal encountered cells with zero alphaBar";
                return diag;
            }
            check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                            "species q6 fallback counter reset after validation");
        }
        q6_species_barycentric_residual_stats_0491c<<<cellBlocks, threads, pairShared>>>(
            species0491c, ws.dux.data(), ws.duy.data(),
            params.speciesQ6Sensitivity, params.speciesQ6AlphaEpsilon,
            speciesQ6Weighted0491c ? 1 : 0,
            ws.partial0.data(), ws.partial1.data());
        check_cuda_0400(cudaGetLastError(), "species q6 barycentric residual launch");
        diag.speciesQ6BarycentricResidualMaxAbs =
            reduce_host_max_0400(ws.partial0.data(), cellBlocks);
        diag.speciesQ6BarycentricResidualMaxScaled =
            reduce_host_max_0400(ws.partial1.data(), cellBlocks);
        if (diag.speciesQ6BarycentricResidualMaxScaled > params.speciesQ6ComparisonTolerance) {
            diag.reason = "speciesQ6 barycentric recomposition scaled residual exceeded tolerance";
            return diag;
        }
        diag.speciesQ6WeightSeconds = seconds_since_0400(tSpeciesWeight0491h);
        const auto tSpeciesApply0491h = Clock0400::now();
        if (fuseForceKick0493x4b) {
            q6_apply_species_force_and_particle_correction_0493x4b<<<particleBlocks, threads, pairShared>>>(
                particles, cells, species0491c, ws.dux.data(), ws.duy.data(), nParticles,
                params.speciesQ6Sensitivity, params.speciesQ6AlphaEpsilon,
                speciesQ6Weighted0491c ? 1 : 0,
                params.speciesQ6FallbackMode == "fatal" ? 1 : 0,
                params.dt, params.Lx, params.Ly, params.bodyAccelerationX,
                params.bodyAccelerationY, tgForceActive0493x4b ? 1 : 0,
                params.taylorGreenForcingAmplitude, params.taylorGreenForcingModeX,
                params.taylorGreenForcingModeY, ws.partial0.data(), ws.partial1.data(),
                ws.counter.data());
            check_cuda_0400(cudaGetLastError(),
                            "0493x4b fused species force and Q6 apply launch");
        } else {
            q6_apply_species_particle_correction_0491c<<<particleBlocks, threads, pairShared>>>(
                particles, cells, species0491c, ws.dux.data(), ws.duy.data(), nParticles,
                params.speciesQ6Sensitivity, params.speciesQ6AlphaEpsilon,
                speciesQ6Weighted0491c ? 1 : 0,
                params.speciesQ6FallbackMode == "fatal" ? 1 : 0,
                ws.partial0.data(), ws.partial1.data(), ws.counter.data());
            check_cuda_0400(cudaGetLastError(), "apply species q6 particle correction launch");
        }
        unsigned long long fallbackCount0491c = 0ull;
        check_cuda_0400(cudaMemcpy(&fallbackCount0491c, ws.counter.data(),
                                   sizeof(fallbackCount0491c), cudaMemcpyDeviceToHost),
                        "species q6 fallback counter download");
        if (fallbackCount0491c != 0ull) {
            diag.reason = "speciesQ6 fallback=fatal encountered cells with zero alphaBar";
            return diag;
        }
        diag.speciesQ6ParticleApplySeconds = seconds_since_0400(tSpeciesApply0491h);
    } else {
        if (fuseForceKick0493x4b) {
            q6_apply_force_and_particle_correction_0493x4b<<<particleBlocks, threads, pairShared>>>(
                particles, cells, ws.dux.data(), ws.duy.data(), nParticles,
                params.dt, params.Lx, params.Ly, params.bodyAccelerationX,
                params.bodyAccelerationY, tgForceActive0493x4b ? 1 : 0,
                params.taylorGreenForcingAmplitude, params.taylorGreenForcingModeX,
                params.taylorGreenForcingModeY, ws.partial0.data(), ws.partial1.data());
            check_cuda_0400(cudaGetLastError(),
                            "0493x4b fused force and Q6 apply launch");
        } else {
            q6_apply_particle_correction_0400<<<particleBlocks, threads, pairShared>>>(
                particles, cells, ws.dux.data(), ws.duy.data(), nParticles,
                ws.partial0.data(), ws.partial1.data());
            check_cuda_0400(cudaGetLastError(), "apply particle correction launch");
        }
    }
    const double dpx = reduce_host_sum_0400(ws.partial0.data(), particleBlocks);
    const double dpy = reduce_host_sum_0400(ws.partial1.data(), particleBlocks);
    diag.momentumResidualBeforeCorrection = std::sqrt(dpx * dpx + dpy * dpy);
    if (params.projectionMomentumCorrectionEnable) {
        diag.momentumCorrectionVx = dpx / totalMass;
        diag.momentumCorrectionVy = dpy / totalMass;
        q6_apply_uniform_momentum_correction_0400<<<particleBlocks, threads>>>(
            particles, nParticles, diag.momentumCorrectionVx, diag.momentumCorrectionVy);
        check_cuda_0400(cudaGetLastError(), "uniform momentum correction launch");
    }
    q6_update_corrected_cell_means_0400<<<cellBlocks, threads>>>(
        cells, ws.dux.data(), ws.duy.data(), diag.momentumCorrectionVx, diag.momentumCorrectionVy);
    check_cuda_0400(cudaGetLastError(), "update corrected cell means launch");
    diag.applySeconds = seconds_since_0400(tApply);

    cuda_shared_particle_state_0251_mark_fresh(
        fuseForceKick0493x4b ? "cuda_q6_resident_0400_fused_force_0493x4b"
                             : "cuda_q6_resident_0400");
    diag.applied = true;
    diag.handled = true;
    diag.reason = fuseForceKick0493x4b ? "ok_fused_force_0493x4b" : "ok";
    diag.totalSeconds = seconds_since_0400(tTotal);
    append_species_q6_resident_audit_0491e(
        params, step, time, static_cast<int>(params.speciesDefinitions.size()), diag);
    return diag;
}


CudaQ6ResidentThermostat0400Diagnostics try_apply_cuda_q6_resident_thermostat_0400(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const std::vector<int>& collisionCellId,
    std::uint64_t step) {
    CudaQ6ResidentThermostat0400Diagnostics diag;
    diag.requested = truthy_0400(std::getenv("MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400"));
    if (!diag.requested) {
        return diag;
    }
    const auto tTotal = Clock0400::now();
    if (!params.thermostatEnable) {
        diag.reason = "thermostat disabled";
        return diag;
    }
    if (params.thermostatEvery <= 0 ||
        (step % static_cast<std::uint64_t>(params.thermostatEvery)) != 0u) {
        diag.reason = "thermostat not due";
        return diag;
    }
    if (params.thermostatMode != "cell_relative_rescale") {
        diag.reason = "unsupported thermostat mode";
        return diag;
    }
    const double targetKBT = params.thermostatTargetKBT > 0.0 ? params.thermostatTargetKBT : params.kBT;
    if (!(targetKBT > 0.0)) {
        diag.reason = "invalid thermostat target";
        return diag;
    }
    if (!cuda_shared_particle_state_0251_is_fresh()) {
        diag.reason = "shared CUDA particle state is not fresh";
        return diag;
    }

    CudaParticleState& gpuState = cuda_shared_particle_state_0251();
    CudaParticleDeviceView particles = gpuState.device_view();
    const std::uint64_t nParticles = particles.nActiveFluid > 0u ? particles.nActiveFluid : active_fluid_count(state);
    if (nParticles == 0u || grid.numCells <= 0) {
        diag.reason = "empty particle/grid state";
        return diag;
    }
    ResidentWorkspace0400& ws = resident_workspace_0400();
    CudaCellWorkspaceDeviceView cells = ws.cells.device_view();
    if (cells.numCells != grid.numCells || cells.cellId == nullptr || cells.count == nullptr ||
        cells.cellUx == nullptr || cells.cellUy == nullptr || cells.cellKinetic == nullptr ||
        cells.cellScale == nullptr || cells.fluidCounter == nullptr) {
        diag.reason = "resident Q6 cell workspace unavailable";
        return diag;
    }

    const int threads = 256;
    const int cellBlocks = std::max(1, std::min(1024, (grid.numCells + threads - 1) / threads));
    const int particleBlocks = std::max(1, std::min(4096, static_cast<int>((nParticles + threads - 1u) / threads)));
    const std::size_t pairShared = 2u * static_cast<std::size_t>(threads) * sizeof(double);

    diag.supported = true;
    std::uint64_t cellIdH2DEntries0491f = 0u;
    if (collisionCellId.size() == static_cast<std::size_t>(nParticles)) {
        check_cuda_0400(cudaMemcpy(cells.cellId, collisionCellId.data(),
                                   static_cast<std::size_t>(nParticles) * sizeof(int),
                                   cudaMemcpyHostToDevice),
                        "thermostat collision cellId upload");
        cellIdH2DEntries0491f = nParticles;
    }
    q6_zero_cells_0400<<<cellBlocks, threads>>>(cells, ws.rhs.data(), ws.phi.data(), ws.r.data(),
                                                ws.p.data(), ws.Ap.data(), ws.dux.data(), ws.duy.data(),
                                                0);
    check_cuda_0400(cudaGetLastError(), "thermostat zero cell moments launch");
    check_cuda_0400(cudaMemset(cells.cellKinetic, 0, static_cast<std::size_t>(grid.numCells) * sizeof(double)),
                    "thermostat kinetic zero");
    check_cuda_0400(cudaMemset(cells.cellScale, 0, static_cast<std::size_t>(grid.numCells) * sizeof(double)),
                    "thermostat scale zero");
    check_cuda_0400(cudaMemset(cells.fluidCounter, 0, sizeof(unsigned long long)),
                    "thermostat fluid counter zero");
    check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                    "thermostat empty counter zero");

    auto t0 = Clock0400::now();
    q6_thermostat_deposit_moments_from_cell_ids_0400<<<particleBlocks, threads>>>(particles, cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "thermostat moment deposit launch");
    q6_finalize_cells_0400<<<cellBlocks, threads>>>(cells, ws.counter.data());
    check_cuda_0400(cudaGetLastError(), "thermostat finalize moments launch");
    q6_thermostat_kinetic_0400<<<particleBlocks, threads>>>(particles, cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "thermostat kinetic launch");
    diag.kineticSeconds = seconds_since_0400(t0);

    // 0493x7l: the resident thermostat is a physical CUDA stage every time it is
    // due, but its 0491f telemetry is not.  On Q6-g-f production steps, keep
    // deposit/kinetic/scale/apply unchanged and collect the expensive host-side
    // thermostat audit only at the same first-step/summary cadence as x7k.
    const bool q6GfThermostat0493x7l =
        params.speciesQ6Enable && params.speciesQ6Mode == "free_surface_masked";
    const bool collectThermostatDiagnostics0493x7l =
        !q6GfThermostat0493x7l ||
        q6_g_f_diagnostics_this_step_0493x7k(params, step);

    t0 = Clock0400::now();
    const int minParticles = std::max(1, params.thermostatMinParticles);
    const double epsilon = std::max(0.0, params.thermostatEpsilon);
    q6_thermostat_scale_0400<<<cellBlocks, threads, pairShared>>>(
        cells, targetKBT, minParticles, epsilon, ws.partial0.data(), ws.partial1.data());
    check_cuda_0400(cudaGetLastError(), "thermostat scale launch");
    double totalKBefore0493x7l = 0.0;
    double targetKTotal0493x7l = 0.0;
    if (collectThermostatDiagnostics0493x7l) {
        totalKBefore0493x7l = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        targetKTotal0493x7l = reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
    }
    diag.scaleSeconds = seconds_since_0400(t0);

    t0 = Clock0400::now();
    q6_thermostat_apply_0400<<<particleBlocks, threads>>>(particles, cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "thermostat apply launch");
    diag.applySeconds = seconds_since_0400(t0);

    if (collectThermostatDiagnostics0493x7l) {
        t0 = Clock0400::now();
        std::vector<std::uint32_t> hostCount(static_cast<std::size_t>(grid.numCells), 0u);
        std::vector<double> hostKinetic(static_cast<std::size_t>(grid.numCells), 0.0);
        std::vector<double> hostScale(static_cast<std::size_t>(grid.numCells), 1.0);
        unsigned long long fluidCounter = 0ull;
        check_cuda_0400(cudaMemcpy(hostCount.data(), cells.count,
                                   static_cast<std::size_t>(grid.numCells) * sizeof(std::uint32_t),
                                   cudaMemcpyDeviceToHost),
                        "thermostat count download");
        check_cuda_0400(cudaMemcpy(hostKinetic.data(), cells.cellKinetic,
                                   static_cast<std::size_t>(grid.numCells) * sizeof(double),
                                   cudaMemcpyDeviceToHost),
                        "thermostat kinetic download");
        check_cuda_0400(cudaMemcpy(hostScale.data(), cells.cellScale,
                                   static_cast<std::size_t>(grid.numCells) * sizeof(double),
                                   cudaMemcpyDeviceToHost),
                        "thermostat scale download");
        check_cuda_0400(cudaMemcpy(&fluidCounter, cells.fluidCounter, sizeof(unsigned long long),
                                   cudaMemcpyDeviceToHost),
                        "thermostat fluid counter download");
        diag.diagnosticsDownloadSeconds = seconds_since_0400(t0);

        double scaleSum = 0.0;
        double scaleMin = std::numeric_limits<double>::infinity();
        double scaleMax = 0.0;
        std::uint64_t dofTotal = 0u;
        std::uint64_t cellsRescaled = 0u;
        std::uint64_t particlesRescaled = 0u;
        for (int c = 0; c < grid.numCells; ++c) {
            const std::uint32_t count = hostCount[static_cast<std::size_t>(c)];
            const double K = hostKinetic[static_cast<std::size_t>(c)];
            const double scale = hostScale[static_cast<std::size_t>(c)];
            if (count < static_cast<std::uint32_t>(minParticles) || !(K > epsilon)) {
                continue;
            }
            cellsRescaled += 1u;
            particlesRescaled += static_cast<std::uint64_t>(count);
            dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
            scaleSum += scale;
            scaleMin = std::min(scaleMin, scale);
            scaleMax = std::max(scaleMax, scale);
        }
        diag.thermostat.applied = cellsRescaled > 0u;
        diag.thermostat.cellsRescaled = cellsRescaled;
        diag.thermostat.particlesRescaled = particlesRescaled;
        diag.thermostat.kBTBefore =
            dofTotal > 0u ? (2.0 * totalKBefore0493x7l / static_cast<double>(dofTotal)) : 0.0;
        diag.thermostat.kBTAfter =
            dofTotal > 0u ? (2.0 * targetKTotal0493x7l / static_cast<double>(dofTotal)) : 0.0;
        diag.thermostat.scaleMean =
            cellsRescaled > 0u ? scaleSum / static_cast<double>(cellsRescaled) : 1.0;
        diag.thermostat.scaleMin = cellsRescaled > 0u ? scaleMin : 1.0;
        diag.thermostat.scaleMax = cellsRescaled > 0u ? scaleMax : 1.0;
        (void)fluidCounter;
    }

    state.NactiveFluid = nParticles;
    cuda_shared_particle_state_0251_mark_fresh("cuda_q6_resident_thermostat_0400");
    diag.handled = true;
    diag.reason = "ok";
    diag.totalSeconds = seconds_since_0400(tTotal);
    if (collectThermostatDiagnostics0493x7l) {
        append_q6_resident_thermostat_audit_0491f(
            params, step, targetKBT, cellIdH2DEntries0491f, diag);
    }
    return diag;
}

} // namespace mpcd

#endif

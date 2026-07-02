#include "boundary_base.h"
#include "cell_grid.h"
#include "filtered_field_recorder_0432.h"
#include "params_io_base.h"
#include "runtime_summary.h"
#include "cuda_shared_particle_state_0251.h"
#include "cuda_live_field_0337.h"
#include "fluid_domain.h"
#include "immersed_solid.h"
#include "live_visualization_0335.h"
#include "src_mpcd_base.h"
#include "state_smpcd_io.h"
#include "weighted_resampling.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace {

bool env_truthy_0260(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0337(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try { return std::stoi(v); } catch (...) { return fallback; }
}

double env_double_0337(const char* name, double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try { return std::stod(v); } catch (...) { return fallback; }
}

std::string env_string_0337(const char* name, const std::string& fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    return std::string(v);
}

void sync_cuda_resident_state_for_host_0260(mpcd::ParticleState& state) {
    if (env_truthy_0260("MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260") ||
        env_truthy_0260("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261") ||
        env_truthy_0260("MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262") ||
        env_truthy_0260("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263") ||
        env_truthy_0260("MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264")) {
        (void)mpcd::cuda_shared_particle_state_0251_download_if_fresh(state);
    }
}



bool disabled_resampling_summary_diagnostics_enabled_0315g(const mpcd::SimulationParams& params) {
    // 0315g: when resampling is disabled, the historical runtime-summary
    // resampling diagnostics rebuild a particle pool and redeposit the whole
    // fluid on summary steps.  In resident CUDA runs this forces an active
    // host mirror and becomes a performance consumer unrelated to the physical
    // SRC classic step.  Keep the old behaviour only on explicit request, and
    // always keep full diagnostics when resampling itself is enabled.
    if (params.resamplingEnable) {
        return true;
    }
    return env_truthy_0260("MPCD_DISABLED_RESAMPLING_SUMMARY_DIAGNOSTICS_0315G") ||
           env_truthy_0260("MPCD_RESAMPLING_DISABLED_DIAGNOSTICS_LEGACY_0315G");
}

bool role_filter_fluid_0314(const std::string& filter) {
    return filter == "fluid";
}

void write_state_dump_0314(const std::string& filepath,
                           mpcd::ParticleState& hostState,
                           const mpcd::SimulationParams& params) {
    if (role_filter_fluid_0314(params.dumpRoleFilter)) {
        mpcd::ParticleState compact;
        mpcd::ParticleRoleCounts counts{};
        if (mpcd::cuda_shared_particle_state_0251_download_role_filtered_if_fresh(
                compact, mpcd::kParticleRoleFluid, &counts)) {
            mpcd::write_smpcd_state(filepath, compact);
            return;
        }
        mpcd::write_smpcd_state_role_filtered(filepath, hostState, mpcd::kParticleRoleFluid);
        return;
    }

    sync_cuda_resident_state_for_host_0260(hostState);
    mpcd::write_smpcd_state(filepath, hostState);
}


std::string state_dump_name(const std::string& outputDir, int step) {
    std::ostringstream oss;
    oss << outputDir << "/state_step_" << std::setw(8) << std::setfill('0') << step << ".smpcd";
    return oss.str();
}

double elapsed_seconds(std::chrono::steady_clock::time_point t0) {
    const auto now = std::chrono::steady_clock::now();
    return std::chrono::duration<double>(now - t0).count();
}

int openmp_max_threads() {
#ifdef _OPENMP
    return omp_get_max_threads();
#else
    return 1;
#endif
}


bool internal_profiles_enabled_0176() {
    static const bool enabled = []() {
        const char* v = std::getenv("MPCD_INTERNAL_PROFILES");
        if (v == nullptr || *v == '\0') {
            return false;
        }
        const std::string s(v);
        return !(s == "0" || s == "false" || s == "FALSE" ||
                 s == "off" || s == "OFF" || s == "no" || s == "NO");
    }();
    return enabled;
}



void write_phase_profile_0163(const std::string& outputDir,
                              const std::array<double, mpcd::StepProfilePhaseCount>& profileSeconds,
                              const int measuredSteps) {
    const std::filesystem::path path = std::filesystem::path(outputDir) / "phase_profile_0163.csv";
    std::ofstream out(path);
    out << "phase,total_s,ms_per_step,percent_total\n";
    double total = 0.0;
    for (double v : profileSeconds) {
        total += v;
    }
    const double steps = measuredSteps > 0 ? static_cast<double>(measuredSteps) : 1.0;
    out << std::setprecision(17);
    for (std::size_t i = 0; i < mpcd::StepProfilePhaseCount; ++i) {
        const double value = profileSeconds[i];
        const double msPerStep = 1000.0 * value / steps;
        const double percent = total > std::numeric_limits<double>::min() ? 100.0 * value / total : 0.0;
        out << mpcd::step_profile_phase_name(i) << ','
            << value << ','
            << msPerStep << ','
            << percent << '\n';
    }
    out << "total_profiled," << total << ',' << (1000.0 * total / steps) << ",100\n";
}


void write_q6_cg_profile_0163(const std::string& outputDir,
                              const std::array<double, mpcd::Q6ProjectionProfilePhaseCount>& q6Seconds,
                              const std::array<double, mpcd::EllipticProjectionProfilePhaseCount>& ellipticSeconds,
                              const int measuredQ6Steps) {
    const std::filesystem::path path = std::filesystem::path(outputDir) / "q6_cg_profile_0163.csv";
    std::ofstream out(path);
    out << "group,phase,total_s,ms_per_q6_step,percent_group_total\n";
    out << std::setprecision(17);
    const double steps = measuredQ6Steps > 0 ? static_cast<double>(measuredQ6Steps) : 1.0;

    double q6Total = 0.0;
    for (double v : q6Seconds) q6Total += v;
    for (std::size_t i = 0; i < mpcd::Q6ProjectionProfilePhaseCount; ++i) {
        const double value = q6Seconds[i];
        const double percent = q6Total > std::numeric_limits<double>::min() ? 100.0 * value / q6Total : 0.0;
        out << "q6_adapter," << mpcd::q6_projection_profile_phase_name(i) << ','
            << value << ',' << (1000.0 * value / steps) << ',' << percent << '\n';
    }
    out << "q6_adapter,total_q6_adapter," << q6Total << ',' << (1000.0 * q6Total / steps) << ",100\n";

    double ellipticTotal = 0.0;
    for (double v : ellipticSeconds) ellipticTotal += v;
    for (std::size_t i = 0; i < mpcd::EllipticProjectionProfilePhaseCount; ++i) {
        const double value = ellipticSeconds[i];
        const double percent = ellipticTotal > std::numeric_limits<double>::min() ? 100.0 * value / ellipticTotal : 0.0;
        out << "elliptic_cg," << mpcd::elliptic_projection_profile_phase_name(i) << ','
            << value << ',' << (1000.0 * value / steps) << ',' << percent << '\n';
    }
    out << "elliptic_cg,total_elliptic_cg," << ellipticTotal << ',' << (1000.0 * ellipticTotal / steps) << ",100\n";
    out << "metadata,q6_applied_steps," << measuredQ6Steps << ",0,0\n";
}


void write_resampling_guard_profile_0169(
    const std::string& outputDir,
    const std::array<double, mpcd::ResamplingPopulationGuardProfilePhaseCount>& populationSeconds,
    const int populationSteps,
    const std::uint64_t populationOverfullCandidateCells,
    const std::uint64_t populationUnderfullCandidateCells,
    const std::uint64_t populationOverfullEditedCells,
    const std::uint64_t populationUnderfullEditedCells,
    const std::uint64_t populationOverfullCandidateParticleRefs,
    const std::uint64_t populationUnderfullCandidateParticleRefs,
    const std::uint64_t populationOverfullScanPasses,
    const std::uint64_t populationUnderfullScanPasses,
    const std::uint64_t populationOverfullParticleRefsScanned,
    const std::uint64_t populationUnderfullParticleRefsScanned,
    const std::uint64_t populationOverfullEligibleParticleRefs,
    const std::uint64_t populationUnderfullEligibleParticleRefs,
    const std::uint32_t populationOverfullCandidatePopulationMax,
    const std::uint32_t populationUnderfullCandidatePopulationMax,
    const std::array<double, mpcd::ResamplingMassGuardProfilePhaseCount>& massSeconds,
    const int massSteps) {
    const std::filesystem::path path = std::filesystem::path(outputDir) / "resampling_guard_profile_0169.csv";
    std::ofstream out(path);
    out << "group,phase,total_s,ms_per_guard_step,percent_group_total\n";
    out << std::setprecision(17);

    const double populationDenom = populationSteps > 0 ? static_cast<double>(populationSteps) : 1.0;
    double populationTotal = 0.0;
    for (std::size_t i = 0; i < 7u && i < mpcd::ResamplingPopulationGuardProfilePhaseCount; ++i) {
        populationTotal += populationSeconds[i];
    }
    for (std::size_t i = 0; i < 7u && i < mpcd::ResamplingPopulationGuardProfilePhaseCount; ++i) {
        const double value = populationSeconds[i];
        const double percent = populationTotal > std::numeric_limits<double>::min()
            ? 100.0 * value / populationTotal : 0.0;
        out << "population_guard," << mpcd::resampling_population_guard_profile_phase_name(i) << ','
            << value << ',' << (1000.0 * value / populationDenom) << ',' << percent << '\n';
    }
    out << "population_guard,total_population_guard," << populationTotal << ','
        << (1000.0 * populationTotal / populationDenom) << ",100\n";

    // Phases 7..14 are the first-level deep profile added in 0168.  They are
    // nested in the high-level population_guard loops and should be interpreted
    // as a decomposition aid, not summed with population_guard.
    double populationDeepTotal = 0.0;
    const std::size_t mutationDetailBegin = 15u;
    const std::size_t populationDeepEnd = std::min<std::size_t>(
        mutationDetailBegin, mpcd::ResamplingPopulationGuardProfilePhaseCount);
    for (std::size_t i = 7u; i < populationDeepEnd; ++i) {
        populationDeepTotal += populationSeconds[i];
    }
    for (std::size_t i = 7u; i < populationDeepEnd; ++i) {
        const double value = populationSeconds[i];
        const double percent = populationDeepTotal > std::numeric_limits<double>::min()
            ? 100.0 * value / populationDeepTotal : 0.0;
        out << "population_guard_deep," << mpcd::resampling_population_guard_profile_phase_name(i) << ','
            << value << ',' << (1000.0 * value / populationDenom) << ',' << percent << '\n';
    }
    out << "population_guard_deep,total_population_guard_deep," << populationDeepTotal << ','
        << (1000.0 * populationDeepTotal / populationDenom) << ",100\n";

    // Phases 15..end are the 0169 mutation micro-profile.  They are nested
    // inside overfull_apply_mutation / underfull_apply_mutation.
    double mutationDetailTotal = 0.0;
    for (std::size_t i = mutationDetailBegin; i < mpcd::ResamplingPopulationGuardProfilePhaseCount; ++i) {
        mutationDetailTotal += populationSeconds[i];
    }
    for (std::size_t i = mutationDetailBegin; i < mpcd::ResamplingPopulationGuardProfilePhaseCount; ++i) {
        const double value = populationSeconds[i];
        const double percent = mutationDetailTotal > std::numeric_limits<double>::min()
            ? 100.0 * value / mutationDetailTotal : 0.0;
        out << "population_guard_mutation_detail," << mpcd::resampling_population_guard_profile_phase_name(i) << ','
            << value << ',' << (1000.0 * value / populationDenom) << ',' << percent << '\n';
    }
    out << "population_guard_mutation_detail,total_population_guard_mutation_detail," << mutationDetailTotal << ','
        << (1000.0 * mutationDetailTotal / populationDenom) << ",100\n";
    out << "metadata,population_guard_steps," << populationSteps << ",0,0\n";
    out << "metadata,population_guard_overfull_candidate_cells_total,"
        << populationOverfullCandidateCells << ','
        << (static_cast<double>(populationOverfullCandidateCells) / populationDenom) << ",0\n";
    out << "metadata,population_guard_underfull_candidate_cells_total,"
        << populationUnderfullCandidateCells << ','
        << (static_cast<double>(populationUnderfullCandidateCells) / populationDenom) << ",0\n";
    out << "metadata,population_guard_overfull_edited_cells_total,"
        << populationOverfullEditedCells << ','
        << (static_cast<double>(populationOverfullEditedCells) / populationDenom) << ",0\n";
    out << "metadata,population_guard_underfull_edited_cells_total,"
        << populationUnderfullEditedCells << ','
        << (static_cast<double>(populationUnderfullEditedCells) / populationDenom) << ",0\n";
    out << "metadata,population_guard_overfull_candidate_particle_refs_total,"
        << populationOverfullCandidateParticleRefs << ','
        << (static_cast<double>(populationOverfullCandidateParticleRefs) / populationDenom) << ",0\n";
    out << "metadata,population_guard_underfull_candidate_particle_refs_total,"
        << populationUnderfullCandidateParticleRefs << ','
        << (static_cast<double>(populationUnderfullCandidateParticleRefs) / populationDenom) << ",0\n";
    out << "metadata,population_guard_overfull_scan_passes_total,"
        << populationOverfullScanPasses << ','
        << (static_cast<double>(populationOverfullScanPasses) / populationDenom) << ",0\n";
    out << "metadata,population_guard_underfull_scan_passes_total,"
        << populationUnderfullScanPasses << ','
        << (static_cast<double>(populationUnderfullScanPasses) / populationDenom) << ",0\n";
    out << "metadata,population_guard_overfull_particle_refs_scanned_total,"
        << populationOverfullParticleRefsScanned << ','
        << (static_cast<double>(populationOverfullParticleRefsScanned) / populationDenom) << ",0\n";
    out << "metadata,population_guard_underfull_particle_refs_scanned_total,"
        << populationUnderfullParticleRefsScanned << ','
        << (static_cast<double>(populationUnderfullParticleRefsScanned) / populationDenom) << ",0\n";
    out << "metadata,population_guard_overfull_eligible_particle_refs_total,"
        << populationOverfullEligibleParticleRefs << ','
        << (static_cast<double>(populationOverfullEligibleParticleRefs) / populationDenom) << ",0\n";
    out << "metadata,population_guard_underfull_eligible_particle_refs_total,"
        << populationUnderfullEligibleParticleRefs << ','
        << (static_cast<double>(populationUnderfullEligibleParticleRefs) / populationDenom) << ",0\n";
    out << "metadata,population_guard_overfull_candidate_population_max,"
        << populationOverfullCandidatePopulationMax << ",0,0\n";
    out << "metadata,population_guard_underfull_candidate_population_max,"
        << populationUnderfullCandidatePopulationMax << ",0,0\n";

    double massTotal = 0.0;
    for (double v : massSeconds) massTotal += v;
    const double massDenom = massSteps > 0 ? static_cast<double>(massSteps) : 1.0;
    for (std::size_t i = 0; i < mpcd::ResamplingMassGuardProfilePhaseCount; ++i) {
        const double value = massSeconds[i];
        const double percent = massTotal > std::numeric_limits<double>::min()
            ? 100.0 * value / massTotal : 0.0;
        out << "mass_guard," << mpcd::resampling_mass_guard_profile_phase_name(i) << ','
            << value << ',' << (1000.0 * value / massDenom) << ',' << percent << '\n';
    }
    out << "mass_guard,total_mass_guard," << massTotal << ','
        << (1000.0 * massTotal / massDenom) << ",100\n";
    out << "metadata,mass_guard_steps," << massSteps << ",0,0\n";
}


bool live_vis_state_sane_0336(const mpcd::ParticleState& state,
                              const mpcd::SimulationParams& params) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (n == 0u || state.x.size() < n || state.y.size() < n ||
        state.vx.size() < n || state.vy.size() < n) {
        return false;
    }
    const double epsX = std::max(1.0e-12, 1.0e-6 * std::max(1.0, params.Lx));
    const double epsY = std::max(1.0e-12, 1.0e-6 * std::max(1.0, params.Ly));
    std::size_t finiteInside = 0u;
    std::size_t nonZeroPosition = 0u;
    for (std::size_t i = 0; i < n; ++i) {
        const double x = state.x[i];
        const double y = state.y[i];
        const double vx = state.vx[i];
        const double vy = state.vy[i];
        if (std::isfinite(x) && std::isfinite(y) &&
            std::isfinite(vx) && std::isfinite(vy) &&
            x >= -epsX && x <= params.Lx + epsX &&
            y >= -epsY && y <= params.Ly + epsY) {
            ++finiteInside;
        }
        if (std::abs(x) + std::abs(y) > 1.0e-14) {
            ++nonZeroPosition;
        }
    }
    // A compact live snapshot with only a handful of visible particles is not
    // useful and typically means the shared 0251 arrays are not authoritative
    // after resampling edits.  Keep this threshold conservative.
    return finiteInside * 10u >= 9u * n && nonZeroPosition * 10u >= 8u * n;
}

int openmp_active_threads() {
    int active = 1;
#ifdef _OPENMP
    #pragma omp parallel
    {
        #pragma omp single
        active = omp_get_num_threads();
    }
#endif
    return active;
}

double smoothstep_0418(double t) {
    t = std::min(1.0, std::max(0.0, t));
    return t * t * (3.0 - 2.0 * t);
}

double darcy_chi_at_cell_0418(int ix, int iy,
                              const mpcd::SimulationParams& params,
                              const std::vector<float>* chiFile) {
    const int nx = params.Nx;
    const int ny = params.Ny;
    if (nx <= 0 || ny <= 0) return 1.0;
    ix = std::max(0, std::min(nx - 1, ix));
    iy = std::max(0, std::min(ny - 1, iy));
    if (chiFile != nullptr) {
        const std::size_t c = static_cast<std::size_t>(iy) * static_cast<std::size_t>(nx) + static_cast<std::size_t>(ix);
        if (c < chiFile->size()) {
            return std::min(1.0, std::max(0.0, static_cast<double>((*chiFile)[c])));
        }
        return 1.0;
    }

    const double x = (static_cast<double>(ix) + 0.5) * params.Lx / static_cast<double>(std::max(1, nx));
    const double y = (static_cast<double>(iy) + 0.5) * params.Ly / static_cast<double>(std::max(1, ny));
    double chi = params.darcyUniformChi;
    const std::string mode = params.darcyChiMode;
    if (mode == "circle" || mode == "cylinder") {
        const double d = std::hypot(x - params.darcyCircleCx, y - params.darcyCircleCy);
        if (params.darcyInterfaceWidth > 0.0) {
            chi = smoothstep_0418((d - params.darcyCircleR) / params.darcyInterfaceWidth);
        } else {
            chi = d <= params.darcyCircleR ? 0.0 : 1.0;
        }
    } else if (mode == "box" || mode == "rectangle") {
        const double dx = std::max(std::max(params.darcyBoxXMin - x, x - params.darcyBoxXMax), 0.0);
        const double dy = std::max(std::max(params.darcyBoxYMin - y, y - params.darcyBoxYMax), 0.0);
        const double outsideDist = std::hypot(dx, dy);
        const bool inside = (x >= params.darcyBoxXMin && x <= params.darcyBoxXMax &&
                             y >= params.darcyBoxYMin && y <= params.darcyBoxYMax);
        if (params.darcyInterfaceWidth > 0.0) {
            chi = inside ? smoothstep_0418(outsideDist / params.darcyInterfaceWidth) : 1.0;
        } else {
            chi = inside ? 0.0 : 1.0;
        }
    }
    return std::min(1.0, std::max(0.0, chi));
}

std::vector<float> load_darcy_chi_file_for_initial_deactivation_0418(const mpcd::SimulationParams& params) {
    const std::size_t ncell = static_cast<std::size_t>(params.Nx) * static_cast<std::size_t>(params.Ny);
    std::vector<float> chi(ncell, 1.0f);
    if (params.darcyChiMode != "file") return chi;
    std::ifstream in(params.darcyChiFile, std::ios::binary);
    if (!in) {
        throw std::runtime_error("darcy initial chi deactivation 0418: cannot open darcyChiFile=" + params.darcyChiFile);
    }
    const std::string fmt = params.darcyChiFileFormat;
    if (fmt == "float64" || fmt == "f64" || fmt == "double") {
        std::vector<double> tmp(ncell, 1.0);
        in.read(reinterpret_cast<char*>(tmp.data()), static_cast<std::streamsize>(tmp.size() * sizeof(double)));
        if (in.gcount() != static_cast<std::streamsize>(tmp.size() * sizeof(double))) {
            throw std::runtime_error("darcy initial chi deactivation 0418: darcyChiFile float64 size mismatch");
        }
        for (std::size_t i = 0; i < ncell; ++i) {
            const double v = std::isfinite(tmp[i]) ? tmp[i] : 1.0;
            chi[i] = static_cast<float>(std::min(1.0, std::max(0.0, v)));
        }
    } else {
        in.read(reinterpret_cast<char*>(chi.data()), static_cast<std::streamsize>(chi.size() * sizeof(float)));
        if (in.gcount() != static_cast<std::streamsize>(chi.size() * sizeof(float))) {
            throw std::runtime_error("darcy initial chi deactivation 0418: darcyChiFile float32 size mismatch");
        }
        for (float& v : chi) {
            const double d = std::isfinite(static_cast<double>(v)) ? static_cast<double>(v) : 1.0;
            v = static_cast<float>(std::min(1.0, std::max(0.0, d)));
        }
    }
    return chi;
}

std::uint64_t deactivate_initial_particles_below_chi_0418(mpcd::ParticleState& state,
                                                          const mpcd::SimulationParams& params) {
    if (!params.darcyBrinkmanEnable || params.darcyInitialDeactivateBelowChi < 0.0) return 0u;
    mpcd::ensure_particle_roles(state, mpcd::ParticleRole::Fluid);
    const std::uint64_t activeBefore = mpcd::active_fluid_count(state);
    if (activeBefore == 0u) return 0u;
    const double invLx = params.Lx > 0.0 ? 1.0 / params.Lx : 1.0;
    const double invLy = params.Ly > 0.0 ? 1.0 / params.Ly : 1.0;
    const int nx = std::max(1, params.Nx);
    const int ny = std::max(1, params.Ny);
    std::vector<float> chiFile;
    const std::vector<float>* chiPtr = nullptr;
    if (params.darcyChiMode == "file") {
        chiFile = load_darcy_chi_file_for_initial_deactivation_0418(params);
        chiPtr = &chiFile;
    }

    std::uint64_t deactivated = 0u;
    const std::size_t active = static_cast<std::size_t>(std::min<std::uint64_t>(activeBefore, state.Np));
    for (std::size_t i = 0; i < active; ++i) {
        if (state.role[i] != mpcd::kParticleRoleFluid) continue;
        double x = state.x[i];
        double y = state.y[i];
        if (!std::isfinite(x) || !std::isfinite(y)) continue;
        x -= std::floor(x * invLx) * params.Lx;
        y -= std::floor(y * invLy) * params.Ly;
        int ix = static_cast<int>(std::floor(x * invLx * static_cast<double>(nx)));
        int iy = static_cast<int>(std::floor(y * invLy * static_cast<double>(ny)));
        const double chi = darcy_chi_at_cell_0418(ix, iy, params, chiPtr);
        if (chi < params.darcyInitialDeactivateBelowChi) {
            state.role[i] = mpcd::kParticleRoleInactive;
            ++deactivated;
        }
    }
    if (deactivated > 0u) {
        mpcd::compact_active_fluid_prefix(state);
    }
    const std::uint64_t activeAfter = mpcd::active_fluid_count(state);
    std::cerr << "[darcy0418] initial chi deactivation threshold=" << params.darcyInitialDeactivateBelowChi
              << " deactivated=" << deactivated
              << " activeBefore=" << activeBefore
              << " activeAfter=" << activeAfter << '\n';
    return deactivated;
}

} // namespace

int main(int argc, char** argv) {
    try {
        if (argc != 2) {
            std::cerr << "Usage: " << argv[0] << " params.kv\n";
            return 2;
        }

        const std::string paramsFile = argv[1];
        mpcd::SimulationParams params = mpcd::read_simulation_params_kv(paramsFile);

#ifdef _OPENMP
        if (params.numThreads > 0) {
            omp_set_num_threads(params.numThreads);
        }
#endif

        const int ompMaxThreads = openmp_max_threads();
        const int ompActiveThreads = openmp_active_threads();
        const bool collectInternalProfiles = internal_profiles_enabled_0176();

        std::filesystem::create_directories(params.outputDir);
        const std::filesystem::path paramsCopy = std::filesystem::path(params.outputDir) / "params_used.kv";
        std::error_code ec;
        std::filesystem::copy_file(paramsFile, paramsCopy,
                                   std::filesystem::copy_options::overwrite_existing, ec);

        mpcd::ParticleState state = mpcd::read_smpcd_state(params.inputState);
        mpcd::ensure_inactive_slots(state, params.initialInactiveSlots);
        mpcd::ensure_particle_roles(state, mpcd::ParticleRole::Fluid);
        deactivate_initial_particles_below_chi_0418(state, params);
        const mpcd::ParticleRoleCounts initialRoleCounts = mpcd::count_particle_roles(state);
        mpcd::CellGrid grid = mpcd::make_cell_grid(params);
        const mpcd::FluidDomainBounds initialDomain = mpcd::make_fluid_domain_bounds(params, 0.0);
        mpcd::apply_boundary_conditions(state, params, initialDomain, 0u, 0.0);
        mpcd::apply_immersed_solid_reflection(state, params, initialDomain, 0.0);

        mpcd::RuntimeSummaryWriter summary(params.outputDir + "/summary_runtime.csv");
        mpcd::LiveVisualization0335 liveVisualization0335;
        liveVisualization0335.maybe_initialize(params);
        mpcd::FilteredFieldRecorder0432 filteredFieldRecorder0432;
        filteredFieldRecorder0432.maybe_initialize(params);
        mpcd::SrcMpcdBaseWorkspace workspace;
        std::array<double, mpcd::StepProfilePhaseCount> phaseProfileSeconds{};
        std::array<double, mpcd::Q6ProjectionProfilePhaseCount> q6ProfileSeconds{};
        std::array<double, mpcd::EllipticProjectionProfilePhaseCount> ellipticProfileSeconds{};
        std::array<double, mpcd::ResamplingPopulationGuardProfilePhaseCount> populationGuardProfileSeconds{};
        std::array<double, mpcd::ResamplingMassGuardProfilePhaseCount> massGuardProfileSeconds{};
        int phaseProfileSteps = 0;
        int q6ProfileSteps = 0;
        int populationGuardProfileSteps = 0;
        int massGuardProfileSteps = 0;
        std::uint64_t populationGuardOverfullCandidateCells = 0;
        std::uint64_t populationGuardUnderfullCandidateCells = 0;
        std::uint64_t populationGuardOverfullEditedCells = 0;
        std::uint64_t populationGuardUnderfullEditedCells = 0;
        std::uint64_t populationGuardOverfullCandidateParticleRefs = 0;
        std::uint64_t populationGuardUnderfullCandidateParticleRefs = 0;
        std::uint64_t populationGuardOverfullScanPasses = 0;
        std::uint64_t populationGuardUnderfullScanPasses = 0;
        std::uint64_t populationGuardOverfullParticleRefsScanned = 0;
        std::uint64_t populationGuardUnderfullParticleRefsScanned = 0;
        std::uint64_t populationGuardOverfullEligibleParticleRefs = 0;
        std::uint64_t populationGuardUnderfullEligibleParticleRefs = 0;
        std::uint32_t populationGuardOverfullCandidatePopulationMax = 0;
        std::uint32_t populationGuardUnderfullCandidatePopulationMax = 0;
        const auto t0 = std::chrono::steady_clock::now();

        const std::vector<std::uint32_t> initialCellCount =
            mpcd::compute_cell_counts(state, grid, mpcd::GridShift{}, params);
        const bool disabledResamplingSummaryDiagnostics0315g =
            disabled_resampling_summary_diagnostics_enabled_0315g(params);
        mpcd::WeightedResamplingDiagnostics initialResampling{};
        const mpcd::WeightedResamplingDiagnostics* initialResamplingSummary0315g = nullptr;
        if (disabledResamplingSummaryDiagnostics0315g) {
            const mpcd::ResamplingParticlePoolDiagnostics initialPool =
                mpcd::rebuild_resampling_particle_pool(state, workspace.resamplingPool);
            initialResampling =
                mpcd::deposit_weighted_real_fluid(state, params, grid, initialDomain, 0.0, mpcd::GridShift{}, workspace.resampling);
            mpcd::attach_resampling_pool_diagnostics(initialResampling, initialPool);
            initialResamplingSummary0315g = &initialResampling;
        }
        summary.append(mpcd::compute_runtime_summary(state, params, 0, elapsed_seconds(t0),
                                                     &initialCellCount, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
                                                     initialResamplingSummary0315g, ompActiveThreads));
        if (params.dumpStateEvery > 0) {
            write_state_dump_0314(state_dump_name(params.outputDir, 0), state, params);
        }


        std::cout << "[src_mpcd_base] Np=" << state.Np
                  << " fluid=" << initialRoleCounts.fluid
                  << " latent=" << initialRoleCounts.latent
                  << " inactive=" << initialRoleCounts.inactive
                  << " grid=" << params.Nx << "x" << params.Ny
                  << " bc=[L:" << params.bcLeft
                  << ", R:" << params.bcRight
                  << ", B:" << params.bcBottom
                  << ", T:" << params.bcTop << "]"
                  << " wallAccommodation=" << params.wallAccommodation
                  << " immersedSolid=" << (params.immersedSolidEnable ? "on" : "off")
                  << " fluid=[" << initialDomain.xMin << "," << initialDomain.xMax
                  << "]x[" << initialDomain.yMin << "," << initialDomain.yMax << "]"
                  << " projection=" << (params.projectionEnable ? params.projectionOperator : std::string("off"))
                  << " resampling=" << (params.resamplingEnable ? std::string("on") : std::string("off"))
                  << " thermostat=" << (params.thermostatEnable ? params.thermostatMode : std::string("off"))
                  << " steps=" << params.nSteps
                  << " threadsActive=" << ompActiveThreads
                  << " threadsMax=" << ompMaxThreads
                  << " outputDir=" << params.outputDir
                  << " dumpRoleFilter=" << params.dumpRoleFilter
                  << " summaryRoleFilter=" << params.summaryRoleFilter << '\n';

        for (int step = 1; step <= params.nSteps; ++step) {
            const bool summaryStep0315g =
                (step % params.summaryEvery == 0) || (step == params.nSteps);
            const bool collectResamplingDiagnostics =
                params.resamplingEnable ||
                (disabledResamplingSummaryDiagnostics0315g && summaryStep0315g);
            const mpcd::StepResult stepResult = mpcd::run_src_mpcd_base_step(
                state, params, grid, static_cast<std::uint64_t>(step), workspace,
                collectResamplingDiagnostics);
            if (collectInternalProfiles) {
                for (std::size_t phase = 0; phase < mpcd::StepProfilePhaseCount; ++phase) {
                    phaseProfileSeconds[phase] += stepResult.profile.seconds[phase];
                }
                ++phaseProfileSteps;
                if (stepResult.q6.applied) {
                    for (std::size_t phase = 0; phase < mpcd::Q6ProjectionProfilePhaseCount; ++phase) {
                        q6ProfileSeconds[phase] += stepResult.q6.profile.seconds[phase];
                    }
                    for (std::size_t phase = 0; phase < mpcd::EllipticProjectionProfilePhaseCount; ++phase) {
                        ellipticProfileSeconds[phase] += stepResult.q6.ellipticProfile.seconds[phase];
                    }
                    ++q6ProfileSteps;
                }
                if (stepResult.resampling.populationGuardAttempted) {
                    for (std::size_t phase = 0; phase < mpcd::ResamplingPopulationGuardProfilePhaseCount; ++phase) {
                        populationGuardProfileSeconds[phase] += stepResult.resampling.populationGuardProfileSeconds[phase];
                    }
                    populationGuardOverfullCandidateCells += stepResult.resampling.populationGuardOverfullCandidateCells;
                    populationGuardUnderfullCandidateCells += stepResult.resampling.populationGuardUnderfullCandidateCells;
                    populationGuardOverfullEditedCells += stepResult.resampling.populationGuardOverfullEditedCells;
                    populationGuardUnderfullEditedCells += stepResult.resampling.populationGuardUnderfullEditedCells;
                    populationGuardOverfullCandidateParticleRefs += stepResult.resampling.populationGuardOverfullCandidateParticleRefs;
                    populationGuardUnderfullCandidateParticleRefs += stepResult.resampling.populationGuardUnderfullCandidateParticleRefs;
                    populationGuardOverfullScanPasses += stepResult.resampling.populationGuardOverfullScanPasses;
                    populationGuardUnderfullScanPasses += stepResult.resampling.populationGuardUnderfullScanPasses;
                    populationGuardOverfullParticleRefsScanned += stepResult.resampling.populationGuardOverfullParticleRefsScanned;
                    populationGuardUnderfullParticleRefsScanned += stepResult.resampling.populationGuardUnderfullParticleRefsScanned;
                    populationGuardOverfullEligibleParticleRefs += stepResult.resampling.populationGuardOverfullEligibleParticleRefs;
                    populationGuardUnderfullEligibleParticleRefs += stepResult.resampling.populationGuardUnderfullEligibleParticleRefs;
                    populationGuardOverfullCandidatePopulationMax = std::max(
                        populationGuardOverfullCandidatePopulationMax,
                        stepResult.resampling.populationGuardOverfullCandidatePopulationMax);
                    populationGuardUnderfullCandidatePopulationMax = std::max(
                        populationGuardUnderfullCandidatePopulationMax,
                        stepResult.resampling.populationGuardUnderfullCandidatePopulationMax);
                    ++populationGuardProfileSteps;
                }
                if (stepResult.resampling.massGuardAttempted) {
                    for (std::size_t phase = 0; phase < mpcd::ResamplingMassGuardProfilePhaseCount; ++phase) {
                        massGuardProfileSeconds[phase] += stepResult.resampling.massGuardProfileSeconds[phase];
                    }
                    ++massGuardProfileSteps;
                }
            }

            if (liveVisualization0335.should_draw(static_cast<std::uint64_t>(step),
                                                      static_cast<std::uint64_t>(params.nSteps))) {
                liveVisualization0335.maybe_reload_controls(static_cast<std::uint64_t>(step));
                const mpcd::LiveVisualization0335RuntimeControls liveControls0337 =
                    liveVisualization0335.current_controls();
                bool drawnByCudaField0337 = false;
                if (env_truthy_0260("SRC_LIVE_VIS_CUDA_FIELD")) {
                    const int liveNx0337 = std::max(16, env_int_0337("SRC_LIVE_VIS_NX", 300));
                    const int liveNy0337 = std::max(16, env_int_0337("SRC_LIVE_VIS_NY", 80));
                    const std::string liveField0337 = liveControls0337.field.empty() ? env_string_0337("SRC_LIVE_VIS_FIELD", "ux") : liveControls0337.field;
                    const double liveClip0337 = liveControls0337.clip;
                    const double liveGain0337 = liveControls0337.gain;
                    const int liveSmooth0337 = std::max(0, liveControls0337.smoothPasses);
                    std::vector<unsigned char> liveRgba0337;
                    mpcd::CudaLiveField0337Diagnostics liveDiag0337{};
                    mpcd::CudaLiveQuiver0337 cudaQuiver0337{};
                    const bool liveQuiverEnabled0337 = (liveControls0337.quiverScale >= 0.0);
                    if (liveQuiverEnabled0337) {
                        cudaQuiver0337.enabled = 1;
                        cudaQuiver0337.nx = std::max(1, liveControls0337.quiverNx);
                        cudaQuiver0337.ny = std::max(1, liveControls0337.quiverNy);
                    }
                    drawnByCudaField0337 = mpcd::cuda_live_field_render_shared_0337(
                        liveRgba0337, liveNx0337, liveNy0337, params, liveField0337, liveClip0337,
                        liveGain0337, liveSmooth0337,
                            liveControls0337.particleTypeFilter,
                            &liveDiag0337,
                        liveQuiverEnabled0337 ? &cudaQuiver0337 : nullptr);
                    if (drawnByCudaField0337) {
                        std::ostringstream liveSourceLabel0337;
                        liveSourceLabel0337 << "cuda_field_0337";
                        if (liveDiag0337.minMaxComputed) {
                            liveSourceLabel0337 << " min=" << std::setprecision(3) << liveDiag0337.fieldMin
                                                << " max=" << std::setprecision(3) << liveDiag0337.fieldMax
                                                << " scale=" << std::setprecision(3) << liveDiag0337.fieldScale;
                        }
                        mpcd::LiveVisualization0335QuiverFrame liveQuiverFrame0337{};
                        const mpcd::LiveVisualization0335QuiverFrame* liveQuiverPtr0337 = nullptr;
                        if (cudaQuiver0337.rendered) {
                            liveQuiverFrame0337.nx = cudaQuiver0337.nx;
                            liveQuiverFrame0337.ny = cudaQuiver0337.ny;
                            liveQuiverFrame0337.scale = liveControls0337.quiverScale;
                            liveQuiverFrame0337.minSpeed = liveControls0337.quiverMinSpeed;
                            liveQuiverFrame0337.ux = cudaQuiver0337.ux;
                            liveQuiverFrame0337.uy = cudaQuiver0337.uy;
                            liveQuiverPtr0337 = &liveQuiverFrame0337;
                            const int liveQuiverSmooth0337 = (liveControls0337.quiverSmoothPasses >= 0) ?
                                liveControls0337.quiverSmoothPasses : liveControls0337.smoothPasses;
                            liveSourceLabel0337 << " quiver=" << cudaQuiver0337.nx << "x" << cudaQuiver0337.ny
                                                << " qscale=" << std::setprecision(3) << liveControls0337.quiverScale
                                                << " typeFilter=" << liveControls0337.particleTypeFilter
                                                << " qsmooth=" << liveQuiverSmooth0337;
                        }
                        liveVisualization0335.draw_rgba_frame(params, static_cast<std::uint64_t>(step),
                                                              static_cast<double>(step) * params.dt,
                                                              liveRgba0337, liveNx0337, liveNy0337,
                                                              liveSourceLabel0337.str(), liveQuiverPtr0337);
                    }
                    if (env_truthy_0260("SRC_LIVE_VIS_LOG_SOURCE")) {
                        std::cerr << "\r\033[K[livevis0335] step=" << step
                                  << " source=" << (drawnByCudaField0337 ? "cuda_field_0337" : "cuda_field_failed_fallback")
                                  << " particles=" << liveDiag0337.particles
                                  << " activeFluid=" << liveDiag0337.activeFluid;
                        if (liveDiag0337.minMaxComputed) {
                            std::cerr << " min=" << liveDiag0337.fieldMin
                                      << " max=" << liveDiag0337.fieldMax
                                      << " scale=" << liveDiag0337.fieldScale
                                      << " minmax_s=" << liveDiag0337.minMaxSeconds;
                        }
                        if (cudaQuiver0337.rendered) {
                            const int liveQuiverSmooth0337 = (liveControls0337.quiverSmoothPasses >= 0) ?
                                liveControls0337.quiverSmoothPasses : liveControls0337.smoothPasses;
                            std::cerr << " quiver=" << cudaQuiver0337.nx << "x" << cudaQuiver0337.ny
                                      << " qscale=" << liveControls0337.quiverScale
                                      << " typeFilter=" << liveControls0337.particleTypeFilter
                                      << " qsmooth=" << liveQuiverSmooth0337;
                        }
                        std::cerr << " total_s=" << liveDiag0337.totalSeconds
                                  << std::flush;
                    }
                }
                if (!drawnByCudaField0337) {
                    mpcd::ParticleState liveState;
                    mpcd::ParticleRoleCounts liveRoleCounts{};
                    bool compactLive0335 = mpcd::cuda_shared_particle_state_0251_download_role_filtered_if_fresh(liveState, mpcd::kParticleRoleFluid, &liveRoleCounts);
                    bool snapshotLive0336 = false;
                    bool rejectedSnapshot0336 = false;
                    if (!compactLive0335 && env_truthy_0260("SRC_LIVE_VIS_CUDA_SNAPSHOT")) {
                        snapshotLive0336 = mpcd::cuda_shared_particle_state_0251_download_role_filtered_snapshot_0336(liveState, mpcd::kParticleRoleFluid, &liveRoleCounts);
                        if (snapshotLive0336 && !live_vis_state_sane_0336(liveState, params)) { snapshotLive0336 = false; rejectedSnapshot0336 = true; liveState = mpcd::ParticleState{}; }
                    }
                    if (!compactLive0335 && !snapshotLive0336) { sync_cuda_resident_state_for_host_0260(state); liveState = state; }
                    if (env_truthy_0260("SRC_LIVE_VIS_LOG_SOURCE")) {
                        const char* liveSource0336 = compactLive0335 ? "cuda_compact_fluid" : (snapshotLive0336 ? "cuda_snapshot_fluid_0336" : (rejectedSnapshot0336 ? "cuda_snapshot_rejected_host_fallback_0336" : "host_state_fallback"));
                        std::cerr << "\r\033[K[livevis0335] step=" << step
                                  << " source=" << liveSource0336
                                  << " Np=" << liveState.Np
                                  << " NactiveFluid=" << liveState.NactiveFluid
                                  << std::flush;
                    }
                    liveVisualization0335.update(liveState, params, static_cast<std::uint64_t>(step), static_cast<double>(step) * params.dt);
                }
            }

            if (filteredFieldRecorder0432.enabled()) {
                const double recordTime0432 = static_cast<double>(step) * params.dt;
                const mpcd::LiveVisualization0335RuntimeControls recordControls0432 =
                    liveVisualization0335.current_controls();
                filteredFieldRecorder0432.poll_controls(static_cast<std::uint64_t>(step),
                                                         recordTime0432,
                                                         recordControls0432);
                if (filteredFieldRecorder0432.needs_host_state(static_cast<std::uint64_t>(step))) {
                    mpcd::ParticleState recordState0432;
                    mpcd::ParticleRoleCounts recordRoleCounts0432{};
                    const bool compactRecord0432 =
                        mpcd::cuda_shared_particle_state_0251_download_role_filtered_if_fresh(
                            recordState0432, mpcd::kParticleRoleFluid, &recordRoleCounts0432);
                    if (!compactRecord0432) {
                        sync_cuda_resident_state_for_host_0260(state);
                        recordState0432 = state;
                    }
                    filteredFieldRecorder0432.sample_and_maybe_write(recordState0432, params,
                                                                      static_cast<std::uint64_t>(step),
                                                                      recordTime0432);
                }
            }

            if (step % params.summaryEvery == 0 || step == params.nSteps) {
                mpcd::ParticleState summaryState;
                mpcd::ParticleRoleCounts compactRoleCounts{};
                bool compactSummary0314 = false;
                if (role_filter_fluid_0314(params.summaryRoleFilter)) {
                    compactSummary0314 = mpcd::cuda_shared_particle_state_0251_download_role_filtered_if_fresh(
                        summaryState, mpcd::kParticleRoleFluid, &compactRoleCounts);
                }
                if (!compactSummary0314) {
                    sync_cuda_resident_state_for_host_0260(state);
                    summaryState = state;
                }
                const double wallTime = elapsed_seconds(t0);
                const mpcd::WeightedResamplingDiagnostics* resamplingSummary0315g =
                    stepResult.resampling.computed ? &stepResult.resampling : nullptr;
                auto s = mpcd::compute_runtime_summary(summaryState, params, step, wallTime,
                                                           &workspace.collision.cellCount,
                                                           &stepResult.boundary,
                                                           &stepResult.immersed,
                                                           &stepResult.collision,
                                                           &stepResult.q6,
                                                           &stepResult.capacity,
                                                           &stepResult.thermostat,
                                                           resamplingSummary0315g,
                                                           ompActiveThreads);
                if (compactSummary0314) {
                    s.Np = state.Np;
                    s.nFluidParticles = compactRoleCounts.fluid;
                    s.nInactiveParticles = compactRoleCounts.inactive;
                    s.nLatentParticles = compactRoleCounts.latent;
                }
                summary.append(s);
    std::cout << "\r\033[K[src_mpcd_base] step=" << step
          << "/" << params.nSteps
          << " t=" << std::fixed << std::setprecision(3) << s.time
          << " kBT=" << std::scientific << std::setprecision(3) << s.kBTEstimate
          << " stdN=" << std::fixed << std::setprecision(3) << s.stdN
          << " resM=" << std::scientific << std::setprecision(2) << s.resampMRelRms
          << " q6=" << std::scientific << std::setprecision(2) << s.q6DivAfterProjectedFluxRms
          << " wall=" << std::fixed << std::setprecision(1) << wallTime << "s"
          << std::flush;
            }

            if (params.dumpStateEvery > 0 && (step % params.dumpStateEvery == 0 || step == params.nSteps)) {
                sync_cuda_resident_state_for_host_0260(state);
                write_state_dump_0314(state_dump_name(params.outputDir, step), state, params);
            }
        }

        filteredFieldRecorder0432.finalize(static_cast<std::uint64_t>(params.nSteps),
                                           static_cast<double>(params.nSteps) * params.dt);

        if (collectInternalProfiles) {
            write_phase_profile_0163(params.outputDir, phaseProfileSeconds, phaseProfileSteps);
            write_q6_cg_profile_0163(params.outputDir, q6ProfileSeconds, ellipticProfileSeconds, q6ProfileSteps);
            write_resampling_guard_profile_0169(params.outputDir,
                                                populationGuardProfileSeconds, populationGuardProfileSteps,
                                                populationGuardOverfullCandidateCells,
                                                populationGuardUnderfullCandidateCells,
                                                populationGuardOverfullEditedCells,
                                                populationGuardUnderfullEditedCells,
                                                populationGuardOverfullCandidateParticleRefs,
                                                populationGuardUnderfullCandidateParticleRefs,
                                                populationGuardOverfullScanPasses,
                                                populationGuardUnderfullScanPasses,
                                                populationGuardOverfullParticleRefsScanned,
                                                populationGuardUnderfullParticleRefsScanned,
                                                populationGuardOverfullEligibleParticleRefs,
                                                populationGuardUnderfullEligibleParticleRefs,
                                                populationGuardOverfullCandidatePopulationMax,
                                                populationGuardUnderfullCandidatePopulationMax,
                                                massGuardProfileSeconds, massGuardProfileSteps);
            std::cout << "\n[src_mpcd_base] wrote " << params.outputDir << "/phase_profile_0163.csv";
            std::cout << "\n[src_mpcd_base] wrote " << params.outputDir << "/q6_cg_profile_0163.csv";
            std::cout << "\n[src_mpcd_base] wrote " << params.outputDir << "/resampling_guard_profile_0169.csv";
        } else {
            std::cout << "\n[src_mpcd_base] internal profile CSV disabled"
                      << " (set MPCD_INTERNAL_PROFILES=1 to enable)";
        }
        std::cout << "\n[src_mpcd_base] done\n";
        liveVisualization0335.hold_until_closed_on_exit();
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}

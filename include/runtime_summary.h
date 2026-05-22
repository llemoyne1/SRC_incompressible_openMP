#pragma once

#include <cstdint>
#include <fstream>
#include <string>
#include <vector>
#include "boundary_base.h"
#include "fluid_domain.h"
#include "immersed_circle.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "src_collision.h"
#include "thermostat.h"

namespace mpcd {

struct RuntimeSummary {
    int step = 0;
    double time = 0.0;
    double wallTime = 0.0;
    int numThreadsUsed = 1;

    std::uint64_t Np = 0;
    double totalMass = 0.0;
    double Px = 0.0;
    double Py = 0.0;
    double meanVx = 0.0;
    double meanVy = 0.0;
    double meanKinetic = 0.0;
    double kBTEstimate = 0.0;

    // Active fluid-domain diagnostics. These are recorded at runtime because
    // future moving-domain runs need the exact geometric state associated with
    // each step. Detailed profiles remain post-processing responsibilities.
    double fluidXMin = 0.0;
    double fluidXMax = 0.0;
    double fluidYMin = 0.0;
    double fluidYMax = 0.0;
    double fluidArea = 0.0;
    double meanPhysicalDensity = 0.0;

    double meanN = 0.0;
    double stdN = 0.0;
    std::uint32_t minN = 0;
    std::uint32_t maxN = 0;

    std::uint64_t hitsLeft = 0;
    std::uint64_t hitsRight = 0;
    std::uint64_t hitsBottom = 0;
    std::uint64_t hitsTop = 0;
    std::uint64_t hitsImmersed = 0;

    std::uint64_t virtualParticleCount = 0;
    double virtualParticleEquivalent = 0.0;
    double virtualMass = 0.0;
    double virtualMassLeft = 0.0;
    double virtualMassRight = 0.0;
    double virtualMassBottom = 0.0;
    double virtualMassTop = 0.0;
    double virtualMassImmersed = 0.0;
    double virtualMomentumX = 0.0;
    double virtualMomentumY = 0.0;

    int thermostatApplied = 0;
    std::uint64_t thermostatCells = 0;
    std::uint64_t thermostatParticles = 0;
    double thermostatKBTBefore = 0.0;
    double thermostatKBTAfter = 0.0;
    double thermostatScaleMean = 1.0;
    double thermostatScaleMin = 1.0;
    double thermostatScaleMax = 1.0;
};

RuntimeSummary compute_runtime_summary(const ParticleState& state,
                                       const SimulationParams& params,
                                       int step,
                                       double wallTime,
                                       const std::vector<std::uint32_t>* cellCount = nullptr,
                                       const BoundaryDiagnostics* boundary = nullptr,
                                       const ImmersedCircleDiagnostics* immersed = nullptr,
                                       const CollisionDiagnostics* collision = nullptr,
                                       const ThermostatDiagnostics* thermostat = nullptr,
                                       int numThreadsUsed = 1);

class RuntimeSummaryWriter {
public:
    explicit RuntimeSummaryWriter(const std::string& filepath);
    void append(const RuntimeSummary& s);

private:
    std::ofstream out_;
};

} // namespace mpcd

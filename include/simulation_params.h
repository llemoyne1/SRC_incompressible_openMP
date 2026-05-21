#pragma once

#include <cstdint>
#include <string>

namespace mpcd {

struct SimulationParams {
    std::string inputState;
    std::string outputDir = "run_base";

    double Lx = 1.0;
    double Ly = 1.0;
    int Nx = 32;
    int Ny = 32;

    double dt = 1.0e-3;
    int nSteps = 1000;

    // Rotation angle in radians. alphaDeg is accepted by the parser as a convenience alias.
    double rotationAngle = 2.0943951023931953; // 120 deg
    bool randomRotationSign = true;

    bool gridShiftEnable = true;
    std::uint64_t rngSeed = 12345u;

    // Uniform body acceleration applied before streaming. The parser also accepts
    // bodyForceX/bodyForceY as aliases for compatibility with previous parameter files.
    double bodyAccelerationX = 0.0;
    double bodyAccelerationY = 0.0;

    // Boundary modes are specified per face. The legacy aliases bcX and bcY are
    // still accepted by the parser and set the corresponding face pairs.
    // Implemented now: periodic pairs, solid thermal walls, and legacy
    // specular/bounceback debug walls. Reserved for future internal-flow
    // simulations: inlet, outlet.
    std::string bcLeft = "periodic";
    std::string bcRight = "periodic";
    std::string bcBottom = "periodic";
    std::string bcTop = "periodic";

    // Generic thermal solid-wall coupling. Solid walls are geometrically
    // impermeable; wall coupling is represented by aggregate virtual wall mass
    // and momentum in boundary-cut collision cells. The recommended path is
    // bcFace=solid with wallAccommodation in [0,1]. Legacy wallVp* keys remain
    // accepted as aliases for compatibility with earlier runs.
    bool wallVpEnable = false;              // legacy: also activates coupling on legacy wall modes
    std::string wallVpMode = "thermal";     // legacy key; accepted values: thermal, deterministic_thermal, stochastic_fraction
    double wallAccommodation = 1.0;         // 0 => slip/specular-like, 1 => full thermal wall coupling
    double wallVpGamma = 0.0;               // wall population in a fully solid collision cell; 0 => mean real occupancy
    double wallVpMass = 1.0;
    double wallKBT = -1.0;                  // negative => use kBT
    double wallVpKBT = -1.0;                // legacy alias for wallKBT
    double wallThermalNoise = 1.0;          // 0 => deterministic momentum, 1 => full thermal aggregate noise
    double wallVpUxLeft = 0.0;
    double wallVpUyLeft = 0.0;
    double wallVpUxRight = 0.0;
    double wallVpUyRight = 0.0;
    double wallVpUxBottom = 0.0;
    double wallVpUyBottom = 0.0;
    double wallVpUxTop = 0.0;
    double wallVpUyTop = 0.0;

    // Mass-aware thermostat acting on velocities relative to the real-particle
    // center-of-mass velocity in each collision cell. It is intended for forced
    // channel calibration runs, where body force and wall coupling otherwise
    // produce viscous heating.
    bool thermostatEnable = false;
    std::string thermostatMode = "cell_relative_rescale";
    int thermostatEvery = 1;
    double thermostatTargetKBT = -1.0; // negative => use kBT
    int thermostatMinParticles = 3;
    double thermostatEpsilon = 1.0e-30;
    double kBT = 0.0;

    int summaryEvery = 10;
    int dumpStateEvery = 0;

    // If >0 and OpenMP is enabled, the executable calls omp_set_num_threads(numThreads).
    int numThreads = 0;
};

void validate_simulation_params(const SimulationParams& params);

bool is_x_periodic(const SimulationParams& params);
bool is_y_periodic(const SimulationParams& params);
bool is_solid_wall_mode(const std::string& mode);
bool has_solid_wall(const SimulationParams& params);

} // namespace mpcd

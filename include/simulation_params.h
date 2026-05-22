#pragma once

#include <cstdint>
#include <string>

namespace mpcd {

struct SimulationParams {
    std::string inputState;
    std::string outputDir = "run_base";

    // Fixed numerical box and collision grid. Lx/Ly remain the numerical
    // extents used by periodic wrapping and fixed-size cell arrays. The active
    // fluid domain can be a sub-domain of this box; see fluid* parameters below.
    double Lx = 1.0;
    double Ly = 1.0;
    int Nx = 32;
    int Ny = 32;

    // Active fluid domain inside the fixed numerical box. Negative max bounds
    // inherit the corresponding box size. Velocities are zero by default, so
    // existing fixed-domain runs are unchanged. fluidYTop0/fluidYTopVelocity
    // are accepted by the parser as aliases for fluidYMax0/fluidYMaxVelocity.
    double fluidXMin0 = 0.0;
    double fluidXMax0 = -1.0;
    double fluidYMin0 = 0.0;
    double fluidYMax0 = -1.0;
    double fluidXMinVelocity = 0.0;
    double fluidXMaxVelocity = 0.0;
    double fluidYMinVelocity = 0.0;
    double fluidYMaxVelocity = 0.0;

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


    // First immersed analytic solid: one fixed circular geometry. It uses the
    // same generic solid_thermal coupling parameters as rectangular walls:
    // wallAccommodation, wallVpGamma, wallVpMass, wallKBT and wallThermalNoise.
    // The circle center can translate linearly and the local wall velocity can
    // include both center translation and a prescribed rigid rotation through
    // immersedCircleOmega. This is the first simple rigid-body immersed solid.
    bool immersedCircleEnable = false;
    double immersedCircleCx = 0.5;
    double immersedCircleCy = 0.5;
    double immersedCircleR = 0.1;
    int immersedCircleFractionSamples = 4;
    double immersedCircleVx = 0.0;     // center translation velocity
    double immersedCircleVy = 0.0;
    double immersedCircleWallUx = 0.0; // legacy uniform wall-velocity offset; normally keep zero
    double immersedCircleWallUy = 0.0;
    double immersedCircleOmega = 0.0;  // angular velocity around the moving center, positive counter-clockwise

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

    // Optional incompressible/projection modules. The current Q6 adapter is the
    // first consumer of the generic elliptic projection core. The supported and
    // validated first use case is a fully periodic fixed box, but this scope is
    // documented rather than guarded by extra runtime restrictions.
    std::string method = "classic";          // classic, q6, q9; q9_virial reserved for later
    bool projectionEnable = false;
    std::string projectionOperator = "periodic_fv_cg"; // aliases accepted: channel_fv_cg, auto_fv_cg, elliptic_fv_cg
    int projectionMaxIterations = 300;
    double projectionTolerance = 1.0e-10;
    bool projectionMomentumCorrectionEnable = true;

    // Optional Q9 mass-flux projection adapter. Q9 reuses the same generic
    // elliptic face-field core as Q6 but projects a mass/momentum flux toward
    // a uniform-density relaxation target. The first validated scope is
    // periodic boxes; other configurations are documented progressively.
    bool q9MassFluxProjectionEnable = false;
    double q9MassFluxProjectionStrength = 1.0;
    double q9DensityRelaxationBeta = 5.0e-4;
    std::string q9TargetFilter = "elliptic_lowpass"; // none, elliptic_lowpass; MATLAB-compatible aliases accepted
    int q9LowKMaxIndex = 2;
    int q9EllipticLowPassPasses = 1;
    double q9EllipticLowPassLengthCells = -1.0; // negative => MATLAB-like default from low-k index
    bool q9MomentumCorrectionEnable = true;


    // Optional MATLAB-like virial EOS pressure diagnostic/kick. This module is
    // independent from Q6/Q9 and is normally called after Q6/Q9 and before the
    // final thermostat. It is disabled by default. method=q9_virial enables
    // diagnostics and kick, with zero effect unless Kvirial and virialBeta are
    // non-zero.
    bool virialDiagnosticsEnable = false;
    bool virialKickEnable = false;
    double Kvirial = 0.0;
    double virialBeta = 0.0;
    std::string virialRhoEOSRefMode = "initial_physical_density"; // initial_physical_density, current_uniform, explicit
    double virialRhoEOSRef = 0.0;
    std::string virialRhoUniformMode = "reference_gamma_current_volume"; // current-volume uniform reference
    double virialRhoUniformNow = 0.0;
    std::string virialDriveTargetMode = "current_uniform"; // current_uniform, eos_ref, zero
    std::string virialRhoKickMode = "uniform_now"; // uniform_now, local
    double virialRhoKickMinFraction = 0.1;
    bool virialMomentumCorrectionEnable = true;

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

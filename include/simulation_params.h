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

    // Optional global mean-flow controller. This is useful for periodic wake
    // tests around immersed solids: it mimics the CUDA VK keepMeanFlow path by
    // applying a spatially uniform velocity shift after the SRC/Q6/Q9/virial/
    // thermostat sequence, while preserving relative thermal velocities.
    bool keepMeanFlowEnable = false;
    double targetMeanUx = 0.0;
    double targetMeanUy = 0.0;

    // Boundary modes are specified per face. The legacy aliases bcX and bcY are
    // still accepted by the parser and set the corresponding face pairs.
    // Implemented now: periodic pairs, solid thermal walls, and legacy
    // specular/bounceback debug walls. Reserved for future internal-flow
    // simulations: inlet, outlet.
    std::string bcLeft = "periodic";
    std::string bcRight = "periodic";
    std::string bcBottom = "periodic";
    std::string bcTop = "periodic";

    // Minimal particle-reservoir inlet/outlet support for classic SRC/MPCD
    // open-channel tests. A particle crossing an outlet is recycled at the
    // paired inlet face with the prescribed inlet mean velocity plus optional
    // Maxwellian thermal noise. The 0061b default follows the legacy CUDA
    // inlet-injection path: reinject into a thin inlet slab and randomize the
    // tangential coordinate to keep the inlet density homogeneous. This
    // deliberately remains a particle-only boundary mechanism; Q6/Q9/virial
    // open-boundary compatibility is added in later patches through the
    // elliptic face-flux machinery.
    double inletUxLeft = 0.0;
    double inletUyLeft = 0.0;
    double inletUxRight = 0.0;
    double inletUyRight = 0.0;
    double inletUxBottom = 0.0;
    double inletUyBottom = 0.0;
    double inletUxTop = 0.0;
    double inletUyTop = 0.0;

    // Optional time ramp for inlet velocities and matching Q6/Q9 open-boundary
    // flux targets.  The stored inletUx*/inletUy* values remain the final
    // target values.  When enabled, they are scaled by a factor interpolating
    // from inletVelocityRampInitialFactor to inletVelocityRampFinalFactor over
    // [inletVelocityRampStartTime, inletVelocityRampEndTime].  This avoids an
    // impulsive hard-inlet start while preserving the final validated method
    // parameters.  Supported profiles: linear, smoothstep.
    bool inletVelocityRampEnable = false;
    double inletVelocityRampStartTime = 0.0;
    double inletVelocityRampEndTime = 0.0;
    double inletVelocityRampInitialFactor = 0.0;
    double inletVelocityRampFinalFactor = 1.0;
    std::string inletVelocityRampProfile = "linear";

    // Optional spatial profile for the imposed inlet velocity and matching
    // Q6/Q9 open-boundary fluxes.  Supported values:
    //   uniform          : historical constant U on the open face;
    //   poiseuille_y     : plane-channel parabola across y, using inletUx*
    //                      as cross-section mean velocity;
    //   poiseuille_y_mean: explicit alias of poiseuille_y;
    //   poiseuille_y_max : parabola using inletUx* as centerline velocity.
    // This deliberately affects only the prescribed boundary velocity/flux;
    // it does not change the SRC/MPCD collision model.
    std::string inletVelocitySpatialProfile = "uniform";

    double inletKBT = -1.0;             // negative => use kBT
    double inletThermalNoise = 1.0;     // 0 => deterministic inlet velocity
    std::string inletInjectionMode = "cuda_recycle"; // currently: cuda_recycle/thin_slab/hard_cell_density
    double inletSlabCells = 1.0;        // injected slab thickness in local grid cells
    bool inletRandomizeTangential = true; // randomize transverse coordinate on injection
    bool inletReinjectBackflow = true;  // re-inject particles crossing back through inlet

    // Hard inlet reservoir mode. Unlike periodic wrapping or CUDA-like
    // recycling, an inlet is a thermodynamic reservoir: in hard_cell_density
    // mode the inlet band is rebuilt every step with exactly
    // inletTargetOccupancy particles per active reservoir cell. Particles
    // crossing an outlet or backflowing through an inlet are deleted, so Np is
    // no longer constrained to remain constant in open-boundary runs.
    std::string inletReservoirMode = "recycle"; // recycle/cuda_recycle or hard_cell_density
    int inletReservoirCells = 1;
    int inletTargetOccupancy = 0;       // must be >0 for hard_cell_density; usually gamma
    bool inletHardCellVelocityMean = true;
    bool inletHardCellThermalRescale = true;

    // Optional segmented open-boundary apertures.  When enabled, inlet/outlet
    // particle exchange and Q6/Q9 open-boundary fluxes are restricted to the
    // specified aperture on each face.  The complementary parts of the boundary
    // behave as impermeable solid walls.  Negative high bounds inherit the
    // active-domain high coordinate, preserving the historical full-face
    // inlet/outlet behavior by default.
    bool openBoundaryApertureEnable = false;
    double leftOpenYMin = 0.0;
    double leftOpenYMax = -1.0;
    double rightOpenYMin = 0.0;
    double rightOpenYMax = -1.0;
    double bottomOpenXMin = 0.0;
    double bottomOpenXMax = -1.0;
    double topOpenXMin = 0.0;
    double topOpenXMax = -1.0;

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


    // Analytic immersed solid handled by the compact immersed_solid module.
    // Current shapes: circle and axis-aligned rectangle. Legacy immersedCircle*
    // parameter keys remain accepted as aliases for shape=circle.
    bool immersedSolidEnable = false;
    std::string immersedSolidShape = "circle"; // circle, rectangle
    int immersedSolidFractionSamples = 4;

    // Circle parameters. The center can translate linearly and the local wall
    // velocity can include both center translation and a prescribed rigid
    // rotation through immersedSolidOmega.
    double immersedSolidCx = 0.5;
    double immersedSolidCy = 0.5;
    double immersedSolidR = 0.1;
    double immersedSolidVx = 0.0;     // center/body translation velocity
    double immersedSolidVy = 0.0;
    double immersedSolidWallUx = 0.0; // legacy uniform wall-velocity offset; normally keep zero
    double immersedSolidWallUy = 0.0;
    double immersedSolidOmega = 0.0;  // circle angular velocity, positive counter-clockwise

    // Rectangle parameters. Bounds are axis-aligned at t=0 and translate with
    // immersedSolidVx/Vy. Rotation is intentionally not implemented for the
    // rectangle yet; use Omega=0 for rectangle/backward-step smoke tests.
    double immersedSolidXMin = 0.0;
    double immersedSolidXMax = 0.25;
    double immersedSolidYMin = 0.0;
    double immersedSolidYMax = 0.50;

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
    double q6ProjectionStrength = 1.0; // under-relax Q6 fluid-fluid correction; immersed-solid no-flux remains hard
    bool projectionImmersedSolidMaskEnable = false;
    bool projectionAllowUnmaskedImmersedSolid = false;
    double projectionImmersedSolidFluidFractionThreshold = 0.5;
    bool projectionImmersedSolidCloseCutFaces = true;

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

    // Q9 safeguards for open-boundary domains containing immersed solids.
    // Inactive by default. Required for Q9 + inlet/outlet + immersed solid.
    int q9OpenBoundaryExclusionCells = 0;
    int q9ImmersedSolidHaloCells = 0;
    double q9MinCellMassForCorrection = 0.0;

    // Q9 correction-kick limiter.  The historical absolute limiter is kept for
    // compatibility.  New thermal modes express the cap as a fraction of a
    // reference thermal speed sqrt(kBT), giving a dimensionless safety policy
    // transferable across inlet/outlet cases.
    // Modes: none, absolute, thermal_soft, thermal_hard.
    double q9CorrectionVelocityLimiter = 0.0;
    std::string q9CorrectionLimiterMode = "absolute";
    double q9CorrectionVelocityLimiterOverThermal = 0.0;
    double q9CorrectionLimiterThermalKBT = 0.0; // <=0: use thermostatTargetKBT if positive, else kBT

    // Low-mass Q9 regularization. suppress = historical hard cutoff;
    // ramp_floor = keep Q9 geometrically active and regularize flux-to-velocity conversion.
    std::string q9LowMassTreatment = "suppress"; // suppress, ramp_floor
    double q9MassFloorForCorrection = 0.0;
    double q9LowMassRampStart = 0.0;
    double q9LowMassRampEnd = 0.0;

    // Gamma-relative Q9 low-mass regularization.  Negative values disable the
    // relative form and preserve the absolute legacy parameter above.  When a
    // relative value is provided, the effective absolute threshold is
    // value * q9ReferenceGamma, with q9ReferenceGamma falling back to
    // inletTargetOccupancy for hard-inlet runs.
    double q9ReferenceGamma = 0.0;
    double q9MinCellMassForCorrectionOverGamma = -1.0;
    double q9MassFloorForCorrectionOverGamma = -1.0;
    double q9LowMassRampStartOverGamma = -1.0;
    double q9LowMassRampEndOverGamma = -1.0;


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
    int virialOpenBoundaryExclusionCells = 3; // 0064: skip inlet/outlet reservoir cells in virial EOS/kick

    int summaryEvery = 10;
    int dumpStateEvery = 0;

    // If >0 and OpenMP is enabled, the executable calls omp_set_num_threads(numThreads).
    int numThreads = 0;
};

void validate_simulation_params(const SimulationParams& params);

bool is_x_periodic(const SimulationParams& params);
bool is_y_periodic(const SimulationParams& params);
bool is_solid_wall_mode(const std::string& mode);
bool is_inlet_boundary_mode(const std::string& mode);
bool is_outlet_boundary_mode(const std::string& mode);
bool is_io_boundary_mode(const std::string& mode);
bool has_solid_wall(const SimulationParams& params);
bool has_io_boundary(const SimulationParams& params);

} // namespace mpcd

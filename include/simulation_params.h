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

    // Optional periodic Taylor--Green body acceleration applied before streaming:
    //   ax = A sin(2*pi*m_x*x/Lx) cos(2*pi*m_y*y/Ly)
    //   ay =-A cos(2*pi*m_x*x/Lx) sin(2*pi*m_y*y/Ly)
    // This forcing is divergence-free and has zero spatial mean on a periodic box.
    bool taylorGreenForcingEnable = false;
    double taylorGreenForcingAmplitude = 0.0;
    int taylorGreenForcingModeX = 1;
    int taylorGreenForcingModeY = 1;

    // Optional global mean-flow controller. This is useful for periodic wake
    // tests around immersed solids: it mimics the CUDA VK keepMeanFlow path by
    // applying a spatially uniform velocity shift after the SRC/Q6/thermostat
    // sequence, while preserving relative thermal velocities.
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
    // deliberately remains a particle-only boundary mechanism; Q6
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

    // Optional time ramp for inlet velocities and matching Q6 open-boundary
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
    // Q6 open-boundary fluxes.  Supported values:
    //   uniform          : historical constant U on the open face;
    //   poiseuille_y     : plane-channel parabola across y, using inletUx*
    //                      as cross-section mean velocity;
    //   poiseuille_y_mean: explicit alias of poiseuille_y;
    //   poiseuille_y_max : parabola using inletUx* as centerline velocity;
    //   flat_taper_y      : plug-like profile with a smooth wall taper. inletUx*
    //                      is preserved as the discrete cross-section mean;
    //   flat_taper_y_mean : explicit alias of flat_taper_y.
    // The wall taper is controlled in cells by inletVelocityWallTaperCells.
    // This deliberately affects only the prescribed boundary velocity/flux;
    // it does not change the SRC/MPCD collision model.
    std::string inletVelocitySpatialProfile = "uniform";
    double inletVelocityWallTaperCells = 2.0;

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
    // particle exchange and Q6 open-boundary fluxes are restricted to the
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

    // Q6 outlet treatment for inlet/outlet pairs.
    //   balanced_flux : validated 0062/0063 policy; the outlet projection flux
    //                   is prescribed equal to the ramped inlet flux.
    //   neumann       : outlet correction has zero normal gradient in practice:
    //                   the outlet boundary flux used by Q6 is the current
    //                   local base face flux, while the inlet remains prescribed.
    //                   Segmented aperture complements stay impermeable.
    //   hybrid        : starts from the local Neumann outlet profile, optionally
    //                   blends it toward the balanced-flux profile, then applies
    //                   a weak global outlet-only flux-balance feedback.  This
    //                   is intended for violent slit/nozzle injection tests.
    std::string openBoundaryOutletMode = "balanced_flux";
    double openBoundaryOutletHybridBlend = 0.0;   // 0: pure Neumann local profile, 1: balanced profile
    double openBoundaryOutletFeedbackGain = 0.0;  // 0: off, 1: cancel current projection flux imbalance

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

    // Optional incompressible/projection module. The openMP-resampling baseline
    // keeps only classic SRC/MPCD and Q6 velocity projection active. Q9
    // mass-flux projection and the virial EOS/kick were deliberately removed
    // from this branch to expose a clean core for weighted resampling.
    std::string method = "classic";          // classic, q6
    bool projectionEnable = false;
    std::string projectionOperator = "periodic_fv_cg"; // aliases accepted: channel_fv_cg, auto_fv_cg, elliptic_fv_cg
    int projectionMaxIterations = 300;
    double projectionTolerance = 1.0e-10;
    bool q6WarmStartEnable = true; // reuse previous elliptic potential as CG initial guess
    bool q6ReuseProjectedDivergenceDiagnostics = true; // skip redundant cell-divergence reconstruction
    bool projectionMomentumCorrectionEnable = true;
    double q6ProjectionStrength = 1.0; // under-relax Q6 fluid-fluid correction; immersed-solid no-flux remains hard
    bool projectionImmersedSolidMaskEnable = false;
    bool projectionAllowUnmaskedImmersedSolid = false;
    double projectionImmersedSolidFluidFractionThreshold = 0.5;
    bool projectionImmersedSolidCloseCutFaces = true;

    // Weighted-resampling diagnostic target.  A non-positive value means that
    // the current mean real-fluid cell mass is used as the reference, so the
    // diagnostic measures relative cell-to-cell dispersion without imposing a
    // prescribed mass yet.  The recycling/remap core will use this field as the
    // physical target in later patches.
    double resamplingTargetCellMass = 0.0;

    // Passive wet/dry and poor/rich cell classification prepared for the
    // extraction/insertion resampling core.  active_domain is the safe default
    // for bulk/channel tests: empty cells inside the active fluid domain are
    // flagged as poor void pockets, not ignored as dry free-surface cells.
    // occupied is reserved for later free-surface/injection tests where empty
    // cells should remain dry/latent.
    std::string resamplingWetMaskMode = "active_domain"; // active_domain, occupied
    double resamplingWetCellMassThreshold = 0.0;
    double resamplingPoorCellMassFraction = 0.5;
    double resamplingRichCellMassFraction = 1.5;
    double resamplingActiveFluidFractionThreshold = 0.5;

    // Mutating weighted-resampling controls.  The top-level
    // resamplingEnable switch gates all role-changing operations so a run can
    // return to pure classic SRC/Q6 while keeping diagnostic columns and even
    // individual sub-switches present in params.kv.
    //
    // Discrete resampling is intended to run every step when enabled:
    //   Fluid -> Inactive  extraction from rich donor cells;
    //   Inactive -> Fluid  insertion into poor receiver cells;
    //   Latent -> Fluid    optional wet/dry activation.
    //
    // Mass renormalisation is deliberately cadenced by
    // resamplingMassRenormalizationPeriod.  K=1 reproduces the historical
    // behaviour, K>1 applies remap/mass-guard every K steps, and K=0 disables
    // the mass renormalisation stages even if their sub-switches are true.
    // Thermal renormalisation remains a per-step correction when enabled.
    bool resamplingEnable = false;
    bool resamplingExtractionEnable = false;
    bool resamplingInsertionEnable = false;
    bool resamplingRemapEnable = false;
    bool resamplingThermalRenormalizationEnable = false;
    int resamplingMassRenormalizationPeriod = 1;

    // Optional particle-mass guard applied on mass-renormalisation steps after
    // the local remap.  It solves a bounded per-cell mass projection so
    // mMin <= m_p <= mMax and sum_p m_p = M_target whenever feasible, then
    // recenters/rescales velocities so the cell velocity and relative thermal
    // energy are restored.
    bool resamplingMassGuardEnable = false;
    double resamplingParticleMassMin = 0.25;
    double resamplingParticleMassMax = 4.0;

    // Optional latent-particle activation for wet/dry filling.  Latent slots
    // are preallocated particles that are ignored by all dynamics until they
    // are explicitly activated.  This switch seeds poor/empty wet receiver
    // cells by converting Latent -> Fluid without touching Inactive free slots.
    bool resamplingLatentActivationEnable = false;
    int resamplingLatentActivationMaxPerCell = 1;
    double resamplingLatentActivationParticleMass = 0.0; // <=0: targetCellMass / maxPerCell

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

#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "species_registry.h"

namespace mpcd {

struct OpenBoundarySegment {
    std::string face;   // left/right/bottom/top
    std::string mode;   // inlet/outlet
    double sMin = 0.0;  // relative tangent coordinate in [0,1]
    double sMax = 0.0;  // relative tangent coordinate in [0,1]
    double ux = 0.0;    // prescribed inlet velocity component; ignored by outlet
    double uy = 0.0;    // prescribed inlet velocity component; ignored by outlet
    std::uint32_t type = 0u;
    double mass = 1.0;
};

struct SimulationParams {
    // 0490a multiphase scaffold. Disabled by default, so legacy parameter files
    // and trajectories are unchanged. Each declaration uses:
    //   speciesK = type name phaseFamily q6StrengthDeclared massClosureStrengthDeclared [referenceCellMassDeclared]
    //   speciesKResamplingEnable = true|false  (default: true)
    // The Q6 strength remains declarative in 0490d. The mass-closure strength
    // and reference cell mass become active only when
    // speciesResamplingMassClosureEnable=true.
    bool speciesRegistryEnable = false;
    int speciesCount = 0;
    std::vector<SpeciesDefinition> speciesDefinitions;
    bool speciesRequireRegisteredTypes = false;
    bool speciesDiagnosticsEnable = false;
    std::string speciesDiagnosticsFilename = "species_runtime_0490a.csv";

    // 0490b opt-in dense CPU reference deposit on the physical, unshifted
    // grid. This is a diagnostic/scaffolding path only.
    bool speciesCellDiagnosticsEnable = false;
    std::string speciesCellDiagnosticsFilename = "species_cell_runtime_0490b.csv";

    // 0493x6a projection-variable contract: the CUDA Q6 scalar phi is a
    // pressure potential, not an absolute thermodynamic pressure.  The discrete
    // solve is Laplacian(phi) = -div(u*) and the particle correction is
    // du = -grad(phi), hence for a constant-density incompressible phase
    // phi = dt * p / rho_ref up to the usual gauge constant.  A later
    // phase-coupled interface condition must convert gas pressure/stress to this
    // variable before inserting it into the Q6 operator.
    //
    // 0491a/0493w5 species-sensitive Q6 contract.
    //   common / weighted: one barycentric mixture solve, legacy 0491 path.
    //   independent_masked: one masked solve per species with q6Strength>0;
    //     q6Strength=0 guarantees no direct Q6 correction.  The support is
    //     selected from the relative species occupancy.
    //   free_surface_masked (0493x5a): one projected liquid species in a
    //     static closed box.  Its support is selected from the absolute fill
    //     proxy mass/referenceCellMass and inactive neighbours impose p=0.
    // The CPU Q6 fallback still rejects species Q6 to avoid a silent change of
    // operator. independent_masked remains CUDA-resident and follows every
    // boundary topology already accepted by the resident Q6 backend.
    bool speciesQ6Enable = false;
    std::string speciesQ6Mode = "common"; // common, weighted, independent_masked, free_surface_masked
    double speciesQ6Sensitivity = 0.0;
    double speciesQ6AlphaEpsilon = 1.0e-14;
    std::string speciesQ6FallbackMode = "common"; // common, fatal; legacy weighted only
    double speciesQ6ComparisonTolerance = 1.0e-11;
    double speciesQ6MinOccupancyFraction = 0.5;

    // 0490h opt-in resident CUDA deposit of N_{c,s}, M_{c,s}, P_{c,s}
    // and composition fractions. The resident workspace is the production
    // foundation for later species-aware CUDA resampling and Q6. In 0490h,
    // host download is diagnostic-only and compared against the 0490b CPU
    // reference at summary steps.
    bool speciesCellCudaDepositEnable = false;
    std::string speciesCellCudaComparisonFilename =
        "species_cell_cuda_equivalence_0490h.csv";
    double speciesCellCudaComparisonTolerance = 1.0e-11;
    int speciesCellCudaThreadsPerBlock = 256;

    // 0490d opt-in phase-aware mass closure. The local closure strength and
    // local target mass are reconstructed from the registered species using
    // occupancy proxies m_s / referenceCellMass_s. All particle masses in a
    // cell receive the same scale, so the local composition is preserved.
    // The first implementation is CPU-authoritative and deliberately excludes
    // the legacy particle-mass guard and closed-capacity override.
    bool speciesResamplingMassClosureEnable = false;

    // 0490i opt-in resident CUDA implementation of the 0490d closure. The
    // 0490h species-cell workspace provides M_{c,s} and occupancy weights;
    // 0490i builds the local target/strength and scales particle masses entirely
    // on device. The host download is retained only to keep the existing CPU
    // diagnostics/post-deposit path coherent. Thermal renormalization remains a
    // separate later CUDA milestone and is therefore excluded in 0490i.
    bool speciesResamplingMassClosureCudaEnable = false;
    std::string speciesMassClosureCudaDiagnosticsFilename =
        "cuda_species_mass_closure_0490i.csv";
    double speciesMassClosureCudaComparisonTolerance = 1.0e-11;

    // 0490e opt-in species-aware selection inside the CPU population support
    // guard. The total Nmin/Ntarget/Nmax policy is unchanged; only the species
    // selected for split/merge is chosen from a deterministic per-cell target
    // composition reconstructed from M_s/referenceCellMass_s.
    bool speciesResamplingPopulationGuardEnable = false;

    // 0490j resident CUDA backend for the 0490e species-aware population
    // policy. The legacy total Nmin/Ntarget/Nmax band remains authoritative;
    // 0490j only selects the species used for each local split/merge. The
    // existing 0297 active-prefix mutation path performs the conservative edit.
    bool speciesResamplingPopulationGuardCudaEnable = false;

    // 0490f opt-in CUDA empty-cell composition memory. When enabled, the
    // resident refill stores M_{c,s} for every registered species and restores
    // a temporarily empty mixed cell with the remembered per-species masses.
    // Species-wise global mass/momentum correction is used after refill.
    bool cudaResamplingEmptyRefillSpeciesCompositionEnable = false;

    // 0490g opt-in species-constrained donor/receiver transfer planning.
    // Each non-empty poor receiver apportions its mass deficit over the species
    // it already contains. Rich donors expose proportional excess per species,
    // and transfer entries may only select particles of the matching type.
    // The planner remains CPU-authoritative; CUDA extraction/insertion may apply
    // the resulting explicit operations without changing their species.
    bool speciesResamplingTransferEnable = false;

    // 0490k native CUDA species donor/receiver planner. The 0490g CPU plan is
    // retained as a strict equivalence mirror during this gate patch; on PASS,
    // the GPU-built plan becomes authoritative for downstream mutation.
    bool speciesResamplingTransferCudaEnable = false;
    std::string speciesTransferCudaDiagnosticsFilename =
        "cuda_species_transfer_plan_0490k.csv";
    double speciesTransferCudaComparisonTolerance = 1.0e-11;

    // 0490l strict resident validation gate. When enabled, the 0490g CPU
    // transfer plan and the CPU passive-operation mirror are deliberately
    // skipped. The native 0490k CUDA plan, the 0453 CUDA materializer and the
    // 0448 CUDA particle-edit backend become authoritative. Any required CPU
    // fallback is a fatal error. This remains the detailed equivalence/audit
    // mode and may retain compact host diagnostics.
    bool speciesResamplingCudaResidentValidationEnable = false;

    // 0490m production resident fast path. The native 0490k plan remains on
    // device and is consumed directly by the 0490m species-aware CUDA
    // materialize+apply backend. No CPU transfer plan, CPU passive operation
    // vector, plan-array D2H/H2D round trip, full particle-state rollback copy,
    // or full-state download is permitted. Only a compact patchback for the
    // particles actually moved is downloaded so legacy host diagnostics and
    // the remaining CPU orchestration stay coherent during this transition.
    bool speciesResamplingCudaResidentFastPathEnable = false;
    std::string speciesCudaResidentFastPathDiagnosticsFilename =
        "cuda_species_resident_fast_path_0490m.csv";

    // 0490n integrated resident maintenance. The legacy weighted real-fluid
    // particle scan and resampling-pool rebuild are replaced by CUDA scans of
    // the shared particle state. The two components remain separately
    // switchable for staged validation; strict mode requires both and forbids
    // every CPU maintenance fallback.
    bool speciesResamplingCudaResidentDepositsEnable = false;
    bool speciesResamplingCudaResidentPoolEnable = false;
    bool speciesResamplingCudaResidentMaintenanceStrict = false;
    std::string speciesCudaResidentMaintenanceDiagnosticsFilename =
        "cuda_species_resident_maintenance_0490n.csv";

    std::string inputState;
    std::string outputDir = "run_base";

    // 0417: restart-friendly inactive reservoir.
    // After reading inputState, ensure that at least this many Inactive slots
    // exist in the storage tail.  This lets compact fluid-only dumps be used
    // as restart states for inlet/outlet or resampling paths that need a free
    // particle pool, without storing the inactive tail in every .smpcd file.
    std::uint64_t initialInactiveSlots = 0u;

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

    // 0493x3/0493x4a/0493x4b experimental force/projection ordering. legacy
    // preserves the historical kick-and-drift before Q6. prestream applies a
    // force kick and Q6 before streaming while retaining the post-collision Q6.
    // prestream_single omits the second Q6. prestream_single_fused additionally
    // folds the tentative-force deposit and the final force+Q6 velocity update
    // into the resident Q6 CUDA pass, removing the standalone force-kick kernel.
    std::string q6ForceProjectionMode = "legacy"; // legacy, prestream, prestream_single, prestream_single_fused

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

    // Compact relative open-boundary segments.  When enabled, partial inlet/outlet
    // regions are declared as one line per segment:
    //   openBoundarySegmentK = face mode sMin sMax ux uy type mass
    // with face in {left,right,bottom,top}, mode in {inlet,outlet}, and sMin/sMax
    // the relative tangent-coordinate interval in [0,1].  Portions of a segmented
    // face not covered by a segment remain impermeable solid wall.  The former
    // openBoundaryApertureEnable + leftOpenYMin/... path was removed deliberately
    // in 0143 to avoid ambiguous mixed configurations.
    bool openBoundarySegmentsEnable = false;
    int openBoundarySegmentCount = 0;
    std::vector<OpenBoundarySegment> openBoundarySegments;

    // Q6 outlet treatment for inlet/outlet pairs.
    //   balanced_flux : validated 0062/0063 policy; the outlet projection flux
    //                   is prescribed equal to the ramped inlet flux.
    //   neumann       : passive pressure outlet.  Q6-G-F extrapolates the
    //                   current boundary-cell normal velocity to the base
    //                   outlet face (zero normal gradient of predictor velocity),
    //                   while the projection uses phi=0 at that open face and
    //                   is therefore free to adjust the final outlet flux.
    //                   The inlet remains prescribed; segmented aperture
    //                   complements remain impermeable.
    //   hybrid        : starts from the local Neumann outlet profile, optionally
    //                   blends it toward the balanced-flux profile, then applies
    //                   a weak global outlet-only flux-balance feedback.  This
    //                   is intended for violent slit/nozzle injection tests.
    std::string openBoundaryOutletMode = "balanced_flux";
    double openBoundaryOutletHybridBlend = 0.0;   // 0: pure Neumann local profile, 1: balanced profile
    double openBoundaryOutletFeedbackGain = 0.0;  // 0: off, 1: cancel current projection flux imbalance

    // CUDA SRC classic outlet regimes for particle reservoirs. These options
    // only affect the particle-level inlet/outlet path; Q6 outlet handling keeps
    // its own projection semantics.
    //   neumann          : zero-normal-gradient open boundary. Particles that
    //                      cross outward are deleted, while the resident CUDA
    //                      path supplies the inward kinetic half-space flux by
    //                      sampling an independent local kinetic bath reconstructed from adjacent interior moments.
    //                      This is the particle counterpart of the local Q6/Q6-G-F
    //                      Neumann face extrapolation, not an absorbing vacuum.
    //   equilibrium_flux : after natural outlet deletion, delete extra particles
    //                      in the outlet layer to cancel the current net inlet
    //                      particle gain. This is convenient, but coupled to inlet.
    //   forced_flux      : delete a user-prescribed mass/particle flux from the
    //                      outlet layer, independent of inlet. This is the mode
    //                      intended for suction/drainage tests.
    double openBoundaryOutletForcedMassFlux = 0.0;       // mass per unit time; target per step = flux*dt
    double openBoundaryOutletForcedMassPerStep = 0.0;    // optional direct mass per step override
    double openBoundaryOutletForcedParticleFlux = 0.0;   // particles per unit time; target per step = flux*dt
    int openBoundaryOutletForcedParticlesPerStep = 0;    // optional direct particle-count override
    int openBoundaryOutletForcedLayerCells = 1;          // outlet suction layer thickness in grid cells

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

    // Optional explicit classic-SRC mode.  When true, the time-step driver
    // keeps the particle SRC/MPCD dynamics but short-circuits the
    // incompressible closure stages (Q6/Q9 projection and closed-capacity
    // virial kick), even if their historical parameter blocks are present in
    // a validation file.  This is intended as a durable, runtime-selectable
    // classic CUDA SRC mode inside the incompressible codebase.
    bool srcClassicCudaModeEnable = false;

    // Optional incompressible/projection module.  Q6 is controlled only by
    // projectionEnable, unless srcClassicCudaModeEnable=true short-circuits
    // it at the step-driver level.  The former method=classic/q6 switch was
    // removed in 0144 to avoid redundant or contradictory configurations.
    bool projectionEnable = false;
    std::string projectionOperator = "periodic_fv_cg"; // aliases accepted: channel_fv_cg, auto_fv_cg, elliptic_fv_cg

    // Prototype backend selector for the Q6/elliptic projection path on the
    // SRC_GPU branch.  The default CPU backend preserves the validated
    // OpenMP-light behaviour.  CUDA support is intentionally incremental:
    //   cpu  : always use the existing OpenMP CPU implementation;
    //   auto : explicit CPU fallback for full simulations;
    //   cuda : patch 0188 wires only the fully periodic, unmasked Q6 subset
    //          in a CUDA-enabled executable. Unsupported geometries fail
    //          explicitly rather than falling back silently.
    std::string projectionBackend = "cpu";

    int projectionMaxIterations = 300;
    double projectionTolerance = 1.0e-10;
    bool projectionMomentumCorrectionEnable = true;
    double q6ProjectionStrength = 1.0; // under-relax Q6 fluid-fluid correction; immersed-solid no-flux remains hard

    // 0493x7b: continuum virial/EOS density-restoring kick on the CUDA-resident
    // free-surface Q6-G path.  kVirial is a continuum stiffness with code units
    // of velocity^2 in Pvir/rhoRef = kVirial*(rawFill-1); the finite-volume
    // gradient carries the physical 1/dx,1/dy factors.  Therefore kVirial must
    // NOT be rescaled with Nx/Ny when the same physical domain is refined.
    // betaEOS is dimensionless.  The selected K32 calibration remains disabled
    // by default, preserving all pre-virial paths as strict no-ops.
    bool virialDensityKickEnable = false;
    double kVirial = 0.10666666666666667;
    double betaEOS = 0.05;
    bool virialMomentumCorrectionEnable = true;

    // 0493x7c/x7d: density-error relaxation embedded directly in the Q6
    // projection constraint.  Zero is an exact no-op.  x7d makes the physical
    // relaxation time tau the preferred parameter:
    //     div(u_projected) = (rawFill - 1) / tau
    // with betaPerStep = dt/tau.  q6DensityRelaxationBeta is retained as the
    // legacy per-step input for backward compatibility; the two inputs are
    // mutually exclusive when positive.
    double q6DensityRelaxationBeta = 0.0;
    double q6DensityRelaxationTime = 0.0;

    // 0493x9d: physical 2-D surface tension used only by the Q6-G-F
    // free-surface Dirichlet jump p_A - p_B = sigma*kappa.  Code units are
    // pressure*length.  Zero is an exact no-op and preserves the pre-x9d path.
    double surfaceTensionSigma = 0.0;

    // 0493x9g: phase-pair abstraction for the resident interface geometry.
    // Defaults reproduce the qualified liquid/gas path exactly.  Selectors are
    // canonicalized by the parser and may be:
    //   family:liquid | family:gas | family:dispersed | family:unspecified
    //   type:<uint32> | vacuum | wall
    // 0493x9h activates `wall` as a geometry-provider selector.  It does not
    // reinterpret a wall as an x6f pressure Dirichlet boundary and does not yet
    // apply a liquid/solid capillary jump: surfaceTensionSigma must remain zero
    // for B=wall until the contact-angle/interfacial-energy closure is added.
    // The wall provider automatically composes (i) static domain wall faces and
    // (ii) an existing Darcy chi field only when chi collision wallVP is enabled.
    // Darcy convention is chi=1 fluid, chi=0 solid, hence solidFraction=1-chi.
    // Phase A owns alpha>=0.5, curvature orientation and the projected Q6 side.
    // Particle phase B remains the exterior pressure source for x6g EOS.
    std::string phaseInterfaceASelector = "family:liquid";
    std::string phaseInterfaceBSelector = "family:gas";

    // 0493x7d-v2 experimental compression/noise discriminator. Disabled by
    // default: false preserves the historical rawFill x7d target bit-for-bit.
    // When enabled, positive density relaxation is admitted only when the
    // center defect and at least one direct face-neighbour exceed the same
    // fill threshold. The Q6-G-F runner writes thetaN/GAMMA here.
    bool q6DensityRelaxationCompressionGateEnable = false;
    double q6DensityRelaxationCompressionThresholdFill = 0.0;

    // 0493x7d-v2-signed1 experimental traction/depression branch.  No extra
    // enable flag: gain=0 is an exact no-op.  When gain>0, a negative density
    // defect is admitted only when the center and at least one direct
    // face-neighbour are below -q6DensityRelaxationTractionThresholdFill.
    // Once classified, the full negative defect is used and multiplied by
    // q6DensityRelaxationTractionGain.
    double q6DensityRelaxationTractionThresholdFill = 0.0;
    double q6DensityRelaxationTractionGain = 0.0;

    bool projectionImmersedSolidMaskEnable = false;
    bool projectionAllowUnmaskedImmersedSolid = false;
    double projectionImmersedSolidFluidFractionThreshold = 0.5;
    bool projectionImmersedSolidCloseCutFaces = true;

    // Closed-domain capacity response.  Disabled by default, so all previously
    // validated open-channel, Poiseuille, Taylor--Green and resampling cases keep
    // their historical behaviour.  When enabled, the code measures the excess
    // mass above N_fluid_cells * referenceCellMass and uses this continuous
    // overfill ratio to attenuate Q6, strengthen a virial pressure kick and
    // weaken the incompressible mass-remap stage.
    bool closedCapacityResponseEnable = false;
    double closedCapacityReferenceCellMass = 0.0;      // <=0: infer from resamplingTargetCellMass or inletTargetOccupancy
    double closedCapacityReferenceParticleMass = 1.0;  // used only when inferring from inletTargetOccupancy
    double closedCapacityQ6Eta = 0.005;
    double closedCapacityQ6Power = 2.0;
    double closedCapacityMassRemapEta = 0.005;
    double closedCapacityMassRemapPower = 2.0;
    bool closedCapacityMassGuardDisableOnOverfill = true;
    bool closedCapacityVirialKickEnable = false;
    double closedCapacityVirialBaseK = 0.0;
    double closedCapacityVirialGain = 20.0;
    double closedCapacityVirialEta = 0.005;
    double closedCapacityVirialPower = 2.0;
    double closedCapacityVirialKickStrength = 1.0;
    bool closedCapacityVirialMomentumCorrectionEnable = true;
    bool closedCapacityInletMassFluxEnable = false;
    double closedCapacityInletMassFluxMultiplier = 1.0;

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

    // Population-support guard matching the MATLAB weighted-resampling logic.
    // In 0144 this guard is no longer controlled by a separate boolean:
    // resamplingEnable=true means that the population-driven support guard is
    // active.  The thresholds below set its target band.  Non-positive N
    // thresholds are inferred from the current target cell mass and mean active
    // particle mass; with m≈1 this gives the MATLAB default 14/20/26 for
    // gamma=20.
    int resamplingPopulationNMin = 0;
    int resamplingPopulationNTarget = 0;
    int resamplingPopulationNMax = 0;
    double resamplingPopulationNMinFraction = 0.70;
    double resamplingPopulationNMaxFraction = 1.30;
    int resamplingPopulationMaxSplitsPerCell = 16;
    int resamplingPopulationMaxSplitsPerStep = 200000;
    int resamplingPopulationMaxExtractionsPerCell = 64;
    int resamplingPopulationMaxExtractionsPerStep = 200000;

    // CUDA 0297 empty-cell refill. This CUDA-resident block is separate from
    // the legacy CPU weighted-resampling switch: empty wet cells are reseeded
    // from inactive slots using the last valid local cell moments kept on
    // device. The refill target is round(fraction * reference), with reference
    // in {nTarget,gamma}. A non-positive gamma falls back to
    // resamplingTargetCellMass, then to nTarget.
    bool cudaResamplingEmptyRefillEnable = false;
    double cudaResamplingEmptyRefillTargetFraction = 0.5;
    std::string cudaResamplingEmptyRefillReference = "ntarget";
    int cudaResamplingEmptyRefillGamma = 0;
    int cudaResamplingEmptyRefillMemoryMaxAge = 1000;

    // Darcy/topology compatibility guard for CUDA 0296/0297/refill. When Darcy
    // is enabled, cells with chi below cudaResamplingChiMin are excluded from
    // mass reconditioning, split/merge and empty-refill memory/update/creation.
    bool cudaResamplingChiFilterEnable = true;
    double cudaResamplingChiMin = 0.5;


    // 0343/topo: pure Brinkman/Darcy penalization for SRC classic CUDA-VIZ.
    // The design variable convention is chi=1 fluid, chi=0 solid/porous.
    // alpha(chi)=alphaMin+(alphaMax-alphaMin)*q*(1-chi)/(q+chi).
    // This first topo branch intentionally keeps full Brinkman population and
    // does not couple to chi-aware resampling or Q6 CUDA yet.
    bool darcyBrinkmanEnable = false;
    std::string darcyChiMode = "uniform"; // uniform, circle/cylinder, box/rectangle, file
    double darcyUniformChi = 1.0;
    std::string darcyChiFile;
    int darcyChiNx = 0;
    int darcyChiNy = 0;
    std::string darcyChiFileFormat = "float32"; // float32 or float64, row-major iy*Nx+ix
    double darcyAlphaMin = 0.0;
    double darcyAlphaMax = 0.0;
    double darcyQ = 0.1;
    double darcyUSolidX = 0.0;
    double darcyUSolidY = 0.0;
    double darcyCircleCx = 0.5;
    double darcyCircleCy = 0.5;
    double darcyCircleR = 0.1;
    double darcyBoxXMin = 0.0;
    double darcyBoxXMax = 0.0;
    double darcyBoxYMin = 0.0;
    double darcyBoxYMax = 0.0;
    double darcyInterfaceWidth = 0.0;
    int darcyCostEvery = 0;
    std::string darcyCostFilename = "darcy_cost_0343.csv";
    int darcyThreadsPerBlock = 256;

    // 0418/topo: optional chi-solid cleanup at load time and an alternative
    // Brinkman forcing mode that mimics a thermal wall bath without explicit
    // persistent wall virtual particles.  The default keeps the historical
    // mean-velocity Darcy kick unchanged.
    double darcyInitialDeactivateBelowChi = -1.0; // <0 disabled; otherwise Fluid->Inactive for chi<threshold at load/restart
    std::string darcyBrinkmanForcingMode = "mean"; // mean/classic, thermal_bath/langevin, outward_bath, or mean_outward_bath

    // 0422/topo: lightweight chi-derived virtual particle contribution for the
    // SRC collision center of mass. This is an effective cell-moment model: no
    // persistent virtual particles are created, streamed, compacted or dumped.
    bool darcyChiCollisionVpEnable = false;
    std::string darcyChiCollisionVpMode = "interface_band"; // interface_band only in 0422
    double darcyChiCollisionVpGamma = -1.0; // <=0: wallVpGamma, then inferred active-fluid gamma
    double darcyChiCollisionVpMass = 1.0;
    int darcyChiCollisionVpLayers = 1;
    double darcyChiCollisionVpThreshold = 0.5;
    double darcyChiCollisionVpStrength = 1.0;

    // 0348/topo: optional benchmark observables.  These are disabled by
    // default to preserve the CUDA resident path.  The 0348a implementation is
    // cell-based only: no extra particle pass and no section/profile binning.
    bool topoBenchmarkEnable = false;
    int topoBenchmarkEvery = 0; // <=0: use darcyCostEvery
    std::string topoBenchmarkFilename = "topo_benchmark_0348.csv";
    bool topoBenchmarkForceEnable = true;
    bool topoBenchmarkDragLiftEnable = true;
    double topoBenchmarkFlowDirX = 1.0;
    double topoBenchmarkFlowDirY = 0.0;
    double topoBenchmarkLiftDirX = 0.0;
    double topoBenchmarkLiftDirY = 1.0;

    int summaryEvery = 10;
    int dumpStateEvery = 0;

    // 0314: optional compact runtime summaries and dumps for CUDA-resident
    // runs with large Inactive reservoirs.  The default "all" preserves
    // legacy restart-compatible dumps and full-state summaries.  "fluid"
    // writes/uses only role=Fluid particles for visualization/diagnostics,
    // avoiding work proportional to large inactive tails when the CUDA state is
    // resident and fresh.
    std::string dumpRoleFilter = "all";      // all | fluid
    std::string summaryRoleFilter = "all";   // all | fluid

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

function params = build_tranche2_params(overrides)
%BUILD_TRANCHE2_PARAMS Complete params struct for tranche 2 (zone pass).
%
% params = build_tranche2_params()
% params = build_tranche2_params(overrides)
%
% The returned struct is complete for the strict C++ reader. Tranche 2 is
% restricted to fixed-volume liquid-flow cases:
%   - noSurfaceCase = true
%   - no wall_wetting
%   - no interface velocity reorientation
%   - no piston / no moving boundaries
%   - redistribution strictly intra-zone during one pass

if nargin < 1
    overrides = struct();
end
assert(isstruct(overrides) && isscalar(overrides), 'overrides must be a scalar struct.');

params = struct();

% Domain / grid
params.Nx = 50;
params.Ny = 50;
params.Lx = 10.0;
params.Ly = 10.0;
params.Nc = params.Nx * params.Ny;

% MPCD / generic step parameters (kept explicit although step02 only uses a subset)
params.gamma = 20.0;
params.n = round(params.gamma * params.Nc);
params.dt = 5e-3;
params.a0 = params.Lx / params.Nx;
params.alpha = deg2rad(170.0);
params.kBT = 1.0;
params.g = 0.0;
params.bodyForceX = 0.0;
params.useThermostat = true;
params.keepMeanFlow = false;

% Boundary conditions
params.boundary_left = 'specular';
params.boundary_right = 'specular';
params.boundary_bottom = 'specular';
params.boundary_top = 'specular';
params.Utop = 0.0;
params.Ubottom = 0.0;
params.wallSigma = sqrt(max(params.kBT, 0.0));

% Fixed hypotheses for tranche 2
params.noSurfaceCase = true;
params.redistributionEnableSurfaceTopology = false;
params.redistributionWallWettingEnabled = false;
params.useInterfaceVelocityReorientation = false;

% Redistribution by zones
params.useIncompressibleRedistribution = true;
params.redistribAfterCollision = true;
params.useZoneRedistribution = true;
params.zoneTileNx = 16;
params.zoneTileNy = 16;
params.zoneUseShiftedSecondPass = true;
params.zonePassthroughMode = false;
params.zoneSingleFullDomainMode = false;
params.enableMomentumCorrectionPostRedistribution = true;
params.coef = 0.20;
params.highMode = 'coef';
params.lowMode = 'coef';
params.maxRedistribPasses = 2;
params.useLocalFluidFractionThresholds = false;
params.fluidFracGain = 0.8;
params.lowThrFloor = 20.0;
params.highThrFloor = 25.0;
params.lowThrBulkOverride = NaN;

% Liquid closure kept explicit for future steps
params.useLiquidClosure = false;
params.useOptimalBetaRepair = true;
params.betaRepair = 0.0;
params.betaEOS = 1.0;
params.Kvirial = 0.0;
params.smoothPdriveAtInterzone = false;
params.smoothPdriveInterzoneWidthCells = 1;
params.smoothPdriveInterzoneBlend = 1.0;
params.smoothPdriveIncludeShiftedLayouts = true;

fn = fieldnames(overrides);
for k = 1:numel(fn)
    params.(fn{k}) = overrides.(fn{k});
end

params.Nc = params.Nx * params.Ny;
params.a0 = params.Lx / params.Nx;
if ~isfield(overrides, 'n')
    params.n = round(params.gamma * params.Nc);
end
if ~isfield(overrides, 'wallSigma')
    params.wallSigma = sqrt(max(params.kBT, 0.0));
end
end

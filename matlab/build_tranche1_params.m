function params = build_tranche1_params(overrides)
%BUILD_TRANCHE1_PARAMS Build a complete params struct for the tranche-1 C++ core.
%
% params = build_tranche1_params()
% params = build_tranche1_params(overrides)
%
% The returned struct is complete for the strict C++ reader: all fields
% expected by Params are explicitly present. The core itself has no
% fallbacks; this helper is only a MATLAB-side convenience to prepare a
% coherent starting configuration.
%
% Example:
%   params = build_tranche1_params();
%   params.boundary_left = 'periodic';
%   params.boundary_right = 'periodic';
%   params.bodyForceX = 0.05;
%
%   params = build_tranche1_params(struct( ...
%       'Nx', 64, 'Ny', 64, 'gamma', 20, ...
%       'boundary_left', 'periodic', 'boundary_right', 'periodic'));

if nargin < 1
    overrides = struct();
end
assert(isstruct(overrides) && isscalar(overrides), ...
    'overrides must be a scalar struct.');

params = struct();

% -------------------------------------------------------------------------
% Domain / grid
% -------------------------------------------------------------------------
params.Nx = 50;
params.Ny = 50;
params.Lx = 10.0;
params.Ly = 10.0;
params.Nc = params.Nx * params.Ny;

% -------------------------------------------------------------------------
% MPCD
% -------------------------------------------------------------------------
params.gamma = 10.0;
params.n = round(params.gamma * params.Nc);
params.dt = 5e-3;
params.a0 = params.Lx / params.Nx;
params.alpha = deg2rad(170.0);
params.kBT = 1.0;
params.g = 0.0;
params.bodyForceX = 0.0;
params.useThermostat = true;
params.keepMeanFlow = false;

% -------------------------------------------------------------------------
% Boundary conditions
% Supported in tranche 1: periodic, thermalize, bounceback, specular
% -------------------------------------------------------------------------
params.boundary_left = 'specular';
params.boundary_right = 'specular';
params.boundary_bottom = 'specular';
params.boundary_top = 'specular';
params.Utop = 0.0;
params.Ubottom = 0.0;
params.wallSigma = sqrt(max(params.kBT, 0.0));

% -------------------------------------------------------------------------
% Hypotheses fixed for the current C++ development
% -------------------------------------------------------------------------
params.noSurfaceCase = true;
params.redistributionEnableSurfaceTopology = false;
params.redistributionWallWettingEnabled = false;
params.useInterfaceVelocityReorientation = false;

% -------------------------------------------------------------------------
% Redistribution (kept explicit even if tranche 1 does not use everything)
% -------------------------------------------------------------------------
params.useIncompressibleRedistribution = true;
params.redistribAfterCollision = true;
params.useZoneRedistribution = true;
params.zoneTileNx = 32;
params.zoneTileNy = 32;
params.zoneUseShiftedSecondPass = true;
params.zonePassthroughMode = false;
params.zoneSingleFullDomainMode = false;
params.enableMomentumCorrectionPostRedistribution = true;
params.coef = 0.20;
params.highMode = 'coef';
params.lowMode = 'coef';
params.maxRedistribPasses = 2;
params.useLocalFluidFractionThresholds = true;
params.fluidFracGain = 0.8;
params.lowThrFloor = 20.0;
params.highThrFloor = 25.0;
params.lowThrBulkOverride = NaN;

% -------------------------------------------------------------------------
% Liquid closure
% -------------------------------------------------------------------------
params.useLiquidClosure = true;
params.useOptimalBetaRepair = true;
params.betaRepair = 0.0;
params.betaEOS = 1.0;
params.Kvirial = 0.0;
params.smoothPdriveAtInterzone = false;
params.smoothPdriveInterzoneWidthCells = 1;
params.smoothPdriveInterzoneBlend = 1.0;
params.smoothPdriveIncludeShiftedLayouts = true;

% -------------------------------------------------------------------------
% Apply user overrides
% -------------------------------------------------------------------------
fn = fieldnames(overrides);
for k = 1:numel(fn)
    params.(fn{k}) = overrides.(fn{k});
end

% -------------------------------------------------------------------------
% Recompute derived quantities after overrides on core geometry / gamma
% -------------------------------------------------------------------------
params.Nc = params.Nx * params.Ny;
params.a0 = params.Lx / params.Nx;
if ~isfield(overrides, 'n')
    params.n = round(params.gamma * params.Nc);
end
if ~isfield(overrides, 'wallSigma')
    params.wallSigma = sqrt(max(params.kBT, 0.0));
end
end

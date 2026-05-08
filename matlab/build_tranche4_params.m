function params = build_tranche4_params(overrides)
%BUILD_TRANCHE4_PARAMS Complete params struct for tranche 4 (liquid closure only).
if nargin < 1
    overrides = struct();
end
assert(isstruct(overrides) && isscalar(overrides), 'overrides must be a scalar struct.');

params = build_tranche2_params();

params.useLiquidClosure = true;
params.useOptimalBetaRepair = true;
params.betaRepair = 0.0;
params.betaEOS = 1.0;
params.Kvirial = 5.0;
params.smoothPdriveAtInterzone = true;
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

function prep = prepare_poiseuille_viz_case(overrides)
%PREPARE_POISEUILLE_VIZ_CASE Single-entry Poiseuille preparation script.
%
% This script replaces the chained workflow
% build_benchmark_poiseuille_params_equal -> build_tranche5 -> build_tranche4
% -> build_tranche2 -> prepare_*.m for the current Poiseuille/OpenMP/viz
% branch.
%
% It does, in one place:
%   1. complete params construction;
%   2. one single override pass;
%   3. derived-field recomputation: Nc, a0, n, wallSigma;
%   4. uniform initial particle state generation, unless x/v are provided;
%   5. params.kv and in_*.bin writing;
%   6. bash launch script writing.
%
% Example:
%
% prep = prepare_poiseuille_viz_case(struct( ...
%     'workdir', fullfile(pwd,'rbps8_viz'), ...
%     'exePath', fullfile(pwd,'build','main_benchmark_poiseuille_openmp_profiled_shifted_profiled_viz'), ...
%     'nThreads', 4, ...
%     'benchmark_nSteps', 200, ...
%     'visualEnable', true, ...
%     'visualMode', 'field_particles', ...
%     'visualField', 'Ux', ...
%     'visualFieldAutoScale', false, ...
%     'visualFieldMin', -1.0, ...
%     'visualFieldMax', 1.0, ...
%     'visualWindowWidth', 1400, ...
%     'visualWindowHeight', 700));
%
% Runtime-only override fields not written to params.kv:
%   workdir, exePath, prefixIn, prefixOut, seed, nThreads,
%   removeMean, x, v, type, r0

if nargin < 1 || isempty(overrides)
    overrides = struct();
end
assert(isstruct(overrides) && isscalar(overrides), ...
    'overrides must be a scalar struct.');

runtimeFields = { ...
    'workdir','exePath','prefixIn','prefixOut','seed','nThreads', ...
    'removeMean','x','v','type','r0'};

paramsOverrides = overrides;
for k = 1:numel(runtimeFields)
    name = runtimeFields{k};
    if isfield(paramsOverrides, name)
        paramsOverrides = rmfield(paramsOverrides, name);
    end
end

params = default_params();
params = merge_structs(params, paramsOverrides);
params = finalize_params(params, paramsOverrides);

workdir    = getf(overrides, 'workdir', fullfile(pwd, 'rbps8_viz'));
prefixIn   = getf(overrides, 'prefixIn', 'in');
prefixOut  = getf(overrides, 'prefixOut', 'out');
seed       = getf(overrides, 'seed', 1);
nThreads   = getf(overrides, 'nThreads', 8);
removeMean = logical(getf(overrides, 'removeMean', true));
exePath    = getf(overrides, 'exePath', default_exe_path());

if isfield(overrides, 'x') && isfield(overrides, 'v')
    x = overrides.x;
    v = overrides.v;

    if isfield(overrides, 'type')
        type = overrides.type;
    else
        type = zeros(size(x,1), 1, 'uint8');
    end

    if isfield(overrides, 'r0')
        r0 = overrides.r0;
    else
        r0 = x;
    end
else
    [x, v, type, r0] = build_uniform_state(params, seed, removeMean);
end

assert(size(x,1) == params.n, ...
    'State has %d particles but params.n = %d.', size(x,1), params.n);
assert(size(x,2) == 2 && size(v,2) == 2, ...
    'x and v must be n x 2 arrays.');

nInsideInitial = count_inside_obstacle_local(params, x);

if ~exist(workdir, 'dir')
    mkdir(workdir);
end

paramsPath = fullfile(workdir, 'params.kv');
inPrefix   = fullfile(workdir, prefixIn);
outPrefix  = fullfile(workdir, prefixOut);
runScriptPath = fullfile(workdir, 'run_poiseuille_viz_case.sh');

write_params_kv_local(params, paramsPath);
write_state_bin_local(inPrefix, x, v, type, r0);
if exist('nInsideInitial', 'var') ~= 1
    nInsideInitial = count_inside_obstacle_local(params, x);
end
fprintf('initialInside : %d\n', nInsideInitial);
write_run_script(runScriptPath, exePath, paramsPath, inPrefix, outPrefix, nThreads);

prep = struct();
prep.params = params;
prep.workdir = workdir;
prep.exePath = exePath;
prep.paramsPath = paramsPath;
prep.inPrefix = inPrefix;
prep.outPrefix = outPrefix;
prep.runScriptPath = runScriptPath;
prep.runScriptLinux = to_linux(runScriptPath);
prep.nThreads = nThreads;
prep.nInsideInitial = nInsideInitial;
prep.dumpSteps = parse_dump_steps(params.benchmark_dumpSteps);

fprintf('\n=== prepare_poiseuille_viz_case ===\n');
fprintf('workdir      : %s\n', workdir);
fprintf('exePath      : %s\n', exePath);
fprintf('nThreads     : %d\n', nThreads);
fprintf('nParticles   : %d\n', params.n);
fprintf('benchmarkSteps: %d\n', params.benchmark_nSteps);
fprintf('visualEnable : %d\n', logical(params.visualEnable));
fprintf('visualMode   : %s\n', char(string(params.visualMode)));
fprintf('visualField  : %s\n', char(string(params.visualField)));
fprintf('run command  : bash %s\n', prep.runScriptLinux);
fprintf('===================================\n');

end

function params = default_params()
% Complete default set for the final Poiseuille/OpenMP/profiled/shifted code.

params = struct();
params.nThreads=4;

% Domain / grid
params.caseType = 'poiseuille';
params.Nx = 50;
params.Ny = 50;
params.Lx = 10.0;
params.Ly = 10.0;
params.Nc = params.Nx * params.Ny;

% MPCD / SRC
params.gamma = 20.0;
params.n = round(params.gamma * params.Nc);
params.dt = 5e-3;
params.a0 = params.Lx / params.Nx;
params.alphaDeg = 90.0;
params.alpha = deg2rad(params.alphaDeg);
params.kBT = 1.0;
params.g = 0.0;
params.bodyForceX = 0.25;
params.useThermostat = true;
params.keepMeanFlow = false;

% Boundary conditions: Poiseuille benchmark
params.boundary_left = 'periodic';
params.boundary_right = 'periodic';
params.boundary_bottom = 'thermalize';
params.boundary_top = 'thermalize';
params.Utop = 0.0;
params.Ubottom = 0.0;
params.wallSigma = sqrt(max(params.kBT, 0.0));

% Fixed-volume liquid-flow assumptions
params.noSurfaceCase = true;
params.redistributionEnableSurfaceTopology = false;
params.redistributionWallWettingEnabled = false;
params.useInterfaceVelocityReorientation = false;

% Incompressible redistribution by zones
params.useIncompressibleRedistribution = true;
params.redistribAfterCollision = true;
params.useZoneRedistribution = true;
params.zoneTileNx = 25;
params.zoneTileNy = 25;
params.zoneUseShiftedSecondPass = true;
params.zonePassthroughMode = false;
params.zoneSingleFullDomainMode = false;
params.enableMomentumCorrectionPostRedistribution = true;
params.coef = 0.1;
params.highMode = 'coef';
params.lowMode = 'coef';
params.maxRedistribPasses = 2;
params.useLocalFluidFractionThresholds = false;
params.fluidFracGain = 0.8;
params.lowThrFloor = 20.0;
params.highThrFloor = 25.0;
params.lowThrBulkOverride = NaN;

% Liquid closure
params.useLiquidClosure = true;
params.useOptimalBetaRepair = true;
params.betaRepair = 0.0;
params.betaEOS = 1.0;
params.Kvirial = 75.0;
params.smoothPdriveAtInterzone = true;
params.smoothPdriveInterzoneWidthCells = 2;
params.smoothPdriveInterzoneBlend = 1.0;
params.smoothPdriveIncludeShiftedLayouts = true;

% Benchmark runtime parameters read by the main executable
params.benchmark_nSteps = 10000;
params.benchmark_metricsEvery = 500;
params.benchmark_dumpSteps = '0,100,300,600,900,1200,1500,1800,2000';

% Optional real-time visualization
params.visualEnable = true;
params.visualEvery = 1;
params.visualMode = 'field';       % particles | field | field_particles
params.visualField = 'vorticity';                % Ux | Uy | speed | vorticity | N | rho | P

params.visualFieldSmoothingEnable = true;
params.visualFieldSmoothingPasses = 2;
params.visualFieldMinOccupancy = 3;
params.visualFieldTemporalAverageEnable = true;
params.visualFieldTemporalAlpha = 0.95;
params.visualFieldRobustScaleEnable = true;
params.visualFieldRobustScaleLowPercentile = 2.0;
params.visualFieldRobustScaleHighPercentile = 98.0;

params.visualFieldAutoScale = true;
params.visualFieldMin = -1.0;
params.visualFieldMax = 2.5;
params.visualShowParticles = true;
params.visualMaxParticles = 10000;
params.visualPointSize = 5.0;
params.visualParticleColorMode = 'speed';    % type | speed | Ux | Uy
params.visualWindowWidth = 700;
params.visualWindowHeight = 700;


% Optional solid obstacle geometry. Geometry only at this stage;
% particle reflection and solid/fluid masking will be added later.
params.obstacleEnable = true;
params.obstacleType = 'cylinder';
params.obstacleCx = 0.25 * params.Lx;
params.obstacleCy = 0.5 * params.Ly;
params.obstacleRadius = 0.8;
end

function params = finalize_params(params, overrides)
params.Nc = params.Nx * params.Ny;
params.a0 = params.Lx / params.Nx;

if ~isfield(overrides, 'n')
    params.n = round(params.gamma * params.Nc);
end

if ~isfield(overrides, 'wallSigma')
    params.wallSigma = sqrt(max(params.kBT, 0.0));
end

if isfield(params, 'alphaDeg') && ~isfield(overrides, 'alpha')
    params.alpha = deg2rad(params.alphaDeg);
end
end

function [x, v, type, r0] = build_uniform_state(params, seed, removeMean)
if ~isempty(seed)
    rng(seed);
end

n = params.n;
x = zeros(n, 2);

if obstacle_active_local(params)
    % Rejection sampling in rectangle minus cylinder.
    filled = 0;
    batch = max(1000, ceil(1.5 * n));

    while filled < n
        cand = zeros(batch, 2);
        cand(:,1) = params.Lx * rand(batch, 1);
        cand(:,2) = params.Ly * rand(batch, 1);

        keep = ~points_in_obstacle_local(params, cand);
        cand = cand(keep, :);

        nadd = min(size(cand, 1), n - filled);
        if nadd > 0
            x(filled + (1:nadd), :) = cand(1:nadd, :);
            filled = filled + nadd;
        else
            batch = min(10 * n, max(batch + 1000, 2 * batch));
        end
    end
else
    x(:,1) = params.Lx * rand(n, 1);
    x(:,2) = params.Ly * rand(n, 1);
end

sigma = sqrt(max(params.kBT, 0.0));
v = sigma * randn(n, 2);

if logical(removeMean)
    v(:,1) = v(:,1) - mean(v(:,1));
    v(:,2) = v(:,2) - mean(v(:,2));
end

type = zeros(n, 1, 'uint8');
r0 = x;
end

function tf = obstacle_active_local(params)
tf = isfield(params, 'obstacleEnable') && logical(params.obstacleEnable) && ...
     isfield(params, 'obstacleType') && strcmpi(char(string(params.obstacleType)), 'cylinder') && ...
     isfield(params, 'obstacleRadius') && params.obstacleRadius > 0;
end

function inside = points_in_obstacle_local(params, x)
if ~obstacle_active_local(params)
    inside = false(size(x,1), 1);
    return;
end

dx = x(:,1) - params.obstacleCx;
dy = x(:,2) - params.obstacleCy;
inside = (dx .* dx + dy .* dy) <= params.obstacleRadius^2;
end

function nInside = count_inside_obstacle_local(params, x)
nInside = nnz(points_in_obstacle_local(params, x));
end

function write_params_kv_local(params, filepath)
fn = fieldnames(params);
fid = fopen(filepath, 'w');
assert(fid >= 0, 'Cannot open %s for writing.', filepath);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>

for k = 1:numel(fn)
    key = fn{k};
    val = params.(key);

    if islogical(val)
        assert(isscalar(val), 'Logical field %s must be scalar.', key);
        sval = string(val);
    elseif isnumeric(val)
        assert(isscalar(val), 'Numeric field %s must be scalar.', key);
        sval = sprintf('%.17g', val);
    elseif isstring(val) || ischar(val)
        sval = string(val);
    else
        error('Unsupported params field type for %s.', key);
    end

    fprintf(fid, '%s=%s\n', key, char(sval));
end
end

function write_state_bin_local(prefix, x, v, type, r0)
n = size(x, 1);
assert(size(x,2) == 2 && size(v,1) == n && size(v,2) == 2, ...
    'x and v must be n x 2 arrays.');

if nargin < 4 || isempty(type)
    type = zeros(n, 1, 'uint8');
end
if nargin < 5 || isempty(r0)
    r0 = x;
end

write_f64_matrix([prefix '_x.bin'], x);
write_f64_matrix([prefix '_v.bin'], v);
write_u8_vector([prefix '_type.bin'], type);
write_f64_matrix([prefix '_r0.bin'], r0);
end

function write_f64_matrix(filepath, A)
fid = fopen(filepath, 'w');
assert(fid >= 0, 'Cannot open %s for writing.', filepath);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
B = reshape(A.', [], 1);
fwrite(fid, B, 'double');
end

function write_u8_vector(filepath, a)
fid = fopen(filepath, 'w');
assert(fid >= 0, 'Cannot open %s for writing.', filepath);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, uint8(a(:)), 'uint8');
end

function write_run_script(runScriptPath, exePath, paramsPath, inPrefix, outPrefix, nThreads)
paramsLinux = to_linux(paramsPath);
inPrefixLinux = to_linux(inPrefix);
outPrefixLinux = to_linux(outPrefix);
exeLinux = to_linux(exePath);

fid = fopen(runScriptPath, 'w');
assert(fid >= 0, 'Cannot open %s for writing.', runScriptPath);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, '#!/usr/bin/env bash\n');
fprintf(fid, 'set -euo pipefail\n');
fprintf(fid, 'export OMP_NUM_THREADS=%d\n', nThreads);
fprintf(fid, 'chmod +x "%s"\n', exeLinux);
fprintf(fid, '"%s" \\\n', exeLinux);
fprintf(fid, ' "%s" \\\n', paramsLinux);
fprintf(fid, ' "%s_x.bin" \\\n', inPrefixLinux);
fprintf(fid, ' "%s_v.bin" \\\n', inPrefixLinux);
fprintf(fid, ' "%s_type.bin" \\\n', inPrefixLinux);
fprintf(fid, ' "%s_r0.bin" \\\n', inPrefixLinux);
fprintf(fid, ' "%s" \\\n', outPrefixLinux);
fprintf(fid, ' 1 \\\n');
fprintf(fid, ' 1 \\\n');
fprintf(fid, ' %d\n', nThreads);
end

function s = to_linux(p)
s = char(string(p));

% Normalise les séparateurs.
s = strrep(s, '\', '/');

% Cas déjà Linux, éventuellement transformé par MATLAB en /home/...
if startsWith(s, '/home/') || startsWith(s, '/mnt/') || startsWith(s, '/tmp/')
    return;
end

sl = lower(s);

% Cas UNC WSL :
% //wsl.localhost/Ubuntu/home/user/... -> /home/user/...
prefixes = { ...
    '//wsl.localhost/ubuntu/', ...
    '/wsl.localhost/ubuntu/', ...
    '//wsl$/ubuntu/', ...
    '/wsl$/ubuntu/'};

for k = 1:numel(prefixes)
    pref = prefixes{k};
    if startsWith(sl, pref)
        s = ['/' s(numel(pref)+1:end)];
        return;
    end
end

% Cas lecteur Windows :
% C:/Users/... -> /mnt/c/Users/...
if numel(s) >= 3 && s(2) == ':' && s(3) == '/'
    drive = lower(s(1));
    rest = s(4:end);
    s = ['/mnt/' drive '/' rest];
    return;
end

error('Chemin non convertible vers Linux: %s', s);
end

function v = getf(s, name, def)
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = def;
end
end

function s = merge_structs(a, b)
s = a;
fn = fieldnames(b);
for k = 1:numel(fn)
    s.(fn{k}) = b.(fn{k});
end
end

function steps = parse_dump_steps(s)
if isnumeric(s)
    steps = unique(s(:).');
    return;
end
if isstring(s)
    s = char(s);
end
parts = regexp(s, ',', 'split');
steps = zeros(1, numel(parts));
for k = 1:numel(parts)
    steps(k) = str2double(strtrim(parts{k}));
end
steps = unique(steps(~isnan(steps)));
end

function exePath = default_exe_path()
exePath = fullfile(pwd, 'build', 'main_benchmark_poiseuille_openmp_profiled_shifted_profiled');
end

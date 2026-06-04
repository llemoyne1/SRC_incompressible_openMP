function state = generate_taylor_green_resampling_state_0126(varargin)
%GENERATE_TAYLOR_GREEN_RESAMPLING_STATE_0126 Generate a V2 Taylor--Green state.
%
% This is the periodic initial condition used by the OpenMP resampling TG
% validator.  All particles are true Fluid particles, with role=1, so the
% run starts from a clean periodic bulk state and any later Inactive slots are
% created by the resampling extractor itself.
%
% Example:
%   addpath('matlab');
%   generate_taylor_green_resampling_state_0126('output', ...
%       'runs/taylor_green_resampling_0126/initial_state_tg_0126.smpcd');

p = inputParser;
p.FunctionName = 'generate_taylor_green_resampling_state_0126';
addParameter(p, 'output', fullfile('runs','taylor_green_resampling_0126','initial_state_tg_0126.smpcd'), @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 32, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'Ny', 32, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'flowAmplitude', 0.08, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'kxMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'kyMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
addParameter(p, 'kBT', 0.001, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'seed', 1260126, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'positionMode', 'uniform_per_cell', @(s) ischar(s) || isstring(s));
parse(p, varargin{:});
opt = p.Results;

state = generate_smpcd_state_taylor_green( ...
    'output', '', ...
    'Lx', opt.Lx, 'Ly', opt.Ly, ...
    'Nx', opt.Nx, 'Ny', opt.Ny, ...
    'gamma', opt.gamma, ...
    'flowAmplitude', opt.flowAmplitude, ...
    'kxMode', opt.kxMode, 'kyMode', opt.kyMode, ...
    'kBT', opt.kBT, ...
    'mass', opt.mass, ...
    'type', uint32(0), ...
    'seed', opt.seed, ...
    'positionMode', char(opt.positionMode), ...
    'removeMeanMomentum', true);

n = numel(state.x);
state.role = ones(n, 1, 'uint8'); % Fluid
state.metadata.generator = 'generate_taylor_green_resampling_state_0126';
state.metadata.version = 2;

output = char(opt.output);
if ~isempty(output)
    outDir = fileparts(output);
    if ~isempty(outDir) && ~isfolder(outDir)
        mkdir(outDir);
    end
    write_smpcd_state(output, state);
end

fprintf('Generated Taylor--Green resampling V2 state:\n');
fprintf('  output     : %s\n', output);
fprintf('  grid       : %d x %d\n', opt.Nx, opt.Ny);
fprintf('  gamma      : %d\n', opt.gamma);
fprintf('  particles  : %d\n', n);
fprintf('  U0/kBT     : %.12g / %.12g\n', opt.flowAmplitude, opt.kBT);
fprintf('  roles      : Fluid=%d Latent=0 Inactive=0\n', n);
end

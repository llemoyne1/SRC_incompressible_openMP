function state = generate_taylor_green_high_snr_short_state(varargin)
%GENERATE_TAYLOR_GREEN_HIGH_SNR_SHORT_STATE Generate the high-SNR TG state.
%
%   state = generate_taylor_green_high_snr_short_state()
%
%   This is a convenience wrapper around generate_smpcd_state_taylor_green.
%   It generates the initial state used by:
%
%     examples/params_taylor_green_high_snr_classic_64x64_g80_short.kv
%     examples/params_taylor_green_high_snr_q6_64x64_g80_short.kv
%
%   Optional name/value pairs override the defaults below.

p = inputParser;
p.FunctionName = 'generate_taylor_green_high_snr_short_state';
addParameter(p, 'output', 'initial_state_tg_64x64_g80_u0p08_kbt0p01.smpcd', @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 64, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'Ny', 64, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'gamma', 80, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'flowAmplitude', 0.08, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'kxMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'kyMode', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'kBT', 0.01, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'type', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'seed', 12345, @(x) isnumeric(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;

state = generate_smpcd_state_taylor_green( ...
    'output', opt.output, ...
    'Lx', opt.Lx, ...
    'Ly', opt.Ly, ...
    'Nx', opt.Nx, ...
    'Ny', opt.Ny, ...
    'gamma', opt.gamma, ...
    'flowAmplitude', opt.flowAmplitude, ...
    'kxMode', opt.kxMode, ...
    'kyMode', opt.kyMode, ...
    'kBT', opt.kBT, ...
    'mass', opt.mass, ...
    'type', opt.type, ...
    'seed', opt.seed);

fprintf('\nGenerated high-SNR Taylor--Green state:\n');
fprintf('  output        : %s\n', char(string(opt.output)));
fprintf('  grid          : %d x %d\n', opt.Nx, opt.Ny);
fprintf('  gamma         : %g\n', opt.gamma);
fprintf('  particles     : %g\n', opt.Nx * opt.Ny * opt.gamma);
fprintf('  flowAmplitude : %.6g\n', opt.flowAmplitude);
fprintf('  kBT           : %.6g\n', opt.kBT);
fprintf('  seed          : %g\n\n', opt.seed);
end

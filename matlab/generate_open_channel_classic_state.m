function state = generate_open_channel_classic_state(varargin)
%GENERATE_OPEN_CHANNEL_CLASSIC_STATE Initial state for 0061 inlet/outlet smoke tests.
%
% Example from repository root:
%   cd matlab
%   generate_open_channel_classic_state('output','../initial_state_open_channel_64x32_g20_kbt0p01.smpcd');
%   cd ..

    p = inputParser;
    p.FunctionName = 'generate_open_channel_classic_state';
    p.addParameter('output', '../initial_state_open_channel_64x32_g20_kbt0p01.smpcd', @(s) ischar(s) || isstring(s));
    p.addParameter('Lx', 2.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('Nx', 64, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    p.addParameter('Ny', 32, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    p.addParameter('gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    p.addParameter('kBT', 0.01, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    p.addParameter('inletUx', 0.05, @(x) isnumeric(x) && isscalar(x));
    p.addParameter('seed', 12345, @(x) isnumeric(x) && isscalar(x));
    p.parse(varargin{:});
    opt = p.Results;

    state = generate_smpcd_state_uniform( ...
        'output', '', ...
        'Lx', opt.Lx, 'Ly', opt.Ly, ...
        'Nx', opt.Nx, 'Ny', opt.Ny, ...
        'gamma', opt.gamma, ...
        'kBT', opt.kBT, ...
        'seed', opt.seed, ...
        'mode', 'uniform_per_cell', ...
        'velocityMode', 'maxwell', ...
        'removeMeanMomentum', true);

    state.vx = state.vx + opt.inletUx;
    write_smpcd_state(char(opt.output), state);
    fprintf('[generate_open_channel_classic_state] wrote %s with Np=%d, meanUx=%g\n', ...
        char(opt.output), numel(state.x), mean(state.vx));
end

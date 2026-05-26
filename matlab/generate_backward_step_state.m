function state = generate_backward_step_state(varargin)
%GENERATE_BACKWARD_STEP_STATE Generate a uniform state excluding a rectangular bottom step.
%
% The C++ first backward-step smoke case represents the solid as an
% immersedSolidShape=rectangle block attached to the bottom wall. This helper
% keeps the initial real particles outside the block.
%
% Example from repository root:
%   cd matlab
%   generate_backward_step_state('output','../initial_state_backward_step_96x48_g20.smpcd');

    p = inputParser;
    addParameter(p, 'output', '../initial_state_backward_step_96x48_g20.smpcd', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Lx', 2.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'Nx', 96, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'Ny', 48, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'kBT', 0.01, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'type', uint32(0), @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'seed', 12345, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'xMin', 0.25, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'xMax', 0.65, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'yMin', 0.0, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'yMax', 0.50, @(x) isnumeric(x) && isscalar(x));
    parse(p, varargin{:});
    opt = p.Results;

    state = generate_smpcd_state_uniform( ...
        'output', char(opt.output), ...
        'Lx', opt.Lx, 'Ly', opt.Ly, 'Nx', opt.Nx, 'Ny', opt.Ny, ...
        'gamma', opt.gamma, 'kBT', opt.kBT, 'mass', opt.mass, 'type', opt.type, ...
        'seed', opt.seed, ...
        'excludeRectangle', true, ...
        'rectangleXMin', opt.xMin, 'rectangleXMax', opt.xMax, ...
        'rectangleYMin', opt.yMin, 'rectangleYMax', opt.yMax);

    fprintf('[generate_backward_step_state] wrote %s with Np=%d, rectangle=[%g,%g]x[%g,%g]\n', ...
        char(opt.output), numel(state.x), opt.xMin, opt.xMax, opt.yMin, opt.yMax);
end

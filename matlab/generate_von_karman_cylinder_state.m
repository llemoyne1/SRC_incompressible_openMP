function state = generate_von_karman_cylinder_state(varargin)
%GENERATE_VON_KARMAN_CYLINDER_STATE Uniform initial state excluding a fixed circle.
%
% This helper intentionally mirrors the geometry used by the CUDA VK test at
% reduced CPU/OpenMP resolution.  It does not implement inlet/outlet injection;
% the OpenMP overnight comparison uses a periodic box with an imposed global
% mean flow around a fixed immersed circle.

p = inputParser;
p.FunctionName = 'generate_von_karman_cylinder_state';
addParameter(p, 'output', '../initial_state_von_karman_320x64_g20.smpcd', @(s) ischar(s) || isstring(s));
addParameter(p, 'Lx', 2.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Ly', 0.4, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Nx', 320, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'Ny', 64, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'kBT', 0.0025, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'seed', 12345, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'circleCx', 0.35, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'circleCy', 0.20, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'circleR', 0.04, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p,'Ux', 9., @(x) isnumeric(x) && isscalar(x));
addParameter(p,'Uy', 0., @(x) isnumeric(x) && isscalar(x));

parse(p, varargin{:});
opt = p.Results;

state = generate_smpcd_state_uniform('output', char(opt.output), ...
    'Lx', opt.Lx, 'Ly', opt.Ly, 'Nx', opt.Nx, 'Ny', opt.Ny, ...
    'gamma', opt.gamma, 'kBT', opt.kBT, 'mass', opt.mass, ...
    'type', 0, 'seed', opt.seed, ...
    'mode', 'uniform_per_cell', 'velocityMode', 'maxwell', ...
    'removeMeanMomentum', true, ...
    'excludeCircle', true, 'circleCx', opt.circleCx, ...
    'circleCy', opt.circleCy, 'circleR', opt.circleR,'Ux',opt.Ux,'Uy',opt.Uy);

fprintf('[generate_von_karman_cylinder_state] wrote %s\n', char(opt.output));
fprintf('  geometry: L=(%.6g, %.6g), grid=%dx%d, gamma=%.6g, circle=(%.6g, %.6g), R=%.6g\n', ...
    opt.Lx, opt.Ly, opt.Nx, opt.Ny, opt.gamma, opt.circleCx, opt.circleCy, opt.circleR);
end

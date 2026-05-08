function out = run_tranche1_step01_example(params, varargin)
%RUN_TRANCHE1_STEP01_EXAMPLE
% Exemple complet : construit un etat initial ad hoc puis lance la tranche 1.
%
% Usage:
%   out = run_tranche1_step01_example(params)
%   out = run_tranche1_step01_example(params,'seed',1,'workdir','run_step01_example')

p = inputParser;
p.addParameter('seed', 1, @(z) isscalar(z));
p.addParameter('workdir', fullfile(pwd,'run_step01_example'), @(s) ischar(s) || isstring(s));
p.addParameter('exePath', '/mnt/data/tranche1_cpp/build/main_step01_stream_bc_collision', @(s) ischar(s) || isstring(s));
p.addParameter('compareAfter', true, @(z) islogical(z) || isnumeric(z));
p.parse(varargin{:});
opt = p.Results;

[x, v, type, r0] = build_ad_hoc_state_uniform(params, 'seed', opt.seed, 'removeMean', true);

out = run_tranche1_step01(params, x, v, ...
    'type', type, ...
    'r0', r0, ...
    'exePath', char(opt.exePath), ...
    'workdir', char(opt.workdir), ...
    'compareAfter', logical(opt.compareAfter));
end

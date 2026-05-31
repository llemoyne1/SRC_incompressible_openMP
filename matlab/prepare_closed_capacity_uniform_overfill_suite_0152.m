function metaAll = prepare_closed_capacity_uniform_overfill_suite_0152(varargin)
%PREPARE_CLOSED_CAPACITY_UNIFORM_OVERFILL_SUITE_0152 Generate static overfill states.
%
% This is a convenience wrapper around
% prepare_closed_capacity_uniform_overfill_0152 for the wall-load validation
% suite.  It creates one uniformly overfilled state per mass factor.

    p = inputParser;
    p.FunctionName = 'prepare_closed_capacity_uniform_overfill_suite_0152';
    addParameter(p, 'outputDir', '../init/closed_capacity_wall_load_0152', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Lx', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'Nx', 48, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
    addParameter(p, 'Ny', 48, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
    addParameter(p, 'gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
    addParameter(p, 'massFactors', [1.00 1.02 1.05 1.10], @(x) isnumeric(x) && isvector(x) && all(x > 0));
    addParameter(p, 'capacityMultiplier', 1.10, @(x) isnumeric(x) && isscalar(x) && x >= 1.0);
    addParameter(p, 'kBT', 0.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'seed', 1520000, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'makePreview', true, @(x) islogical(x) || isnumeric(x));
    parse(p, varargin{:});
    opt = p.Results;

    outDir = char(opt.outputDir);
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    factors = double(opt.massFactors(:)');
    metaCells = cell(numel(factors), 1);

    for k = 1:numel(factors)
        f = factors(k);
        tag = local_factor_tag(f);
        output = fullfile(outDir, sprintf('static_mf%s.smpcd', tag));
        metaCells{k} = prepare_closed_capacity_uniform_overfill_0152( ...
            'output', output, ...
            'Lx', opt.Lx, 'Ly', opt.Ly, ...
            'Nx', opt.Nx, 'Ny', opt.Ny, ...
            'gamma', opt.gamma, ...
            'massFactor', f, ...
            'capacityMultiplier', opt.capacityMultiplier, ...
            'kBT', opt.kBT, ...
            'velocityMode', 'zero', ...
            'seed', double(opt.seed) + k, ...
            'makePreview', logical(opt.makePreview));
    end

    metaAll = vertcat(metaCells{:});
    summaryPath = fullfile(outDir, 'closed_capacity_uniform_overfill_suite_0152.csv');
    writetable(metaAll, summaryPath);
    fprintf('[0152 prepare suite] wrote %d states under %s\n', numel(factors), outDir);
    fprintf('[0152 prepare suite] summary: %s\n', summaryPath);
end

function tag = local_factor_tag(f)
    tag = sprintf('%.6g', f);
    tag = strrep(tag, '.', 'p');
    tag = strrep(tag, '-', 'm');
end
